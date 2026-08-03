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
- The preferred public distribution path is TestFlight followed by the App
  Store, while source and supported sideloading remain first-class. Storefront
  and first-run presentation use the neutral **Eco Pro** identity and calm
  **compatible user-supplied data** language rather than franchise marketing;
  technical documentation and App Review notes remain precise and transparent.
- GitHub, TestFlight, and App Store archives fail closed unless the complete
  expected AOT manifest is linked. The development shell without generated
  game code is never a publishable artifact.
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
| Native Swift/Objective-C++/C++ iPad process | Experimental; signed physical gameplay verified |
| Signed native ARM64 execution | Implemented through linked AOT game code; physical runtime reports `PROT_EXEC=no` |
| Storage and Metal initialization | Implemented; user-local data and physical Metal rendering verified |
| Controller, audio, and lifecycle integration | Experimental; core paths run, physical controller and side-by-side media remain open |
| User-owned Jak 1 import pipeline | Experimental; prepared folders remain supported, and Release builds can select a supported raw ISO or a standard ZIP32 archive containing exactly one ISO. The native composer, Objective-C++ bridge, recoverable staging/activation, ZIP extraction, and deterministic validation are implemented; a successful end-to-end simulator import and a real-device Files-provider import remain unrecorded |
| Compiler-produced ARM64 GOAL execution | Implemented for the current Jak 1 AOT set; seven native routines remain |
| OpenGOAL game frame or title screen | Implemented and physically verified |
| Playable gameplay slice | Experimental; sustained physical play reached Misty and Training |
| Jak 1 completion track | Planned |

The current application initializes the real OpenGOAL Jak 1 kernel, loads
user-local game data, runs linked AOT/native game code without executable arena
pages, renders through the Metal backend, accepts controller/touch input, and
plays audio. Signed physical-iPad runs reach sustained gameplay. Current
blockers are visual correctness and remaining platform gaps, not real-media
import validation, the earlier synthetic arena, or literal-instruction probes.
`HANDOFF.md` Checkpoint 62 is the authoritative current build and next-task
record; Checkpoint 37 remains the latest sustained physical-iPad gameplay
evidence.

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
Local OpenGOAL verification and preparation
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

Current status:

- Implemented: the public dedicated fork is
  `https://github.com/zschwendi/jak-pad.git`; published branch
  `goalpad/ipad-demo-pacing` and the parent submodule both resolve to
  `db376b727c52ffeb19788df4ac453693a07c40c8`.
- Verified: the remote branch resolves to that exact pin, and the affected host
  tests and application integration passed. Earlier fresh-clone evidence was
  recorded against the historical `9eecb9c3` checkpoint.
- Pending: rerun the complete clean-clone Stage 1 host baseline at the current
  pin when a fresh full build is next useful; publication and fetchability are
  no longer blockers.

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
- Parent commit `f13d8f0` implements required work 9. The wrapper sets and
  snapshots distinct X20 process/`pp`, X21 `st`, and X22 offset-base values,
  calls the compiler-produced entry, and proves caller-register restoration.
- The app built, signed, installed, launched, and logged `result=42` through
  that boundary on the physical iPad Pro M5 without JIT or writable executable
  pages.
- Stage 2 is complete. The synthetic register values do not constitute general
  runtime initialization; that remains part of the portable runtime path.

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

Current progress:

- Child commit `149840cfa8cb4cecd62c8f5c7ffe5a8b8c26ce31` makes
  `IR_FunctionCall` clobber metadata target-aware while preserving the prior
  x86 set.
- Exact ABI-set tests and live-across-call allocator tests cover ARM64 GPR and
  SIMD behavior in both allocator versions.
- `goalc-aot` and `goalc-test` build; all 5 focused tests and all 691
  non-listener tests pass.
- Child commit `32cf26aef8c61cecdceeb07ed90e0296e1e8e052` compiles the
  real Jak 1 `'#f` expression from `gcommon.gc` to `mov x0, x21; ret`.
- The false-form artifact passes 6 focused and 692 non-listener tests, executes
  through the static state wrapper on ARM64 macOS and the dedicated M5
  simulator, and is installed in a normally signed physical build.
- Child commit `92c8f975efc9741c9e6a4bc4b0086f131ac9aefd` adds named-function
  AOT selection and compiles the complete real Jak 1 `false-func` definition.
  Empty `IR_ValueReset` is treated as function-entry metadata while the
  selected body remains exactly `mov x0, x21; ret`.
- The complete-function checkpoint passes 9 focused and 695 non-listener
  tests, executes through the static state wrapper on ARM64 macOS and the
  dedicated M5 simulator, and is present in a normally signed generic iOS
  build. Its top-level `define` and live GOAL symbol installation remain
  explicitly unsupported.
- Physical execution of the false-form and complete-function checkpoints is
  deferred until the maintainer explicitly schedules a device pass. ARM64
  general function and function-call code generation remain unsupported.
