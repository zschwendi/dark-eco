# AGENTS.md

This file defines the operating rules for coding agents working in this repository.

Read `docs/PROJECT_OVERVIEW.md` before planning or changing code. That document defines the project mission, architecture, legal boundaries, scope, and non-goals. When a prompt, issue, generated plan, or other document conflicts with it, `docs/PROJECT_OVERVIEW.md` takes priority unless a maintainer explicitly changes the project direction.

## Project objective

Build a native ARM64 iPadOS platform port of OpenGOAL for user-supplied, legally obtained Jak game data.

The first supported game is **Jak and Daxter: The Precursor Legacy**. Jak II
and Jak 3 are follow-on scope only after Jak 1 is complete, or after the port
has reached physical playtesting and physical playtesting is the sole remaining
Jak 1 blocker while all earlier platform/runtime work is healthy. Do not use
the follow-on games to bypass an earlier unresolved Jak 1 platform problem.

This project is not a PS2 emulator, a Swift rewrite of OpenGOAL, a remake, or a repository for copyrighted game assets.

## Required agent behavior

Before editing:

1. Read `docs/PROJECT_OVERVIEW.md`.
2. Inspect the relevant existing code, build scripts, tests, and upstream conventions.
3. Identify the narrowest change that advances the requested task.
4. Determine which existing targets and tests must remain healthy.
5. Do not assume an API, platform capability, compiler behavior, entitlement, or file format without verifying it in the repository or authoritative documentation.

While editing:

1. Preserve working behavior.
2. Prefer focused patches over broad refactors.
3. Keep Apple-specific code isolated behind clear platform boundaries.
4. Preserve upstream OpenGOAL compatibility where practical.
5. Avoid changing unrelated files.
6. Do not delete, rename, reorganize, or reformat unrelated code.
7. Do not add speculative abstractions for unimplemented future features.
8. Do not suppress compiler errors, warnings, failing tests, or unsupported behavior with placeholders presented as complete.
9. Keep the project buildable after every meaningful change.

After editing:

1. Build every affected target available in the current environment.
2. Run the relevant tests.
3. Report the exact commands run and their results.
4. State clearly what was not tested and why.
5. Summarize changed files and behavior.
6. Call out remaining risks, temporary workarounds, and follow-up work.

## Long-running work and delegation

Use subagents whenever bounded work can proceed independently. Keep all four
available concurrency slots productive when there are useful non-overlapping
tasks. Use one `gpt-5.6-sol` `xhigh` integration lane and up to two
`gpt-5.6-sol` `xhigh` implementation lanes for importer architecture,
renderer behavior, ABI/AOT work, unsafe file handling, and other ambiguous or
high-risk changes. When available, prefer `gpt-5.6-luna` at `max` (or `high`
for very narrow work) for bounded builds, test execution, simple validated
commands, CMake wiring, documentation, fixture expansion, build-log triage,
formatting, and mechanical API plumbing. Have Sol xhigh review Luna's exact
patch and first useful failure before integration whenever the result affects
architecture or product behavior. If Luna is not exposed in the current agent
model picker, use `gpt-5.6-terra` `high` for those bounded lanes and record the
fallback honestly; never claim Luna ran when it did not. Editing subagents
should use dedicated branches and worktrees where practical; never let agents
edit the same files concurrently. The primary agent must review and validate
every subagent result before integration.

Avoid duplicated validation work:

1. Each worker runs only `git diff --check`, changed-file parse or compile
   checks, focused unit tests, and the smallest isolated compile for its patch.
2. Integrate several reviewed non-overlapping commits before running the full
   compiler, Metal proof, AOT build, or Xcode matrix once per checkpoint.
3. Do not rebuild Eco for an importer-only nested OpenGOAL change that is
   not part of the Xcode target.
4. Keep one canonical OpenGOAL CMake build directory and one current Xcode
   DerivedData directory. Do not run multiple heavy C++, AOT, or Xcode builds
   simultaneously.
5. Use `ccache` through `CMAKE_C_COMPILER_LAUNCHER` and
   `CMAKE_CXX_COMPILER_LAUNCHER` for new host build directories when it is
   installed. Keep its cache bounded; do not make it a product dependency.
6. Generate the 518-object public source pack once on canonical code. Reuse its
   recorded identity unless its writer or embedded graph changes.
7. Delete obsolete reproducible build directories after recording results and
   checking that they are not source worktrees.
8. Stop speculative visual work when static review reaches a physical A/B
   gate. Continue only with a bounded deterministic test or existing diagnostic
   seam until a newly authorized capture can distinguish explicit hypotheses.

Every major feature that reaches integration is a numbered release checkpoint.
Before beginning integration of the next major feature: give the current
checkpoint the next global `CURRENT_PROJECT_VERSION` in every target
configuration, commit it, run validation proportional to the affected targets,
push the integration branch, and record the exact local/remote hash plus artifact
or pending physical gate in `HANDOFF.md`. Small corrective commits needed to make
that same feature build and pass remain part of its checkpoint; unrelated major
features do not silently accumulate under one build number. Workers never bump
the build independently.

Preserve enough state for a context wipe at all times. When context usage
reaches approximately 70 percent, or earlier when the platform does not expose
an exact percentage and the transcript is becoming large:

1. Stop starting new overlapping edits.
2. Commit every verified checkpoint and leave unverified work clearly
   identified in its dedicated worktree.
3. Update `HANDOFF.md` with exact branches, worktrees, commits, dirty files,
   commands, results, blockers, and the next executable task.
4. Recheck the parent and child Git status and preserve all uncommitted work.
5. Compact or clear context using the platform-supported mechanism, then resume
   from `AGENTS.md`, `docs/PROJECT_OVERVIEW.md`, `HANDOFF.md`, and `ROADMAP.md`.

For unattended long-running work, maintain a progress heartbeat at least every
one to two hours of active execution. Each heartbeat should confirm the active
goal, running subagents/builds, Git/worktree state, resource use, the most recent
verified checkpoint, and the next task. If a worker resumes after a lapse,
treat the resume as a heartbeat: reread the handoff and current Git state before
continuing. Use the product's persistent-goal/continuation mechanism; do not
install an OS daemon, cron job, or other external automation merely to restart
an agent unless a maintainer explicitly requests that separate system change.

Operate as an **AGI-pilled worker**: stay outcome-oriented, persistent,
self-verifying, and honest about evidence; use agents and tools to finish the
queue rather than merely narrating it. This does not weaken any safety, legal,
physical-device, validation, or authority boundary in this file.

If repeated evidence shows an item cannot be checked off without missing
authority, unavailable external state, or an unresolved architecture blocker,
stop starting later FIFO work. Commit and push every verified checkpoint,
record the exact blocker and first useful failure in `HANDOFF.md`, recheck all
worktree status, and stop the run so the maintainer can pause the persistent
goal. Never mark the goal complete to escape a wall, and never claim the goal
was paused when the current goal API does not expose a pause transition.

Treat roughly 30 percent context remaining as a hard compaction checkpoint, not
an invitation to work tired. Finish or isolate the current edit, commit and push
verified state, update `AGENTS.md` and `HANDOFF.md`, record active workers/builds,
then clear or compact context and resume from those files.

## Hard constraints

Agents must not:

