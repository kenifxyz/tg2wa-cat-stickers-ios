# Maomijiang Cat Stickers — iOS app build notes

Built from WhatsApp's official iOS sample (`WhatsApp/stickers` → `iOS/WAStickersThirdParty`).

## Packs (4)
Source: 70 WhatsApp-spec WEBPs converted from Telegram pack `maomijiang_by_fStikBot`
(65 animated, 5 static; all 512×512; animated ≤500KB, static ≤100KB). Tray = 96×96 PNG, 18.4KB.

- `maomijiang_anim_1`  — Maomijiang Cats 1        — animated — 30 stickers
- `maomijiang_anim_2`  — Maomijiang Cats 2        — animated — 30 stickers
- `maomijiang_anim_3`  — Maomijiang Cats 3        — animated —  5 stickers
- `maomijiang_static`  — Maomijiang Cats Static   — static   —  5 stickers

Publisher: `Kenneth (via tg2wa)`. Shared tray `tray_maomijiang.png`. Per-sticker emoji from
the converter manifest (default `["🐱"]`). Pack metadata is in
`WAStickersThirdParty/sticker_packs.wasticker`. Sticker files are `mm_NNN.webp` (flat in the
`WAStickersThirdParty/` group, loaded by filename from `Bundle.main`).

## Project config
- Bundle id: `com.durianbit.maomijiangstickers`
- Scheme / target: `WAStickersThirdParty`
- Team: `55JNCECNTX` (durianbit)
- Deployment target: iOS 13.0

## Xcode 26 fixes applied
1. `IPHONEOS_DEPLOYMENT_TARGET` 8.0 → 13.0 — libarclite was removed; 8.0 fails to link.
2. `EXCLUDED_ARCHS[sdk=iphonesimulator*] = arm64` — the bundled `WebP.framework` is a fat
   static archive with **device arm64 + x86_64-sim** slices but **no arm64-simulator** slice.
   On Apple Silicon the default arm64 simulator build can't link it. Excluding arm64 for the
   simulator SDK only forces an x86_64 simulator build (runs under Rosetta). Device (arm64)
   builds are unaffected — the device arm64 slice is present, so archiving for TestFlight is fine.

## Verify (simulator build)
```
xcodebuild -project WAStickersThirdParty.xcodeproj -scheme WAStickersThirdParty \
  -sdk iphonesimulator -configuration Debug -derivedDataPath build build CODE_SIGNING_ALLOWED=NO
```
→ **BUILD SUCCEEDED**. Resulting `.app` bundles all 70 webps + tray + `sticker_packs.wasticker`.

## To ship to an iPhone (follow-up, NOT done here)
1. App Store Connect: create app record with bundle id `com.durianbit.maomijiangstickers`,
   add keyword `WAStickers` (so WhatsApp can surface it).
2. Replace the placeholder app icon (still the sample "Cuppy" icon in
   `Assets.xcassets/AppIcon.appiconset`) before submission.
3. Apple review note: per WhatsApp's README, a pure sticker-export app is usually rejected —
   add some real functionality / unique UI before App Store submission. (TestFlight internal
   testing is fine as-is.)
4. Archive for device (real signing, no EXCLUDED_ARCHS needed for device):
   ```
   xcodebuild -project WAStickersThirdParty.xcodeproj -scheme WAStickersThirdParty \
     -sdk iphoneos -configuration Release -archivePath build/WAStickers.xcarchive archive \
     DEVELOPMENT_TEAM=55JNCECNTX
   ```
5. Export + upload via durianbit ASC API key
   (issuer `ca417faa-98a3-4868-97ae-b7163dd7dd06`, key `Y565C23GG4`,
   `~/.appstoreconnect/private_keys/AuthKey_Y565C23GG4.p8`), e.g. fastlane `pilot`/`deliver`
   or `xcrun altool`/`notarytool`-style upload with the API key.
6. Install via TestFlight on the iPhone, open the app, tap each pack's "Add to WhatsApp".
