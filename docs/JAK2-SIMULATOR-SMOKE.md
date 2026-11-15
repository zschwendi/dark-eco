# Jak II simulator smoke procedure

This developer procedure exercises authored mission starts and rendering environments with
user-owned game data. A mission-start smoke test enters a task through its authored
`play-continue`; it does not play or complete that mission. A cutscene sweep separately
exercises Scene Player playback and return to the progress menu. Neither establishes full
campaign progression, save/load correctness, controller behavior, audible audio, visual
fidelity, or physical iPad compatibility. Record those acceptance gates separately.

## Prepare an isolated fixture

Use a dedicated, explicitly identified simulator with no personal iCloud account. Before its
first app launch, disable `jak2ICloudSavesEnabled` and
`jak2ICloudPresentationSettingsSyncEnabled`; disable the Jak 1 equivalents
`iCloudSavesEnabled` and `iCloudPresentationSettingsSyncEnabled` as well. These preferences
default to enabled when absent. Keep the original user data and saves untouched; use independent
copies or copy-on-write clones inside the dedicated app container, never writable links to originals.
The Jak II save directory is `Library/Application Support/OpenGOAL/jak2/saves` in that container.
Record fixture hashes and source identity before testing. Do not commit retail data, saves,
captured game imagery, or generated prepared data to the repository.
Complete any first-launch guide acknowledgment in the dedicated fixture before automated runs;
an unacknowledged guide can prevent the test session from starting.

Build/install the unified app using [BUILDING.md](BUILDING.md), with matching public source
objects, generated AOT code, and native runtime. The test-hook generation checkpoint pins the
840-object source pack to `4f3e512e091fae63` (Build 290 race-stack correction;
Build 289 used `007055c0f2867a88`); AOT preflight and pinned-pack verification were
checked for that generation. This is generation evidence, with no full-runtime validation
attached to that record. An older pack cannot exercise the new GOAL task hook. Refresh only the
fixture's prepared public objects to match the tested app, retaining the user's original assets.
Record app/native commits, dirty patches, build number, pack identity, simulator runtime and UDID.

## Run authored task starts

Run from the app repository root. The scripts require an already booted simulator, installed app,
and prepared fixture; they do not build, install, boot, or shut down the simulator.
`SIM` is its explicit UDID; `OUT` is an absolute directory outside source control for this run.
Every runner artifact directory must be new.

```sh
python3 Scripts/jak2-task-smoke.py --self-test
sh Scripts/run-jak2-task-smoke.sh --self-test
Scripts/run-jak2-task-smoke.sh --simulator "$SIM" \
  --bundle-id com.zephyrstudiosllc.eco --process 'Dark Eco' \
  --artifacts "$OUT/tasks-1x" --timeout 180 --dwell-seconds 10 --frame-diagnostics \
  -- fortress-escape=prison city-help-kid=ctyslumb ruins-tower=ruins \
     atoll-water=atoll fortress-dump=fordumpa city-krew-delivery=ctysluma
```

The reviewed static inventory contains 98 playable task rows across 48 distinct primary levels.
It derives from `game-task.gc`, `game-task-h.gc`, `progress-static.gc`, and `level-info.gc` under
`OpenGOAL/goal_src/jak2/engine`. Keep the source-only inventory JSON with the run receipts and
recheck its recorded source hashes against the tested checkout. `INVENTORY` below names that file;
its task rows contain `name`, `play_available`, and `play_level`. This runs one representative per
primary level; replace `levels` with `tasks` for all 98 starts, including repeated environments.

```sh
python3 - "$INVENTORY" "$SIM" "$OUT/levels-1x" levels <<'PY'
import json, subprocess, sys
rows = [r for r in json.load(open(sys.argv[1]))["tasks"] if r["play_available"]]
assert len(rows) == 98 and len({r["play_level"] for r in rows}) == 48
if sys.argv[4] == "levels":
    rows = list({r["play_level"]: r for r in reversed(rows)}.values())
raise SystemExit(subprocess.run([
    "Scripts/run-jak2-task-smoke.sh", "--simulator", sys.argv[2],
    "--bundle-id", "com.zephyrstudiosllc.eco", "--process", "Dark Eco",
    "--artifacts", sys.argv[3], "--timeout", "180", "--dwell-seconds", "10",
    "--frame-diagnostics", "--", *[f'{r["name"]}={r["play_level"]}' for r in rows]
]).returncode)
PY
```

The runner sets `GOALPAD_JAK2_DEBUG_PLAY_TASK` once per fresh process. Success requires the exact
resolved GOAL `result=spawned` task/continue marker, `mode=game`, the expected **active** level,
checked `smoke-target=1/1`, and increasing ticks, completed chains/commands, acquired and submitted drawables
across at least three observations spanning the requested wall-clock dwell. A queued request,
responsive overlay, desired level, or nonempty target name alone is insufficient.
The renderer excludes `addPresentedHandler` on simulator, so presentation callbacks remain zero;
the checker reports them unavailable and uses drawable/command progress. Drops and errors still fail.
Zero callback-derived drops do not prove the absence of dropped frames on simulator.
This follows the simulator contract in `OpenGOAL/game/kernel/core/jak2_metal_presenter.mm` and
does not establish physical display presentation.

## Cutscenes, audio and resolution

Use scene request names from the authored scene inventory, separately from task names:

```sh
Scripts/run-jak2-scene-sweep.sh --simulator "$SIM" \
  --bundle-id com.zephyrstudiosllc.eco --process 'Dark Eco' \
  --artifacts "$OUT/scenes-1x" --timeout 240 -- city-help-kid-intro
```

Only when simulator hardware audio output is unavailable, opt in before either runner with
`export SIMCTL_CHILD_GOALPAD_SIMULATOR_MANUAL_AUDIO=1`. The simulator-only
`GOALPAD_SIMULATOR_MANUAL_AUDIO=1` path runs the real mixer through offline AVAudioEngine
rendering and discards the PCM. Its pull/produced-frame counters can exercise audio-clock
progress; it provides no audible-audio acceptance or hardware performance evidence. Record
this mode explicitly and unset the exported variable for normal hardware-output tests.

Run 1x and 2x as separate batches with fresh artifact directories and otherwise identical
settings/fixtures. Select Jak II's scale in settings (`jak2InternalResolutionScaleV2`), recording
Fit to Screen, frame-rate mode and actual drawable/internal dimensions. Do not infer dimensions
from the selector: frame-timing diagnostics require an orderly inactive/background/shutdown
transition to write `Documents/Diagnostics/jak2/frame-timing.json`; termination alone may not flush it.

## Review evidence

Each task keeps launch/stdout/stderr/unified logs, polling observations, three screenshots,
visual selection, before/after save manifests and `result.json`. The batch emits `summary.tsv`
and `summary.json`, records failures, and continues with a fresh process; any failure makes the
batch exit nonzero. Native/Metal/stack/foreground errors, failed progression, missing required
telemetry, process death, screenshot failures and save mutations fail the task. Hash snapshots
occur with gameplay stopped. A changed fixture save is evidence to investigate, not permission
to restore or overwrite the user's originals. Screenshot non-black checks are triage only;
inspect the images and log context, including legitimately dark scenes, before classifying results.
Record coverage actually observed, unresolved failures, audio mode and source/build identities;
never turn the 98-task/48-level inventory or a green smoke summary into campaign completion.
