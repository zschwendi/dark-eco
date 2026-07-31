# AGENTS.md

This file defines the operating rules for coding agents working in this repository.

Read `docs/PROJECT_OVERVIEW.md` before planning or changing code. That document defines the project mission, architecture, legal boundaries, scope, and non-goals. When a prompt, issue, generated plan, or other document conflicts with it, `docs/PROJECT_OVERVIEW.md` takes priority unless a maintainer explicitly changes the project direction.

## Project objective

Build a native ARM64 iPadOS platform port of OpenGOAL for user-supplied, legally obtained Jak game data.

The first supported game is **Jak and Daxter: The Precursor Legacy**. Jak II is not active implementation scope until the Jak 1 platform foundation is stable.

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

> Establish the smallest reproducible path from the existing OpenGOAL ARM64 work to a signed iPadOS application that executes native project code on physical hardware.

Do not spend substantial effort on launcher polish, touch controls, Jak II, mod browsing, high-resolution settings, or public packaging before this platform path is proven.

## Code clarity

Write clean, human-readable code suitable for an open-source project.

- Prefer the simplest direct implementation that satisfies the current milestone.
- Reduce complexity whenever possible and do not over-engineer for hypothetical future work.
- Use clear names and control flow so the code explains itself.
- Minimize comments and the need for comments. Add one only when a non-obvious constraint or rationale cannot be made clear in the code itself.