- Add ROMs, ISOs, extracted retail game data, textures, models, animation, dialogue, cinematics, music, sound effects, keys, or proprietary SDK files.
- Download copyrighted game data on behalf of the user.
- Add ownership-bypass, DRM-circumvention, jailbreak, private-entitlement, or unsigned-code requirements.
- Depend on unrestricted JIT execution on ordinary iPadOS installations.
- Replace OpenGOAL with a new Swift engine.
- Begin a wholesale GOAL-to-Swift or C++-to-Swift translation.
- Add a PS2 emulator or wrap an emulator.
- Begin Jak II-specific feature work when it delays the Jak 1 platform path.
- Claim iPad compatibility based only on the simulator.
- Claim a feature works without a successful build or a clearly described manual validation.
- make legal claims or guarantees. Document technical asset separation and defer legal conclusions to maintainers or qualified counsel.

## Language and architecture boundaries

Use the existing languages where they fit:

- **Swift / SwiftUI:** application lifecycle, launcher, settings, file selection, save management, touch UI, and iPad-specific presentation.
- **Objective-C++:** narrow bridge between Swift and the native runtime.
- **C++:** OpenGOAL runtime, portable engine code, compiler/tooling integration, asset loading, renderer integration, and platform abstractions.
- **GOAL:** reconstructed game and engine logic maintained through OpenGOAL.
- **Metal and Apple frameworks:** iPad-compatible rendering, controller input, audio, storage, and system integration.

Keep the Swift-facing API small, stable, and ownership-safe. Do not expose large C++ implementation details directly to Swift.

## Preferred implementation strategy

Advance through small executable proofs in roughly this order:

1. Keep the upstream or minimally modified ARM64 macOS target healthy.
2. Compile a minimal portable OpenGOAL runtime subset for iPadOS.
3. Link that subset into a minimal SwiftUI application.
4. Initialize logging and application storage.
5. Initialize a physical-device graphics surface.
6. Receive controller input.
7. Render a test frame.
8. Load one synthetic or user-extracted asset.
9. Load static level geometry.
10. Execute a representative, signed ARM64 GOAL workload.
11. Reach the Jak 1 title screen.
12. Enter gameplay and close remaining platform gaps subsystem by subsystem.

Do not skip several milestones by introducing a large unvalidated rewrite.

## Build integrity

A task is not complete merely because code was written.

At the end of each task, preserve all targets currently documented as healthy. Depending on repository maturity, these may include:

- OpenGOAL host tools
- ARM64 macOS development build
- compiler and code-generation tests
- iPadOS static library or framework
- iPadOS application target
- importer or preparation tools

When an affected target cannot be built in the current environment, say so explicitly. Do not infer success from source inspection alone.

### Build failure policy

When the repository does not build:

1. Determine whether the failure existed before the change.
2. Fix failures caused by the current change before doing additional work.
3. Do not stack unrelated fixes unless they are required to restore the build.
4. Preserve the first useful error output in the task report.
5. Never hide a failure by disabling the target, test, warning, or code path without explicit maintainer direction.

## Testing policy

Prefer deterministic tests and synthetic fixtures that can remain in the public repository.

Use:

- Unit tests for platform-independent logic.
- Compiler/code-generation tests for ARM64 behavior.
- Synthetic assets and tiny original fixtures for loaders and rendering tests.
- Integration tests for the Swift-to-C++ boundary.
- Physical iPad validation for executable-memory behavior, Metal, controllers, audio, storage, performance, and thermal behavior.

Do not commit fixtures extracted from retail game data.

Simulator results are useful but are not proof of physical-device compatibility.

### Physical-device access

Use simulators for routine build, launch, rendering, and runtime validation.
The local **iPad Pro 11-inch (M5)** simulator is explicitly approved for
routine use without additional permission; keep its resource use bounded and
shut it down after validation when it was not already running.
Do not install, launch, attach logs, capture the screen, or otherwise test on
the physical device named **Z iPad Pro** unless the maintainer explicitly asks
for physical-device testing in the current request. Do not infer permission
from an earlier request or from the device being paired and available.

A generic signed iOS build that does not access the physical device is allowed
when needed to validate compilation and code signing. Record it as build
evidence only. When a milestone still requires physical-device evidence, leave
that gate pending and ask the maintainer to schedule it rather than accessing
the device automatically.

## iPadOS executable-code policy

Treat iPadOS code signing as a primary architectural constraint.

The default direction is ahead-of-time preparation and normal signed executable code. Runtime-generated native code must not be assumed to work on ordinary iPadOS.

Before changing compiler or runtime architecture, document:

- where GOAL code is compiled,
- what artifact is produced,
- when it is linked or signed,
- what remains data-driven at runtime,
- how code mods differ from data-only mods,
- and how the approach works on a non-jailbroken physical iPad.

Do not mark the AOT path complete until representative GOAL code executes in a signed physical-device build.

## Upstream policy

OpenGOAL is the foundation, not merely reference material.

Prefer changes that could plausibly be upstreamed:

- platform interfaces,
- portable ARM64 fixes,
- renderer abstractions,
- build-system improvements,
- tests,
- and narrowly scoped Apple-platform support.

Keep downstream-only iPad application code separated from portable upstream changes.

When modifying vendored or forked upstream code:

1. Explain why the change cannot remain outside upstream code.
2. Keep the patch narrow.
3. Avoid unrelated formatting.
4. Add or update tests where practical.
5. Record upstream commit or version assumptions when relevant.

## Dependency policy

Do not add a dependency until existing repository capabilities and Apple frameworks have been evaluated.

Any new dependency must have:

- a clear purpose,
- an iPadOS-compatible license,
- ARM64 iOS support,
- no prohibited runtime-code requirement,
- acceptable maintenance status,
- and a documented reason it is preferable to a smaller local implementation.

Avoid dependencies that duplicate large portions of OpenGOAL, introduce emulator code, or make the build materially harder to reproduce.

## Asset and import workflow

The repository must remain functional without copyrighted game assets.

Import tooling may:

- verify supported disc revisions,
- read a user-selected legally obtained image or extracted source,
- call compatible OpenGOAL extraction tooling,
- produce user-local prepared data,
- and explain unsupported revisions clearly.

Import tooling must not:

- fetch game data from the internet,
- include fallback retail assets,
- upload user game data,
- disguise unsupported or invalid data as successful,
- or commit generated retail data into the repository.

Generated user data should remain ignored by version control by default.

## Performance policy

Correctness and stable execution come before optimization.

Do not introduce unsafe caching, concurrency, SIMD, memory-layout, or rendering changes until the relevant subsystem works correctly and has a measurable bottleneck.

When optimizing:

1. Capture a baseline.
2. Change one material variable at a time.
3. Measure on physical hardware where relevant.
4. Preserve deterministic behavior and tests.
5. Document performance improvement and any tradeoff.

## Documentation policy

Update documentation in the same change when modifying:

- build steps,
- supported platforms,
- supported game revisions,
- architecture boundaries,
- import workflow,
- signing requirements,
- known limitations,
- or project milestones.

Do not describe planned behavior as implemented behavior.

Use these labels consistently where useful:

- **Implemented:** built and validated.
- **Experimental:** exists but is incomplete or insufficiently validated.
- **Planned:** agreed direction with no complete implementation.
- **Investigating:** feasibility or architecture remains unresolved.

## Task scope and commits

Each task should produce one coherent change.

Good task scope:

- Add an iPadOS-compatible logging adapter.
- Make one portable runtime component compile for arm64-apple-ios.
- Add a minimal Objective-C++ bridge and integration test.
- Add a Metal-backed test surface.
- Verify one ARM64 code-generation instruction and add its test.

Bad task scope:

- Port the entire engine to iPad.
- Rewrite the renderer, audio, input, and compiler together.
- Refactor all platform code before any iPad target builds.
- Add Jak 1 and Jak II support simultaneously.

Do not commit generated build products, user game data, signing identities, provisioning profiles, secrets, or machine-specific paths.

## Required completion report

