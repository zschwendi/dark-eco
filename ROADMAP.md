# GOALPad Roadmap

Date established: 2026-07-30

Status: Active

## Authority and scope

This roadmap turns the project direction in
[`docs/PROJECT_OVERVIEW.md`](docs/PROJECT_OVERVIEW.md) into an ordered execution
plan. The project overview remains authoritative if the documents conflict.
[`HANDOFF.md`](HANDOFF.md) records the latest commands, commits, validation
results, and blockers.

The goal is to progress from the current native ARM64 iPad application probe to
playing *Jak and Daxter: The Precursor Legacy* through the real OpenGOAL
implementation on a normally signed, non-jailbroken physical iPad.

Completing this roadmap means completing all ten stages below. Reaching an
early probe, a title screen, or one controlled gameplay area is a checkpoint,
not completion of the overall goal.

The active implementation goal remains open until the Stage 10 exit gate is
satisfied. Completing this document or any earlier stage must not be reported
as completing the overall goal.

## Fixed boundaries

- OpenGOAL C++, GOAL source, tooling, runtime behavior, and formats remain the
  implementation source of truth.
- Do not replace OpenGOAL with recreated gameplay, a toy engine, an emulator,
  or a Swift rewrite.
- Executable GOAL code must follow normal Apple signing rules. Do not require
  unrestricted JIT, writable executable memory, private entitlements, or a
  jailbreak.
- Retail game files remain user-supplied data and never enter the repository,
  CI artifacts, or hosted services.
- Jak 1 is the only active game implementation scope until its platform
  foundation is stable.
- Keep game simulation separate from rendering and presentation. iPadOS is the
  first implementation, but the runtime must not become directly dependent on
  one view, layer, screen size, lifecycle, or fixed camera.
- Where the current port already needs a platform boundary, prefer an equally
  small choice that leaves room for other Apple targets, multiple render
  views, stereo, and externally supplied view/projection matrices.
- Record future Apple-platform work instead of implementing it now. It must
  not delay booting and making Jak 1 playable on iPad.
- Simulator results support rapid iteration but do not establish physical-iPad
  compatibility.

## Current position

| Project milestone | Current state |
| --- | --- |
| Reproducible OpenGOAL ARM64 baseline | Implemented and verified |
| Native Swift/Objective-C++/C++ iPad process | Experimental; simulator verified; signed physical build and install verified |
| Signed native ARM64 instruction probe | Experimental; this is handwritten C++, not GOAL |
| Storage and Metal initialization | Experimental |
| Controller, audio, and lifecycle integration | Planned |
| User-owned Jak 1 import pipeline | Planned |
| Compiler-produced ARM64 GOAL execution | Experimental; ARM64 macOS and simulator verified, physical launch pending |
| OpenGOAL game frame or title screen | Planned |
| Playable gameplay slice | Planned |
| Jak 1 completion track | Planned |

The current application proves that Swift, Objective-C++, C++, statically
linked ARM64 code, logging, storage, and a Metal surface can coexist in an
iPadOS process. The Stage 2 compiler path also proves that the real top-level
GOAL expression `42` can produce deterministic ARM64 assembly that is linked
and signed with the app and executed in the iPad Pro M5 simulator. The signed
physical build is installed, but its automated launch was denied while the
iPad was locked. The app does not yet initialize general OpenGOAL runtime
state, load Jak data, or render the game.

## Required code and data pipelines

Executable code:

```text
OpenGOAL GOAL source
        ↓
ARM64 ahead-of-time compiler
        ↓
Mach-O object or assembly artifacts
        ↓
GOALPad link step
        ↓
Normal Apple code signing
```

User-owned data:

```text
User-selected Jak 1 source
        ↓
Local macOS verification and extraction
        ↓
Deterministic data-only package
        ↓
GOALPad import and compatibility validation
```

The two pipelines meet inside the native iPad OpenGOAL runtime. Runtime data
may remain relocatable and data-driven. Executable code must already be part
of the signed application image.

## Stage 1 — Establish the maintainable OpenGOAL fork

Outcome: GOALPad has a durable, reproducible place for narrowly scoped
OpenGOAL compiler and platform changes.

Required work:

1. Choose the GitHub user or organization that owns the dedicated fork.
2. Fork `open-goal/jak-project`.
3. Preserve `open-goal/jak-project` as the fork's `upstream` remote.
4. Point the `OpenGOAL` submodule at the fork while retaining the currently
   verified upstream commit.
5. Document the update and upstream-sync procedure.
6. Verify a clean clone can initialize and build the pinned submodule.

Exit gate:

- The parent repository points only to a child commit that is fetchable from
  the documented remote.
- The pinned ARM64 `gk` and `goalc-test` baseline still builds and passes.