- Child commit `1fc20e793f6c7fd8db3bca3fcc458b098a8b4ea3` emits the selected
  signed text and a guarded zero-argument X-macro export record as a paired
  build-time artifact. It passes 16 focused ARM64 AOT tests, 702 non-listener
  tests, and the deterministic paired-artifact CTest.
- Child commit `25917e278aeeaf6fee9faa4fbba93f4a2c64f146` compiles the exact
  one-argument Jak 1 `identity` body using GPR `IR_RegSet` and the Apple-ABI
  X0 argument/return register. Child commit
  `1c80b667aa943d066c1fe2deef85c464c09996fe` adds its distinct typed export;
  the combined checkpoint passes 22 focused tests, 708 non-listener tests, and
  the paired-artifact CTest.
- Child commits `35d653f1fadc52e78925e952a507d60dc4c11245` and
  `f979c82cb6da50b847808ebd23ec10c4fa1c1c9e` compile and export the exact
  zero-argument Jak 1 `true-func` body. Its signed text is `mov x0, x21; add
  x0, x0, #8; ret`, returning `#t` as the `st` base plus eight. The combined
  checkpoint passes 27 focused tests, 713 non-listener tests, and CTest 1/1.
- Reviewed child commit `2475b3c1f097dedb60e5e78a1fc4d88aab5ab052`, preserved
  by parent commit `6697d2d`, compiles the exact one-argument Jak 1 `lognot`
  definition to `mvn x0, x0; ret`. Child commit
  `9acf4e79751d83626915f03aebcfc738e4d0c242`, preserved by `fbfa0d5`, adds
  its guarded `OPENGOAL_AOT_EXPORT1("lognot", goalpad_aot_lognot)` pair. The
  combined checkpoint passes 34 focused tests, 720 non-listener tests, and
  CTest 1/1; mismatched symbols or cross-ABI exports fail atomically.
- Child commit `fab37c1f755aa342304db8dbf27f1fa1c42423ac`, preserved by parent
  `8995197`, compiles and exports only the exact maintained debug-only Jak 1
  `glst-node-name` form. Its one-argument code adds X22 and X0, then loads the
  32-bit unsigned field at offset eight; the generated words are
  `8b36e010`, `b8408200`, and `d65f03c0`. This is strict compiler/export
  evidence, not general ARM64 load support or CMake artifact execution.
- The 0019 compiler/export proof built `goalc-test` and `goalc-aot` with `-j4`;
  Arm64Aot passed 41/41, the type/form regression 190/190, the established
  compiler/emitter filter 129/129, CLI CTest 1/1, and full CTest 8/8.
- Child commit `1e43e767d66b6f554a6cc9aedb9fa024ca3130ee`, preserved by parent
  `faf3f1a`, extends the existing host CMake artifact to the same exact
  `glst-node-name` form and emits its guarded `Export1` metadata. The one-arena
  serial ABI test calls the production dispatcher with the canonical nonzero
  `global_heap_current` node offset in X0 and two X22 logical bases 0x40 bytes
  apart. It reads the distinct high-bit unsigned 32-bit values at `+8` as
  `0x0000000081234567` and `0x00000000f2345678`, while preserving the caller
  state. A `clang-format` include-order regression initially changed the
  `Export1` table order; the ordered generated includes are now protected and
  asserted. This remains evidence for only this checked field load, not general
  ARM64 load support or an iPad runtime.
- The 0020 affected host build passed; ABI CTest passed 3/3, data-arena CTest
  4/4, the established compiler/emitter filter 129/129, AOT CLI CTest 1/1, and
  full CTest 8/8. Final review found no blockers.

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

Current progress:

- The first static artifact boundary is verified: the compiler emits guarded
  zero-argument metadata for `false-func` and `true-func` alongside signed
  text, plus typed one-argument metadata for `identity`. Parent commits
  `0866a1e`, `1d5e4bf`, and `d12f732` preserve the true-function compiler and
  export patches, register its checked-in artifact beside `false-func`, and
  execute all three entries through the existing static state boundaries.
- This is build-time native binding only. It does not execute the surrounding
  top-level `define`, install a legacy GOAL symbol value, initialize live GOAL
  state, relocate code, or use the desktop V3 linker.
- The registry and state harnesses, ARM64 macOS app build, dedicated M5
  simulator build/run, and generic signed iOS build passed. The generic
  simulator destination selected x86_64 and failed assembling the existing
  ARM64-only state wrapper before runtime; use the specific M5 simulator
  destination for ARM64 runtime evidence. No physical-device validation was
  performed.
- The Debug generic iOS artifact remains only limited signing/code-layout
  evidence because it uses an Xcode Preview split bundle. The verified Release
  generic iOS build used `ENABLE_PREVIEWS=NO ENABLE_DEBUG_DYLIB=NO` and contains
  a 216K monolithic app bundle with one ARM64 executable; it has no Preview
  dylib, Preview/JIT strings, or dynamic executable-memory imports. This is
  stronger static layout evidence, but not verification, installation, or
  physical-device execution evidence.
