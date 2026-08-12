# GOALPad — Project Overview

> **Status:** Experimental playable Jak 1 port; Build 154 is the accepted conventional-2D baseline within its physically tested scope
> **Working name:** GOALPad
> **Public product name:** Dark Eco
> **App Store subtitle:** Native OpenGOAL Runtime
> **Primary target:** iPadOS on Apple silicon; the shared windowed app also supports macOS and visionOS
> **Initial game target:** *Jak and Daxter: The Precursor Legacy*
> **Later target:** *Jak II* after the first game is stable
> **Upstream foundation:** OpenGOAL
> **Affiliation:** Unofficial community project; not affiliated with Sony Interactive Entertainment, Naughty Dog, or the OpenGOAL team

## Purpose of this document

This document defines what the project is, what it is not, and how contributors and coding agents should make technical decisions.

Read this before changing architecture, adding dependencies, rewriting upstream code, creating a roadmap, or implementing a feature. When another document, issue, prompt, or agent-generated plan conflicts with this overview, this document takes priority unless maintainers explicitly update it.

## Mission

Build an open-source, native ARM64 Apple-platform port of OpenGOAL that allows
users to run supported Jak games from game data they legally provide themselves.
iPadOS remains the primary correctness and performance target; Dark Eco also
builds and runs as a conventional windowed Apple Silicon macOS app.

The intended result is a high-resolution, controller-friendly iPad and Mac
version with no PlayStation 2 CPU emulation, no bundled copyrighted game assets,
and a path toward custom levels and other OpenGOAL-compatible mods.

## The intended user experience

A user should eventually be able to:

1. Obtain Dark Eco through a supported open-source, Mac, or sideloading workflow.
2. Provide a supported, legally obtained PlayStation 2 copy of the game.
3. Use Dark Eco or the desktop tooling to verify and prepare the required game data.
4. Keep that prepared data on the Mac or transfer it to another Apple device.
5. Launch the game natively on iPadOS or Apple Silicon macOS.
6. Play with a supported controller at platform-appropriate resolutions and presentation settings.
7. Install supported data-driven mods, including compatible custom levels, without receiving original game assets from this project.

The exact installation workflow may change during development. The ownership and asset-separation rules may not.

## Definition of “native”

For this project, **native** means:

- The application runs as a native ARM64 process on the selected Apple platform.
- Gameplay does not run through a PlayStation 2 CPU emulator.
- The project uses OpenGOAL's reconstructed GOAL code and native runtime approach.
- Platform integration uses Apple platform APIs where practical.
- Rendering uses the shared Metal path on iPadOS and macOS.
- Input uses Apple's Game Controller framework directly or through a deliberately retained portability layer.
- Audio uses a platform-compatible native or portable backend.

Native does **not** mean every source file must be rewritten in Swift.

## Language and runtime policy

The app should feel like a first-class Apple application on iPad and Mac, but
rewriting OpenGOAL into Swift is not the project goal.

Expected language boundaries:

```text
Swift / SwiftUI
    App lifecycle, launcher UI, settings, import status, saves,
    file management, touch UI, Apple-platform presentation

Objective-C++ bridge
    Stable boundary between Swift and the existing native runtime

C++
    OpenGOAL tools and runtime, portable engine/platform code,
    renderer integration, asset loading, compiler support

GOAL
    Reconstructed game and engine logic supplied by OpenGOAL

Metal / Apple frameworks
    Apple rendering, input, audio, storage, and system integration
```

### Hard rule

Do not begin a wholesale C++-to-Swift or GOAL-to-Swift translation. Such a rewrite would discard the main value of OpenGOAL, greatly increase correctness risk, and move the project away from upstream compatibility.

Swift should own the Apple application shell and platform-facing features.
Existing OpenGOAL code should remain in its native languages unless a specific
component must be replaced for Apple-platform compatibility.

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

### Current enhancement direction

Build 154 is the accepted conventional-2D regression baseline for subsequent
Apple-device work. It retains **Graphics Modern** Fit to Screen presentation,
the physically accepted single-owner gameplay touch path, and the working Jak 1
runtime. Subsequent builds continue the bounded save-sync and touch-layout work
without replacing that accepted renderer baseline. The maintainer accepted
Build 154 within the gameplay and presentation scope exercised on physical
hardware. That acceptance is
intentionally scoped: it is not yet a complete-playthrough, every-level,
every-save, every-orientation, or every-controller certification.

