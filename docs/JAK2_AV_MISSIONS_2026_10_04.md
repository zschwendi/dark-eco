# Jak II rendering, audio, and mission checkpoint

Status: **Partially complete.** Work remains on the real unified Dark Eco 2.0
app, outer `codex/jak2-github-playability`, with nested OpenGOAL `v2.0`.
The maintainer confirmed movement previously worked and prioritized rendering,
audio, and mission start/end. No input behavior was changed in this checkpoint.

## Changes

- `ccc713e1a`: bucket 322 now executes source-shaped HUD/font packets through
  the existing Metal Direct renderer after live/copied semantic plans agree.
  The parser recognizes the authored terminal `default-end-buffer` reset;
  unknown or malformed content remains passive. Before/after simulator captures
  prove the previously missing Naughty Dog card, subtitle-toggle prompt, and
  subsequent Jak II logo are restored.
- `090fd6c23`: extends the same guarded path to exact source font-only chains
  with a terminal reset. Unresolved text and subtitle-image uploads stay passive.
  The Sony opening text and subtitle prompt are visibly restored in a separate
  before/after capture before the Naughty Dog card appears.
- `4ed6ff53f`: connects the previously empty `snd_SetSoundPitchBend` function
  to the existing locked 989snd handler. Positive, negative, and reset-to-zero
  RPC commands now produce the same PCM as equivalent initial pitch bends.
  This affects block SFX through the shared sound shim, including Jak 1 callers;
  no new synthesis or resampling implementation was introduced.
- `e2735ae9b`: bounded, read-only mission observation, using asserted GOAL
  object layouts and type checks. `GOALPAD_JAK2_MISSION_STATE` logs changes to
  fortress-escape entry/completion and the 67 story-task completion count.
  No public runtime ABI or game progression was changed.
- `284eb66ae` plus `TargetSupport/Jak2/EcoJak2RuntimeBridge.mm`: opt-in bounded
  packet-envelope capture and existing typed-plan metrics. Captures contain
  metadata, not texture or game-asset payloads.

The changes belong in nested OpenGOAL because that repository owns the renderer,
GOAL memory reader, and sound engine. App-only logging stays in the outer bridge.
No dependency, generated GOAL code, retail data, or save was committed.

## Validation

From the integration checkout:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Release -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=E033177B-9F6B-48E2-B99F-CF81DB39EF80' \
  -derivedDataPath /private/tmp/GOALPad-jak2-github-derived \
  -jobs 2 CODE_SIGNING_ALLOWED=NO GOALPAD_BUILD_JOBS=2 build
sh Scripts/run-game-lifecycle-check.sh
sh Scripts/run-native-runtime-router-check.sh
git diff --check
git -C OpenGOAL diff --check
```

Combined HUD/audio/mission simulator build: **PASS**, 60.499 seconds. Both
Jak 1 app sound objects and the Jak II runtime sound objects rebuilt. Lifecycle
and runtime-router checks: **PASS**.
Final font extension simulator build: **PASS**, 45.066 seconds; installed and
launched successfully on the same isolated simulator.

From nested OpenGOAL:

```sh
cmake --build build/Release/bin --target jak2-sound-rpc-test --parallel 2
ctest --test-dir build/Release/bin -R '^jak2-sound-rpc-test$' --output-on-failure
cmake --build build/Release/bin --target jak2-runtime-metrics-reader-test --parallel 2
ctest --test-dir build/Release/bin -R '^jak2-runtime-metrics-reader-test$' --output-on-failure
```

Sound: **PASS 1/1**. Four PCM assertions failed before the wiring fix and pass
after it. Mission reader: **PASS 1/1**, covering not-started, entered, complete,
optional-task exclusions, no mutation, wrong type, false pointers, and truncation.

Renderer worker checks, reviewed before cherry-picking:

```sh
cmake --build /tmp/GOALPad-subtitle322-hud-direct \
  --target jak2-subtitle-bucket322-plan-test jak2-metal-bucket-table-test \
  jak2-metal-host-bridge-test -j 2