- Parent commit `f7ad14c` registers the checked-in `lognot` Export1 artifact
  beside `identity`, then calls it through the existing one-argument X0 and
  X20/X21/X22 state wrapper. The host harnesses, ARM64 macOS app build,
  dedicated M5 simulator build/run, Debug generic signed iOS build, and Release
  monolithic regression build passed. `lognot` returns the bitwise complement
  of its synthetic argument; it does not create a live GOAL symbol, execute a
  top-level definition, or enable relocation.
- Child `cb1cc102`, preserved as patch 0021 by parent `c577f47`, adds the
  direct real Jak 1 `level-group-load-commands-set!` body to the strict AOT
  allowlist and emits guarded two-argument Export2 metadata. The resulting
  body stores W1 at X22 + X0 + `0x20`, returns X1, and is not a live method
  installation or dispatch. Sibling child `311be477`, preserved as patch 0022
  by parent `6c1370c`, hardens the four-byte store lowering against stack,
  X22-address, and unsafe X16 operand forms. Sibling child `13672fad`,
  preserved as patch 0023 by parent `8468742`, executes the generated entry in
  the existing host ABI test. These are sibling child commits from 0021, not a
  linear 0021-to-0023 child history; preserve their mboxes and revalidate a
  combined restoration before treating it as a durable fork sequence.
- Parent commit `0da05dd` binds the generated Export2 entry into GOALPad's
  typed registry and two-argument state wrapper. Its direct synthetic proof
  uses two real aligned X22 bases, verifies full 64-bit returns and four-byte
  W1 stores at the expected locations, and checks whole-buffer integrity and
  caller-state restoration. The ARM64 macOS app build, named M5 simulator
  build/run, and generic signed Release iOS build passed. The simulator result
  remains simulator evidence; the Release result remains static
  build/signing/layout evidence. Neither is a method-installation, dispatch,
  runtime-initialization, Jak-data, title-screen, or physical-device proof.
- Patches 0024 and 0025 compile the exact
  `load-state::want-vis` body from
  `goal_src/jak1/engine/level/load-boundary.gc:1074-1076` to a guarded
  Export2 artifact and preserve its required packed inline layout. Patch 0026
  executes the generated entry on the ARM64 host against two guarded arena
  bases. Parent `3ce59d4` registers the checked-in artifact as the app's second
  Export2 entry and verifies its low-word stores at raw field `#x24`, zero
  return, arena isolation, and caller-state restoration. The app harness,
  ARM64 macOS build, named M5 simulator run, and generic signed monolithic
  Release build passed. This remains direct method-body evidence only; it does
  not install or dispatch `want-vis`, initialize the runtime, load Jak data,
  boot the game, or establish physical-device execution.
- Patches 0027-0031 add only the exact encoder corrections, local control flow,
  guarded integer math, signed loop backedges, and strict 160-record match
  needed to compile the complete real
  `load-state::want-levels` body. Patch 0032 adds a distinct three-argument
  Export3 manifest, and patch 0033 executes the generated 142-instruction body
  through the host ARM64 boundary against six guarded branch-matrix cases.
  Parent commits `18c6238` and `33beb79` check in the exact artifact, register
  the typed entry, establish X20/X21/X22 before X0/X1/X2, and repeat all six
  semantics in the app and native harness. Host tests, ARM64 macOS, the named
  M5 simulator runtime, and the signed monolithic generic iOS Release build
  passed. This is still direct body evidence only; there is no method
  installation, live runtime initialization, Jak data, boot, or current
  physical-device execution.
- Patches 0034-0036 compile, export, and execute the complete real
  `load-state::reset!` body from
  `goal_src/jak1/engine/level/load-boundary.gc:1027-1040`. The exact
  50-IR match emits 58 ARM64 instructions (232 bytes), and the host proof
  executes it against two disjoint guarded arenas with Jak 1 `#f` in X21.
  It verifies all eight `want` words, the empty `command-list`, all 256
  `object-name` and 256 `object-status` entries, full-arena equality, caller
  state, and return value. Parent commits `53f7422`, `27e3a57`, and `379949e`
  preserve the ordered child patches; `d843e17` checks in the exact artifact;
  and `cabb027` registers and repeats the proof in GOALPad. Host tests, the
  ARM64 macOS app, the named M5 simulator runtime, and the normally signed
  monolithic generic iOS Release build passed. This is direct static body
  evidence only: there is no method installation or dispatch, live global
  binding, relocation, Jak data, boot, or current physical-device execution.
  The bare name `reset!` is a known artifact identity only; it is not a
  general or qualified GOAL method-resolution scheme. A future dispatch image
  must distinguish method owner/type rather than assuming every `reset!`
  denotes this body.
