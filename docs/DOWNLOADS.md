# Dark Eco downloads

All packages require your own supported game data. These are experimental
previews; recipient signing, import, gameplay and save-preserving updates are
not certified by package checks. Sideloaded previews use local saves.

## Current packages

| Device | Package | Setup and limits |
| --- | --- | --- |
| iPhone and iPad, iOS/iPadOS 26.5+ | [Build 290 iOS IPA](https://github.com/zschwendi/dark-eco/releases/download/build290-preview/DarkEco-iOS-2.0-build290-preview.ipa) | [Phone/tablet setup](IOS-SIDELOADING.md). Import alternative, Jak II resolution/remap/audio corrections, sewer and race fixes. Known renderer/cutscene failures remain. Package and public-download verification passed; physical acceptance remains pending. |
| Vision Pro, visionOS 26.5+ | [Build 290 visionOS IPA](https://github.com/zschwendi/dark-eco/releases/download/build290-preview/DarkEco-visionOS-2.0-build290-preview.ipa) | [Windows/Linux walkthrough](SIDELOADING.md). Shared runtime corrections; experimental third-person Jak 1 immersion, unfinished windowed Jak II. No new immersive or headset acceptance. Package and public-download verification passed; physical acceptance remains pending. |
| Apple Silicon Mac, macOS 26.5+ | [Build 270.1 app ZIP](https://github.com/zschwendi/dark-eco/releases/tag/macos-build270.1-preview) | [Mac setup](MACOS-INSTALL.md). Fresh native arm64 build; Jak 1 only. Ad-hoc signed, not notarized; gameplay remains unverified. |

Both IPAs are in the single [Build 290 release](https://github.com/zschwendi/dark-eco/releases/tag/build290-preview),
from app [`76d3663`](https://github.com/zschwendi/dark-eco/commit/76d3663a87686abfe578b924038a127c7956677d)
and engine [`d36fe150f`](https://github.com/zschwendi/jak-pad/commit/d36fe150fc2c009db684e84cab20fa0f674b12b5).
**Release iOS, visionOS and macOS compilation passed. Both IPA package checks passed.** Exact results
and limitations belong to [Build 290 validation](BUILD290-VALIDATION.md).

The latest 98 authored mission-start results are 81 PASS / 17 FAIL across mixed
Build 289b and 290 simulator attempts. This does not certify a playthrough,
physical performance, every effect or audible output. The Mac download stays
at **Build 270.1**, with none of the later runtime fixes.

**Updating an existing installation:** back up saves and update in place with
the same signing identity when possible. Keep your installed game data; you
do not need to re-import solely for this update or the race fix. Two isolated
Build 290 mission-start checks passed with unchanged Build 288 prepared data.
That is a limited compatibility check, not a guarantee for every import or
device. A different App ID or signer can create a separate save container.

Download the named app asset, not GitHub's source-code ZIP. Verify it against
the release's `SHA256SUMS`. The iOS and visionOS IPAs are different platform
builds and cannot substitute for each other. IPA recipients use their own
signing identity; private profiles and certificates are not distributed.
The native Mac app does not need an IPA sideloader or Apple Account signing.

The [iPhone/iPad provenance](IPA-IOS290-PROVENANCE.json) and
[Vision Pro provenance](IPA-VISIONOS290-PROVENANCE.json) record the compiled source,
hashes and testing limits. The [Mac provenance](IPA-MACOS270-PROVENANCE.json)
retains its original Build 270 source and unchanged package identity.

## Earlier packages

| Device | Package | Notes |
| --- | --- | --- |
| iPhone and iPad | [Build 286 IPA](https://github.com/zschwendi/dark-eco/releases/tag/build286-preview) | Earlier portrait-text preview. [Validation](BUILD286-VALIDATION.md) and [provenance](IPA-IOS286-PROVENANCE.json) retain its original checks and limits. |
| Vision Pro | [Build 286 IPA](https://github.com/zschwendi/dark-eco/releases/tag/build286-preview) | Earlier shared-source preview; no new headset acceptance. [Provenance](IPA-VISIONOS286-PROVENANCE.json). |
| iPhone and iPad | [Build 285 IPA](https://github.com/zschwendi/dark-eco/releases/tag/build285-preview) | Full-display Fit, automatic Duo laptop layout and 60 FPS defaults. [Validation](BUILD285-VALIDATION.md) and [provenance](IPA-IOS285-PROVENANCE.json) retain its original evidence and limits. |
| Vision Pro | [Build 285 IPA](https://github.com/zschwendi/dark-eco/releases/tag/build285-preview) | Shared Apple source with experimental Jak 1 immersion; no new headset acceptance. [Provenance](IPA-VISIONOS285-PROVENANCE.json). |
| iPhone and iPad | [Build 282 IPA](https://github.com/zschwendi/dark-eco/releases/tag/build282-preview) | Unified-source iOS package; retained the Build 280/281 import, presentation and Jak II distortion corrections. [Provenance](IPA-IOS282-PROVENANCE.json). |
| Vision Pro | [Build 282 IPA](https://github.com/zschwendi/dark-eco/releases/tag/build282-preview) | Unified-source visionOS package with experimental third-person Jak 1 immersion. [Provenance](IPA-VISIONOS282-PROVENANCE.json). |
| iPhone and iPad | [Build 281 IPA](https://github.com/zschwendi/dark-eco/releases/tag/ios-build281-preview) | Corrected vertically mirrored Jak II framebuffer distortion; retained Build 280 import/presentation candidates. [Provenance](IPA-IOS281-PROVENANCE.json). |
| Vision Pro | [Build 264.1 IPA](https://github.com/zschwendi/dark-eco/releases/tag/visionos-build264.1-preview) | Audited repack of Build 264 with no later runtime fixes. [Provenance](IPA-BUILD264-PROVENANCE.json). |
