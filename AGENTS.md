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
tasks. Use one `gpt-5.6-sol` `xhigh` integration lane, up to two
`gpt-5.6-sol` `xhigh` implementation lanes for importer architecture,
renderer behavior, ABI/AOT work, and unsafe file handling, and one
`gpt-5.6-terra` `medium` or `high` lane for bounded CMake wiring,
documentation, fixture expansion, build-log triage, formatting, and mechanical
API plumbing. Editing subagents should use dedicated branches and worktrees
where practical; never let agents edit the same files concurrently. The
primary agent must review and validate every subagent result before
integration.

Avoid duplicated validation work:

1. Each worker runs only `git diff --check`, changed-file parse or compile
   checks, focused unit tests, and the smallest isolated compile for its patch.
2. Integrate several reviewed non-overlapping commits before running the full
   compiler, Metal proof, AOT build, or Xcode matrix once per checkpoint.
3. Do not rebuild Eco Pro for an importer-only nested OpenGOAL change that is
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

### Live Jak 1 orchestration ledger

This checklist is a tracked execution ledger, not a promise that every item
ships in one build. Update it whenever a worker begins, commits, integrates,
passes a focused gate, or reaches a physical-validation boundary. Each active
item must have one file owner; do not let workers edit the same files
concurrently. Use these states in notes where a checkbox alone is ambiguous:
`Planned`, `Investigating`, `In progress`, `Implemented`, `Validated`, and
`Deferred`.

#### Baseline and integration

- [x] Preserve Build 93 at `9c87b0be` as the immutable known-good baseline.
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
- [ ] Physically compare the next candidate against Build 93 on iPhone and iPad
  before calling it the replacement baseline.

#### Settings shell and per-game ownership

- [ ] Hide the app Settings and developer-log controls during gameplay; expose
  them only while the native Jak pause/start menu is open.
  - Investigating: `ContentView` currently gates both controls only on
    `session.isRunning`; `GameSession` and `GOALPadRuntimeBridge` expose no
    native pause/start-menu readback. Do not infer it from renderer output.
- [ ] In the paused overlay, use white `Eco Pro` plus the Settings icon.
- [ ] Add a per-game `Show developer logs` setting; logs remain off the normal
  player surface when disabled.
- [ ] Fix the stationary Settings sheet/modal layout flicker and roughly
  100-point vertical text jump before adding more rows.
- [ ] Present Modern before Classic in every global and section picker while
  preserving stored enum/document compatibility.
- [ ] Make app settings title-scoped. The launcher Settings entry lists Jak 1,
  Jak II, and later supported titles; each title remembers its own profile and
  options locally and in iCloud.
- [ ] Do not present unimplemented title settings as functional. Jak 1 is the
  active settings document; later-title rows may be clearly unavailable until
  their title support is real.
- [ ] Rename `Reset All` to `Reset Jak 1 Settings` in the Jak 1 document.
- [x] Remove Jak X from the game library because it is outside OpenGOAL scope.
  - Validated worker branch `agent/build94-portrait-library` in
    `/private/tmp/GP-build94-portrait-library`, commit `f7669744`, with
    `Scripts/run-portrait-library-check.sh`.
- [ ] Remove empty Audio and UI sections for now unless a setting exists that is
  not already meaningfully covered by Jak's native options.
- [ ] Move Fill Width into the in-game Graphics settings, call the user-facing
  option `Fit to Screen`, and do not expose the implementation term `Hor+`.
- [ ] Preserve Build 93's accepted Modern Graphics default and exact Classic
  presentation while moving that option.
- [ ] Combine the duplicate `iCloud Settings` and `iCloud Saves` sections into
  one `iCloud` block with independent `Sync Settings` and `Sync Saves` toggles.
- [ ] Give that block one combined progress/status, last-sync date, and
  Sync/Retry action covering whichever toggles are enabled.
- [ ] Preserve the existing independent opt-outs and safe pregame save gate
  beneath the combined presentation.
- [ ] Add the smallest truthful settings entry needed to import/manage supported
  data-only mods; do not imply a mod browser or code-mod support exists.
- [ ] Add a save-conflict manager that lists preserved divergent copies in
  player language and can explicitly promote a validated copy to the canonical
  native memcard without weakening archive/journal/CAS safety.
- [ ] Finalize the in-game Jak 1 title with the maintainer before changing player
  strings. Do not guess.
- [ ] Finalize the app/product name with the maintainer before changing Eco Pro,
  bundle-facing metadata, or public branding. Current candidates include JKDX,
  JKDX HD, JKDX 4K, and JKDX iOS; do not pick one autonomously.

#### Input-source ownership and remapping

- [ ] Add a Jak 1 `Primary Controller` choice that can explicitly prefer Touch,
  a connected controller, or Mouse & Keyboard, with an honest Automatic/default
  behavior when the preferred source is unavailable.
- [ ] Preserve normal controller-first behavior while a physical controller is
  actively driving input; return to touch after touch activity according to a
  deterministic tested policy.
- [ ] Add remapping for all supported physical-controller inputs.
- [ ] Add remapping for all supported mouse-and-keyboard inputs.
- [ ] Define collision/duplicate-binding behavior, reset defaults, persistence,
  cloud sync, and unavailable-device presentation before calling remapping done.
- [ ] Implement mouse/trackpad camera control and WASD movement.
- [ ] Default keyboard face directions to Left = Square, Right = Circle,
  Up = Triangle, and Down = the Jak 1 shoulder/stats action.
- [ ] Default Escape to Start/Pause; map additional explicitly chosen keys to
  Stats rather than treating arbitrary typing as gameplay input.

