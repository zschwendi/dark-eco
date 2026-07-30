# GOALPad — Project Overview

> **Status:** Early feasibility and platform-port project
> **Working name:** GOALPad
> **Target platform:** iPadOS on Apple silicon
> **Initial game target:** *Jak and Daxter: The Precursor Legacy*
> **Later target:** *Jak II* after the first game is stable
> **Upstream foundation:** OpenGOAL
> **Affiliation:** Unofficial community project; not affiliated with Sony Interactive Entertainment, Naughty Dog, or the OpenGOAL team

## Purpose of this document

This document defines what the project is, what it is not, and how contributors and coding agents should make technical decisions.

Read this before changing architecture, adding dependencies, rewriting upstream code, creating a roadmap, or implementing a feature. When another document, issue, prompt, or agent-generated plan conflicts with this overview, this document takes priority unless maintainers explicitly update it.

## Mission

Build an open-source, native ARM64 iPadOS platform port of OpenGOAL that allows users to run supported Jak games from game data they legally provide themselves.

The intended result is a high-resolution, controller-friendly iPad version with no PlayStation 2 CPU emulation, no bundled copyrighted game assets, and a path toward custom levels and other OpenGOAL-compatible mods.

## The intended user experience

A user should eventually be able to:

1. Obtain the project through a supported open-source or sideloading workflow.
2. Provide a supported, legally obtained PlayStation 2 copy of the game.
3. Run a desktop importer that verifies and extracts the required game data.
4. Transfer or install the prepared data for use by the iPad app.
5. Launch the game natively on iPadOS.
6. Play with a supported controller at resolutions and presentation settings appropriate for modern iPads.
7. Install supported data-driven mods, including compatible custom levels, without receiving original game assets from this project.

The exact installation workflow may change during development. The ownership and asset-separation rules may not.

## Definition of “native”

For this project, **native** means:

- The application runs as an ARM64 iPadOS process.
- Gameplay does not run through a PlayStation 2 CPU emulator.
- The project uses OpenGOAL's reconstructed GOAL code and native runtime approach.
- Platform integration uses iPadOS APIs where practical.
- Rendering ultimately targets an iPad-compatible graphics path, preferably Metal.
- Input uses Apple's Game Controller framework directly or through a deliberately retained portability layer.
- Audio uses an iPad-compatible native or portable backend.

Native does **not** mean every source file must be rewritten in Swift.

## Language and runtime policy

The app should feel like a first-class iPad application, but rewriting OpenGOAL into Swift is not the project goal.

Expected language boundaries:

```text
Swift / SwiftUI
    App lifecycle, launcher UI, settings, import status, saves,
    file management, touch UI, iPad-specific presentation

Objective-C++ bridge
    Stable boundary between Swift and the existing native runtime

C++
    OpenGOAL tools and runtime, portable engine/platform code,
    renderer integration, asset loading, compiler support

GOAL
    Reconstructed game and engine logic supplied by OpenGOAL

Metal / Apple frameworks
    iPad rendering, input, audio, storage, and system integration
```

### Hard rule

Do not begin a wholesale C++-to-Swift or GOAL-to-Swift translation. Such a rewrite would discard the main value of OpenGOAL, greatly increase correctness risk, and move the project away from upstream compatibility.

Swift should own the iPad application shell and platform-facing features. Existing OpenGOAL code should remain in its native languages unless a specific component must be replaced for iPadOS compatibility.

## Project scope

### Initial scope: Jak 1

The first complete target is *Jak and Daxter: The Precursor Legacy*.

The project must prove the following before Jak II becomes active scope:

- The iPad app launches reliably on physical hardware.
- The runtime executes natively on ARM64.
- Supported Jak 1 data can be imported without distributing game assets.
- The game reaches its title screen and boots into gameplay.
- Rendering, controller input, audio, saving, and level streaming work.
- A substantial portion of the game can be completed without platform-specific blockers.
- The build remains reproducible and documented.

### Later scope: Jak II

Jak II begins only after Jak 1 has a stable platform foundation. Work that is naturally shared between games may account for Jak II, but Jak II-specific implementation must not delay the first playable Jak 1 milestone.