At the end of an implementation task, report:

```text
Summary
- What changed and why.

Files changed
- Important files and their purpose.

Validation
- Exact build/test commands run.
- Result of each command.
- Physical-device validation performed, if any.

Not validated
- Anything that could not be tested and the reason.

Risks / follow-up
- Remaining limitations, architectural risk, or next smallest step.
```

Do not report “done” when required validation failed or was not performed. Use “implemented but unvalidated,” “partially complete,” or another accurate status.

## Decision priority

When choosing between approaches, use this order:

1. Legal and asset-separation boundaries.
2. Successful reproducible builds.
3. Correctness on physical iPad hardware.
4. Compatibility with OpenGOAL and its formats.
5. Small, reviewable changes.
6. Maintainability and testability.
7. Performance.
8. Convenience or stylistic preference.

## Current project priority

Until maintainers update this section, the priority is:

> Preserve Build 93 as the known-good Jak 1 baseline while building the next
> iPhone/iPad interaction and per-game settings layer in small, physically
> testable checkpoints.

Build 93 is accepted by the maintainer as the known-good baseline for gameplay,
performance, graphics, current touch behavior, settings persistence, and iCloud
saves. Its source checkpoint is `9c87b0be7fd194bb13af8033be6bb5787b2aba77`
and its preserved signed app is
`/private/tmp/GOALPad-build93-cloud-save-ux-signed/GOALPad.app`. Do not rewrite,
amend, or repurpose that branch. New work starts from Build 93 in a later build
and must not replace it until the maintainer accepts the physical comparison.
Build 105 is a rejected transition candidate, not the accepted baseline. Its
physical Sandover-to-Misty boat sequence still rendered an unloaded void and
allowed Jak to fall through; death/respawn then recovered to an intact Misty
Island with the boat correctly placed. Build 105 also showed a new iPad
letterboxing/aspect regression. Preserve Build 93/90 presentation behavior
until both failures have a separately validated replacement.

### Live Jak 1 orchestration ledger

This checklist is a tracked execution ledger, not a promise that every item
ships in one build. Update it whenever a worker begins, commits, integrates,
passes a focused gate, or reaches a physical-validation boundary. Each active
item must have one file owner; do not let workers edit the same files
concurrently. Use these states in notes where a checkbox alone is ambiguous:
`Planned`, `Investigating`, `In progress`, `Implemented`, `Validated`, and
`Deferred`.

#### Baseline and integration

- [x] Preserve Build 93 at `9c87b0be` as the immutable known-good baseline only
  within the physically exercised areas. It is not accepted for unvisited
  progression or level transitions; the Sandover-to-Misty boat transition is
  now a confirmed critical failure.
- [x] Create Build 94 integration branch `agent/build94-jak1-settings` from
  Build 93 in `/private/tmp/GP-build94-jak1-settings`.
- [ ] Record every worker branch, worktree, commit, validation command, and
  physical gate in this ledger and `HANDOFF.md`.
- [ ] Require every validated worker slice to end in a focused commit and push
  its dedicated branch before integration. Record the remote branch and exact
  pushed hash; never leave the only copy of completed worker work unpushed.
- [ ] Keep one integration owner and one heavy-build owner; batch full AOT,
  Metal, and Xcode validation after focused worker checks.
- [ ] Assign every integrated checkpoint the next global Xcode build number,
  then commit and push it from the integration branch. Parallel workers must not
  edit `CURRENT_PROJECT_VERSION`; independent branch-local bumps collide and
  make artifact identity ambiguous.
- [ ] When any lane approaches 30 percent context remaining, stop overlapping
  work, commit and push every verified slice, mark unverified work explicitly,
  update this ledger and `HANDOFF.md`, recheck parent/child status, then resume
  from a compact handoff instead of carrying the full transcript.
- [ ] Agents must test every deterministic behavior they can themselves before
  involving the maintainer: focused unit/static checks, simulator interaction,
  affected host compilation, signed generic builds, and safe device automation
  in proportion to risk. Do not use the maintainer as a substitute for a test
  the agent can run.
- [ ] Loop the maintainer in only for a material product/branding choice, a new
  authority boundary, or physical visual, ergonomic, audio, haptic, thermal, or
  gameplay acceptance that automation cannot establish.
- [ ] For this active Jak 1 interaction program, `Z iPad Pro` is authorized for
  in-place Build 94-and-later candidate installation and launch whenever it is
  unlocked and available; do not uninstall or clear its app data. This standing
  authorization does not silently extend to destructive data changes or broad
  screen/log capture unrelated to the active test.
- [ ] Never present a physical candidate blind. Before asking the maintainer to
  test, provide the exact build number, the changed behavior, a short numbered
  test route, expected results, and the Build 93 regression checks that matter.
- [ ] Physically compare the next candidate against Build 93 on iPhone and iPad
  before calling it the replacement baseline.

Active lanes:

- `Build 120 MVP candidate integrated; signed build and physical acceptance
  pending` — Build 118's physical run exposed
  missing Start/Resume chrome and missing native-menu Back actions. Parent
  `3588baf3`, `64050a11`, `c6757a51`, and `c85ce554` add exact read-only title
  and progress navigation state, restore Start at `target-title-wait`, use
  Pause in gameplay, keep a truthful Resume visible throughout pause/progress,
  expose Back only where the native responder accepts it, preserve the special
  stats Square semantics, and add an explicit Settings Done action. Controller
  suppression retains only the session Start/Resume action. Independent Sol
  xhigh re-review returned ACCEPT; focused native, touch, and presentation
  suites and the signed generic-iOS Release build pass. `e3bfa046` bumps both
  iOS configurations to 118. Build 118 was installed in place and launched on
  `Z iPad Pro` without uninstalling or clearing its app container. The
  maintainer accepted Fit to Screen but rejected the candidate: ordinary touch
  input has regressed from Build 96, and leaving/backgrounding then resuming can
  loop a black screen with the theme song while the SwiftUI/touch shell remains
  responsive. Build 119 restores the Build 96 stick geometry, two-pill layout,
  and base gesture handling while retaining crouch-left punch, pinch, SKIP,
  haptics, full-screen warp capture, and the accepted native-menu chrome. It
  removes Classic touch/editor UI while preserving old synced documents as
  inert compatibility data. Build 120 adds the independently accepted scene,
  display-link, Metal-layer, audio, and save-generation lifecycle recovery.
  Focused touch, presentation, save, and lifecycle suites pass; signed build and
  physical touch/warp/background-resume acceptance remain pending. After that,
  stop nonessential iOS settings work and prioritize true stereoscopic visionOS
  rendering.
- `Build 114 signed generic-iOS candidate ready; physical Misty/title gate
  pending` — nested OpenGOAL `352064ace`, `f260ae7df`, and `cb5032a83` make
  fisherman-boat arrival atomic: destination collision must genuinely ground
  Jak before clone exit, destination continue/title ownership, and dock-ready
  state commit. Nested `2e0438416` pins the regenerated 518-object source pack
  at aggregate `2b812636de96f221`. Parent `7d017e73` and `a2c31501` bump both
  iOS configurations to 114 and record that identity. The signed generic-iOS
  Release build passed and is preserved at
  `/private/tmp/GOALPad-build114-misty-skip-signed/GOALPad.app`; it has not been
  installed or physically accepted. Acceptance must prove the ordinary first
  Sandover-to-Misty ride, `MISTY ISLAND` on arrival only, grounded dock exit,
  no stale source interaction, and a clean return trip without the Misty title.
