//
//  RemoteStickerLoader.swift
//  WAStickersThirdParty
//
//  Web-driven loader: pulls the pack catalogue + sticker bytes from a hosted
//  index at runtime instead of from the app bundle. Adding a new pack means
//  dropping files on the host and updating index.json — no app re-ship.
//
//  Contract (index.json — see packs/index.json in the repo):
//  {
//    "format_version": 1,
//    "ios_app_store_link": "",
//    "android_play_store_link": "",
//    "packs": [
//      {
//        "identifier": "maomijiang_anim_1",
//        "name": "Maomijiang Cats 1",
//        "publisher": "Kenneth",
//        "animated": true,
//        "tray_image_file": "tray_maomijiang.png",
//        "publisher_website": "",
//        "privacy_policy_website": "",
//        "license_agreement_website": "",
//        "stickers": [ { "image_file": "anim1_00.webp", "emojis": ["🐱"] }, ... ]
//      }
//    ]
//  }
//
//  The downloaded webp bytes are handed to the existing data-based
//  StickerPack / addSticker initializers, so the UIPasteboard payload built by
//  StickerPack.sendToWhatsApp carries the real webp bytes — identical to the
//  bundled path.
//

import UIKit

// MARK: - Host configuration

enum RemoteConfig {
    /// Raw GitHub host. New/changed packs appear by editing files under packs/.
    static let baseURL = "https://raw.githubusercontent.com/kenifxyz/tg2wa-cat-stickers-ios/main/packs/"
    static let indexFile = "index.json"
}

// MARK: - Index schema (Codable)

struct RemoteStickerEntry: Codable {
    let image_file: String
    let emojis: [String]?
    let accessibility_text: String?
}

struct RemotePack: Codable {
    let identifier: String
    let name: String
    let publisher: String
    let animated: Bool
    let tray_image_file: String
    let publisher_website: String?
    let privacy_policy_website: String?
    let license_agreement_website: String?
    let stickers: [RemoteStickerEntry]
}

struct PackIndex: Codable {
    let format_version: Int?
    let ios_app_store_link: String?
    let android_play_store_link: String?
    let packs: [RemotePack]
}

enum RemoteLoaderError: LocalizedError {
    case badURL
    case indexUnavailable
    case noPacksBuilt

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid host URL."
        case .indexUnavailable: return "Could not reach the pack host and no cached copy is available."
        case .noPacksBuilt: return "No sticker packs could be assembled (offline with empty cache?)."
        }
    }
}

// MARK: - Loader

final class RemoteStickerLoader {

    static let shared = RemoteStickerLoader()

