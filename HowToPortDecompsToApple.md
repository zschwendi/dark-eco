# How to Port an Existing Decompilation Project to Apple Platforms

This is a phase-gated workflow for moving an already reconstructed game or
runtime to Apple silicon, with iPadOS as the strictest target. It is for
projects that already have substantial native source and host tooling. It is
not a recipe for starting a decompilation, rewriting a game in Swift, or
wrapping an emulator.

The central rule is to advance by falsifiable runtime evidence, not by lines
compiled. OpenGOAL and Jak 1 are the worked example because GOALPad exercised
this path through playable macOS and rendered iPad-simulator builds. The method
applies more broadly, but other decomps will have different languages, object
formats, linkers, memory models, command streams, and asset pipelines.

## Evidence levels

Keep these claims separate in issues, handoffs, and release notes:

| Level | What it proves | What it does not prove |
| --- | --- | --- |
| Source inspection | A design appears possible | Compilation or behavior |
| Host tool build | Tooling compiles on Apple silicon | Target runtime behavior |
| Target object/archive | Selected source compiles for the target ABI | Final link, signing, or execution |
| Host ARM64 execution | ABI and behavior work on Apple silicon macOS | iPadOS lifecycle, GPU, or hardware behavior |
| Signed generic iOS build | Final link, layout, and signing succeed | Installation or execution |
| ARM64 simulator run | Full app integration works in that scenario | Physical memory, GPU, thermals, controller, or audio hardware |
| Physical-device run | The observed scenario works on that device | Untested gameplay, revisions, devices, or distribution |
| Distribution validation | The selected archive/profile/store path is accepted | Complete game correctness |

Every phase below has an exit gate. Never substitute a lower evidence level for
the one the gate requires.

## Non-negotiable boundaries

### Preserve the reconstructed project

- Keep the existing engine, logic, formats, and tools as the source of truth.
- Use Swift or SwiftUI for the Apple shell, not as a replacement engine.
- Put portable runtime work in the project's native implementation language.
- Cross the Swift/C++ boundary through a small C API or Objective-C++ bridge.
- Isolate Apple-only code behind narrow platform seams.
- Keep a host target healthy as the fastest behavioral oracle.

### Separate code from user-owned data

- Never ship or commit retail assets, disc images, keys, or generated retail
  data.
- Require users to provide supported input and validate its revision and
  integrity with the project's existing identification scheme.
- Keep extraction output outside the checkout and ignored by Git.
- Keep public builds and synthetic tests useful without retail data.
- Document technical separation; leave legal conclusions to maintainers or
  qualified counsel.

### Treat executable-code policy as architecture

Ordinary iPadOS must not be assumed to allow writable-executable memory,
runtime native-code generation, private entitlements, or unsigned code. Before
implementation, document where reconstructed code is compiled, what artifact
is produced, when it is signed, what remains runtime data, how function
references and relocations work, and how code mods differ from data-only mods.

For a runtime that normally emits machine code, prefer ahead-of-time
translation to C, C++, LLVM IR, or native objects that Apple clang can place in
ordinary signed Mach-O `__TEXT`. Preserve the original data linker if its
relocations only modify data. Replace no more of the runtime than policy
requires.

## The phase plan

These are sequential claim gates, not a ban on parallel work. Once the
execution model and core contracts are stable, renderer, service, and import
lanes may proceed independently. They form a higher claim only after
integration passes. Merge or split phases to fit the project; preserve their
ordering, exit evidence, and refusal to skip unresolved lower-level blockers.

### Phase 0 — Define the product boundary

Write down the supported game and revisions, upstream baseline, retained
languages, Apple targets and minimum OS, user-data rules, prohibited
approaches, first visible milestone, final playable milestone, and every step
that requires physical hardware.

**Exit gate:** maintainers agree on a short architecture and asset-boundary
document, and a clean checkout contains no proprietary data.

