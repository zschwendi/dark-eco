# Dark Eco for Apple Silicon Mac

The [**2.0 / Build 270.1 preview**](https://github.com/zschwendi/dark-eco/releases/tag/macos-build270.1-preview) is a native **arm64 macOS app** for
**Apple Silicon Macs running macOS 26.5 or later**. This target includes
**Jak and Daxter: The Precursor Legacy only**. Jak II is not supported by this
Mac package, even though it is included in the separate iPhone/iPad preview.

The package is built from [app source `cefd732`](https://github.com/zschwendi/dark-eco/commit/cefd732138849ff1f582be931e58bd06ef2a327c)
and [engine source `a49443d`](https://github.com/zschwendi/jak-pad/commit/a49443d9646d12b305ca4aec4d4c44ae34267d7f),
with freshly generated Jak 1 AOT code. It contains the runtime and reconstructed
OpenGOAL source objects; you must supply your own retail game data.
The [provenance receipt](IPA-MACOS270-PROVENANCE.json) records the build and
validation limits.

## Install the native app

1. Download `DarkEco-macOS-arm64-2.0-build270.1-preview.zip` and `SHA256SUMS`
   from the [Mac release](https://github.com/zschwendi/dark-eco/releases/tag/macos-build270.1-preview). Choose the
   native Mac archive, not an iOS/visionOS IPA or GitHub's source-code ZIP.
2. Extract the ZIP and move **Dark Eco.app** to Applications. Back up existing
   saves before replacing an older app; keep the old app until you have checked
   the preview. Installing this native app does not require Xcode or an IPA
   sideloader.
3. Open **Dark Eco**. The preview has an ad-hoc signature and is **not
   notarized**. If macOS blocks it because the developer cannot be verified,
   and you trust the downloaded release, open **System Settings → Privacy &
   Security → Open Anyway**, then confirm. Follow
   [Apple's instructions](https://support.apple.com/en-us/102445) for the exact
   prompt. There is no need to disable Gatekeeper globally or install a
   borrowed signing certificate.

## Add your game data

Use your own **SCUS-97124 NTSC v1 Black Label** Jak and Daxter disc image.
The importer accepts an ISO, a ZIP/7z containing one supported ISO, or a
prepared folder with the expected `iso/` and `fr3/` data. Download cloud files
completely before importing and allow room for the input plus prepared data.

Open **Dark Eco → Library → Jak and Daxter → Set Up Game Data → Continue →
Choose game data…** and select your input. Keep Dark Eco open until preparation
and validation finish. Start with a gamepad and the ordinary game window.
Game code is compiled ahead of time; no JIT step is required.

## Preview limits and saves

This is an experimental Mac package. A successful compile and package audit
do not establish fresh-user launch, raw-disc import, gameplay or save-update
acceptance. Build 270 also predates the later Jak 1 ocean-renderer teardown
investigation. Full Mac gameplay and stability remain unverified.

The app retains its sandbox and user-selected-file access, with **local saves**.
The maintainer's iCloud entitlements, profiles and signing credentials are not
included. After importing, test a save, close the app and reopen it to check
the save persists. Keep backups before changing versions or app identities.

This Mac package does not use the seven-day free Apple Account signing cycle
described in the iPhone/iPad guide. See [all platform downloads](DOWNLOADS.md)
to choose the package for another device.