- `Signed Build 113 validation passed; Misty ownership trace rejected the
  candidate before physical install` — nested OpenGOAL `ef48da80a` retries a
  false animation clone, waits for the destination level to become active, and
  relocates the boat and Jak. A newer trace found that its intentional yield
  still precedes `set-continue!`, so source-level ownership remains authoritative
  during the only title/current-level reevaluation frame. The original five
  tests do not cover that semantic state. Nested `93dd44e16` and source-pack
  identity `c2fa7910dd863ae7` remain reproducible build evidence, not an
  accepted gameplay fix. Build 113 must not be installed as the Misty candidate.
- `Integrated and signed in Build 116; physical input check pending` — parent
  `23be12e8` adds a Standard/Swapped Sticks
  whole-vector controller mapping. It preserves paired X/Y stick vectors,
  existing Y normalization and trigger semantics, applies before keyboard,
  mouse, and touch merge, and participates in local/iCloud/reset persistence.
  Parent `0657614b` then adds 25–400% mouse/trackpad camera sensitivity and
  independent horizontal/vertical inversion while preserving exact 100%
  bytes, the existing accumulator clamp, one-frame consumption, remappable
  WASD ownership, and controller-first arbitration. Parent `96c24efd` bumps
  both iOS configurations to 115. Independent review and root focused input,
  Swift parse, settings UI, local/iCloud, legacy decoding, and reset checks pass.
  The generic-iOS Release build also passes and is preserved at
  `/private/tmp/GOALPad-build115-input-signed/GOALPad.app`; no device validation
  is claimed. Parent `60ddc9c0` adds independent Movement/Camera whole-vector
  sensitivity, radial dead-zone, and horizontal/vertical inversion after
  Standard/Swapped role assignment; defaults retain exact old bytes. Independent
  review found no P0-P2 issue, and root input, parse, UI, settings/iCloud, and
  save-sync regression suites pass. Both iOS configurations are now 116.
  The signed generic-iOS product is preserved at
  `/private/tmp/GOALPad-build116-analog-signed/GOALPad.app`; no device validation
  is claimed. The approved M5 iPad simulator Release also builds, installs, and
  launches as 116; native UI interaction verified both stick sections, live
  camera inversion, and Controls-default restoration. This is not physical
  controller/gameplay evidence.
- `Integrated locally; synthetic visionOS proof only` — parent `9edcf64e` plus
  actor-isolation correction `2f29c327` render one immutable synthetic,
  depth-tested tetrahedron through distinct compositor views using predicted
  tracking and per-view transforms/projections/targets. The xros Swift/Metal
  gate passes. This is not game stereo, tabletop, room-scale, first-person,
  real DMA, or physical Vision Pro evidence; Comfort remains the active game
  mode.
- `Integrated locally; independent review ACCEPT; numbered build pending` —
  parent `535810a1` plus Classic artwork correction `5a4e5ff2` and nested
  OpenGOAL `39e451aa1` add a safe authored-cutscene SKIP and a distinct STATS
  touch control. GOAL exposes SKIP only for the central explicitly skippable,
  skip-enabled, undecided Triangle query; native owner/sequence/heartbeat
  validation and touch lifecycle changes fail closed. A completed current tap
  emits one ordinary Triangle pulse, while STATS holds exactly L2+R2. The
  independent Sol xhigh review found no remaining safety or UI blocker. Root
  rebuilt all 277 focused GOAL dependencies and passed the native, touch,
  menu/progress, and keyboard/controller gates. This is not permission to jump
  arbitrary states, skip load/death/warp/boat transitions, or claim every
  cinematic is authored skippable.
- `Validator accepted but parked; manager authority still BLOCKS product
  integration` — the data-only mod branch preserves initial manager commit
  `72587e9c`, parent validator chain through `f3818815`, and nested checked
  production Level validator through `97e564ae04`. Complete bounded Level
  deserialization now rejects malicious strip/BVH, runtime-budget, Hfrag,
  Tie/Shrub, DrawMode/matrix, and Merc/Blerc relationships before install.
  Two independent security passes found and closed all source findings; the
  warnings-as-errors package/FR3 suite passes and the validation-boundary docs
  are current. Do not integrate or expose the manager until the maintainer
  authorizes the scoped app-sandbox filesystem transaction layer; same-FD
  publication, immutable copies, strict registry JSON, rollback/recovery, and
  process-wide transaction ownership remain part of that separate gate.
- `Mod inventory documented; no curated bundle approved` — parent `eaa3b5e0`
  adds `docs/JAK1_MOD_INVENTORY.md` from a primary-source review of the pinned
  OpenGOAL capabilities and discoverable Jak 1 mod landscape through
  2026-08-06. Existing upstream settings are separated from third-party mods;
  no surveyed package is currently verified as data-only, compatible with the
  signed source pin, and redistributable with audited asset provenance. No
  mod, executable, or asset was downloaded or added.
- `Integrated; focused validation passed; Build 107 full Xcode build pending` —
  Jak 1 physical-button/key remapping came from
  `/private/tmp/GP-build94-input-remapping`, worker commit `13197fd7`, and is
  integrated as `10986ec9`. It preserves exact controller and keyboard defaults,
  adds mouse-button bindings, uses deterministic swap/duplicate normalization,
  persists in the title-scoped iCloud document, and participates in Controls/full
  reset. Analog stick and mouse camera axes remain fixed and are not claimed as
  remappable yet.
- `Integrated through 88e97b6f; focused validation passed; consolidated Build
  106 pending` — post-Build-105 work now includes title-scoped stable Settings,
  Primary Controller arbitration persisted in the Jak 1/iCloud document, a
  validated native preserved-save promotion manager, discrete touch haptics,
  authoritative look-around state readback, state-aware Modern pinch zoom, and
  the visionOS five-mode scene foundation. Worker pushes were attempted but rejected by the execution
  approval boundary; every worker commit is preserved in this integration
  branch and will be pushed with the checkpoint. Modern pinch zoom is the only
  active touch-file owner.
- `Signed and physically rejected as incomplete on Z iPad Pro` — Build 105 packages
  the Misty transition, Metal allocation rollback, DGO terminal failure, and
  Fire Canyon preview-title fixes. Parent packaging commit `5153fcfa` and nested
  OpenGOAL `c63c73ecf` are pushed. The preserved signed app is
  `/private/tmp/GOALPad-build105-misty-signed/GOALPad.app`. It was installed
  without uninstalling or clearing app data on 2026-08-06. The authored boat
  cutscene still entered an unloaded void and Jak could fall through; death
  respawned on intact Misty with the boat correctly placed. The same physical
  build also letterboxed the iPad Pro 11-inch with black bars at the top and
  bottom, and changing Jak's native Aspect Ratio options could leave the image
  squashed. Fire Canyon preview-title behavior was not re-reported in this run.

- `Integrated; focused validation and signed-build validation passed; physical
  presentation pending` — the public product rename from Eco Pro to Eco came
  from `agent/build104-eco-branding` in
  `/private/tmp/GP-build104-eco-branding`. Worker commit `76d0110e` is pushed
  to `origin/agent/build104-eco-branding` and integrated as `b1faac13`.
  User-facing source, Settings copy, app display metadata, focused tests, and
  maintained product documentation use Eco; durable bundle, iCloud, storage,
  source, scheme, and target identifiers remain unchanged.
- `Integrated; Apple SDK and signed-profile validation passed; runtime sign-in
  pending` — Game Center authentication foundation came from
  `agent/build100-game-center-foundation` in
  `/private/tmp/GP-build100-game-center`. Code commit `9c825502` is integrated
  as `d47233e4`; worker/ledger HEAD `31f32584` is pushed to
  `origin/agent/build100-game-center-foundation`. Root wired launcher/gameplay
  state into the access-point policy, reran `Scripts/run-game-center-check.sh`,
  and verified that the Build 103 development provisioning profile carries the
  standard Game Center and existing iCloud entitlements.
