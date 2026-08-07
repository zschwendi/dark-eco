# Jak II manual completion runbook

This is the single-owner path for bringing Jak II to the same platform
readiness as Jak 1, with optional conversational LLM help but no delegated
agents. Work in small verified checkpoints and keep the result mergeable for
the Eco integration owner.

## Boundaries and current state

- Parent worktree: `GP-jak2-real-dma-draw`
  - branch: `agent/jak2-real-dma-draw-parent`
  - verified base: `9577f29c`
- Nested OpenGOAL worktree: `GP-jak2-real-dma-draw/OpenGOAL`
  - branch: `agent/jak2-real-dma-draw-proof`
  - verified title checkpoint: `7cbd59272`
- Canonical Mac build: `/private/tmp/GOALPad-jak2-real-dma-host`
- Canonical simulator build: `/private/tmp/GOALPad-jak2-m5-xcode`
- Approved routine simulator: iPad Pro 11-inch (M5), UDID
  `96C5C21A-B925-4213-82A3-90DCB8518339`
- Prepared Jak II data is user-local and must never be committed, copied into
  artifacts, or enumerated in logs.

Stay inside the GOALPad tree except for the existing toolchains, Codex state,
and temporary build/artifact paths already used by the project. Do not modify
the Jak 1 lane. Do not reset, clean, rebase, or overwrite either worktree.
Generated AOT output is not a source commit.

At this checkpoint the live runtime, input, audio, AOT pack, Metal command
submission, and simulator presentation work. Fresh state reaches the real Jak
II city title and visibly renders `Press the Start Button`. The source fix
64-byte-aligns the title's exact-size external-art buffer, and the Metal
`PROGRESS` Direct binding exposes the title prompt. No diagnostic PMODE clamp
or injected controller pulse remains.

Maintainer Start/X navigation, audible-output perception, lifecycle acceptance,
and new-game entry remain the Stage 9 exit gates. Bucket 318
`DEBUG_NO_ZBUF1` still defers the initial raw-image splash; treat it as known
renderer debt unless it blocks navigation or gameplay.

## Start every session by recovering exact state

```sh
cd /Users/zach/Developer/OS_Projects/GOALPad/GP-jak2-real-dma-draw
git status --short --branch
git log --oneline --decorate -5
git submodule status
git -C OpenGOAL status --short --branch
git -C OpenGOAL log --oneline --decorate -8
git diff --submodule=log
git -C OpenGOAL diff --check
```

Read `AGENTS.md`, `docs/PROJECT_OVERVIEW.md`, the latest `HANDOFF.md` Jak II
checkpoint, and the current `ROADMAP.md` section. Preserve all dirty files
until each line is understood. Keep one integration owner, one canonical build
directory per platform, and no simultaneous heavy builds.

## Stage 9 exit: recognizable title and navigation

1. Remove diagnostic-only mutations before making the real fix: forced PMODE
   alpha, injected controller pulses, and unproven GOAL defaults.
2. Add the smallest telemetry needed to identify where the title process is
   waiting. Prefer process/state counters over per-frame logs.
3. Trace the normal Jak II title sequence through settings load, memory-card
   status, scene-player startup, `bg-a`, and PMODE updates.
4. Correct the first source-faithful state or platform contract that differs
   from normal OpenGOAL behavior. Preserve intentional fades and blackouts.
5. Fix only renderer gaps that block recognition, navigation, or gameplay.
   Record cosmetic draw-only debt with bounded telemetry and continue.
6. Regenerate the 840-object AOT pack once if GOAL source, the pack writer, or
   the embedded object graph changed. Otherwise reuse the recorded pack.

Run the focused Mac check, then one batched Eco build/check:

```sh
cd /Users/zach/Developer/OS_Projects/GOALPad/GP-jak2-real-dma-draw

GOALPAD_JAK2_DATA_DIR=/Users/zach/Developer/OS_Projects/GOALPad/Jak2/projdata/out/jak2 \
  Scripts/run-jak2-stage9-mac.sh check

GOALPAD_JAK2_DATA_DIR=/Users/zach/Developer/OS_Projects/GOALPad/Jak2/projdata/out/jak2 \
  Scripts/run-jak2-eco-sim.sh build

GOALPAD_JAK2_DATA_DIR=/Users/zach/Developer/OS_Projects/GOALPad/Jak2/projdata/out/jak2 \
  Scripts/run-jak2-eco-sim.sh check
```

Stage 9 exits only when the capture is a recognizable Jak II title, input is
consumed by the runtime, navigation works, audio is non-silent, Metal reports
no errors/drops, and fresh saves/settings do not change the result. A merely
nonblack frame is insufficient.