The implemented settings documents retain their versioned fields for backward
and iCloud compatibility, but the shipped touch experience is no longer a
Modern/Classic choice. The maintainer rejected the post-Build-96 Classic touch
concept and touch editor in favor of one gameplay-touch scheme whose stick
placement, radii, two-pill layout, and base face gestures match Build 96. Later
bounded additions remain: crouch-left punch, semantic zoom, contextual SKIP,
touch haptics, truthful native-menu controls, and validated warp-gate capture.
Graphics retains its independent **Modern / Classic** presentation choice,
including Modern Fit to Screen. Builds 160 and 161's post-processing experiment
was physically rejected and removed; the accepted conventional-2D presentation
is frozen, and visual-improvement work is deferred until the maintainer
explicitly reopens it. Old Controls profile and touch-layout documents must stay
decodable, but they no longer control gameplay or appear as player-facing touch
configuration. Pinch input is not part of the frozen touch contract; camera zoom
uses one explicit semantic toggle. A device-local settings-sync opt-out does not
disable iCloud saves.

Enhancement work proceeds in this order:

1. Preserve Build 154 as the accepted conventional-2D regression baseline.
2. Close only actual MVP shipping blockers; do not expand unrelated touch,
   settings, or graphics surfaces.
3. Ship Jak 1 in conventional 2D across iOS/iPadOS and visionOS. Keep the
   physically accepted visionOS Comfort window on the normal launch path,
   defer stereoscopic presentation until a later, separately gated project,
   and keep macOS compilation healthy while its release remains deferred.

An experimental iOS High Frame Rate option is implemented on that conventional
renderer. It uses a 120 Hz gameplay timing domain with adaptive display-link
fallback and is built for both iPhone and iPad. Deterministic timing, signed
build, and simulator checks are complete; sustained performance, thermals,
power, and frame pacing on an iPhone 13 Pro-class device or newer remain a
physical acceptance gate.

No enhancement may fork gameplay semantics, weaken user-owned asset separation,
or replace the accepted Build 154 baseline before its replacement has been
physically compared and accepted.

### Potential future scope

These are allowed later but are not prerequisites for the first complete port:

- Jak II support
- Additional accessibility work
- Keyboard support
- External display support
- Custom aspect ratios
- Advanced mod management
- On-device mod browsing
- Custom-level workflows
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
- An App Store-only project; source builds and user-controlled data workflows remain first-class.
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
│ SwiftUI Dark Eco application — iPadOS / macOS / visionOS   │
│                                                            │
│ Launcher · Settings · Import status · Saves · iPad touch UI│
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

The desired shipping renderer is Metal-compatible and performant on modern
iPads and Apple Silicon Macs. However, the project must not begin with an
unnecessary full renderer rewrite before the rest of the runtime can be
validated.

Required sequence:

1. Audit the current OpenGOAL rendering architecture and platform dependencies.
2. Identify the smallest viable path to render a test scene on iPad.
3. Define a clean rendering interface where one does not already exist.
4. Choose between adapting an existing portable layer and implementing a direct Metal backend.
5. Preserve renderer correctness before adding visual enhancements.

A direct Metal backend is the preferred long-term direction, not permission to rewrite every rendering subsystem immediately.

### Simulation and presentation boundary

iPadOS is the first Apple frontend/backend implementation, not a reason to
make the OpenGOAL runtime inseparable from one `UIView`, `CAMetalLayer`, screen
size, platform lifecycle, fixed camera, or render target.

Keep game simulation separate from rendering and final presentation. Where the
current iPad port directly needs a boundary, prefer narrow interfaces for the
graphics surface, input, audio, filesystem, timing, lifecycle, and display
configuration. Preserve the distinction between the gameplay camera and the
final viewer/render camera where the existing architecture already allows it.

