# Build 286 validation

Build 286 is an experimental portrait-text preview. Scoped Duo simulator checks and all affected builds passed; physical acceptance remains pending.

## Source and behavior

- Compiled app: `0f04a8c8d9ad01ab4793a307dba1ead83adc16ea`.
- Compiled engine: `b8d08811accfd1e5e77a1571bddd766ca6fa7d7e`.
- Default game fonts now size to viewport width in conventional iOS Fit to Screen portrait. Glyph advances, measurement and UI line height use the same scale; anchors and full-screen world framing are preserved.
- Jak 1 adjusts six glyph-size vectors around the active GOAL draw/measurement functions and restores them after each call. Jak II temporarily adjusts text-context scale. Custom matrices, landscape, Fit off, macOS and visionOS retain their existing font scale.
- Existing valid imports load the current linked AOT code by object name; re-importing is not required.

## Important files

- App `GOALPad/Native/GOALPadRenderSurface.mm` and `TargetSupport/Jak2/EcoJak2RuntimeBridge.mm`: supply the actual Fit setting and gameplay viewport to the font query.
- Engine `game/kernel/core/desktop_seams.cpp`, `kernel_game.h` and game symbol inventories: expose the query using the native GOAL integer-register float-bit ABI; desktop binding returns identity.
- Both games' `goal_src/*/engine/gfx/font.gc`, `font-h.gc` and `engine/ui/text.gc`: matched draw, measurement and line-height correction.
- Source-object pack identities and native tests updated. `docs/PORTRAIT_TEXT_LAYOUT.md` explains the scope.

## Checks and results

| Check | Result |
| --- | --- |
| Native GOAL ABI tests | 2/2 passed |
| Source-object pack tests | 2/2 passed |
| Full GOAL graph / source-pack generation | Jak 1 518 objects; Jak II 840 objects |
| Production source-pack validation | Jak 1 `c1e79fbb50f33437`; Jak II `52a48a48ebb03e70` |
| Release arm64 iOS simulator build | Passed |
| Release arm64 iOS build | Passed; signed input verified |
| Release arm64 visionOS build | Passed; staged signed input verified |
| Release arm64 macOS build | Passed; no new Mac download published |
| Public IPA local independent readback | ZIP integrity, every file hash, source/build, source packs and strict transport signatures passed |

The first native test run hit an existing fixture that requested display values without enabling the portable display. The fixture now enables it and resets it afterward; both retry tests passed. Original failure evidence is retained locally.

## Commands

Commands below use `HOST_BUILD`, `DERIVED_DATA`, `APP_SOURCE`, and `ARTIFACTS` for the recorded local directories and `SIGNING_TEAM` for the configured team. Platform-build receipts retain the exact executed arguments. No physical device destination was used.

```sh
cmake --build "$HOST_BUILD" --target jak1-gfx-host-test jak2-lightweight-machine-test --parallel 2
ctest --test-dir "$HOST_BUILD" -R '^(jak1-gfx-host-test|jak2-lightweight-machine-test)$' --output-on-failure
cmake --build "$HOST_BUILD" --target jak1-source-object-pack-verify jak2-source-object-pack-verify jak1-source-object-pack-test jak2-source-object-pack-test --parallel 2
ctest --test-dir "$HOST_BUILD" -R '^(jak1-source-object-pack-test|jak2-source-object-pack-test)$' --output-on-failure
"$HOST_BUILD/goalc/jak1-source-object-pack-verify" "$ARTIFACTS/generated-staging/jak1-source-object-pack"
"$HOST_BUILD/goalc/jak2-source-object-pack-verify" "$ARTIFACTS/generated-staging/jak2-source-object-pack"
```

Platform commands (run from `APP_SOURCE`, all exit 0):

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath "${DERIVED_DATA}" -jobs 2 DEVELOPMENT_TEAM="${SIGNING_TEAM}" CODE_SIGN_STYLE=Automatic CODE_SIGNING_ALLOWED=NO GOALPAD_BUILD_JOBS=2 GOALPAD_OPENGOAL_GIT_METADATA="${APP_SOURCE}/OpenGOAL/.git" ARCHS=arm64 build
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad -configuration Release -sdk iphoneos -destination generic/platform=iOS -derivedDataPath "${DERIVED_DATA}" -jobs 2 DEVELOPMENT_TEAM="${SIGNING_TEAM}" CODE_SIGN_STYLE=Automatic CODE_SIGNING_ALLOWED=YES GOALPAD_BUILD_JOBS=2 GOALPAD_OPENGOAL_GIT_METADATA="${APP_SOURCE}/OpenGOAL/.git" ARCHS=arm64 build
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad -configuration Release -sdk xros -destination generic/platform=visionOS -derivedDataPath "${DERIVED_DATA}" -jobs 2 DEVELOPMENT_TEAM="${SIGNING_TEAM}" CODE_SIGN_STYLE=Automatic CODE_SIGNING_ALLOWED=NO GOALPAD_BUILD_JOBS=2 GOALPAD_OPENGOAL_GIT_METADATA="${APP_SOURCE}/OpenGOAL/.git" ARCHS=arm64 build
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad -configuration Release -sdk macosx -destination generic/platform=macOS -derivedDataPath "${DERIVED_DATA}" -jobs 2 DEVELOPMENT_TEAM="${SIGNING_TEAM}" CODE_SIGN_STYLE=Automatic CODE_SIGNING_ALLOWED=NO GOALPAD_BUILD_JOBS=2 GOALPAD_OPENGOAL_GIT_METADATA="${APP_SOURCE}/OpenGOAL/.git" ARCHS=arm64 build
```

Full generated-input and packaging commands/results are retained in the task's `portrait-text-20261102` artifacts: `generate-font-inputs.py`, `run-platform-build.py`, `prepare-public286.py`, `verify-public286.py` and `verify-public-download.py`. The release includes manifests, independent package checks, both provenance records and `SHA256SUMS`; [delivery evidence](BUILD286-DELIVERY.json) records anonymous public download verification.

## Scoped simulator observation

On the isolated iPhone Duo simulator running iOS 27.1, Build 285 title-menu text was captured before installing 286. Build 286 rendered smaller title/load text at the original anchors, navigation worked, and an existing Geyser Rock 0% save loaded. The portrait pause screen rendered its title/counters/options. Rotating to landscape restored the original font scale; returning to portrait restored the correction, with no progressive shrinking observed over repeated frames.

This was a font/layout check, not a playthrough. A transient-file save comparison fixture failed and cannot prove before/after byte equality; the actual existing save remained present and loaded successfully. The Duo simulator was shut down afterward, preserving its app and data. The potentially user-active Air simulator was left untouched.

## Not validated / remaining limits

- No Build 286 physical-device access, installation or acceptance.
- No Build 286 Air visual check or full Jak II menu/dialogue visual coverage.
- No claim that every hard-coded HUD position, icon or menu layout fits every portrait aspect ratio; this patch adjusts fonts, not all UI art/layout.
- Renderer, ProMotion stutter, water/taillight/cutscene defects and immersive HUD/wearer acceptance remain separate open issues. ProMotion still defaults off; existing choices are preserved.
- The requested laptop reflection remains unimplemented. Upside-down work was canceled.
- Public IPAs contain no retail assets or maintainer provisioning; recipients supply data and signing. Packaging does not establish gameplay or signing-provider compatibility on every device.