**Jak 1 example:** GOALPad retained OpenGOAL, C++, and GOAL; Swift owns the app
shell. User-extracted game data stays outside the repository. The result is a
native port, not an emulator or Swift rewrite.

### Phase 1 — Establish a reproducible baseline

Build and test the documented upstream host before changing it. Record the
compiler, SDK, build system, dependencies, and result. Work in a dedicated
fork or downstream branch while preserving upstream history and licenses. Pin
submodules by immutable commit and verify them from a fresh recursive clone.

**Exit gate:** a fresh checkout resolves all dependencies and reproduces the
host baseline from the recorded pins.

**Jak 1 example:** GOALPad moved from local patch series to a fetchable
OpenGOAL fork and immutable parent gitlink while retaining the real compiler,
kernel, loader, renderer, and asset tools.

### Phase 2 — Map and measure the platform blockers

Trace a frame from host entry to game code and back. Inventory memory mapping,
code generation, calling convention, stacks and coroutines, symbols and
relocations, file/RPC services, input, audio, saves, timing, renderer commands,
shaders, resource lifetime, generated files, and architecture-specific code.

Measure disputed assumptions with small probes: mapping permissions, pointer
ranges under ASLR, stack usage, data layout, shader support, and the actual
architecture selected by each build. Classify components as portable core,
Apple seam, build-time host tool, signed target code, runtime user data, or
unsupported behavior that must fail loudly.

**Exit gate:** the code/data boundary and first real blocker are supported by
measurements, with a written replacement for every runtime-generated-code path.

**Jak 1 example:** desktop OpenGOAL copied code into an executable heap and
created runtime trampolines. Address-placement experiments were unreliable,
but data relocations required no executable memory. GOALPad therefore replaced
only code execution and retained the real data linker.

### Phase 3 — Prove the ARM64 execution model

Start on ARM64 macOS for fast debugging. Execute representative compiler output
through the production ABI, checking arguments, results, preserved registers,
stack alignment, real function dispatch, and stateful memory access. Unknown
or untranslated entries must fail. Compile the same sources for arm64 iOS.

Treat compiler coverage as discovery, not correctness. Memory, call, vector,
stack, and thread lowerings need behavioral tests with mutation checks. If a
handwritten backend grows one instruction at a time, compare it with emitting a
mature compiler input. Keep true stack/context primitives native when a simple
translation would compile but silently change semantics.

**Exit gate:** real reconstructed code runs through the ARM64 production call
path, target code enters a normal signed iOS build, and inspection finds no
writable-executable segment or prohibited JIT dependency.

**Jak 1 example:** small emitter proofs clarified the ABI but did not scale.
The successful backend emitted C from GOAL IR, used clang for ARM64, stored
native entries in normal function objects, and kept seven real thread/stack
operations as native ARM64 routines. Game code lived in signed `__TEXT`.

### Phase 4 — Carve out one portable runtime core

Create one shared core that owns runtime memory, globals, symbols and types,
object loading, frame dispatch, and translated routines. Thin hosts own app
lifecycle, views, controller discovery, audio devices, presentation, and user
file selection. Expose narrow C APIs or function tables with explicit
ownership, threading, sizes, lifetime, and failure behavior.

Build the same source list in its normal host graph and a focused iOS target.
Do not copy a machine-local archive into the app; build from the pinned source
or a reproducible artifact.

**Exit gate:** the real core initializes and tears down repeatedly in a host
harness, cross-compiles for arm64 iOS, and links without desktop window,
audio-device, or JIT dependencies.

**Jak 1 example:** `game/kernel/core/` became a shared library with no SDL
window and no audio output backend. A C++ macOS host and Objective-C++ iPad host
consume the same core.

### Phase 5 — Restore object loading with synthetic fixtures

Implement the original object model faithfully: place static data in
runtime-owned writable memory, apply every data relocation, create function
objects backed only by trusted signed entries, register them by stable object
identity, execute top-level initialization through the real dispatcher, and
stop at the first missing translation.

