# Dark Eco downloads

All packages require your own supported game data. These are experimental
previews; recipient signing, import, gameplay and save-preserving updates are
not certified by package checks. Sideloaded previews use local saves.

## Current packages

| Device | Package | Setup and limits |
| --- | --- | --- |
| iPhone and iPad, iOS/iPadOS 26.5+ | [Build 286 iOS IPA](https://github.com/zschwendi/dark-eco/releases/download/build286-preview/DarkEco-iOS-2.0-build286-preview.ipa) | [Phone/tablet setup](IOS-SIDELOADING.md). Smaller default game text at the same anchors in conventional Fit to Screen portrait. Retains full-display Fit, the iOS 27.1+ automatic Duo laptop layout and earlier import/presentation corrections. Scoped Duo checks passed; Build 286 Air visuals and physical acceptance remain pending. ProMotion and other renderer bugs remain open. |
| Vision Pro, visionOS 26.5+ | [Build 286 visionOS IPA](https://github.com/zschwendi/dark-eco/releases/download/build286-preview/DarkEco-visionOS-2.0-build286-preview.ipa) | [Windows/Linux walkthrough](SIDELOADING.md). Jak 1 and unfinished Jak II; experimental third-person Jak 1 immersion in the normal build. HUD orb/icon depth and wearer acceptance remain open. |
| Apple Silicon Mac, macOS 26.5+ | [Build 270.1 app ZIP](https://github.com/zschwendi/dark-eco/releases/tag/macos-build270.1-preview) | [Mac setup](MACOS-INSTALL.md). Fresh native arm64 build; Jak 1 only. Ad-hoc signed, not notarized; gameplay remains unverified. |

Both Build 286 IPAs are in the single [Build 286 release](https://github.com/zschwendi/dark-eco/releases/tag/build286-preview), compiled from
one shared source checkpoint and build number: [app `0f04a8c`](https://github.com/zschwendi/dark-eco/commit/0f04a8c8d9ad01ab4793a307dba1ead83adc16ea)
and [engine `b8d08811a`](https://github.com/zschwendi/jak-pad/commit/b8d08811accfd1e5e77a1571bddd766ca6fa7d7e).
iOS, iOS simulator, macOS and visionOS builds passed, along with both native
ABI and both source-pack checks; see [Build 286 validation](BUILD286-VALIDATION.md).
There is no Mac Build 286 package; the Mac preview remains Build 270.1.
Existing valid game imports do not need re-importing for the font update.

Download the named app asset, not GitHub's source-code ZIP. Verify it against
the release's `SHA256SUMS`. The iOS and visionOS IPAs are different platform
builds and cannot substitute for each other. IPA recipients use their own
signing identity; private profiles and certificates are not distributed.
The native Mac app does not need an IPA sideloader or Apple Account signing.

The [iPhone/iPad provenance](IPA-IOS286-PROVENANCE.json) and
[Vision Pro provenance](IPA-VISIONOS286-PROVENANCE.json) record the Build 286
source, hashes and testing limits. The [Mac provenance](IPA-MACOS270-PROVENANCE.json)
records its original Build 270 source; the Mac package is unchanged and
contains no later runtime fixes.

## Earlier packages

| Device | Package | Notes |
| --- | --- | --- |
| iPhone and iPad | [Build 285 IPA](https://github.com/zschwendi/dark-eco/releases/tag/build285-preview) | Full-display Fit, automatic Duo laptop layout and 60 FPS defaults. [Validation](BUILD285-VALIDATION.md) and [provenance](IPA-IOS285-PROVENANCE.json) retain its original evidence and limits. |
| Vision Pro | [Build 285 IPA](https://github.com/zschwendi/dark-eco/releases/tag/build285-preview) | Shared Apple source with experimental Jak 1 immersion; no new headset acceptance. [Provenance](IPA-VISIONOS285-PROVENANCE.json). |
| iPhone and iPad | [Build 282 IPA](https://github.com/zschwendi/dark-eco/releases/tag/build282-preview) | Unified-source iOS package; retained the Build 280/281 import, presentation and Jak II distortion corrections. [Provenance](IPA-IOS282-PROVENANCE.json). |
| Vision Pro | [Build 282 IPA](https://github.com/zschwendi/dark-eco/releases/tag/build282-preview) | Unified-source visionOS package with experimental third-person Jak 1 immersion. [Provenance](IPA-VISIONOS282-PROVENANCE.json). |
| iPhone and iPad | [Build 281 IPA](https://github.com/zschwendi/dark-eco/releases/tag/ios-build281-preview) | Corrected vertically mirrored Jak II framebuffer distortion; retained Build 280 import/presentation candidates. [Provenance](IPA-IOS281-PROVENANCE.json). |
| Vision Pro | [Build 264.1 IPA](https://github.com/zschwendi/dark-eco/releases/tag/visionos-build264.1-preview) | Audited repack of Build 264 with no later runtime fixes. [Provenance](IPA-BUILD264-PROVENANCE.json). |