#### Touch profiles and customization

- [ ] Implement Classic touch before deeper native-menu touch conversion so
  every touch device has an understandable fallback.
- [ ] Make Controls Modern select the existing Build 93 gesture/touch scheme.
- [ ] Make Controls Classic select a DualShock-style overlay with symmetrical
  sticks, PlayStation-like spacing, Jak 1 face/shoulder controls, no L2/R2
  overlay, and visibly intentional inactive/dead controls where requested.
- [ ] Keep Modern first and Classic second in the touch profile picker.
- [ ] Preserve current Modern behavior until its separate polish patch is
  physically accepted.
- [ ] Reduce the Modern movement stick's outer ring while retaining its accepted
  thumb/knob size.
- [ ] Move the Modern right stick inward from the bottom-trailing corner with an
  adaptive spacer capped at 200 points.
- [ ] Add Modern pinch-to-zoom gestures that map unambiguously to the existing Y
  zoom toggle: pinch in and pinch out must not accidentally perform each other's
  action.
- [ ] Replace the second Pause/Select pill with `SKIP` per the maintainer's
  latest direction. Define exactly which skippable state is active before
  emitting input; never bypass progression or corrupt game state.
- [ ] Make Start display `Pause` during gameplay and `Resume` while the native
  pause menu is open; keep Resume visible throughout that menu.
- [ ] Add a touch-layout editor for position pinning/movement, remapping,
  opacity, and size only after Classic and Modern have stable layout models.
- [ ] Store touch customization per game and sync it with that game's settings
  document.

#### Touch-friendly game and launcher interaction

- [ ] When a physical controller is active, preserve ordinary controller input
  and avoid intrusive touch chrome.
- [ ] When touch is active, make the app-owned settings/library surfaces use
  normal touch targets and scroll/swipe behavior.
- [ ] Investigate native Jak menu state/readback before attempting touch hit
  targets over GOAL-rendered rows; do not infer selection rectangles from a
  screenshot.
- [ ] Make the native pause menu usable by touch, beginning with swipe selection
  and explicit confirm/back controls, then direct row taps only if deterministic
  menu state is available.
- [ ] Replace raw X/Square/Triangle/Circle instructional chrome with clear touch
  actions where the app truly owns the target; Classic overlay remains the MVP
  fallback elsewhere.
- [ ] For warp gates, prefer a truthful `Touch gate to use warp gate` interaction
  only if gate focus/availability can be read safely. Otherwise show large
  explicit button controls and make the destination list swipe-selectable.
- [x] In portrait gameplay, top-align the renderer instead of vertically
  centering it so the remaining lower area is available to touch controls.
  - Validated worker branch `agent/build94-portrait-library` in
    `/private/tmp/GP-build94-portrait-library`, commit `f7669744`, with
    `Scripts/run-portrait-library-check.sh`; iOS compilation remains pending
    an initialized nested OpenGOAL checkout for the Metal build phase.

#### Haptics, stats, and skipping

- [ ] Add satisfying, state-appropriate touch-device haptics without duplicating
  every frame or vibrating for passive UI changes.
- [ ] Preserve and extend connected-controller rumble through Game Controller;
  use supported left/right localities when the device exposes them and degrade
  cleanly when it does not.
- [ ] Keep native Jak rumble fidelity separate from new app UI haptics so one
  source cannot mask or continuously restart the other.
- [ ] Preserve a reachable Stats action even though the latest touch pill is
  named `SKIP`; document controller and keyboard defaults.
- [ ] Treat `skip anything` as Investigating until cutscene/dialog/event state,
  safe completion hooks, and progression invariants are known. Do not implement
  a generic state jump or arbitrary GOAL call.

#### Game Center

- [ ] Add Game Center capability/entitlements only with a concrete authenticated
  runtime slice and App Store Connect configuration; a project entitlement alone
  is not a completed feature.
- [ ] Define player-visible friend presence/current-run information with an
  explicit privacy and refresh model.
- [ ] Define authoritative timing boundaries for current run, fastest completed
  run, and fastest completion percentage category before creating leaderboards.
- [ ] Confirm whether the completion category is 100% or 101% from actual game
  semantics and maintainer direction; do not guess.
- [ ] Decide offline behavior, retries, duplicate submissions, clock tampering,
  save imports, mods, and version/category compatibility before publishing times.

#### Candidate later-update scope

Keep this list at ten or fewer. These are currently the strongest candidates
to defer from the first post-Build-93 update because they require a larger
architecture, gameplay-semantic, backend, or physical-tuning gate:

1. Game Center friend presence and competitive run leaderboards.
2. Universal `skip anything` behavior.
3. Full draggable/resizable/opacity/remapping touch-layout editor.
4. Direct touch hit-testing for every native GOAL-rendered menu.
5. Complete controller and mouse/keyboard remapping UI.
6. Full mod manager/browser beyond a truthful local import entry.
7. Manual archived-save promotion/conflict-management UI.
8. Rich localized device/controller haptic design beyond preserved native
   rumble and a small UI-haptic proof.

Classic touch, portrait top alignment, Modern-first ordering, empty-section
removal, pause-gated app chrome, and the unified iCloud presentation are not in
this defer list; they are the preferred first executable slices.

## Code clarity

Write clean, human-readable code suitable for an open-source project.

- Prefer the simplest direct implementation that satisfies the current milestone.
- Reduce complexity whenever possible and do not over-engineer for hypothetical future work.
- Use clear names and control flow so the code explains itself.
- Minimize comments and the need for comments. Add one only when a non-obvious constraint or rationale cannot be made clear in the code itself.