Commit original fixtures for each relocation, code-plus-data loading,
function/method dispatch, malformed bounds, missing exports, initialization,
teardown, and thread/catch/suspend behavior. Fail closed: returning zero is not
neutral when the runtime expects a tagged false, size, volume, or pointer.

**Exit gate:** synthetic archives pass through the production loader; calls and
mutations are checked; missing or malformed inputs fail without corruption.

**Jak 1 example:** the AOT loader replaced each object's code segment with its
matching signed entry while linking versioned data normally. Missing code was
an error, never a skipped object. Synthetic thread tests proved live stack and
context restoration before gameplay depended on them.

### Phase 6 — Build the data pipeline and headless boot

Accept only user-selected local input. Identify supported revisions; reject
unknown or corrupt data. Reuse the project's extractor/decompiler, output to a
documented directory outside Git, distinguish portable assets from generated
code, and design progress, cancellation, free-space, retry, and partial-output
behavior. Never fetch or upload retail content.

Add an optional real-data test that skips clearly when unconfigured and becomes
strict when a data path is supplied. Load the smallest kernel archive, then the
main archive, then run bounded dispatcher frames. Report object counts and the
first missing symbol, service, or file.

**Exit gate:** a supported user input is prepared end to end, and a fresh host
process loads it in canonical order into a stable headless state.

**Jak 1 example:** host tools validated a user disc and produced runtime
archives outside Git. Headless tests loaded the real kernel and game, ran
top-levels and the dispatcher, then exercised real level transitions before
the Apple UI became the debugging surface.

### Phase 7 — Port rendering through capture and replay

Find a stable renderer input boundary: a DMA chain, display list, render graph,
or command buffer. Capture real host input privately, keep it outside Git, and
create original public fixtures. Replay offscreen into Metal, port passes
incrementally, count consumed and skipped commands/bytes, add texture and level
resources, then present first in a macOS host and finally through an iPad
`CAMetalLayer` host.

Compile shaders before signing and load a signed library; do not require
runtime source compilation. Document threading. Snapshot mutable frame input,
lock shared resource pools only as required, and never wait for GPU completion
while holding those locks. A single-threaded initial host is valid when it
makes ownership deterministic.

**Exit gate:** synthetic and private real captures replay deterministically;
the host shows a real game frame; skipped work and GPU errors are observable;
the iPad host presents the same backend with build-time shaders.

**Jak 1 example:** GOALPad ported Metal buckets against captured frame chains,
used its macOS host as the playable reference, and installed the same renderer
behind an iPad function table. A jitter bug came from rendering a snapshot
while reading live skeleton memory and was fixed with a regression test.

### Phase 8 — Implement platform services as seams

Add only services demanded by the next real state:

- **Storage:** sandbox-relative roots, atomic saves, rotation/versioning, and
  corruption behavior.
- **Input:** exact bits and axes, disconnected state, hotplug, touch synthesis,
  and haptic requests.
- **Audio:** fixed engine format, host conversion, preallocated real-time
  buffers, route/interruption handling, and shutdown.
- **File/RPC:** bounds-check guest spans and preserve request/response and
  aliasing semantics.
- **Timing/lifecycle:** monotonic clocks, frame pacing, repeatable suspend,
  resume, and teardown.

Test malformed buffers, absent files, short reads, disconnections, and repeated
start/stop. Leave every unsupported call loud.

**Exit gate:** the game reaches its next real state using the service; focused
positive and negative tests pass; already supported game versions are healthy.

**Jak 1 example:** a stubbed volume query returned zero and muted ambient
audio even though mixing worked. Saves were proven by write, bank rotation,
fresh-process reload, corrupt data, and no-save cases—not by file existence.

### Phase 9 — Prove end-to-end game behavior

Build a ladder: title, menu input, new game, player control, movement/camera/
collision, audio and dialogue, two-way level streaming, save/relaunch/load,
multi-level memory stability, then full completion. Automate against semantic
states or explicit events instead of fixed frame counts; cutscenes and asset
timing can change legitimate timing.