Current blocker:

- The maintainer must choose whether the fork lives under `zschwendi`,
  `zephyrstudiosllc`, or another explicitly named owner.
- The configured GitHub credential is currently invalid, so the selected owner
  must also be authenticated before publication.

## Stage 2 — Compile one real GOAL workload for ARM64

Outcome: An actual GOAL expression is compiled ahead of time and executes as
normally signed ARM64 code.

Required work:

1. Add architecture-selected ARM64 register and calling-convention metadata.
2. Test X0-X7 arguments, X0 return, and OpenGOAL's X20/X21/X22 special
   registers.
3. Keep ARM64 GPR and SIMD register banks distinguishable, and make both
   register allocators use the selected target metadata.
4. Implement the minimum ARM64 function emission and IR operations required by
   the top-level GOAL literal `42`: `IR_LoadConstant64`, `IR_Return`, and
   `IR_Null`. Do not begin with a `defun`, which expands the first IR slice.
5. Reject unsupported spills, saved-register handling, SIMD, calls,
   relocations, and other unimplemented paths explicitly.
6. Add a deterministic compiler test requiring the eight-byte
   `mov x0, #42; ret` result.
7. Export the verified instructions as generated Apple assembly in the build
   output and assemble them with Xcode/Clang. Do not treat OpenGOAL's V3 runtime
   object format as a signed Mach-O artifact.
8. Link the generated artifact into GOALPad before code signing.
9. First call the generated entry through the ordinary static ARM64 ABI, then
   add a defined static OpenGOAL wrapper that initializes the X20/X21/X22
   runtime-state contract.

Exit gate:

- The compiler test proves that real GOAL source produced the expected ARM64
  instructions.
- ARM64 macOS executes the statically linked artifact.
- A signed physical-iPad build executes the same representative GOAL workload
  without JIT or writable executable pages.

This isolated artifact proves the chosen direction. It does not complete the
general signed code/data object and loading model in Stage 4.

Current progress:

- Child commit
  `79f22008c3119bf79297f41d586ab4f75725a36e` implements required work 1-8
  for the exact top-level literal `42`.
- The parent preserves that unpublished child commit as
  `patches/OpenGOAL/0001-Add-minimal-ARM64-GOAL-AOT-proof-AI-assisted.patch`
  while the official submodule stays at its fetchable upstream pin.
- The generated Apple assembly is checked into the app as a transitional
  artifact and has executed on ARM64 macOS and the named iPad Pro M5
  simulator.
- The app has built, signed, and installed on the physical iPad Pro M5.
  Physical launch was denied because the iPad was locked.
- Required work 9 remains incomplete: add the static X20/X21/X22 OpenGOAL
  state wrapper and execute the generated workload through it on physical
  hardware.

## Stage 3 — Expand the ARM64 GOAL compiler backend

Outcome: The backend can compile the increasing subset of real Jak 1 GOAL code
needed by the boot path.

Required work:

1. Add integer, memory, control-flow, call, stack, symbol, and relocation
   support in small test-driven increments.
2. Add floating-point and SIMD support only when demanded by representative
   Jak 1 code.
3. Make normal compiler entry points select the requested instruction set
   instead of assuming x86.
4. Preserve x86 host behavior and upstream tests after every increment.
5. Drive implementation from the next real Jak 1 compilation failure rather
   than attempting an unvalidated complete rewrite.

Exit gate:

- The selected Jak 1 initialization objects compile deterministically for
  ARM64.
- Compiler and register-allocation tests cover every newly supported path.
- Existing documented host targets remain healthy.

## Stage 4 — Replace the desktop executable-object model

Outcome: OpenGOAL code and runtime data have a signed, iPad-compatible artifact
and loading model.

Required work:

1. Document which GOAL code is compiled, what artifact is produced, and when
   Apple signs it.
2. Separate build-time executable code from runtime-relocatable data.
3. Define static symbol, function, top-level initialization, and relocation
   tables.
4. Replace the desktop path that copies and patches executable code in
   read-write-execute memory.
5. Keep data-only mods dynamically loadable where practical.
6. Treat executable-code mods as a separate rebuild and resign workflow.

Exit gate:

- Representative linked GOAL objects initialize through the new static code
  and runtime data model.
- No ordinary iPad path allocates writable executable memory.
- Unsupported object or mod forms fail clearly.

## Stage 5 — Build a portable OpenGOAL runtime for iPadOS

Outcome: A minimal real Jak 1 runtime subset compiles and links into GOALPad.

Required work:

1. Isolate the runtime/kernel state, memory model, object loading, symbols,
   streaming, logging, and call trampolines needed by Jak 1.
2. Keep desktop OpenGL, windowing, host input, listener/debugger, and unrelated
   tools outside the iPad target.
