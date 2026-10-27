# Jak II ordinary-play baseline before immersion

Status: **The scoped ordinary rendering, asset and audio gate is complete.** Jak II remains experimental. This permits starting immersion work; it does not certify a complete game playthrough or physical-device performance.

The maintainer owns broad gameplay verification. The agreed agent gate covers reproducible visual, missing-asset, rendering and audio defects, without requiring every mission, vehicle route or checkpoint to be completed first.

## Summary

- Corrected the reproduced PRIS2 and common PRIS eye-upload forms while preserving strict malformed-packet rejection.
- Corrected the inverted paused-world copy and implemented ordered Fortress map layers and typed player icons.
- Replayed the final map-to-gameplay transition twice in simulator Build 266, with the full map/player arrow visible and no rejected rendering chains.
- Verified real native PCM production and streaming in Build 268. Split the existing audio counters out of an overlong diagnostic message and sampled crossed frame intervals so batched frames cannot skip the readout. This changes developer diagnostics, not the mixer or renderer.

## Evidence against the gate

| Requirement | Evidence |
| --- | --- |
| Ordinary title, scene assets and gameplay render | Actual title/intro and prison captures; sustained zero-failure runtime counters. The prison props previously suspected missing were visibly present. |
| Pause preserves world orientation | Matched source A/B, repeated ring/submenu captures and synthetic Metal orientation checks in [the pause report](JAK2_PAUSE_ORIENTATION_2026_10_26.md). |
| Fortress map layers and player icon render | Ordered-layer CPU/GPU checks and actual repeated map entries in [the map report](JAK2_MAP_UPLOAD_2026_10_26.md). |
| Returning from the map does not reject the observed eye-only packet | Strict 57-transfer CPU/Metal proof and two successful actual map returns in [the common PRIS report](JAK2_COMMON_PRIS_EYE_ONLY_2026_10_26.md). Build 266 reported zero failed chains through tick 27002. |
| Audio output produces real samples | Build 268 produced/requested 731648, 1193472 and 1675264 frames at 48000 Hz, with nonzero cumulative peaks 5758/5761/5761. This observes actual returned PCM, not merely a linked audio seam. |
| Streamed audio reaches and advances through the playback ring | A live 44100 Hz source stream had nonzero ring/voice state, advances increasing from 287 to 1157, and zero invalid reads/stalls in the captured run. This is distinct from the 48000 Hz output mixer rate. |
| Required English audio data is present | Installed user-local `VAGWAD.ENG` is 493027328 bytes and `VAGDIR.AYB` is 65552 bytes. No retail data is in this repository. |
| Existing saves and per-title state survive | The existing Game 4 loaded normally; all six save-bank hashes remained unchanged through Builds 266–268. Temporary developer settings were restored byte-for-byte with the original modification time. |

## Files changed

The renderer changes and tests are described in the three linked reports. Native checkpoint `0ac5b269c0a9e72a8dd7a1923ab0f22368d4c223` contains the final common PRIS correction. Outer checkpoint `f98ff9bf0f5e33e4e151d24420849d2c6f237b35` contains the diagnostic corrections in `GOALPad/Game/GameSession.swift` and is the clean source used for simulator Build 268.

## Validation

- Native host and affected CPU/Metal targets built successfully. The final common PRIS/PRIS2/Metal-eye group passed 3/3; the preceding sound-RPC/capture group passed 3/3. The map integration group passed 6/6, with its subsequent icon-planner checks passing 2/2. Those preserved results were inspected; unchanged native checks were not needlessly rerun for the Swift diagnostic changes.
- `git diff --check` and `xcrun swiftc -frontend -parse GOALPad/Game/GameSession.swift` passed for both diagnostic patches.
- Release simulator Builds 266, 267 and 268 passed. Build 268 took 48.19 seconds and used the source identities above. Build 267 exposed the skipped exact-modulo diagnostic sampling; Build 268's actual runtime logs verify the interval-crossing correction and short audio message.
- Only the approved isolated iPad simulator was installed/launched. It was stopped and shut down after validation. No physical iPad or Vision Pro was accessed for these checks.

Exact machine-specific commands, identities, scalar logs and screenshots remain in the ignored workspace evidence directory `.agent-builds/jak2-playability-20261026/`. Key receipts are `pris266-map-replay-result.json`, `pris266-replay-safe-stop.json`, `audio268-build-command.json`, `audio268-build-result.json` and `audio268-runtime-result.json`.

## Not validated

Every voice/music cue, every later level and a full game playthrough were not checked. These remain part of maintainer playtesting. The PCM peak is cumulative over the audio-output lifetime; it does not prove that a particular voice was heard or that a physical speaker/controller route works.

Build 268 is a simulator artifact, not a signed device delivery. The headset remains on the separately installed Jak 1 experimental Build 264 during the maintainer's trial.

## Risks and next step

Bring the verified ordinary Jak II changes into the Vision source before adding the immersive adapter. Keep the current Jak 1 experiment and canonical copies intact. Future Jak II/Jak 3 immersion requires a standard DualSense; ordinary supported touch and keyboard paths remain available. No Jak II immersion was added by this checkpoint, and the separate Jak 1 black-sky issue remains open.
