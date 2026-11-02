# Build 285 validation

Compiled app source: `e35b062ea0414ff422cc69f4e69f32cae75b6ac4`.
Native source: `5e87ec78a5cf6397fbce40035cf5d015e9538702`.
The public source checkpoint adds full-display iOS Fit to Screen, portrait
Vert+ camera framing, automatic Duo laptop layout, and a 60 FPS default.
Explicit saved ProMotion choices remain preserved. This is not a ProMotion
frame-pacing fix. Vision refresh preference remains independent.

## Focused checks

- `Scripts/run-presentation-layout-check.sh`: passed; full display, Classic
  framing, laptop viewport and lower touch placement.
- `Scripts/run-portrait-library-check.sh`: passed.
- `Scripts/run-touch-controls-check.sh`: passed, including short lower
  regions and input reset behavior.
- `Scripts/run-presentation-settings-check.sh`: passed after the final
  default change; local/cloud behavior, defaults, explicit opt-in/out,
  persistence, reset and UI contract checks. The old UI source assertion
  expected Modern to default to 120 FPS; it was updated to the requested
  60 FPS contract. No failing check was disabled.
- The new posture observer passed Swift 6 strict-concurrency type checks for
  both iOS and iOS Simulator with the existing deployment target.
- The native portrait camera's deterministic projection tests passed.
- Jak 1 and Jak II source-object pack tests passed (2/2); current production
  packs pass, and the old aggregate identities are rejected.
- Source packs and AOT output were regenerated together. In each game the
  only changed generated game-code translation unit is `math_camera.c`;
  only `math-camera.o` and the object manifest change in the source pack.
- Source pack identities: Jak 1 518 objects / `561e066fb203d182`; Jak II
  840 objects / `c70c183115784045`.

## Simulator observations

In the isolated iPhone Duo simulator, the initial Build 285 layout checkpoint
`d09ad04` showed the existing imported Jak 1 Geyser Rock level in the top half
with controls below when partially open and portrait. Pause/resume and a
lower-control movement drag responded. Opening the hinge restored full-height
portrait gameplay; bending it again restored the split, without relaunching.

The final `e35b062` checkpoint changes only the ProMotion default, its tests
and documentation. It was rebuilt, installed without uninstalling the app or
resetting data, and launched. Graphics showed ProMotion off without changing
the switch; the existing Jak 1 import remained Ready. Game boot and lower
Start controls retained laptop presentation.


On the existing isolated iPhone Air iOS 26.5 simulator, the final Build 285
launched the existing Jak 1 data into Geyser Rock. The world filled the tall
portrait display behind the status area, with touch controls at the bottom.
No special hinge layout was used. This is a visual presentation observation;
Air performance, ergonomics, import and physical-device acceptance are not
claimed. Upside-down work is canceled.

These are bounded simulator observations, not physical Duo acceptance, a
full game playthrough, multiplayer touch validation, or Jak II laptop runtime
acceptance. The lower-half reflection is not implemented. Upside-down work was canceled
by the maintainer and is not part of this release.

## Platform and package results

| Target | Result | Duration |
| --- | --- | --- |
| simulator | PASS | 50.05 s |
| ios | PASS | 50.07 s |
| vision | PASS | 675.64 s |
| mac | PASS | 355.35 s |

Exact build invocations, with local paths and signing team replaced by placeholders:

simulator:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath '<derived-data>' -jobs 2 'DEVELOPMENT_TEAM=<your-team>' CODE_SIGN_STYLE=Automatic CODE_SIGNING_ALLOWED=NO GOALPAD_BUILD_JOBS=2 'GOALPAD_OPENGOAL_GIT_METADATA=<native-git-metadata>' ARCHS=arm64 build
```

ios:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad -configuration Release -sdk iphoneos -destination generic/platform=iOS -derivedDataPath '<derived-data>' -jobs 2 'DEVELOPMENT_TEAM=<your-team>' CODE_SIGN_STYLE=Automatic CODE_SIGNING_ALLOWED=YES GOALPAD_BUILD_JOBS=2 'GOALPAD_OPENGOAL_GIT_METADATA=<native-git-metadata>' ARCHS=arm64 build
```

vision:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad -configuration Release -sdk xros -destination generic/platform=visionOS -derivedDataPath '<derived-data>' -jobs 2 'DEVELOPMENT_TEAM=<your-team>' CODE_SIGN_STYLE=Automatic CODE_SIGNING_ALLOWED=NO GOALPAD_BUILD_JOBS=2 'GOALPAD_OPENGOAL_GIT_METADATA=<native-git-metadata>' ARCHS=arm64 build
```

mac:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad -configuration Release -sdk macosx -destination generic/platform=macOS -derivedDataPath '<derived-data>' -jobs 2 'DEVELOPMENT_TEAM=<your-team>' CODE_SIGN_STYLE=Automatic CODE_SIGNING_ALLOWED=NO GOALPAD_BUILD_JOBS=2 'GOALPAD_OPENGOAL_GIT_METADATA=<native-git-metadata>' ARCHS=arm64 build
```

Each platform used the same app/native commits and Build 285. Builds were
sequential, using one canonical DerivedData directory and two compiler jobs.
Commands used `xcodebuild -project GOALPad.xcodeproj -scheme GOALPad
-configuration Release -derivedDataPath <local-derived-data> -jobs 2
ARCHS=arm64 build`, with the platform SDK and generic destination.
The iOS input was automatically development-signed. The visionOS build was
compiled without signing and then signed with the existing local development
identity/profile. Both signed inputs passed strict verification.

Public IPAs remove the maintainer's provisioning and entitlements and receive
ad-hoc transport signatures for recipients to replace using their own signer.
Independent checks verify ZIP integrity, every file's size and SHA256,
platform/build identity, embedded provenance, complete source packs, absent
private profiles, and unchanged Mach-O code/data sections after repackaging.

No physical device was accessed for this checkpoint. Existing ProMotion,
Jak II rendering/cutscene issues and Jak 1 immersive acceptance remain open.
Compile, signing and package checks do not certify those behaviors.

## Public delivery

Both public IPAs were anonymously downloaded and every manifest member was
verified against its SHA256 and size. Embedded provenance matched the public
receipts. See [delivery receipt](BUILD285-DELIVERY.json). This verifies package
delivery, not recipient installation or gameplay.