- Patch 0037 preserves child `0327eee4`'s narrow ARM64 `load-state-value`
  artifact. It reads a 32-bit value cell through a signed `int32_t`
  displacement in normal application data, with X21 as the synthetic Jak 1
  symbol-table base and X22 as the caller-owned arena base. Parent checkpoints
  `7c49125` and `8e3b4ac` preserve and integrate it. The child suite (12/12),
  parent registry harness, ARM64 macOS build, approved M5 simulator runtime,
  and generic signed Release build passed. This proves only the signed static
  symbol-value code/data shape and high-bit zero extension in synthetic
  storage. It does not resolve a live `*load-state*` symbol, execute top-level
  GOAL code, initialize the runtime, bind a method, dispatch virtually, load
  Jak data, boot, or establish physical-device execution.
- Checkpoint 21 pins OpenGOAL child `9eecb9c3` and executes the real generated
  `load-state::reset!` Export1 inside GOALPad through the production
  `DataArenaNativeMethodBinding1`, portable method lookup, and typed ARM64
  invoker. Two guarded synthetic arenas verify exact method metadata, reset
  results, full-state equality, and fail-closed mismatch behavior. The same
  path passed the ARM64 host harness, approved M5 simulator, and normal signed
  generic iOS Release build. This advances signed static method composition,
  but the Stage 4 exit gate remains open because no general static-object or
  top-level initialization model exists yet.

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

Current progress:

- Child commits `5c536859`, `b094144b`, and `5495181f` verify a portable,
  caller-owned Jak 1 data-arena header through the preserved 0013-0015 patch
  series. The direct source compile produced an iPhoneOS ARM64 object, and the
  focused data tests and pure compiler checks passed on the host.
- Child `5ad2efa3`, preserved by parent `a2f41c7` as patch 0016, adds a
  minimal CMake 4.4.1 mode for that same static library. Its iPhoneOS arm64
  archive contains only `data_arena.cpp.o`, carries an iOS 18.0 load command,
  and has only the system `_bzero` undefined reference. The generated target
  graph excludes desktop libraries, tools, JIT paths, and runtime globals;
  normal-host regressions remained 4/4, 122/122, and 5/5.
- Child `45e1897f`, preserved by parent `0c0395e` as patch 0017, dispatches
  `call_goal` to the existing ARM64 assembly helper on macOS ARM64 and adds a
  static assembly ABI probe. The recorded host build and tests passed: ABI
  CTest 2/2, data-arena CTest 4/4, the host compiler filter 122/122, and full
  CTest 7/7. The probe verifies argument placement, X20/X21/X22 setup,
  16-byte stack alignment, result propagation, and restoration of caller
  callee-saved registers. It is a macOS-host static-test result only: the
  target does not link the OpenGOAL runtime or CodeTester, and it does not
  execute compiler-produced GOAL code or establish an iPhoneOS, app, signing,
  simulator, or physical-device result.
- Child `bd3f4752`, preserved by parent `3cb4e16` as patch 0018, generates
  four exact Jak 1 AOT artifacts on the macOS ARM64 host, links them into the
  ABI probe, and calls them through the production assembly dispatcher after
  initializing one caller-owned data arena. The affected host build passed;
  ABI CTest passed 3/3, data-arena CTest 4/4, the compiler filter 122/122, and
  full CTest 8/8. This proves the generated `false-func`, `true-func`,
  `identity`, and `lognot` entries receive the intended X21/X0 inputs and
  return expected values. None dereferences X22 or reads arena memory, so it
  does not prove X22-relative addressing, arena contents, C++ `call_goal`
  runtime dispatch, globals, JIT, an iPhoneOS executable/app, signing,
  simulator, or device behavior. A direct iPhoneOS static archive containing
  the data-arena object, dispatcher assembly, and four generated assembly
  files also passed object/symbol inspection; it is compatibility evidence,
  not runtime execution. The current minimal iPhoneOS data-arena
  configure/build still passes independently and contains no host AOT target.
- Child `1e43e767`, preserved by parent `faf3f1a` as patch 0020, adds the
  generated `glst-node-name` assembly and Export1 header as a fifth entry in
  that same host-only artifact. The existing serial one-arena test uses the
  canonical nonzero `global_heap_current` offset with two X22 bases 0x40 bytes
  apart and verifies the zero-extended results `0x0000000081234567` and
  `0x00000000f2345678` from separate unsigned fields at `+8`. The production
  dispatcher sets the requested X22 base for each call and caller state is
  restored. This proves neither general loads nor global/runtime binding.
  A direct iPhoneOS archive at
  `/private/tmp/goalpad-ios-aot-x22.38XD72/libopengoal-jak1-aot-context-ios.a`
  contains the data-arena object, dispatcher, and all five generated entries;
  it is arm64 with iOS minimum 18.0, reports SDK n/a for the dispatcher and
  generated assembly and SDK 26.5 for the data object, and has only `_bzero`
  undefined. It is static compatibility evidence only, not an executable,
  app, signing, simulator, device, or runtime-execution result.
