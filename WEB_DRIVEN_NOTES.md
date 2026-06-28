# Web-driven sticker app — how it works & how to add packs

## What changed (vs the bundled static build)
The app no longer bundles any sticker assets. On launch it:
1. `GET`s `packs/index.json` from the raw-GitHub host (network-first, on-disk
   cache fallback when offline).
2. Downloads each referenced tray + sticker `.webp` into the app's Caches dir
   (`URLSession`, keyed by filename; a present file is trusted, not re-fetched).
3. Builds `StickerPack`/`Sticker` objects from the downloaded **bytes** using the
   WhatsApp sample's existing data-based initializers
   (`StickerPack(...trayImagePNGData:)`, `addSticker(imageData:type:emojis:)`).
4. Each pack's "Add to WhatsApp" button runs the unchanged handoff:
   `StickerPack.sendToWhatsApp` → JSON (incl. base64 webp bytes) onto
   `UIPasteboard` type `net.whatsapp.external.sticker-pack` → opens
   `whatsapp://stickerPack`. The pasteboard payload carries the real webp bytes
   regardless of whether they came from the bundle or a download.

Touched Swift files: **`RemoteStickerLoader.swift`** (new, the whole data layer)
and **`AllStickerPacksViewController.swift`** (load via the remote loader +
retry-on-error; removed the sample "don't ship this" nag). Everything else is
the stock WhatsApp sample.

## Host
- Base URL: `https://raw.githubusercontent.com/kenifxyz/tg2wa-cat-stickers-ios/main/packs/`
- Contract file: `packs/index.json` (schema below). Repo must be **public** for
  raw URLs to resolve (it is).
- raw.githubusercontent caches ~5 min, so a freshly-pushed change appears within
  a few minutes.

## index.json schema (the app↔host contract)
```json
{
  "format_version": 1,
  "ios_app_store_link": "",
  "android_play_store_link": "",
  "packs": [
    {
      "identifier": "maomijiang_anim_1",   // unique, stable, <=128 chars
      "name": "Maomijiang Cats 1",
      "publisher": "Kenneth",
      "animated": true,                     // true = all stickers animated; false = all static
      "tray_image_file": "tray_maomijiang.png",  // 96x96 png <=50KB, filename under packs/
      "publisher_website": "",
      "privacy_policy_website": "",
      "license_agreement_website": "",
      "stickers": [
        { "image_file": "anim1_00.webp", "emojis": ["🐱"] }
        // 3..30 per pack; never mix animated + static in one pack
      ]
    }
  ]
}
```

## To add ANY future pack (NO app re-ship)
1. Put the new `.webp` files (512×512; animated ≤500KB, static ≤100KB) and a
   96×96 ≤50KB tray png into `packs/`. Use clear filenames (e.g. `dogs1_00.webp`).
2. Add a pack object to `packs/index.json` (new unique `identifier`, the tray
   filename, `animated` flag, and the sticker list with emojis). Respect the
   WhatsApp rules: 3–30 stickers per pack, no mixing animated + static.
3. `git add packs/ && git commit && git push origin main`.
4. Wait a few minutes for raw-GitHub cache, then it shows up in the app on next
   launch (the app re-fetches index.json every launch). No new TestFlight build.

## Ship pipeline used (for reference)
- Archive (device, no EXCLUDED_ARCHS): `xcodebuild ... -sdk iphoneos archive`
  with `-allowProvisioningUpdates` + the durianbit ASC API key.
- Bundle ID `com.durianbit.maomijiangstickers` registered via ASC API.
- App Store provisioning profile created via ASC API (bound to the keychain
  "Apple Distribution: durianbit" cert) → manual-signing export → `.ipa`.
- Upload: `xcrun altool --upload-app --apiKey Y565C23GG4 --apiIssuer <issuer>`.
- One manual step: the ASC **app record** must be created via `fastlane produce`
  (Apple's API blocks `POST /v1/apps` for all key roles), which needs a one-time
  Apple ID 2FA code. `/tmp/finish_testflight.sh` does record-create + upload once
  the 2FA code is entered.