- `Integrated; focused validation passed; physical keyboard/mouse tuning
  pending` — default keyboard/mouse input came from
  `agent/build97-keyboard-mouse` in `/private/tmp/GP-build97-keyboard-mouse`.
  Code commit `ddb0e8ed` is integrated as `7861e892`; worker/ledger HEAD
  `cbe47d19` is pushed to `origin/agent/build97-keyboard-mouse`. Root reran
  `Scripts/run-keyboard-mouse-input-check.sh` and `git diff --check`; both
  passed. The worker also passed warnings-as-errors macOS, iOS, and visionOS
  SDK type-checks.
- `Integrated; focused validation passed; physical presentation pending` —
  Pause/Resume touch artwork came from `agent/build100-pause-label` in
  `/private/tmp/GP-build100-pause-label`. Code commit `c5da85d4` is integrated
  as `501f3f4d`; worker/ledger HEAD `074d9cdb` is pushed to
  `origin/agent/build100-pause-label`. Root reran
  `Scripts/run-touch-controls-check.sh`, iOS Swift parsing, and
  `git diff --check`; all passed.
- `Integrated; focused validation passed; physical ergonomics pending` —
  Modern touch geometry came from `agent/build101-modern-touch-layout` in
  `/private/tmp/GP-build101-modern-touch-layout`, commit `6005cfdc`, pushed to
  `origin/agent/build101-modern-touch-layout`. It moves the right stick inward
  with a deterministic safe-area-aware spacer and reduces only the movement
  ring artwork. Root additionally routed UIKit-captured safe-area insets into
  the Modern helper because the full touch surface intentionally ignores the
  SwiftUI safe area. The dynamic movement input radius, knob size, right-stick
  radius, deadzone, and controller bytes remain unchanged.
- `Integrated; focused validation passed; profile binding and physical
  ergonomics pending` — Classic touch fallback plus Modern held-crouch-left
  punch came from `agent/build94-classic-touch` in
  `/private/tmp/GP-build94-classic-touch`. Code commit `501d64a3` was integrated
  as `e032457b`; worker/ledger HEAD `7936b744` is pushed to
  `origin/agent/build94-classic-touch`. Root reran
  `Scripts/run-touch-controls-check.sh` with Xcode macro services and all checks
  passed.
- `Integrated; focused validation passed; physical presentation pending` —
  Jak 1 settings and combined iCloud presentation came from
  `agent/build94-jak1-settings-icloud` in
  `/private/tmp/GP-build94-jak1-settings-icloud`. Code commit `a289e36e` is
  integrated as `5b268b8a`; worker/ledger HEAD `3e5c4e52` is pushed to
  `origin/agent/build94-jak1-settings-icloud`. Root reran both
  `Scripts/run-presentation-settings-check.sh` and
  `Scripts/run-save-sync-check.sh` with Xcode services; both passed.
- `Integrated; focused validation passed; physical portrait check pending` —
  portrait renderer alignment and complete Jak X library removal came from
  `agent/build94-portrait-library` in
  `/private/tmp/GP-build94-portrait-library`. Worker commit `f7669744` was
  integrated as `3db17c67`; root removed the remaining dead Jak X enum/palette
  code and reran `Scripts/run-portrait-library-check.sh`.
- `Implemented; signed Build 108 validation passed; physical presentation pending` — root integration
  added a read-only native `*master-mode*` bridge for exact game/pause/progress/
  menu state, exposed it through `GameSession`, and added
  `Scripts/run-game-menu-state-check.sh`. Root then used it to gate the in-game
  Eco Settings control and optional synced developer logs, and bound the
  saved Controls profile to the matching live touch style. Build 108 adds an
  explicit touch Resume action for native pause and a truthful D-pad plus
  Confirm/Back/Resume surface for the native debug menu. It deliberately leaves
  `progress` unchanged until its internal screen state is bridged. Root still
  owns skip, warp, mod, and the remaining Game Center seam discovery. It will
  not edit a worker-owned file while that lane is active.
- `Implemented; signed Build 109 validation passed; physical presentation pending` —
  worker commits `2954142f` and corrective `59b79a7c` from
  `/private/tmp/GP-build109-progress-touch` were independently source-reviewed
  and integrated as `f2874b7c` and `01f854be`. A checked read-only
  `*progress-process*` snapshot now gates exact stats actions, shipping-PC
  settings/file-list navigation, selected-option Cancel, and vertical one-shot
  swipes. Autosave, transitions, malformed objects, unsupported PC screens, and
  unknown rows remain inert. Review caught incorrect PC list lengths and
  unhandled unselected Left/Right affordances before the full build. Preserved
  app: `/private/tmp/GOALPad-build109-progress-touch-signed/GOALPad.app`.
- `Implemented; signed Build 110 validation passed; physical touch/VoiceOver
  acceptance pending` — library commits `a21de013` and corrective `6e6b35bd`
  were integrated as `79b3cba9` and `f9651068` only after independent review
  kept the artwork menu separately focusable and moved its 44-point target into
  the actual label. Classic hit-target commit `0123163f` was integrated as
  `9e566a76`; root added the 44-point paused Eco Settings label and focused
  source checks in `2a5c5928`. Visible Classic artwork, stick geometry,
  controller bytes, Modern input, and standard SwiftUI Forms/Lists remain
  unchanged. Preserved app:
  `/private/tmp/GOALPad-build110-touch-accessibility-signed/GOALPad.app`.
- `Storage cleanup complete; dirty and Jak II work preserved` — removed 62 clean
  obsolete parent worktrees, then 22 clean obsolete OpenGOAL Jak 1/Build 84–88
  worktrees. No branch or commit was deleted. Dirty maintainer/audit worktrees,
  current implementation lanes, and both Jak II paths remain. After the held
  Game Center worktree was removed, the integration OpenGOAL store was fully
  repacked, its temporary alternates pointer was removed, and full fsck plus
  current/history object lookups passed.

#### Critical Sandover-to-Misty transition blocker

- [ ] `Physically reproduced; Build 105 is only a partial recovery` —
  taking the Sandover Village boat toward Misty Island first presents a
  low-detail/untextured Sandover-like scene, then streamed world geometry
  remains absent during travel. Jak can jump out and fall through. After death,
  the ordinary respawn does recover to intact Misty Island and the boat is in
  its expected destination position. This proves the destination can become
  resident after recovery, but it does not validate the boat transition,
  cutscene world, or initial-arrival collision.
- [ ] `First-trip relocation failure clarified after extended Misty play` —
  the boat does not authoritatively move to its destination on the first trip.
  It remains at the old location in a de-resolved state while Jak remains in
  the boat and can invoke `Take Boat` again. That second invocation begins from
  stale transition state and corrupts world streaming. Jumping out before a
  death/respawn falls through the unloaded route. The fix must complete the
  boat and Jak relocation on the first trip, leave the source boat
  non-interactable, and must not treat death/respawn recovery as success.
- [ ] The same recovered session displayed `MISTY ISLAND` only when the
  maintainer later boarded the boat to leave Misty. Treat this as evidence that
  first-arrival completion/title state remained armed across death/respawn and
  fired on the next boat interaction. Acceptance requires the title on the
  completed first arrival, never on departure, without changing ordinary
  level-title boundaries elsewhere.