ctest --test-dir /tmp/GOALPad-subtitle322-hud-direct \
  -R '^(jak2-subtitle-bucket322-plan-test|jak2-metal-bucket-table-test|jak2-metal-host-bridge-test)$' \
  --output-on-failure
```

**PASS 3/3**, including corrupt glyph/reset rejection and unknown content
remaining passive. The fixtures are synthetic and source-derived. They do not
contain copied retail packet payloads.

## Simulator evidence

Local artifacts are outside Git under
`../.agent-builds/jak2-av-missions-20261004/`:

- `typed-intro/card.png`: before, black at aframe 226.787.
- `combined-intro/card.png`: after, Naughty Dog card and subtitle-toggle prompt
  at aframe 225.820.
- `combined-intro/scene.png`: Jak II logo over rendered village at aframe 477.978.
- `combined-intro/runtime.log`: at tick 4320, typed plans matched 4320 times,
  rejected 0, mismatched 0; the guarded route executed 715 times.
- `font-before/prompt.png`: before the font-only extension, black at aframe
  103.594. `font-after/prompt.png`: Sony opening text and subtitle prompt at
  aframe 123.428. The final card and scene captures are aframe 231.914/468.047.
  At tick 3960, all 3960 typed plans match, with 0 rejects/mismatches and 985
  executions for 985 present buckets.
- `ordinary-save-recognized.png`, `ordinary-prison-reloaded.png`,
  `prison-stdout.log`, `prison-stderr.log`: normal Library → Start → Load Game →
  Game 1 → Confirm returns to prison. At tick 13339 the observer reports
  `fortress-escape state=entered start_frame=308735 story_complete=0 story_total=67`.
- `preview-save-check.json`: the existing 133120-byte save remained unchanged
  through the HUD preview, SHA-256
  `94c0502937000df58a4c1da8125347040dbaf0249af4c715d00ce364ab2d292a`.
  `final-save-check.json` confirms the same bytes after the ordinary reload and
  final font capture. Task-owned capture streams stopped and the simulator was
  shut down after validation; the final built app remains installed.
- `audio-pitch-before.log`, `audio-pitch-fixed-test.log`, `mission-reader-test.log`,
  `combined-simulator-build.log`, and `font-simulator-build.log` retain results.

The previous report's inference that the card itself used an unknown qwc10
setup was incorrect. The complete typed plan now recognizes source font/HUD
packets plus the terminal qwc10 reset. Before reset support the first rejection
was index 150; during the card it shifted by three transfers to 153. The first
64-entry envelope capture alone did not establish a complete glyph count.

## Not validated / remaining work

- Full playthrough, mission completion and subsequent mission transitions,
  later levels, and complete visual fidelity are still unverified. The live
  mission log proves saved task entry, not completion. The reader fixture's
  complete bit is synthetic and must not be presented as a completed mission.
- Sound regression checks prove PCM behavior. They do not constitute listening
  acceptance of music/dialogue balance or physical output. Reverb application,
  automatic pitch ramps, and MIDI/Ame live pitch-bend handlers remain existing
  gaps; this checkpoint only fixes direct block-SFX pitch bend.
- Subtitle-image upload/CLUT families remain passive and need a separately
  proven renderer contract. Do not broaden the guarded path to arbitrary DMA.
- No physical iPad was accessed. No new signed device build, Mac runtime,
  Jak 1 gameplay, publication, or push was performed.
- The `jakb-lod0` bone-42 finite degenerate-matrix warning is diagnostic-only:
  matching source/expected palette bases and later draw calls do not prove a
  rendering failure. Preserve it as evidence; do not replace authored matrices
  or disable draws merely to remove the warning.

Next: preserve these verified fixes, reproduce a specific mission close/retry
failure using the read-only task signal, and test remaining rendering/audio
families against a concrete live capture. Do not return to the rolled-back
HUD-only hypothesis or diagnose movement as broken from short automated inputs.