- Children `da6cfe9e` and `deebafd`, preserved by parent `b89ff6c` as patches
  0038 and 0039, add a portable, read-only lookup for an existing symbol value
  cell in caller-owned synthetic Jak 1 arena storage. It validates the
  canonical header and symbol-table tag layout, uses the compatible stateless
  CRC probe order, and returns a GOAL offset plus a signed `s7` displacement;
  it does not read the cell value. Host validation passed the 23/23 focused
  data-arena cases, 191/191 established compiler/emitter cases, and 31/31 full
  CTest cases. The fresh iPhoneOS archive has one arm64 data-arena object with
  an iOS 18.0 load command and exports the initializer and resolver. This is
  static-library compatibility evidence only, not app, signing, simulator,
  device, or runtime execution.
- Child `a13b42f7`, reviewed from source commit `9a830552` and preserved by
  parent `bea6550` as patch 0040, composes the existing resolver,
  `load-state-value` artifact, and direct `reset!` export in one manually
  staged synthetic arena. The new ARM64 ABI test validates the resolver's
  displacement, the signed value read, reset writes, string/symbol/value-cell
  preservation, object and outer guards, and caller-register restoration. The
  incremental target build passed; focused ABI CTest passed 8/8, full CTest
  passed 32/32, and the established compiler/emitter filter passed 191/191.
  It is test-only and uses one roughly 66 MiB arena without a duplicate. It is
  not a heap advancement, linker, type-object, method-dispatch, game-data,
  app, signing, simulator, device, or boot result.
- Checkpoint 21 publishes and pins the accepted OpenGOAL series, directly links
  `data_arena.cpp` plus the typed ARM64 invoker C++/assembly into Xcode, and
  runs the trusted reset composition inside the application. The host harness,
  ARM64 macOS build, approved M5 simulator runtime, and normally signed generic
  iOS Release build passed. This is real portable OpenGOAL source integration,
  but the arena is still a temporary synthetic fixture local to one probe. It
  does not yet provide a persistent initialized runtime session, lifecycle,
  failure surface, or teardown, so Stage 5 remains partial.
- This is only a partial data boundary: it establishes canonical heap and
  symbol-table offsets, can locate already-staged synthetic symbol metadata,
  and has one direct static composition proof in caller-owned storage, but does
  not bind `g_ee_main_mem`, advance a heap, initialize native kernel/symbol
  globals, create symbol metadata or types, link game data, execute GOAL
  through the runtime, or initialize an app runtime.
  The CMake proof is not an app, signing, simulator, device, GOAL-execution, or
  live-runtime proof. It therefore does not satisfy this stage's runtime
  initialization or cross-compiled-library exit gates.

## Stage 6 — Complete the Apple platform layer

Outcome: OpenGOAL receives the iPad services required for sustained gameplay.

Required work:

1. Connect supported game controllers to the runtime input model.
2. Initialize audio and handle interruptions and route changes.
3. Preserve state across foregrounding, backgrounding, suspension, and memory
   pressure.
4. Keep gameplay and game audio active when GOALPad remains visible beside
   another iPad app, and allow outside music or video audio to play at the same
   time. Validate the actual iPad multitasking lifecycle signals and audio-mix
   policy rather than treating every loss of focus as true backgrounding.
5. Define app-controlled game-data, save, settings, cache, and log locations.
6. Implement save and load operations with recoverable error handling.
7. Establish frame timing and display lifecycle behavior.
8. Narrow the application to documented iPadOS destinations or split
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

1. Preserve the existing macOS OpenGOAL preparation path while carving out a
   portable, offline data-preparation seam suitable for Apple-device use.
2. Accept a user-selected source image or extracted directory.
3. Verify supported revision and integrity metadata.
4. Reject unknown, incomplete, or corrupted inputs clearly.
5. Produce a deterministic data-only package.
6. Import through supported Apple file workflows.
7. Validate compatibility before starting the runtime.
8. Keep imported data separate from saves and settings.
9. Preserve the implemented streaming, bounds-checked raw ISO reader,
   fail-closed five-revision validator, checked DGO/FR3 preparation, output
   graph/materializer, exact public-artifact generator, checked public source
   pack, `jak1-base-retail` profile, native composer, Objective-C++ bridge,
   recoverable activation, and bounded ZIP32-to-ISO adapter as separately
   validated phases.
10. Keep the current prepared-folder importer available throughout this work.

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

Physical hardware remains required for authoritative final gates, but agents
must not access **Z iPad Pro** unless the maintainer explicitly requests a
physical-device pass in the current task. Until then, leave these gates
pending and continue routine work on the approved M5 simulator.

When explicitly scheduled, use physical hardware to validate:

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

Current checkpoint lanes:

- One Sol `xhigh` integration lane owns scope, review, integration, and the
  checkpoint gate.
- Up to two Sol `xhigh` implementation lanes own non-overlapping importer
  architecture, renderer bugs, ABI/AOT, or unsafe-file-handling work.
- One Terra `medium` or `high` mechanical lane owns bounded CMake, documents,
  fixtures, build-log triage, formatting, or API plumbing.

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
8. Workers run focused checks only; run medium checks per integrated subsystem,
   then the expensive compiler, Metal, AOT, and Xcode matrix once per
   checkpoint.