### Potential future scope

These are allowed later but are not prerequisites for the first complete port:

- Jak II support
- Touch controls
- Keyboard support
- Higher frame-rate modes
- External display support
- Custom aspect ratios
- Advanced mod management
- On-device mod browsing
- Custom-level workflows
- iPhone support
- tvOS support
- Upstreamable Apple-platform abstractions

## Explicit non-goals

This project is not:

- A PlayStation 2 emulator.
- A wrapper around PCSX2 or another emulator.
- A demake, remake, or recreation of Jak gameplay.
- A new engine inspired by Jak.
- A full rewrite of OpenGOAL in Swift.
- A repository for ROMs, ISOs, extracted game files, textures, models, audio, dialogue, cinematics, keys, or proprietary SDK material.
- An attempt to bypass ownership verification or copyright protection.
- Initially an App Store product.
- A promise to support every revision, region, mod, iPad, or controller immediately.
- A reason to destabilize working OpenGOAL behavior merely to make the code look more “Apple-native.”

## Core engineering principles

### 1. Preserve upstream compatibility

OpenGOAL continues to evolve. Keep the downstream delta understandable and as small as practical.

Prefer:

- Platform abstractions over invasive rewrites.
- Focused patches over broad refactors.
- Upstream-compatible C++ changes.
- Existing OpenGOAL tests and conventions.
- Clearly isolated Apple-specific code.
- Periodic upstream synchronization.

Avoid:

- Renaming or reorganizing unrelated upstream systems.
- Reformatting large areas without functional need.
- Replacing working portable code solely due to stylistic preference.
- Forking asset formats or mod formats without necessity.

### 2. Build after every meaningful change

Every implementation step must leave the project in a known buildable state.

At minimum, changes should preserve whichever targets are currently declared healthy:

- OpenGOAL host tools
- ARM64 macOS development target
- iPadOS engine/library target
- iPadOS application target
- Relevant unit and compiler tests

Do not stack multiple speculative architectural changes before validating the first one.

### 3. Prove the narrowest slice first

The project should advance through executable proofs, not large unvalidated rewrites.

A preferred progression is:

1. Build an unmodified or minimally modified OpenGOAL target on ARM64 macOS.
2. Build selected portable runtime code for iPadOS.
3. Launch a Swift iPad app linked to a minimal native C++ library.
4. Initialize logging, storage, input, and a graphics surface on physical iPad hardware.
5. Render a controlled test frame.
6. Load one user-extracted asset.
7. Load static level geometry.
8. Execute a minimal prepared GOAL workload.
9. Reach Jak 1's title screen.
10. Enter gameplay and close platform gaps one subsystem at a time.

### 4. Separate code from copyrighted game data

The public repository must remain useful without containing original game content.

The repository may contain:

- Original project code.
- OpenGOAL-derived code under its applicable license.
- Build scripts.
- Import and verification tools.
- Tests using original or synthetic fixtures.
- Documentation.
- Metadata required to identify supported game revisions, where legally appropriate.

The repository must not contain:

- Original game assets.
- Extracted files from the game disc.
- Disc images.
- Audio, video, dialogue, textures, models, animations, or level data from the retail games.
- Proprietary Sony or Naughty Dog code not already lawfully present in the upstream open-source project.
- Private keys, signing material, or circumvention tooling.

### 5. Do not rely on unrestricted runtime code generation

The desktop OpenGOAL architecture includes a compiler and live-development workflow. iPadOS imposes stricter executable-code and signing constraints than desktop platforms.

The default project strategy is therefore:

- Prefer ahead-of-time preparation of executable game code where required.
- Keep generated executable code within normal Apple signing rules.
- Do not make a private JIT entitlement, jailbreak, or security bypass a requirement for ordinary use.
- Preserve data-driven mods as dynamically loadable where possible.
- Treat runtime code mods separately from data-only mods because they may require recompilation and resigning.

The exact AOT boundary requires technical validation. Agents must not pretend this problem is solved until a signed iPad build executes a representative GOAL workload on physical hardware.

### 6. Physical-device results are authoritative

Simulator success is useful but insufficient. Architecture, executable memory, Metal behavior, controller support, storage access, thermal behavior, and performance must be validated on real iPad hardware.

