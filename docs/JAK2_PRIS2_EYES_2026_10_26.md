# Jak II PRIS2 eye uploads — October 26, 2026

Status: **Experimental; the reproduced fortress cutscene rejection is fixed in simulator Build 251. Full playability and physical iPad validation remain pending.** No Jak II immersive work was added.

## Reproduction and correction

The existing `fortress-save-friends-res` scene completed its authored playback in Builds 239 and 250, but the renderer rejected real drawing chains. Build 239 first failed at telemetry tick 5521; the diagnostic Build 250 first failed at tick 5161. Two source-valid PRIS2 forms were rejected:

- A third eye chunk overflowed the generic 64-transfer metadata capture. The capture held two complete chunks and seven transfers from the next one. Three chunks require 86 transfers.
- Two high-resolution eye chunks wrote the same pair in one PRIS2 producer. The original game and upstream OpenGL draw these in order; the later write replaces the earlier one before that producer's Merc consumer.

The original `update-eyes` in `goal_src/jak2/engine/gfx/foreground/eye.gc` visits six arrays of sixteen controls. Distinct destination slots do not bound the number of emissions. The PRIS2 reader now owns up to 96 chunks and 2597 transfers in source order. Its larger capture and per-frame plans live in the heap-owned host object. Ordinary captures retain their 64-transfer capacity, and the existing per-level/common PRIS grammar remains unchanged.

The executor permits a later same-resolution write from the same audited PRIS2 producer. Each eye pass clears and redraws its target; the later pass replaces the prior contents in place. Cross-producer texture versioning remains intact. The planner and execution checks still reject malformed or unsupported envelopes, same-pair mixed resolutions, and invalid producer ordering. The existing partial low/high-resolution VRAM alias limitation is not resolved by this patch.

The copied and live plans continue to own every chunk, compare their order and semantic fingerprints, and reject mutations in later or overwritten chunks. The opt-in rejection diagnostic logs protocol metadata only, at most two distinct reasons and 64 transfer headers. No game data was added to source.

## Validation

From the canonical unified v2.0 integration tree, native base `090fd6c23b3580e56f3a2ad397a27c3fd50dba0d`, now preserved as native checkpoint `d144b76825a63556511c05dec74047395f8fab1a`:

```sh
cmake --build OpenGOAL/build/Release/bin --target \
  jak2-common-tfrag-texture-upload-capture-test \
  jak2-pris2-bucket228-plan-test jak2-metal-eye-renderer-test --parallel 2
ctest --test-dir OpenGOAL/build/Release/bin \
  -R '^(jak2-common-tfrag-texture-upload-capture-test|jak2-pris2-bucket228-plan-test|jak2-metal-eye-renderer-test)$' \
  --output-on-failure
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Release -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=E033177B-9F6B-48E2-B99F-CF81DB39EF80' \
  -derivedDataPath /private/tmp/GOALPad-jak2-github-derived \
  -jobs 2 CODE_SIGNING_ALLOWED=NO GOALPAD_BUILD_JOBS=2 \
  CURRENT_PROJECT_VERSION=251 build
```

- Focused build: PASS, 56.605 seconds.
- Tests: PASS, 3/3. This includes a real Metal GPU pixel check that the later same-producer eye write wins, plus existing cross-producer and invalid-duplicate checks.
- Simulator app build: PASS, 44.989 seconds, Xcode 27.1. Installed version verified as 2.0 (251).
- Same fortress scene: PASS, 145.089 seconds. Final recorded chain counters were `11641/11641/0`; failed chains stayed zero. Five content-bearing stills were visually reviewed. Save hashes before and after the scene matched.
- Normal Build 239 gameplay separately verified creating a new Game 2 save, fully terminating/relaunching the process, and loading that save back to the prison checkpoint. The original Game 1 and bank metadata were unchanged. No ordinary mission completion is claimed.

Exact command arrays, logs, source-patch identity, installed executable/framework identities, private screenshots and save receipts are retained outside version control in the workspace's `.agent-builds/jak2-playability-20261026/`.

## Remaining gates

- Generic iOS app compilation: PASS, 697.722 seconds wall time (Xcode reported 693.600 seconds). Signing was disabled and no device was accessed. The exact command matches the simulator build above with `-sdk iphoneos` and `-destination generic/platform=iOS`.
- Build 251 is an unsigned simulator build, not a signed physical-device delivery. No physical iPad was accessed.
- Complete normal mission progression, death/retry and save checks beyond the current prison checkpoint. Scripted scene playback is separate evidence.
- Investigate the observed vertically flipped world behind the pause ring and light-mode settings label contrast without speculative renderer edits.
- Reconcile verified source checkpoints to the Mac mini once its local macOS sign-in restores remote access.

An actual local Claude Code Opus 5.5 worker authored the proposed renderer patch in scratch. Codex reviewed and integrated it, corrected a diagnostic counter/include, and owned all canonical builds and GPU/simulator validation. The worker lost API connectivity before its final report. A proposed independent mini review did not start because remote login reported that macOS was locked.
