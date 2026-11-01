# Build 282 validation

Compiled app `9107051ccee1929b9585c5d066529239978a2445`; native engine `8b2cd07517c738128f41d66a2a9602be3751273a`. Both device packages use this exact checkpoint. Later delivery/provenance documentation commits do not change compiled source. One release, `build282-preview`, supplies separate iOS and visionOS IPAs. The older Mac 270.1 binary is unchanged.

## Changes

- Reconcile the later Jak 1 immersive foundation with current iOS/Jak II code, preserving current importer, touch, timing and WARP changes.
- Enable immersive code and its scene configuration in normal visionOS builds through SDK-specific project settings. No private build override is required. iOS/macOS keep their ordinary paths.
- Retain the current callback ownership policy while adding the later pause/exit/re-entry, tracking and Sense paths.
- Correct opted-in Direct HUD scissoring using perspective-correct authored coordinates. Ordinary draws retain their original clipping path.
- Document ten existing OpenGOAL mod candidates and first-person/Sense-hands research; no new mod or first-person gameplay feature is implemented.

Important files: `GOALPad/Vision/Immersive/`, app/host bridge and SDK-scoped `GOALPad.xcodeproj/project.pbxproj`; native `metal_immersive_camera.cpp`, per-view renderer state, world sprites/sky, `shaders/direct.metal` and its synthetic GPU fixture. Detailed source changes are available at the pinned commits.

## Checks

| Check | Result |
| --- | --- |
| Native camera/sky CPU checks | 5/5 passed on the integrated foundation; six worker standalone checks also passed |
| Vision source-integration check | Passed after stale assertions were updated for the retained current callback and toolbar policy |
| Integrated immersive proof | Passed; camera/menu math, real host-GPU per-eye resolve, lifecycle/tracking/session/input, Swift module and bridge checks |
| Native sky, sprite, Generic2, ocean, WARP and glow GPU targets | 7/7 passed; see the pre-existing fixture correction below |
| Direct HUD scissor old/new comparison | Same test fails with the old shader and passes with the correction; 12 cases cover affine/projective transforms, both eyes, basic/textured rendering and unchanged controls |
| Generic iOS Release | Passed, 85.08 seconds; development signature verified |
| Generic visionOS Release | Passed, 15.02 seconds on the final checkpoint; existing development signing profile applied and strict signature verified |
| Native macOS Release | Passed, 55.04 seconds; compile/link only, signing disabled |
| iOS Simulator Release | Passed, 120.09 seconds; compilation only, no simulator launched |
| Source-object packs | Both current native verifiers passed every member size/hash and aggregate: Jak 1, 518 / `806abc2b2667435a`; Jak II, 840 / `f2cdf82e9b913501` |
| Both public IPAs | ZIP integrity, all inventory hashes, native platform/device family, strict transport signatures and empty entitlements passed; no private profile remains |
| Compiled-code preservation | Every non-signature code/data Mach-O section matches the corresponding signed input app and embedded Jak II framework |

### Test corrections and preserved failures

The imported stereo math test used a tolerance smaller than floating-point cancellation error. Its analytical golden result remained correct; the test now uses an independent double reference and a local operation-derived float error bound. No global tolerance was loosened.

An old ocean envmap fixture placed its sprite at pixel Y 80.5–93, entirely outside its 64-pixel target under the source's 128-pixel viewport. Two synthetic Y coordinates now place it at Y 30.5–43, containing the existing oracle; a second pixel verifies the untouched clear region. Existing tolerances and production ocean code are unchanged. The complete corrected ocean test passes with both old and new Direct shaders. **This fixes the test, not the reported water rendering bug.**

Original failing logs and corrected results are preserved in the local Build 282 evidence. Initial source-text checks were updated to match retained current behavior, not disabled.

## Reproduction commands

Run from the outer checkout, with the existing canonical native build directory configured for that checkout:

```sh
sh Scripts/run-vision-stereo-integration-check.sh
sh Scripts/run-vision-immersive-proof-check.sh
cmake --build "$NATIVE_BUILD" --target metal-view-transform-test metal-jak1-sky-depth-math-test jak1-sky-generation-lifecycle-test jak1-sky-generation-contract-test jak1-mips2c-sky-register-state-test -j2
cmake --build "$NATIVE_BUILD" --target jak1-metal-sky-immersive-depth-test jak1-metal-sky-generated-immersive-test jak2-metal-sprite-renderer-test jak2-metal-generic2-renderer-test jak2-metal-ocean-envmap-proof jak2-metal-gmerc-warp317-renderer-test jak2-metal-glow-final-flare-proof -j2
ctest --test-dir "$NATIVE_BUILD" -R '^(metal-view-transform-test|metal-jak1-sky-depth-math-test|jak1-sky-generation-lifecycle-test|jak1-sky-generation-contract-test|jak1-mips2c-sky-register-state-test|jak1-metal-sky-immersive-depth-test|jak1-metal-sky-generated-immersive-test|jak2-metal-sprite-renderer-test|jak2-metal-generic2-renderer-test|jak2-metal-ocean-envmap-proof|jak2-metal-gmerc-warp317-renderer-test|jak2-metal-glow-final-flare-proof)$' --output-on-failure
```

Platform builds used `xcodebuild -project GOALPad.xcodeproj -scheme GOALPad -configuration Release -jobs 2 ARCHS=arm64 GOALPAD_BUILD_JOBS=2 build`, with generic iOS/visionOS/macOS/iOS Simulator destinations and matching SDKs. iOS used existing automatic development signing; the other compile checks disabled signing. Vision was then signed using the existing compatible profile. Machine-specific paths and private signing details remain local.

## Not validated and remaining work

No physical device was accessed and no simulator gameplay/performance test was run. Signed packaging is not gameplay acceptance.

- GenericHud collected orbs and 3D counter icons still bypass the calibrated HUD plane. Their logical depth cannot safely be substituted for physical compositor depth. This remains implementation work in #3.
- Sky, effects, HUD clipping and pause/warp/re-entry behavior require headset acceptance.
- ProMotion stutter, Jak II taillight blocks, frozen cutscene video and dark water/streaks remain open. WARP orientation correction is retained, not treated as a blanket water fix.
- Recipient import, Fit to Screen, pause presentation and full-game/save acceptance remain pending. The earlier Duo simulator importer check does not replace recipient-device confirmation.
- Jak II immersive and first-person/Sense hands are not implemented. The ten-mod report is source research, not Apple compatibility certification.

See the two provenance JSON files for the exact artifact identities and limits. Public download verification is recorded separately in `BUILD282-DELIVERY.json` after publication.