3. Add a narrow ownership-safe Objective-C++ API instead of exposing broad C++
   implementation details to Swift.
4. Make currently required platform assumptions explicit behind narrow
   interfaces without beginning a speculative abstraction campaign.
5. Add integration tests for initialization, failure reporting, and teardown.

Exit gate:

- The portable subset cross-compiles for `arm64-apple-ios`.
- GOALPad initializes and tears down real OpenGOAL runtime state.
- The ARM64 macOS development target and upstream host tools remain healthy.

## Stage 6 — Complete the Apple platform layer

Outcome: OpenGOAL receives the iPad services required for sustained gameplay.

Required work:

1. Connect supported game controllers to the runtime input model.
2. Initialize audio and handle interruptions and route changes.
3. Preserve state across foregrounding, backgrounding, suspension, and memory
   pressure.
4. Define app-controlled game-data, save, settings, cache, and log locations.
5. Implement save and load operations with recoverable error handling.
6. Establish frame timing and display lifecycle behavior.
7. Narrow the application to documented iPadOS destinations or split
   diagnostic targets deliberately, eliminating unsupported platform claims
   without hard-coding the runtime against later Mac or iPhone frontends.

Exit gate:

- A controller drives a deterministic runtime test.
- Audio and graphics initialize on physical hardware.
- Lifecycle transitions do not corrupt runtime or save state.
- Memory-pressure behavior is measured and documented.

## Stage 7 — Establish the real renderer path

Outcome: Actual OpenGOAL scene data renders through an iPad-compatible graphics
path.

Required work:

1. Audit the current renderer and its platform dependencies.
2. Identify the smallest viable route to a real OpenGOAL test scene.
3. Define or reuse a narrow rendering interface where needed.
4. Evaluate an existing portable layer before committing to a broad rewrite.
5. Implement direct Metal support where it is the smallest maintainable
   long-term solution.
6. Preserve renderer correctness before adding resolution or visual polish.
7. Keep final presentation separate from simulation and avoid an unnecessary
   one-view, one-layer, fixed-size, or fixed-camera contract. Do not implement
   multi-view, stereo, external-camera, or visionOS behavior during this stage
   unless the iPad path directly requires the same boundary.

Exit gate:

- Synthetic geometry renders through the real renderer boundary.
- Frame presentation works on the physical iPad.
- GPU errors, memory use, and frame timing are observable.

## Stage 8 — Create the bring-your-own-game importer

Outcome: The maintainer can prepare supported Jak 1 data locally and import it
into GOALPad without adding retail content to the repository.

Required work:

1. Build a macOS command-line or application importer around compatible
   OpenGOAL extraction tooling.
2. Accept a user-selected source image or extracted directory.
3. Verify supported revision and integrity metadata.
4. Reject unknown, incomplete, or corrupted inputs clearly.
5. Produce a deterministic data-only package.
6. Import through supported Apple file workflows.
7. Validate compatibility before starting the runtime.
8. Keep imported data separate from saves and settings.

Exit gate:

- A supported user-owned Jak 1 source produces a reproducible package.
- No retail files enter Git, CI, logs, or hosted services.
- GOALPad imports and validates the package on physical hardware.

## Stage 9 — Boot Jak 1 through the real OpenGOAL path

Outcome: GOALPad reaches a recognizable title-screen or first-game-frame path
using real OpenGOAL code and user-supplied data.

Required work:

1. Initialize the real OpenGOAL kernel and runtime state.
2. Load one prepared real object through the iPad object/data model.
3. Load one real asset, then static level geometry.
4. Execute the required initialization GOAL.
5. Route controller input into the game runtime.
6. Produce actionable logs for every boot-stage failure.
7. Advance one dependency at a time until the title screen is stable.

Exit gate:

- A recognizable Jak 1 frame or title screen renders from user-supplied data.
- Input reaches the game runtime.
- The path is reproducible after a clean install and import.
- The result is captured on a signed physical iPad build.

## Stage 10 — Reach and stabilize playable Jak 1

Outcome: Jak enters gameplay and progresses toward being completable on
supported iPad hardware.

Required work:

1. Enter one controlled gameplay area.
2. Make camera, movement, collision, animation, audio, and streaming operate
   together.
3. Make saving and loading reliable.
4. Measure and improve memory use, frame pacing, thermal behavior, and crash
   resilience on physical hardware.
5. Track remaining platform blockers by subsystem.
6. Add regression tests, original fixtures, or reproducible save states where
   possible.
7. Expand coverage until the game can be completed without platform-specific
   blockers.
8. Document installation, controller setup, supported data revisions, and
   known limitations.

Exit gate:

- A controlled gameplay slice is repeatably playable.
- The game can ultimately be completed on at least one documented supported
  iPad configuration.