## Proposed architecture

```text
┌────────────────────────────────────────────────────────────┐
│ SwiftUI iPad application                                   │
│                                                            │
│ Launcher · Settings · Import status · Saves · Touch UI     │
└──────────────────────────────┬─────────────────────────────┘
                               │ Objective-C++ API
┌──────────────────────────────▼─────────────────────────────┐
│ Apple platform layer                                       │
│                                                            │
│ Lifecycle · Files · Logging · Controller · Audio · Display │
└──────────────────────────────┬─────────────────────────────┘
                               │
┌──────────────────────────────▼─────────────────────────────┐
│ OpenGOAL native runtime and shared C++ systems              │
│                                                            │
│ GOAL runtime · Loaders · Streaming · Game integration      │
└──────────────────────────────┬─────────────────────────────┘
                               │
┌──────────────────────────────▼─────────────────────────────┐
│ Prepared ARM64 GOAL game code                              │
│                                                            │
│ Signed/AOT-compatible execution strategy                    │
└──────────────────────────────┬─────────────────────────────┘
                               │
┌──────────────────────────────▼─────────────────────────────┐
│ User-supplied extracted game data                           │
│                                                            │
│ Never stored in or distributed by the public repository     │
└────────────────────────────────────────────────────────────┘
```

## Renderer strategy

The desired shipping renderer is Metal-compatible and performant on modern iPads. However, the project must not begin with an unnecessary full renderer rewrite before the rest of the runtime can be validated.

Required sequence:

1. Audit the current OpenGOAL rendering architecture and platform dependencies.
2. Identify the smallest viable path to render a test scene on iPad.
3. Define a clean rendering interface where one does not already exist.
4. Choose between adapting an existing portable layer and implementing a direct Metal backend.
5. Preserve renderer correctness before adding visual enhancements.

A direct Metal backend is the preferred long-term direction, not permission to rewrite every rendering subsystem immediately.

## Import and ownership model

The project follows a bring-your-own-game model.

### Desktop importer responsibilities

A macOS importer or command-line tool should eventually:

- Accept a user-selected game image or extracted disc directory.
- Verify that the input matches a supported retail revision.
- Reject unknown or corrupted input with a clear error.
- Invoke or reuse OpenGOAL extraction and preparation tooling.
- Generate only the files needed by the iPad port.
- Produce a deterministic data package or installable development output.
- Avoid uploading the user's game data to any service.
- Avoid bundling game data into the public repository or CI artifacts.

### iPad app responsibilities

The iPad app should:

- Detect whether valid prepared game data is installed.
- Explain what is missing without directing users to piracy sources.
- Import a prepared package through supported Apple file workflows where possible.
- Store game data in an appropriate app-controlled location.
- Keep saves and user settings separate from imported source data.
- Verify compatibility before launching the runtime.

## Modding policy

Mod support is a core long-term goal, but it must build on OpenGOAL compatibility rather than inventing an unrelated ecosystem.

Priority order:

1. Preserve compatibility with existing data formats and workflows where practical.
2. Support replacement assets and custom levels that do not require new executable code.
3. Define a safe, versioned mod manifest for the iPad port if needed.
4. Separate data-only mods from executable-code mods in the UI and documentation.
5. Never distribute original game data inside a mod example or test fixture.

Modding must not block initial game boot.

## Distribution strategy

### Initial distribution

The first public releases should prioritize:

- Source code.
- Reproducible Xcode build instructions.
- A macOS import/preparation tool.
- User-owned game data.
- Personal signing or supported sideloading workflows.

### Deferred distribution decisions

Do not promise any of the following until technical and legal review is complete:

- App Store distribution.
- TestFlight distribution.
- A prebuilt IPA containing prepared game code.
- Automatic cloud import or conversion.
- A hosted game-data conversion service.

The open-source repository can be public before the end-user installation process is polished.

## Repository strategy

The project should retain upstream history and make synchronization possible.

Preferred approaches:

1. A long-lived fork of `open-goal/jak-project` with Apple-platform work isolated by directory and commit scope; or
2. A thin iPad application repository with OpenGOAL pinned as a submodule or dependency, provided required engine changes can remain reviewable and maintainable.

