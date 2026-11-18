# Optional Jak II immersion

Status: **Experimental**, signed Build 291 ready for a headset trial.
Tracked in [#30](https://github.com/zschwendi/dark-eco/issues/30).
The published Build 290 preview does not include this extension.

## Behavior

On Vision Pro, Jak II can use the same optional third-person immersive
presentation as Jak 1. The game's camera remains the base camera, with Jak
visible; headset pose supplies the two eye views. The conventional window
remains available. Entering immersion suspends its renderer, and leaving
restores it. Pausing returns to the window with the game still paused.

A normal gamepad or a pair of PSVR2 Sense controllers can supply buttons and
sticks. With motion gestures enabled, either-hand jabs map to Square,
side-to-side shakes to Circle, and raising both controllers to Cross. A second
lift can trigger the normal double jump. These gestures are optional and also
available during windowed play; original buttons remain available. This is
not first-person play or controller-anchored hands.

## Implementation

- Shared Swift presentation, menu and input gates now admit Jak II. The
  isolated Jak II framework forwards the existing reservation, external-target
  and completion API to its own renderer and Metal queue.
- Both eyes replay the same validated DMA frame. Host uploads and callbacks
  run once, while geometry draws for each eye. Culling uses a conservative
  binocular volume instead of the original single-camera frustum.
- The eye transform accounts for Jak II's projection and vertical scale.
  Sky generation applies the head rotation before the native producer clips
  polygons. Copied sky payloads must map to their validated original EE spans
  and match their bytes before the producer receipt is accepted.
- Shadow volumes and glow positions use their eye transforms. Fullscreen
  shadow resolves retain screen coordinates. Generic warp sampling derives
  its screen position after raster interpolation to preserve perspective.
- Invalid targets, camera data and provenance fail explicitly. Conventional
  rendering and the existing Jak 1 path retain their own camera conventions.

These are native C++/Objective-C++/Metal changes, not a GOAL code-mod pack.
The existing signed AOT libraries and public source-pack identities remain
unchanged: Jak 1 has 518 objects (`c1e79fbb50f33437`), and Jak II has 840
(`4f3e512e091fae63`). No game assets or new runtime-generated code are added.

## Validation boundaries

The synthetic tests exercise camera projection, binocular disparity, head
rotation, sky coverage, copied-DMA provenance, callbacks, shadow coverage and
recovery without retail assets. A separate CPU fixture executes the native
sky polygon producer and clipping functions. Its sun, moon and star callback
paths have source review only.

The canonical Release host build and all 26 scoped CTest cases pass, including
the native external-frame recovery test, actual sky-producer contract, stereo
GPU fixture, and existing Jak 1 sky regressions. The shared Swift/visionOS proof
aggregate also passes. Three fixture corrections were needed: a level name
exceeded the native packet's limit, the synthetic sky depth format was wrong,
and authored fog dimmed the quad below its exact-color detector. Projection
oracles and tolerances were preserved. The host recovery fixture now uses a
valid physical eye pair and a layer-backed host matching the application.

Release app builds passed for visionOS, iOS and macOS. The iOS signature and
the separately staged visionOS development signature both passed strict deep
verification. The signed visionOS app was copied to the delivery Mac and its
entire file-tree hash and signature independently verified. The intended
headset is included in the provisioning profile, but was unavailable, so no
physical installation or gameplay validation occurred.

Compiled source: app `8121568c4187680eaecaa02bec8d295f208a7182`, engine
`d2856ee9c16a39ea0efc4f2d8731a0b0bf5d08d1`. Later documentation changes do not
change that package identity. Public Build 290 downloads remain unchanged.

### Commands and results

The canonical host build used `cmake --build` with `--parallel 2` and explicit
targets for all 26 cases. `ctest --output-on-failure -j 1 -R` selected exactly
those registered tests; 26/26 passed. The selected targets cover DMA source
mapping, Jak II camera/effects math, sky classification and generation, stereo
GPU replay, native host recovery, terrain, shrubs, ties, generic effects,
warp, glow, shadow and display blits, plus the shared/Jak 1 regressions.

`sh Scripts/run-vision-immersive-proof-check.sh` passed, including shared
Swift presentation/input checks, native bridge checks and the existing Metal
proofs. `git diff --check` passed in both repositories.

Each app build used this command, sequentially, with the same DerivedData
directory and clean source identities recorded above:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Release -sdk "$SDK" -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" -jobs 2 \
  DEVELOPMENT_TEAM=V729QMY3V6 CODE_SIGN_STYLE=Automatic \
  CODE_SIGNING_ALLOWED="$SIGN" GOALPAD_BUILD_JOBS=2 \
  GOALPAD_OPENGOAL_GIT_METADATA="$PWD/OpenGOAL/.git" ARCHS=arm64 build
```

| SDK | Destination | SIGN | Result |
| --- | --- | --- | --- |
| xros | generic/platform=visionOS | NO | Pass; development-signed staging copy verified afterward |
| iphoneos | generic/platform=iOS | YES | Pass; signature verified |
| macosx | generic/platform=macOS | NO | Pass; compile validation only |

Staged app verification used `codesign --verify --deep --strict` on both Macs.
Complete expanded command arrays, logs, source hashes and private delivery
receipts are retained in the workspace's ignored
`.agent-builds/jak2-immersive-20261118` directory.

### Still unvalidated

Headset acceptance is still required for comfort, real-world effects and sky,
Sense gesture tuning, performance, and repeated enter/pause/resume/exit.
Compilation or synthetic GPU checks do not establish those results. Existing
Jak II renderer, mission and performance issues remain tracked separately;
this feature does not claim a complete story playthrough.