9. Keep one canonical OpenGOAL build, `/private/tmp/GOALPad-sim` DerivedData,
   and bounded `/private/tmp/GOALPad-ccache`; never run heavy builds in
   parallel. Generate the 518-object source pack once and subsequently verify
   its recorded identity unless its writer or embedded graph changes. Delete
   only obsolete disposable builds after recording their results.
10. Pause the visual lane at a physical A/B gate unless a deterministic
    hypothesis and test can distinguish the next change.
11. Do not delegate maintainer decisions, destructive actions, credential
   entry, proprietary-data handling, or physical-device claims.
12. Stop delegation when it no longer improves the narrow current checkpoint.

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

Checkpoint 62 is the current integration checkpoint. Checkpoint 37 remains the
latest sustained physical gameplay and visual-fidelity run. Its signed build
booted the real Jak 1 kernel and user-local data, rendered 29,666 consecutive
chains during the final run, reached Misty and Training, and exited cleanly.
The maintainer nevertheless rejected it as a camera or visual-fidelity
improvement: camera and world-depth fighting felt worse than Checkpoint 36,
Merc deformation remained, and metallic materials developed a new flicker.
Checkpoints 38-44 record the original app icon, neutral App Store distribution
direction, fail-closed release-AOT policy, windowed visionOS target,
local-first iCloud saves, and current **Eco Pro** identity at
`com.zephyrstudiosllc.eco`. Checkpoint 45 adds an enforced Jak 1 Release-AOT
preflight and a mutually exclusive Jak II iPhoneOS full-AOT link proof; it does
not make Jak II an app target. Checkpoints 46-50 add the checked Jak 1 raw-disc
preparation graph, ZIP32 ingestion, serial staging/activation, and deterministic
synthetic coverage. No successful real raw/ZIP import is claimed.

Checkpoint 51 adds schema-v4 camera, Merc, and target/control diagnostics.
Checkpoint 52 adds raw/ZIP route-to-activation coverage, an atomically published
reproducible 518-object source pack, and a clean unsigned ARM64 macOS, M5 iPad
simulator, and generic visionOS Release matrix. Real-media import remains
unvalidated and explicitly non-blocking by maintainer choice.

Checkpoint 53 classifies the existing physical v4 trace and repairs two
diagnostic blind spots without changing gameplay behavior. The v4 cache showed
zero chain drops, drawable misses, live/packet camera mismatches, or Merc output
composition mismatches, but its camera-slave record was always invalid and its
target/control observer retained no samples. The camera observer had treated a
GOAL `ppointer` as the camera-slave object and rejected derived runtime types.
The bounded v5 observer now dereferences the ppointer, walks the checked runtime
type-parent chain, and retains wall-relevant LOS, movement-blocked, max-angle,
tracking, and rotation fields. Target/control telemetry now retains capture
stage/result, ordinary and neutral/Square samples, engine-frame and probe-slot
identity, raw direction/quaternion fields, camera basis, and input/output
deformation. Focused checks passed. This is diagnostic coverage, not a camera,
steering, or Flat-Stanley fix.

The physical observation is intentionally local: at Geyser Rock, Jak appeared
normally volumetric facing toward the portal and thinnest facing away. The
earlier “backward” description was camera-relative. Camera rotation did not
visibly change thickness in that test, but no global world-heading or
camera-independence conclusion is proved. Ordinary roughly 10-degree roll/Z
shake mostly stopped; severe slower near-wall oscillation and the
wrong-facing/skinny transform failure remain.

The current parent implementation point before this documentation update is
`1427118a28284cdbd19676b38da4faef85ea17b3`. The current nested OpenGOAL pin is
`ac8f3460dbc12b785348eaa96f38353613de7719`. The nested commit matches its
corresponding remote branch before this documentation commit. The recorded Jak 1 source
pack remains 518 objects, aggregate `f1770cae6287a359`, and 10,729,681 bytes;
the AOT corpus remains 10,596 emitted functions and 7 native routines. The
signed v5 generic iOS Release build passed, produced a valid thin ARM64
executable with SHA-256
`82a81daa9c69c7f11cb6eb0fb4570ed672cd922c0ccfe56b6b49443bf5ce83b1`,
and was update-installed and launched on the authorized Z iPad Pro while
preserving its app container. The first controlled v5 portal-relative cache was
backgrounded and copied with SHA-256
`0ac9e9836ea5b5d51acd67a8ed52f8460f46d6b2eeac41716f6e71c1f5820075`.
The repaired camera attachment retained a valid movement-blocked slave and
tracking combiner. However, all 5,754 target/control capture attempts failed at
the control object's exact type check (stage `4`, result `6`), so the cache
cannot classify portal-relative facing or Square through those new fields.
This is a physical observer failure to repair, not evidence that target control
was correct. The away/toward A/B is paused until that probe is no longer blind.