    private let session: URLSession
    private let cacheDir: URL
    private let fileManager = FileManager.default

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        session = URLSession(configuration: config)

        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDir = caches.appendingPathComponent("packs", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    private var indexCacheURL: URL { cacheDir.appendingPathComponent("index.json") }

    private func assetURL(for filename: String) -> URL {
        cacheDir.appendingPathComponent(filename)
    }

    /// Entry point. Fetches the index (network first, cache fallback), downloads
    /// any missing assets, builds StickerPack objects, returns on the main queue.
    func loadPacks(completion: @escaping (Result<[StickerPack], Error>) -> Void) {
        fetchIndex { [weak self] indexResult in
            guard let self = self else { return }
            switch indexResult {
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            case .success(let index):
                self.downloadMissingAssets(for: index) {
                    self.buildPacks(from: index, completion: completion)
                }
            }
        }
    }

    // MARK: Index

    private func fetchIndex(completion: @escaping (Result<PackIndex, Error>) -> Void) {
        guard let url = URL(string: RemoteConfig.baseURL + RemoteConfig.indexFile) else {
            completion(.failure(RemoteLoaderError.badURL)); return
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData   // always look for new packs

        let task = session.dataTask(with: request) { [weak self] data, response, _ in
            guard let self = self else { return }
            if let data = data,
               let http = response as? HTTPURLResponse, http.statusCode == 200,
               let index = try? JSONDecoder().decode(PackIndex.self, from: data) {
                try? data.write(to: self.indexCacheURL)   // cache for offline launch
                completion(.success(index))
                return
            }
            // Offline / non-200 → fall back to last cached index.
            if let cached = try? Data(contentsOf: self.indexCacheURL),
               let index = try? JSONDecoder().decode(PackIndex.self, from: cached) {
                completion(.success(index))
            } else {
                completion(.failure(RemoteLoaderError.indexUnavailable))
            }
        }
        task.resume()
    }

    // MARK: Assets

    /// Downloads any referenced tray/sticker file not already cached. Assets are
    /// immutable-by-name (a new pack uses new filenames), so a present file is
    /// trusted and not re-fetched.
    private func downloadMissingAssets(for index: PackIndex, completion: @escaping () -> Void) {
        var files = Set<String>()
        for pack in index.packs {
            files.insert(pack.tray_image_file)
            for sticker in pack.stickers { files.insert(sticker.image_file) }
        }

        let group = DispatchGroup()
        for file in files {
            let dest = assetURL(for: file)
            if fileManager.fileExists(atPath: dest.path) { continue }
            guard let url = URL(string: RemoteConfig.baseURL + file) else { continue }

            group.enter()
            let task = session.downloadTask(with: url) { [weak self] tmpURL, response, _ in
                defer { group.leave() }
                guard let self = self,
                      let tmpURL = tmpURL,
                      let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
                try? self.fileManager.removeItem(at: dest)
                try? self.fileManager.moveItem(at: tmpURL, to: dest)
            }
            task.resume()
        }
        group.notify(queue: .global()) { completion() }
    }

    // MARK: Build

    private func buildPacks(from index: PackIndex, completion: @escaping (Result<[StickerPack], Error>) -> Void) {
        StickerPackManager.queue.async {
            let iosLink = index.ios_app_store_link
            let androidLink = index.android_play_store_link
            Interoperability.iOSAppStoreLink = (iosLink?.isEmpty == false) ? iosLink : nil
            Interoperability.AndroidStoreLink = (androidLink?.isEmpty == false) ? androidLink : nil

            var result: [StickerPack] = []

            for remote in index.packs {
                guard let trayData = try? Data(contentsOf: self.assetURL(for: remote.tray_image_file)) else {
                    print("[RemoteStickerLoader] missing tray for \(remote.identifier), skipping pack")
                    continue
                }
                do {
                    let pack = try StickerPack(
                        identifier: remote.identifier,
                        name: remote.name,
                        publisher: remote.publisher,
                        trayImagePNGData: trayData,
                        publisherWebsite: remote.publisher_website,
                        privacyPolicyWebsite: remote.privacy_policy_website,
                        licenseAgreementWebsite: remote.license_agreement_website
                    )
                    // The data-based init defaults animated=false; honour the index.
                    pack.animated = remote.animated

                    for entry in remote.stickers {
                        guard let webpData = try? Data(contentsOf: self.assetURL(for: entry.image_file)) else {
                            print("[RemoteStickerLoader] missing sticker \(entry.image_file), skipping")
                            continue
                        }
                        try pack.addSticker(
                            imageData: webpData,
                            type: .webp,
                            emojis: entry.emojis,
                            accessibilityText: entry.accessibility_text
                        )
                    }

                    if pack.stickers.count >= Limits.MinStickersPerPack {
                        result.append(pack)
                    } else {
                        print("[RemoteStickerLoader] \(remote.identifier) has too few stickers (\(pack.stickers.count)), skipping")
                    }
                } catch {
                    print("[RemoteStickerLoader] failed to build \(remote.identifier): \(error)")
                    continue
                }
            }

            DispatchQueue.main.async {
                if result.isEmpty {
                    completion(.failure(RemoteLoaderError.noPacksBuilt))
                } else {
                    completion(.success(result))
                }
            }
        }
    }
}