Keep real-data runs private while committing their harnesses and original
fixtures. Do not commit derived captures, audio, or screenshots without an
explicit project decision.

**Exit gate:** the selected gameplay slice works from a fresh process and its
state, rendering, input, audio, streaming, and save effects are independently
observable.

**Jak 1 example:** the macOS host proved title-to-control gameplay, movement,
dialogue, audio, controller rumble, two-way level transitions, save/reload, and
resource-residency behavior. It became the reference before the same seams
were connected to the iPad shell.

### Phase 10 — Integrate the Apple application shell

Keep the ownership chain small:

```text
Swift / SwiftUI: scene, settings, import UI, Apple services, view
        |
small C or Objective-C++ bridge
        |
C++ core + renderer + generated signed game code
```

Expose honest states for missing generated code, missing data, unsupported
revision, booting, running, suspended, and failure. Validate repeatable boot,
foreground/background return, drawable changes, memory warnings, app-container
data access, controller changes, audio interruptions, and teardown.

**Exit gate:** a named Apple-silicon simulator builds, installs, launches,
loads user data from its container, reaches the chosen state, and shuts down.
A generic iOS Release build also links and signs.

**Jak 1 example:** the simulator booted and rendered the real game, produced
audio, polled input, and loaded app-container data. That remained simulator
evidence, not a physical-iPad claim.

### Phase 11 — Validate hardware, performance, and distribution

Physical testing should be explicitly authorized. Record Release build,
architecture, Mach-O layout, entitlements, signing, installation, launch,
runtime checkpoint, visible frame, input, audio, storage, lifecycle, sustained
frame time, memory, thermals, and battery as separate results. Public release
and store availability require additional evidence.

Optimize after correctness: capture a baseline, change one material variable,
measure on relevant hardware, and retain behavioral tests. Prioritize level
residency, transient allocation, audio underruns, GPU occupancy, and thermal
throttling over cosmetic tuning.

**Exit gate:** the agreed gameplay slice runs on a non-jailbroken physical
device with ordinary signing, no prohibited entitlement, and acceptable
measured lifecycle and performance.

**Jak 1 example:** GOALPad separately verified a thin arm64 Release binary,
signed code and build-time Metal shaders, with no writable-executable segment.
Where no physical run was recorded, that gate remained pending.

## Build and test matrix

Adapt names and paths; never commit machine-specific values.

| Lane | Typical command | Evidence |
| --- | --- | --- |
| Host configure | `cmake --preset <host-arm64-preset>` | Toolchain and pin recorded |
| Focused build | `cmake --build <host-build> --target <target> --parallel <N>` | Exact target succeeds |
| Focused tests | `ctest --test-dir <host-build> -R '<regex>' --output-on-failure` | Behavioral checks pass |
| Full regression | `ctest --test-dir <host-build> --output-on-failure -j 1` | Documented healthy suite passes |
| iOS core | `cmake -S <source> -B <ios-build> -G Ninja -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64` | Intended arm64 archive objects |
| Simulator | `xcodebuild -project <App>.xcodeproj -scheme <Scheme> -destination '<named-arm64-simulator>' build` | Build, install, launch, logs, behavior |
| Generic device | `xcodebuild -project <App>.xcodeproj -scheme <Scheme> -configuration Release -destination 'generic/platform=iOS' build` | Link/sign evidence only |
| Physical device | `xcrun devicectl device install app --device <device-id> <app>` | Separate install, launch, and runtime evidence |

Inspect artifacts rather than trusting the build banner:

```sh
file <executable>
xcrun lipo -info <executable-or-archive>
xcrun otool -l <executable>
xcrun nm -u <executable>
codesign -d --entitlements - <app>
codesign --verify --deep --strict <app>
```