Checkpoint 54 fixes that observer failure without changing gameplay. GOAL's
declared basic-object offsets include the four-byte type tag, but live basic
pointers begin after it; the v5 observer consequently read `node-list` at live
`target + 112` instead of `control` at live `target + 108`. Nested
`c2f933ba0` applies the shared `BASIC_OFFSET` to all diagnostic target/control/
cpad fields, keeps exact runtime types and declared allocated-size checks, and
adds a decoy-old-slot regression. All 58 focused C++ checks and both parent
bridge checks passed. A new signed thin ARM64 Eco Pro build passed with SHA-256
`4b9eb6e0848a2e1c222f0ef8bd16aae9b00739043b4379ecb2f271ca64e9d315`.
It was update-installed on the authorized Z iPad Pro while preserving app data;
launch is pending only because the iPad locked. No corrected physical trace or
visual acceptance is claimed yet.

Jak II now has two additional bounded host seams. Nested `17a097baa` adds an
ordinary-file STR channel 4 seam that validates the measured request/reply shape, reads a
safe uppercase basename from user-local `out/jak2/iso`, bounds the EE write,
and returns actual bytes or a handled error. Its focused unit test passed. The
real headless proof loaded KERNEL 8/8 and GAME 465/465, performed one
309,856-byte STR read, completed 100 dispatcher frames, and no longer repeats
the false `Game subtitle2 heap overrun!` diagnostic. A fresh current-tree
iPhoneOS final-link proof also passed: all 840 objects plus the manifest linked
with alias-safe C rules into a thin ARM64 iOS 18.0 executable, SHA-256
`0490f08ed0d2dde92a58bc9f4192d9bd20d70ae21e43bf2b1ca07fe562fc1e77`,
with representative AOT/kernel/Zstd symbols defined and no unresolved project
symbols. Nested `e4bb61c7f` then makes loader RPC framing command-aware: every
loader command still requires the exact aligned send block, only command 16
requires a reply block, and command 2 now reports a measured bank-load request
as explicitly unimplemented instead of a malformed version handshake. Its
focused unit test and the 100-frame real-data host proof passed. A reviewed
full bank-load attempt remains quarantined because its inner SBlk parsing could
still abort on malformed offsets/counts and its sound shutdown lifecycle was
incomplete. Chunked STR and real bank parsing/loading remain unimplemented.
This is still an unsigned isolated link proof, not app wiring, a signed app,
simulator/device runtime, title screen, or gameplay. Jak II does not displace
Jak 1 as active scope.

Checkpoint 56 identifies and fixes the common source of Jak's angle-dependent
collapse and the coherent wall/out-of-frame camera A/B flicker. The AOT C
backend had lowered packed vector square root as an X-only write. Nested
`360d618b3` restores four-lane semantics and adds broadcast regressions;
`3a425003e` initializes the helper result. A single fresh 518-source sweep
produced a complete Jak 1 AOT corpus and checked source pack with the recorded
identity `f1770cae6287a359`. A signed generic iOS Release build passed, was
update-installed without erasing the app container, and launched on the
authorized Z iPad Pro. Physical visual acceptance and the corrected cache are
still pending the maintainer's active run.

Jak II command 2 now has a bounded host implementation rather than a no-op.
Nested `b40e2f975` reads a user-local SBlk once, preflights and parses the same
bytes, retains the resulting 989snd bank, and owns explicit sound teardown.
Nested `ac8f3460d` closes decoded-allocation amplification with a
format-derived aggregate grain budget and makes partial block construction
exception-safe. The SBlk, sound-RPC, and Jak 1 lifecycle tests pass 3/3. This
is a checked host seam, not playback, app wiring, simulator, or device proof.

Checkpoint 57 records the first strongly positive physical result from the
packed-square-root correction. In the maintainer's current Z iPad Pro run,
gameplay was very playable and the camera, Jak's volumetric shape/facing, and
attacks looked fixed. This is **Experimental** evidence from that run, not a
universal completion claim. After the app was backgrounded, a completed
18,780-frame trace was copied read-only with SHA-256
`7fc6078e01c380818ea42f70914a4afb741e424ce8c67c5cf6be6d5097ede55f`.
It is an independent run rather than a continuation of the earlier live cache.
It confirms unit control/render quaternion norms, unit target/camera-combiner
basis axes, uniform input/output deformation, zero missing Jak bones, and zero
output-composition mismatches. The only consistent visible defect reported in
that run is metallic-material flicker.

The dedicated nested visual work through `988153483` adds schema-v6 post-flag,
root-scale, visibility, raw-draw, attack, and TIE diagnostics plus a narrowly
scoped Jak 1 Metal TIE second-envmap-pass gate. The deterministic Metal A/B/A
proof passed, and the regenerated diagnostic pack verified as 518 objects,
aggregate `0a6387a3959fd8cb`, 10,729,950 bytes, 10,596 emitted functions, and 7
native routines. Nested `63b8a67c` cleanly merges that line with the remote Jak
II sound progress at `4717d6000`; focused Jak 1/Jak II host tests and the signed
iOS compile pass, while real Jak II data boot remains untested. These are
**Implemented** diagnostic/proof seams. The physical
TIE-disabled B update is installed without erasing the app container. Its launch
was denied because the iPad was locked, so the metallic comparison remains
**Experimental** and pending.