The automated title checkpoint is recorded at nested commit `7cbd59272`.
`Scripts/run-jak2-eco-sim.sh build` and `check` passed, and the later visible
capture is `/private/tmp/goalpad-jak2-progress-menu-20260806.png`. The strict
check artifacts are
`/private/tmp/goalpad-jak2-eco-check-20260806-215422-60254.log` and
`/private/tmp/goalpad-jak2-eco-check-20260806-215422-60254.png`.

Then run `Scripts/run-jak2-eco-sim.sh play` and personally verify Start/X,
controller navigation, audio, one background/foreground cycle, and starting a
new game. Enter Stage 10 immediately when these pass; do not wait for cosmetic
renderer parity.

## Stage 10: controlled gameplay slice

Advance one blocking subsystem at a time in this order:

1. Stable gameplay entry, camera, movement, collision, and animation.
2. Level streaming and transitions needed by the controlled slice.
3. Blocking renderer families; keep cosmetic effects deferred and measured.
4. Gameplay audio, pause/resume, controller reconnect, and lifecycle recovery.
5. Settings, save/load, import/data discovery, and failure recovery using the
   established Jak 1 platform seams where applicable.

For every slice:

1. Reproduce one concrete failure from a fresh save/settings directory.
2. Identify the narrowest owning layer and change only that layer.
3. Run `git diff --check`, a changed-file parse/compile check, and the smallest
   focused test.
4. Batch reviewed slices before one full AOT/Metal/Xcode checkpoint.
5. Record the exact command, result, first useful failure, and artifact path.
6. Commit verified work before starting a new subsystem.

Do not use long speculative test matrices. Stop when the current gate passes
and move to the next visible blocker.

## Jak 1-equivalent readiness matrix

Jak II reaches the current Jak 1 platform level only after all applicable rows
have direct evidence:

| Area | Required evidence |
| --- | --- |
| Boot/title | Repeatable recognizable title from fresh state |
| Gameplay | New game reaches a controlled playable area |
| Renderer | Geometry, characters, UI, camera, and blocking effects are correct enough to progress |
| Input | Controller navigation/gameplay, reconnect, pause, and required touch mapping |
| Audio | Music, effects, dialogue, volume/settings, interruptions, and resume |
| Streaming | Required levels and transitions load without stalls or corruption |
| Settings | Shared Eco/Jak 1 settings behave equivalently where applicable |
| Saves | Save, load, relaunch recovery, and invalid/missing-state handling |
| Lifecycle | Background/foreground and repeated launch do not duplicate or corrupt the runtime |
| Data/import | User-owned prepared data is detected and validated without bundled retail assets |
| Stability | Sustained gameplay has no crash, runaway memory, or recurring renderer/runtime errors |
| Performance | Frame pacing, memory, temperature, and audio remain acceptable on authorized hardware |

Simulator evidence is integration evidence, not physical-device proof. Access
to `Z iPad Pro` requires explicit permission in the current request. After
authorization, separately record signed build, install, launch, controller,
audio, lifecycle, save/import, performance, thermal, and sustained-play
results. Do not claim physical or release readiness before that gate passes.

## Commit and Eco handoff

Commit nested OpenGOAL first, staging only reviewed Jak II files:

```sh
cd /Users/zach/Developer/OS_Projects/GOALPad/GP-jak2-real-dma-draw/OpenGOAL
git diff --check
git status --short
git add <reviewed-files>
git commit -m "fix(jak2): <verified checkpoint>"
git rev-parse HEAD
```

Then commit only the parent gitlink and checkpoint documentation/scripts:

```sh
cd /Users/zach/Developer/OS_Projects/GOALPad/GP-jak2-real-dma-draw
git diff --submodule=log
git add OpenGOAL HANDOFF.md ROADMAP.md <reviewed-files>
git commit -m "jak2: record <verified checkpoint>"
git show --stat --submodule=log --oneline HEAD
git status --short
git -C OpenGOAL status --short
```

Give the main Eco integrator both commit SHAs, both branches/worktrees, exact
validation commands/results, artifact paths, remaining dirty files, and the
physical-device status. Do not hand off a nested commit without its parent
gitlink commit. Do not push, alter remotes, install on a physical device, or
make a distribution claim without separate authorization.

Release is a later gate: clean reproducible builds, normal signing, documented
supported configurations and limitations, user-owned data separation, no
proprietary artifacts, authorized physical evidence, and maintainer approval.
