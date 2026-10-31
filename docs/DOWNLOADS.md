# Dark Eco downloads

All packages require your own supported game data. These are experimental
previews; recipient signing, import, gameplay and save-preserving updates are
not certified by package checks. Sideloaded previews use local saves.

| Device | Package | Setup and limits |
| --- | --- | --- |
| Vision Pro, visionOS 26.5+ | [Build 264.1 IPA](https://github.com/zschwendi/dark-eco/releases/tag/visionos-build264.1-preview) | [Windows/Linux walkthrough](SIDELOADING.md). Jak 1 and unfinished Jak II; experimental Jak 1 immersion. |
| iPhone and iPad, iOS/iPadOS 26.5+ | [Build 279 IPA](https://github.com/zschwendi/dark-eco/releases/tag/ios-build279-preview) | [Phone/tablet setup](IOS-SIDELOADING.md). Frame-timing and Jak II catch-up presentation test candidate. ProMotion and persistent world slowdown still need physical acceptance; Library stutter remains unexplained. |
| Apple Silicon Mac, macOS 26.5+ | [Build 270.1 app ZIP](https://github.com/zschwendi/dark-eco/releases/tag/macos-build270.1-preview) | [Mac setup](MACOS-INSTALL.md). Fresh native arm64 build; Jak 1 only. Ad-hoc signed, not notarized; gameplay remains unverified. |

Download the named app asset, not GitHub's source-code ZIP. Verify it against
the release's `SHA256SUMS`. The iOS and visionOS IPAs are different platform
builds and cannot substitute for each other. IPA recipients use their own
signing identity; private profiles and certificates are not distributed.
The native Mac app does not need an IPA sideloader or Apple Account signing.

The [Vision Pro provenance](IPA-BUILD264-PROVENANCE.json) and
[iPhone/iPad provenance](IPA-IOS279-PROVENANCE.json) describe the original
builds and packaging changes. The [Mac provenance](IPA-MACOS270-PROVENANCE.json)
records its original Build 270 source; the Mac package is unchanged.
The older Vision Pro and Mac `.1` previews contain no later runtime fixes.
iPhone/iPad Build 279 is a fresh compilation; each receipt states its testing limits.