Do not copy the OpenGOAL source into a new repository without preserving attribution, license text, and a practical upstream-update path.

A possible top-level structure is:

```text
/
├── apps/
│   ├── ipad/                  # Swift/SwiftUI application
│   └── importer-macos/        # Ownership verification and data preparation
├── game/                      # OpenGOAL game/runtime source or upstream tree
├── platform/
│   └── apple/                 # Shared Apple platform implementation
├── renderer/
│   └── metal/                 # Metal-specific implementation when introduced
├── tools/
│   ├── package-builder/
│   └── validation/
├── tests/
│   ├── platform-apple/
│   └── synthetic-assets/
└── docs/
    ├── PROJECT_OVERVIEW.md
    ├── ARCHITECTURE.md
    ├── BUILDING.md
    ├── LEGAL_AND_CONTENT_POLICY.md
    ├── SUPPORTED_GAME_VERSIONS.md
    └── ROADMAP.md
```

The final structure should follow upstream conventions where possible. This example is directional, not an instruction to reorganize OpenGOAL immediately.

## Milestones

### Milestone 0 — Reproducible baseline

Success means:

- The chosen OpenGOAL upstream revision is pinned.
- Existing host builds and relevant tests pass.
- ARM64 macOS build status is documented accurately.
- Development setup is reproducible.
- No iPad-specific changes have broken existing targets.

### Milestone 1 — Native iPad process

Success means:

- A SwiftUI app launches on a physical iPad.
- It links a minimal C++ library through Objective-C++.
- CI or a documented local command builds the iPad target.
- Logging and crash diagnostics cross the language boundary.

### Milestone 2 — Platform foundation

Success means:

- File storage paths are defined.
- A controller can drive a test harness.
- Audio and graphics devices initialize.
- App backgrounding and foregrounding do not corrupt state.
- A renderer test displays on physical hardware.

### Milestone 3 — Asset pipeline

Success means:

- A supported Jak 1 source image is verified on macOS.
- Required assets are extracted and packaged deterministically.
- No original assets enter source control or CI artifacts.
- The iPad app validates and loads a user-generated package.

### Milestone 4 — GOAL execution proof

Success means:

- A representative GOAL workload executes natively on iPad ARM64.
- The chosen JIT/AOT/interpreter boundary is documented with measured evidence.
- The implementation does not rely on jailbreak-only behavior.
- Compiler and runtime tests cover the new execution path.

### Milestone 5 — First game frame

Success means:

- The app loads real user-supplied Jak 1 data.
- A recognizable game frame or title-screen path renders.
- Input reaches the game runtime.
- Failures produce actionable logs rather than silent hangs.

### Milestone 6 — Playable slice

Success means:

- The game enters a controlled gameplay area.
- Camera, movement, collision, animation, audio, and streaming operate together.
- Saving and loading work.
- Performance and thermal behavior are measured on at least one target iPad.

### Milestone 7 — Jak 1 completion track

Success means:

- Platform-specific blockers are tracked by subsystem.
- Regressions have reproducible tests or save states where possible.
- The game can be completed on supported hardware.
- Installation and controller setup are documented for non-contributors.

### Milestone 8 — Modding and polish

Success means:

- Supported mod directories and package rules are defined.
- At least one original, legally distributable custom-level sample works.
- Resolution, aspect ratio, frame pacing, and accessibility options are exposed appropriately.
- The project is ready to evaluate Jak II as an active target.

## Agent operating rules

Coding agents working in this repository must follow these rules:

1. Read this document and the current build instructions before proposing work.
2. Inspect the actual code before describing architecture.
3. Never claim a subsystem works without building or testing it.
4. Never add copyrighted game assets, extracted retail files, or ROM links.
5. Never replace working upstream systems simply to increase Swift usage.
6. Do not start Jak II-specific work unless the assigned task explicitly requires it.
7. Keep changes narrow and preserve existing behavior.
8. Run the smallest relevant tests after each change, then run the declared project build gate.
9. Record platform assumptions and unsupported cases instead of hiding them.
10. Treat physical iPad behavior as the final authority for iPad-specific claims.
11. Do not add JIT, executable-memory, signing, or entitlement workarounds without an explicit architecture decision and documented rationale.
12. Do not change the ownership/import model without maintainer approval.
13. Prefer an incomplete but building milestone over a sprawling unbuildable branch.
14. Update documentation when a verified implementation changes an assumption in this overview.

