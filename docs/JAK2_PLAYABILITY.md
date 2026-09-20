# Jak II playability work

Updated: September 20, 2026. Status: **Partially complete; simulator app build blocked.**

## Direction and baseline

GitHub-only distribution, using the real unified Dark Eco runtime. Preserve
Jak 1, current launcher/settings/saves, and all existing Jak II behavior.
The v1.0 release and v1.1 App Store reviewer/demo launcher are outside this
path. Historical `jak2-best` is comparison history, not the active app.

Work branch: `codex/jak2-github-playability`, based on outer `v2.0` at
`9fe17edf67a99f1b305443f8101e3e9d39ec94bc`. Nested OpenGOAL is unchanged at
`c8666f88b31260c84b2e0adf8cbee3073d9deda5`. This includes the tap-only R1 and
weapon-wheel fade fixes after the Build 239 handoff.

## Current validation

Run from the integration worktree:

| Command | Result |
| --- | --- |
| `Scripts/verify-generated-aot.sh Generated/jak1-aot 518` | PASS: 518 objects, 10,632 emitted functions, 7 native functions |
| `Scripts/verify-generated-aot.sh Generated/jak2-aot 840` | PASS: 840 objects, 18,493 emitted functions, 7 native functions |
| `Scripts/run-jak2-import-target-config-check.sh` | PASS |
| `Scripts/run-touch-controls-check.sh` | PASS |
| `Scripts/run-native-runtime-router-check.sh` | PASS |
| `Scripts/run-save-sync-check.sh` | PASS |
| `python3 Scripts/jak2-scene-sweep.py --self-test` | PASS |
| `python3 OpenGOAL/test/goalc/test_jak2_managed_display_settings.py` | PASS: 5 tests |
| `git diff --check` | PASS |

These are source, synthetic, and host checks. They do not prove gameplay,
renderer fidelity, full import, or a complete playthrough.

## Isolated simulator and build

A new iPad Pro 11-inch (M5), iOS 26.5 simulator named **Dark Eco Jak 2 -
Isolated** was created and booted successfully. Its UDID is
`E033177B-9F6B-48E2-B99F-CF81DB39EF80`. It was shut down while the app build
is blocked. Use this exact device for all installs, launches, captures, and
shutdowns; never use an unqualified `booted` destination or Peel's device.

The first full build command was:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Release -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=E033177B-9F6B-48E2-B99F-CF81DB39EF80' \
  -derivedDataPath /private/tmp/GOALPad-jak2-github-derived \
  -jobs 2 CODE_SIGNING_ALLOWED=NO GOALPAD_BUILD_JOBS=2 build
```

Result: **FAILED**, exit 65. First useful error:

```text
cannot execute tool 'metal' due to missing Metal Toolchain;
use: xcodebuild -downloadComponent MetalToolchain
```

`xcodebuild -showComponent MetalToolchain -json` confirms build `27A266a`,
status `uninstalled`. Maintainer approval to install the Apple component is
pending. No runtime code was changed before this failure. No app was installed
on the new simulator, and no physical device was accessed.

Local logs are under `/private/tmp/goalpad-jak2-github-validation/`:
`simulator-build.log`, `simulator-boot.log`, `touch-controls.log`,
`runtime-router.log`, and `save-sync.log`. Reuse the partial DerivedData on retry.

## Source gaps to reproduce

The initial read-only Cursor browser audit used the live-selected **Claude
Fable 5.1 High**, with both exact source tips available. The coordinator also
verified these paths locally. These are source findings, not a diagnosis of
the maintainer's particular scene or new runtime evidence:

- `OpenGOAL/game/graphics/pipelines/metal/metal_jak2_bucket_table.cpp:134-140`
  deliberately defers all six per-level GMerc PRIS and six GMerc PRIS2 paths.
  `metal_jak2_bucket_table_test.cpp:315` explicitly says their separate grammar
  is pending. Capture a scene that actually emits these paths before adding
  typed dispatch and a deterministic packet fixture; do not assume an existing
  normal GMerc parser accepts the same input.
- The same table defers SHADOW and SHADOW2 (`:155`, `:165`). The test at
  `metal_jak2_bucket_table_test.cpp:132` preserves a **physically rejected**
  Shadow2 route. The existing shadow195 capture renderer is diagnostic; simply
  enabling it would revive rejected behavior. Use its bounded frame-capture
  seam to isolate the geometry/presentation mismatch first.
- `OpenGOAL/game/graphics/pipelines/metal/metal_jak2_host_bridge.mm:2800-2836`
  loads every newly requested level into resident art/model pools, keeps the
  requested-name list, and leaves `set_active_levels` empty. Normal-session
  eviction is absent; the normal teardown releases loaded keys at `:3372`.
  Measure resident memory and loaded-level counts across repeated transitions,
  then test the lifetime of common, requested, and in-flight render resources
  before introducing eviction. This is a memory-growth risk, not a measured
  out-of-memory diagnosis.

The old water/eye repairs are already in the nested baseline; their physical
acceptance remains unverified. Source history convergence does not close the
missing drawing paths above or establish a complete game.

## Local game-data readiness

The existing `Jak2/projdata/out/jak2` directory outside the source worktree is
about 2 GiB and contains 22 of the current bounded manifest's 23 required
files. It is missing `iso/VAGWAD.ENG`. A targeted read-only metadata search of
the established local prepared-data/build roots found no complete alternative.
No asset contents were read into reports, copied, or uploaded. Do not weaken
readiness checks or use a placeholder archive to make this candidate pass.

Use the current real importer with the existing user-supplied Jak II ISO to
prepare the isolated simulator's data. This presence check does not certify
the old files' format compatibility or full-game completeness.

## Next execution gate

1. After installation approval, restore the missing Apple Metal component and
   rerun the exact simulator build without disabling shader compilation.
2. Install the real unified app on the dedicated simulator. Import the existing
   user-supplied ISO locally, with isolated prepared data and test saves.
3. Record baseline title/new-game behavior, then reproduce the maintainer's
   concrete missing gameplay/visual features. Use the existing scene-sweep and
   renderer diagnostics to distinguish an absent draw path from bad input,
   streaming failures, or presentation problems.
4. Fix one reproduced blocker at a time. Keep title isolation and the existing
   Jak 1/Jak II input/save checks passing, with a full app build for runtime
   changes. Do not revive a previously rejected renderer just by enabling it.
5. Track new game, traversal, missions, cutscenes, audio, save/load, level
   streaming, and return-to-library/relaunch as separate acceptance outcomes.
   A successful title screen or scene preview is not full playability.

Simulator validation is the current authorized device scope. Final physical
performance and playthrough acceptance remain separate and require a current
maintainer request before accessing Z iPad Pro.
