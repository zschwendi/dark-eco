# Vision Pro IPA preview

The first prepared package is **Dark Eco 2.0, Build 264.1** for **visionOS 26.5
or later**. It contains the native Jak and Daxter runtime, the embedded Jak II
runtime, and the on-device import tools. It is not a launcher-only build.
Users must supply their own supported game data; no disc image or extracted
retail game-data payload is included.

Look for a `.ipa` attachment in [GitHub Releases](https://github.com/zschwendi/dark-eco/releases).
A source ZIP is not an app. An IPA must be signed for the recipient's device by
a visionOS-compatible sideloading tool before it can run.

## What this preview contains

This is a repack of the existing experimental **Build 264** app, not a rebuild
of the public `v2.0` source branch. Its original build receipts identify:

- App source: `caf7b65152efa0359a8d50cee7ca2742af859931`
- OpenGOAL engine: `561baff2a28ac390570ab534d02ed5db77c3e89f`

Those exact source commits were not fetchable during packaging. The public
`v2.0` source guide describes a separate conventional-window checkpoint and
does not reproduce this preview. The complete packaging provenance is in
[IPA-BUILD264-PROVENANCE.json](IPA-BUILD264-PROVENANCE.json).

The package retains the original application and framework code. Build **264.1**
identifies this packaging revision of Build 264. Packaging
removes the maintainer's provisioning profile and original signatures, adds
upstream notices, and applies ad-hoc signatures with empty entitlements so a
recipient can re-sign the app. It does not contain the maintainer's signing
certificate or a universal installation profile.

**Use local saves and manual save export/import.** iCloud is not provisioned
in this package. Export saves before changing signing accounts or bundle IDs;
those changes can create a separate installation. Do not uninstall an existing
copy to troubleshoot an update.

## Game-data import and limits

In the Library, choose **Jak and Daxter**, then **Set Up Game Data → Continue →
Choose game data…**. Supply a supported **SCUS-97124 NTSC v1 / Black Label**
ISO, a ZIP/7z containing exactly one supported ISO, or a compatible prepared
folder containing `iso/` and `fr3/`. Keep Dark Eco in the foreground while it
imports and verifies the data. Use the file formats offered by the app.

Start in the ordinary window with a compatible gamepad. Jak 1 immersion is
experimental: sky gaps, stereo effects, HUD and interaction issues remain.
The included Jak II runtime is unfinished, predates later Jak II fixes, and
has no immersive mode. The current source README may describe newer work
that is not in Build 264.

## Validation boundary

The original signed Build 264 has an installation receipt. This repack has
passed bundle inspection, source-object manifest/hash checks, native visionOS
platform checks, ad-hoc code-sign verification, resource-preservation checks,
and IPA ZIP integrity checks. Its release includes SHA-256 and a per-file
package manifest.

**This repack has not been installed, launched, signed with a recipient's free
Apple account, or tested for gameplay.** Installation success, game import,
gameplay and save-preserving updates remain separate tests. Do not interpret
this package as a confirmed Windows-to-headset installation result.

## Maintainer packaging

Requires macOS with Xcode command-line tools and Python 3.11 or newer. This
command packages an already built, audited app and does not compile or install:

```sh
python3 Scripts/package-visionos-ipa.py \
  --app '/absolute/path/to/Dark Eco.app' \
  --receipt docs/IPA-BUILD264-PROVENANCE.json \
  --licenses docs/ipa-licenses \
  --output /absolute/path/to/new-output-directory
```

The receipt pins the original app/framework hashes and source-pack manifests.
It must describe the actual input artifact. The helper rejects mismatched
builds, incomplete source packs, unexpected root files, retail payload file
types, and symlinks. Before recording a new receipt, verify every source-pack
object's XXH64 against its manifest, inspect the native code provenance and
all bundle resources, and review the relevant upstream notices. The helper's
file checks do not replace that audit.

Keep the original build untouched. Publish the IPA with `SHA256SUMS`,
`PACKAGE-MANIFEST.json`, this validation boundary, and its provenance. A
future preview must identify its own input build and validation results.