Check architecture, segment protections, signed-code placement, unexpected
libraries, unresolved symbols, preview/debug layouts, JIT APIs, runtime shader
compilation, and private entitlements. Imports such as `mmap` or `dlsym` need
interpretation; their presence alone is not proof of executable-memory use.

## Failure policy

When something fails:

1. preserve the first useful error and exact command;
2. reproduce it on the pre-change baseline when practical;
3. reduce it to the smallest target, object, state, or frame;
4. fix current-change regressions before broadening the work;
5. keep unsupported behavior loud and bounded;
6. never disable a target, warning, assertion, or test to create green;
7. rerun the focused test, affected matrix, and end-to-end gate;
8. report partial or unvalidated work accurately.

Negative tests should cover malformed archives, missing exports, bad guest
pointers, overlapping buffers, stale resources, absent devices, corrupt saves,
missing assets, and background return.

## Worktrees, agents, and handoffs

- Separate compiler, runtime, renderer, audio, import, and shell lanes into
  branches/worktrees; never edit the same files concurrently.
- Give each task one behavioral gate and bounded file set.
- Integrators review every result and rerun affected validation.
- Merge dependencies before consumers: ABI, loader, boot, renderer seam, host.
- Preserve user work and stage explicit paths at verified checkpoints.
- Never pin a parent to an unpublished submodule commit.
- Keep build products, user data, credentials, profiles, and machine paths out
  of Git.

A useful handoff records the objective and phase; parent and dependency commits;
worktrees and dirty files; implemented behavior; exact commands/results;
evidence level; untested areas; first blocker; next executable task; and actions
requiring maintainer permission. Update it before a context reset and after a
strategy change. Mark old directions as superseded instead of silently erasing
the history.

## Follow-on games and variants

Do not treat a sequel as a configuration switch. Reuse the ladder, then
inventory kernel layouts, object versions, native translated-function sets,
RPCs, renderer buckets, resource formats, audio streams, saves, languages, and
revision detection. A per-game seam is safer than unmeasured conditionals in a
“universal” core.

Jak 2 followed the correct pattern: compile its sources, boot its kernel,
register its native translated functions, load the main archive, then implement
the first measured sound-RPC handshake with a synthetic protocol test. That
handshake proved one request, not audio, rendering, or gameplay. The lesson is
universal even though GOAL and its formats are not.

## Completion checklist

- [ ] Product, asset, license, and non-goal boundaries are written.
- [ ] Dependencies are pinned and fresh-clone verified.
- [ ] Runtime-generated code has an ordinary signed-code replacement.
- [ ] Code mods and data-only mods have a documented trust model.
- [ ] ARM64 ABI, stack, context, and function representation are tested.
- [ ] Portable core initializes, runs, and tears down deterministically.
- [ ] Production object loading and every relocation kind are exercised.
- [ ] Missing translations and malformed input fail closed.
- [ ] User data is locally supplied, validated, and kept outside Git.
- [ ] Synthetic fixtures are deterministic and public-safe.
- [ ] Real-data tests skip clearly and become strict when configured.
- [ ] Renderer captures replay without unexplained skipped work.
- [ ] Shaders compile before signing.
- [ ] Input, audio, storage, timing, and lifecycle have tested seams.
- [ ] Title, gameplay, streaming, and save/reload are separate gates.
- [ ] Automation waits for semantic states rather than fixed frame counts.
- [ ] Long sessions check resource residency and memory.
- [ ] Named ARM64 simulator build, install, launch, and teardown pass.
- [ ] Generic iOS Release is arm64, linked, signed, and inspected.
- [ ] No writable-executable segment or prohibited entitlement is present.
- [ ] Physical runtime and hardware behavior are separately recorded.
- [ ] Distribution and public-availability claims have their own evidence.

The port is complete only when the requested product milestone reaches its
required evidence level. Until then, preserve the last working phase, report
the next concrete blocker, and keep moving the real game rather than polishing
proofs that no longer reduce risk.