- Remaining limitations are explicit and do not contradict the supported
  claim.

## Project milestone mapping

| Roadmap stages | Project overview milestones |
| --- | --- |
| Existing baseline plus Stage 1 | Milestone 0 — Reproducible baseline |
| Existing platform probe and Stage 5 integration | Milestone 1 — Native iPad process |
| Stages 5-7 | Milestone 2 — Platform foundation |
| Stage 8 | Milestone 3 — Asset pipeline |
| Stages 2-4 | Milestone 4 — GOAL execution proof |
| Stages 7 and 9 | Milestone 5 — First game frame |
| Early Stage 10 | Milestone 6 — Playable slice |
| Remaining Stage 10 | Milestone 7 — Jak 1 completion track |
| Deferred until afterward | Milestone 8 — Modding and polish |

The order is risk-driven rather than strictly numerical. The synthetic GOAL
execution proof intentionally begins before retail-data import because it
attacks the primary architecture risk without requiring copyrighted data.

## Validation lanes

### ARM64 macOS

Use for fast compiler, register allocator, artifact, runtime, and host
regression tests. A passing macOS test does not prove iPad compatibility.

### iPad Pro 11-inch M5 simulator

Use the existing iOS 26.5 simulator for routine build, install, launch, UI,
logging, storage, and deterministic integration checks.

- Reuse `/private/tmp/GOALPad-sim` instead of creating multiple DerivedData
  trees.
- Run memory-intensive builds serially.
- Check memory and disk pressure before large builds.
- Boot the simulator only for validation and shut it down afterward.
- Do not treat simulator results as executable-code, controller, audio,
  graphics, performance, or thermal proof for physical iPad hardware.

### Physical iPad

Use physical hardware at authoritative gates:

- Compiler-produced signed GOAL execution.
- Metal rendering and presentation.
- Controller input.
- Audio and lifecycle behavior.
- Import, storage, and saves.
- Memory pressure, performance, and thermals.
- Title screen, gameplay, and completion claims.

Record build, install, launch, logs, and observed behavior separately.

## Subagent execution policy

Subagents are required whenever a bounded task can run independently without
creating overlapping edits.

Current agent configuration:

- Model: fast `gpt-5.6-terra`
- Reasoning effort: `xhigh`
- If that configuration is unavailable, report it instead of silently
  downgrading.

Operating rules:

1. The primary agent owns scope, architecture decisions, integration, commits,
   and final validation.
2. Before each implementation checkpoint, delegate independent audits or
   non-overlapping work where practical. Typical lanes are:
   - OpenGOAL compiler/runtime and upstream compatibility.
   - Xcode, Apple platform integration, and physical-device validation.
   - Tests, build reproducibility, documentation, and Git state.
3. Every subagent must read `AGENTS.md` and the relevant project documents
   before acting.
4. Prefer read-only parallel audits when agents would otherwise touch the same
   files.
5. Assign edits only when file ownership is explicit and non-overlapping.
6. The primary agent reviews all subagent findings and diffs; subagent output
   is not validation by itself.
7. Record material delegation, conclusions, exact commands, and unresolved
   disagreements in `HANDOFF.md` at each checkpoint.
8. Keep builds serial when parallel compilation would create memory pressure.
   Agent parallelism does not imply parallel heavy builds.
9. Do not delegate maintainer decisions, destructive actions, credential
   entry, proprietary-data handling, or physical-device claims.
10. Stop delegation when it no longer improves the narrow current checkpoint.

## Checkpoint and commit policy

- Each checkpoint must be a small coherent change.
- Build every affected available target and run the relevant deterministic
  tests.
- Preserve the first useful failure and distinguish pre-existing failures from
  regressions.
- Update `HANDOFF.md` with exact commands, results, commits, blockers, and the
  next smallest task.
- Commit each verified checkpoint with `(AI-assisted)` in the message when
  required by the pinned OpenGOAL contribution rules.
- Do not advance the roadmap status based only on source inspection.

## Current checkpoint

Stages 1 and 2 are active in parallel.

Stage 1 is blocked on the durable fork owner and working GitHub authentication.
Until publication, keep the official submodule pin clean and preserve the
verified child commit through the repository patch.

The next Stage 2 actions are:

1. Retry the installed app after the physical iPad is unlocked and record
   build, sign, install, launch, and runtime-result evidence separately.
2. Define a minimal static wrapper for X20/X21/X22 OpenGOAL runtime state.
3. Add deterministic macOS tests for the wrapper and compiler-produced entry.
4. Link and execute that boundary in the simulator and then the signed
   physical-device build.
5. Make ARM64 call-clobber handling target-aware before enabling call-bearing
   GOAL source in Stage 3.

No proprietary game data is needed before Stage 8.