## Pull-request acceptance criteria

A pull request should normally include:

- A focused explanation of the problem solved.
- The platforms and game targets affected.
- Exact build and test commands run.
- Results from physical hardware when iPad-specific behavior changed.
- Confirmation that no proprietary game data was added.
- Screenshots or logs only when they contain no copyrighted assets that the repository should not distribute.
- A rollback path or clear isolation when the work is experimental.

Changes that break established targets should not merge unless the break is explicitly accepted and documented.

## Legal and project-boundary statement

This project is intended as an open-source interoperability and platform-port effort. Users must provide their own legitimately obtained supported copy of the game. The project does not provide the games or their original assets.

OpenGOAL's repository is distributed under the ISC License, but that does not grant rights to Sony or Naughty Dog trademarks, retail game assets, or other third-party materials. Contributors remain responsible for ensuring their additions are lawful and properly licensed.

This document is a project policy, not legal advice. Any public binary-distribution plan should receive separate review before release.

## Current upstream facts informing this plan

As of July 2026:

- OpenGOAL describes its current port as native x86-64 and requires users to supply a legally obtained PlayStation 2 copy because original game assets are not included.
- Jak 1 is treated as polished and complete by the OpenGOAL project; Jak II is broadly playable but remains labeled beta due to known issues.
- OpenGOAL has active ARM64 compiler work, including ARM64 compiler tests on macOS and implementation of a large portion of the ARM64 instruction backend.
- The OpenGOAL source repository uses the ISC License.

These facts can change. Update this section when the project pins a newer upstream revision.

## Decision summary

The following decisions are currently binding:

- **Project type:** Native iPadOS platform port of OpenGOAL.
- **First game:** Jak 1.
- **Second game:** Jak II, after the platform foundation is stable.
- **Emulation:** Not used for gameplay.
- **Primary app language:** Swift/SwiftUI.
- **Existing runtime languages:** Retained where practical; C++ and GOAL are not being wholesale rewritten.
- **Graphics direction:** iPad-compatible renderer with Metal as the preferred long-term backend.
- **Game data:** Supplied and prepared by the user; never distributed by this repository.
- **Runtime code generation:** Do not rely on unrestricted JIT; validate an AOT-compatible approach.
- **Distribution:** Public source first; prebuilt binary strategy deferred.
- **Modding:** Important, but secondary to reliable game boot and playability.
- **Quality gate:** The project must remain buildable after each meaningful change.

## One-sentence test for scope decisions

A proposed change belongs in this project when it directly helps OpenGOAL run reliably and natively on iPadOS using user-supplied game data without turning the project into an emulator, a rewrite, or a distributor of copyrighted game content.

## References

- OpenGOAL repository and technical overview: <https://github.com/open-goal/jak-project>
- OpenGOAL website and FAQ: <https://opengoal.dev/> and <https://opengoal.dev/docs/faq/>
- OpenGOAL Q2 2026 progress report: <https://opengoal.dev/blog/progress-report-q2-2026/>
- OpenGOAL ISC license: <https://github.com/open-goal/jak-project/blob/master/LICENSE>
- Apple executable/JIT entitlement documentation: <https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.allow-jit>

## Architectural Principles

### Swift is a platform language, not a rewrite target

The goal of this project is a native iPadOS port of OpenGOAL—not a reimplementation of OpenGOAL.

Swift should be used where it provides clear platform advantages:
- SwiftUI application shell
- App lifecycle
- Settings
- File import/export
- GameController integration
- Apple-specific APIs

The OpenGOAL runtime, GOAL compiler, and reconstructed game logic should remain intact unless there is a measurable technical benefit to replacing a component.

Long-term engine modernization is encouraged through clean interfaces rather than wholesale rewrites. Any subsystem replacement must preserve behavior and improve maintainability, performance, portability, or platform integration.