The current Jak II full iPhoneOS AOT link proof remains isolated and unsigned.
Its thin ARM64 executable has SHA-256
`4cac833e5ee0197adcf2cecc55272112dbd1b5bd20f56db8c24538277cb3f497`,
minimum iOS 18.0, no unresolved project `goal_`/`ZSTD_` symbols, and no app,
signing, simulator, device, title-screen, or gameplay claim.

Checkpoint 59 closes the current-pin Jak 1 source-build reproducibility gate in
a detached clean worktree: the 518-object pack, full 10,596-function AOT set,
focused host targets, and committed-project generic-iOS Release all pass. It
also adds Jak II's composed channel-3 DGO RPC and AOT-code/data-link boundary,
with synthetic protocol coverage and a real-data 100-frame host boot. This does
not add Jak II app wiring or physical runtime support.

Checkpoint 60 integrates the schema-v7 Jak 1 camera-reversal and weighted-skin
diagnostics with the shared Jak II DGO/title frontier. The supplied physical
screenshots remain separated into a world-heading-dependent character collapse
and a repeating whole-scene wall/out-of-frame camera pose change. The new
diagnostics retain the relevant Merc palette/output and camera
slave/target/combiner evidence, but no behavior fix or physical v7 capture is
claimed.

Checkpoint 61 routes Jak II controller symbols through the portable pad seam,
retains upstream-compatible interrupt-handler registrations, and mirrors the
desktop `engine`/`art`/`common` package bookkeeping after `GAME.CGO`. The
bounded host `--play` probe now exits cleanly without the false standalone
`ART.CGO` request, loads `TITLE.DGO` as one AOT code object plus six data
objects, and stops at the next reporting machine seam, `pc-rand`. Focused pad,
handler, Jak 1 regression, real-data 100-frame, and title-path tests pass. A
fresh isolated iPhoneOS link validates all 840 AOT units and emits a thin ARM64
iOS 18.0 executable containing the pad and handler symbols. This remains an
unsigned link proof, not Jak II app, simulator, device, title-screen, or
gameplay support.

Checkpoint 62 adds a faithful game-neutral `pc-rand` implementation and runs
Jak II's title path through upstream-compatible `play-boot` and a real GOAL
process. The bounded host probe now links the first `TITLE.DGO` code object and
exposes the graphics-DMA frontier after a short reporting/sync seam sequence.
The exact-current 840-unit iPhoneOS link proof passes. An exact-current signed
Jak 1 generic-iOS Release also passes after replacing a stale importer CMake
cache; this closes the clean source/build gap but does not override the
maintainer's physical rejection of the heading-dependent Jak collapse and
near-wall/off-screen camera oscillation.

The Settings-only iCloud resolution design is **Implemented and deterministically
validated** at parent `dca45a36`. It now has source-and-target compare-and-swap,
a durable exact-phase pair journal with embedded source banks, offline and
account-switch recovery, FIFO operation exclusivity, a pregame local-recovery
gate, and same-call upload-only reconciliation after an interrupted cloud
write. The full failure/recovery suite and independent re-review returned GO;
the signed Release artifact built and installed. Real two-device iCloud,
provider interleaving, eviction, account switching, and migration remain
**Experimental** and are not claimed complete.

The next actions are:

1. When the maintainer next explicitly authorizes physical-device access,
   install and run the schema-v7 Jak 1 artifact. Slowly sweep Jak through the
   thin and normal headings in open space, then hold the same wall condition
   with him barely in frame and barely out of frame. Retain one completed event
   from each diagnostic so the palette/output and camera
   slave/target/combiner hypotheses can be decided. Include the bounded TIE
   second-pass metallic comparison in that same authorized run.
2. Validate signed iCloud behavior with two devices, including a real divergent
   pair, account/provider transitions, and preservation of both originals.
3. Keep camera, Merc, importer, source-pack, and AOT gates green. Reuse the
   518-object pack only while its recorded writer and embedded graph remain
   unchanged, and keep the visual nested line separate from clean Jak II work.
4. Continue Jak II with a read-only faithfulness audit of `pc-prof`,
   `flush-cache`, `sync-path`, `syncv`, and `mouse-get-data`, then cross the
   substantive `__send-gfx-dma-chain` boundary by reusing or minimally
   generalizing the existing Jak 1 renderer seam. Playback, streams, app
   wiring, signing, simulator/device runtime, and physical gameplay remain
   unproved.
5. Treat real raw/ZIP import as presentation/distribution follow-up. It is
   explicitly non-blocking and must not be conflated with gameplay readiness.

Use the local iPad Pro 11-inch (M5) simulator as the routine runtime gate.
Checkpoint 62 did not access Z iPad Pro. The maintainer supplied screenshots
from their own current physical run, but the agent did not install, launch,
log, copy, or otherwise access the device. The maintainer reported that the app
was backgrounded or closed, and any later install, launch, logging, capture, or
other physical access requires fresh authorization. No proprietary game data
belongs in source control or CI.