Do not undertake a renderer rewrite, camera refactor, abstraction campaign,
volumetric or immersive visionOS work, or speculative multi-platform work to
satisfy this direction. The implemented conventional visionOS window reuses
the shared Apple target and existing runtime seams. When two implementations
are equally small, prefer the one that does not prevent Mac or iPhone targets,
multiple render views, stereo rendering, externally supplied view/projection
matrices, or a future visionOS volumetric or immersive presentation layer.

Larger future-facing notes live in
[`APPLE_PLATFORM_DIRECTION.md`](APPLE_PLATFORM_DIRECTION.md). They constrain
avoidable coupling but do not expand the current milestone: boot and make the
real OpenGOAL Jak 1 runtime playable on iPadOS first.

## Import and ownership model

The project follows a bring-your-own-game model.

### macOS app and desktop-tool responsibilities

The macOS Dark Eco app or command-line tooling should:

- Accept a user-selected game image or extracted disc directory.
- Verify that the input matches a supported retail revision.
- Reject unknown or corrupted input with a clear error.
- Invoke or reuse OpenGOAL extraction and preparation tooling.
- Generate only the files needed by the iPad port.
- Produce a deterministic data package or installable development output.
- Run compatible prepared data locally through the same native runtime.
- Avoid uploading the user's game data to any service.
- Avoid bundling game data into the public repository or CI artifacts.

### Dark Eco app responsibilities

The Apple app should:

- Detect whether valid prepared game data is installed.
- Explain what is missing without directing users to piracy sources.
- Import a prepared package through supported Apple file workflows where possible.
- Store game data in an appropriate app-controlled location.
- Keep saves and user settings separate from imported source data.
- Verify compatibility before launching the runtime.

### On-device preparation status

**Experimental:** The Apple-device importer accepts a user-selected raw `.iso`,
a standard ZIP32 or 7z archive containing exactly one `.iso`, or an already
prepared `out/jak1` folder. Archive extraction is local and streaming: the app
writes the ISO to private Application Support staging, verifies the extracted
file, passes it to the same raw-disc preparation pipeline, and removes the
temporary image. Selected Files-provider archives are opened through a
coordinated local snapshot so
the parser does not inspect an incomplete placeholder or a moving provider
revision. Exact reads also tolerate valid short file reads.
Stored and raw-DEFLATE ZIP members are supported. ZIP64, encrypted, multi-disk,
ambiguous, and unsafe archives are rejected with no change to active game data.
Member names must use ASCII or UTF-8; legacy CP437 names are deliberately
rejected rather than guessed.

7z archives are detected by their content rather than their filename extension,
so a 7z file mislabeled as `.zip` still reaches the correct decoder. PLzmaSDK is
used only for file-backed 7z reading and extraction; the app validates one
unencrypted ISO and retains its own storage, path, cancellation, and atomic
activation checks.

On-device preparation is more than extracting an archive: the pipeline parses
and verifies the disc image, generates the prepared level data, and rebuilds
the flat `out/jak1/iso` layout that the runtime consumes.

Any on-device implementation must remain an offline data-preparation tool. It
must use normal signed code, bounded concurrency, recoverable errors, progress
and cancellation, an internal staging directory, and an atomic final install.
It must preserve the existing prepared-folder path and desktop-compatible
output rather than introducing a GOALPad-only data format.

### Save storage and synchronization

