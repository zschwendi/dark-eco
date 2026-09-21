# Jak II playability work

Updated: September 20, 2026. Status: **Partially complete; simulator app build blocked.**

## Direction and baseline

GitHub-only distribution, using the real unified Dark Eco runtime. Preserve
Jak 1, current launcher/settings/saves, and all existing Jak II behavior.
The v1.0 release and v1.1 App Store reviewer/demo launcher are outside this
path. Historical `jak2-best` is comparison history, not the active app.

Work branch: `codex/jak2-github-playability`, based on outer `v2.0` at
`9fe17edf67a99f1b305443f8101e3e9d39ec94bc`. Nested baseline was
`c8666f88b31260c84b2e0adf8cbee3073d9deda5`; the local `v2.0` branch now includes
the verified importer-only commit `f42edddc42a761c9a18232bc2505329f87e7a97a`.
The baseline includes the tap-only R1 and weapon-wheel fade fixes after the
Build 239 handoff. No changes have been pushed or released.

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

- The level-art lifetime issue below is the first stability investigation.
  `metal_jak2_host_bridge.mm:243-248` makes a load failure terminal, and
  `:1706-1710` then rejects subsequent drawing chains. Reproduce failure and
  observe app behavior before choosing recovery; do not remove fail-closed
  checks while texture/resource ownership remains uncertain.
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
- SUBTITLE bucket 322 is also deferred (`metal_jak2_bucket_table.cpp:173`).
  Unlike the upstream `TextureUploadHandler` with direct fallback, the current
  bucket-322 plan is explicitly a passive classifier, not an executor.
  `goal_src/jak2/engine/scene/scene.gc:1588-1600` emits the cutscene subtitle
  toggle confirmation into this path. Capture that exact action, then test
  its upload/draw packets with readback before connecting an executor. This
  does **not** mean all subtitles are missing: ordinary PC subtitle text uses
  the already implemented `debug-no-zbuf2` path.