- [ ] `Build 113 source fix rejected by the newer ownership trace` — the
  two-direction finalizer retries the authored clone/spool path, waits
  fail-closed for the destination to become active, and snaps boat and target
  to the authored dock, but it yields for current-level/title reevaluation
  before publishing the destination continue. `level-get-target-inside` still
  prefers the active source continue during that frame. The five relocation
  contract tests model coordinates and ordering but not current-level
  ownership, stale interaction, death/respawn, or title consumption. Do not
  install or physically accept Build 113 as the Misty fix. The replacement
  must make destination ownership authoritative before the first reevaluation,
  consume the arrival title once at arrival, never on departure, and prove the
  docked/source-interaction state in both directions.
- [x] `Corrected Build 114 source path independently accepted and signed;
  physical gate pending` — nested OpenGOAL `352064ace`, `f260ae7df`, and
  `cb5032a83` end the
  clone animation's stale-position fallback, make destination collision a
  fail-closed prerequisite, and preserve the passenger-relative target offset
  across every failed-ground retry. Each retry reapplies the intended target
  position before probing; no end-mode, continue/title ownership, or dock-ready
  state commits until `move-to-ground` succeeds. The grounded transform then
  flows through ordinary restore before destination continue and the single
  post-commit suspension. Three Sol xhigh review passes caught and corrected
  ordering, fabricated-ground, and clone-overwrite bugs; final review returned
  ACCEPT. Root integration passes 6/6 structural contracts and a 328-dependency
  GOAL compile. Nested `2e0438416` records the regenerated 518-object source
  pack identity `2b812636de96f221`; canonical generation emits 10,618
  functions with seven native functions and zero failed files. These are
  source/AOT proofs, not physical boat/title/collision acceptance.
- [x] Establish that Build 90 and Build 93 pin the same OpenGOAL revision and
  contain no renderer, shader, Metal-host, AOT, or generated-source delta.
  Classify this as an unvisited transition gap unless later evidence proves a
  regression earlier than Build 90.
- [x] Build the exact 518-object host engine and run a direct `misty-start`
  load against the maintainer's local prepared data. `MIS.DGO` completed,
  Misty reached `'active`, the target remained in a stable stance, and the
  canonical AOT/data path passed.
- [x] Run the same direct `misty-start` state through `goalpad-play` and Metal.
  `misty.fr3` loaded with 627 textures, 73.2 MB of vertices, 10.1 MB of
  indices, zero level failures, and healthy screenshots at frames 1300 and
  1600. The desktop host evicted unwanted title art after 181 frames and kept
  only Village1 plus Misty resident.
- [x] Repair the iOS parent's missing level-art eviction/lifecycle seam and the
  nested Metal loader's silent nil-buffer/zero-texture success path. Review
  those worker patches independently before integrating either.
- [x] Repair the independent DGO fail-open seam: a terminal archive error is
  currently indistinguishable from pending to GOAL, so a non-wait transition
  can continue forever without the destination BSP/collision.
- [x] Add deterministic direct-Misty and terminal-DGO-error coverage plus the
  closest synthetic boat-transition state coverage available without retail
  fixtures. The exact authored boat route remains a physical Build 105 gate;
  do not claim it from title-screen, static-level, or source-manifest checks.
- [x] Investigate and repair the related physical report that the 20-cell Fire Canyon
  camera preview displayed the `FIRE CANYON` title before Jak entered and that
  the title cleared only after pause/unpause plus time. The authored preview
  moves the camera across non-player display boundaries, while ambient/hint
  collection uses `ear-trans`; distinguish original behavior from leaked
  transition state before changing GOAL UI logic.
- [ ] Any candidate fix must preserve Build 93 saves, accepted graphics,
  performance, input, and iCloud behavior and requires this exact physical
  Sandover-to-Misty route before becoming a new gameplay baseline.

#### Settings shell and per-game ownership

- [x] Hide the app Settings and developer-log controls during gameplay; expose
  them only while the native Jak pause/start menu is open.
- [x] In the paused overlay, use white `Eco` plus the Settings icon.
- [x] Add a per-game `Show developer logs` setting; logs remain off the normal
  player surface when disabled.
- [x] Replace the unstable boolean Settings sheet with one item-backed,
  title-scoped presentation identity. Focused presentation tests pass; stationary
  physical confirmation remains part of the next candidate check.
- [x] Present Modern before Classic in every global and section picker while
  preserving stored enum/document compatibility.
- [x] Make app settings title-scoped. The launcher Settings entry lists Jak 1,
  Jak II, and later supported titles; each title remembers its own profile and
  options locally and in iCloud.
- [x] Do not present unimplemented title settings as functional. Jak 1 is the
  active settings document; later-title rows may be clearly unavailable until
  their title support is real.
- [x] Rename `Reset All` to `Reset Jak 1 Settings` in the Jak 1 document.
- [x] Remove Jak X from the game library because it is outside OpenGOAL scope.
- [x] Remove empty Audio and UI sections for now unless a setting exists that is
  not already meaningfully covered by Jak's native options.
- [x] Move Fill Width into the in-game Graphics settings, call the user-facing
  option `Fit to Screen`, and do not expose the implementation term `Hor+`.
- [ ] Preserve Build 93's accepted Modern Graphics default and exact Classic
  presentation while moving that option.
- [x] Remove the PC-only `Display` and `Display Mode` rows from Jak 1's native
  Graphics options on Apple devices. They cannot meaningfully control Eco's
  app-owned surface and must not persist incompatible presentation state.
- [x] Remove `MSAA` from the Apple-managed native Graphics list. Also remove
  `V-Sync`: both setters are only loud machine stubs in the current portable
  Jak 1 kernel and neither changes Eco's Metal configuration. Do not confuse
  the renderer's required internal `syncv` callback with a wired player V-Sync
  option. Preserve ordinary desktop OpenGOAL's menu unchanged.
- [ ] Repair the Build 105 physical presentation regression: Modern/Fit to
  Screen must again fill the iPad Pro 11-inch as accepted in Build 90/93, with
  no top/bottom black bars or squashing. Include a safe migration/reset for a
  native Aspect Ratio choice changed while compensating for Build 105.
- [x] Combine the duplicate `iCloud Settings` and `iCloud Saves` sections into
  one `iCloud` block with independent `Sync Settings` and `Sync Saves` toggles.
- [x] Give that block one combined progress/status, last-sync date, and
  Sync/Retry action covering whichever toggles are enabled.
- [x] Preserve the existing independent opt-outs and safe pregame save gate
  beneath the combined presentation.
- [ ] Add the smallest truthful settings entry needed to import/manage supported
  data-only mods; do not imply a mod browser or code-mod support exists.
- [x] Add a save-conflict manager that lists preserved divergent copies in
  player language and can explicitly promote a validated copy to the canonical
  native memcard without weakening archive/journal/CAS safety.
- [ ] Finalize the in-game Jak 1 title with the maintainer before changing player
  strings. Do not guess.
- [x] Use `Eco` as the maintainer-selected public product and display name.
  Keep GOALPad as the internal repository, scheme, target, and runtime name,
  and preserve existing bundle, iCloud, and durable storage identifiers.

#### Input-source ownership and remapping

- [x] Add a Jak 1 `Primary Controller` choice that can explicitly prefer Touch,
  a connected controller, or Mouse & Keyboard, with an honest Automatic/default
  behavior when the preferred source is unavailable.
- [x] Preserve normal controller-first behavior while a physical controller is
  actively driving input; return to touch after touch activity according to a
  deterministic tested policy.
- [x] Add remapping for all supported physical-controller inputs. All 16
  ingested buttons are assignable, whole sticks can exchange Movement/Camera
  roles, and each complete logical vector has bounded sensitivity, radial dead
  zone, and independent horizontal/vertical inversion without splitting X/Y.