**Implemented:** Gameplay saves remain in OpenGOAL's existing local
`Application Support/OpenGOAL/jak1/saves` directory. The Apple host has a
local-first actor that can mirror stable snapshots to a private iCloud
Documents container. Launch and foreground synchronization runs before gameplay
resumes and can merge both directions. Synchronization triggered after completed
saves is upload-only: it archives divergent cloud members before mirroring the
active local pair and cannot replace local gameplay files. Each
OpenGOAL alternating bank pair is merged as one save slot with a pair baseline.
Dark Eco reproduces the loader's validation and `save_count` selection. A
loadable valid memcard always beats a corrupt or unsupported peer. Divergent
valid memcards are ranked by their effective modification dates, then by the
loader-selected native save generation; completion percentage is display data,
not conflict authority. When neither copy validates, the newest available pair
member wins. Hashes are used only for byte identity. Equal or missing dates
retain the local gameplay authority.
Divergent originals are archived locally and in iCloud before the winning pair,
including member presence, becomes canonical. Pair replacement removes a stale
odd generation before atomically replacing the even bank. A durable phased intent
embeds the immutable source banks before canonical mutation; recovery requires an
exact target-side and phase match. Committed local-target work can finish from the
embedded banks without the provider and before an account reset. Cloud-target work
may be abandoned when the provider disappears or the account changes because the
local canonical source remains intact. All top-level save operations share one
FIFO-exclusive lease. Gameplay remains paused if a committed local-target intent
cannot be validated and recovered. A source generation that changed after commit
is reconciled in that same pregame sync. A one-bank slot without a matching intent
is ranked as normal divergence rather than inferred to be an interrupted write.
Settings reports sync progress, availability, the last successful sync, and a
concise recovery action without exposing internal memcard paths or presenting a
second save picker. The game's ordinary four save positions remain inside its
native OpenGOAL memcard banks and appear through Jak's own Load/Save menu.
State and archive files remain outside the gameplay save directory. Import accepts
only the exact `OpenGOAL/jak1/saves` root with its single Jak 1 slot, or the exact
slot directory with raw banks directly inside; it bounds and validates the files
before changing local saves. Export writes the unchanged `OpenGOAL/jak1/saves`
tree, preserving raw desktop OpenGOAL memcard compatibility.

**Experimental:** The canonical project enables the standard iCloud Documents
capability for the selected paid-team identity
`com.zephyrstudiosllc.eco` and private container
`iCloud.com.zephyrstudiosllc.eco`. Source and unsigned platform builds can be
validated without iCloud, but provisioning, signed builds, and a real
two-device conflict/migration pass still require healthy Zephyr Studios LLC
Xcode credentials and registered identifiers.

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

### Preferred public distribution

The maintainer's preferred end-user path is an App Store release so family and
other users can install the native application without Xcode. TestFlight is the
natural pre-release lane. Source code, reproducible Xcode builds, personal
signing, and supported sideloading remain important project outputs rather than
fallbacks to delete after a store release.

App Store availability is a direction, not a current approval claim. Public
binary distribution still requires a separate license, intellectual-property,
and App Review assessment. This project policy documents the technical content
boundary and does not make a legal guarantee.

### Public product identity

Public-facing product surfaces use **Dark Eco**, with the App Store subtitle
**Native OpenGOAL Runtime**, and a calm, platform-oriented voice. GOALPad
remains the repository, target, scheme, and internal runtime name. The App
Store name, subtitle, icon, screenshots, preview media, and first-run setup
should not market the application with a supported game's name, characters,
official artwork, logos, or recognizable franchise symbols. Prefer concise
language such as **Add compatible game data**, **Choose a prepared game
folder**, and **No compatible data found**. Do not turn setup into a loud
franchise prompt.

Neutral branding is not concealment. Technical documentation may name the
currently supported game where precision, attribution, compatibility, or
contributor work requires it, and App Review notes must accurately explain the
application's core behavior. The app must not imply affiliation or endorsement.

### Store-safe technical boundary

The intended distribution package contains the open-source native runtime and
the complete supported GOAL workload compiled ahead of time into the normally
signed application. It contains no retail game data. Users provide compatible
prepared data locally; the app neither downloads it nor treats it as executable
code. Data-only mods may follow the same boundary. Executable-code mods require
a separate architecture and distribution review.

Every GitHub, TestFlight, and App Store archive must fail closed if its expected
AOT manifest is absent or incomplete. At the current Jak 1 pin, a distributable
build contains all 518 AOT object entries. A shell that reports that game code
is missing is useful only as an explicitly labeled development build and must
never be published as an end-user release.

### Required release outputs

Public release work should preserve:

- Source code.
- Reproducible Xcode build instructions.
- A macOS import/preparation tool.
- User-owned game data.
- Personal signing or supported sideloading workflows.
- A complete, normally signed AOT application with no retail data in its bundle.

### Deferred distribution services

Do not promise any of the following until technical and legal review is complete:

- Automatic cloud import or conversion.
- A hosted game-data conversion service.
- Executable-code mod delivery.

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