The completed [Cursor audit](https://cursor.com/agents/bc-f17d70be-2453-4e46-93c6-86366c0421e3)
is a source review only. Its proposed patches require coordinator review and
runtime evidence; no worker edit was integrated. The redundant queued follow-up
was stopped after the report completed.

The old water/eye repairs are already in the nested baseline; their physical
acceptance remains unverified. Source history convergence does not close the
missing drawing paths above or establish a complete game.

## Voice import investigation and verified change

**Implemented:** Jak II finalization now uses one exact-directory content scan
per validation checkpoint, instead of immediately hashing every file twice.
The three validation checkpoints remain intact. File-set, size, content-hash,
private-file, directory-identity, and promotion checks are retained. This drops
composer-wide output scans from seven to four. No Jak 1/shared materializer,
launcher, save, audio, or renderer code changed.

The only nested source changes are:

- `decompiler/extractor/jak2_import_composer.cpp`: remove the redundant first
  per-file scan in `validate_captured_directory`.
- `test/common/test_jak2_import_composer.cpp`: exercise same-size content
  mutation rejection at all three finalization callback boundaries.

Earlier sequential ISO extraction and redundant-verification fixes are already
ancestors of the baseline (`c70f784e4`, `aefbd1dc6`, `c7c45c31a`). The current
FR3 preparer sets `rip_streamed_audio = false`; voice archives are copied, not
converted to decoded audio during import. The runtime's silent/art-only stream
clock is a separate playback fallback, not an import-speed workaround.

The unified app has a real VAG playback path: `sound_rpc_jak2.cpp` opens the
selected `VAGWAD` language archive and feeds the mixer; Swift `AudioOutput`
pulls the embedded Jak II runtime's audio. `GOALPAD_SND_NO_CUBEB=1` disables
Cubeb device ownership because the app uses AVAudioEngine; it does not disable
the mixer. Actual voiced-scene output in the new simulator is still pending.

Validation commands run from nested OpenGOAL:

```sh
cmake -S . -B build/Release/bin \
  -DOPENGOAL_BUILD_JAK2_IMPORT_COMPOSER_ONLY=ON -DBUILD_TESTING=ON
cmake --build build/Release/bin --target jak2-import-composer-test --parallel 2
ctest --test-dir build/Release/bin -R '^jak2-import-composer-test$' --output-on-failure
python3 scripts/build-jak2-fr3-project-bundle.py --source-root . \
  /private/tmp/goalpad-jak2-github-validation/Jak2ProjectResources
python3 scripts/build-jak2-fr3-project-bundle.py --verify-only \
  /private/tmp/goalpad-jak2-github-validation/Jak2ProjectResources
python3 /private/tmp/goalpad-jak2-github-validation/run-timed-oracle.py
```

All passed. The resource bundle contains 29 public files; its SHA-256 is
`7c9a52b61d4deec2a67ca1a8fcc6b44f6a8212ad479610daf29dfe76f43d751f`.
The timed oracle is a local-only copy of the existing real-import test with
elapsed-time logging added to its progress callback, linked to the rebuilt
libraries. It preserves the original synthetic and real-output assertions.
The user-supplied ISO and generated retail outputs stayed local, outside Git.

The full oracle passed in **38.014 seconds on this Mac**, producing 150
archives, 2,853 objects, 417 flat files, 147 FR3 files, and 5,236,849,659 output
bytes. Approximate phase times: ISO extraction 3.7 seconds; FR3 preparation
16.1 seconds; materialization plus initial capture 11.3 seconds. This is a
single host run, not an iPad timing or a measured before/after speedup.

Strict changed-file compilation also passed for both Apple SDKs:

```sh
xcrun --sdk iphonesimulator clang++ -std=c++20 -Wall -Wextra -Wpedantic -Werror \
  -target arm64-apple-ios17.0-simulator \
  -isysroot "$(xcrun --sdk iphonesimulator --show-sdk-path)" -I. \
  -fsyntax-only decompiler/extractor/jak2_import_composer.cpp
xcrun --sdk iphoneos clang++ -std=c++20 -Wall -Wextra -Wpedantic -Werror \
  -target arm64-apple-ios17.0 \
  -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" -I. \
  -fsyntax-only decompiler/extractor/jak2_import_composer.cpp
```

These are changed-file compile checks, not a linked/signed app build. The
canonical host cache was restored to its normal configuration afterward with
`cmake -S . -B build/Release/bin -DOPENGOAL_BUILD_JAK2_IMPORT_COMPOSER_ONLY=OFF`.
Logs: `importer-configure.log`, `importer-build.log`, `importer-tests.log`,
`importer-apple-compile.log`, `import-resources.log`, and `import-oracle.log`
under the local validation directory recorded above.

The existing voice backend regression target was then rebuilt and run:

```sh
cmake --build build/Release/bin --target jak2-sound-rpc-test --parallel 2
ctest --test-dir build/Release/bin -R '^jak2-sound-rpc-test$' --output-on-failure
```

Both passed. The test covers nonzero synthetic VAG mixer samples, long-stream
buffer wraparound, pause/resume, natural completion, and simultaneous stereo
streams. Logs: `jak2-audio-build.log`, `jak2-audio-tests.log`. This does not
establish audible output through the simulator's AVAudioEngine path.

The maintainer changed worker routing after the completed Cursor audit:
subsequent work uses Astra. No further Cursor work was dispatched.

## Local game-data readiness

The existing `Jak2/projdata/out/jak2` directory outside the source worktree is
about 2 GiB and contains 22 of the current bounded manifest's 23 required
files. It is missing `iso/VAGWAD.ENG`. A targeted read-only metadata search of
the established local prepared-data/build roots found no complete alternative.
No asset contents were read into reports, copied, or uploaded. Do not weaken
readiness checks or use a placeholder archive to make this candidate pass.

The rebuilt real importer has now created a fresh checked candidate at
`/private/tmp/goalpad-jak2-github-validation/jak2-prepared`. It contains exactly
`iso/` (567 files) and `fr3/` (147 files), with no remaining hidden work tree.
`VAGWAD.ENG` is 493,027,328 bytes and `VAGDIR.AYB` is 65,552 bytes. All 23 files
in the app's current bounded manifest are present, regular, and nonempty.
The real oracle also validated the full base-retail output contract. This is
import evidence, not proof of runtime compatibility or complete playability.
The incomplete old directory was not modified.

## Next execution gate

1. After installation approval, restore the missing Apple Metal component and
   rerun the exact simulator build without disabling shader compilation.
2. Install the real unified app on the dedicated simulator. Use the fresh
   checked local candidate above with isolated test saves; separately exercise
   the app's import UI to measure simulator progress and cancellation.
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