- [x] Add remapping for all supported mouse-and-keyboard inputs. All 12 bounded
  named keys and three mouse buttons are assignable; WASD movement is ordinary
  remappable input, while relative mouse/trackpad motion remains the requested
  camera source with bounded sensitivity and independent inversion.
- [x] Define collision/duplicate-binding behavior, reset defaults, persistence,
  cloud sync, and unavailable-device presentation before calling remapping done.
  Bindable buttons/keys use deterministic swapping and declared-order duplicate
  normalization. Analog customization preserves whole-vector ownership and
  exact default bytes; arbitrary typing and per-component stick tearing remain
  intentionally unsupported.
- [x] Implement mouse/trackpad camera control and WASD movement.
- [x] Default keyboard face directions to Left = Square, Right = Circle,
  Up = Triangle, and Down = the exact L1+R1 shoulder chord. Ordinary Jak 1
  progress/stats remains Start and is distinct from this speedrunner chord.
- [x] Default Escape to Start/Pause.
- [x] Map explicit Tab to the native L2+R2 Stats chord without treating arbitrary
  typing as gameplay input. Further bindings belong to the remapping lane.

#### Touch profiles and customization

- [x] `Superseded by the maintainer after Build 118 physical testing` — Classic
  touch and the Controls Modern/Classic picker were implemented, but the entire
  concept is now rejected and must be removed from player-facing runtime/UI.
  Keep old synced documents decodable only.
- [x] Restore the Build 96 (`f5643c41`) ordinary gameplay-touch foundation:
  dynamic left stick, fixed right stick, original face gestures, Select, and
  Start. Retain the explicitly accepted later crouch-left punch, pinch, SKIP,
  haptics, full-screen warp capture, and native-menu
  Start/Pause/Resume/Back controls. Focused suites and independent Sol xhigh
  review pass; physical acceptance remains pending.
- [x] In Modern touch, once a held downward gesture has engaged crouch, sliding
  left without releasing must trigger crouch + punch. Preserve the existing
  held down-then-up crouch jump and ordinary left-swipe behavior, with focused
  sequencing and one-shot/retrigger tests.
- [x] `Superseded by the Build 96 restoration` — the smaller outer movement
  ring and adaptive inward right-stick spacer were implemented but are not part
  of the Build 120 gameplay layout.
- [x] Add Modern pinch-to-zoom gestures that map unambiguously to the existing Y
  zoom toggle: pinch in and pinch out must not accidentally perform each other's
  action. The implementation emits Triangle only for an authoritative
  normal-to-look-around or look-around-to-normal transition and fails closed for
  Billy, unavailable state, or a reversed gesture.
- [x] Replace the second Pause/Select pill with `SKIP` per the maintainer's
  latest direction. Define exactly which skippable state is active before
  emitting input; never bypass progression or corrupt game state. Builds 114
  and 115 expose it only for the native, authored, skip-enabled central
  Triangle query with current owner/sequence/heartbeat validation; STATS remains
  a separate L2+R2 action and generic state jumps remain unsupported.
- [x] Make Start display `Pause` during gameplay and `Resume` while the native
  pause menu is open; keep Resume visible throughout that menu.
- [x] `Superseded by the maintainer after Build 118 physical testing` — the
  Build 117 touch-layout editor and its isolated iCloud sidecar remain useful
  compatibility history, but Build 119 removes the editor/runtime effect. Do
  not delete or reinterpret an old cloud document; ignore it after decoding.

#### Touch-friendly game and launcher interaction

- [x] Expose Jak 1's real `*master-mode*` as a read-only Apple-host state so
  pause-gated chrome and Pause/Resume labels do not rely on screenshots,
  timing, or a duplicate Swift pause flag.
- [x] When a physical controller is active, preserve ordinary controller input
  and avoid intrusive touch chrome.
- [x] When touch is active, make the app-owned settings/library surfaces use
  normal touch targets and scroll/swipe behavior. Build 110 preserves native
  SwiftUI Form/List/ScrollView controls, converts the launcher tile to a
  semantic Button, keeps its artwork Menu independent, guarantees 44-point
  artwork-menu and paused Eco Settings targets, and floors compact Classic
  button hit regions at 44 points without changing their artwork.
- [x] Investigate native Jak menu state/readback before attempting touch hit
  targets over GOAL-rendered rows; do not infer selection rectangles from a
  screenshot. `*progress-process*` is the authoritative object: after a checked
  type/tag dereference it exposes `display-state`, `option-index`,
  `selected-option`, and `in-transition`. Build 109 now exposes that checked
  snapshot and fails closed for malformed, transitional, or unsupported state.
- [x] Add only the coarse native actions whose meanings are already
  authoritative: Pause exposes Resume/Start, and the debug Menu exposes D-pad,
  Confirm/Cross, Back/Square, and Resume/Start. Build 108 cancels carried
  gameplay gestures at these transitions, suppresses touch chrome while a
  physical controller is driving, and delivers menu haptics immediately.
- [ ] Finish truthful Start/Pause/Resume and explicit Back coverage for the
  native pause/progress menus. Build 109 already provides the maintainer-accepted
  interaction model: exact stats shortcuts, conservative PC settings/file-list
  actions, and vertical one-shot swipes. Direct row hit-testing is intentionally
  out of scope; do not reopen it unless the maintainer changes direction.
- [ ] Replace raw X/Square/Triangle/Circle instructional chrome with clear touch
  actions where the app truly owns the target; the frozen Build 96 gameplay
  controls remain the fallback elsewhere.
- [x] For warp gates, prefer a truthful `Touch gate to use warp gate` interaction
  only if gate focus/availability can be read safely. Otherwise show large
  explicit button controls and make the destination list swipe-selectable. The
  gate remains in gameplay mode, so `*master-mode*` cannot identify it. The
  narrow safe seam is read-only GOAL state owned by `villagep-obs.gc` with
  unavailable, Circle-use-available, destination-list-active (selected/permitted
  slots), and transitioning states; do not infer this from pixels or proximity.
  Build 120 retains the implemented full-screen destination capture, explicit
  actions, horizontal swipes, stale-snapshot rejection, and transient-invalid
  retention. Deterministic tests pass; physical warp testing remains pending.
- [x] In portrait gameplay, top-align the renderer instead of vertically
  centering it so the remaining lower area is available to touch controls.

#### Haptics, stats, and skipping

- [x] Add a bounded touch-device haptic proof for direct buttons, recognized
  gestures, and one meaningful stick-engagement edge. It emits only from touch
  callbacks, never from the frame loop; physical feel remains pending.
- [ ] Preserve and extend connected-controller rumble through Game Controller;
  use supported left/right localities when the device exposes them and degrade
  cleanly when it does not.
- [x] Keep native Jak rumble fidelity separate from new app UI haptics so one
  source cannot mask or continuously restart the other.
- [ ] Preserve a reachable Stats action even though the latest touch pill is
  named `SKIP`; document controller and keyboard defaults.
- [ ] Extend the existing `SKIP` touch control across the game's authored skip
  interactions by emitting the same context-appropriate native button or chord
  a controller player would use. This is input accessibility, not a generic
  state jump: do not call arbitrary GOAL completion hooks or skip transitions
  the game itself does not make skippable.

#### Game Center

- [x] Add the source-level Game Center authentication foundation and standard
  `com.apple.developer.game-center` entitlement without adding private
  entitlements, custom social behavior, leaderboard IDs, or activity definitions.
- [x] Wire `GameCenterService.setGameplayActive(_:)` to
  `GameSession.isRunning`, so the authenticated standard access point is
  launcher-only and cannot overlay gameplay.
