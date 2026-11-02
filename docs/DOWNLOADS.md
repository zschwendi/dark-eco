# Dark Eco downloads

All packages require your own supported game data. These are experimental
previews; recipient signing, import, gameplay and save-preserving updates are
not certified by package checks. Sideloaded previews use local saves.

## Current packages

| Device | Package | Setup and limits |
| --- | --- | --- |
| iPhone and iPad, iOS/iPadOS 26.5+ | [Build 285 iOS IPA](https://github.com/zschwendi/dark-eco/releases/download/build285-preview/DarkEco-iOS-2.0-build285-preview.ipa) | [Phone/tablet setup](IOS-SIDELOADING.md). Unified source; Fit to Screen fills portrait and landscape displays, and an experimental automatic Duo laptop layout applies on iOS 27.1+. Retains the Build 280/281 import, presentation and Jak II distortion corrections. Physical acceptance is pending; ProMotion and other renderer bugs remain open. |
| Vision Pro, visionOS 26.5+ | [Build 285 visionOS IPA](https://github.com/zschwendi/dark-eco/releases/download/build285-preview/DarkEco-visionOS-2.0-build285-preview.ipa) | [Windows/Linux walkthrough](SIDELOADING.md). Jak 1 and unfinished Jak II; experimental third-person Jak 1 immersion in the normal build. HUD orb/icon depth and wearer acceptance remain open. |
| Apple Silicon Mac, macOS 26.5+ | [Build 270.1 app ZIP](https://github.com/zschwendi/dark-eco/releases/tag/macos-build270.1-preview) | [Mac setup](MACOS-INSTALL.md). Fresh native arm64 build; Jak 1 only. Ad-hoc signed, not notarized; gameplay remains unverified. |

Both Build 285 IPAs are in the single [Build 285 release](https://github.com/zschwendi/dark-eco/releases/tag/build285-preview), compiled from
one shared source checkpoint and build number. There is no Mac Build 285
package; the Mac preview remains Build 270.1.

Download the named app asset, not GitHub's source-code ZIP. Verify it against
the release's `SHA256SUMS`. The iOS and visionOS IPAs are different platform
builds and cannot substitute for each other. IPA recipients use their own
signing identity; private profiles and certificates are not distributed.
The native Mac app does not need an IPA sideloader or Apple Account signing.

The [iPhone/iPad provenance](IPA-IOS285-PROVENANCE.json) and
[Vision Pro provenance](IPA-VISIONOS285-PROVENANCE.json) record the Build 285
source, hashes and testing limits. The [Mac provenance](IPA-MACOS270-PROVENANCE.json)
records its original Build 270 source; the Mac package is unchanged and
contains no later runtime fixes.

## Earlier packages

| Device | Package | Notes |
| --- | --- | --- |
| iPhone and iPad | [Build 282 IPA](https://github.com/zschwendi/dark-eco/releases/tag/build282-preview) | Unified-source iOS package; retained the Build 280/281 import, presentation and Jak II distortion corrections. [Provenance](IPA-IOS282-PROVENANCE.json). |
| Vision Pro | [Build 282 IPA](https://github.com/zschwendi/dark-eco/releases/tag/build282-preview) | Unified-source visionOS package with experimental third-person Jak 1 immersion. [Provenance](IPA-VISIONOS282-PROVENANCE.json). |
| iPhone and iPad | [Build 281 IPA](https://github.com/zschwendi/dark-eco/releases/tag/ios-build281-preview) | Corrected vertically mirrored Jak II framebuffer distortion; retained Build 280 import/presentation candidates. [Provenance](IPA-IOS281-PROVENANCE.json). |
| Vision Pro | [Build 264.1 IPA](https://github.com/zschwendi/dark-eco/releases/tag/visionos-build264.1-preview) | Audited repack of Build 264 with no later runtime fixes. [Provenance](IPA-BUILD264-PROVENANCE.json). |
