# Dark Eco downloads

All packages require your own supported game data. These are experimental
previews; recipient signing, import, gameplay and save-preserving updates are
not certified by package checks. Sideloaded previews use local saves.

| Device | Package | Setup and limits |
| --- | --- | --- |
| Vision Pro, visionOS 26.5+ | [Build 264.1 IPA](https://github.com/zschwendi/dark-eco/releases/tag/visionos-build264.1-preview) | [Windows/Linux walkthrough](SIDELOADING.md). Jak 1 and unfinished Jak II; experimental Jak 1 immersion. |
| iPhone and iPad, iOS/iPadOS 26.5+ | [Build 270.1 IPA](https://github.com/zschwendi/dark-eco/releases/tag/ios-build270.1-preview) | [Phone/tablet setup](IOS-SIDELOADING.md). One native arm64 device IPA; known Jak II and Jak 1 teardown crashes remain. |
| Apple Silicon Mac | Package preparation pending | The native Mac target supports Jak 1 only. No new Mac build or gameplay validation is claimed. |

Download the named app asset, not GitHub's source-code ZIP. Verify it against
the release's `SHA256SUMS`. The iOS and visionOS IPAs are different platform
builds and cannot substitute for each other. Each recipient uses their own
signing identity; private profiles and certificates are not distributed.

The [Vision Pro provenance](IPA-BUILD264-PROVENANCE.json) and
[iPhone/iPad provenance](IPA-IOS270-PROVENANCE.json) describe the exact original
builds, packaging changes and testing limits. Build numbers ending in `.1`
identify a packaging revision; they do not mean newer game code was compiled.