- [x] Confirm automatic provisioning for `com.zephyrstudiosllc.eco` accepts
  Game Center and inspect the signed Build 104 profile. It carries the standard
  Game Center entitlement alongside the existing iCloud container.
- [ ] Exercise sign-in with a Game Center test account and verify launcher-only
  access-point presentation on a real runtime. Source, SDK, and signed-profile
  checks do not prove authentication or App Store Connect configuration.
- [ ] Define player-visible friend presence/current-run information with an
  explicit privacy and refresh model.
- [ ] Add validated native read-only seams for the friend's current area and
  overall run progress before publishing Game Center presence. Competitive
  timing, fastest-run records, completion leaderboards, and score submission are
  not part of the requested Game Center scope.

#### Candidate later-update scope

Keep this list at ten or fewer. These are currently the strongest candidates
to defer from the first post-Build-93 update because they require a larger
architecture, gameplay-semantic, backend, or physical-tuning gate:

1. Touch-layout presets/sharing and further physical ergonomics beyond the
   bounded Build 117 editor.
2. Complete controller and mouse/keyboard remapping UI.
3. Full mod manager/browser and curated mod pack beyond a truthful local import
   entry; mods remain a nice-to-have rather than release-critical work.
4. Rich localized device/controller haptic design beyond preserved native
   rumble and a small UI-haptic proof.
5. ProMotion/120 Hz; research is complete and the maintainer does not need an
   implementation in the current product cycle.
6. Stereoscopic, tabletop, room-scale, and first-person visionOS modes beyond
   the conventional Comfort window.
7. Extensive low-memory optimization after confirmed lifecycle freezes are
   repaired and basic footprint measurements establish a real bottleneck.

Classic touch, portrait top alignment, Modern-first ordering, empty-section
removal, pause-gated app chrome, and the unified iCloud presentation are not in
this defer list; they are the preferred first executable slices.

#### visionOS presentation modes

These are deferred visionOS-only follow-on modes requested by the maintainer. The scene
coordinator and five-mode capability model are **Implemented**, and a synthetic
per-view compositor layer is **Validated by Apple SDK typecheck**. Only
Comfort/Normal is playable; game stereo and spatial world modes remain
**Planned** or **Investigating** and must not delay the current
Jak 1 iPhone/iPad correctness track. Preserve the conventional window as the
fallback while the shared renderer is isolated from its current single
`CAMetalLayer`, single display clock, and gameplay-camera assumptions.

1. **Comfort / Normal:** the existing monoscopic conventional window.
2. **Stereoscopic 3D:** the default visionOS presentation for the Modern
   graphics profile once true per-eye rendering passes physical Vision Pro
   validation. Duplicating one completed framebuffer is not stereo.
3. **Tabletop / Volume:** render a bounded Jak world in front of the user so
   rotating or walking around the volume changes the viewer relationship while
   gameplay remains third-person. Provide an immersion/zoom control for how
   much world the volume contains.
4. **Room-scale World:** expand the stationary third-person world to an
   environment-sized mixed or progressive immersive space that the user can
   physically walk around without the world rotating with head movement.
5. **First-person VR:** an immersive player-view mode with gameplay-camera and
   head-pose separation. Rolls, spins, cutscenes, vehicles, death, HUD, turning,
   and camera shake require explicit comfort behavior; default to a stable
   floating/spectator treatment rather than forcing artificial head rotation.

Implement in narrow proofs: keep the flat window healthy, preserve the existing
visionOS-only scene/session coordinator and synthetic compositor proof, define an
immutable per-frame simulation snapshot plus external view/projection and
render-target contract, cover renderer buckets and culling, then add stereo,
tabletop, room-scale, and first-person in that order. Real stereo requires
per-view color/depth targets and compositor timing. A useful tabletop proof may
use RealityKit, but a textured flat plane is only a compatibility prototype,
not the requested volumetric world.

#### Background lifecycle and memory (newest FIFO item)

- [ ] Reproduce and repair the report that after Eco/Jak remains open through a
  phone lock or background interruption, the SwiftUI/touch shell resumes but
  native gameplay stays frozen. Build 118 additionally produced a black-screen
  loop with the theme song after leaving and resuming. Trace scene activation,
  display-link recreation, audio-session interruption, render-surface
  availability, and any in-flight frame ownership; preserve the active run and
  do not treat a responsive overlay or restarted theme as proof that native
  frames resumed.
- [ ] Make suspended gameplay as background-friendly as iOS permits: stop active
  clocks/audio work, release only safely recreatable transient renderer/importer
  resources under lifecycle or memory pressure, keep user saves and the resumable
  gameplay authority intact, and add deterministic suspend/resume plus memory-
  warning coverage before physical lock/unlock validation. This item follows the
  older interaction/settings/visionOS queue and must not preempt it.
- [ ] `Deferred after basic lifecycle correctness` — measure, do not estimate,
  Eco's foreground resident footprint, peak during
  representative Jak 1 level transitions, post-transition steady state,
  background footprint, memory-warning response, and jetsam/background survival.
  Record the exact build, device RAM class, OS, route, and measurement source.
  Compare the current 12 GB iPad Pro M5 and iPhone Air observations with at least
  one materially lower-memory supported iPhone/iPad or an appropriate controlled
  simulator/Memory Graph diagnostic, while keeping physical thermal acceptance
  separate from simulator evidence. Investigate the comfortable-but-warm iPhone
  report and the iPad process-loss report only when this FIFO item is reached.
- [x] Inventory the current pinned OpenGOAL and relevant community mod landscape
  when this FIFO item is reached. Compare Eco against useful QoL and graphics
  capabilities, texture replacement packs, original custom levels, and other
  supported extensions. Classify each candidate as: a stable engine option Eco
  should expose as a native per-game setting; a user-supplied data-only package
  Eco can validate/install/remove without code execution; a GOAL/code mod that
  requires ahead-of-time compilation and ordinary Apple signing; or unsupported.
  Record provenance, compatibility/version rules, conflicts/load order, storage
  and iCloud policy, safe rollback, and whether content is original/user-owned.
  Do not bundle, download, recommend importing, or silently accept retail-derived
  game assets, and do not present the existing game-data importer as a mod manager.
  The bounded primary-source result is recorded in
  `docs/JAK1_MOD_INVENTORY.md`: upstream-native options are the only immediate
  Modern candidates, no third-party package passed the current bundle boundary,
  and executable mods remain a signed-AOT review path rather than a runtime
  import format.
- [ ] `Nice-to-have / deprioritized` — after that inventory, define a
  maintainer-approved Modern curated pack
  covering the major compatible QoL, graphics, texture, and original-content
  additions available through August 2026. Classic must remain the accepted
  unmodified presentation; Modern may enable the approved built-in features and
  bundled content as a coherent preset while retaining per-setting overrides.
  Before any third-party item enters the app or repository, verify exact source,
  version, license/redistribution permission, attribution, dependency/load order,
  user-game-data separation, storage cost, iOS/visionOS behavior, and whether it
  contains or derives from retail assets. Do not bundle copyrighted game assets,
  merely publicly downloadable content without redistribution permission, or
  runtime code that bypasses the signed AOT architecture. Classify excluded items
  as user-installed or unsupported rather than weakening these boundaries.

## Code clarity

Write clean, human-readable code suitable for an open-source project.

- Prefer the simplest direct implementation that satisfies the current milestone.
- Reduce complexity whenever possible and do not over-engineer for hypothetical future work.
- Use clear names and control flow so the code explains itself.
- Minimize comments and the need for comments. Add one only when a non-obvious constraint or rationale cannot be made clear in the code itself.
