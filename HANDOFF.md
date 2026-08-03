# GOALPad iPadOS Port Handoff

Date: 2026-08-01

Branch: `feat/ipados-native-boot`

Status: Partially complete. **Read "Checkpoint 38" at the end of this file
before doing anything else.** The synthetic-arena era is over: the app now
initializes the real OpenGOAL Jak 1 kernel, and the AOT C backend currently
emits 10,596 of Jak 1's 10,603 functions, with seven native routines retained.

Everything above and below this note, up to Checkpoint 22, is HISTORICAL. It
describes the previous approach of compiling individual hand-picked GOAL
functions to byte-exact golden ARM64 assembly against a hand-staged synthetic
memory arena. That approach reached roughly a dozen functions and did not
converge; the maintainer directed a change of course. Do not resume it, and do
not treat its "next smallest task" sections as current direction.

The prior checkpoint was parent commit `0b413b9c`, pinned to OpenGOAL child
`9eecb9c3` on `https://github.com/zschwendi/jak-pad.git`.

## Active roadmap and delegated audit

`ROADMAP.md` is the active ten-stage path from the current probe through a
completable Jak 1 physical-iPad result. The implementation goal remains open
until all ten stage exit gates are satisfied.

The roadmap and earlier Stage 2 checkpoints used parallel subagents. Current
delegation uses non-fast `gpt-5.6-sol` with `xhigh` reasoning, per the latest
maintainer direction. Historical model choices below do not override that
current setting.

| Delegation | Scope | Result |
| --- | --- | --- |
| Documentation and milestone audit | Project overview, handoff, build docs, and roadmap structure | Confirmed no prior roadmap; corrected evidence labels, stage ordering, and milestone mapping |
| OpenGOAL compiler audit | ARM64 registers, allocators, IR, CodeGenerator, AOT artifact, and tests | Defined the top-level GOAL literal `42` slice and recommended generated Apple assembly |
| Xcode and validation audit | Target configuration, simulator/device evidence, test surface, and memory-conscious validation | Confirmed simulator gates, physical authority boundaries, and a future need to narrow broad platform declarations |
| ARM64 register implementation | Register identity, calling convention, compiler target plumbing, and both allocators | Implemented target-aware X0-X7 arguments, X0 return, X20/X21/X22 special registers, distinct GPR/SIMD identities, and preserved x86 allocation order |
| ARM64 code-generation implementation | Minimal IR lowering, function emission, and raw non-V3 materialization | Implemented the exact literal-`42` slice without using the desktop runtime-linker object path |
| AOT artifact and test implementation | Writer, CLI, fixture, CMake wiring, and deterministic tests | Added `goalc-aot`, exact instruction tests, unsupported-source rejection, and Apple assembly output |
| Independent Stage 2 review | Cross-target register semantics, allocator regression risk, and next-boundary review | Found and prompted the x86 `hw_id` correction; identified call-clobber handling as the next compiler boundary |
| OpenGOAL state-boundary audits | X20/X21/X22 semantics, ABI preservation, Xcode integration, and probe coverage | Confirmed the app-local static wrapper, 16-byte stack alignment, register snapshots/restoration, and ARM64-only target scope |
| Stage 3 call-clobber audit | ARM64/x86 ABI sets, register identity, and v1/v2 allocator coverage | Confirmed the implementation and prompted exact literal-set assertions instead of a self-referential test |
| Stage 3 source-boundary audit | First real Jak 1 source form, IR seam, and ARM64 emitter operation | Selected the `'#f` body of `false-func` in `gcommon.gc`; the next bounded artifact should be `mov x0, x21; ret` |
| Stage 3 false-form implementation | Narrow symbol-pointer lowering, provenance fixture, compiler tests, and signed-app integration | Compiled real Jak 1 `'#f`, preserved all other symbol rejection, and made the app return its supplied X21 `st` value |
| Stage 3 false-form review | x86 semantic parity, ARM64 bytes, fixture provenance, and app boundary | Confirmed `#f == st+0`, `mov x0, x21; ret`, byte checks, wrapper reuse, and no renderer or lifecycle coupling |
| Full `false-func` failure audit | Exact real `defun`, nearby `identity`, IR sequence, and first deterministic failure | Both forms failed at the two-function guard; selected named-function emission plus empty `IR_ValueReset` was the smaller next seam |
| Named-function compiler audit | Frontend lowering, Apple ABI parameter path, x86 parity, and regression requirements | Confirmed complete `false-func` needs only selected-body emission; `identity` additionally needs GPR `IR_RegSet` |
| Stage 4 artifact audit | V3 links, GOAL pointer representation, symbol storage, and signed export options | Confirmed top-level installation cannot reuse the RWX desktop linker or store a native pointer in the legacy 32-bit-offset symbol value |
| Full `false-func` test implementation | Exact upstream fixtures, named selection, deterministic bytes, missing-name and identity rejection | Added the non-overlapping fixture/test lane; primary agent reviewed, integrated, and ran all validation |
| Named-selection checkpoint review | Selected-function semantics, duplicate definitions, top-level IR, and saved patch integrity | Found that constant-return functions and extra top-level effects could pass or be discarded; prompted the strict corrective checkpoint |
| Static export design audits | Compiler artifact ownership, app registry ABI, linker behavior, and missing-export handling | Independently selected a generated zero-argument X-macro manifest plus an app-local typed registry; no live GOAL symbol-table mutation |
| Stage 4 export-metadata implementation | Paired compiler artifacts, CLI behavior, failure preservation, and CTest coverage | Added guarded `OPENGOAL_AOT_EXPORT0` output for the exact `false-func` proof; validates paired output without changing the signed assembly |
| Stage 4 registry integration and validation | Generated metadata inclusion, typed lookup, host harness, app targets, simulator, and signing evidence | Added app-local zero-argument lookup without writing a native pointer into GOAL data; validated missing-name rejection, ABI state, M5 runtime, and generic signed bundle contents |
| Identity compiler implementation | Exact Jak 1 `identity` IR shape, GPR `IR_RegSet`, Apple-ABI allocation, and negative tests | Compiled only the one-argument identity proof, preserving explicit failure for other function shapes and unsupported IR |
| Typed identity export implementation | Distinct `OPENGOAL_AOT_EXPORT1` contract, paired artifact behavior, and cross-ABI rejection | Added a one-argument metadata lane without broadening the zero-argument export contract |
| Identity registry and wrapper integration | Typed lookup, X20/X21/X22-before-X0 order, probe offsets, combined harness, and app validation | Added the smallest separate one-argument wrapper and required both signed calls without live GOAL pointers or symbol-table mutation |
| `want-vis` compiler implementation | Exact method-body source, strict store lowering, Export2 metadata, and CLI atomicity | Compiled only the real two-form body to five deterministic ARM64 instructions |
| `want-vis` execution review | Combined patch ancestry, guarded arenas, caller-register restoration, and generated artifacts | Verified the host execution proof and identified the non-linear restoration order |
| `want-vis` app integration | Typed registry, runtime verification, app harness, and generated artifacts | Added the second Export2 entry without method installation, dispatch, or lifecycle coupling |
| Validation and claim audit | macOS, named M5 simulator, generic Release signing/layout, and physical-device exclusions | Confirmed each evidence boundary and preserved the no-device rule |
| Checkpoint documentation audit | Commit identities, patch hashes, source citations, status text, and next seam | Corrected the method-body citation and selected compiler-only `want-levels` |
| `want-levels` compiler primitives | Encoder corrections, local labels, guarded math, and signed loop backedges | Added only the exact portable ARM64 operations required by the real two-loop body |
| Complete `want-levels` compiler proof | Strict 160-record IR match, exact source fixture, deterministic golden assembly, and negative cases | Compiled the complete real body to 142 instructions without diagnostic-name gating |
| Export3 implementation | Three-argument manifest, CLI paired-artifact behavior, and cross-arity rejection | Added a distinct typed metadata lane without broadening existing arities |
| Combined host execution proof | Ordered patch replay, guarded six-case branch matrix, and caller-register restoration | Executed the generated body through the real ARM64 call boundary and passed all host regressions |
| Parent artifact and ABI integration | Generated artifact, Export3 registry, eight-argument Apple wrapper, runtime core, and harness | Verified exact arguments, X21 `#f`, whole-arena outcomes, guard bytes, and state restoration |
| Independent Checkpoint 12 reviews | Commit-object scope, generated bytes, ABI layout, semantic matrix, and nonclaims | Accepted the compiler, host, generated-artifact, and parent integration checkpoints with no remaining issue |
| `reset!` compiler and Export1 implementation | Exact 50-IR body, 58-word golden, mutation/CLI tests, and guarded metadata | Compiled only the real direct reset body and preserved the ordered child patches |
| `reset!` host and parent integration | Two disjoint guarded arenas, app-local Export1 registry, native harness, and Apple builds | Verified every reset field, full buffers, ABI state, M5 runtime, and generic signed layout |
| Checkpoint 13 correctness and documentation reviews | Compiler/export/runtime commits, parent diff, signed bundle, status docs, and nonclaims | Accepted the bounded implementation and identified source-faithful wrapper dispatch as the next unresolved boundary |
| Next-seam dispatch audit | `load-state-want-levels`, global binding, type/method lookup, and indirect call | Stopped before guessing a static binding/dispatch architecture that could change virtual semantics |

The implementation agents edited non-overlapping files in the isolated
OpenGOAL worktree. The primary agent reviewed and integrated every diff, fixed
cross-target issues exposed by the full non-network test suite, ran all builds
serially with `-j 4` to limit memory pressure, and created the verified child
commit.

## Direction that must remain fixed

- OpenGOAL C++, GOAL source, tooling, runtime behavior, and formats are the
  implementation source of truth.
- Do not replace OpenGOAL with recreated gameplay, a toy engine, an emulator,
  or a Swift rewrite.
- User-supplied game files remain data. Never commit, distribute, download, or
  synthesize retail assets.
- Executable GOAL code must be generated before the app is linked and signed.
  Ordinary iPadOS cannot depend on JIT, mutable executable pages, private
  entitlements, or jailbreak behavior.
- Keep Apple lifecycle and presentation code at a narrow
  Swift/Objective-C++ boundary.
- Keep simulation separate from rendering and presentation. Do not bind the
  OpenGOAL runtime directly to one view, `CAMetalLayer`, screen size, lifecycle,
  fixed camera, or render target.
- Keep graphics surface, input, audio, filesystem, timing, lifecycle, and
  display configuration behind narrow boundaries when the current port
  directly needs them. Preserve room for separate gameplay and final viewer
  cameras where doing so is negligible.
- Prefer equally small choices that do not foreclose Mac/iPhone targets,
  multiple render views, stereo, external view/projection matrices, or a
  future visionOS presentation layer. Do not implement those future features
  or delay the iPad Jak 1 boot path for them.
- Simulator and generic-device builds are compilation evidence only. Physical
  build, install, launch, and execution must be recorded separately.

The larger future-facing notes are recorded in
`docs/APPLE_PLATFORM_DIRECTION.md`; they are constraints against avoidable
coupling, not current implementation scope.

## Device validation rule

Use the local iPad Pro 11-inch (M5) simulator freely for routine app build,
launch, log, screenshot, and runtime validation. Keep memory use bounded and
shut down that simulator after a validation pass when it was not already
running.

Do not access the physical device named **Z iPad Pro** unless the maintainer
explicitly asks for physical-device testing in the current request. This
includes install, launch, console/log attachment, screenshot, and other
CoreDevice actions. A generic signed iOS build that does not access the device
is allowed and is build/signing evidence only. The authoritative rule is also
recorded in the workspace `AGENTS.md`.

## Repository state

The outer workspace is not a Git repository. The checkout is nested:

```text
/Users/zach/Developer/OS_Projects/GOALPad
└── GOALPad/                         # Git checkout
```

The outer workspace contains local proprietary inputs. None were read into,
copied into, or generated inside the Git checkout.

History at the original 2026-07-31 handoff (newest first):

```text
cabb027 feat(aot): integrate direct Jak 1 load-state reset proof (AI-assisted)
d843e17 feat(aot): add generated Jak 1 load-state reset artifact (AI-assisted)
379949e test(opengoal): preserve Jak 1 reset execution proof (AI-assisted)
27e3a57 feat(opengoal): preserve Jak 1 reset Export1 metadata (AI-assisted)
53f7422 feat(opengoal): preserve Jak 1 reset compiler proof (AI-assisted)
3746363 docs: record complete want-levels AOT checkpoint (AI-assisted)
33beb79 feat(aot): validate complete Jak 1 want-levels body (AI-assisted)
18c6238 feat(aot): add generated Jak 1 want-levels artifact (AI-assisted)
8b991ba test(opengoal): preserve Jak 1 want-levels execution proof (AI-assisted)
9db5b87 feat(opengoal): preserve Jak 1 want-levels Export3 metadata (AI-assisted)
e5bb7a1 feat(opengoal): preserve complete Jak 1 want-levels compiler proof (AI-assisted)
e91581a feat(opengoal): preserve signed ARM64 AOT loops (AI-assisted)
b4beb31 feat(opengoal): preserve guarded ARM64 AOT math (AI-assisted)
b1680ea feat(opengoal): preserve ARM64 AOT control flow (AI-assisted)
0c7bc53 fix(opengoal): preserve ARM64 AOT encoder corrections (AI-assisted)
83c21b2 docs: record want-vis AOT checkpoint (AI-assisted)
3ce59d4 feat(aot): validate Jak 1 want-vis export (AI-assisted)
78e2c66 test(opengoal): preserve Jak 1 want-vis execution proof (AI-assisted)
4580cf3 feat(opengoal): preserve ARM64 want-vis proof (AI-assisted)
5f5b99c docs: record level command AOT checkpoint (AI-assisted)
0da05dd feat(aot): validate level command store export (AI-assisted)
8468742 test(opengoal): preserve Jak 1 level store execution proof (AI-assisted)
6c1370c fix(opengoal): preserve ARM64 store operand guards (AI-assisted)
bf33dcc docs: codify long-running port workflow (AI-assisted)
c577f47 feat(opengoal): preserve ARM64 level command store proof (AI-assisted)
6c9574f docs: record X22-backed GOAL load checkpoint (AI-assisted)
faf3f1a test(opengoal): preserve X22-backed GOAL load proof (AI-assisted)
b041d59 docs: record node-name compiler proof (AI-assisted)
8995197 feat(opengoal): preserve ARM64 node-name AOT proof (AI-assisted)
78bb0ee docs: record generated Jak 1 AOT context checkpoint (AI-assisted)
3cb4e16 test(opengoal): preserve generated Jak 1 AOT execution proof (AI-assisted)
6e3579d docs: record host ARM64 GOAL call ABI checkpoint (AI-assisted)
```

The repository remote remains:

```text
https://github.com/zschwendi/GOALPad.git
```

On 2026-07-30, `git ls-remote origin` failed with:

```text
remote: Repository not found.
fatal: repository 'https://github.com/zschwendi/GOALPad.git/' not found
```

`gh auth status` most recently reported that the configured
`zephyrstudiosllc` credential is invalid and did not report an authenticated
`zschwendi` account. No fork creation or pull request was attempted because
choosing
`zephyrstudiosllc` versus `zschwendi` as the durable owner would change project
ownership and branding direction.

After commits `e77a402`, `821b58c`, and `6830cb4`, explicitly requested pushes
were attempted:

```sh
git push -u origin feat/ipados-native-boot
```

It failed without changing remote state:

```text
remote: Repository not found.
fatal: repository 'https://github.com/zschwendi/GOALPad.git/' not found
```

After parent commit `cf73386`, another requested push first failed in the
sandbox with `Could not resolve host: github.com`. The required external
network escalation was then rejected because the destination remote is still
unverified. No remote state changed. Do not work around that rejection; the
maintainer must explicitly confirm the durable destination and authenticate
it.

No push was attempted for child commits `92c8f975`/`b78d7c28` or parent commits
`eea1031`/`c3187da`. The same destination/authentication blocker remains, and
the earlier rejected escalation must not be bypassed.

## Checkpoint 1: Apple platform/AOT probe

Commit `350867b` preserves the pre-existing uncommitted work:

- A small Swift-to-Objective-C++ bridge.
- Application Support storage initialization.
- A C++ ARM64 function linked into the application before signing.
- Verification of that function's instruction bytes and return value.
- A minimal Metal clear surface.

This is a platform and code-signing probe only. The function is handwritten
C++, not compiler-produced GOAL. The Metal surface is not an OpenGOAL renderer.
Do not expand either into a parallel game implementation.

The current macOS debug build places app code in
`GOALPad.debug.dylib`. Disassembly confirmed:

```text
_goalpad_aot_increment:
    add x0, x0, #0x1
    ret
```

## Checkpoint 2: pinned OpenGOAL baseline

Commit `89e4630` adds:

- `OpenGOAL` as a root-level Git submodule.
- Official source URL `https://github.com/open-goal/jak-project.git`.
- Pinned commit `a4cb1ac1f0596c8740b1c26accb24a58505cda92`.
- Repository-local agent instructions, project overview, README, and build
  documentation.
- Ignore rules for build state, Xcode user state, local game data, disc images,
  and signing material.
- Removal of Xcode user state from Git tracking without deleting the local
  file.

The submodule is deliberately outside the synchronized `GOALPad/` app source
group. The Xcode project otherwise auto-discovers Swift, Objective-C++, and C++
inside that group; placing all upstream source there would accidentally add a
monolithic host codebase to the app.

The official pin is reproducible, but it is not yet a dedicated downstream
fork. Do not commit a parent gitlink that points at an unpublished local child
commit. Create or choose the durable fork owner first.

## Checkpoint 3: real GOAL-to-signed-ARM64 proof

The downstream OpenGOAL work is preserved independently of the clean official
submodule pin:

```text
Parent checkpoint: e77a402
Static state boundary: f13d8f0
Worktree: /private/tmp/GOALPadOpenGOAL-stage2
Branch: goalpad/arm64-aot-proof
Commit: 79f22008c3119bf79297f41d586ab4f75725a36e
Patch: patches/OpenGOAL/0001-Add-minimal-ARM64-GOAL-AOT-proof-AI-assisted.patch
Stage 3 child: 149840cfa8cb4cecd62c8f5c7ffe5a8b8c26ce31
Stage 3 patch: patches/OpenGOAL/0002-Make-function-call-clobbers-target-aware-AI-assisted.patch
Jak 1 false child: 32cf26aef8c61cecdceeb07ed90e0296e1e8e052
Jak 1 false patch: patches/OpenGOAL/0003-Compile-Jak-1-false-form-for-ARM64-AI-assisted.patch
Full false-func child: 92c8f975efc9741c9e6a4bc4b0086f131ac9aefd
Full false-func patch: patches/OpenGOAL/0004-Compile-full-Jak-1-false-function-for-ARM64-AOT-AI-assisted.patch
Named-selection child: b78d7c28c5f4f034e020a4ace48c10a9190d7fa1
Named-selection patch: patches/OpenGOAL/0005-Constrain-named-ARM64-AOT-function-selection-AI-assi.patch
Export-metadata child: 1fc20e793f6c7fd8db3bca3fcc458b098a8b4ea3
Export-metadata patch: patches/OpenGOAL/0006-Emit-atomic-signed-ARM64-export-metadata-AI-assisted.patch
Identity compiler child: 25917e278aeeaf6fee9faa4fbba93f4a2c64f146
Identity compiler patch: patches/OpenGOAL/0007-feat-aot-compile-exact-Jak-1-identity-function-AI-as.patch
Identity export child: 1c80b667aa943d066c1fe2deef85c464c09996fe
Identity export patch: patches/OpenGOAL/0008-feat-aot-add-typed-identity-export-metadata-AI-assis.patch
```

The child commit adds:

- Target-selected ARM64 register and calling-convention metadata.
- Distinct cross-target register identity and distinct ARM64 GPR/SIMD banks.
- Target plumbing through both register allocators and the compiler.
- The minimal ARM64 IR and function generation needed by top-level GOAL
  literal `42`.
- A dedicated raw single-function materialization path. It does not call
  `generate_data_v3` and does not produce desktop runtime-linker code objects.
- `goalc-aot`, which compiles the exact fixture to deterministic Apple
  assembly while rejecting unsupported source and backend paths.
- Regression coverage for the ARM64 emitter fields used by the proof and for
  preserved x86 behavior.

The generated app artifact is:

```text
GOALPad/Native/Generated/OpenGOALConstant42.s
```

It contains exactly:

```asm
.section __TEXT,__text,regular,pure_instructions
.p2align 2
.globl _goalpad_aot_constant_42
_goalpad_aot_constant_42:
  .long 0xd2800540
  .long 0xd65f03c0
.subsections_via_symbols
```

Reproducibility hashes:

```text
a9376d35e97f966dfcced3b4f47a36045ebc60ed98d57833d7da41b0ddfac1ac  OpenGOALConstant42.s
2f96d9a99f1806825538fdfbd3c5d09b9a2bdc044d58ffbfaac9cf859071c68c  OpenGOAL Stage 2 patch
23d33b602fdeb2da1cc9e5f47c276e24c2f2c52b86b837e6523338a19c9668d1  OpenGOAL Stage 3 call-clobber patch
42a8d20a4d9f1b5edd7ef5e5a11d6a0e6239d1cc4d1a1323c9ac6aa5ccffe369  OpenGOALJak1False.s
fd9ddb6491c6b45250e44169dac84d3b70405b37d87b8b9d76b4c9968be53bcb  OpenGOAL Stage 3 false-form patch
22b670ac4b318a43a8e3e049b9d576b3ad1a8292d0df3f52397d1156cca8c450  OpenGOALJak1FalseFunc.s
65116d095cc43dd09e26222d2f7702a30dba6bbb0559f951f33458e27ecace3f  OpenGOAL full false-func patch
abb26d05d717d87d4a4a93fc11bd269082ba672b2fdd16d192f68667025f79ce  OpenGOALJak1FalseFunc.exports.h
d6930f33b01f004682da2232b773bfcc5f8a5192d62bbce5f3ee9e49826fd069  OpenGOAL export-metadata patch
ab3b9d8f63e473fee9fc108d0e38921b2cc754688924fbe473706198ad2cf246  OpenGOALJak1Identity.s
02e4c08a949be31945366020100e6a5be27933b09011bf5d78a16b03e39d4f83  OpenGOALJak1Identity.exports.h
b6e27d488849bca0c2e27095b16c458f8d152f0a297d9b109329ad974645162c  OpenGOAL identity compiler patch
57fbf8e6d38be489abeba80c1b3664fa899db742fbd387282e0ff628346ba2eb  OpenGOAL identity export patch
dcccaaa13f07aced806cfac3a210ecd6a8b43268024fa1cf5da634f01384ff87  OpenGOALJak1TrueFunc.s
9fbe7cf54992385ad6c91bad9433cd716d0379bbbb424600cec7c338dfcd8629  OpenGOALJak1TrueFunc.exports.h
4ce50d86b4d44730f1c6e847aabe59cfcb8c95bb2e01660d210b3d4e7f92bffe  OpenGOAL true-func compiler patch
a625a581402bd08546e28b5a3ba9c72556a44db21ffed026497cfef4e5910f46  OpenGOAL true-func export patch
7d886912f47c51023c09dc168141598b61877bf60eceee16abdd1b84f5a79d34  OpenGOAL lognot assembly artifact
2f8587a50c6c7d5bc7ff1f07dbd396d6fdcb37e063a05ad2d617fc9a71c55858  OpenGOAL lognot Export1 header
18339711be9d4bbde58dced7f2f208cdb0799c938052fbbc04023dd47e3ec087  OpenGOAL lognot compiler patch
38f764204543d516dcf1581b5ded2ed9b63618f933ae0aac705f8bc99e7caf56  OpenGOAL lognot export patch
```

`GOALPadRuntimeCore.cpp` now calls the compiler-generated Jak 1 false function
in `GOALPad/Native/Generated/OpenGOALJak1False.s` through
`GOALPadGoalStateWrapper.s`. The wrapper establishes X20 as the GOAL
process/`pp` value, X21 as `st`, and X22 as the GOAL memory offset base,
captures the state before and after the generated call, and restores the
caller's callee-saved registers. The core verifies all snapshots, the expected
instruction bytes, and that the result equals the supplied X21 `st` value
`0x2002`. The values remain synthetic and are never dereferenced. The earlier
literal artifact and handwritten probe remain preserved, but neither supplies
the displayed result.

## Verified OpenGOAL and Stage 2 compiler

The official `OpenGOAL` submodule was temporarily detached at child commit
`79f22008` only for validation, then restored to the clean official pin. The
existing build directory was reused to avoid another large build tree.

```sh
cmake -S OpenGOAL -B /private/tmp/GOALPad-pinned-opengoal-build \
  --preset=Release-macos-arm64-clang \
  -DOPENSSL_ROOT_DIR=/opt/homebrew/opt/openssl@3

cmake --build /private/tmp/GOALPad-pinned-opengoal-build \
  --target goalc-aot goalc-test -j 4

cmake --build /private/tmp/GOALPad-pinned-opengoal-build \
  --target gk -j 4

/private/tmp/GOALPad-pinned-opengoal-build/goalc-test \
  --gtest_filter='Arm64Aot.*:ARM64EmitterLoads.*:ARM64EmitterIntegerMath.*:CodeTester.*:X86EmitterXMM.*:EmitterAVX.*'

/private/tmp/GOALPad-pinned-opengoal-build/goalc-test \
  --gtest_filter='-Listener.*'

/private/tmp/GOALPad-pinned-opengoal-build/goalc/goalc-aot \
  --project-path "$PWD/OpenGOAL" \
  --input "$PWD/OpenGOAL/test/goalc/source_templates/arm64-aot/constant-42.gc" \
  --output /private/tmp/goalpad_aot_constant_42.s \
  --symbol goalpad_aot_constant_42

xcrun --sdk iphoneos clang -arch arm64 \
  -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" \
  -c /private/tmp/goalpad_aot_constant_42.s \
  -o /private/tmp/goalpad_aot_constant_42.o

file /private/tmp/goalpad_aot_constant_42.o
xcrun llvm-objdump --macho --disassemble \
  /private/tmp/goalpad_aot_constant_42.o
```

Results:

- CMake configure exited `0`.
- `goalc-aot`, `goalc-test`, and the full `gk` host target built successfully.
- All 91 focused ARM64 AOT/emitter and affected x86 regression tests passed.
- All 689 tests other than the local-socket `Listener.*` tests passed.
- `goalc-aot` produced exactly `mov x0, #42; ret`.
- The iPhoneOS assembler produced a Mach-O 64-bit ARM64 object, and
  `llvm-objdump` confirmed those two instructions.
- An ARM64 macOS C harness linked the same generated assembly, called the
  function, received `42`, and exited `0`.

The nine `Listener.*` tests were run separately: three passed and six failed
because the sandbox could not bind local port `8112`
(`XSocketServer:8112 failed to bind`). `lsof` found no competing listener.
These network-environment failures are not source regressions; the non-network
suite remains the reproducible local gate.

An earlier full run exposed 68 x86 regressions because ARM64 architectural
register IDs had initially been applied to x86 SIMD registers as well. The
target-specific `Register::hw_id` correction fixed them; the 91 focused tests
and 689-test non-network suite above are the final post-fix results.

## Verified Stage 3 call-clobber checkpoint

The isolated OpenGOAL worktree advanced from `79f22008` to child commit
`149840cfa8cb4cecd62c8f5c7ffe5a8b8c26ce31` without moving the official
submodule pin. `IR_FunctionCall` now carries its instruction set and uses a
target-specific call-clobber set. ARM64 clobbers X0-X15, V0-V7, and V16-V31;
x86 preserves its previous RAX, RCX, RDX, RSI, RDI, R8, R9, and XMM0-XMM7
behavior. Tests verify those exact vectors and prove that both v1 and v2
allocators keep GPR and SIMD values live across calls in saved ARM64
registers.

```sh
cmake -S /private/tmp/GOALPadOpenGOAL-stage2 \
  -B /private/tmp/GOALPadOpenGOAL-stage3-build \
  --preset=Release-macos-arm64-clang \
  -DOPENSSL_ROOT_DIR=/opt/homebrew/opt/openssl@3

cmake --build /private/tmp/GOALPadOpenGOAL-stage3-build \
  --target goalc-test goalc-aot --parallel 4

/private/tmp/GOALPadOpenGOAL-stage3-build/goalc-test \
  --gtest_filter='Arm64Aot.*'

/private/tmp/GOALPadOpenGOAL-stage3-build/goalc-test \
  --gtest_filter='-Listener.*'
```

Results: configuration exited `0`; both targets built; all 5 focused tests
passed; and all 691 non-listener tests passed. The larger count reflects the
two new Stage 3 tests. No device build was required because this checkpoint
changes compiler allocation metadata only and does not change the checked-in
app artifact.

## Verified Stage 3 Jak 1 false-form checkpoint

Child commit `32cf26aef8c61cecdceeb07ed90e0296e1e8e052` adds a
provenance-preserving fixture containing the `'#f` expression from the body of
Jak 1 `false-func` in `goal_src/jak1/kernel/gcommon.gc`. The AOT path accepts
only the original literal `42` or `#f`; `#t`, named symbols, statics, calls,
and other IR remain rejected. ARM64 `IR_LoadSymbolPointer` implements only
`#f` by moving X21 `st` to the allocated return register.

```sh
cmake --build /private/tmp/GOALPadOpenGOAL-stage3-build \
  --target goalc-test goalc-aot --parallel 4

/private/tmp/GOALPadOpenGOAL-stage3-build/goalc-test \
  --gtest_filter='Arm64Aot.*'

/private/tmp/GOALPadOpenGOAL-stage3-build/goalc-test \
  --gtest_filter='-Listener.*'

/private/tmp/GOALPadOpenGOAL-stage3-build/goalc/goalc-aot \
  --project-path /private/tmp/GOALPadOpenGOAL-stage2 \
  --input /private/tmp/GOALPadOpenGOAL-stage2/test/goalc/source_templates/arm64-aot/false-from-jak1-gcommon.gc \
  --output /private/tmp/goalpad_aot_false.s \
  --symbol goalpad_aot_false
```

Results: both targets built; all 6 focused tests and all 692 non-listener tests
passed. The compiler output is exactly:

```text
mov x0, x21
ret
```

The iPhoneOS assembler produced a Mach-O 64-bit ARM64 object and
`llvm-objdump` confirmed those instructions. `cmp` verified the output is
byte-identical to `GOALPad/Native/Generated/OpenGOALJak1False.s`.

The host harness exited `0`, and the ARM64 macOS app target built. The
dedicated M5 simulator built, installed, launched as PID `22771`, and logged:

```text
GOALPad runtime probe: Signed ARM64 Jak 1 false-form state call verified;
architecture=arm64; result=8194
```

The settled screenshot at `/private/tmp/GOALPad-jak1-false-m5.png` visually
shows the same success and `AOT result: 8,194`. Only the dedicated M5
simulator was shut down afterward; no state-changing command targeted a
Freemote simulator in that historical pass.

The generic iOS build completed normal Apple Development signing. The signed
binary contains `_goalpad_aot_false` at `0x4008`, and disassembly confirms
`mov x0, x21; ret`. Installation on the physical M5 iPad succeeded. Two normal
launch attempts failed only because SpringBoard reported the device was
locked. After those attempts, the maintainer directed agents not to access the
physical Z iPad Pro unless explicitly requested in the current task. Physical
execution of this new false-form build is therefore deferred; the earlier
literal Stage 2 build remains the latest physically executed checkpoint.

## Verified Stage 3 complete `false-func` checkpoint

Child commit `92c8f975efc9741c9e6a4bc4b0086f131ac9aefd` compiles the
complete real Jak 1 definition from `goal_src/jak1/kernel/gcommon.gc:173`.
`goalc-aot --function false-func` selects the named function from the
two-function object created by `defun`. Empty `IR_ValueReset` is emitted as
function-entry metadata/no code. The surrounding top-level `define` is
compiled by the frontend but is not materialized or applied.

The first pre-change failure was preserved for both exact real forms:

```text
Error during ARM64 AOT code generation:
ARM64 AOT proof only supports one top-level function.
```

After the change, full `false-func` produces exactly:

```text
mov x0, x21
ret
```

The exact real `identity` form remains rejected because its named body also
requires parameter entry and GPR `IR_RegSet`. Unknown selected function names,
statics, top-level symbol installation, general relocations, calls, saved
registers, spills, and stack locals remain explicit failures.

```sh
cmake --build /private/tmp/GOALPadOpenGOAL-stage3-build \
  --target goalc-test goalc-aot --parallel 4

/private/tmp/GOALPadOpenGOAL-stage3-build/goalc-test \
  --gtest_filter='Arm64Aot.*'

/private/tmp/GOALPadOpenGOAL-stage3-build/goalc-test \
  --gtest_filter='-Listener.*'

/private/tmp/GOALPadOpenGOAL-stage3-build/goalc/goalc-aot \
  --project-path /private/tmp/GOALPadOpenGOAL-stage2 \
  --input /private/tmp/GOALPadOpenGOAL-stage2/test/goalc/source_templates/arm64-aot/full-false-func-from-jak1-gcommon.gc \
  --function false-func \
  --output /private/tmp/goalpad_aot_full_false_func.s \
  --symbol goalpad_aot_false_func
```

Results: both affected targets built; all 9 focused tests and all 695
non-listener tests passed. The CLI output SHA-256 is
`22b670ac4b318a43a8e3e049b9d576b3ad1a8292d0df3f52397d1156cca8c450`.
The iPhoneOS assembler produced a Mach-O 64-bit ARM64 object, and
`llvm-objdump` confirmed `mov x0, x21; ret`.

The first incremental build exposed one current-change error:
`assigning to 'FunctionEnv *' from 'const FunctionEnv *' discards qualifiers`.
Named/top-level selection was corrected to recover the mutable function from
the owning `FileEnv::functions()` vector; the complete build and test results
above are post-fix.

Parent commit `eea1031` checks in the byte-identical generated artifact as
`GOALPad/Native/Generated/OpenGOALJak1FalseFunc.s` and routes the existing
generic X20/X21/X22 wrapper and host harness through it. The harness and ARM64
macOS app build passed. The dedicated M5 simulator build installed and launched
as PID `30667`, then logged:

```text
GOALPad runtime probe: Signed ARM64 Jak 1 false-func body call verified;
architecture=arm64; result=8194
```

The screenshot `/private/tmp/GOALPad-full-false-func-m5.png` shows the same
success. The M5 simulator was shut down afterward; no state-changing command
targeted a Freemote simulator in that historical pass.

The generic iOS build completed normal Apple Development signing without
accessing a physical device. The signed binary contains
`_goalpad_aot_false_func` at `0x4010`, and disassembly confirms the expected
two instructions. This is build/signing evidence only. No physical-device
validation was attempted.

The exact child patch is preserved as
`patches/OpenGOAL/0004-Compile-full-Jak-1-false-function-for-ARM64-AOT-AI-assisted.patch`.
Its SHA-256 is
`65116d095cc43dd09e26222d2f7702a30dba6bbb0559f951f33458e27ecace3f`;
the child commit and saved patch share stable patch ID
`bfde6607109f75e86c0ef09246e0bbca758aea99`.

### Strict named-selection corrective checkpoint

Child commit `b78d7c28c5f4f034e020a4ace48c10a9190d7fa1` narrows the
selected-function proof to what the checkpoint claims. A zero-argument
function returning `42` can no longer pass as Jak 1 `false-func`; the selected
body must be named `false-func` and load `#f`. Duplicate definitions are
rejected. Named selection also requires exactly one named function plus the
unmodified top-level `IR_FunctionAddr`/`IR_SetSymbolValue`/`IR_Return`/`IR_Null`
installer tied to that function and symbol, so unrelated top-level effects
cannot be silently discarded.

```sh
cmake --build /private/tmp/GOALPadOpenGOAL-stage3-build \
  --target goalc-test goalc-aot --parallel 4

/private/tmp/GOALPadOpenGOAL-stage3-build/goalc-test \
  '--gtest_filter=Arm64Aot.*'

/private/tmp/GOALPadOpenGOAL-stage3-build/goalc-test \
  '--gtest_filter=-Listener.*'

git apply --check --reverse \
  patches/OpenGOAL/0005-Constrain-named-ARM64-AOT-function-selection-AI-assi.patch
```

Results: both targets built; all 12 focused tests and all 698 non-listener
tests passed. The first focused invocation omitted quotes around the zsh glob
and exited before running tests with
`zsh:1: no matches found: --gtest_filter=Arm64Aot.*`; the quoted command above
is the successful rerun. The saved patch SHA-256 is
`6e02050128cfdbbf275f516d6a76fa92956efa693d1ecc07f7c30cfc249639a9`.
The child commit and saved patch share stable patch ID
`45d430b5e0d1520a15707b5e49f35a14ff36e802`.

## Verified Stage 4 export-registry checkpoint

Child commit `1fc20e793f6c7fd8db3bca3fcc458b098a8b4ea3` extends the constrained
`false-func` proof with paired build outputs: the unchanged signed ARM64 text
and a guarded C++ X-macro record:

```text
OPENGOAL_AOT_EXPORT0("false-func", goalpad_aot_false_func)
```

`--exports-output` requires `--function`, rejects an alias of `--output`, and
only accepts this exact proof name and C symbol. The implementation generates
both outputs before publication and preserves pre-existing destinations when a
paired publication cannot complete. This is build-time native binding, not a
GOAL symbol-table write, a native pointer stored in GOAL's legacy 32-bit
offset representation, relocation, or the desktop V3 runtime linker.

```sh
cmake --build /private/tmp/GOALPadOpenGOAL-stage3-build \
  --target goalc-test goalc-aot --parallel 4

/private/tmp/GOALPadOpenGOAL-stage3-build/goalc-test \
  '--gtest_filter=Arm64Aot.*'

/private/tmp/GOALPadOpenGOAL-stage3-build/goalc-test \
  '--gtest_filter=-Listener.*'

ctest --test-dir /private/tmp/GOALPadOpenGOAL-stage3-build \
  -R '^goalc-aot-artifact-pair$' --output-on-failure

/private/tmp/GOALPadOpenGOAL-stage3-build/goalc/goalc-aot \
  --project-path /private/tmp/GOALPadOpenGOAL-stage2 \
  --input /private/tmp/GOALPadOpenGOAL-stage2/test/goalc/source_templates/arm64-aot/full-false-func-from-jak1-gcommon.gc \
  --function false-func \
  --output /private/tmp/goalpad_aot_full_false_func.s \
  --exports-output /private/tmp/goalpad_aot_full_false_func.exports.h \
  --symbol goalpad_aot_false_func

cmp /private/tmp/goalpad_aot_full_false_func.s \
  GOALPad/Native/Generated/OpenGOALJak1FalseFunc.s

cmp /private/tmp/goalpad_aot_full_false_func.exports.h \
  GOALPad/Native/Generated/OpenGOALJak1FalseFunc.exports.h

git -C /private/tmp/GOALPadOpenGOAL-stage2 apply --check --reverse \
  "$PWD/patches/OpenGOAL/0006-Emit-atomic-signed-ARM64-export-metadata-AI-assisted.patch"
```

Results: both affected targets built; all 16 focused tests and all 702
non-listener tests passed; `goalc-aot-artifact-pair` passed; both comparisons
passed; and the reverse patch check passed. The saved patch SHA-256 is
`d6930f33b01f004682da2232b773bfcc5f8a5192d62bbce5f3ee9e49826fd069`.
The child commit and saved patch share stable patch ID
`60d83aca19145d279e71260106cf9776b556db4e`.
Parent commit `a5df18a` preserves that verified patch in the repository.

Parent commit `463e366` adds `GOALPadAOTExportRegistry`, which declares the
generated C symbol and constructs an app-local typed table only after defining
`OPENGOAL_AOT_EXPORT0`. `find_aot_export0("false-func")` supplies the entry to
the existing state wrapper; missing and empty names return no entry. The
runtime treats a missing required export as an initialization failure. The
registry does not initialize a live GOAL symbol table.

```sh
xcrun --sdk macosx clang++ -std=c++20 -arch arm64 \
  -I GOALPad/Native \
  tests/native/GOALPadAOTExportRegistryHarness.cpp \
  GOALPad/Native/GOALPadAOTExportRegistry.cpp \
  GOALPad/Native/Generated/OpenGOALJak1FalseFunc.s \
  GOALPad/Native/GOALPadGoalStateWrapper.s \
  -o /private/tmp/goalpad_aot_export_registry_harness

/private/tmp/goalpad_aot_export_registry_harness
```

The host registry harness exited `0`: it resolved `false-func`, rejected
unknown/empty names, returned the supplied X21 `st` value, and preserved the
synthetic X20/X21/X22 state contract.

The current-source ARM64 macOS build, dedicated M5 simulator build/run, and
generic signed iOS build all passed using reused derived-data trees and `-jobs
4`. The final M5 launch ran as PID `46524` and logged:

```text
GOALPad runtime probe: Signed ARM64 Jak 1 false-func body call verified;
architecture=arm64; result=8194
```

`/private/tmp/GOALPad-stage4-export-registry-final-m5.png` was inspected and
shows that result. The M5 simulator was shut down afterward; no Freemote
command was issued in that pass. The generic signed app is thin ARM64 and contains
`_goalpad_aot_false_func` at `0x4010`, the registry lookup, and the state
wrapper; disassembly confirms `mov x0, x21; ret`. Xcode completed normal Apple
Development signing. A subsequent `codesign --verify --deep --strict` returned
`CSSMERR_TP_NOT_TRUSTED`; that local certificate-trust result is not resolved
by this checkpoint and is not evidence against the successful Xcode signing.
No physical device was accessed.

The first sandboxed macOS build failed in `sandbox-exec` while Swift Preview
processing. The successful escalated build is the recorded macOS evidence.
An initial `.inc` metadata suffix also produced an Xcode warning, so the
checked-in generated metadata is deliberately named `.exports.h`.

### Typed `identity` function and export checkpoint

Child commit `25917e278aeeaf6fee9faa4fbba93f4a2c64f146` compiles the exact
one-argument real Jak 1 `identity` function from `gcommon.gc`. Its narrow
ARM64 path supports only the GPR `IR_RegSet` that moves the one `object`
argument through Apple-ABI X0; the selected body therefore contains exactly:

```text
ret
```

Child commit `1c80b667aa943d066c1fe2deef85c464c09996fe` pairs that text with
the distinct typed metadata record:

```text
OPENGOAL_AOT_EXPORT1("identity", goalpad_aot_identity)
```

The one-argument record cannot be emitted for `false-func`, and the
zero-argument record cannot be emitted for `identity`. Cross-ABI or
wrong-symbol requests fail while preserving existing paired artifacts.

```sh
cmake --build /private/tmp/GOALPadOpenGOAL-stage3-build \
  --target goalc-test goalc-aot --parallel 4

/private/tmp/GOALPadOpenGOAL-stage3-build/goalc-test \
  '--gtest_filter=Arm64Aot.*'

/private/tmp/GOALPadOpenGOAL-stage3-build/goalc-test \
  '--gtest_filter=-Listener.*'

ctest --test-dir /private/tmp/GOALPadOpenGOAL-stage3-build --output-on-failure

/private/tmp/GOALPadOpenGOAL-stage3-build/goalc/goalc-aot \
  --project-path /private/tmp/GOALPadOpenGOAL-stage2 \
  --input /private/tmp/GOALPadOpenGOAL-stage2/test/goalc/source_templates/arm64-aot/full-identity-from-jak1-gcommon.gc \
  --function identity \
  --output /private/tmp/goalpad_aot_identity.s \
  --exports-output /private/tmp/goalpad_aot_identity.exports.h \
  --symbol goalpad_aot_identity

cmp /private/tmp/goalpad_aot_identity.s \
  GOALPad/Native/Generated/OpenGOALJak1Identity.s

cmp /private/tmp/goalpad_aot_identity.exports.h \
  GOALPad/Native/Generated/OpenGOALJak1Identity.exports.h

git -C /private/tmp/GOALPadOpenGOAL-stage2 apply --check --reverse \
  "$PWD/patches/OpenGOAL/0007-feat-aot-compile-exact-Jak-1-identity-function-AI-as.patch"

git -C /private/tmp/GOALPadOpenGOAL-stage2 apply --check --reverse \
  "$PWD/patches/OpenGOAL/0008-feat-aot-add-typed-identity-export-metadata-AI-assis.patch"
```

Results: both targets built; all 22 focused tests and all 708 non-listener
tests passed; CTest passed 1/1; both comparisons and both reverse patch checks
passed. The compiler patch SHA-256 is
`b6e27d488849bca0c2e27095b16c458f8d152f0a297d9b109329ad974645162c`
with stable patch ID `aacd14b605e40ae1651c860ae2d98d426fcdd845`. The typed
export patch SHA-256 is
`57fbf8e6d38be489abeba80c1b3664fa899db742fbd387282e0ff628346ba2eb`
with stable patch ID `d5c5ce0a113a6d023f14804caf8792c473e1e54e`.
Parent commits `9faaa0e` and `a2235da` preserve the two child patches.

Parent commit `ffeb20d` adds a separate `AOTEntry1`/`AOTExport1` registry lane
and one-argument wrapper. The wrapper sets synthetic X20/X21/X22 state before
copying its X4 argument to X0, then invokes only the typed registry entry.
The `GoalCallProbe1` test record captures input argument, result, entry/exit
state, and caller-restoration sentinels; no native pointer enters a live GOAL
symbol value or table.

```sh
xcrun --sdk macosx clang++ -std=c++20 -arch arm64 \
  -I GOALPad/Native \
  tests/native/GOALPadAOTExportRegistryHarness.cpp \
  GOALPad/Native/GOALPadAOTExportRegistry.cpp \
  GOALPad/Native/Generated/OpenGOALJak1FalseFunc.s \
  GOALPad/Native/Generated/OpenGOALJak1Identity.s \
  GOALPad/Native/GOALPadGoalStateWrapper.s \
  -o /private/tmp/goalpad_aot_export_registry_harness

/private/tmp/goalpad_aot_export_registry_harness
```

The combined host harness exited `0`. It resolves both typed entries, rejects
cross-type/missing names, exercises the wrapper that establishes X20/X21/X22
before placing the identity argument in X0, verifies identity returns the
exact object argument, and checks both wrappers restore caller state.

The current-source ARM64 macOS build, M5 simulator build/run, and generic
signed iOS build passed with reused build trees and `-jobs 4`. The final M5
launch ran as PID `50618` and logged:

```text
GOALPad runtime probe: Signed ARM64 Jak 1 false-func and identity calls verified;
architecture=arm64; result=8194
```

`/private/tmp/GOALPad-stage4-identity-final-m5.png` was inspected and shows
that result. The M5 simulator was shut down. No state-changing command targeted
a Freemote simulator; final observed Freemote simulator states had changed
externally (two shut down and one booted), so this checkpoint makes no
attribution about them. The thin
ARM64 signed dylib contains `goalpad_aot_false_func` at `0x4010` and
`goalpad_aot_identity` at `0x4018`, both typed lookups/wrappers, and the exact
`mov x0, x21; ret` and `ret` instruction sequences. No physical device was
accessed. The prior `codesign --verify --deep --strict`
`CSSMERR_TP_NOT_TRUSTED` certificate-trust caveat remains unresolved and was
not rerun.

## Verified Jak 1 `true-func` compiler, export, and runtime checkpoint

Child commit `35d653f1fadc52e78925e952a507d60dc4c11245`
(`feat(aot): compile exact Jak 1 true function (AI-assisted)`) compiles the
exact zero-argument `true-func` definition from upstream Jak 1 `gcommon.gc`.
Its selected ARM64 text is exactly:

```text
mov x0, x21
add x0, x0, #8
ret
```

This represents OpenGOAL `#t` as the synthetic X21 `st` base plus eight.
Child commit `f979c82cb6da50b847808ebd23ec10c4fa1c1c9e`
(`feat(aot): export exact Jak 1 true function (AI-assisted)`) adds the
matching zero-argument metadata record:

```text
OPENGOAL_AOT_EXPORT0("true-func", goalpad_aot_true_func)
```

The strict export allowlist remains limited to zero-argument `false-func` and
`true-func`, and one-argument `identity`. Wrong bodies, native symbols, and
cross-ABI export requests are rejected without replacing existing paired
artifacts. Neither change executes the surrounding top-level `define`, writes
a live GOAL symbol table, or uses a desktop runtime linker.

The preserved downstream patches are:

```text
0009-feat-aot-compile-exact-Jak-1-true-function-AI-assist.patch
SHA-256: 4ce50d86b4d44730f1c6e847aabe59cfcb8c95bb2e01660d210b3d4e7f92bffe
stable patch ID: 8afa60cccac0c7590763211fb086db106fde0094

0010-feat-aot-export-exact-Jak-1-true-function-AI-assiste.patch
SHA-256: a625a581402bd08546e28b5a3ba9c72556a44db21ffed026497cfef4e5910f46
stable patch ID: 37fc0b9f2f8571ab8ddbf997579b6f29a1fe23b8
```

Parent commit `0866a1e` preserves patch 0009, `1d5e4bf` preserves patch 0010,
and `d12f732` links the generated true-function artifacts into GOALPad. The
checked-in artifacts match the compiler output and have these SHA-256 hashes:

```text
dcccaaa13f07aced806cfac3a210ecd6a8b43268024fa1cf5da634f01384ff87  OpenGOALJak1TrueFunc.s
9fbe7cf54992385ad6c91bad9433cd716d0379bbbb424600cec7c338dfcd8629  OpenGOALJak1TrueFunc.exports.h
```

The compiler checkpoint was validated with the existing constrained build and
test surface:

```sh
cmake --build /private/tmp/GOALPadOpenGOAL-stage3-build \
  --target goalc-test goalc-aot gk -j 4

/private/tmp/GOALPadOpenGOAL-stage3-build/goalc-test \
  --gtest_filter='Arm64Aot.*:ARM64EmitterLoads.*:ARM64EmitterIntegerMath.*:CodeTester.*:X86EmitterXMM.*:EmitterAVX.*'

/private/tmp/GOALPadOpenGOAL-stage3-build/goalc-test \
  --gtest_filter='-Listener.*'

ctest --test-dir /private/tmp/GOALPadOpenGOAL-stage3-build \
  -R '^goalc-aot-artifact-pair$' --output-on-failure

git -C /private/tmp/GOALPadOpenGOAL-stage2 apply --check --reverse \
  "$PWD/patches/OpenGOAL/0009-feat-aot-compile-exact-Jak-1-true-function-AI-assist.patch"

git -C /private/tmp/GOALPadOpenGOAL-stage2 apply --check --reverse \
  "$PWD/patches/OpenGOAL/0010-feat-aot-export-exact-Jak-1-true-function-AI-assiste.patch"
```

Results: the affected targets built; all 27 focused tests and all 713
non-listener tests passed; CTest passed 1/1; checked-in assembly and metadata
compared byte-for-byte; and both reverse patch checks passed.

The app-local zero-argument registry includes the true-function metadata beside
`false-func`, then uses the existing state wrapper to verify its twelve signed
ARM64 instruction bytes, result, entry/exit X20/X21/X22 state, and caller
restoration. Together, the two current deterministic host harnesses link both
zero-argument generated entries; the registry harness also links `identity`:

```sh
xcrun --sdk macosx clang -arch arm64 \
  tests/native/GOALPadAOTStateHarness.c \
  GOALPad/Native/Generated/OpenGOALJak1FalseFunc.s \
  GOALPad/Native/Generated/OpenGOALJak1TrueFunc.s \
  GOALPad/Native/GOALPadGoalStateWrapper.s \
  -o /private/tmp/goalpad_jak1_true_func_state_harness

/private/tmp/goalpad_jak1_true_func_state_harness

xcrun --sdk macosx clang++ -std=c++20 -arch arm64 \
  -I GOALPad/Native \
  tests/native/GOALPadAOTExportRegistryHarness.cpp \
  GOALPad/Native/GOALPadAOTExportRegistry.cpp \
  GOALPad/Native/Generated/OpenGOALJak1FalseFunc.s \
  GOALPad/Native/Generated/OpenGOALJak1TrueFunc.s \
  GOALPad/Native/Generated/OpenGOALJak1Identity.s \
  GOALPad/Native/GOALPadGoalStateWrapper.s \
  -o /private/tmp/goalpad_aot_export_registry_harness

/private/tmp/goalpad_aot_export_registry_harness
```

Both harnesses exited `0`. The registry harness resolves `true-func` only
through the zero-argument lane, rejects it from the one-argument lane, and
checks that every wrapper restores its caller state.

The verified app builds and runtime evidence were:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/GOALPad-mac -jobs 4 \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/GOALPad-sim \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug \
  -destination 'id=96C5C21A-B925-4213-82A3-90DCB8518339' \
  -derivedDataPath /private/tmp/GOALPad-sim -jobs 4 build

xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-device -jobs 4 build
```

The ARM64 macOS build passed. The generic simulator build selected x86_64 and
failed while assembling the existing ARM64-only `GOALPadGoalStateWrapper.s`; no
app launched and no runtime probe ran, so it is not ARM64 execution evidence.
The corrected explicit M5 simulator build and run passed. Its final launch PID
was `57206` and logged:

```text
GOALPad runtime probe: Signed ARM64 Jak 1 false-func, true-func, and identity calls verified;
architecture=arm64; result=8194
```

`/private/tmp/GOALPad-stage4-true-func-m5.png` was inspected and shows that
result. The generic signed iOS build also passed; it is build/signing evidence
only, not physical-device validation. The M5 simulator was shut down after the
pass. No state-changing Freemote command was issued, and no physical device was
accessed.

## Verified Jak 1 `lognot` compiler, export, and runtime checkpoint

Reviewed child commit `2475b3c1f097dedb60e5e78a1fc4d88aab5ab052`
(`feat(aot): compile exact Jak 1 lognot function (AI-assisted)`) compiles the
exact full one-argument `int` `lognot` definition from upstream Jak 1
`gcommon.gc` to:

```text
mvn x0, x0
ret
```

Reviewed child commit `9acf4e79751d83626915f03aebcfc738e4d0c242`
(`feat(aot): export exact Jak 1 lognot function (AI-assisted)`) adds the
guarded paired metadata:

```c
OPENGOAL_AOT_EXPORT1("lognot", goalpad_aot_lognot)
```

Parent commit `6697d2d` preserves the compiler patch as
`patches/OpenGOAL/0011-feat-aot-compile-exact-Jak-1-lognot-function-AI-assi.patch`.
Its SHA-256 is
`18339711be9d4bbde58dced7f2f208cdb0799c938052fbbc04023dd47e3ec087`
and its stable patch ID is `d5cb8ecafda681d8583e30f94ec76a4d09213d75`.
Parent commit `fbfa0d5` preserves the Export1 patch as
`patches/OpenGOAL/0012-feat-aot-export-exact-Jak-1-lognot-function-AI-assis.patch`.
Its SHA-256 is
`38f764204543d516dcf1581b5ded2ed9b63618f933ae0aac705f8bc99e7caf56`
and its stable patch ID is
`9088a2d647579868581c7815414f294a6c6e1289`. Parent commit `f7ad14c`
checks the generated pair into GOALPad, registers it beside `identity`, and
calls it through the existing signed X0/X20/X21/X22 boundary.

The generated assembly and header SHA-256 values are respectively
`7d886912f47c51023c09dc168141598b61877bf60eceee16abdd1b84f5a79d34` and
`2f8587a50c6c7d5bc7ff1f07dbd396d6fdcb37e063a05ad2d617fc9a71c55858`.

The constrained compiler/test checkpoint used the actual build directory:

```sh
cmake --build /private/tmp/GOALPadOpenGOAL-stage3-build \
  --target goalc-test goalc-aot gk -j 4

/private/tmp/GOALPadOpenGOAL-stage3-build/goalc/goalc-aot \
  --project-path /private/tmp/GOALPadOpenGOAL-stage2 \
  --input \
  /private/tmp/GOALPadOpenGOAL-stage2/test/goalc/source_templates/arm64-aot/full-lognot-from-jak1-gcommon.gc \
  --function lognot \
  --output /private/tmp/goalpad_aot_lognot.s \
  --exports-output /private/tmp/goalpad_aot_lognot.exports.h \
  --symbol goalpad_aot_lognot

cmp /private/tmp/goalpad_aot_lognot.s \
  GOALPad/Native/Generated/OpenGOALJak1Lognot.s
cmp /private/tmp/goalpad_aot_lognot.exports.h \
  GOALPad/Native/Generated/OpenGOALJak1Lognot.exports.h

/private/tmp/GOALPadOpenGOAL-stage3-build/goalc-test \
  --gtest_filter='Arm64Aot.*:ARM64EmitterLoads.*:ARM64EmitterIntegerMath.*:CodeTester.*:X86EmitterXMM.*:EmitterAVX.*'

/private/tmp/GOALPadOpenGOAL-stage3-build/goalc-test \
  --gtest_filter='-Listener.*'

ctest --test-dir /private/tmp/GOALPadOpenGOAL-stage3-build \
  -R '^goalc-aot-artifact-pair$' --output-on-failure
```

Results: affected targets built; all 34 focused tests, all 720 non-listener
tests, and CTest 1/1 passed. The paired generation and comparison succeeded.
Wrong-symbol and cross-ABI export requests fail atomically without replacing
the existing paired destinations.

Both ARM64 macOS host harnesses exited `0`: the state harness verifies the
static X20/X21/X22 call boundary, and the registry harness resolves `lognot`
only through Export1, passes its ordinary argument in X0, receives the bitwise
complement, and preserves the caller state. The registry command is:

```sh
xcrun --sdk macosx clang++ -std=c++20 -arch arm64 \
  -I GOALPad/Native \
  tests/native/GOALPadAOTExportRegistryHarness.cpp \
  GOALPad/Native/GOALPadAOTExportRegistry.cpp \
  GOALPad/Native/Generated/OpenGOALJak1FalseFunc.s \
  GOALPad/Native/Generated/OpenGOALJak1TrueFunc.s \
  GOALPad/Native/Generated/OpenGOALJak1Identity.s \
  GOALPad/Native/Generated/OpenGOALJak1Lognot.s \
  GOALPad/Native/GOALPadGoalStateWrapper.s \
  -o /private/tmp/goalpad_aot_export_registry_harness

/private/tmp/goalpad_aot_export_registry_harness
```

The following ARM64 macOS app build, dedicated M5 simulator build/run, Debug
generic iOS build, and Release generic iOS build all exited `0`:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/GOALPad-mac -jobs 4 \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug \
  -destination 'id=96C5C21A-B925-4213-82A3-90DCB8518339' \
  -derivedDataPath /private/tmp/GOALPad-sim -jobs 4 build

xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-device -jobs 4 build

xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-device -jobs 4 \
  ENABLE_PREVIEWS=NO ENABLE_DEBUG_DYLIB=NO build
```

The M5 simulator launch PID was `65590` and logged exactly:

```text
GOALPad runtime probe: Signed ARM64 Jak 1 false-func, true-func, identity, and lognot calls verified;
architecture=arm64; result=8194
```

`/private/tmp/GOALPad-stage4-lognot-m5.png` was visually inspected and passed
(1668x2420, SHA-256
`c08f547d040a52cdd42fd137cc7c66e372afe4af26783809e33ee75d2d726f0f`).
The M5 simulator was shut down after validation. No state-changing Freemote
command and no physical-device access occurred.

This is static, normally signed Export1/X0 wrapper execution with synthetic
state. It does not install a live GOAL symbol, execute a surrounding top-level
definition, or enable relocation.

### Debug Preview caveat and verified Release generic iOS layout

The Debug generic iOS build remains limited evidence. Its Preview split bundle
places the AOT entries in `GOALPad.debug.dylib`: `false-func` at `0x4010`,
`identity` at `0x4018`, `lognot` at `0x401c`, and `true-func` at `0x4024`.
Its static call-boundary entries are at `0x44a0`, `0x44f4`, `0x4540`, and
`0x459c`; its SHA-256 is
`38e41c1104a59257f29396b4603637f5a9d9f2709bcc473b0511bf466e9d79e6`.
That dylib has RX `__TEXT` and no executable-memory imports, but the main
Debug stub imports `dlopen`/`dlsym` and contains Preview JIT strings. It is not
release-like no-JIT evidence.

The verified Release generic iOS build used the existing device derived-data
path and explicitly disabled Preview/debug-dylib layout:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-device -jobs 4 \
  ENABLE_PREVIEWS=NO ENABLE_DEBUG_DYLIB=NO build
```

It produced a 216K app bundle containing only a 188,624-byte monolithic ARM64
main executable plus normal bundle metadata, signature, and embedded profile;
there is no `GOALPad.debug.dylib` or `__preview.dylib`. SHA-256 values are:

```text
3a5c94892fa8d71e53f38ba2d98d08f85d171d66cbf415f136a717d220f4d794  GOALPad
ef4a32f9aef6cca1709423e53e66518204e49a86af4d2752139de63d21244ad1  embedded.mobileprovision
```

The Release main contains the AOT entries at `0x100004000` (`false-func`),
`0x100004008` (`identity`), `0x10000400c` (`lognot`), and `0x100004014`
(`true-func`). Its static call-boundary entries are at `0x1000040f0`,
`0x100004144`, `0x100004190`, and `0x1000041ec`. `__TEXT` has `maxprot r-x`
and `initprot r-x`; undefined-import and string scans found no `dlopen`,
`dlsym`, `mmap`, `mprotect`, `pthread_jit_write_protect_np`, Preview, or JIT
markers. The Release embedded profile is unchanged from the paired Debug
output.

Use the supported display command `codesign -d --entitlements -`: both local
Debug and Release outputs show valid application identifier, team identifier,
and `get-task-allow` entitlements, with no JIT entitlement. `codesign -dvv`
displays `Authority=(unavailable)` and
`Info.plist=not bound` for both local outputs; these are display limits, not a
Release-specific signing failure. No `codesign --verify`, installation, or
physical-device execution was performed, so this remains static build/signing
evidence rather than trust, installability, or physical-runtime proof.

## Verified GOALPad targets

The completed Stage 2 boundary was verified through an ARM64 macOS harness,
the macOS app target, the exact simulator, and the signed-device target.

```sh
xcrun --sdk macosx clang -arch arm64 \
  tests/native/GOALPadAOTStateHarness.c \
  GOALPad/Native/Generated/OpenGOALConstant42.s \
  GOALPad/Native/GOALPadGoalStateWrapper.s \
  -o /private/tmp/goalpad_aot_state_harness

/private/tmp/goalpad_aot_state_harness

xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/GOALPad-mac -jobs 4 \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug \
  -destination 'id=96C5C21A-B925-4213-82A3-90DCB8518339' \
  -derivedDataPath /private/tmp/GOALPad-sim -jobs 4 build

xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-device -jobs 4 build
```

All four commands exited `0`. The harness verified distinct synthetic X20,
X21, and X22 values before and after the generated call and verified that the
wrapper restored the caller's three sentinel values. Xcode compiled both
`OpenGOALConstant42.s` and `GOALPadGoalStateWrapper.s`. The generic iOS build
used the existing Apple Development identity and provisioning profile and
completed normal code signing.

The final signed device app's `GOALPad.debug.dylib` contains the generated
entry at `0x4000`, the state wrapper at `0x4010`, and the restoration probe at
`0x4064`. `llvm-objdump` confirms the generated entry remains:

```text
4000: 40 05 80 d2  mov x0, #0x2a
4004: c0 03 5f d6  ret
```

`codesign -dv` also verified the signed bundle identifier
`com.zephyrstudiosllc.GOALPad`. No signing identity or provisioning profile is
stored in the repository.

## iPad Pro M5 simulator validation

The maintainer-created simulator was used instead of touching the physical
iPad:

```text
Name: iPad Pro 11-inch (M5)
Runtime: iOS 26.5
UDID: 96C5C21A-B925-4213-82A3-90DCB8518339
```

The simulator was booted only for this run. The incremental build reused the
existing 151 MB DerivedData directory and exited `0`:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug \
  -destination 'id=96C5C21A-B925-4213-82A3-90DCB8518339' \
  -derivedDataPath /private/tmp/GOALPad-sim -jobs 4 build
```

The final boundary build installed and launched as
`com.zephyrstudiosllc.GOALPad`, producing PID `1067`. A settled screenshot
showed:

```text
Signed ARM64 OpenGOAL AOT call boundary verified
architecture=arm64
result=42
```

Simulator logs independently recorded:

```text
GOALPad runtime probe: Signed ARM64 OpenGOAL AOT call boundary verified;
architecture=arm64; result=42
```

The screenshot is preserved locally as
`/private/tmp/GOALPad-open-goal-state-boundary.png`. Builds used `-jobs 4`, no new
DerivedData tree was created, and the simulator was shut down immediately
after validation. The last resource check showed 72 GB free disk and 41% free
system memory.

This proves the signed static-call boundary on the named simulator. Physical
evidence is recorded separately below.

## Physical iPad status

`xcrun devicectl list devices` sees:

```text
Name: Z iPad Pro
CoreDevice ID: 6A4111AB-1663-508A-98D9-F0C1A9EA7863
UDID: 00008142-000A504C3CC2401C
Model: iPad Pro 11-inch (M5), iPad17,1
OS: iPadOS 26.6 (23G71)
Architecture: arm64e with arm64 support
Developer Mode: enabled
Pairing: available (paired)
```

The compiler-generated Stage 2 app completed a signed generic-device build:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-device -jobs 4 build
```

Result: exit `0`; the app contains the generated ARM64 assembly and was signed
with the existing Apple Development identity and provisioning profile.

Installation also succeeded:

```sh
xcrun devicectl device install app \
  --device 6A4111AB-1663-508A-98D9-F0C1A9EA7863 \
  /private/tmp/GOALPad-device/Build/Products/Debug-iphoneos/GOALPad.app
```

Earlier launch attempts were blocked while the iPad was locked. The final
Stage 2 build was installed after the wrapper change and then launched
normally:

```sh
xcrun devicectl device process launch \
  --device 6A4111AB-1663-508A-98D9-F0C1A9EA7863 \
  --terminate-existing com.zephyrstudiosllc.GOALPad
```

Result at 19:06: exit `0`; `devicectl` reported the application launched.

A ten-second console-attached launch captured:

```text
GOALPad runtime probe: Signed ARM64 OpenGOAL AOT call boundary verified;
architecture=arm64; result=42
```

The command later exited `2` only because the foreground app did not terminate
before the requested ten-second console timeout. The launch and runtime line
preceded the timeout. A final normal launch exited `0` and left the verified
build running on the iPad.

## Confirmed compiler and runtime blockers

At the current Stage 4 artifact-boundary checkpoint:

- The top-level literal `42`, real Jak 1 `'#f` expression, and selected bodies
  of the complete real `false-func`, `true-func`, and one-argument `identity`
  definitions have target-aware ARM64 compiler paths. General functions and
  almost all other ARM64 IR operations remain unsupported and reject
  explicitly.
- A complete `defun` creates a named function plus top-level
  `IR_FunctionAddr`/`IR_SetSymbolValue` installation. The selected text now
  has compiler-generated metadata and app-local lookup, but the installation
  itself remains unexecuted and requires a real static runtime-data model.
- Jak 1 symbols and function pointers use 32-bit offsets from the desktop GOAL
  memory arena. A native Mach-O pointer cannot be placed directly in that
  representation, and the desktop workaround relies on runtime-linked
  executable heap code.
- Function-call clobber metadata is now target-aware and both ARM64 allocator
  paths preserve live values correctly. ARM64 function-call code generation
  itself remains explicitly unimplemented, so call-bearing GOAL source still
  rejects.
- The static entries now execute through ABI-correct X20/X21/X22 boundaries.
  The one-argument wrapper establishes those registers before setting X0; all
  values remain synthetic and never dereferenced. This is not live kernel,
  symbol-table, or GOAL-memory initialization.
- `game/runtime.cpp` allocates the desktop EE region with read, write, and
  execute permissions.
- OpenGOAL v3 objects contain executable payloads that the desktop linker
  copies and patches at runtime; they are not normally signed Mach-O code.
- `_call_goal_asm_arm64` exists and uses X0-X7 arguments, X0 return, and
  X20/X21/X22 for OpenGOAL's process/st/offset-base state, but C++ runtime
  dispatch and Jak 1 trampolines are not a complete ARM64 path.
- The host runtime target is monolithic and carries desktop renderer, window,
  input, audio, listener, and debugging assumptions.

The lower-level ARM64 emitter, target-aware compiler slice, named-function
selection, generated typed export metadata, typed native registry, and static
signed call-boundary paths are real and tested. `true-func` proves the second
zero-argument value shape (X21 plus eight) through a signed static artifact.
`lognot` proves the one-argument integer MVN/RET shape through its typed
Export1 record and signed X0/state wrapper, returning the complement of its
ordinary argument. The Release generic build proves that current linked entries
can reside in a monolithic ARM64 executable without Preview/debug-dylib layout.
None of these checks creates a live GOAL function value, installs a symbol,
executes a top-level definition, or relocates code. Live portable kernel state
remains a later separate boundary.

## Highest-value next checkpoint

1. Define and prove the narrow RW-only OpenGOAL data arena/header required by
   the next real runtime dependency, while keeping executable text static and
   normally signed. Do not add a runtime linker, writable executable memory,
   or general symbol installation as part of that checkpoint.
2. Choose the durable fork owner and authenticate that GitHub account. Publish
   child commit `2475b3c1` with its predecessors, preserve the official
   `upstream` remote, and only then update the parent submodule URL/gitlink to
   the fetchable fork commit.
3. After the static artifact boundaries can initialize a kernel subset, replace
   the synthetic X20/X21/X22 values with portable real process, symbol-table,
   and GOAL-memory state. Keep unsupported compiler paths explicit until a
   real Jak 1 boot dependency requires them.

Physical execution of the false-form, complete-function, true-function,
identity, and lognot checkpoints remains pending. Do not attempt it unless the
maintainer explicitly schedules physical-device testing in the current request.

Do not introduce `MAP_JIT`, writable executable memory, or the desktop V3
runtime-linker path. Do not broaden this into renderer, camera, or future Apple
platform work before the real Jak 1 boot path requires it.

## Next-session commands

```sh
cd /Users/zach/Developer/OS_Projects/GOALPad/GOALPad

git status --short
git log --oneline --decorate -5
git submodule status
git -C OpenGOAL status --short

git submodule update --init --recursive

git -C /private/tmp/GOALPadOpenGOAL-stage2 status --short
git -C /private/tmp/GOALPadOpenGOAL-stage2 log --oneline -4

/private/tmp/GOALPadOpenGOAL-stage3-build/goalc-test \
  --gtest_filter='-Listener.*'

ctest --test-dir /private/tmp/GOALPadOpenGOAL-stage3-build \
  -R '^goalc-aot-artifact-pair$' --output-on-failure
```

Routine Apple runtime validation should use only simulator
`96C5C21A-B925-4213-82A3-90DCB8518339`. It was shut down after the last pass.
Do not run `devicectl` against Z iPad Pro unless the maintainer explicitly asks
for physical testing in that request.

Before making upstream changes, confirm:

- Which GitHub account or organization owns the dedicated OpenGOAL fork.
- That the fork is accessible over the submodule's chosen HTTPS/SSH path.
- That the parent `zschwendi/GOALPad` remote is accessible for checkpoint
  publication.

If the isolated worktree is unavailable, restore the exact child change from
the parent repository without moving the official submodule pin:

```sh
git -C OpenGOAL worktree add -b goalpad/arm64-aot-proof \
  /private/tmp/GOALPadOpenGOAL-stage2 \
  a4cb1ac1f0596c8740b1c26accb24a58505cda92

git -C /private/tmp/GOALPadOpenGOAL-stage2 am \
  "$PWD/patches/OpenGOAL/0001-Add-minimal-ARM64-GOAL-AOT-proof-AI-assisted.patch"

git -C /private/tmp/GOALPadOpenGOAL-stage2 am \
  "$PWD/patches/OpenGOAL/0002-Make-function-call-clobbers-target-aware-AI-assisted.patch"

git -C /private/tmp/GOALPadOpenGOAL-stage2 am \
  "$PWD/patches/OpenGOAL/0003-Compile-Jak-1-false-form-for-ARM64-AI-assisted.patch"

git -C /private/tmp/GOALPadOpenGOAL-stage2 am \
  "$PWD/patches/OpenGOAL/0004-Compile-full-Jak-1-false-function-for-ARM64-AOT-AI-assisted.patch"

git -C /private/tmp/GOALPadOpenGOAL-stage2 am \
  "$PWD/patches/OpenGOAL/0005-Constrain-named-ARM64-AOT-function-selection-AI-assi.patch"

git -C /private/tmp/GOALPadOpenGOAL-stage2 am \
  "$PWD/patches/OpenGOAL/0006-Emit-atomic-signed-ARM64-export-metadata-AI-assisted.patch"

git -C /private/tmp/GOALPadOpenGOAL-stage2 am \
  "$PWD/patches/OpenGOAL/0007-feat-aot-compile-exact-Jak-1-identity-function-AI-as.patch"

git -C /private/tmp/GOALPadOpenGOAL-stage2 am \
  "$PWD/patches/OpenGOAL/0008-feat-aot-add-typed-identity-export-metadata-AI-assis.patch"

git -C /private/tmp/GOALPadOpenGOAL-stage2 am \
  "$PWD/patches/OpenGOAL/0009-feat-aot-compile-exact-Jak-1-true-function-AI-assist.patch"

git -C /private/tmp/GOALPadOpenGOAL-stage2 am \
  "$PWD/patches/OpenGOAL/0010-feat-aot-export-exact-Jak-1-true-function-AI-assiste.patch"

git -C /private/tmp/GOALPadOpenGOAL-stage2 am \
  "$PWD/patches/OpenGOAL/0011-feat-aot-compile-exact-Jak-1-lognot-function-AI-assi.patch"

git -C /private/tmp/GOALPadOpenGOAL-stage2 am \
  "$PWD/patches/OpenGOAL/0012-feat-aot-export-exact-Jak-1-lognot-function-AI-assis.patch"
```

`git am` reconstructs patch-equivalent commits but normally produces different
SHAs because committer metadata changes. `79f22008`, `149840cf`, `32cf26ae`,
`92c8f975`, `b78d7c28`, `1fc20e79`, `25917e27`, `1c80b667`, `35d653f1`,
`f979c82c`, `2475b3c1`, and `9acf4e79` are the exact original child commits in
the current isolated worktree; compare content and patch identity when
reconstructing them elsewhere.

This pre-checkpoint instruction is superseded by Checkpoint 5 below. The
narrow RW-only OpenGOAL data-arena/header proof was completed without retail
data or physical-device access; its next seam and remaining publication gate
are recorded there.

## Checkpoint 5: portable Jak 1 data-arena header

Parent checkpoint `c201ea8a3d09934d155cb4cadca7c4ef9ad563d2` preserves the
first three unpublished OpenGOAL data-arena children; descendant parent
checkpoint `a2f41c772073ee77564272cb65ed92522305c42a` preserves the fourth.
The official submodule remains pinned at
`a4cb1ac1f0596c8740b1c26accb24a58505cda92` and was not moved.

| Order | Child commit | Patch | SHA-256 | Stable patch ID | Preserved by parent |
| --- | --- | --- | --- | --- | --- |
| 0013 | `5c5368598bf808e5e8a8494679360601d42c02b4` | `0013-feat-kernel-add-portable-Jak-1-data-arena-header-pro.patch` | `60bd2a50bcac0d34bbd60913e583208f4b635cafac3a4e6303e6832015ec9602` | `9e8159a68654a4568220ea94cb36e51622a77ab3` | `c201ea8` |
| 0014 | `b094144b27af99abd2e3b6809e8f58f93d0fb15a` | `0014-fix-build-preserve-Apple-SDK-selections-for-host-tes.patch` | `5c28722688323eba798552f6bcae10779db4152481fbe4bf57f2efaf5c549f9b` | `b47e3ae39b93f47be4fa8465a5c684b4130919d9` | `c201ea8` |
| 0015 | `5495181f304bb63b49a82e9067d59fd27a5dd6c8` | `0015-fix-kernel-preserve-canonical-Jak-1-data-arena-bound.patch` | `ed0aba2b7d717f5a2a93099f5264bb1fc567b15c5bfd62f574e87917fbeba92b` | `1ab6fb92d40e3cc5b4e949df8e5d12da55b482d9` | `c201ea8` |
| 0016 | `5ad2efa3dac3febe642370aec39629b17039ead9` | `0016-build-ios-add-portable-Jak-1-data-arena-target-AI-as.patch` | `723ec9c96638233330b7358934b0c67a11f87ccbf00efc1e4fab866bc3b9c762` | `b0a0d2bc563b653412f75bb705edb935caa95118` | `a2f41c7` |

Apply 0013, then 0014, then 0015, then 0016 after the existing 0001 through
0012 series. Patch 0013 introduces the source, static library, and test; 0014
changes the test registration to preserve a caller-selected Apple SDK and
avoid host-side discovery of a cross-compiled executable; 0015 corrects
0013's arena bounds; and 0016 factors that exact library definition into a
minimal portable target mode. Do not preserve, apply, or publish a partial or
reordered suffix.

```sh
git -C /private/tmp/GOALPadOpenGOAL-stage2 am \
  "$PWD/patches/OpenGOAL/0013-feat-kernel-add-portable-Jak-1-data-arena-header-pro.patch"
git -C /private/tmp/GOALPadOpenGOAL-stage2 am \
  "$PWD/patches/OpenGOAL/0014-fix-build-preserve-Apple-SDK-selections-for-host-tes.patch"
git -C /private/tmp/GOALPadOpenGOAL-stage2 am \
  "$PWD/patches/OpenGOAL/0015-fix-kernel-preserve-canonical-Jak-1-data-arena-bound.patch"
git -C /private/tmp/GOALPadOpenGOAL-stage2 am \
  "$PWD/patches/OpenGOAL/0016-build-ios-add-portable-Jak-1-data-arena-target-AI-as.patch"
```

### Delegation and review

Four non-overlapping lanes produced this checkpoint:

- `arm64_next_seam` implemented and validated the portable data-arena proof
  and its 0016 minimal-CMake follow-up in its dedicated OpenGOAL worktree.
- `arm64_codegen` reviewed heap semantics, CMake behavior, and patch-series
  preservation.
- `false_func_failure` performed independent regression, documentation, and
  fork/reproducibility audits.
- The root agent serialized the broad runtime retry, patch reconstruction, and
  parent integration, preserving memory headroom and avoiding conflicting
  worktree edits.

The final `arm64_codegen` and `false_func_failure` reviews were clean after
the canonical-bounds and host-test-gate fixes in 0014/0015, and both
independently approved `5ad2efa3`. `false_func_failure` audited the resulting
cache, target graph, normal-mode target equivalence, archive, and tests-on
rejection. The reviews found no preservation-blocking source fix: the minimal
target has one source object and no desktop, JIT, or OpenGOAL-global
dependency. The root agent preserved 0016 as `a2f41c7`. The earlier full
iPhoneOS CMake/OpenSSL stop and broad-runtime permission failure remain
historical limits for the full graph, not passing evidence or source
regressions.

### Implemented data-only boundary

`initialize_data_arena_header` initializes caller-owned, zero-based GOAL
storage. It requires at least `GLOBAL_HEAP_END = 0x03eb82e0` bytes, clears only
`[storage, storage + GLOBAL_HEAP_END)`, and leaves any tail untouched. The
verified Jak 1 header values are:

```text
global heap record: 0x13ad00
base:               0x13fd20
current:            0x17fd20
top / top-base:     0x03eb82e0
symbol table:       [0x13fd20, 0x17fd20)
SymbolTable2:       0x13fd24
LastSymbol:         0x15fc20
s7:                 0x14fd24
#f / #t:            s7 / s7 + 8
```

This is not live OpenGOAL runtime initialization. It does not bind storage to
`g_ee_main_mem`, initialize `kglobalheap` or native `s7`, `SymbolTable2`,
`LastSymbol`, or `NumSymbols` globals, create types, native trampolines, or
GOAL functions, link game data, or execute GOAL code. It has no renderer,
presentation, lifecycle, camera, or platform-view coupling.

### Validation ledger

The host configuration and focused target builds below exited `0`:

```sh
cmake -S /private/tmp/GOALPadOpenGOAL-data-arena-corrections \
  -B /private/tmp/GOALPadOpenGOAL-data-arena-corrections-build \
  -G Ninja -DCMAKE_BUILD_TYPE=Release

cmake --build /private/tmp/GOALPadOpenGOAL-data-arena-corrections-build \
  --target jak1-data-arena-test --parallel 4

ninja -C /private/tmp/GOALPadOpenGOAL-data-arena-corrections-build \
  goalc-test goalc-aot jak1-data-arena-test -j4
```

```sh
ctest --test-dir /private/tmp/GOALPadOpenGOAL-data-arena-corrections-build \
  -R '^Jak1DataArena\.' --output-on-failure

/private/tmp/GOALPadOpenGOAL-data-arena-corrections-build/goalc-test \
  --gtest_filter='Arm64Aot.*:ARM64EmitterLoads.*:ARM64EmitterIntegerMath.*:CodeTester.*:X86EmitterXMM.*:EmitterAVX.*'

ctest --test-dir /private/tmp/GOALPadOpenGOAL-data-arena-corrections-build \
  --output-on-failure
```

Results: focused data-arena CTest 4/4 passed; pure compiler filter 122/122
passed; full CTest 5/5 passed, including `goalc-aot-artifact-pair`.

The source compiled directly for iPhoneOS ARM64 without a desktop runtime:

```sh
goalpad_iphoneos_sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos clang++ -std=c++20 -arch arm64 \
  -miphoneos-version-min=18.0 -isysroot "$goalpad_iphoneos_sdk" -I. \
  -c game/kernel/jak1/data_arena.cpp \
  -o /private/tmp/goalpad_jak1_data_arena_corrections_iphoneos.o
```

Result: exit `0`; `otool` reported an 1848-byte `MH_MAGIC_64 ARM64` object.

The tests-off configure (`-DBUILD_TESTING=OFF`) exited `0`, and its target-list
check confirmed that `jak1-data-arena-test` was not registered. An iPhoneOS
CMake configure with `CMAKE_SYSTEM_NAME=iOS`, `CMAKE_OSX_SYSROOT=iphoneos`,
`CMAKE_OSX_ARCHITECTURES=arm64`, `CMAKE_OSX_DEPLOYMENT_TARGET=18.0`, and
`BUILD_TESTING=ON` retained the iPhoneOS sysroot, then stopped at curl's first
missing OpenSSL dependency. It generated no `build.ninja`; do not claim an
iPhoneOS CMake library, target-gate, app, simulator, or device result from
this checkpoint.

The broad desktop runtime suite is also unvalidated: its inherited
main-memory mapping reported `Permission denied`; an escalated retry reached
the 1538-test suite and then `Jak1KernelTest`, where the same error recurred.
It was stopped with Ctrl-C (exit 130), not passed.

### Verified minimal iPhoneOS data-arena target

Child `5ad2efa3` introduces the deliberately narrow, portable
`OPENGOAL_BUILD_JAK1_DATA_ARENA_ONLY` CMake mode. It is a static-library mode,
not an iPad application or runtime target. The option is enabled only after
the top-level C/C++ project is declared and before CTest, desktop compiler
flags, Apple Objective-C enablement, third-party dependencies, game runtime,
and compiler tools. It includes the same `jak1-data-arena` target definition
used in normal game mode, then returns from the top-level CMake file.

The top-level project still performs normal C and C++ compiler detection before
the early return. That is configuration work, not an archive dependency: the
generated archive has no C object. The project declares CMake 3.10 and uses
only the established no-argument top-level `return()` form, but the recorded
configuration was CMake 4.4.1; do not describe this as a CMake 3.10 execution
result.

The following CMake 4.4.1 commands exited `0`; use `-j 4` or less to preserve
memory headroom:

```sh
cmake -S /private/tmp/GOALPadOpenGOAL-ios-data-arena \
  -B /private/tmp/GOALPadOpenGOAL-ios-data-arena-iphoneos-minimal-build \
  -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 \
  -DOPENGOAL_BUILD_JAK1_DATA_ARENA_ONLY=ON -DBUILD_TESTING=OFF

cmake --build /private/tmp/GOALPadOpenGOAL-ios-data-arena-iphoneos-minimal-build \
  --target jak1-data-arena -j 4

cmake -S /private/tmp/GOALPadOpenGOAL-ios-data-arena \
  -B /private/tmp/GOALPadOpenGOAL-ios-data-arena-host-minimal-build \
  -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DOPENGOAL_BUILD_JAK1_DATA_ARENA_ONLY=ON -DBUILD_TESTING=OFF

cmake --build /private/tmp/GOALPadOpenGOAL-ios-data-arena-host-minimal-build \
  --target jak1-data-arena -j 4

cmake -S /private/tmp/GOALPadOpenGOAL-ios-data-arena \
  -B /private/tmp/GOALPadOpenGOAL-ios-data-arena-host-normal-build \
  -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DOPENGOAL_BUILD_JAK1_DATA_ARENA_ONLY=OFF

cmake --build /private/tmp/GOALPadOpenGOAL-ios-data-arena-host-normal-build \
  --target jak1-data-arena-test goalc-test goalc-aot -j 4

ctest --test-dir /private/tmp/GOALPadOpenGOAL-ios-data-arena-host-normal-build \
  -R '^Jak1DataArena\\.' --output-on-failure

/private/tmp/GOALPadOpenGOAL-ios-data-arena-host-normal-build/goalc-test \
  --gtest_filter='Arm64Aot.*:ARM64EmitterLoads.*:ARM64EmitterIntegerMath.*:CodeTester.*:X86EmitterXMM.*:EmitterAVX.*'

ctest --test-dir /private/tmp/GOALPadOpenGOAL-ios-data-arena-host-normal-build \
  --output-on-failure
```

The normal host regression passed the data-arena CTest 4/4, pure compiler
filter 122/122, and full CTest 5/5. The normal target retains its name, source,
static output, and no link dependencies. Its factored definition explicitly
publishes the repository root include path and C++20 usage requirement; this
is equivalent to the normal graph's global C++20/root include setup, but is
not a claim of byte-for-byte identical generated metadata.

For the iPhoneOS minimal build, `CMakeCache.txt` records
`CMAKE_SYSTEM_NAME=iOS`, `CMAKE_OSX_SYSROOT=iphoneos`,
`CMAKE_OSX_ARCHITECTURES=arm64`, `CMAKE_OSX_DEPLOYMENT_TARGET=18.0`, and
`OPENGOAL_BUILD_JAK1_DATA_ARENA_ONLY=ON`. CMake's compiler metadata records
AppleClang and arm64. The generated compile rule is exactly scoped to
`game/kernel/jak1/data_arena.cpp` with:

```text
-O3 -DNDEBUG -std=gnu++20 -arch arm64
-isysroot .../iPhoneOS26.5.sdk -miphoneos-version-min=18.0
```

`ninja -t targets all` lists only `jak1-data-arena` and CMake utility targets;
it contains no curl, OpenSSL, SDL, runtime, goalc, gk, or gtest target. The
archive `libjak1-data-arena.a` contains only `data_arena.cpp.o`; `lipo -info`
reports arm64, its object has `LC_BUILD_VERSION` platform `IOS`, minimum 18.0,
SDK 26.5, and `nm -um` reports only `_bzero`. This proves the generated static
archive and its target graph do not pull an OpenGOAL runtime, desktop library,
JIT path, or project global. `_bzero` is an ordinary system C-library symbol
to be resolved by a final iOS executable; the archive alone does not prove a
future application's complete link closure.

Testing is intentionally unavailable in minimal mode. This expected command
fails at configuration with
`OPENGOAL_BUILD_JAK1_DATA_ARENA_ONLY requires BUILD_TESTING=OFF.` and creates
no `build.ninja` or archive:

```sh
cmake -S /private/tmp/GOALPadOpenGOAL-ios-data-arena \
  -B /private/tmp/GOALPadOpenGOAL-ios-data-arena-testing-rejected-build \
  -G Ninja -DOPENGOAL_BUILD_JAK1_DATA_ARENA_ONLY=ON -DBUILD_TESTING=ON
```

The rejection directory may still contain `CMakeCache.txt`; that is not target
generation. Because minimal mode returns before `include(CTest)`, an unset
`BUILD_TESTING` value is also treated as off; the documented commands pin it
to `OFF` and the mode rejects an explicit `ON`. A shell `test -e
.../build.ninja` returning status `1` is the expected absence check, not a
source failure. CMake's compiler-ABI probe also printed `clang++: warning:
-Wl,-v: 'linker' input unused`; it is a toolchain probe diagnostic, not an
archive-source warning. Verify the recorded 0016 digest against the stored
patch file, not a regenerated differently formatted `format-patch --stdout
--full-index --binary` stream.

This checkpoint makes no simulator, device, application, signing, runtime,
GOAL-execution, live-global, or physical-iPad claim. It does not satisfy the
Stage 5 runtime-initialization exit gate.

No application, simulator, generic-device, or physical-device validation ran
for this data-only proof. Do not access **Z iPad Pro** unless the maintainer
explicitly requests physical-device testing in the current task.

### Current integration and publication gate

The Darwin/macOS ARM64 host generated-artifact call-context seam is now
preserved as Checkpoint 7 below. It links four build-generated Jak 1 entries
through the production assembly dispatcher with an initialized synthetic arena,
but the current entries use only X21/X0 and do not dereference X22. Keep it as
a host regression guard while the next dependency is selected by post-0018
audit. Do not bind desktop globals, install a live GOAL symbol, add executable
memory, use the desktop runtime linker, or start a renderer/camera/platform-
abstraction effort.

Durable parent integration is blocked until a maintainer chooses a fetchable,
pinned OpenGOAL fork and its owner, visibility/access policy, and HTTPS/SSH
transport. The local GitHub CLI configuration contains `zschwendi` (active)
and `zephyrstudiosllc` (inactive), but both credentials are invalid. Do not
authenticate, create a fork, change `.gitmodules`, move the submodule gitlink,
or publish without that direction. The official source must remain `upstream`;
the fork must be published and fresh-clone verified before the parent points to
an immutable fork commit.

At this checkpoint, the parent history is:

```text
3cb4e16 test(opengoal): preserve generated Jak 1 AOT execution proof (AI-assisted)
0c0395e build(opengoal): preserve ARM64 GOAL call ABI proof (AI-assisted)
1980e2f docs: clarify data-arena proof handoff (AI-assisted)
7f4a013 docs: record minimal iPhoneOS data-arena proof (AI-assisted)
a2f41c7 build(opengoal): preserve iPhoneOS data-arena target (AI-assisted)
98880fd docs: clarify data-arena checkpoint progress (AI-assisted)
2dee378 docs: record data-arena checkpoint (AI-assisted)
c201ea8 Preserve Jak 1 data-arena correction series (AI-assisted)
c95b07a docs: correct lognot generator path (AI-assisted)
df6057d docs: record signed lognot runtime checkpoint (AI-assisted)
f7ad14c feat(aot): bind exact Jak 1 lognot export (AI-assisted)
```

`origin` remains configured as `https://github.com/zschwendi/GOALPad.git`.
Publication is blocked by the unverified destination/fork decision and invalid
local GitHub credentials; no push was attempted for `a2f41c7`, `0c0395e`,
`3cb4e16`, or the current documentation checkpoints. Preserve the platform
boundaries above so later Mac, iPhone, multiple-view, stereo, externally
supplied projection, and visionOS presentation work remain possible without
delaying the iPad Jak 1 boot path.

## Checkpoint 6: host ARM64 GOAL call ABI

Parent checkpoint `0c0395ee1281b5fc4eaa2f58e630e907684a4af9` preserves the
corrected child patch after data-arena parent `5ad2efa3dac3febe642370aec39629b17039ead9`.
The official submodule remains pinned at
`a4cb1ac1f0596c8740b1c26accb24a58505cda92` and was not moved.

| Child commit | Patch | Stored SHA-256 | Stable patch ID | Preserved by parent |
| --- | --- | --- | --- | --- |
| `45e1897f7cd560e4951f515e264078a023a2d08c` | `0017-fix-arm64-verify-GOAL-call-context-ABI-AI-assisted.patch` | `7013f6b23da8e4d9f223b97062b4ca6d8a55cf65255849e901aa74d49bdac89d` | `62a4273278f231fc05c30e657cce9867286e777d` | `0c0395ee1281b5fc4eaa2f58e630e907684a4af9` |

Patch 0017 must follow the ordered 0013-0016 data-arena unit; it is not part
of that unit and does not expand its iPhoneOS static-library claim. The parent
contains the saved mbox (whose `From` header is the corrected child ID), rather
than the child Git object. Verify the recorded digest against the saved patch,
not a regenerated `format-patch` stream:

```sh
shasum -a 256 \
  patches/OpenGOAL/0017-fix-arm64-verify-GOAL-call-context-ABI-AI-assisted.patch
git patch-id --stable < \
  patches/OpenGOAL/0017-fix-arm64-verify-GOAL-call-context-ABI-AI-assisted.patch
```

The outputs are the stored SHA-256 above and
`62a4273278f231fc05c30e657cce9867286e777d 45e1897f7cd560e4951f515e264078a023a2d08c`.

### Scope and claim boundary

The source change selects the existing `call_goal_asm_arm64` helper from
`call_goal` only on `__APPLE__ && __aarch64__`. Its macOS ARM64 host-test gate
explicitly enables ASM and builds one static probe from C++, test assembly, and
the existing `asm_funcs_arm64.s`. The probe verifies X0/X1/X2 argument mapping;
X20 = X21 = synthetic `st`; X22 = a synthetic arena pointer; 16-byte stack
alignment; X0 result propagation; restoration of caller X20/X21/X22 sentinels;
and a false-like static entry returning X21. The probe calls the production
assembly dispatcher directly. The C++ `call_goal` selection is compile/link
evidence only; `call_goal_on_stack` is unchanged and untested.

This is host ABI evidence only. `arm64-goal-call-abi-test` does not link the
OpenGOAL runtime or CodeTester and does not execute compiler-produced GOAL
code. It does not bind the data arena to `g_ee_main_mem`, initialize kernel or
symbol globals, load user data, create a live GOAL symbol, establish a runtime,
or provide an iPhoneOS, app, signing, simulator, physical-device, or normally
signed executable-GOAL result. The separately run host compiler filter includes
pre-existing `CodeTester.*` coverage; that is neither a dependency of this
target nor iPad/JIT evidence.

### Recorded host validation

The final fresh configuration deliberately used no
`CMAKE_ASM_COMPILE_OBJECT` override. A prior configuration reported that
internal variable as missing; adding `enable_language(ASM)` inside the Apple
ARM64 host-test gate corrected the source registration. The following
configuration, build, and tests exited `0`:

```sh
cmake --log-level=NOTICE \
  -S /private/tmp/GOALPadOpenGOAL-arm64-goal-call \
  -B /private/tmp/GOALPadOpenGOAL-arm64-goal-call-host-final-build \
  -G Ninja -DCMAKE_BUILD_TYPE=Release

/opt/homebrew/bin/ninja \
  -C /private/tmp/GOALPadOpenGOAL-arm64-goal-call-host-final-build \
  -j 4 \
  runtime arm64-goal-call-abi-test jak1-data-arena-test goalc-test goalc-aot

ctest --test-dir /private/tmp/GOALPadOpenGOAL-arm64-goal-call-host-final-build \
  -R '^Arm64GoalCallAbi\.' --output-on-failure

ctest --test-dir /private/tmp/GOALPadOpenGOAL-arm64-goal-call-host-final-build \
  -R '^Jak1DataArena\.' --output-on-failure

cd /private/tmp/GOALPadOpenGOAL-arm64-goal-call-host-final-build
./goalc-test '--gtest_filter=Arm64Aot.*:ARM64EmitterLoads.*:ARM64EmitterIntegerMath.*:CodeTester.*:X86EmitterXMM.*:EmitterAVX.*'

ctest --test-dir /private/tmp/GOALPadOpenGOAL-arm64-goal-call-host-final-build \
  --output-on-failure
```

Results: the ABI CTest passed 2/2, the data-arena CTest passed 4/4, the host
compiler filter passed 122/122 (with its usual `cpuid not implemented on
platform` warnings), and the complete CTest set passed 7/7. Link/symbol
inspection reported an ARM64 Mach-O probe whose `_call_goal_asm_arm64` comes
from its directly linked `asm_funcs_arm64.s` object. Separately, in the normal
runtime graph, `kscheme.cpp.o` references and `libruntime.a` defines the same
symbol; the probe does not link `libruntime.a`.

### Disposable-build incident and process recovery

The first disposable final-build `data` symlink pointed to a nonexistent
`.../data` directory, so the separately invoked `goalc-test` reported
`Failed to initialize project path` and asserted
`g_file_path_info.initialized`. Only the disposable build-directory link was
corrected to the child worktree root; source, parent data, and user assets were
not changed. The succeeding 122/122 compiler-filter result is the valid result.

During the same tooling incident, foreground CMake-wrapper PIDs `1293`,
`2604`, `3767`, `4841`, `5935`, `7195`, `90436`, `91531`, `93215`, `94086`,
`95051`, `96187`, `97294`, `98520`, and `99523`, plus orphan Ninja-supervisor
PIDs `7207`, `94100`, and `96198`, were terminated after process inspection.
A final matching-process count was `0`. This was disposable `/private/tmp`
process recovery, not build or product-validation evidence.

No simulator, generic iOS build, signing, device, physical hardware, remote,
or push was used for this checkpoint. **Z iPad Pro** was not accessed.

### Historical next task and blocker

The generated-artifact seam described here is completed by Checkpoint 7 below.
The fork publication blocker remains: a maintainer must choose and publish a
dedicated, fetchable, pinned OpenGOAL fork before durable parent integration.
At that point restore 0013-0018 in order and retain the ABI probes as macOS
regression guards. The fork choice remains blocked on maintainer direction for
owner, visibility/access policy, and HTTPS/SSH transport; current local GitHub
credentials are invalid. Do not change `.gitmodules`, move the official
submodule gitlink, authenticate, create the fork, or push without that
direction.

## Checkpoint 7: generated host Jak 1 AOT call context

Parent checkpoint `3cb4e16fec1f7aadd23ae566b8fb6749b80056d9` preserves child
`bd3f4752cea18e73fb1e5cbaec3efdd89ec38195` after parent
`45e1897f7cd560e4951f515e264078a023a2d08c`. The official submodule remains
pinned at `a4cb1ac1f0596c8740b1c26accb24a58505cda92` and was not moved.

| Child commit | Patch | Stored SHA-256 | Stable patch ID | Preserved by parent |
| --- | --- | --- | --- | --- |
| `bd3f4752cea18e73fb1e5cbaec3efdd89ec38195` | `0018-test-arm64-execute-generated-Jak-1-AOT-artifacts-AI-.patch` | `bb413a73853d568ba848085735bc5817238ab1287fb16c393d24dd5bdb261fdb` | `edb9c6aa2a99d32b1d6932e8b4f6b90abe27ddfb` | `3cb4e16fec1f7aadd23ae566b8fb6749b80056d9` |

Patch 0018 must follow 0017, which follows the ordered 0013-0016 data-arena
unit. It extends only the macOS ARM64 host proof. As with 0017, the parent
preserves the saved mbox rather than the child Git object. Verify the stored
artifact rather than a regenerated patch stream:

```sh
shasum -a 256 \
  patches/OpenGOAL/0018-test-arm64-execute-generated-Jak-1-AOT-artifacts-AI-.patch
git patch-id --stable < \
  patches/OpenGOAL/0018-test-arm64-execute-generated-Jak-1-AOT-artifacts-AI-.patch
```

The outputs are the recorded SHA-256 above and
`edb9c6aa2a99d32b1d6932e8b4f6b90abe27ddfb bd3f4752cea18e73fb1e5cbaec3efdd89ec38195`.

### Scope and claim boundary

Within the existing Apple ARM64 host-test gate, 0018 adds one CMake custom
command with four sequential `goalc-aot` invocations. It emits four assembly
files and four X-macro export headers for `false-func`, `true-func`, `identity`,
and `lognot`; explicit outputs, template inputs, and the `goalc-aot` target
preserve incremental freshness. The ABI test depends on those outputs, compiles
the generated assembly directly, and links only `jak1-data-arena`, GoogleTest,
the test probe, and existing `asm_funcs_arm64.s`—not `libruntime.a`.

The test initializes one local caller-owned data arena (about 62.7 MiB), sets
X20 = X21 = `s7` and X22 = its base pointer, then branches directly through the
production assembly dispatcher to the generated entries. It verifies false =
X21, true = X21 + 8, identity = X0, lognot = `~X0`, and restoration of caller
X20/X21/X22 sentinels. Generated export headers are included as typed X-macro
declarations and tables, making metadata/symbol drift a compile failure.

The four generated instruction streams use X21/X0 only: none dereferences X22
or reads arena memory. The C++ `call_goal` runtime dispatcher is not called;
`call_goal_on_stack` remains untested. Therefore this is not proof of
X22-relative addressing, initialized arena contents, data-memory loads,
runtime/global initialization, JIT, C++ runtime dispatch, iPhoneOS, app,
signing, simulator, physical device, or normally signed executable-GOAL
behavior.

### Validation, graph, and artifacts

The final affected build, including the tool used by the custom command,
exited `0`:

```sh
cmake --build /private/tmp/GOALPadOpenGOAL-arm64-goal-call-host-final-build \
  --target runtime arm64-goal-call-abi-test jak1-data-arena-test goalc-test goalc-aot \
  -j 4

ctest --test-dir /private/tmp/GOALPadOpenGOAL-arm64-goal-call-host-final-build \
  -R '^Arm64GoalCallAbi\.' --output-on-failure

ctest --test-dir /private/tmp/GOALPadOpenGOAL-arm64-goal-call-host-final-build \
  -R '^Jak1DataArena\.' --output-on-failure

cd /private/tmp/GOALPadOpenGOAL-arm64-goal-call-host-final-build
./goalc-test '--gtest_filter=Arm64Aot.*:ARM64EmitterLoads.*:ARM64EmitterIntegerMath.*:CodeTester.*:X86EmitterXMM.*:EmitterAVX.*'

ctest --test-dir /private/tmp/GOALPadOpenGOAL-arm64-goal-call-host-final-build \
  --output-on-failure
```

The build completed 200 remaining curl/SDL/imgui and `goalc-test` steps; one
duplicate-zstd linker warning did not prevent its `0` exit. ABI CTest passed
3/3, data-arena CTest 4/4, the existing compiler filter 122/122, and full CTest
8/8. All three discovered ABI tests are `RUN_SERIAL`, intentionally preventing
the local 62.7 MiB arena test from competing with other CTest processes.

Ninja graph inspection confirmed
`goalc-aot -> arm64-goal-call-aot-artifacts -> arm64-goal-call-abi-test`, with
the eight generated files also object-order dependencies. The test executable
defines `_call_goal_asm_arm64`, `_call_goal_on_stack_asm_arm64`, and all four
generated `_goalpad_aot_*` symbols from directly linked assembly. Its imports
contain no `mmap`, `mprotect`, `g_ee_main_mem`, or `call_goal*` symbol. Its
dynamic dependencies are GoogleTest, libc++, and libSystem only.

Direct iPhoneOS object/archive compatibility also passed in
`/private/tmp/goalpad-ios-aot-context.RbzOUa`: `asm_funcs_arm64.s`, the four
fresh host-generated `.s` files, and the verified iPhoneOS `data_arena.o` were
compiled or reused, archived, and ranlib'd. The result is arm64. The inspected
dispatcher, false-function, and data-arena objects report `LC_BUILD_VERSION`
platform iOS/minimum 18.0 (the assembly objects have no SDK field and
`data_arena.o` reports SDK 26.5). It defines `initialize_data_arena_header`,
`call_goal_asm_arm64`, and all four `goalpad_aot_*` symbols, with only `_bzero`
undefined from the data-arena object. This is static object/archive evidence,
not an executable/app link, signing, simulator, device, or runtime-execution
result.

Run from the 0018 child worktree, the exact direct proof was:

```sh
ios_proof_dir=$(mktemp -d /private/tmp/goalpad-ios-aot-context.XXXXXX) &&
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=18.0 \
  -c game/kernel/asm_funcs_arm64.s -o "$ios_proof_dir/asm_funcs_arm64.o" &&
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=18.0 \
  -c /private/tmp/GOALPadOpenGOAL-arm64-goal-call-host-final-build/generated-arm64-goal-call/OpenGOALJak1FalseFunc.s \
  -o "$ios_proof_dir/OpenGOALJak1FalseFunc.o" &&
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=18.0 \
  -c /private/tmp/GOALPadOpenGOAL-arm64-goal-call-host-final-build/generated-arm64-goal-call/OpenGOALJak1TrueFunc.s \
  -o "$ios_proof_dir/OpenGOALJak1TrueFunc.o" &&
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=18.0 \
  -c /private/tmp/GOALPadOpenGOAL-arm64-goal-call-host-final-build/generated-arm64-goal-call/OpenGOALJak1Identity.s \
  -o "$ios_proof_dir/OpenGOALJak1Identity.o" &&
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=18.0 \
  -c /private/tmp/GOALPadOpenGOAL-arm64-goal-call-host-final-build/generated-arm64-goal-call/OpenGOALJak1Lognot.s \
  -o "$ios_proof_dir/OpenGOALJak1Lognot.o" &&
cp /private/tmp/GOALPadOpenGOAL-arm64-goal-call-iphoneos-0018-build/CMakeFiles/jak1-data-arena.dir/game/kernel/jak1/data_arena.cpp.o \
  "$ios_proof_dir/data_arena.o" &&
xcrun ar qc "$ios_proof_dir/libopengoal-jak1-aot-context-ios.a" \
  "$ios_proof_dir/data_arena.o" "$ios_proof_dir/asm_funcs_arm64.o" \
  "$ios_proof_dir/OpenGOALJak1FalseFunc.o" "$ios_proof_dir/OpenGOALJak1TrueFunc.o" \
  "$ios_proof_dir/OpenGOALJak1Identity.o" "$ios_proof_dir/OpenGOALJak1Lognot.o" &&
xcrun ranlib "$ios_proof_dir/libopengoal-jak1-aot-context-ios.a"
```

The actual directory was `/private/tmp/goalpad-ios-aot-context.RbzOUa`. The
following inspection commands all exited `0`:

```sh
lipo -info "$ios_proof_dir/libopengoal-jak1-aot-context-ios.a"
xcrun vtool -show-build "$ios_proof_dir/asm_funcs_arm64.o"
xcrun vtool -show-build "$ios_proof_dir/OpenGOALJak1FalseFunc.o"
xcrun vtool -show-build "$ios_proof_dir/data_arena.o"
nm -gU "$ios_proof_dir/libopengoal-jak1-aot-context-ios.a" | \
  rg 'call_goal_asm_arm64|goalpad_aot_|initialize_data_arena_header'
nm -um "$ios_proof_dir/libopengoal-jak1-aot-context-ios.a"
```

| Generated artifact | SHA-256 |
| --- | --- |
| `OpenGOALJak1FalseFunc.s` | `22b670ac4b318a43a8e3e049b9d576b3ad1a8292d0df3f52397d1156cca8c450` |
| `OpenGOALJak1FalseFunc.exports.h` | `abb26d05d717d87d4a4a93fc11bd269082ba672b2fdd16d192f68667025f79ce` |
| `OpenGOALJak1TrueFunc.s` | `dcccaaa13f07aced806cfac3a210ecd6a8b43268024fa1cf5da634f01384ff87` |
| `OpenGOALJak1TrueFunc.exports.h` | `9fbe7cf54992385ad6c91bad9433cd716d0379bbbb424600cec7c338dfcd8629` |
| `OpenGOALJak1Identity.s` | `ab3b9d8f63e473fee9fc108d0e38921b2cc754688924fbe473706198ad2cf246` |
| `OpenGOALJak1Identity.exports.h` | `02e4c08a949be31945366020100e6a5be27933b09011bf5d78a16b03e39d4f83` |
| `OpenGOALJak1Lognot.s` | `7d886912f47c51023c09dc168141598b61877bf60eceee16abdd1b84f5a79d34` |
| `OpenGOALJak1Lognot.exports.h` | `2f8587a50c6c7d5bc7ff1f07dbd396d6fdcb37e063a05ad2d617fc9a71c55858` |

The current iPhoneOS minimal data-arena configure and build also passed. The
archive is at the build root (`libjak1-data-arena.a`), is arm64 with iOS 18.0
and SDK 26.5 metadata, and has only `_bzero` undefined. An initial inspection
looked incorrectly under `game/` and failed `No such file`; root-archive
inspection then passed. That was an environment command-path error, not source
failure. The minimal iPhoneOS graph has no host generated-AOT target.

### Delegation and review

`arm64_codegen` implemented and validated the generated-artifact checkpoint.
`arm64_next_seam` performed an independent source, CMake graph, target-isolation,
and ABI semantic audit. Its nested `cmake_incremental_review` independently
confirmed explicit output freshness, host/iPhoneOS gating, serial generation,
and the `RUN_SERIAL` behavior. No review found a source blocker. `RUN_SERIAL`
does serialize all discovered ABI tests against CTest rather than artifact
generation alone; retain it for this checkpoint because it bounds memory use.

No simulator, generic iOS app build, signing, device, physical hardware,
remote, or push was used. **Z iPad Pro** was not accessed.

### Next task pending post-0018 audit

Do not choose a new seam in this checkpoint. The bounded candidates are the
first real generated X22 data-arena dereference, or a host-generated artifact
handoff into an iPhoneOS signed/linkable target. Either must preserve the
host-only claim boundary above until an ordinary signed app and separately
scheduled physical-device validation exist. Durable parent integration is still
blocked on maintainer direction for a fetchable pinned OpenGOAL fork, owner,
visibility/access policy, and HTTPS/SSH transport; local GitHub credentials are
invalid. Do not change `.gitmodules`, move the official submodule gitlink,
authenticate, create a fork, or push without that direction.

## Checkpoint 8: strict Jak 1 node-name compiler/export proof

Parent checkpoint `899519733fa12e57a913ca186cbae3d1931b5189` preserves child
`fab37c1f755aa342304db8dbf27f1fa1c42423ac`, whose parent is
`bd3f4752cea18e73fb1e5cbaec3efdd89ec38195`. The official OpenGOAL submodule
remains pinned at `a4cb1ac1f0596c8740b1c26accb24a58505cda92` and was not
moved.

| Child commit | Patch | Stored SHA-256 | Stable patch ID | Preserved by parent |
| --- | --- | --- | --- | --- |
| `fab37c1f755aa342304db8dbf27f1fa1c42423ac` | `0019-feat-arm64-AOT-compile-Jak-1-node-name-lookup-AI-ass.patch` | `09cbeebe9924e5e17c3e7e0631ffb655bd19aa3365c6c0f82fc8df47627a3dc8` | `6b49a5f014bc23d4c0d4cadb9a68aba8fce2068d` | `899519733fa12e57a913ca186cbae3d1931b5189` |

Patch 0019 follows 0018, which follows 0017 and the ordered 0013-0016
data-arena unit. The parent preserves the saved mbox rather than the child Git
object. Verify the stored artifact rather than a regenerated patch stream:

```sh
shasum -a 256 \
  patches/OpenGOAL/0019-feat-arm64-AOT-compile-Jak-1-node-name-lookup-AI-ass.patch
git patch-id --stable < \
  patches/OpenGOAL/0019-feat-arm64-AOT-compile-Jak-1-node-name-lookup-AI-ass.patch
```

The expected outputs are the SHA-256 in the table and
`6b49a5f014bc23d4c0d4cadb9a68aba8fce2068d fab37c1f755aa342304db8dbf27f1fa1c42423ac`.

### Scope and claim boundary

Within the existing compiler/export proof, 0019 recognizes only the exact
maintained debug-only Jak 1 `glst-node-name` definition. It accepts its one
`glst-named-node` argument in X0, combines it with the X22 GOAL-memory logical
base, and loads the unsigned 32-bit `privname` field at X22 + X0 + 8. The
generated ARM64 words are `8b36e010`, `b8408200`, and `d65f03c0`, disassembling
as:

```text
add x16, x0, x22, sxtx
ldur w0, [x16, #8]
ret
```

The paired output is the guarded one-argument export
`OPENGOAL_AOT_EXPORT1("glst-node-name", goalpad_aot_glst_node_name)`. Exact
name, body, type, field offset, field type, arity, symbol, and Export1 ABI are
validated; mismatches fail without replacing an existing paired output.

This is strict compiler/export evidence only. It does not establish a general
ARM64 load implementation, CMake artifact generation or execution, a host ABI
runtime result, initialized arena contents, C++ dispatcher behavior, desktop
global binding, live GOAL symbols, relocations, JIT, iPhoneOS, app, signing,
simulator, or physical-device behavior.

### Recorded validation and recovery

The affected `goalc-test` and `goalc-aot` build with `-j4` passed. The focused
`Arm64Aot.*` suite passed 41/41; the type/form regression passed 190/190; the
established compiler/emitter filter passed 129/129; the AOT CLI CTest passed
1/1; and full CTest passed 8/8. Host disassembly of the generated function
reported `add x16, x0, x22, sxtx; ldur w0, [x16, #8]; ret`.

An attempted `goalc-test --gtest_filter=-Listener.*` entered desktop
`Jak1KernelTest`, logged `Failed to initialize main memory! Permission denied`,
hung, and was interrupted with Ctrl-C (exit 130). It is not validation evidence
and left no source changes.

The patch was reconstructed on `bd3f4752`; its resulting tree
`7912442f30be55ab08ab75494ae44043b02b6137` was identical to the verified
child tree. The disposable
reconstruction worktree was removed. No simulator, iOS app, physical device,
remote, or push was used; **Z iPad Pro** was not accessed.

### Next exact task: 0020

Add a generated CMake artifact and host-dispatcher execution proof for only
this `glst-node-name` form. Use one allocation, two distinct X22 logical bases,
the same nonzero node offset, and two high-bit unsigned 32-bit payloads at
offset eight. Retain `RUN_SERIAL` and all present host-only claim boundaries.
Do not generalize ARM64 loads, bind desktop globals, create live GOAL symbols,
introduce executable memory or the desktop runtime linker, or claim iPhoneOS,
app, signing, simulator, or device execution.

Durable parent integration remains blocked until a maintainer chooses a
fetchable pinned OpenGOAL fork and the associated owner, visibility/access
policy, and HTTPS/SSH transport. Do not move the official submodule pin,
change `.gitmodules`, authenticate, create a fork, or push without that
direction.

## Checkpoint 9: generated host X22-backed node-name execution

Parent checkpoint `faf3f1a1a9f5dfc28dc791235345b6a4b8fc6679` preserves child
`1e43e767d66b6f554a6cc9aedb9fa024ca3130ee`, whose parent is
`fab37c1f755aa342304db8dbf27f1fa1c42423ac`. The official OpenGOAL submodule
remains pinned at `a4cb1ac1f0596c8740b1c26accb24a58505cda92` and was not
moved.

| Child commit | Patch | Stored SHA-256 | Stable patch ID | Preserved by parent |
| --- | --- | --- | --- | --- |
| `1e43e767d66b6f554a6cc9aedb9fa024ca3130ee` | `0020-test-arm64-execute-X22-backed-GOAL-field-load-AI-ass.patch` | `30d44af98ed030a4da1ac329af2aae167aa71225e82b47862a53ec7009d1c31b` | `59c59b4f6830d6d6ab91e24ab5c5b16d8301e14a` | `faf3f1a1a9f5dfc28dc791235345b6a4b8fc6679` |

Patch 0020 follows the ordered 0013-0019 sequence. The parent preserves the
saved mbox rather than the child Git object. Verify the stored artifact rather
than a regenerated patch stream:

```sh
shasum -a 256 \
  patches/OpenGOAL/0020-test-arm64-execute-X22-backed-GOAL-field-load-AI-ass.patch
git patch-id --stable < \
  patches/OpenGOAL/0020-test-arm64-execute-X22-backed-GOAL-field-load-AI-ass.patch
```

The expected outputs are the SHA-256 in the table and
`59c59b4f6830d6d6ab91e24ab5c5b16d8301e14a 1e43e767d66b6f554a6cc9aedb9fa024ca3130ee`.

### Scope and claim boundary

Within the existing Apple ARM64 host-test gate, 0020 extends the one CMake
custom command with the exact maintained debug-only Jak 1 `glst-node-name`
source. It generates and directly links that assembly plus its guarded Export1
header into `arm64-goal-call-abi-test`; the test remains separate from
`libruntime.a` and the C++ `call_goal` dispatcher.

The existing serial test makes one caller-owned arena allocation and initializes
the existing data-arena header. It uses the canonical nonzero
`global_heap_current` field as the same X0 node offset for both calls. It writes
two high-bit unsigned 32-bit payloads at that node offset plus eight, then calls
the production assembly dispatcher with two X22 logical bases 0x40 bytes apart.
The exact results are `0x0000000081234567` and `0x00000000f2345678`; both have
zero high 32 bits. The existing caller X20/X21/X22 sentinel-restoration checks
also pass.

The generated entry is exactly:

```text
add x16, x0, x22, sxtx
ldur w0, [x16, #8]
ret
```

This is bounded host evidence for this field load with caller-owned synthetic
arena contents. It does not establish general ARM64 loads, native runtime or
desktop-global initialization, a live GOAL symbol, relocation, JIT, C++ runtime
dispatch, iPhoneOS executable behavior, an app, signing, simulator, or physical
device behavior.

An initial `clang-format` pass reordered the contiguous generated Export1
includes and therefore changed the table expansion order. The declaration and
table include blocks now use `clang-format off` / `clang-format on`; assertions
protect the required `identity`, `lognot`, `glst-node-name` ordering. Final
review found no blockers.

### Recorded validation and recovery

The affected host build passed:

```sh
cmake --build /private/tmp/GOALPadOpenGOAL-arm64-goal-call-host-final-build \
  --target runtime arm64-goal-call-abi-test jak1-data-arena-test goalc-test goalc-aot \
  -j 4
```

ABI CTest passed 3/3, data-arena CTest passed 4/4, the established
compiler/emitter filter passed 129/129, AOT CLI CTest passed 1/1, and full
CTest passed 8/8. A Ninja graph query reported
`goalc-aot -> arm64-goal-call-aot-artifacts -> arm64-goal-call-abi-test`.
`nm` found the dispatcher plus all five generated AOT entries; disassembly
confirmed dispatcher X22 setup and the exact `glst-node-name` sequence above.
Import inspection found no forbidden imports.

The direct minimal iPhoneOS configure/build also passed using
`/private/tmp/GOALPadOpenGOAL-arm64-goal-call-iphoneos-0018-build`. The direct
archive
`/private/tmp/goalpad-ios-aot-x22.38XD72/libopengoal-jak1-aot-context-ios.a`
is arm64 with iOS minimum 18.0. The dispatcher and generated `glst-node-name`
assembly objects report SDK n/a; `data_arena.o` reports SDK 26.5. The archive
defines the dispatcher and all five AOT entries, has only `_bzero` undefined,
and its iPhoneOS `glst-node-name` disassembly is the exact three-instruction
sequence above. This is static object/archive compatibility only, not an
executable/app link, signing, simulator, device, or runtime-execution result.

The patch was reconstructed on `fab37c1`; its resulting tree
`26ca101158f5563789cdc8a4f2b355784a318c98` was identical to the verified child
tree. The disposable reconstruction worktree was removed. No simulator, iOS
app, physical device, remote, or push was used; **Z iPad Pro** was not accessed.

### Next task pending independent post-0020 audit

Do not choose or document a new seam in this checkpoint. Preserve the fork
publication blocker, the official OpenGOAL pin, the ordered patch sequence, and
the host-only claim boundary until an independent post-0020 audit selects the
next smallest task. A maintainer must still choose a fetchable pinned OpenGOAL
fork and its owner, visibility/access policy, and HTTPS/SSH transport before
durable parent integration. Do not move the official submodule pin, change
`.gitmodules`, authenticate, create a fork, or push without that direction.

## Checkpoint 10: direct Jak 1 level-command store AOT proof

Current parent app checkpoint:
`0da05dd82a7a1be9ef640a324c2bc339c5eb6a48`
(`feat(aot): validate level command store export (AI-assisted)`). It leaves the
official OpenGOAL submodule at
`a4cb1ac1f0596c8740b1c26accb24a58505cda92`. The equivalent isolated app
commit is `5714658e507e56acf57d2f70e91d2e062ab5f2cb` (stable patch ID
`5796c0819854d6c12c121a1cff24f91db75b326c`).

| Patch | Child commit | SHA-256 | Stable patch ID | Parent preservation commit |
| --- | --- | --- | --- | --- |
| `0021-feat-arm64-compile-Jak-1-level-command-store-AI-assi.patch` | `cb1cc102ac2af46e9581ac5b47404fe797c5b582` | `aa351b8ab006c5574f8c1f926873c344a16c5dfefcec50f856d1a3df3a58039a` | `a0f9f946d8dfa69176c10d48606b3b6812451d3a` | `c577f471e5cac7b774d932f9b627425a239bd8eb` |
| `0022-fix-arm64-reject-reserved-constant-store-operands-AI.patch` | `311be4773feaf85740427d844e1db65ba4fe5591` | `b01a9cef72acb8614968fc414f84d3a24f5e4482707cfe5f1bc38fdb2768b6a0` | `96cf91c9f9b5620924fdba710bad00b8ec9ed7d6` | `6c1370c24aef5137137f8361d0acc73f5f42382a` |
| `0023-test-arm64-execute-Jak-1-level-command-store-AI-assi.patch` | `13672fadb3fa977f407d19f15989136c38f58d61` | `68cd7a456ab2453a6614c193458458aaba9148b3721a26688a69cc9b35baea86` | `4ea0d360f9239315de845f0de6af55d4961bdc17` | `846874251af4317c1c9d91f37d227f5b54ad691e` |

Verify preserved mboxes, not regenerated patch streams:

```sh
shasum -a 256 \
  patches/OpenGOAL/0021-feat-arm64-compile-Jak-1-level-command-store-AI-assi.patch \
  patches/OpenGOAL/0022-fix-arm64-reject-reserved-constant-store-operands-AI.patch \
  patches/OpenGOAL/0023-test-arm64-execute-Jak-1-level-command-store-AI-assi.patch
git patch-id --stable < patches/OpenGOAL/0021-feat-arm64-compile-Jak-1-level-command-store-AI-assi.patch
git patch-id --stable < patches/OpenGOAL/0022-fix-arm64-reject-reserved-constant-store-operands-AI.patch
git patch-id --stable < patches/OpenGOAL/0023-test-arm64-execute-Jak-1-level-command-store-AI-assi.patch
```

0021 descends from 0020. 0022 and 0023 are sibling child commits of 0021, not
a linear 0021-to-0023 child history. The parent stores their mboxes in order,
but a future fork restoration needs a fresh combined apply/build validation;
do not claim that 0023 descends from 0022.

### Scope

0021 compiles only the direct real Jak 1
`level-group-load-commands-set!` defun body to guarded Export2 metadata and:

```text
add x16, x0, x22
add x16, x16, #0x20
str w1, [x16]
mov x0, x1
ret
```

The entry stores low 32 bits of X1 at X22 + X0 + `0x20`, then returns full X1.
0022 limits that four-byte store lowering by rejecting stack operands, X22 as a
direct address base, and unsafe X16 use. `IR_LoadConstOffset` remains guarded
to its current GPR-only shape; no general load expansion is included. 0023
executes this entry through the existing host ABI test with two X22 bases,
exact stores, full-width returns, and X20/X21/X22 restoration.

This is a direct defun-body proof only. It does not execute a top-level
`define`, install or dispatch a GOAL method/symbol, initialize the runtime,
relocate code, load user data, boot Jak, or use JIT/writable executable memory.

The checked-in generated artifacts exactly match compiler output:

```text
24e632977fca5784aabd31f8d5102b9e8f8459e2d9cd0cb9cd4464a9c45d84ed  OpenGOALJak1LevelGroupLoadCommandsSet.s
e1ada68958c9a685ff97dab3648bfeab05934680214d642ceba8fba7930b01f8  OpenGOALJak1LevelGroupLoadCommandsSet.exports.h
```

### Validation

OpenGOAL host commands:

```sh
cmake --build /private/tmp/GOALPadOpenGOAL-arm64-level-store-runtime-build \
  --target runtime arm64-goal-call-abi-test jak1-data-arena-test goalc-test goalc-aot -j 4
ctest --test-dir /private/tmp/GOALPadOpenGOAL-arm64-level-store-runtime-build \
  -R '^Arm64GoalCallAbi\.' --output-on-failure
ctest --test-dir /private/tmp/GOALPadOpenGOAL-arm64-level-store-runtime-build \
  -R '^Jak1DataArena\.' --output-on-failure
/private/tmp/GOALPadOpenGOAL-arm64-level-store-build/goalc-test \
  '--gtest_filter=Arm64Aot.*:ARM64EmitterLoads.*:ARM64EmitterIntegerMath.*:CodeTester.*:X86EmitterXMM.*:EmitterAVX.*'
ctest --test-dir /private/tmp/GOALPadOpenGOAL-arm64-level-store-runtime-build \
  -R '^goalc-aot-artifact-pair$' --output-on-failure
ctest --test-dir /private/tmp/GOALPadOpenGOAL-arm64-level-store-runtime-build --output-on-failure
```

Results: target build exit 0; ABI CTest 3/3; data-arena CTest 4/4; constrained
compiler/emitter filter 141/141; AOT artifact CTest 1/1; full CTest 8/8. This
is macOS-host static generated-code evidence only.

The app-local Export2 registry harness command in `docs/BUILDING.md` compiled
and ran with exit 0. It uses two real aligned synthetic X22 pointers at bases
`0x10`/`0x70`, X0 `0x4`, writes `0x34`/`0x94`, checks full X1 return versus W1
store, whole-buffer guards, typed cross-ABI lookup rejection, and preserved
caller X20/X21/X22 state.

The current-source macOS Debug command was:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/GOALPad-mac -jobs 4 \
  CODE_SIGNING_ALLOWED=NO build
```

The first tool-sandboxed run failed only during Swift Preview macro-server
startup with `sandbox-exec: sandbox_apply: Operation not permitted`; the same
command in the approved unsandboxed environment exited 0. The macOS Debug
dylib has `_goalpad_aot_level_group_load_commands_set` at `0x15d4` and the
exact five instructions above. This is ARM64 macOS build/disassembly evidence,
not iPad execution.

The M5 simulator build was:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'id=96C5C21A-B925-4213-82A3-90DCB8518339' \
  -derivedDataPath /private/tmp/GOALPad-sim -jobs 4 build
```

It exited 0; the app was installed/launched only on that named local simulator.
At `2026-07-31 00:48:59`, its log reported direct proof verification,
`architecture=arm64`, `result=8194`, then the first Metal frame. The settled
green screenshot is `/private/tmp/goalpad-level-store-m5-sim.png` (SHA-256
`2fda23cfb4382e79a183c74fad15342022fe0e3e8974af4528b0d52d1727c997`).
The cleanup commands were:

```sh
xcrun simctl shutdown 96C5C21A-B925-4213-82A3-90DCB8518339
xcrun simctl list devices
```

Explicit shutdown succeeded and final simulator inventory showed every
simulator `Shutdown`. This is simulator evidence only.

The generic signed Release iOS command was:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-device -jobs 4 \
  ENABLE_PREVIEWS=NO ENABLE_DEBUG_DYLIB=NO build
```

It exited 0. The monolithic main executable SHA-256 is
`f68f6e9d2b7a7608837618d13e0a5b17b8df2697d335304c321c4dae8d9836a1`; it
contains the new symbol at `0x10000400c` and the exact five instructions,
has no app-root dylibs, `__TEXT` initial protection `0x5` (read/execute), and
no `dlopen`, `dlsym`, `mmap`, `mprotect`,
`pthread_jit_write_protect_np`, Preview, or JIT markers. `codesign -d
--entitlements -` reports the app/team identifiers and `get-task-allow` true;
the embedded profile remains
`ef4a32f9aef6cca1709423e53e66518204e49a86af4d2752139de63d21244ad1`.
`codesign --verify --deep --strict` still fails with
`CSSMERR_TP_NOT_TRUSTED`, the known local certificate-trust caveat. This is
compile/signing/layout evidence only, not trust, installability, or physical
device evidence.

No physical device, **Z iPad Pro**, Freemote simulator, remote, or push was
accessed for this checkpoint.

## Checkpoint 11: direct Jak 1 `want-vis` AOT proof

Current parent app checkpoint:
`3ce59d478abe2562021bd42f3b65e0ac041847c7`
(`feat(aot): validate Jak 1 want-vis export (AI-assisted)`). Parent commits
`4580cf33ed2a03dabc1b209a4c0b352f2c5ff58a` and
`78e2c6699ec0a77fef0ea8e0a59527bd41b253e7` preserve the OpenGOAL work while
the official submodule remains at
`a4cb1ac1f0596c8740b1c26accb24a58505cda92`.

| Patch | Child commit | SHA-256 | Stable patch ID | Parent preservation commit |
| --- | --- | --- | --- | --- |
| `0024-feat-arm64-compile-Jak-1-load-state-vis-store-AI-ass.patch` | `3c6d7f871a86ecfa53a3cbd94e90237986c68219` | `e62ff82f5155882c545798af57ae5467b7346c8a132670cf3d21175949bfd986` | `43b327f7d72bce0c8c08f017fd2d4280f4df1319` | `4580cf33ed2a03dabc1b209a4c0b352f2c5ff58a` |
| `0025-test-arm64-preserve-want-vis-inline-layout-AI-assist.patch` | `d3492375caf8de14815133c3597eb65efb44bca2` | `ff6061bce14fa515d56ab92dbaa852e1a8e19effb98cbc851ed4ff1ee5af3c7f` | `159a5f6c36302627cb605d2cb1e54fad459ac302` | `4580cf33ed2a03dabc1b209a4c0b352f2c5ff58a` |
| `0026-test-arm64-execute-Jak-1-want-vis-store-AI-assisted.patch` | `3b821e75b4995a6e9a81f2624beb2485191e4e96` | `f065e49cc0975f36034ae024b3e76ae03cb0e3c1c5bd60f4090e51430fa45af1` | `7c5d6169eaa4b42bb7239639ea499a4bc4a3f492` | `78e2c6699ec0a77fef0ea8e0a59527bd41b253e7` |

Use the full `git rev-parse`-verified 0026 child above; an earlier reported
expansion of short commit `3b821e75` was incorrect. Verify the preserved
mboxes directly:

```sh
shasum -a 256 \
  patches/OpenGOAL/0024-feat-arm64-compile-Jak-1-load-state-vis-store-AI-ass.patch \
  patches/OpenGOAL/0025-test-arm64-preserve-want-vis-inline-layout-AI-assist.patch \
  patches/OpenGOAL/0026-test-arm64-execute-Jak-1-want-vis-store-AI-assisted.patch
git patch-id --stable < patches/OpenGOAL/0024-feat-arm64-compile-Jak-1-load-state-vis-store-AI-ass.patch
git patch-id --stable < patches/OpenGOAL/0025-test-arm64-preserve-want-vis-inline-layout-AI-assist.patch
git patch-id --stable < patches/OpenGOAL/0026-test-arm64-execute-Jak-1-want-vis-store-AI-assisted.patch
```

0024 and 0025 form the literal compiler-only line
`311be477 -> 3c6d7f87 -> d3492375`. Patch 0026 was exported from the separately
combined runtime line:

```text
cb1cc102 -> 13672fad (0023)
           -> e81d001b (0022 replay)
           -> 3ac22e28 (0024 replay)
           -> 420a01cc (0025 replay)
           -> 3b821e75 (0026)
```

The replay commits have the same stable patch IDs as preserved patches 0022,
0024, and 0025. Patch 0026 is not a Git-object descendant of the literal 0024
or 0025 child commits, and it does not apply directly after `d3492375`.
A future fork restoration must integrate 0023 and the stable-equivalent
0022/0024/0025 changes before 0026, then repeat the combined build and tests.

### Scope

The exact method body is in
`OpenGOAL/goal_src/jak1/engine/level/load-boundary.gc:1074-1076`:

```lisp
(set! (-> this vis-nick) arg0)
0
```

`load-boundary.gc:1101-1102` is the wrapper and
`OpenGOAL/goal_src/jak1/engine/level/level.gc:1006-1012` is caller context,
with the call at line 1009. Patch 0024 maps raw field `#x24`, represented by
GOAL-relative `#x20` plus the basic-pointer bias in X0, to a guarded Export2
entry:

```text
add x16, x0, x22
add x16, x16, #0x20
str w1, [x16]
eor x0, x0, x0
ret
```

Patch 0025 requires the expected packed inline layout. Patch 0026 executes the
generated entry on the ARM64 host against two guarded arena bases and verifies
the zero return, exact low-word stores, offset isolation, and restored
registers.

Parent `3ce59d4` changes exactly five files: the app-local export registry,
runtime core, generated `want-vis` assembly and header, and native registry
harness (`180` insertions, `5` deletions). The app adds `want-vis` as its
second Export2 entry. Its host and runtime checks use X0 `0x4`, X1 values
`0xaabbccdd81234567` and
`0x11223344f2345678`, and aligned X22 bases at arena offsets `0x10` and
`0x70`. The low words land only at raw arena offsets `0x34` and `0x94`; the
first write survives the second call, all other bytes retain their guard
value, the result is zero, and X20/X21/X22 state is restored. A missing entry
fails initialization with
`Required signed ARM64 AOT export unavailable: want-vis`.

The checked-in generated artifacts are byte-identical to the OpenGOAL build
outputs:

```text
718e440c35491569102a22ea6bf9fb204ec60fa6ade91c54dbb4602c25c081f0  OpenGOALJak1WantVis.s
18bc127bd7bfd2af14bd40a6db0277d0a0ce0ce97778f7fd2ead4fc78493d23f  OpenGOALJak1WantVis.exports.h
```

This is a direct method-body proof only. It does not execute the surrounding
top-level flow, install or dispatch `want-vis`, mutate a live GOAL symbol
table, initialize the OpenGOAL runtime, relocate code, load Jak data, boot the
game, or use JIT/writable executable memory.

### Validation

The combined OpenGOAL worktree built the affected targets with `-j 4`. Its
focused `Arm64Aot` suite passed 62/62, the ARM64 ABI CTest passed 4/4, the
data-arena CTest remained 4/4, the paired-artifact CTest passed 1/1, and the
full host CTest passed 9/9. The new host test was
`Arm64GoalCallAbi.executes_generated_jak1_want_vis_against_two_guarded_arena_bases`.

The app-local registry harness command in `docs/BUILDING.md`, including
`OpenGOALJak1WantVis.s`, compiled and ran with exit `0`.

The ARM64 macOS Debug command was:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/GOALPad-mac -jobs 4 \
  CODE_SIGNING_ALLOWED=NO build
```

It exited `0`. The resulting `GOALPad.debug.dylib` SHA-256 is
`5d802533222b9a89a1d599562b8e99673f5457c62d3bd1f00700ae4e75d84de0`.
Symbol `_goalpad_aot_load_state_want_vis` is at `0x15fc`, and disassembly
matches the five instructions above. This is macOS build and execution
evidence, not iPad evidence.

The dedicated M5 simulator build used only UDID
`96C5C21A-B925-4213-82A3-90DCB8518339`:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'id=96C5C21A-B925-4213-82A3-90DCB8518339' \
  -derivedDataPath /private/tmp/GOALPad-sim -jobs 4 build
```

The simulator was `Shutdown` initially. Build, install, and launch succeeded
only on that simulator. Its log reported:

```text
GOALPad runtime probe: Signed ARM64 Jak 1 false-func, true-func, identity, lognot, and direct level-group-load-commands-set! and want-vis AOT proof verified; architecture=arm64; result=8194
First Metal frame submitted
```

The settled screenshot
`/private/tmp/goalpad-want-vis-m5-sim.png` is visually green and has SHA-256
`bffe8a0de4fd0c4b06af9d51b90393ffa5da3c57153ed171be29c5e2db9bd2c9`.
Explicit shutdown succeeded, and the final simulator inventory again showed
the M5 simulator `Shutdown`. This is simulator evidence only.

The generic signed Release build was:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-device -jobs 4 \
  ENABLE_PREVIEWS=NO ENABLE_DEBUG_DYLIB=NO build
```

Xcode compilation and signing exited `0`. The monolithic main executable
SHA-256 is
`0f9174ef92687a036af6ea0b6400d9f01d4fedab4532fb261253c8931ff67c94`;
`_goalpad_aot_load_state_want_vis` is at `0x100004034` with the exact five
instructions. The Mach-O `__TEXT` maximum and initial protections are both
`0x5` (read/execute). Inspection found no app-root dylibs and no `dlopen`,
`dlsym`, `mmap`, `mprotect`, `pthread_jit_write_protect_np`, Preview, or JIT
markers. The signed entitlements include the app/team identifiers and
`get-task-allow`; the embedded profile SHA-256 remains
`ef4a32f9aef6cca1709423e53e66518204e49a86af4d2752139de63d21244ad1`.
`codesign --verify --deep --strict` still reports
`CSSMERR_TP_NOT_TRUSTED`, the expected local certificate-trust caveat. This is
build, signing, and layout evidence only, not trust, installability, or
physical-device execution evidence.

No physical device, **Z iPad Pro**, Freemote simulator, remote, or push was
accessed for this checkpoint.

### Historical next task completed by Checkpoint 12

Compile the complete real Jak 1 `load-state::want-levels` method body from
`OpenGOAL/goal_src/jak1/engine/level/load-boundary.gc:1042-1064`. Its wrapper
is at `load-boundary.gc:1095-1096`, and its first boot-flow caller is
`level.gc:1007` within the `1006-1012` caller context.

Keep this next checkpoint compiler-only. Audit and implement only the missing
control flow, two-iteration loops, comparisons, indexed field accesses, and
conditional stores required by that exact body, with exact and negative
compiler tests. Do not add Export3 metadata, an app wrapper, app integration,
method installation/dispatch, or broader branch/indexed-store abstractions
until the compiler proof is complete and independently reviewed.

## Checkpoint 12: complete Jak 1 `want-levels` AOT proof

Current parent checkpoints:

```text
18c623816f3db4f0600a4eb0e86b9ac35dd3c7be
feat(aot): add generated Jak 1 want-levels artifact (AI-assisted)

33beb793789892711345a5187a4ac111aaf02e1b
feat(aot): validate complete Jak 1 want-levels body (AI-assisted)
```

The official submodule remains clean at
`a4cb1ac1f0596c8740b1c26accb24a58505cda92`. The unpublished OpenGOAL work is
preserved as ordered repository patches while fork ownership, visibility,
transport, and authentication remain unresolved:

| Patch | Child commit | SHA-256 | Stable patch ID | Parent preservation commit |
| --- | --- | --- | --- | --- |
| `0027-fix-arm64-correct-AOT-encoder-primitives-AI-assisted.patch` | `732a99553a5208b0f58b70d43f146592496a8863` | `8c403d62e6dd1e65b48fbced75a6d23f3571707779910abf86cb87172c60a857` | `54ea2a358505f78e03ca596bbd3566d9502667a4` | `0c7bc5352631938dfe6581757ae2ceed8a6ffa06` |
| `0028-feat-arm64-materialize-local-AOT-control-flow-AI-ass.patch` | `e5daa70a8ebaa569859acf3f5d51a56a4f727287` | `d1c779530217d989cc4014affd7570376ad6652972dac6eb21fabfa377b430e2` | `3506c4add02c01df52af977fdee3b2fb0ff005d9` | `b1680ea5eec82a543ab143e0c475b7d0ce0424e1` |
| `0029-feat-arm64-lower-guarded-AOT-integer-math-AI-assiste.patch` | `38e15824de976e4fd9d9ebbc9e2e3d70cbfbbee9` | `39c776a6d55fa90aa64e4f26313e4b9f1dee08c2df9c95c745364f609b21acfc` | `e22fd086ac6f32f29c4bb0181ffac7fbaa27a503` | `b4beb317856e6c6f6f73c858e30ca136aed90bde` |
| `0030-feat-arm64-lower-signed-AOT-loop-backedges-AI-assist.patch` | `f514c40ff8205760d3219a4676747218f5418cb3` | `ff186bca87b566fc3621b36e4b46989669ecdab1b9f943c028b10703293b22ef` | `b2c028a7cd8bcb180ef26d5a3ce26453104cf55c` | `e91581a7dc81f85788435b1d49e5473bb82b1ae2` |
| `0031-feat-arm64-compile-complete-Jak-1-want-levels-body-A.patch` | `0b461a5619397e3a6f1c9699436023b088ba6814` | `e3f724d01331339537cfb25061c5d39cdfcddccea3ec1ba7ec5b16f36666eb60` | `0fdc1bb70886ae6f02bed043e1b4a162947534f3` | `e5bb7a1448d30095ad51ca3950d383e50200e924` |
| `0032-feat-aot-export-Jak-1-want-levels-with-three-argumen.patch` | `16123d8d317704e9f18cccbd124a1615824e5ae2` | `7e0aa676de764bd5ddf871a9d7fc9cf3aba0547be2a9174c70d2cdeaa1e9454a` | `b3c76f941ba574562fe37a5b4b289a351748808d` | `9db5b87aa5e361c6ad7064fa0d37c93951db904b` |
| `0033-test-arm64-execute-Jak-1-want-levels-branch-matrix-A.patch` | `71fc691895acf44746961b7c7a3910da376ed0fd` | `ad055ff3185f6553942eada9685d98d8189cf98790dfca35a3c9f97825d649d4` | `6ceb71e28f9ffc4b45d1a2d3c3fe8d9be7646d5e` | `8b991ba2b494bedb240b00e1d985e394c3e4e76f` |

Patches 0027-0032 form this literal compiler/export line:

```text
732a9955 -> e5daa70a -> 38e15824 -> f514c40f -> 0b461a56 -> 16123d8d
```

The reviewed host-runtime line starts from the prior combined `want-vis`
runtime and replays the same stable changes before adding 0033:

```text
3b821e75 -> a09cd329 -> ec0bcc31 -> 57ecc6e8
           -> 0291745c -> f1975b56 -> 93a97199 -> 71fc6918
```

Do not claim literal Git ancestry between the replay commits and the
corresponding preserved child objects; the stable patch IDs are the portable
identity.

### Scope

Patch 0031 matches all 160 lowered records of the complete real method body in
`OpenGOAL/goal_src/jak1/engine/level/load-boundary.gc:1042-1064`. Its direct
function fixture changes only `defmethod` to `defun`; the body is otherwise
byte-equivalent to the upstream source. The compiler emits 142 ARM64
instructions, 568 code bytes, from a strict CFG/dataflow/type/ABI match. It
does not use a diagnostic-name gate. Patches 0027-0030 add only the encoder,
local-label, guarded integer-math, and signed-loop behavior required by that
exact body. Patch 0032 adds the distinct three-argument metadata mapping:

```text
want-levels -> goalpad_aot_load_state_want_levels
```

Patch 0033 executes six semantic cases: both arguments retained, both
replaced, duplicate arguments, argument zero false, argument one false, and
both false. Each call supplies X0 `this = 4`, the level arguments in X1/X2,
Jak 1 `#f = 0x14fd24` in X21, and a guarded aligned arena base in X22. The
host test checks the whole arena and both canaries.

Parent `18c6238` adds only the generated assembly and Export3 header. They are
byte-identical to the combined OpenGOAL output:

```text
b02fe8ba458f85597d1900c854dca08cdaf001e9b56b854e6de81f16259e8f96  OpenGOALJak1WantLevels.s
840388bd896ceb4b98e6b6365175fe7328f0096f6cd659fbd301e923d509effc  OpenGOALJak1WantLevels.exports.h
```

Parent `33beb79` adds a typed Export3 lookup, a narrow eight-Apple-argument
wrapper, a 104-byte probe record, and the same six-case semantic proof in both
the runtime core and native harness. The wrapper establishes X20/X21/X22
before moving the three generated arguments into X0/X1/X2; it preserves
X19-X23 and the 16-byte stack alignment. The registry rejects every cross-
arity name. A missing entry fails initialization with:

```text
Required signed ARM64 AOT export unavailable: want-levels
```

Independent xhigh reviews accepted the exact compiler commit, host execution
commit, artifact-only commit, wrapper ABI, registry isolation, branch matrix,
guard bounds, and parent diff.

This remains a direct, statically linked method-body proof. It does not execute
the top-level `defmethod`, install or dispatch `want-levels`, initialize a live
GOAL symbol table or data arena, relocate code, load Jak data, or boot the
game. It uses no JIT or writable executable memory.

### Validation

The combined OpenGOAL worktree is
`/private/tmp/GOALPadOpenGOAL-arm64-want-levels-runtime`, branch
`goalpad/arm64-want-levels-runtime`, commit `71fc6918`. Its Release Ninja tree
is `/private/tmp/GOALPadOpenGOAL-arm64-want-levels-runtime-build`. Builds used
`-j 4`. Results:

```text
Arm64GoalCallAbi focused branch matrix: 1/1 passed
Arm64GoalCallAbi:                        5/5 passed
Jak1DataArena:                           4/4 passed
goalc-aot-artifact-pair:                 1/1 passed
Arm64Aot + exact compiler filter:       99/99 passed
full CTest:                             10/10 passed
```

The `goalc-test` executable requires `jak-project` in its path, so temporary
aliases `/private/tmp/want-levels-jak-project` and
`/private/tmp/want-levels-jak-project-build` point to the source and build
trees. They contain no repository changes.

The parent native harness was built and executed with:

```sh
xcrun --sdk macosx clang++ -std=c++20 -arch arm64 \
  -I GOALPad/Native \
  tests/native/GOALPadAOTExportRegistryHarness.cpp \
  GOALPad/Native/GOALPadAOTExportRegistry.cpp \
  GOALPad/Native/GOALPadGoalStateWrapper.s \
  GOALPad/Native/Generated/OpenGOALJak1FalseFunc.s \
  GOALPad/Native/Generated/OpenGOALJak1TrueFunc.s \
  GOALPad/Native/Generated/OpenGOALJak1Identity.s \
  GOALPad/Native/Generated/OpenGOALJak1Lognot.s \
  GOALPad/Native/Generated/OpenGOALJak1LevelGroupLoadCommandsSet.s \
  GOALPad/Native/Generated/OpenGOALJak1WantVis.s \
  GOALPad/Native/Generated/OpenGOALJak1WantLevels.s \
  -o /private/tmp/goalpad_aot_export_registry_harness_want_levels

/private/tmp/goalpad_aot_export_registry_harness_want_levels
```

Compilation and execution exited `0`.

The ARM64 macOS Debug build was:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/GOALPad-mac -jobs 4 \
  CODE_SIGNING_ALLOWED=NO build
```

The first sandboxed attempt failed at the Swift Preview macro because
`sandbox-exec` could not apply its nested sandbox. The identical command
outside that sandbox succeeded. The resulting `GOALPad.debug.dylib` SHA-256 is
`b4a2b583a9ab52af9ffc591de3fe3e4d8955d947f094a2da6fdb58a30f8a315d`;
the `want-levels` entry is at `0x15fc`.

Only the local M5 simulator UDID
`96C5C21A-B925-4213-82A3-90DCB8518339` was used:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug \
  -destination 'id=96C5C21A-B925-4213-82A3-90DCB8518339' \
  -derivedDataPath /private/tmp/GOALPad-sim -jobs 4 build

xcrun simctl boot 96C5C21A-B925-4213-82A3-90DCB8518339
xcrun simctl bootstatus 96C5C21A-B925-4213-82A3-90DCB8518339 -b
xcrun simctl install 96C5C21A-B925-4213-82A3-90DCB8518339 \
  /private/tmp/GOALPad-sim/Build/Products/Debug-iphonesimulator/GOALPad.app
xcrun simctl launch --terminate-running-process \
  96C5C21A-B925-4213-82A3-90DCB8518339 \
  com.zephyrstudiosllc.GOALPad
xcrun simctl shutdown 96C5C21A-B925-4213-82A3-90DCB8518339
```

Build, boot, install, and launch passed; launch returned PID `15755`. The green
runtime UI reported the complete `want-levels AOT proof verified`,
`Architecture: arm64`, and `AOT result: 8,194`. Screenshot
`/private/tmp/GOALPad-want-levels-M5.png` has SHA-256
`17348c1dab472dc1012029daa708b5696ec378a4b1f3282ab18e99246aab2646`.
The M5 was confirmed `Shutdown` afterward. No Freemote simulator was
accessed. This is simulator evidence only.

The generic signed Release iOS build was:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-device -jobs 4 \
  ENABLE_PREVIEWS=NO ENABLE_DEBUG_DYLIB=NO build
```

Compilation and Xcode signing exited `0`. The app contains one monolithic
ARM64 executable and no app-root dylibs. Its SHA-256 is
`1e7fb1f902794bf0104516974ce84b6fceaa2aff7c71a12df977927693116bee`.
`_goalpad_aot_load_state_want_levels` is at `0x100004034`; its 142
instructions occupy 568 bytes and have raw SHA-256
`a4a511c21f024e5e5fc3c9dc0c03513b7aab3415604521258559361231b8e6ea`,
matching the checked-in `.long` stream. Mach-O `__TEXT` maximum and initial
protections are `0x5` (read/execute), while data segments are non-executable.
Undefined-import and string scans found no `dlopen`, `dlsym`, `mmap`,
`mprotect`, `pthread_jit`, Preview, or JIT marker.

`codesign -d --entitlements -` reports the app/team identifiers and
`get-task-allow`, with no JIT entitlement. The embedded profile SHA-256 remains
`ef4a32f9aef6cca1709423e53e66518204e49a86af4d2752139de63d21244ad1`.
Strict verification still reports the known local
`CSSMERR_TP_NOT_TRUSTED` certificate-trust caveat. A separate
`security cms -D` diagnostic could not decode that local profile. These facts
do not replace Xcode's successful signing and do not establish installability
or execution on a physical device.

No physical device, **Z iPad Pro**, Freemote simulator, remote, proprietary
game data, or push was accessed for this checkpoint. Push remains blocked on
the unresolved repository owner/visibility/transport decision and invalid
GitHub credentials; do not retry publication without maintainer direction.

### Historical next task completed by Checkpoint 13

The next narrow boot dependency is the complete real
`load-state::reset!` body at
`OpenGOAL/goal_src/jak1/engine/level/load-boundary.gc:1027-1040`. Its first
direct game-flow call is
`OpenGOAL/goal_src/jak1/engine/level/level.gc:1005`, directly before
`load-state-want-levels` at line 1007. The `load-state` constructor in
`goal_src/jak1/engine/game/game-info-h.gc:48-72` also calls `reset!`; the two
top-level constructor sites are `load-boundary.gc:1109` and `1382`.

Keep the first checkpoint compiler-only and exact. It must clear both `want`
slots, write the real empty-list value to `command-list`, clear 256
`object-name` and `object-status` entries, and return `this`. Audit the
required `_empty_`, constant/basic value, shift/index, and loop operations
against the actual IR before changing the compiler. Do not add installation,
dispatch, live runtime initialization, app integration, or general
abstractions until the strict body compiles and passes independent review.

## Checkpoint 13: complete Jak 1 `load-state::reset!` AOT proof

Current parent checkpoints:

```text
53f7422c1b1dd6709a4aaa4a775d3b77abef9e31
feat(opengoal): preserve Jak 1 reset compiler proof (AI-assisted)

27e3a57a6a34903c3d1ea97c9831f80da9ba49f2
feat(opengoal): preserve Jak 1 reset Export1 metadata (AI-assisted)

379949ea10b7cb3d77db539ffe01999cb16b7ceb
test(opengoal): preserve Jak 1 reset execution proof (AI-assisted)

d843e17cd1efd3920eec6c3006ef0e4d42379623
feat(aot): add generated Jak 1 load-state reset artifact (AI-assisted)

cabb0274226dd865dda43599d2e4d7bbeb7e9908
feat(aot): integrate direct Jak 1 load-state reset proof (AI-assisted)
```

The official OpenGOAL submodule remains clean at
`a4cb1ac1f0596c8740b1c26accb24a58505cda92`. The unpublished changes are
preserved in order:

| Patch | Child commit | SHA-256 | Stable patch ID |
| --- | --- | --- | --- |
| `0034-feat-arm64-compile-Jak-1-load-state-reset-body-AI-as.patch` | `e96cedd236512ca629455e3e2bab97ae28e410a1` | `fd7dccae28bd9b6ef44213dc61a1fff1f780598f31481d5edee9a7e59a3860fb` | `a5c7198d70c35be5695a5ac288b7b6cc2bb3404b` |
| `0035-feat-aot-export-direct-Jak-1-load-state-reset-AI-ass.patch` | `2229c13ea7f1563327e03e29951425f8ce345185` | `a8eb87d556812780b1abaf9a205e297ddd4e507bbdcfafa847c988e9233117f3` | `b850708e2df5c0c4486e49b093fd155e3bd4deb1` |
| `0036-test-arm64-execute-Jak-1-load-state-reset-body-AI-as.patch` | `bb4b2e7e8705f55e8629da10cad9fb25d10e6cba` | `58b3a5f1ad13d691bbed9ca310e6275faaf4a6a5e6d822585915ab15ccf40ab8` | `47ef21e55cd67d023bf7c17c4143b4bb57967064` |

The literal child sequence is:

```text
71fc691895acf44746961b7c7a3910da376ed0fd
  -> e96cedd236512ca629455e3e2bab97ae28e410a1
  -> 2229c13ea7f1563327e03e29951425f8ce345185
  -> bb4b2e7e8705f55e8629da10cad9fb25d10e6cba
```

Worktrees and branches:

```text
/private/tmp/GOALPadOpenGOAL-arm64-load-state-reset
  goalpad/arm64-load-state-reset

/private/tmp/GOALPadOpenGOAL-arm64-load-state-reset-export
  goalpad/arm64-load-state-reset-export

/private/tmp/GOALPadOpenGOAL-arm64-load-state-reset-runtime
  goalpad/arm64-load-state-reset-runtime

/private/tmp/GOALPad-parent-load-state-reset-artifacts
  goalpad/load-state-reset-artifacts

/private/tmp/GOALPad-parent-load-state-reset-integration
  goalpad/load-state-reset-integration
```

Preserve the compiler worktree's untracked convenience symlink
`GOALPadOpenGOAL-arm64-load-state-reset-runtime`, which points to the runtime
worktree. Do not clean it.

### Scope and artifacts

Patch 0034 compiles the complete direct body at
`OpenGOAL/goal_src/jak1/engine/level/load-boundary.gc:1027-1040`. Its fixture
changes only the enclosing method form needed for a direct named AOT entry;
the 50 lowered IR records remain source-faithful. It emits 58 deterministic
ARM64 words (232 bytes), including the required Jak 1 `_empty_` value,
four-byte indexed stores, shift-by-two indexing, and the exact 256-iteration
loop.

Patch 0035 emits only the guarded one-argument metadata:

```text
reset! -> goalpad_aot_load_state_reset
```

Patch 0036 generates and links the artifact into the host ABI test. It invokes
the entry through the production state wrapper with X0 `this = 4`, the Jak 1
`#f = 0x14fd24` in X21, and two disjoint aligned X22 bases in a guarded
`0x112c`-byte arena. The expected result clears all eight `want` words, stores
`0x14fd1a` in `command-list`, fills all 256 `object-name` words with `#f`,
zeros all 256 `object-status` words, preserves the object headers,
`vis-nick`, inter-arena gap and guards, returns the full `this` value, and
restores caller registers.

The checked-in artifact is byte-identical to OpenGOAL output:

```text
b6c9baab7b6bb5b94a282013aeaf28adf29894644adeacff0f27873740110964  OpenGOALJak1LoadStateReset.s
51df1b61f6a9e134307300958564bd0fa66c3fc6fddda385040f7abdcf0371fb  OpenGOALJak1LoadStateReset.exports.h
```

The app-local Export1 table is exactly `identity`, `lognot`, and `reset!`;
`glst-node-name` remains host-only. The native harness rejects every reset
cross-arity lookup and missing names and mirrors the two-base whole-arena
proof. Independent fast `gpt-5.6-terra` subagents with `xhigh` reasoning
reviewed the compiler, export, host-runtime, generated-artifact, and parent
integration checkpoints. Final reviews accepted each bounded change.

`reset!` is a common bare method name. The current metadata identifies this
one explicit known artifact only; it is not generic symbol lookup, qualified
method identity, or dispatch. A future binding image must include sufficient
owner/type identity to avoid collisions.

This is a direct, statically linked method-body proof. It does not execute the
top-level `defmethod`, install or dispatch `reset!`, initialize a live GOAL
symbol table or data arena, bind `*load-state*`, relocate code, load Jak data,
or boot the game. It uses no JIT or writable executable memory.

### Validation

The OpenGOAL runtime worktree is at `bb4b2e7e` with Release build tree
`/private/tmp/GOALPadOpenGOAL-arm64-load-state-reset-runtime-build`.
All builds used `-j 4`. Results:

```text
Arm64GoalCallAbi:             6/6 passed
Jak1DataArena:                4/4 passed
goalc-aot-artifact-pair:      1/1 passed
compiler/emitter selection: 186/186 passed
full CTest:                  11/11 passed
```

The first direct `goalc-test` invocation failed before tests with
`Failed to initialize project path` and the
`g_file_path_info.initialized` assertion at `FileUtil.cpp:247`, because the
executable path lacked `jak-project`. The no-copy aliases
`/private/tmp/load-state-reset-jak-project` and
`/private/tmp/load-state-reset-jak-project-build` resolved it. The export
child also encountered an incomplete generated cubeb archive in its
disposable build tree; after the agent verified there was no active owner, a
clean rebuild of only that disposable output passed. Initial runtime commands
were killed by short tool yields; the same commands completed in a persistent
terminal. These were infrastructure/tooling failures, not source test
failures.

The parent native harness was compiled and executed with:

```sh
xcrun --sdk macosx clang++ -std=c++20 -arch arm64 \
  -I GOALPad/Native \
  tests/native/GOALPadAOTExportRegistryHarness.cpp \
  GOALPad/Native/GOALPadAOTExportRegistry.cpp \
  GOALPad/Native/GOALPadGoalStateWrapper.s \
  GOALPad/Native/Generated/OpenGOALJak1FalseFunc.s \
  GOALPad/Native/Generated/OpenGOALJak1TrueFunc.s \
  GOALPad/Native/Generated/OpenGOALJak1Identity.s \
  GOALPad/Native/Generated/OpenGOALJak1Lognot.s \
  GOALPad/Native/Generated/OpenGOALJak1LevelGroupLoadCommandsSet.s \
  GOALPad/Native/Generated/OpenGOALJak1WantVis.s \
  GOALPad/Native/Generated/OpenGOALJak1WantLevels.s \
  GOALPad/Native/Generated/OpenGOALJak1LoadStateReset.s \
  -o /private/tmp/goalpad_aot_export_registry_harness_load_state_reset_parent

/private/tmp/goalpad_aot_export_registry_harness_load_state_reset_parent
```

Compilation and execution exited `0`. A standalone ARM64 compile of
`GOALPadRuntimeCore.cpp` also exited `0`.

The ARM64 macOS build was:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/GOALPad-mac -jobs 4 \
  CODE_SIGNING_ALLOWED=NO build
```

It succeeded and explicitly compiled `OpenGOALJak1LoadStateReset.s`.
`GOALPad.debug.dylib` has SHA-256
`b39e999f78d75a755490f6ca87eac26beb3f86207c321cbf3d33eeccd3ecf42d`;
`_goalpad_aot_load_state_reset` is at `0x15e8`, and the disassembly contains
the exact 58 instructions.

The approved local M5 simulator build was:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=96C5C21A-B925-4213-82A3-90DCB8518339' \
  -derivedDataPath /private/tmp/GOALPad-sim -jobs 4 \
  CODE_SIGNING_ALLOWED=NO ENABLE_PREVIEWS=NO build

xcrun simctl boot 96C5C21A-B925-4213-82A3-90DCB8518339
xcrun simctl bootstatus 96C5C21A-B925-4213-82A3-90DCB8518339 -b
xcrun simctl install 96C5C21A-B925-4213-82A3-90DCB8518339 \
  /private/tmp/GOALPad-sim/Build/Products/Debug-iphonesimulator/GOALPad.app
xcrun simctl launch --terminate-running-process --console \
  96C5C21A-B925-4213-82A3-90DCB8518339 \
  com.zephyrstudiosllc.GOALPad
xcrun simctl io 96C5C21A-B925-4213-82A3-90DCB8518339 screenshot \
  /private/tmp/GOALPad-load-state-reset-M5.png
xcrun simctl shutdown 96C5C21A-B925-4213-82A3-90DCB8518339
```

It succeeded and explicitly compiled the reset assembly. Only simulator UDID
`96C5C21A-B925-4213-82A3-90DCB8518339` was booted, installed, and launched.
The launch PID was `1794`; its exact runtime line was:

```text
GOALPad runtime probe: Signed ARM64 Jak 1 false-func, true-func, identity,
lognot, and direct level-group-load-commands-set!, want-vis, want-levels, and
load-state reset body AOT proof verified; architecture=arm64; result=8194
```

The green UI showed `Architecture: arm64` and `AOT result: 8,194`. Screenshot
`/private/tmp/GOALPad-load-state-reset-M5.png` is 1668 by 2420 pixels and has
SHA-256
`353dd362039be3486a65c49006800f9bc8fbc9ce687009598b10884a43af7d9f`.
The simulator was explicitly shut down and then confirmed `Shutdown`.

The normally signed generic Release build was:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-device -jobs 4 \
  ENABLE_PREVIEWS=NO ENABLE_DEBUG_DYLIB=NO build
```

`xcodebuild` reported success in 3.695 seconds with normal Xcode signing and no
device target.
The app contains one ARM64 monolithic executable and no app-root dylibs. Its
SHA-256 is
`aae97872933a7ba266ad8041e77c076e6769a26e85cb3fc3535e121d9f117c6b`.
`_goalpad_aot_load_state_reset` is at `0x100004020`; its 58 instructions and
232 raw bytes end immediately before `_goalpad_aot_lognot`, and the body
SHA-256 is
`2f0171fc455619ad95eb20ef2686b4a8db1642cd94a727e22121051420ab4edd`.

Mach-O `__TEXT` maximum and initial protections are `0x5` (read/execute).
`__DATA_CONST` and `__DATA` are `0x3` and non-executable. Undefined-import and
string scans found no `dlopen`, `dlsym`, `mmap`, `mprotect`, `pthread_jit`,
Preview, or JIT marker. `codesign -d --entitlements -` reports application
identifier `D2YYJ54Q6V.com.zephyrstudiosllc.GOALPad`, team
`D2YYJ54Q6V`, and `get-task-allow = true`, with no JIT entitlement. The
decoded local profile reports the same identifiers and no JIT or
unsigned-executable-memory entitlement and expires at
`2026-08-06T23:51:59Z`. This is Apple Development signing, not distribution
or App Store evidence. Its SHA-256 remains
`ef4a32f9aef6cca1709423e53e66518204e49a86af4d2752139de63d21244ad1`.
Strict verification exited `1` with:

```text
CSSMERR_TP_NOT_TRUSTED
In architecture: arm64
```

That remains the known local certificate-trust caveat; Xcode's build and
signing step succeeded. The first sandboxed `security cms -D` decode returned
`cert import failed` and `problem decoding`, while the identical read-only
decode outside the sandbox succeeded. This restricted-environment fallback
also decoded the entitlements without network access:

```sh
openssl smime -inform der -verify -noverify -in "$profile" 2>/dev/null |
  plutil -extract Entitlements xml1 -o - - |
  plutil -p -
```

The deprecated
`codesign -d --entitlements :-` spelling also produced invalid/deprecated
output; the correct current command is `codesign -d --entitlements -`.

System memory remained healthy while builds were serialized:
`memory_pressure -Q` reported 67% free immediately before the Release build
and 68% afterward.

No physical device, **Z iPad Pro**, Freemote simulator, remote, retail game
data, or push was accessed for this checkpoint. Publication remains blocked
on the maintainer's repository owner/visibility/transport decision and invalid
GitHub credentials; do not retry without maintainer direction.

### Next exact task: source-faithful `load-state-want-levels` dispatch

The actual Jak 1 play-flow sequence at
`OpenGOAL/goal_src/jak1/engine/level/level.gc:1005-1009` is:

```text
reset! -> level-get-for-use -> load-state-want-levels -> display -> want-vis
```

The next audited wrapper is
`OpenGOAL/goal_src/jak1/engine/level/load-boundary.gc:1095-1096`, with
signature `(symbol symbol) -> int`. It invokes `want-levels` on global
`*load-state*`. A clean, read-only xhigh audit worktree is:

```text
/private/tmp/GOALPadOpenGOAL-arm64-load-state-want-levels-wrapper
goalpad/arm64-load-state-want-levels-wrapper
bb4b2e7e8705f55e8629da10cad9fb25d10e6cba
```

No change or checkpoint was made because the exact IR crosses four currently
unsupported signed-AOT boundaries:

1. `IR_GetSymbolValue` for `*load-state*`;
2. the object's runtime type and method-table load;
3. the 32-bit GOAL method-table entry to signed native function mapping; and
4. `IR_FunctionCall` indirect dispatch plus static relocation/linking.

The ARM64 generator currently rejects statics/relocations, and both
`IR_GetSymbolValue` and `IR_FunctionCall` are explicitly not implemented. The
existing direct `goalpad_aot_load_state_want_levels` Export3 artifact proves
the method body only. Replacing the wrapper with a hard-coded native call
would bypass the non-final `load-state` type's virtual method semantics and
would falsely present registry lookup as method dispatch.

The next implementation must first define the smallest normally signed static
binding image for symbol values, type objects, method tables, and the mapping
from a 32-bit GOAL function value to signed native ARM64 text. It must state
initialization ownership, relocation/linking behavior, data that remains
writable, and deterministic fixtures for global load, method lookup, and
indirect call. Keep game simulation separate from rendering/presentation and
do not use this compiler boundary as an excuse for a renderer, camera, or
platform-abstraction campaign.

## Checkpoint 14: signed ARM64 `*load-state*` value-cell proof

Current parent checkpoints, in order:

```text
7c49125b41f4258dc5c1e70d812ad7783c22c3f4
feat(opengoal): preserve Jak 1 symbol-value binding proof (AI-assisted)

8e3b4acfb76f0a44c559c698ce58997047083552
Integrate ARM64 load-state value binding (AI-assisted)
```

`8e3b4ac` is pushed to `origin/feat/ipados-native-boot`. The official OpenGOAL
submodule remains at `a4cb1ac1f0596c8740b1c26accb24a58505cda92`; do not move
that fetchable pin until a maintainer has selected and authenticated a durable
fork. The unpublished child is preserved independently:

| Patch | Child commit | SHA-256 | Stable patch ID |
| --- | --- | --- | --- |
| `0037-Add-ARM64-load-state-symbol-value-proof-AI-assisted.patch` | `0327eee4886f7a076d3b01f8e62afc3adddb8eeb` | `b45b36e77252b7cb31f000b497f7339c27bbfb7549d8bbe375a4e7cab5783226` | `e23e6a2dfefbfc5d7907264ee897b9a2416faa52` |

The patch follows the preserved reset execution line:

```text
71fc691895acf44746961b7c7a3910da376ed0fd
  -> e96cedd236512ca629455e3e2bab97ae28e410a1
  -> 2229c13ea7f1563327e03e29951425f8ce345185
  -> bb4b2e7e8705f55e8629da10cad9fb25d10e6cba
  -> 0327eee4886f7a076d3b01f8e62afc3adddb8eeb
```

### Scope and artifact identity

Patch 0037 adds one compiler-produced, zero-argument ARM64 artifact:

```text
goalpad_aot_load_state_value:
  signed offset = app-local int32_t cell
  address = X22 + (X21 + signed offset)
  return zero-extended 32-bit value at address
```

The artifact is normal signed text; its one mutable offset cell is ordinary
`__DATA`, never executable. Generated metadata identifies the intended Jak 1
name and type: `"jak1", "*load-state*", "load-state"`. The parent registry
contains exactly one typed `AOTSymbolValueBinding32` for that metadata.

The app harness uses synthetic, caller-owned, guarded symbol arenas and
verifies zero, positive, and negative signed displacements, including a
high-bit `0x81234567` value that must be zero-extended. It restores the offset
cell through RAII after the proof. This is an AOT code/data-shape proof only.
It does **not** initialize an OpenGOAL heap or symbol table, look up a live
`*load-state*` symbol, execute the top-level `define`, install or dispatch a
method, relocate code, load user game data, or boot Jak 1. Imported game files
remain data; native GOAL code remains built and signed with the application.

Checked-in artifact hashes:

```text
890bccca9517a6a4de48dfdc4977b650610a7a5659d2f75a5269cc53aa8af405  OpenGOALJak1LoadStateValue.s
ac3f611804cb3bfa934f2ed3a02b36da48be6c3d4810f82dce2d74c5934564f3  OpenGOALJak1LoadStateValue.exports.h
f4d5029777e0eaef5d72eb173b80cce55149e944a3a6d5b517b9da522426a20d  OpenGOALJak1LoadStateValue.symbol-value-offset.h
```

### Validation

The isolated child worktree was:

```text
/private/tmp/GOALPadOpenGOAL-arm64-load-state-symbol-value-binding
goalpad/arm64-load-state-symbol-value-binding
0327eee4886f7a076d3b01f8e62afc3adddb8eeb
```

Its configured test suite passed 12/12 with serialized resource use (`-j 4`).
The parent registry harness was compiled and executed with:

```sh
xcrun --sdk macosx clang++ -std=c++20 -arch arm64 \
  -I GOALPad/Native \
  tests/native/GOALPadAOTExportRegistryHarness.cpp \
  GOALPad/Native/GOALPadAOTExportRegistry.cpp \
  GOALPad/Native/GOALPadGoalStateWrapper.s \
  GOALPad/Native/Generated/OpenGOALJak1FalseFunc.s \
  GOALPad/Native/Generated/OpenGOALJak1TrueFunc.s \
  GOALPad/Native/Generated/OpenGOALJak1LoadStateValue.s \
  GOALPad/Native/Generated/OpenGOALJak1Identity.s \
  GOALPad/Native/Generated/OpenGOALJak1Lognot.s \
  GOALPad/Native/Generated/OpenGOALJak1LevelGroupLoadCommandsSet.s \
  GOALPad/Native/Generated/OpenGOALJak1WantVis.s \
  GOALPad/Native/Generated/OpenGOALJak1WantLevels.s \
  GOALPad/Native/Generated/OpenGOALJak1LoadStateReset.s \
  -o /private/tmp/goalpad_aot_export_registry_harness_load_state_value_parent

/private/tmp/goalpad_aot_export_registry_harness_load_state_value_parent
```

Compilation and execution exited `0`. The first ARM64 macOS `xcodebuild`
attempt under the restricted sandbox failed because of that environment, not a
source diagnostic. The same command outside the sandbox succeeded in 5.501
seconds:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/GOALPad-mac -jobs 4 \
  CODE_SIGNING_ALLOWED=NO build
```

It compiled `OpenGOALJak1LoadStateValue.s`. `GOALPad.debug.dylib` SHA-256 is
`a0b8b31e8dd19f84951acd4ae50f025eb6b1b520139457f5d058af483b195b57`.

The only runtime validation used the approved local iPad Pro 11-inch (M5)
simulator, UDID `96C5C21A-B925-4213-82A3-90DCB8518339`:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=96C5C21A-B925-4213-82A3-90DCB8518339' \
  -derivedDataPath /private/tmp/GOALPad-sim -jobs 4 \
  CODE_SIGNING_ALLOWED=NO ENABLE_PREVIEWS=NO build

xcrun simctl boot 96C5C21A-B925-4213-82A3-90DCB8518339
xcrun simctl bootstatus 96C5C21A-B925-4213-82A3-90DCB8518339 -b
xcrun simctl install 96C5C21A-B925-4213-82A3-90DCB8518339 \
  /private/tmp/GOALPad-sim/Build/Products/Debug-iphonesimulator/GOALPad.app
xcrun simctl launch --terminate-running-process --console \
  96C5C21A-B925-4213-82A3-90DCB8518339 com.zephyrstudiosllc.GOALPad
xcrun simctl io 96C5C21A-B925-4213-82A3-90DCB8518339 screenshot \
  /private/tmp/GOALPad-load-state-value-M5.png
xcrun simctl shutdown 96C5C21A-B925-4213-82A3-90DCB8518339
```

The build completed in 2.225 seconds, launch PID was `32186`, and the exact
runtime log was:

```text
GOALPad runtime probe: Signed ARM64 Jak 1 false-func, true-func, identity, lognot, and direct level-group-load-commands-set!, want-vis, want-levels, and load-state reset body plus load-state symbol-value AOT proof verified; architecture=arm64; result=8194
```

The screenshot is 1668 by 2420 pixels at
`/private/tmp/GOALPad-load-state-value-M5.png`, SHA-256
`5e8b29ac11a4ee212f4ea144ce1b0f1aa69d1f242ba933e18f3c07440eca6139`.
The simulator was confirmed `Shutdown` afterward. This is simulator evidence
only; it is not physical-device evidence.

The normally signed generic iOS Release command was:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-device -jobs 4 \
  ENABLE_PREVIEWS=NO ENABLE_DEBUG_DYLIB=NO build
```

It succeeded in 2.929 seconds. The one monolithic ARM64 executable SHA-256 is
`606b7698c53bb034fee2ce3c2c860a4a8e3ba64e4186a239f4400277863dd64f`.
`_goalpad_aot_load_state_value` is at `0x100004108`; its signed offset cell is
at `0x100014960`. Mach-O inspection reports `__TEXT` protections `0x5`
(read/execute) and `__DATA` protections `0x3` (read/write). Strict
`codesign --verify --deep --strict --verbose=4` passed. The embedded profile
SHA-256 is `ef4a32f9aef6cca1709423e53e66518204e49a86af4d2752139de63d21244ad1`,
and expires `2026-08-06T23:51:59Z`. Undefined-import, app-root-dylib, and
string scans had no JIT or dynamic-library-loading hits. This is build,
signature, and layout evidence only; no device was selected, installed to, or
launched.

Builds and simulator use were serialized. `memory_pressure -Q` reported 67%
free before the validation sequence and 64% free afterward. Independent fast
`gpt-5.6-terra` subagents using `xhigh` reasoning reviewed the child change and
parent integration; the documentation was rechecked against their evidence.

No physical device, **Z iPad Pro**, other simulator, remote, or retail game
data was accessed for Checkpoint 14. Do not claim a Jak boot or physical-device
result from this checkpoint.

### Next exact task: read-only existing-symbol value-cell resolver

Implement and prove now the smallest portable, read-only resolver over a
validated caller-owned Jak 1 data arena with synthetic fixtures:

1. Locate an already-initialized `*load-state*` `Symbol` without calling
   `intern_from_c`, allocating, executing GOAL, or creating a symbol.
2. Return only the signed `int32_t` displacement from the arena header's `s7`
   to that symbol's value-cell GOAL offset; validate every probe and bound.
3. Keep it in the existing portable `jak1-data-arena` boundary, test it with
   synthetic data and a stateless compatible name hash/CRC path, and preserve
   the host and ARM64 test suite.
4. Production callers may invoke the resolver only after real link/top-level
   initialization has created its symbol metadata; do not claim that the
   synthetic fixtures initialize a live symbol.

Only after that resolver is proved should a separate guarded method-binding
audit begin. Type-object and method-table reads, mapping a 32-bit GOAL function
value to signed native text, and indirect invocation remain distinct later
tasks. Do not shortcut the non-final `load-state` virtual semantics with a
hard-coded direct native call.

## Checkpoint 15: portable existing-symbol value-cell resolver

Current parent checkpoint:

```text
b89ff6cccef73952c5f57415905d893d23267f46
feat(opengoal): preserve Jak 1 symbol resolver (AI-assisted)
```

`b89ff6c` is pushed to `origin/feat/ipados-native-boot`. The official OpenGOAL
submodule remains at `a4cb1ac1f0596c8740b1c26accb24a58505cda92`; do not move
that fetchable pin until a maintainer has selected and authenticated a durable
fork. The unpublished child changes are independently preserved:

| Patch | Child commit | SHA-256 | Stable patch ID |
| --- | --- | --- | --- |
| `0038-feat-data-arena-add-read-only-symbol-value-lookup-AI.patch` | `da6cfe9eaf245db3d92cc69bc0074a4496b02f9d` | `a7ab385d97511c126766e5cb756eca564a1be0c3f550b2cf9d030368c7066b89` | `369d7a19a863e8dae653f0dc12ab3ef41542b5d6` |
| `0039-fix-data-arena-validate-canonical-symbol-table-tags-.patch` | `deebafd603f702f54133a8a9e8f5ce500a113231` | `3effeea99ea54d96fde7f1489c16357d773646f282e2e955cbfbe72bc54697eb` | `8ddab02469c04970285d73a5f632ce17e05de5ea` |

The literal child sequence is:

```text
71fc691895acf44746961b7c7a3910da376ed0fd
  -> e96cedd236512ca629455e3e2bab97ae28e410a1
  -> 2229c13ea7f1563327e03e29951425f8ce345185
  -> bb4b2e7e8705f55e8629da10cad9fb25d10e6cba
  -> 0327eee4886f7a076d3b01f8e62afc3adddb8eeb
  -> da6cfe9eaf245db3d92cc69bc0074a4496b02f9d
  -> deebafd603f702f54133a8a9e8f5ce500a113231
```

### Scope

Patch 0038 adds the portable, read-only
`jak1::find_data_arena_symbol_value_cell` boundary. Given a caller-owned byte
arena, a separately initialized `DataArenaHeader`, and a symbol name, it
validates bounds and the canonical Jak 1 header shape, follows the compatible
stateless CRC probe order, and returns only the existing value-cell GOAL offset
and signed `s7`-relative displacement. It does not read the value cell.

The lookup neither calls `intern_from_c` nor allocates, mutates the arena,
binds caller storage to `g_ee_main_mem`, or accesses global `s7` state. It
rejects null or oversized storage, malformed headers, embedded-NUL and
pseudo-symbol queries, unrepresentable hashes, malformed symbols, and
malformed strings without mutation. Patch 0039 additionally rejects
self-consistent but shifted symbol-table tags before probing.

This remains a synthetic data-format proof. It does not create or populate
symbol metadata, initialize a live OpenGOAL runtime, execute GOAL, perform
top-level/link initialization, create a type or method table, map a 32-bit GOAL
function value to signed native text, dispatch a method, load user data, or
boot Jak 1. It is not evidence that the iPad app, simulator, signed bundle, or
physical device resolves a live `*load-state*` symbol.

### Validation

The child worktree and host build tree were:

```text
/private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup
goalpad/data-arena-symbol-value-lookup
deebafd603f702f54133a8a9e8f5ce500a113231

/private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup-build
```

The host commands were:

```sh
ctest --test-dir /private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup-build \
  -R '^Jak1DataArena\\.' --output-on-failure

cmake --build /private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup-build \
  --target arm64-goal-call-abi-test goalc-aot -j 4

ctest --test-dir /private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup-build -N

ctest --test-dir /private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup-build \
  --output-on-failure -j 1

cmake --build /private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup-build \
  --target goalc-test -j 4

/private/tmp/data-arena-symbol-value-lookup-jak-project-build/goalc-test \
  '--gtest_filter=Arm64Aot.*:ARM64EmitterLoads.*:ARM64EmitterIntegerMath.*:CodeTester.*:X86EmitterXMM.*:EmitterAVX.*'
```

The direct `goalc-test` command used the no-copy aliases
`/private/tmp/data-arena-symbol-value-lookup-jak-project` and
`/private/tmp/data-arena-symbol-value-lookup-jak-project-build`, which point to
the source and build trees respectively. They are needed only because the
upstream executable locates a development checkout by the `jak-project` path
component; the CTest targets do not need them.

Before the prerequisite build, the first full CTest invocation reported
`arm64-goal-call-abi-test_NOT_BUILT` and failed the AOT CLI script because its
`goalc-aot` path did not exist after the resolver tests. That was an
incomplete-target infrastructure failure, not a source-test failure. After the
targeted builds, the focused `Jak1DataArena` suite passed 23/23, the
established compiler/emitter filter passed 191/191, and complete CTest passed
31/31.

The fresh iPhoneOS static-library build used:

```sh
cmake -S /private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup \
  -B /private/tmp/GOALPadOpenGOAL-arm64-symbol-resolver-iphoneos-build \
  -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 \
  -DOPENGOAL_BUILD_JAK1_DATA_ARENA_ONLY=ON -DBUILD_TESTING=OFF

cmake --build /private/tmp/GOALPadOpenGOAL-arm64-symbol-resolver-iphoneos-build \
  --target jak1-data-arena -j 4

/usr/bin/ar -t /private/tmp/GOALPadOpenGOAL-arm64-symbol-resolver-iphoneos-build/libjak1-data-arena.a
/usr/bin/lipo -info /private/tmp/GOALPadOpenGOAL-arm64-symbol-resolver-iphoneos-build/libjak1-data-arena.a

cd /private/tmp/goalpad-resolver-iphoneos.YtmF1h
/usr/bin/ar -x /private/tmp/GOALPadOpenGOAL-arm64-symbol-resolver-iphoneos-build/libjak1-data-arena.a
/usr/bin/xcrun vtool -show-build data_arena.cpp.o
/usr/bin/otool -l data_arena.cpp.o | rg -A8 'LC_BUILD_VERSION|LC_VERSION_MIN'
/usr/bin/nm -gU data_arena.cpp.o
/usr/bin/nm -um data_arena.cpp.o
```

The resulting archive contains one `data_arena.cpp.o` arm64 member. Its
`LC_BUILD_VERSION` declares iOS 18.0 with SDK 26.5. It exports
`initialize_data_arena_header` and `find_data_arena_symbol_value_cell`, and its
only undefined imports are `_bzero`, `_memchr`, and `_memcmp`. This is static
iPhoneOS compatibility evidence only; it is not an executable, app, signing,
simulator, physical-device, or runtime-execution result.

No simulator, physical device (including **Z iPad Pro**), Xcode app build,
remote, or retail game data was accessed for this checkpoint. Builds were
serialized with `-j 4`.

### Next exact task: resolver-backed synthetic composition

Compose the resolver's signed displacement with the existing signed
`load-state-value` artifact and direct `load-state::reset!` artifact using
guarded caller-owned synthetic storage. After the fixture setup, the resolver
path must remain read-only with respect to symbol metadata and must not
introduce live linking, top-level initialization, type or method-table reads,
GOAL function-value mapping, virtual dispatch, or a Jak boot claim. Keep the
app boundary unchanged until a separate validated integration requires it.

## Checkpoint 16: synthetic resolver and reset composition

Current parent checkpoint:

```text
bea65508b83261b58b11cde89efb1daa445aeaa6
test(opengoal): preserve load-state composition proof (AI-assisted)
```

`bea6550` is pushed to `origin/feat/ipados-native-boot`. The official OpenGOAL
submodule remains at `a4cb1ac1f0596c8740b1c26accb24a58505cda92`; the reviewed
source commit and preserved child commit are:

```text
9a830552
reviewed source commit

a13b42f7c8e67eb123f01ad0bca9ba07ad27bf96
test(arm64): compose load-state resolver and reset coverage (AI-assisted)
```

| Patch | Child commit | SHA-256 | Stable patch ID |
| --- | --- | --- | --- |
| `0040-test-arm64-compose-load-state-resolver-and-reset-cov.patch` | `a13b42f7c8e67eb123f01ad0bca9ba07ad27bf96` | `c90826e4d56bbff5b91c9a11b74f1c01488b1e64ec1899021446eb37b129d975` | `34929147e5b019a1b9298b0c27ae5fa604c5498a` |

`a13b42f7` is the literal child of `deebafd`, cherry-picked from reviewed
source commit `9a830552`:

```text
0327eee4886f7a076d3b01f8e62afc3adddb8eeb
  -> da6cfe9eaf245db3d92cc69bc0074a4496b02f9d
  -> deebafd603f702f54133a8a9e8f5ce500a113231
  -> a13b42f7c8e67eb123f01ad0bca9ba07ad27bf96
```

The preservation audit confirmed that ordered patches 0038-0040 replay to the
same tree as `a13b42f7`.

### Scope

Patch 0040 changes only `test/test_arm64_goal_call_abi.cpp`. Its one new ABI
test manually stages a synthetic `*load-state*` name string, `SymInfo` record,
symbol value cell, and `load-state` object in a single guarded data arena. It
uses the portable resolver to derive the signed displacement, installs that
value in the existing signed `load-state-value` offset cell, invokes the
existing static artifact to read the synthetic object pointer, and passes that
pointer to the existing direct `reset!` export.

The test verifies the resolver result, zero-extended signed-artifact return,
direct reset writes, unchanged staged string/symbol/value-cell data, immutable
arena values, object guards, outer arena guards, and caller-register
restoration. Its one roughly 66 MiB arena allocation is retained; no duplicate
arena is introduced.

This is a manually staged, test-only composition proof. It does not advance the
heap, bind `g_ee_main_mem`, create a real symbol or type object, run a linker,
execute a top-level form, map a GOAL method value to signed native text,
perform virtual method dispatch, load game data, boot Jak 1, or prove iPhoneOS,
app, signing, simulator, or physical-device behavior.

### Validation

The child commit was validated in the existing resolver host build tree:

```text
/private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup-build
```

The exact host commands were:

```sh
cmake --build /private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup-build \
  --target arm64-goal-call-abi-test -j 4

ctest --test-dir /private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup-build \
  -R '^Arm64GoalCallAbi\\.' --output-on-failure -j 1

ctest --test-dir /private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup-build \
  --output-on-failure -j 1

cmake --build /private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup-build \
  --target goalc-test -j 4

/private/tmp/data-arena-symbol-value-lookup-jak-project-build/goalc-test \
  '--gtest_filter=Arm64Aot.*:ARM64EmitterLoads.*:ARM64EmitterIntegerMath.*:CodeTester.*:X86EmitterXMM.*:EmitterAVX.*'
```

The incremental `arm64-goal-call-abi-test` build passed. Focused
`Arm64GoalCallAbi` CTest passed 8/8, full CTest passed 32/32, and the
established direct compiler/emitter filter passed 191/191. No iPhoneOS rebuild
was run because this patch does not change the `jak1-data-arena` library
source. No simulator, physical device (including **Z iPad Pro**), Xcode app
build, remote, or retail game data was accessed. Builds used `-j 4`; CTest was
serialized with `-j 1`.

### Next exact task: guarded existing-object binding audit

Reject production symbol staging for now: a fresh data arena has zero
`symbol` and `string` Type values, so staging would formalize synthetic fixture
work before fundamental-type and top-level bootstrap exists. Instead, audit and
prove the narrower guarded existing-object path: validate supplied object type
and method-table data, read the 32-bit GOAL method value, and resolve it through
an explicit signed-native mapping. Do not hard-code a direct `reset!` registry
call in place of that mapping. This remains separate from live linking,
top-level initialization, general type creation, method dispatch in a live
runtime, game data, and boot.

## Checkpoint 17: read-only BASIC method-value lookup

Current parent checkpoint:

```text
98a007148619c9e2a8e1bcddb01a09ae4af2e8f3
feat(opengoal): preserve BASIC method lookup (AI-assisted)
```

The official OpenGOAL submodule remains at
`a4cb1ac1f0596c8740b1c26accb24a58505cda92`; it was not moved. Parent commit
`98a0071` preserves the exact downstream child
`0ee4a48f9f58ea1504e84c500f6a0942bc8047ce`:

| Patch | Child commit | SHA-256 | Stable patch ID |
| --- | --- | --- | --- |
| `0041-feat-data-arena-add-read-only-BASIC-method-lookup-AI.patch` | `0ee4a48f9f58ea1504e84c500f6a0942bc8047ce` | `92fb8c378e666626c8656473451a8d024a2eb4b9f78dcf99e3bc6b518d6089cb` | `477d57e981399206ca7c890f66235153eee5554c` |

The literal preserved child sequence is:

```text
0327eee4886f7a076d3b01f8e62afc3adddb8eeb
  -> da6cfe9eaf245db3d92cc69bc0074a4496b02f9d
  -> deebafd603f702f54133a8a9e8f5ce500a113231
  -> a13b42f7c8e67eb123f01ad0bca9ba07ad27bf96
  -> 0ee4a48f9f58ea1504e84c500f6a0942bc8047ce
```

The ordered 0038-0041 replay exactly matches the `0ee4a48f` tree, and the
reverse check for patch 0041 passed.

### Delegation and review

A fast `gpt-5.6-terra` editor with xhigh reasoning produced `0ee4a48f` in its
dedicated worktree. Two independent read-only reviewers accepted the exact
commit's bounds, virtual-semantics, and executable-code boundary. The root
agent serialized all builds and patch integration.

### Scope

Patch 0041 adds the portable, read-only
`jak1::read_data_arena_basic_method_value` boundary. Given an initialized
caller-owned Jak 1 data arena, a BASIC object word, and a method id, it
validates the data-only header; the BASIC object representation; the object's
actual runtime `object_type`; the fixed Type-Type root; the runtime type tag;
the allocated and padded object sizes; and the method-table bounds. It returns
the actual `object_type`, allocated and padded sizes, and the method slot's raw
32-bit GOAL `method_value` without mutating storage.

The synthetic fixture covers the exact `load-state`-shaped values used by the
next seam: `method_id = 9`, `allocated_size = 0x82c`, and
`padded_size = 0x830`. The returned method word remains data. This checkpoint
does not cast it to a native address, inspect a function object, map it to
signed text, invoke native code, execute GOAL, or introduce JIT.

This is a data-arena proof only. It does not integrate with the GOALPad app or
the OpenGOAL runtime, stage production symbols, perform a live virtual method
dispatch, link code, load game data, or boot Jak 1. No simulator or physical
device validation occurred.

### Validation

The child worktree and existing host build tree were:

```text
/private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup
goalpad/data-arena-symbol-value-lookup
0ee4a48f9f58ea1504e84c500f6a0942bc8047ce

/private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup-build
```

Recorded host validation used:

```sh
cmake --build /private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup-build \
  --target jak1-data-arena-test -j 4

ctest --test-dir /private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup-build \
  -R '^Jak1DataArena\\.' --output-on-failure -j 1

cmake --build /private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup-build \
  --target arm64-goal-call-abi-test -j 4

ctest --test-dir /private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup-build \
  --output-on-failure -j 1

/private/tmp/data-arena-symbol-value-lookup-jak-project-build/goalc-test \
  '--gtest_filter=Arm64Aot.*:ARM64EmitterLoads.*:ARM64EmitterIntegerMath.*:CodeTester.*:X86EmitterXMM.*:EmitterAVX.*'
```

The focused `jak1-data-arena-test` build passed; focused `Jak1DataArena` CTest
passed 31/31. The `arm64-goal-call-abi-test` target build passed, full CTest
passed 40/40, and the already-existing direct compiler binary passed the
compiler/emitter filter 191/191.

The fresh minimal iPhoneOS static-library configure and build were:

```sh
cmake -S /private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup \
  -B /private/tmp/GOALPadOpenGOAL-arm64-method-value-iphoneos-build \
  -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 \
  -DOPENGOAL_BUILD_JAK1_DATA_ARENA_ONLY=ON -DBUILD_TESTING=OFF

cmake --build /private/tmp/GOALPadOpenGOAL-arm64-method-value-iphoneos-build \
  --target jak1-data-arena -j 4

xcrun ar -t /private/tmp/GOALPadOpenGOAL-arm64-method-value-iphoneos-build/libjak1-data-arena.a
file /private/tmp/GOALPadOpenGOAL-arm64-method-value-iphoneos-build/libjak1-data-arena.a
xcrun nm -g /private/tmp/GOALPadOpenGOAL-arm64-method-value-iphoneos-build/libjak1-data-arena.a

cd /private/tmp/goalpad-method-iphoneos.lQaWHf
xcrun ar -x /private/tmp/GOALPadOpenGOAL-arm64-method-value-iphoneos-build/libjak1-data-arena.a
file data_arena.cpp.o
xcrun vtool -show-build data_arena.cpp.o
xcrun nm -u data_arena.cpp.o
```

The fresh configure and `jak1-data-arena` build both passed. The archive
inspections reported one ARM64 Mach-O object with iOS platform, minimum 18.0,
and SDK 26.5. It exports only the documented data-arena surface for this series:
`initialize_data_arena_header`, `find_data_arena_symbol_value_cell`, and
`read_data_arena_basic_method_value`; its only undefined imports are `bzero`,
`memchr`, and `memcmp`. This is static iPhoneOS compatibility evidence only,
not app, runtime, signing, simulator, or physical-device evidence.

No GOALPad app build, runtime integration, simulator, physical device
(including **Z iPad Pro**), remote, or retail game data was accessed for this
checkpoint. Builds used `-j 4`; CTest was serialized with `-j 1`.

### Next exact task: Commit B exact load-state method binding

Bind the exact `load-state` method through the read-only lookup rather than a
hard-coded direct export. The fixture must key the binding by the lookup's
actual `object_type`, `method_id = 9`, raw `method_value`, and exact
`allocated_size`/`padded_size` `0x82c`/`0x830`, then select only an immutable,
statically linked signed entry. Do not cast the raw method word to a native
address or add JIT. Preserve one caller-owned arena as stable and exclusively
owned across lookup, binding, and invocation.

This remains separate from live linking, top-level initialization, general type
creation, production method-table loading, indirect dispatch in a live runtime,
game data, and boot. Do not claim native invocation from the raw method word.

## Checkpoint 18: portable trusted-native BASIC method binding

Current parent checkpoint:

```text
eaa649934ce3ba7523529bef30b39729c06d4af4
feat(opengoal): preserve trusted method binding (AI-assisted)
```

The official OpenGOAL submodule remains at
`a4cb1ac1f0596c8740b1c26accb24a58505cda92`; it was not moved. Parent commit
`eaa6499` preserves downstream child
`7aaaf29942f5836dda311e173865dfcd0ea6de64`:

| Patch | Child commit | SHA-256 | Stable patch ID |
| --- | --- | --- | --- |
| `0042-feat-data-arena-bind-trusted-native-BASIC-methods-AI.patch` | `7aaaf29942f5836dda311e173865dfcd0ea6de64` | `7bc05ccdd163742fd0701d7bd350bebecef79ccb5d1b422be403085adf428af3` | `9ddfba8fcf1a5c1416266aae51c6d66c7fbe7c73` |

The literal preserved child sequence is:

```text
0327eee4886f7a076d3b01f8e62afc3adddb8eeb
  -> da6cfe9eaf245db3d92cc69bc0074a4496b02f9d
  -> deebafd603f702f54133a8a9e8f5ce500a113231
  -> a13b42f7c8e67eb123f01ad0bca9ba07ad27bf96
  -> 0ee4a48f9f58ea1504e84c500f6a0942bc8047ce
  -> 7aaaf29942f5836dda311e173865dfcd0ea6de64
```

The ordered 0038-0042 replay exactly matches the `7aaaf299` tree, and the
reverse check for patch 0042 passed.

### Delegation and review

A fast `gpt-5.6-terra` editor with xhigh reasoning produced `7aaaf299` in its
dedicated worktree. Independent read-only review accepted the exact tuple,
Function-tag, virtual-semantics, raw-word non-execution, and lifetime boundary.
The root agent serialized builds and patch integration.

### Scope

Patch 0042 adds the portable, synchronous
`jak1::invoke_data_arena_native_basic_method1` boundary. It first reads the
actual BASIC method value from caller-owned storage, validates the resulting
Function-tagged BASIC object, then matches a caller-provided native entry only
when the complete tuple agrees: actual `object_type`, requested `method_id`,
raw 32-bit GOAL `method_value`, allocated size, padded size, and arity one.
The retained `load-state` fixture uses `method_id = 9`, `allocated_size =
0x82c`, and `padded_size = 0x830`.

The raw GOAL method word is comparison data only. It is never cast to a native
pointer; the only callable entry comes from the external binding table and is
passed to the caller-provided invoker. The neutral `native` API name does not
claim C++ proves static linkage, code signatures, entry provenance, or the
platform ABI. Production callers must provide those properties outside this
portable boundary.

The binding records, header, arena, binding span, and exposed aliases must stay
alive, immutable where required, and free of concurrent mutation or reallocation
for the entire synchronous lookup-to-invocation operation. The boundary itself
does not synchronize access. Tests cover the exact tuple; derived overrides;
wrong type, id, raw value, and each size; zero, malformed, and out-of-bounds
Function values; duplicate, null, invalid-arity, and unknown bindings; lookup
failure; and no mutation.

This is a guarded synthetic native-entry proof only. It does not call a
generated AOT Export1 through the ARM64 GOAL ABI, integrate with the GOALPad
app or OpenGOAL runtime, establish signing, perform simulator or device
execution, load game data, or boot Jak 1.

### Validation

The child source and host build tree were:

```text
/private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup
goalpad/data-arena-symbol-value-lookup
7aaaf29942f5836dda311e173865dfcd0ea6de64

/private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup-build
```

Recorded host validation used:

```sh
cmake --build /private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup-build \
  --target jak1-data-arena-test -j 4

ctest --test-dir /private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup-build \
  -R '^Jak1DataArena\\.' --output-on-failure -j 1

cmake --build /private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup-build \
  --target arm64-goal-call-abi-test -j 4

ctest --test-dir /private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup-build \
  --output-on-failure -j 1

/private/tmp/data-arena-symbol-value-lookup-jak-project-build/goalc-test \
  '--gtest_filter=Arm64Aot.*:ARM64EmitterLoads.*:ARM64EmitterIntegerMath.*:CodeTester.*:X86EmitterXMM.*:EmitterAVX.*'
```

The focused `jak1-data-arena-test` build passed; focused `Jak1DataArena` CTest
passed 37/37. The `arm64-goal-call-abi-test` target build passed, full CTest
passed 46/46, and the existing direct compiler binary passed the
compiler/emitter filter 191/191.

The fresh minimal iPhoneOS static-library configure, build, and inspection used:

```sh
cmake -S /private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup \
  -B /private/tmp/GOALPadOpenGOAL-arm64-native-binding-iphoneos-build \
  -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 \
  -DOPENGOAL_BUILD_JAK1_DATA_ARENA_ONLY=ON -DBUILD_TESTING=OFF

cmake --build /private/tmp/GOALPadOpenGOAL-arm64-native-binding-iphoneos-build \
  --target jak1-data-arena -j 4

xcrun ar -t /private/tmp/GOALPadOpenGOAL-arm64-native-binding-iphoneos-build/libjak1-data-arena.a
file /private/tmp/GOALPadOpenGOAL-arm64-native-binding-iphoneos-build/libjak1-data-arena.a
xcrun nm -g /private/tmp/GOALPadOpenGOAL-arm64-native-binding-iphoneos-build/libjak1-data-arena.a

cd /private/tmp/goalpad-native-binding-iphoneos.yGWxmo
xcrun ar -x /private/tmp/GOALPadOpenGOAL-arm64-native-binding-iphoneos-build/libjak1-data-arena.a
file data_arena.cpp.o
xcrun vtool -show-build data_arena.cpp.o
xcrun nm -u data_arena.cpp.o
```

The fresh configure and `jak1-data-arena` build passed. The archive inspection
reported one ARM64 Mach-O object with iOS minimum 18.0 and SDK 26.5. It exports
`initialize_data_arena_header`, `find_data_arena_symbol_value_cell`,
`read_data_arena_basic_method_value`, and
`invoke_data_arena_native_basic_method1`; its only undefined imports are
`bzero`, `memchr`, and `memcmp`. This is static iPhoneOS compatibility evidence
only, not app, runtime, signing, simulator, physical-device, or AOT ABI
invocation evidence.

No GOALPad app build, runtime integration, simulator, physical device
(including **Z iPad Pro**), remote, or retail game data was accessed for this
checkpoint. Builds used `-j 4`; CTest was serialized with `-j 1`.

### Next exact task: generated reset! Export1 through the typed binding

Invoke the actual generated `load-state::reset!` Export1 only through this typed
binding and a `call_goal_asm_arm64` invoker. Use guarded synthetic arena(s),
preserve the established caller-register and guard checks, and ensure every
nonmatching type, id, value, size, or arity fails closed before the native call.
Do not add a raw-address cast, JIT, app/runtime integration, signing claim, or
live data path as part of that task.

## Checkpoint 19: generated reset! through the typed ARM64 ABI boundary

Current parent checkpoint:

```text
a0ce15551f3b9642c162db1a9a8dca08c7c160e7
test(opengoal): preserve native reset binding composition (AI-assisted)
```

The official OpenGOAL submodule remains at
`a4cb1ac1f0596c8740b1c26accb24a58505cda92`; it was not moved. Parent commit
`a0ce155` preserves downstream child
`e60fb292b28168ad62d9345e8e0a33eea9356d82`:

| Patch | Child commit | SHA-256 | Stable patch ID |
| --- | --- | --- | --- |
| `0043-test-arm64-compose-native-load-state-reset-binding-A.patch` | `e60fb292b28168ad62d9345e8e0a33eea9356d82` | `b1c82bdde66acecabb5a0f1fd5c1db713e3512fb8a64d634bd340683d2ba7374` | `ac085c91b06863f4b7f3362b7eb93f6c3eaedb5d` |

The literal preserved child sequence is:

```text
0327eee4886f7a076d3b01f8e62afc3adddb8eeb
  -> da6cfe9eaf245db3d92cc69bc0074a4496b02f9d
  -> deebafd603f702f54133a8a9e8f5ce500a113231
  -> a13b42f7c8e67eb123f01ad0bca9ba07ad27bf96
  -> 0ee4a48f9f58ea1504e84c500f6a0942bc8047ce
  -> 7aaaf29942f5836dda311e173865dfcd0ea6de64
  -> e60fb292b28168ad62d9345e8e0a33eea9356d82
```

The ordered 0038-0043 replay exactly matches the `e60fb292` tree, and the
reverse check for patch 0043 passed against that preserved child.

### Delegation and review

Two independent read-only reviews returned **ACCEPT** for the exact child.
They confirmed the generated reset Export1 selection and ordering, the typed
binding tuple and raw-word boundary, guarded two-arena execution, exact reset
writes, guard and caller-register restoration, and full-backing no-mutation
failure for a mismatched binding. The root agent serialized validation and
patch integration.

### Scope

Patch 0043 changes only `test/test_arm64_goal_call_abi.cpp`. It binds the
actual generated `load-state::reset!` entry
`kArm64GoalExports1[3].entry` through the existing typed
`DataArenaNativeMethodBinding1` boundary, whose tuple retains the actual
`object_type` `0x42084`, method id `9`, Function word `0x42a04`, allocated
size `0x82c`, padded size `0x830`, and arity one. The test asserts that export
index 3 is `reset!` and that its entry type matches the ARM64 Export1 entry.

The test invokes only the trusted binding entry through the existing ARM64 ABI
outer wrapper, which uses `call_goal_asm_arm64`. The raw 32-bit GOAL method
word remains comparison data and is never cast to a native pointer. Two compact
canonical caller-owned arenas run inside guarded backing storage; each full
arena is compared with the expected reset state, including the eight `want`
flags, empty command list, object-name and status ranges, preserved metadata,
and a `vis-nick` sentinel. Global and inner guards, plus caller X20/X21/X22,
must be restored. A changed binding method word must return `UnboundMethod`,
make zero invoker calls, and leave the full backing buffer unchanged.

This is a test-only child change. It did not alter production runtime or
iPhoneOS library inputs, so no iPhoneOS static-library rebuild was run for this
checkpoint. It is host ARM64 synthetic evidence only: no GOALPad application
build, runtime integration, signing, simulator, physical device (including
**Z iPad Pro**), remote, or proprietary game data was accessed. It does not
establish static linkage, code-signature validity, live storage lifetime,
runtime initialization, game-data loading, or Jak 1 boot.

### Validation

Recorded host validation used the existing configured build trees:

```sh
cmake --build /private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup-build \
  --target arm64-goal-call-abi-test -j 4

ctest --test-dir /private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup-build \
  -R '^Arm64GoalCallAbi\\.' --output-on-failure -j 1

ctest --test-dir /private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup-build \
  --output-on-failure -j 1

/private/tmp/data-arena-symbol-value-lookup-jak-project-build/goalc-test \
  '--gtest_filter=Arm64Aot.*:ARM64EmitterLoads.*:ARM64EmitterIntegerMath.*:CodeTester.*:X86EmitterXMM.*:EmitterAVX.*'
```

The `arm64-goal-call-abi-test` target build passed. Focused
`Arm64GoalCallAbi` CTest passed 9/9, full CTest passed 47/47, and the existing
direct compiler/emitter binary passed 191/191. Builds used `-j 4`; CTest was
serialized with `-j 1`.

### Next exact task: audit the first app/runtime integration boundary

Before altering runtime or application code, audit the smallest GOALPad
app/runtime boundary that can provide a statically linked native entry and
caller-owned storage with explicit initialization, lifetime, ownership, and
normal signing responsibilities. Select one contained integration proof only
after that audit. Do not add JIT or a raw-address cast, and do not claim app,
signing, simulator, device, game-data, or boot execution without its own
validation.

## Fork readiness audit: complete 0001-0043 replay

This read-only audit started from the official OpenGOAL pin
`a4cb1ac1f0596c8740b1c26accb24a58505cda92`. It did not create or publish a
fork, contact a network service, use GitHub authentication, run a build, or
create commits. The GOALPad parent worktree was not edited.

Two detached temporary OpenGOAL audit worktrees were preserved with their
staged replay result and no new commits:

```text
/private/tmp/GOALPadOpenGOAL-fork-readiness-0043
/private/tmp/GOALPadOpenGOAL-fork-readiness-0043-topological
```

All 43 numbered mbox files in `patches/OpenGOAL` applied with
`git apply --index --whitespace=nowarn`; there was no first failure. The
literal lexical order `0001` through `0043` applies cleanly. The
topology-preserving publication order is:

```text
0001-0021, 0023, 0022, 0024-0043
```

The intentional `0023`/`0022` swap accounts for their sibling relationship
from 0021. The historical replay contains the stable-equivalent identities for
0022 and 0024-0032, while 0023, 0026, and 0033 retain their literal commits.
Both audit orders produced tree
`b56430db836c2f722f91f7f263692b535c820c52`, exactly equal to
`e60fb292b28168ad62d9345e8e0a33eea9356d82^{tree}`. The final preserved child
`e60fb292` descends from the official pin.

### Conditional publication recipe

Only after a maintainer selects the fork owner, repository, visibility, and
SSH-versus-HTTPS transport, create a clean clone of that fork and replay the
preserved mboxes. Do not put credentials or tokens in commands, shell history,
or documentation.

```sh
git clone "$FORK_URL" jak-project-goalpad
cd jak-project-goalpad
git switch -c goalpad/arm64-aot-0043 \
  a4cb1ac1f0596c8740b1c26accb24a58505cda92

patch_dir=/absolute/path/to/GOALPad/patches/OpenGOAL
git am --3way \
  "$patch_dir"/000{1,2,3,4,5,6,7,8,9}-*.patch \
  "$patch_dir"/001{0,1,2,3,4,5,6,7,8,9}-*.patch \
  "$patch_dir"/002{0,1}-*.patch \
  "$patch_dir"/0023-*.patch \
  "$patch_dir"/0022-*.patch \
  "$patch_dir"/002{4,5,6,7,8,9}-*.patch \
  "$patch_dir"/003{0,1,2,3,4,5,6,7,8,9}-*.patch \
  "$patch_dir"/004{0,1,2,3}-*.patch

test "$(git rev-parse HEAD^{tree})" = \
  b56430db836c2f722f91f7f263692b535c820c52
git diff --check a4cb1ac1f0596c8740b1c26accb24a58505cda92..HEAD
git push -u origin goalpad/arm64-aot-0043
```

If replay conflicts in the selected fork, stop with `git am --abort` and audit
the new upstream base before resolution; do not stack an unreviewed manual
fix. This audit proves a local replay at the pinned base only. It does not
prove that a remote fork exists, that the chosen remote contains the pin, or
that authentication and push permission work.

## Claude transition: Checkpoint 20 and immediate build path

This section supersedes older “next task” text above it.

### Verified Git state

The parent repository is clean at a pushed checkpoint:

```text
/Users/zach/Developer/OS_Projects/GOALPad/GOALPad
branch: feat/ipados-native-boot
HEAD: ce027a09693f7e010ddcf863c3f306a12ec9a503
origin/feat/ipados-native-boot: ce027a09693f7e010ddcf863c3f306a12ec9a503
commit: feat(opengoal): preserve typed ARM64 method invoker (AI-assisted)
```

The official `OpenGOAL` submodule is deliberately still pinned to the
fetchable upstream commit:

```text
a4cb1ac1f0596c8740b1c26accb24a58505cda92
https://github.com/open-goal/jak-project.git
```

The accepted unpublished OpenGOAL child is clean in both of these worktrees:

```text
/private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup
branch: goalpad/data-arena-symbol-value-lookup
HEAD: c7ef4691571cc462815816c098fa9d241bc58c81

/private/tmp/GOALPadOpenGOAL-data-arena-arm64-invoker
branch: goalpad/data-arena-arm64-invoker
HEAD: c7ef4691571cc462815816c098fa9d241bc58c81
commit: feat(arm64): add typed data-arena method invoker (AI-assisted)
```

The parent patch worktree is clean at:

```text
/private/tmp/GOALPad-parent-symbol-resolver-patches
branch: goalpad/symbol-resolver-patches
HEAD: 3e5e56b314724611e06b61c4a53103ac05d85387
```

Patch 0044 is:

```text
patches/OpenGOAL/0044-feat-arm64-add-typed-data-arena-method-invoker-AI-as.patch
SHA-256: a2a174ce14e236dc4a2691a3e5349432fea7f2eb852f47664e78df56306499ef
stable patch ID: ec2f9c43c1984d58a12442edd1b844e7b2055f1a
child commit: c7ef4691571cc462815816c098fa9d241bc58c81
```

The reverse-apply check passed against `c7ef4691`. The ordered 0038-0044
replay exactly matches that child. The complete topology-preserving 0001-0044
staged replay also exactly matches it:

```text
accepted tree: 7be1ffe4f016ed97c470c9b501231630d603e82f
replayed tree: 7be1ffe4f016ed97c470c9b501231630d603e82f
```

Preserve the replay worktrees. They are intentionally staged/dirty audit
evidence, not abandoned edits:

```text
/private/tmp/GOALPadOpenGOAL-resolver-ordered-replay
  detached ordered 0038-0044 replay; new files are intent-to-add

/private/tmp/GOALPadOpenGOAL-fork-readiness-0043-topological
  detached staged topology-preserving 0001-0044 replay; directory name is stale

/private/tmp/GOALPadOpenGOAL-fork-readiness-0043
  detached staged lexical 0001-0043 historical audit
```

Do not reset, clean, discard, or “fix” those worktrees.

### What Checkpoint 20 implements

OpenGOAL child `c7ef4691` adds:

```text
game/kernel/jak1/data_arena_arm64_invoker.h
game/kernel/jak1/data_arena_arm64_invoker.cpp
game/kernel/jak1/data_arena_arm64_invoker.s
game/kernel/jak1/data_arena_arm64_invoker.cmake
```

`jak1::invoke_data_arena_native_method1_arm64` accepts a typed
`DataArenaNativeMethodArm64Context`, resolves the existing fail-closed binding,
and calls only the statically linked trusted native entry. The assembly bridge
keeps process, `s7`, and arena base distinct in X20, X21, and X22; zero-extends
the 32-bit GOAL object; preserves the Apple ARM64 callee-saved state; and does
not cast the GOAL method word to a native pointer. The existing real generated
`reset!` host test now uses this production callback across two arenas and
retains mismatch/no-call/no-mutation coverage.

The root CMake file also has the narrow minimal build mode:

```text
OPENGOAL_BUILD_JAK1_DATA_ARENA_ARM64_INVOKER_ONLY=ON
```

It produces `libjak1-data-arena.a` and
`libjak1-data-arena-arm64-invoker.a` for Apple ARM64 without configuring the
full OpenGOAL graph.

### Exact Checkpoint 20 validation

Host target and tests:

```sh
cmake --build \
  /private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup-build \
  --target arm64-goal-call-abi-test -j 4

ctest --test-dir \
  /private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup-build \
  -R '^Arm64GoalCallAbi\\.' --output-on-failure -j 1

ctest --test-dir \
  /private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup-build \
  --output-on-failure -j 1

/private/tmp/data-arena-symbol-value-lookup-jak-project-build/goalc-test \
  '--gtest_filter=Arm64Aot.*:ARM64EmitterLoads.*:ARM64EmitterIntegerMath.*:CodeTester.*:X86EmitterXMM.*:EmitterAVX.*'
```

Results: target build passed; focused CTest passed 10/10; full CTest passed
48/48; direct compiler/emitter filter passed 191/191.

Minimal iPhoneOS ARM64 build:

```sh
cmake -S /private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup \
  -B /private/tmp/GOALPadOpenGOAL-data-arena-arm64-invoker-configure \
  -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 \
  -DOPENGOAL_BUILD_JAK1_DATA_ARENA_ARM64_INVOKER_ONLY=ON \
  -DBUILD_TESTING=OFF

cmake --build \
  /private/tmp/GOALPadOpenGOAL-data-arena-arm64-invoker-configure \
  --target jak1-data-arena-arm64-invoker -j 4
```

The build passed. Archive inspection found only the intended C++ and assembly
invoker objects, the typed C++ entry, and the assembly call entry. Both objects
are ARM64 Mach-O for iOS with minimum OS 18.0. The companion data-arena archive
contains only `data_arena.cpp.o` and its expected portable APIs/imports.

Not validated in Checkpoint 20: GOALPad app linkage, simulator execution,
physical-device execution, app signing/layout, game data, or Jak boot.

### Stop compiling micro-proofs; build the integration

The maintainer's final direction is explicit: do not add another compiler
micro-proof unless the integration produces a concrete compiler failure. The
shortest route is:

1. Publish `c7ef4691` to a dedicated fetchable OpenGOAL fork and branch.
2. Change `.gitmodules` and the `OpenGOAL` gitlink to that exact published
   commit; verify a fresh recursive checkout resolves it.
3. Compile/link the pinned `data_arena.cpp` and ARM64 invoker C++/assembly into
   the GOALPad Xcode build from the submodule. Do not copy a machine-local
   archive or add an absolute `/private/tmp` path.
4. Replace the app's direct reset proof with composition through the pinned
   `DataArenaNativeMethodBinding1` and typed ARM64 invoker, using the already
   signed generated `reset!` export and caller-owned arena storage.
5. Build and run on only the local iPad Pro 11-inch (M5) simulator
   `96C5C21A-B925-4213-82A3-90DCB8518339`, then shut it down. Also run a generic
   Release `iphoneos` build with normal signing. Never access **Z iPad Pro**
   without a new explicit request.

The Xcode project uses a `PBXFileSystemSynchronizedRootGroup` for `GOALPad/`, so
all app-local files below that directory are auto-included. `OpenGOAL/` is
outside that synchronized group and currently contributes no sources or target.
The current app already contains the generated `reset!` assembly/export in
`GOALPad/Native/Generated`, registers it in
`GOALPad/Native/GOALPadAOTExportRegistry.cpp`, and calls it directly from
`GOALPad/Native/GOALPadRuntimeCore.cpp`. `ContentView.swift` triggers
`GOALPadRuntimeBridge.initializeRuntime()`. Those are the current composition
points; the next change should add the pinned production data-arena/invoker
source boundary and route the existing reset validation through it.

### Current external blocker

The parent repository push succeeded on 2026-07-31:

```text
00e093c..ce027a0  feat/ipados-native-boot -> feat/ipados-native-boot
```

Fork creation did not occur. `gh auth status` currently reports invalid tokens
for both configured accounts, `zschwendi` and `zephyrstudiosllc`. Neither
`zschwendi/jak-project` nor `zephyrstudiosllc/jak-project` was established by
this worker. A non-escalated `git credential fill` probe also failed with
`Device not configured`; it printed no secret. The previous owner/visibility/
transport choice was never supplied. Claude must get working GitHub auth and a
confirmed durable owner before creating the remote. Once the fork exists, do
not delay the Xcode integration for more architecture or documentation work.

All newly started subagent audits were interrupted when the maintainer switched
workers. They made no shared-worktree edits. The isolated documentation
worktree `/private/tmp/GOALPad-parent-checkpoint20-docs` is clean at `ce027a0`.

## Checkpoint 21: published fork and in-app typed reset composition

This section supersedes the Checkpoint 20 transition above.

### Published and pinned repositories

The parent implementation checkpoint is:

```text
repository: /Users/zach/Developer/OS_Projects/GOALPad/GOALPad
branch: feat/ipados-native-boot
commit: 0b413b9c760cae933509499852523fcddb139193
remote branch: origin/feat/ipados-native-boot
```

The workspace handoff files are ready for Claude:

```text
/Users/zach/Developer/OS_Projects/GOALPad/CLAUDE.md -> AGENTS.md
default subagents: non-fast gpt-5.6-sol, xhigh reasoning
context checkpoint: update this handoff near 70 percent usage before clearing
```

The dedicated public OpenGOAL fork and pin are:

```text
fork: https://github.com/zschwendi/jak-pad.git
published branch: goalpad/arm64-aot-0044
pin: 9eecb9c3193ed8cb5175c9199cecbe9cfd2baa42
submodule state: detached and clean at the pin
```

The verified parent sequence is:

```text
1c64426 build(opengoal): pin dedicated ARM64 fork (AI-assisted)
b5922f5 build(ipados): link pinned OpenGOAL data arena (AI-assisted)
d9910ab fix(opengoal): pin canonical reset fixture (AI-assisted)
0b413b9 feat(runtime): execute reset through pinned data arena (AI-assisted)
```

OpenGOAL child `9eecb9c3` corrects the canonical reset fixture by staging
`kheapinfo::top_base` as the heap end, writing only the empty pair's CAR/CDR
cells, and asserting those header values before invocation. It was pushed as a
fast-forward update to `goalpad/arm64-aot-0044`. The parent gitlink was then
advanced to that exact fetchable commit.

A fresh lightweight parent clone and a fresh fork-branch clone both resolved
the published pin. `.gitmodules`, the parent gitlink, the submodule checkout,
and the remote branch all agreed on `9eecb9c3`.

The post-bump fetchability check used:

```sh
git clone --filter=blob:none --no-checkout --depth 1 \
  --branch feat/ipados-native-boot \
  https://github.com/zschwendi/GOALPad.git \
  /private/tmp/goalpad-pin-final.ORISUE/GOALPad

git clone --filter=blob:none --no-checkout --depth 1 \
  --branch goalpad/arm64-aot-0044 \
  https://github.com/zschwendi/jak-pad.git \
  /private/tmp/goalpad-pin-final.ORISUE/jak-pad

git -C /private/tmp/goalpad-pin-final.ORISUE/GOALPad \
  ls-tree HEAD OpenGOAL
git -C /private/tmp/goalpad-pin-final.ORISUE/jak-pad rev-parse HEAD
```

Both clones exited `0`; the parent was `0b413b9`, its gitlink was `9eecb9c3`,
and the fork branch was `9eecb9c3`. The two partial clones occupy under 1 MiB
combined.

### Xcode and runtime composition

`GOALPad.xcodeproj` directly compiles these sources from the pinned submodule:

```text
OpenGOAL/game/kernel/jak1/data_arena.cpp
OpenGOAL/game/kernel/jak1/data_arena_arm64_invoker.cpp
OpenGOAL/game/kernel/jak1/data_arena_arm64_invoker.s
```

There is no copied archive, absolute temporary path, or alternate engine. The
runtime proof now creates two compact caller-owned synthetic arenas, stages the
canonical heap/type/function/load-state metadata, resolves the actual BASIC
method tuple, exact-matches it to an immutable trusted binding, and calls the
signed generated `load-state::reset!` Export1 only through
`jak1::invoke_data_arena_native_basic_method1` and the typed ARM64 invoker. It
checks the returned object, full binding tuple, every expected reset write, the
complete arena image, metadata, sentinels, and guards for both arena bases.

The negative path changes only the binding's raw GOAL method word and requires
`UnboundMethod`, no native callback, no byte mutation, and intact outer guards.
The raw 32-bit GOAL method value is never converted to a native pointer. The
implementation adds no JIT, writable-executable-memory, dynamic symbol lookup,
or UI/lifecycle coupling.

An independent correctness review first rejected the inherited malformed
empty-pair write and incorrect `top_base`. Both the fork fixture and app staging
were corrected. The follow-up review accepted the exact corrected diff. A
separate security/architecture review also accepted the trusted-entry
provenance, lifetimes, bounds, fail-closed behavior, and no-JIT design.

### Validation

The corrected OpenGOAL ARM64 target and focused ABI suite passed:

```sh
cmake --build \
  /private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup-build \
  --target arm64-goal-call-abi-test -j 4

ctest --test-dir \
  /private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup-build \
  -R '^Arm64GoalCallAbi\\.' --output-on-failure -j 1
```

Result: build exit `0`; `Arm64GoalCallAbi` passed 10/10.

The current host composition harness was built and run with the app runtime and
pinned OpenGOAL sources:

```sh
xcrun --sdk macosx clang++ -std=c++20 -arch arm64 \
  -I GOALPad/Native -I OpenGOAL \
  tests/native/GOALPadAOTExportRegistryHarness.cpp \
  GOALPad/Native/GOALPadAOTExportRegistry.cpp \
  GOALPad/Native/GOALPadRuntimeCore.cpp \
  GOALPad/Native/GOALPadGoalStateWrapper.s \
  OpenGOAL/game/kernel/jak1/data_arena.cpp \
  OpenGOAL/game/kernel/jak1/data_arena_arm64_invoker.cpp \
  OpenGOAL/game/kernel/jak1/data_arena_arm64_invoker.s \
  GOALPad/Native/Generated/OpenGOALJak1FalseFunc.s \
  GOALPad/Native/Generated/OpenGOALJak1TrueFunc.s \
  GOALPad/Native/Generated/OpenGOALJak1LoadStateValue.s \
  GOALPad/Native/Generated/OpenGOALJak1Identity.s \
  GOALPad/Native/Generated/OpenGOALJak1Lognot.s \
  GOALPad/Native/Generated/OpenGOALJak1LevelGroupLoadCommandsSet.s \
  GOALPad/Native/Generated/OpenGOALJak1WantVis.s \
  GOALPad/Native/Generated/OpenGOALJak1WantLevels.s \
  GOALPad/Native/Generated/OpenGOALJak1LoadStateReset.s \
  -o /private/tmp/goalpad_pinned_runtime_composition_harness

/private/tmp/goalpad_pinned_runtime_composition_harness

xcrun nm -n -C /private/tmp/goalpad_pinned_runtime_composition_harness | \
  rg 'goalpad_aot_load_state_reset|jak1_data_arena_call_native_method1_arm64|invoke_data_arena_native_method1_arm64|invoke_data_arena_native_basic_method1'
```

Result: compile and execution exited `0`. All four required symbol families
were present.

The ARM64 macOS app build passed:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/GOALPad-mac -jobs 4 \
  CODE_SIGNING_ALLOWED=NO ENABLE_PREVIEWS=NO ENABLE_DEBUG_DYLIB=NO build
```

Only the approved M5 simulator
`96C5C21A-B925-4213-82A3-90DCB8518339` was used. The Debug build, boot,
install, and launch passed; the launch PID was `99701`. The runtime logged:

```text
GOALPad runtime probe: Signed ARM64 Jak 1 false-func, true-func, identity, lognot, and direct level-group-load-commands-set!, want-vis, want-levels, and data-arena-bound load-state reset plus load-state symbol-value AOT proof verified; architecture=arm64; result=8194
```

The inspected screenshot is
`/private/tmp/GOALPad-data-arena-reset-M5.png`, SHA-256
`45647e0001a53147b4c43ea0bb9a9f99866eff4c95e78848d210f070c824d2df`.
The simulator was explicitly shut down and confirmed `Shutdown` afterward.

The normally signed generic iOS Release build passed:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-device -jobs 4 \
  ENABLE_PREVIEWS=NO ENABLE_DEBUG_DYLIB=NO build
```

The output at
`/private/tmp/GOALPad-device/Build/Products/Release-iphoneos/GOALPad.app`
is a monolithic thin ARM64 app. The executable SHA-256 is
`f7fc6b8e5533105eeaa7fc3890701fb56e74ccefeea6f1d74ddf767ed26c7cd0`;
the embedded profile SHA-256 is
`ef4a32f9aef6cca1709423e53e66518204e49a86af4d2752139de63d21244ad1`.
Current symbol addresses are:

```text
0x1000044ec  jak1::invoke_data_arena_native_basic_method1
0x100004874  jak1::invoke_data_arena_native_method1_arm64
0x1000048d0  _goalpad_aot_load_state_reset
0x1000074c0  _jak1_data_arena_call_native_method1_arm64
```

The assembly invoker preserves X19-X22 and performs its only native entry call
with `blr x19`. `__TEXT` is read/execute; `__DATA_CONST` and `__DATA` are
read/write and non-executable. No app-root dynamic library exists. Undefined
symbol and string scans found none of `dlopen`, `dlsym`, `mmap`, `mprotect`,
`pthread_jit`, Preview, or JIT markers.

Keychain-backed strict verification reported `valid on disk` and `satisfies its
Designated Requirement`. The Apple Development signature is
`zschwendi@zephyrstudios.dev (BZ68MJN5R5)`, Team ID `D2YYJ54Q6V`, CDHash
`9514d2fedbdcf46985725f9ef6a277068510e647`. Entitlements are limited to the
application identifier, team identifier, and `get-task-allow = true`; there is
no JIT or unsigned-executable-memory entitlement. The Xcode-managed local
development profile expires `2026-08-06T23:51:59Z`.

### Not validated

No physical iPad, including **Z iPad Pro**, was accessed. This checkpoint does
not prove live OpenGOAL globals, a persistent runtime session, general symbol or
type bootstrap, top-level GOAL initialization, linker/object loading, retail
game data, the game renderer, title-screen boot, gameplay, distribution, or App
Store readiness.

### Next smallest task

Continue Stage 5 by giving GOALPad one C++-owned Jak 1 arena with explicit
initialization, stable lifetime, failure reporting, and teardown, using
`jak1::initialize_data_arena_header`. Reuse that arena serially so the runtime
does not duplicate the 65,766,112-byte (`0x03eb82e0`, 62.719 MiB) canonical
allocation. Allocate the trusted type/function/load-state objects at or after
the initialized heap current `0x17fd20`, reserve the full declared Type method
table, and advance the live heap record past every staged object before
repeating the typed reset invocation through the existing signed path. Do not
reuse the compact fixture offsets `0x42004`, `0x42104`, or `0x42a04`; they are
below canonical `HEAP_START = 0x13fd20`.

Do not bind desktop globals, call `InitHeapAndSymbol`, add the general linker,
load retail data, or start another compiler micro-proof in this checkpoint.

### Audited implementation boundary for the next worker

Two independent non-fast `gpt-5.6-sol`/`xhigh` read-only audits accepted the
persistent arena as the next real Stage 5 seam with the narrowing above.

Keep the implementation to the existing runtime/bridge boundary and harness:

```text
GOALPad/Native/GOALPadRuntimeCore.cpp
GOALPad/Native/GOALPadRuntimeCore.hpp
GOALPad/Native/GOALPadRuntimeBridge.h
GOALPad/Native/GOALPadRuntimeBridge.mm
tests/native/GOALPadAOTExportRegistryHarness.cpp
```

Use one private process-lifetime C++ session with a mutex, one stable nothrow
heap allocation, the canonical `DataArenaHeader`, derived staged-object layout,
storage identity, and an immutable external signed binding. Add an explicit,
idempotent `shutdown_runtime()` forwarded by Objective-C++, but do not attach
shutdown to a SwiftUI view, scene inactivity, or backgrounding. Repeated
initialization with the same storage path must reuse the exact allocation;
conflicting storage paths must fail without destroying a valid session; a
shutdown followed by initialization must create clean canonical state.

The initializer destructively clears the full 62.719 MiB range. Allocate only
one canonical arena and do not retain a second full expected copy. Snapshot and
compare only the small staged metadata/object window, plus canonical header,
fixed-symbol, object-guard, and outer-guard checks. Leave the unrelated compact
compiler regression probes outside the persistent session.

Initialization is all-or-nothing. Allocation, header, layout, symbol resolver,
binding, invocation, or guard failure must publish no live session and must not
allow a C++ exception across Objective-C++. Hold the mutex across symbol-offset
selection, lookup, invocation, verification, failure cleanup, and teardown.
Restore `goalpad_aot_jak1_load_state_symbol_offset` on failure and teardown.

The host harness must prove: exact logical size and one allocation; derived
objects do not overlap and remain below heap end; live heap current advances;
two resets reuse the same arena; a second initialization does not re-zero state;
binding mismatch remains no-call/no-mutation; conflicting-path failure preserves
the valid session; a first-initialization failure publishes no session and a
later retry succeeds; concurrent initialization/reset callers are serialized;
double teardown is safe; and teardown/reinitialize returns fresh working state.
Run `/usr/bin/time -l` around the harness and keep heavy builds serial. Then
repeat the Checkpoint 21 OpenGOAL tests, ARM64 macOS build, approved M5
simulator build/run with RSS sampling and shutdown, and generic signed iOS
Release inspection.

---

# Checkpoint 22: strategy change, real kernel, and the AOT C backend

Date: 2026-07-31. This checkpoint supersedes all earlier direction in this file.

## Maintainer direction (explicit, this session)

- **Hard fork.** No effort is spent keeping changes upstreamable.
- **Zero x86 is the end state.** x86 is removed from everything shipped or
  targeted. `goalc`'s x86 emitter is deleted once ARM64 compiles Jak 1.
- **Progress is judged by movement toward a playable game.** Passing unit tests
  is explicitly *not* sufficient. The maintainer said this directly after many
  checkpoints of byte-exact golden tests produced no runnable game.
- Subagents this session were Fable/Opus by maintainer request. That was
  session-only; do NOT edit the `AGENTS.md` subagent policy for it.

## Why the previous approach was abandoned

The ARM64 backend was a proof backend: ~8 of 42 IR node types had any lowering,
each artificially gated, with `IR_FunctionCall`, `IR_GetSymbolValue`,
`IR_SetSymbolValue`, `IR_FloatMath`, `IR_StaticVarAddr/Load`, and
`IR_FunctionAddr` all `throw "NYI"`. Roughly a dozen Jak 1 functions had been
compiled. Jak 1 has 10,601.

## The blocking mechanism, now measured

Recorded in `docs/AOT_EXECUTION_MODEL.md`. Desktop OpenGOAL executes GOAL out of
the GOAL heap: `game/runtime.cpp:160` maps it `PROT_EXEC|READ|WRITE`,
`game/kernel/jak1/klink.cpp:216` copies code segments into it, and
`game/mips2c/mips2c_table.cpp:663` writes x86 trampolines at runtime.

Measured facts (do not re-derive):
- `mmap` refuses `PROT_EXEC` here; the app reports `PROT_EXEC granted: NO`.
- Native code is NOT reachable via a 32-bit GOAL offset. arm64 reserves the low
  4 GiB and app `__TEXT` lands only 40-77 MiB above it, so a 128 MiB GOAL heap
  cannot fit below it. `__PAGEZERO` is linker-capped at 4 GB, and dyld places
  dylibs within ~150 KiB of the main image. Function objects must therefore
  carry a native pointer / tagged index.
- All four V3 relocation kinds (`common/link_types.h:11`) are DATA relocations,
  so static data can keep using the real linker at runtime. Only code must be
  ahead-of-time. This is a much smaller problem than "replace the linker".

## What now exists (all independently re-verified by the primary agent)

**Real kernel in the app.** `game/kernel/core/**` in the fork. The app
initializes real EE memory, real global/debug heaps, a real symbol table
(90 symbols, `s7 #x0018fe04`, 533,002 bytes used) and real type bootstrap, with
values byte-identical between the macOS ARM64 host and the M5 simulator. The
~1000-line synthetic-arena probe is deleted. Two real bugs were found and fixed:
`call_goal_on_stack` had no ARM64 branch and fell off the end returning garbage,
and `versions.cpp` broke fresh clones via a generated header.

**AOT C backend.** `goalc/aot/{CBackend.cpp,goal_c_runtime.h}`, drivers
`goalc-cbackend` and `goalc-cbackend-sweep`. Emits C from the GOAL IR so clang
is the ARM64 backend. Whole-game coverage measured across all 518 sources
(derived from `game.gp` via the make system, not globbing):

| stage | coverage |
| --- | --- |
| first pass | 5828/10601 (54.98%) |
| after r13 process register | 8760/10601 (82.63%) |

All 518 generated files compile clean for `arm64-apple-ios15.0`.

**Remaining blockers:** `rlet` on `rsp` 1059 (needs the AOT stack model
decision — the single biggest lever), `.blend.vf` 545, `.pcpyld` 188, lane ops
~49, and **3 genuinely fundamental functions** (`.push`/`.pop`/`.add` in GOAL's
cooperative-thread asm, which manipulate the real machine stack pointer;
lowering them to arithmetic compiles and is SILENTLY WRONG — keep them failing).

**Real game data.** 4.8 GB under `/Users/zach/Developer/OS_Projects/GOALPad/Jak1/`
(outside every checkout), validated by OpenGOAL's own extractor as Black Label
NTSC-U SCUS-97124. 28 CGO/DGO, 26 fr3. Pipeline documented in
`docs/setup/jak1-data-pipeline-macos-arm64.md`. Note its GOAL code is x86 —
`goalc` hardcodes `InstructionSet::X86`. Assets are architecture-independent.

**Metal renderer.** Apple runs GL 4.1, not 4.3, with zero compute/SSBO/geometry
shaders, so the gap is small. Direct Metal backend behind `GfxRendererModule`;
stage 2 adds per-frame command buffers, offscreen target + letterbox present
pass, a PSO cache, and build-time MSL (no runtime shader compilation — signing
clean). `send_chain` is still an honest no-op; no game content renders.

## Branches (OpenGOAL fork worktrees under /private/tmp/GP-*)

`goalpad/play-cbackend` (compiler), `goalpad/play-iosruntime` (kernel, pinned as
`e2d9aa2a`), `goalpad/play-renderer` (Metal, `f95d668a3`),
`goalpad/play-datapipe` (docs), `goalpad/play-exec` (kernel+compiler merged, the
execution track). Parent `feat/ipados-native-boot` had 5 unpushed commits.

## Honest limits

82.63% COMPILES; only `gcommon.gc` and a process fixture are proven to RUN. The
other 516 files are compile-proven, not correct-proven. Nothing has been linked
together, so cross-file symbols and the static/relocation tables are
unexercised. No GOAL code has executed through the real runtime yet. No physical
device has been touched. Coverage percentages are not progress toward playable
on their own.

## Next tasks, in value order

1. **Decide the AOT stack model** — do AOT GOAL functions keep running on
   GOAL-memory stacks? Unblocks 1059 functions. Entangled with the execution
   track; do not decide it blind.
2. **Execute real GOAL through the real runtime** (branch `goalpad/play-exec`).
   Expect trouble in cross-file linking and relocation.
3. Retire the dead hand-written emitter (`goalc/emitter/IGenARM64.*`, ARM64
   lowering in `IR.cpp`, golden-byte tests) and the now-unreferenced app
   artifacts `GOALPadAOTExportRegistry.cpp`, `GOALPadGoalStateWrapper.s`,
   `GOALPadAOTWorkload.cpp`, `Generated/*.s`. Then delete the x86 emitter.
4. Renderer stage 3: TexturePool/TextureUploadHandler on `MTLTexture`.

Require behavioral tests with mutation checks on compiler work. Emit counts are
not evidence of correctness.

---

# Checkpoint 23: Jak 1 is playable

Date: 2026-08-01. Supersedes Checkpoint 22.

## State

**The game plays.** On macOS, `goalpad-play` runs the real engine driving the
Metal renderer: title screen, progress menu, new game, Sandover Village,
walking, jumping, swimming, with a **DualSense over SDL including rumble**, and
music plus sound effects. On the iPad Pro M5 simulator, the SwiftUI app boots
the real kernel, loads the player's DGOs, runs `kernel_dispatcher`, and plays
audio — the renderer link is the last piece before it shows picture.

| Piece | State |
| --- | --- |
| Compiler | 10595 AOT C + 7 native ARM64 routines, 0 untranslated |
| Runtime | Full engine loop, real DGO/STR/ramdisk RPCs, level heaps |
| Renderers | sky, direct, sprite, tfrag/tie/shrub, ocean, merc, eyes, Generic2, shadow; **0 skipped bucket bytes** |
| Audio | Sequenced music + SFX; streamed VAG (dialogue) in progress |
| Input | Pad seam with no windowing dependency; SDL host + GameController on iPad |
| macOS host | `goalpad-play` — this IS the Mac build; no SwiftUI needed |
| iPad app | Shell complete; boots engine + audio; renderer link in flight |

## Architecture that settled

One shared core, two thin hosts. `game/kernel/core/` (no SDL, no windowing, no
input, no audio backend) plus the Metal renderer behind `GfxRendererModule`;
`gfx_host.{cpp,h}` is the host-agnostic glue. `goalpad_play.cpp` is the macOS
host and the worked example; `GOALPad.app` is the iPadOS host. Seams:
`goal_pad_set_state`, `goal_sound_pull_audio`, `goal_kernel_core_set_data_directory`.

## Branches (fork: zschwendi/jak-pad)

`goalpad/play-fusion` (everything + the live host), `play-exec` (runtime),
`play-renderer` (all renderers), `play-r-extra` (eyes/Generic2/shadow/envmap),
`play-audio`, `play-cleanup` (x86 + dead emitter removed, -11,521 lines).
Parent: `feat/ipados-native-boot`.

## Open bugs, from real play

- Jak collapses to a plane while rotating on Y — suspect bone-matrix `std140`
  layout in the merc shader. Being fixed with a Y-rotation sweep regression test.
- World/camera and sprite jitter when stationary — suspect the DMA chain
  snapshot racing the game thread.
- **`TexturePool` data race** — it does NOT lock internally; callers must hold
  `pool.mutex()` (see `Loader.cpp:341,538,635,698`). The game thread's
  `texture_relocate` races the render thread's level loading. Do not hold the
  lock across `waitUntilCompleted`.
- Streamed VAG dialogue not implemented.
- Level transitions beyond title→village1 unexplored.

## Deferred, counted

TIE wind, DepthCue, sprite distort/glow, merc blerc/mod-vtx, ocean-near
geometry (no capture near water), and the duplicate `.fr3` parse between the
background and merc level pools.

## Housekeeping

**Never put Claude attribution in git** — no `Co-Authored-By`, no "Generated
with Claude Code", and never author or commit as `Claude`. Every commit is
authored AND committed as `zephyrstudiosllc <zschwendi@zephyrstudios.dev>`, the
repo's configured identity. The project's own `(AI-assisted)` suffix stays.

Pending scrub, to run once the in-flight agents land. Three separate fixes:
1. rewrite author and committer to `zephyrstudiosllc <zschwendi@zephyrstudios.dev>`
   on all commits — **16 are currently authored as `Claude`** (6 parent, 10 in
   the fork range);
2. strip the `Co-Authored-By: Claude ...` trailer — ~42 commits;
3. remove any other Claude mention from messages and bodies.

Bound the rewrite to OpenGOAL commits at or after `9eecb9c3` so upstream keeps
its SHAs, and remap the parent's submodule gitlinks or they will dangle.
Backups: `/private/tmp/goalpad-backup/`.

macOS crash dialogs were disabled for this session
(`defaults write com.apple.CrashReporter DialogType none`); revert with
`defaults delete com.apple.CrashReporter DialogType`.

---

# Checkpoint 24: the iPad draws the game

Date: 2026-08-01. Extends Checkpoint 23; nothing in it is superseded.

Parent commit `df69d1b`, branch `feat/ipados-native-boot`. Submodule pinned to
`d0794462dbe1a87d427568e133f9b6c499de6dd1` on `goalpad/play-fusion`.

## State

**The iPad app shows the game.** On the iPad Pro 11-inch (M5) simulator
(`96C5C21A-B925-4213-82A3-90DCB8518339`), `GOALPad.app` boots Jak 1, runs its
frames and draws them with OpenGOAL's Metal renderer: the title screen with the
logo, the sky, the ocean and Sandover Village, at a sustained 60 fps. The
placeholder blue box is gone.

Measured over ~50 s of the title sequence: 600 dispatcher frames every
10.00-10.05 s with 599 of every 600 presented; 2915 DMA chains sent, 2915 drawn,
0 dropped; 285 draw calls and 485,590 triangles in the last frame; drawable
2420x1668, internal 1280x960, draw region 2224x1668; level art `title+village1`
loaded with 0 failures; audio still 517632/517632 frames at 48 kHz.

Screenshots: `/private/tmp/goalpad-ipad-shots/jak1-title-ipad-sim.png` and
`jak1-title-ipad-sim-readout.png`.

## How it is wired

`GOALPad/Native/GOALPadMetalHost.mm` is the iPad's `goalpad_play.cpp`: it fills
in the `goal_gfx_host` table from `game/kernel/core/gfx_host.h` and owns the
`MetalRenderer`, the `TexturePool`, the `FixedChunkDmaCopier` and the level-art
loading. `GOALPadGameBoot.cpp` starts it and installs the seam before the first
DGO load. `metal_pipeline.mm` is not compiled — it is the SDL window — but the
renderer under it is, plus 61 other files mirroring `goalpad-metal-gfx`.

**Threading: one thread does everything.** The GOAL frame, the texture calls,
the level loads and the render are the main thread inside one `CADisplayLink`
tick, so the `TexturePool` race in Checkpoint 23's open-bugs list cannot happen
here — there is no second thread. `syncv` returns immediately (the display link
is the clock) and `__pc-set-levels` loads synchronously where the game asked.
Anything that later moves the engine off the main thread has to take
`pool.mutex()` and re-read that section of `docs/BUILDING.md` first.

Shaders are compiled by a build phase with `xcrun metal` and embedded as a byte
array; nothing is compiled on the iPad. The signed generic-iOS Release build is
thin arm64, 26,466,656 bytes, SHA-256
`8adcabf623df9c4d8dde1bc7ae51e88e56a235fb94a3102a54b564a772f379c6`, entitlements
unchanged (application-identifier, team-identifier, get-task-allow), no
writable-executable segment, no `newLibraryWithSource:`.

## Next, in value order

1. Drive a controller past the title screen on the simulator and confirm
   gameplay draws, not just the title. Nothing here is evidence that it does.
2. Physical iPad: install, measure frame rate and thermals at 2x and 3x, and
   check memory as levels accumulate (they are never unloaded).
3. The unported buckets the renderer names once per run: `l0-tfrag-generic`,
   `l1-tfrag-generic`, `l1-shrub-generic`, `common-alpha-generic`, tfrag-trans
   inside the sky-blend buckets, sprite distort. Fork-side work, not iPad work.
4. Re-test backgrounding and returning now that the renderer holds drawables.

---

## Session end: 2026-08-01, ~02:00

Stopped mid-flight so the maintainer could sleep. Nothing is lost; everything
is committed and pushed.

### Where to pick up

1. **Physical iPad.** Still ungated — the maintainer must ask in the moment.
   Everything is staged: 26 MB signed bundle, entitlements correct, no
   writable-executable segment, touch controls landing. This is the only
   remaining unknown about real iPadOS behaviour.
2. **`wip/touch-controls` (parent repo) — DOES NOT COMPILE.** Touch controls
   were interrupted. Spec, as given by the maintainer and revised twice:
   stationary stick origin on the left half; swipe above the stick controls the
   camera (right analog stick); right-half swipes up/left/right = cross/square/
   circle; tap repeats the last swiped button; SELECT and START pills at bottom
   centre; everything hidden when untouched; **stick deflection also synthesizes
   D-pad presses** (edge-detect + auto-repeat) because the menus read the D-pad
   and the analog stick cannot navigate them. Missing piece: the bridge symbols
   (`GOALPadButton`, `GOALPadAnalogNeutral`, `GOALPadInputSetState`, …) are not
   exposed to Swift, which is why it does not build.
   **Constraint from the maintainer: iOS-layer changes only for now — nothing in
   the submodule, no GOAL source modding yet.**
3. **`goalpad/play-levels` (fork) — WIP, unvalidated.** Real level transitions
   beyond title→village1 have still never run. This is the biggest unknown for
   "beatable start to finish".
4. **Save games — never verified.** No run has ever saved and reloaded.
   `kmemcard` was on the excluded list when the portable library was carved out.
   If saving does not work the game cannot be completed. An agent had just
   started on this.
5. **Y-rotation collapse** (Jak goes 1-pixel-thin while turning) — still open.
   The bone-UBO-layout hypothesis is disproved with an injected-defect sweep.
   May share a root cause with the shiver, so re-check on current `play-fusion`
   first. F9/F10 in `goalpad-play` capture a `.gpdma` for replay.

### Landed this session

Playable on macOS and the iPad simulator. Shiver fixed (bones were read from
live EE memory while the chain was a snapshot — measured 162/500 frames stale,
now 0/500, frame rate unchanged). Ambient audio fixed (`scf-get-volume` stub
returned 0, muting 989snd's ambient group entirely). VAG dialogue works on
`goalpad/play-audio2-vag`, unmerged because the intro cutscene now plays out
and re-times the scripted gameplay test. README and both repo descriptions now
credit OpenGOAL.

### Machine state, restored

Simulators shut down. `com.apple.CrashReporter DialogType` deleted (crash
dialogs back to normal — it was set to `none` during the session). Stray
`goalpad-play` / `metal-proof` processes killed.

### Still pending

The attribution scrub. Script is ready and dry-run clean at
`…/scratchpad/scrub-attribution.sh` (`check` | `run`); scope is 16 commits
authored as Claude and ~42 carrying the trailer. Backups in
`/private/tmp/goalpad-backup/`. **Note `/private/tmp` does not survive a
reboot** — re-bundle before rebooting, or run the scrub first.

---

# Checkpoint 25: Mac Jak 1 bug sweep complete; Jak II data prepared

Date: 2026-08-01. Extends Checkpoint 24. Maintainer direction this session:
validate on macOS only (the iPad translation is treated as 1:1 — no simulator
runs), fix all Mac Jak 1 bugs, then bring up Jak II, then Jak 3/X (their data
is not on this device).

Submodule pin: `4788b64af` on `goalpad/play-fusion`. All work below is merged
there and validated by the full non-listener suite (63/63) plus scripted
windowed runs at 57.5-60 fps.

## What landed

- **Streamed VAG dialogue merged** (`play-audio2-vag`). The intro now plays
  out fully (~23,600 frames from new game to control). The scripted gameplay
  test re-keys off `target-hit-ground` (the warp drop onto Geyser Rock).
  Three ambient names (`EIA2`, `LOI2`, `FIBRTMIS`) are genuinely absent from
  this VAGDIR and are reported honestly.
- **x86 + dead-emitter cleanup merged** (`play-cleanup`, -11,522 lines) plus
  the data-pipeline doc (`play-datapipe`). One test removed with its subject
  (`goalc-aot-artifact-pair`).
- **Y-rotation collapse and stationary jitter: both no longer reproduce** —
  the Checkpoint 24 skeleton-snapshot fix was the shared root cause. Proven
  with a 141-consecutive-frame turn sweep, the committed 241-check rotation
  test, and pixel-diffed idle frames. No code change.
- **Save games work end to end** (`play-saves`). kmemcard was already
  compiled in; the port now sets a saves directory seam
  (`goal_kernel_core_set_saves_directory`), goalpad-play defaults to
  `<data-dir>/saves` (`--saves-dir` overrides). Proven: new-game slot write,
  manual SAVE GAME with double-bank rotation, fresh-process reload of the
  newer bank, corrupt-save and no-saves boots. The boot-test harness always
  redirects saves to a temp scratch dir so no test touches player saves.
  Not exercised: autosave from a power-cell pickup.
- **Real level transitions work** (`play-levels`). village1→beach walked
  through the stream culvert with the SENTINEL BEACH banner, and back.
  Root cause of the historic block: the `intro-start` continue point's
  `intro` flag suppresses `(-> *level* border?)`. With the intro now playing,
  border checks enable naturally (verified: `want training+village1`,
  "on a border", frame 23488). New tools in both hosts: `--warp` (any
  continue point), `--walk-to` autopilot, `--report-levels`; new CTests
  `jak1-level-boundary-test`, `jak1-level-tour-test`. GOAL level slots
  recycle correctly; RSS flat across crossings.
- **Eye rendering in texture buckets + sprite distort ported**
  (`play-buckets`). The "unported generic buckets" list in Checkpoint 24 was
  stale — those already route to MetalGeneric2. Characters now have composed
  eye textures; heat shimmer draws. 0 skipped bucket bytes; deterministic
  .gpdma before/after replays.

## In flight (branches, unmerged until validated)

- `goalpad/play-blerc` — merc blerc/mod-vtx facial morphs, the last named
  visual gap ("Metal merc: blerc/mod-vtx not ported").
- `goalpad/play-art-residency` — the Metal host keeps every visited level's
  art resident (~1.16 GB after four levels); eviction keyed to GOAL slots.
- `goalpad/play-jak2-sweep` — Jak II scoping: cbackend coverage over
  goal_src/jak2, kernel/renderer/sound deltas, attack order.

## Jak II data (prepared, outside all checkouts)

`/Users/zach/Developer/OS_Projects/GOALPad/Jak2/` — NTSC-U SCUS-97265 v2.01,
validated by the extractor (`-g jak2`). `iso_data/jak2` 4.1 GB;
`projdata/out/jak2/iso` 4.3 GB; `fr3/` 628 MB. Note: the extractor writes to
`iso_data/_temp` and errors if run without `-g jak2` (it defaults to jak1);
`buildinfo.json` had to be reconstructed (serial + ELF hash
18445016742498932084 from the extractor database) before `-d`/`-c` ran clean.

## Housekeeping

- The attribution scrub is staged as
  `../.goalpad-local/scrub-attribution-v2.sh` (the v1 script had an invalid
  filter-branch range and relied on a map file git deletes; v2 rebuilds and
  verifies the map from refs/original). History backups are durably copied to
  `../.goalpad-local/backup/*.bundle`. Run the scrub after in-flight branches
  land, then re-point /private/tmp worktrees and force-push.
- Dead historical worktrees/build trees under /private/tmp (~10 GB) were NOT
  deleted: the bulk removal was blocked by the permission classifier. Disk is
  at ~97%.
- jak1-gameplay-test now takes ~61 s (it plays the whole intro); suite total
  ~115 s.

---

# Checkpoint 26: Jak 1 polish integrated; the Jak 2 kernel boots

Date: 2026-08-01. Extends Checkpoint 25. Submodule pin: `f210265273e90d55a9bda5df4b7c898b25e0d9ba` on
`goalpad/play-fusion`. Full dual-game suite: 65/65.

## Landed since Checkpoint 25 (all merged into play-fusion, all validated)

- **Merc blerc/mod-vtx ported to Metal** (`play-blerc`). Pixel-proven by a
  new synthetic metal-proof test (weighted blend target shifts a quad);
  retail replays byte-identical where weights are zero. Open game-side gap:
  no retail frame ever sends nonzero weights — `pc-merc-blend-shape`
  returns false during cutscenes (suspect missing blerc-data on STR-streamed
  anims). Faces will not animate until that trigger is found. mod-vtx
  (texscroll/ripple) implemented but unvalidated against retail content.
- **Level-art eviction** (`play-art-residency`). Mirrors upstream Loader:
  180-frame grace, >=3 resident, one eviction/frame, TexturePool under
  pool.mutex(). Seven-level tour: loaded list converges to the wanted set,
  RSS bounded (peak 1.5 GB vs 2.0 GB before), return visits reload
  pixel-equivalent.
- **C backend sweep gained --game** (`play-jak2-sweep`).
- **Jak 2 kernel boots headless** (`play-jak2-kernel`): jak2 KERNEL.CGO
  (8 objects) loads through the AOT path, Symbol4 table + kernel version 2.0
  verified, kernel-dispatcher ran 100 frames; only `pc-prof` touched among
  machine stubs (loud). goal_src/jak2 got the same hard-fork thread-primitive
  rewrites as jak1, so **jak2 AOT coverage is 100%** (18,478 emitted + 7
  shared native routines; 0 failures across all 840 sources; all files
  compile for arm64). New per-game seam `kernel_game.h` +
  `kernel_game_jak{1,2}.cpp` (process field offsets are the only layout
  delta); jak2-kernel-core library, dgo_loader_jak2, jak2-data-boot-test,
  jak2-thread-switch-test. GOALPAD_JAK2_DATA_DIR points at the prepared data.
- **Full-system live proof on the merged head**: windowed run with sound
  through the whole intro to Geyser Rock — 60.0 fps, 16.68 ms +/- 0.01,
  0 late frames across 25,435; natural state chain through
  target-hit-ground into walking.

## Jak 2 next, in value order

1. Port/register the jak2 mips2c library (mips2c_jak2.cpp mirroring
   mips2c_jak1.cpp; jak2_functions TUs exist upstream). GAME.CGO currently
   stops honestly at object 67/465 (`texture` wants
   `adgif-shader<-texture-with-update!`).
2. Sound-RPC seam for jak2 (check-irx-version gate in gsound; different
   command enum; VAG multi-stream layer later).
3. Renderer lane: bucket table 70->327, then TextureAnimator (largest),
   etie envmap, Shadow2, Glow.
4. kmachine subset + kmachine_extras (37.6K, jak2-only GOAL<->C surface).

Scoping detail (coverage tables, kernel/renderer/sound deltas) is in the
Checkpoint 25 sweep report summary and /private/tmp/jak2-sweep-out.

---

# Checkpoint 27: Jak 2 GAME.CGO loads through the native mips2c seam

Date: 2026-08-01. Extends Checkpoint 26. Submodule pin:
`162442960bdf5ceec11532200b1a114d2cce2579` on `goalpad/play-fusion`.

## Integrated work

The interrupted `goalpad/play-jak2-mips2c` worktree was clean and contained
three complete commits. They are merged into `goalpad/play-fusion` by
`7b8bfd677222d5ec5fd239e834ef3757633ddcb2`:

- `a48706c3c49aafdc1160366090b5f15be91cff85` compiles the 28 existing Jak 2
  mips2c translation units into `jak2-kernel-core` and registers the 137 unique
  functions from upstream's Jak 2 table. Upstream names 138 entries because
  `method_33_sky_work` appears twice; the native registry intentionally adds it
  once.
- `d8ec459942bbbd7dcea259df70233f2ddb35022e` routes the remaining trans, post,
  and main-thread backup buffers through `PROCESS_STACK_SAVE_SIZE`. The first
  full GAME load measured a 336-byte subtitle2 suspension against the old raw
  256-byte buffer; the converted buffer is 1,280 bytes.
- `0c7ac0db1272fa45bda713103b9170ffc594bc53` calls
  `adgif-shader<-texture-with-update!` through the real name lookup, native
  trampoline, mips2c scratch stack, and `ExecutionContext`, then checks the
  resulting TEX0, TEX1, and MIPTBP1 words for a synthetic texture.
- `162442960bdf5ceec11532200b1a114d2cce2579` documents the current Jak 2
  headless boundary and makes explicit that `--with-game` remains an
  exploratory, non-CTest mode.

## Validation

All commands ran from `/private/tmp/GP-audio` before the branch was merged.

- `cmake --build build/Release/bin -j 4 --target jak2-data-boot-test` — passed;
  the existing build was current (`ninja: no work to do`).
- `GOALPAD_JAK2_DATA_DIR=/Users/zach/Developer/OS_Projects/GOALPad/Jak2/projdata/out/jak2 ctest --test-dir build/Release/bin -R '^jak2-data-boot-test$' --output-on-failure`
  — passed 1/1.
- `./build/Release/bin/game/jak2-data-boot-test --data-dir /Users/zach/Developer/OS_Projects/GOALPad/Jak2/projdata/out/jak2 --frames 100 --with-game`
  — passed. KERNEL.CGO loaded 8/8 objects, the behavioral mips2c check passed,
  GAME.CGO loaded 465/465 objects, and the kernel dispatcher completed 100
  frames.
- `GOALPAD_JAK1_DATA_DIR=/Users/zach/Developer/OS_Projects/GOALPad/Jak1/projdata/out/jak1 GOALPAD_JAK2_DATA_DIR=/Users/zach/Developer/OS_Projects/GOALPad/Jak2/projdata/out/jak2 ctest --test-dir build/Release/bin --output-on-failure -j 1`
  — passed 65/65 in 113.88 seconds.
- `cmake --build build/ios-kernel-core -j 4 --target jak2-kernel-core` — passed;
  the static library and all 28 Jak 2 mips2c translation units compiled for
  `arm64` with the `iphoneos` SDK. Existing format/deprecation warnings remain.
- `git diff --check goalpad/play-fusion...goalpad/play-jak2-mips2c` — passed.

No simulator or physical device was accessed. No renderer, controller, audio,
streaming, title-screen, gameplay, or physical-iPad behavior is established by
this checkpoint.

## Expected headless diagnostics

The exploratory run prints `Game subtitle2 heap overrun!` once per dispatcher
frame. This is not an observed memory overwrite. The reporting-mode sound RPC
stubs return zero without replacing the requested STR transfer size;
`str-load-status` therefore reports the full requested size and the original
GOAL subtitle heap guard fires. Subtitle text remains unloaded and retries once
per frame. This is part of the missing sound-RPC seam, not a reason to weaken
the guard or suppress the diagnostic.

## Next Jak 2 task

Implement the smallest Jak 2 sound-RPC handshake needed for
`check-irx-version`, with a focused behavioral test and unchanged Jak 1
behavior. Do not broaden this into VAG multi-stream audio, rendering, or
gameplay work in the same checkpoint.

---

# Checkpoint 28: Jak 2 accepts the sound-loader IRX 4.0 handshake

Date: 2026-08-01. Extends Checkpoint 27. Submodule pin:
`7e69774a0c91ff804f165df574f919afc6e7b826` on `goalpad/play-fusion`.

## Integrated work

The focused branch `goalpad/play-jak2-sound-rpc` landed as
`711300ae68218237a15798193e9c8780d25c8b9a` and is merged into fusion by
`7e69774a0c91ff804f165df574f919afc6e7b826`.

- `sound_rpc_jak2.cpp` replaces only Jak 2's reporting stubs for `rpc-call`
  and `rpc-busy?`. Loader channel 1, command 16 receives the exact upstream
  80-byte message, replies synchronously with IRX 4.0, and retains the EE
  sound-info address. All other channels, commands, and malformed buffers
  remain loud missing-machine diagnostics.
- The eight-register wrapper preserves the GOAL stack-argument ABI. EE spans
  are checked before access; malformed sizes, nulls, end-crossing spans, and
  out-of-range addresses do not touch memory.
- SIF semantics are preserved: a separate EE send buffer stays unchanged and
  only the receive buffer gets the IOP-side response. The game's in-place
  send/receive alias still works.
- `jak2-sound-rpc-test` calls the actual installed GOAL function objects and
  covers separate and aliased buffers, IRX 4.0, retained `ee_addr`, complete
  response copying, canaries, pre-init installation, unsupported channels and
  commands, malformed sizes, and address boundaries without retail data.
- `jak2-data-boot-test --with-game` now requires exactly one successful
  version request and verifies that the retained address equals GOAL's
  `*sound-iop-info*` value.

An independent patch review caught the initial separate-buffer implementation
writing back into both EE buffers. That mismatch was corrected before the
checkpoint was committed, and the focused, real-data, full-suite, and iOS
validations below were rerun against the corrected implementation.

## Validation

All final commands ran from `/private/tmp/GP-audio`.

- `cmake --build build/Release/bin -j 4 --target jak2-sound-rpc-test jak2-data-boot-test`
  — passed. The new seam, focused test, and the full 840-unit Jak 2 AOT boot
  bundle compiled and linked.
- `ctest --test-dir build/Release/bin -R '^jak2-sound-rpc-test$' --output-on-failure`
  — passed 1/1 after the separate-buffer and address-boundary corrections.
- `GOALPAD_JAK2_DATA_DIR=/Users/zach/Developer/OS_Projects/GOALPad/Jak2/projdata/out/jak2 ctest --test-dir build/Release/bin -R '^jak2-data-boot-test$' --output-on-failure`
  — passed 1/1.
- `./build/Release/bin/game/jak2-data-boot-test --data-dir /Users/zach/Developer/OS_Projects/GOALPad/Jak2/projdata/out/jak2 --frames 100 --with-game`
  — passed. KERNEL.CGO loaded 8/8, GAME.CGO loaded 465/465, GOAL printed
  `IRX version 4.0`, the retained info block was `#x138cbd0`, and the kernel
  dispatcher completed 100 frames.
- `GOALPAD_JAK1_DATA_DIR=/Users/zach/Developer/OS_Projects/GOALPad/Jak1/projdata/out/jak1 GOALPAD_JAK2_DATA_DIR=/Users/zach/Developer/OS_Projects/GOALPad/Jak2/projdata/out/jak2 ctest --test-dir build/Release/bin --output-on-failure -j 1`
  — passed 66/66 in 109.22 seconds.
- `cmake --build build/ios-kernel-core -j 4 --target jak1-kernel-core jak2-kernel-core`
  — passed for the iPhoneOS configuration. Existing unrelated format and
  switch warnings remain.
- `xcrun lipo -info build/ios-kernel-core/libjak1-kernel-core.a` and
  `xcrun lipo -info build/ios-kernel-core/libjak2-kernel-core.a` — both report
  non-fat `arm64` archives.
- `xcrun nm -g build/ios-kernel-core/libjak2-kernel-core.a | rg 'goal_jak2_sound_rpc'`
  — exports both `goal_jak2_sound_rpc_install` and
  `goal_jak2_sound_rpc_stats_get`.
- `git diff --cached --check` — passed before the focused commit.

No simulator or physical device was accessed. This checkpoint proves a
headless host handshake and an iPhoneOS archive build, not sound playback,
rendering, title-screen behavior, gameplay, or physical-iPad execution.

## Remaining boundary and next task

The real GAME probe now passes the wrong-IRX-version gate, but later valid
sound traffic still reports loudly: additional loader messages, player RPC,
busy queries on other channels, STR, sound-info frame updates, banks, streams,
and audio output are unimplemented. The repeated `Game subtitle2 heap overrun!`
diagnostic is unchanged because channel 4 STR still returns through the
reporting stub without a real transfer size.

Before implementing another sound subsystem, capture and classify the first
post-handshake RPC calls by channel, function, sizes, and command. Use that
evidence to select one bounded protocol seam with a synthetic behavioral test;
do not jump directly to the full desktop IOP or VAG stack.

## Context-clear resume note

The maintainer requested a context reset immediately after Checkpoint 28 and
asked that work continue until Jak 1 is ready to play on the physical iPad Pro.
A persistent goal records that outcome. The physical device `Z iPad Pro` must
still not be accessed until the maintainer explicitly authorizes that install
and test in the current request. Current evidence is only a signed-compatible
arm64 iPhoneOS static-library build; it is not a playable iPad app claim.

Clean resume state:

- Parent `feat/ipados-native-boot`: `cb4bbe3e95177595c3f2f2ca863f85d4751e6334`.
- Fusion `/private/tmp/GP-fusion`: `goalpad/play-fusion` at
  `7e69774a0c91ff804f165df574f919afc6e7b826`.
- Next worktree `/private/tmp/GP-audio`: clean branch
  `goalpad/play-jak2-str-file`, based on the fusion head, with no code changes.
- A documentation subagent is creating `HowToPortDecompsToApple.md`: a generic,
  phase-gated Apple-port workflow whose worked example is the proven Jak 1
  path. Review and commit it before starting overlapping parent-repo edits.

The post-handshake trace is now concrete. GAME.CGO sends four fire-and-forget
loader-channel 1 command-2 bank requests (`common`, `empty0`, `empty1`,
`empty2`) after the successful version query. They must remain visibly
unimplemented until real bank state exists. The first dispatcher frame then
sends channel 4, function 0, async 1, a 64-byte request with a 32-byte aliased
reply: section `-1`, max length `#x96000`, destination `#x01c0a340`, basename
`0subti2.TXT`. The reporting stub leaves result 666 and the offered max length
in place, so GOAL mistakes the request for a complete 614,400-byte read and
prints the false heap-overrun once per frame.

The next bounded Jak 2 implementation is therefore a synchronous ordinary-file
STR channel-4 seam. Validate the exact 64-byte request/32-byte reply wire format,
only read the transmitted 32 basename bytes, bounds-check the EE destination,
load `iso/<uppercase basename>` from the configured user-data directory, reply
with result 0 plus the actual length or result 1 plus zero length, and return
idle for `rpc-busy?(4)`. Keep chunked sections, bank loading, player RPC,
streamed playback, and fabricated sound-info values out of that first slice.
Use a synthetic file test, then the real headless GAME probe, full host suite,
and both iPhoneOS archives; no physical device is needed for this checkpoint.

Maintainer priority after the context reset is Jak 1 physical-iPad readiness,
not immediate continuation of the parked Jak 2 branch. Resume by auditing the
current Swift/Objective-C++ iPad host against Checkpoint 24, rebuilding the
approved M5 simulator and a generic signed iOS Release, and listing the exact
remaining gap between the proven simulator title screen and a playable
physical-device run. Do not install or launch on `Z iPad Pro` during that audit.
Once source, signing, app-container data, rendering, input, audio, lifecycle,
and resource limits are ready for the physical gate, notify the maintainer and
ask for explicit permission to perform the install and run. The clean
`goalpad/play-jak2-str-file` worktree remains the exact Jak 2 resume point after
that higher-priority Jak 1 device gate.

---

# Checkpoint 29: current-head Jak 1 app installed with complete data on Z iPad Pro

Date: 2026-08-01. Parent base `9e35203` on `feat/ipados-native-boot`; OpenGOAL
submodule `7e69774a0c91ff804f165df574f919afc6e7b826` on
`goalpad/play-fusion`. The maintainer explicitly authorized physical-device
build, install, launch, and validation in the current request.

## Current-head Xcode repair

The first current-pin Release build reached the final arm64 link and failed
because the manually maintained Xcode source list had drifted behind the
OpenGOAL Jak 1 kernel-core and Metal targets. The focused parent patch adds the
nine existing translation units now required by those targets:

- `game/sce/libscf.cpp`
- `game/kernel/core/kernel_game_jak1.cpp`
- `game/kernel/core/vag_stream.cpp`
- `game/kernel/core/mips2c_jak1.cpp`
- `game/graphics/pipelines/metal/metal_eye_renderer.mm`
- `game/graphics/pipelines/metal/metal_generic2.mm`
- `game/graphics/pipelines/metal/metal_shadow_renderer.mm`
- `game/graphics/opengl_renderer/Shadow_PS2.cpp`
- `game/graphics/opengl_renderer/ShadowVu.cpp`

The build phase and `Scripts/compile-metal-shaders.sh` now compile the existing
`eye.metal`, `generic.metal`, and `shadow.metal` sources. `metal_pipeline.mm`
remains intentionally excluded: `GOALPadMetalHost` replaces that desktop SDL
display/event owner with `CAMetalLayer` and the app display link.

## Validation and physical install

- `plutil -lint GOALPad.xcodeproj/project.pbxproj` — passed.
- `sh -n Scripts/compile-metal-shaders.sh` — passed.
- `git diff --check` — passed.
- `xcodebuild -project GOALPad.xcodeproj -scheme GOALPad -configuration Release -destination 'id=6A4111AB-1663-508A-98D9-F0C1A9EA7863' -derivedDataPath /private/tmp/GOALPad-current-device -jobs 4 -allowProvisioningUpdates ENABLE_PREVIEWS=NO ENABLE_DEBUG_DYLIB=NO -quiet build` — passed after the focused source-list repair. Existing upstream conversion/uninitialized warnings remain.
- The result is a thin arm64 `iPhoneOS` app, bundle
  `com.zephyrstudiosllc.GOALPad`, minimum iOS 26.5. Its parsed entitlements are
  only the development application identifier, team identifier, and
  `get-task-allow`. `__TEXT` is RX rather than writable/executable. Local
  `codesign --verify --deep --strict` could not establish the certificate trust
  chain (`CSSMERR_TP_NOT_TRUSTED`), but CoreDevice accepted the embedded
  signature and installed the app successfully.
- `xcrun devicectl device install app --device 6A4111AB-1663-508A-98D9-F0C1A9EA7863 /private/tmp/GOALPad-current-device/Build/Products/Release-iphoneos/GOALPad.app` — passed; existing app-container data was preserved.
- The container was empty. `xcrun devicectl device copy to` transferred the
  maintainer's prepared local `iso` and `fr3` directories to
  `Documents/Jak1`. A recursive device-side listing verifies 321 `iso` files,
  26 `fr3` files, 1,628,186,274 bytes, and exactly one each of `KERNEL.CGO` and
  `GAME.CGO`.

The app and complete data are now installed on physical **Z iPad Pro**. Three
remote launch attempts reached SpringBoard but were denied because the device
was locked. This is not an app crash or signature/install failure. Physical
Jak 1 boot, rendered title screen, controller, audio, and gameplay remain
unvalidated until the device is unlocked and the installed app is launched.

The next executable step is only: unlock **Z iPad Pro**, launch
`com.zephyrstudiosllc.GOALPad`, capture the boot/runtime evidence, and test a
controller past the title screen. Do not resume Jak 2 before recording that
physical Jak 1 result.

---

# Checkpoint 30: iPad host consumes each frame with its matching skeleton

Date: 2026-08-01. Parent base `8c7bbfe` on `feat/ipados-native-boot`; OpenGOAL
remains clean and pinned at `7e69774a0c91ff804f165df574f919afc6e7b826`.

The maintainer launched Checkpoint 29 manually and reported playable Jak 1 on
physical **Z iPad Pro**, with violent camera/world shiver while Jak stood still.
This is user-reported physical runtime evidence; no agent accessed the device
during this checkpoint.

## Root cause

The known fix is already in the OpenGOAL pin: `8543c0cad` is an ancestor of the
current commit and measured stale live-bone data on 162/500 frames before the
fix and 0/500 after it. Its wait lives in desktop-only `metal_pipeline.mm`,
which the Xcode target intentionally excludes. The app instead compiled
`GOALPadMetalHost.mm`, whose `send_chain` copied only DMA-tagged chunks and
deferred drawing until after the whole GOAL dispatcher returned. Merc resolves
bone pointers from live EE memory outside that compact copy, so the deferred
iPad draw could combine an older chain with a newer skeleton. The earlier
same-thread/same-tick argument was insufficient; the chain must be consumed
before GOAL continues past its send.

## Focused iPad adaptation

- `GOALPadRenderSurface.beginFrame` validates and arms the current layer and
  geometry before GOAL runs; `endFrame` clears that one-tick context and counts
  a presentation.
- `host_send_chain` now copies and renders synchronously on the armed frame
  thread. It returns to GOAL only after Merc has copied the matching live bone
  matrices into renderer-owned buffers.
- A send outside an armed frame, including boot-time display traffic, is
  dropped and counted rather than deferred with stale live pointers. A
  wrong-thread send is also rejected and reported once.
- `GameSession.tick` does not advance GOAL when no drawable surface can be
  armed. The active order is now `begin -> input -> GOAL/send/render -> end ->
  rumble` with no condition-variable wait and therefore no same-thread
  deadlock.
- `docs/BUILDING.md` now describes the actual ordering and the reason for it.

## Validation

- `git diff --check` — passed.
- `plutil -lint GOALPad.xcodeproj/project.pbxproj` — passed.
- `xcodebuild -quiet -project GOALPad.xcodeproj -scheme GOALPad -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/GOALPad-shiver-mac CODE_SIGNING_ALLOWED=NO -jobs 4 build` — passed; existing upstream warnings remain.
- `xcodebuild -quiet -project GOALPad.xcodeproj -scheme GOALPad -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/GOALPad-current-device -jobs 4 -allowProvisioningUpdates ENABLE_PREVIEWS=NO ENABLE_DEBUG_DYLIB=NO build` — passed; existing upstream warnings remain.
- The Release result is a signed thin `arm64` iPhoneOS executable. Parsed
  entitlements are the development application identifier, team identifier,
  and `get-task-allow`.
- The approved M5 simulator build was attempted with destination
  `96C5C21A-B925-4213-82A3-90DCB8518339` and failed in unchanged pinned source:
  `metal_renderer.mm` calls
  `presentDrawable:afterMinimumDuration:`, which the iPhone Simulator 26.5 SDK
  does not expose. `git blame` attributes both calls to OpenGOAL commit
  `aae65e76bc`, predating this parent-host patch. This is a current-pin
  simulator compatibility regression, not a failure caused by the synchronous
  iPad host change. The simulator remained shut down.

## Physical update-install and relaunch

The maintainer then explicitly requested a physical relaunch. `Z iPad Pro` was
connected as `6A4111AB-1663-508A-98D9-F0C1A9EA7863`.

- `xcrun devicectl device install app --device 6A4111AB-1663-508A-98D9-F0C1A9EA7863 /private/tmp/GOALPad-current-device/Build/Products/Release-iphoneos/GOALPad.app` — passed as an update-install of bundle `com.zephyrstudiosllc.GOALPad`; the existing app container was not uninstalled.
- `xcrun devicectl device process launch --device 6A4111AB-1663-508A-98D9-F0C1A9EA7863 --terminate-existing --activate com.zephyrstudiosllc.GOALPad` — passed and launched the updated app in the foreground.

No debugger or console was attached. Runtime acceptance remains the
maintainer's direct observation: idle in one controllable area for at least 60
seconds, turn through a full circle, and idle again. Accept only when Jak, the
world, and the camera no longer shiver, sent/rendered counts advance together,
and no new chain drops accrue after boot.

---

# Checkpoint 31: physical Jak 1 camera A/B and paused Merc deformation hunt

Date: 2026-08-01. This is an intentionally uncommitted context-clear
checkpoint. Parent branch `feat/ipados-native-boot` is at `8c7bbfe`, three
commits ahead of its remote. Nested OpenGOAL branch
`goalpad/ipad-demo-pacing` is at
`7e69774a0c91ff804f165df574f919afc6e7b826`. Preserve every dirty file listed
below; do not reset, clean, or replace either checkout.

The maintainer explicitly authorized continuing signed update-installs and
runtime testing on physical **Z iPad Pro** during this session. Device ID was
`6A4111AB-1663-508A-98D9-F0C1A9EA7863`; bundle ID is
`com.zephyrstudiosllc.GOALPad`. Every install was an update-install, never an
uninstall, so `Documents/Jak1` and saves remained in the existing container.
After a context clear, follow the current physical-device policy and obtain a
fresh explicit device-test request if the maintainer's resume message does not
itself authorize another install or launch.

## Last installed and physically observed build

The app currently on the iPad came from:

`/private/tmp/GOALPad-fixedtick-device/Build/Products/Release-iphoneos/GOALPad.app`

Its executable SHA-256 is
`7b6af06f70ef29ff0befbe9b5a6e8da116478798ac56e98655c4e2adef0d3c56`.
It is thin arm64, bundle `com.zephyrstudiosllc.GOALPad`, TeamIdentifier
`D2YYJ54Q6V`. The generic iOS Release build exited 0, CoreDevice update-install
exited 0 at 13:25, launch with `--terminate-existing` exited 0, and a later
process query found the app still alive as PID 6558. Local strict codesign
verification continued to report the already-known untrusted local certificate
chain, while CoreDevice accepted the signature.

That installed build combines two iOS-only runtime experiments in
`GOALPadGameBoot.cpp`:

- It sets `*use-new-bones*` to Jak 1 false after GAME.CGO loading and before
  `play`, selecting OpenGOAL's already-linked MIPS2C `bones-mtx-calc` instead
  of the AOT `new-bones-mtx-calc-asm`.
- Immediately before each `kernel-dispatcher` call it resets
  `*timer-reset-value*` from `__read-ee-timer >> 9`. This excludes the outside
  CADisplayLink wait from the next `display-frame-start` measurement, but a
  dispatcher/render workload above about 1.3 frames can still produce
  `time-ratio == 2`.

Exact final iOS build command for that installed artifact:

```sh
xcodebuild -quiet -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-fixedtick-device \
  -jobs 4 -allowProvisioningUpdates ENABLE_PREVIEWS=NO \
  ENABLE_DEBUG_DYLIB=NO build
```

The corresponding arm64 macOS Debug build also passed with
`/private/tmp/GOALPad-fixedtick-mac` and `CODE_SIGNING_ALLOWED=NO`. Existing
upstream warnings remained.

## Physical result

Maintainer observations, in order:

- The earlier MIPS2C-only A/B initially made Jak look volumetric through a full
  rotation. Its executable is preserved at
  `/private/tmp/GOALPad-mips2c-bones-device/Build/Products/Release-iphoneos/GOALPad.app`
  with SHA-256
  `e185654142f2518a1546975b91880729ee6e8a4c4c6f67caf683ce91ede483ca`.
- The fixed-timer build removed the worst violent camera shake. Hiding the
  diagnostics overlay improves cadence but does not remove the root problem.
- With no controller input, the remaining camera motion is a slower
  left/right sway roughly once per second, like alternating right-stick input.
  The maintainer verified the raw input readout is not oscillating, ruling out
  controller drift or spoofed input.
- Flat Jak returned despite the MIPS2C selector. The deformation is a stable
  plane: at an edge-on view Jak becomes a vertical line of pixels; changing
  Jak's facing direction changes the apparent thickness, and the camera can
  rotate around that proportionate result.
- Jak also becomes briefly large or balloon-like for several frames,
  especially during rapid camera rotation.

These observations separate the remaining work into two bugs. The slow camera
sway is the game's idle auto-centering spring reacting to occasional ratio-2
simulation steps. Flat/balloon Jak is bad or incomplete Merc skinning state,
not controller input and not merely drawable presentation cadence.

## Verified source findings

- `*use-new-bones*` is not being reset by `play` or level loading. Jak 1 has
  only its top-level true initialization and the branch read in `bones.gc`.
  `bones.o` is only in ENGINE.CGO/GAME.CGO, already-loaded AOT objects do not
  rerun top level, and the generated AOT rereads the live symbol slot each call.
- The false branch passes `(output, joints, bones, count, camera)` correctly.
  The iPad MIPS2C seam forwards the fifth native argument into MIPS `t0`, and
  the translated bones function reads its camera rows from `t0`.
- MIPS2C is therefore not an independent end-to-end baseline. It shares the
  joints, bones, camera, output allocation, seven-qword palette layout, packet
  pointers, and Metal consumer with the AOT producer.
- The current synchronous host and Metal stream-buffer lifetime do not support
  an ordinary CPU-copy/GPU-read race: `host_send_chain` consumes each chain
  before GOAL resumes, the renderer waits for the preceding GPU command buffer,
  and each flush receives its own stream range.
- Multiple chains are serialized, but every chain currently acquires a
  drawable and schedules it at the same display-link target time. On resume,
  record the overlay's exact `tick chains 0/1/>1` and `max` values before
  deciding whether multi-chain presentation is involved. `last merc 2/3`
  describes only the last chain and is not sufficient evidence.
- Metal initializes the 128-entry skeleton palette to zero and fills only the
  packet's supplied slots. It does not verify that positive-weight vertices
  reference only supplied slots. Its bad-pointer message claims an identity
  fallback, but the implementation actually leaves a zero matrix. That is a
  source-proven flattening hazard, though it does not yet explain ballooning.

## Unbuilt fixed-step experiment

Immediately before the clear request, a narrower production-shaped camera fix
was started but not generated, built, installed, or tested:

- `OpenGOAL/goal_src/jak1/engine/draw/drawable.gc` defines default-false
  `*pc-fixed-step*` and forces the local `time-ratio` to 1 immediately before
  `set-time-ratios` when that flag is true.
- `GOALPad/Native/GOALPadGameBoot.cpp` verifies `*timer-reset-value*`, caches
  its slot, verifies `*pc-fixed-step*`, and enables the flag only under
  `TARGET_OS_IOS` after `play` and before the first gameplay dispatcher.

The exact generation command was started:

```sh
Scripts/generate-jak1-aot.sh /private/tmp/GOALPad-aot-host
```

It configured successfully and compiled through about 240 of 438 host-tool
steps, then was deliberately interrupted with Ctrl-C for the requested context
clear. Exit was 130. The sweep itself had not run, so
`Generated/jak1-aot/drawable.c` does not yet contain `*pc-fixed-step*`. No app
build or physical install contains this change. The incremental resume command
is exactly the same command above; it should reuse the partial host build.

## Exact next executable sequence

1. Reread `AGENTS.md`, `docs/PROJECT_OVERVIEW.md`, this checkpoint, and the
   current Git status. Preserve all dirty work.
2. Finish `Scripts/generate-jak1-aot.sh /private/tmp/GOALPad-aot-host` and verify
   the generated `drawable.c` contains `*pc-fixed-step*` and the ratio-one
   branch.
3. Run `git diff --check` in both checkouts. Build arm64 macOS Debug and generic
   signed iOS Release into new `/private/tmp` derived-data directories.
4. With fresh explicit physical authorization, update-install and relaunch the
   fixed-step A/B. Test diagnostics hidden: rotate for 10 seconds, release all
   input, idle at least 30 seconds, and verify whether the one-second sway is
   gone. Also record whether flat/balloon Jak changes.
5. If deformation remains, add the smallest decisive Merc probe before another
   speculative fix. Label by display tick, chain ordinal, Merc bucket/model,
   and model name. For Jak record supplied slots, `addr - 128 * slot` base
   consistency, producer/live/copied/uploaded palette hashes, finite values,
   transform determinant/axis norms, and perspective hash. Compare positive-
   weight used slots against supplied slots. CPU-skin a small deterministic
   sample of Jak vertices and record bounds before and after perspective.
6. Classify before patching: bad at producer means bone input/producer;
   producer healthy but live mismatch means matrix-area reuse; palette-stage
   mismatch means packet/copy; healthy pre-perspective but bad post-perspective
   means camera constants; all CPU stages healthy means GPU binding or
   multi-chain presentation.
7. Independently correct the false identity fallback only with its own test:
   initialize unsupplied matrices as Merc identity (`tmat = -I4`, `nmat = I3`)
   and count or skip any model whose positive-weight used-slot mask is not
   covered. Do not present that defensive fix as the balloon root cause without
   probe evidence.

## Dirty state to preserve

Parent checkout modifications at clear:

- `GOALPad/ContentView.swift`
- `GOALPad/Game/GameSession.swift`
- `GOALPad/Game/GameSurfaceView.swift`
- `GOALPad/Native/GOALPadGameBoot.cpp`
- `GOALPad/Native/GOALPadMetalHost.hpp`
- `GOALPad/Native/GOALPadMetalHost.mm`
- `GOALPad/Native/GOALPadRenderSurface.mm`
- `GOALPad/Native/GOALPadRuntimeBridge.h`
- `HANDOFF.md`
- `docs/BUILDING.md`
- dirty nested `OpenGOAL` gitlink

Nested OpenGOAL modifications at clear:

- `game/graphics/pipelines/metal/metal_pipeline.h`
- `game/graphics/pipelines/metal/metal_renderer.h`
- `game/graphics/pipelines/metal/metal_renderer.mm`
- `goal_src/jak1/engine/draw/drawable.gc`

`git diff --check` passed in both checkouts after the fixed-step source patch.
All three read-only subagents completed; no subagent edited files. The AOT build
was interrupted and no build process should remain. No checkpoint commit was
made because the latest fixed-step code is explicitly unbuilt and physically
unvalidated.

---

# Checkpoint 32: fixed-step simulator validation and Experimental touch controls

Date: 2026-08-01. This is an intentionally uncommitted continuation checkpoint.
Parent branch `feat/ipados-native-boot` remains at
`8c7bbfe517aef11455bac7045d1e1940ef94eed2`, three commits ahead of its remote.
Nested OpenGOAL branch `goalpad/ipad-demo-pacing` remains at
`7e69774a0c91ff804f165df574f919afc6e7b826`. Preserve all dirty work listed
below. No physical device was accessed in this checkpoint; the current request
authorized only the local iPad Pro simulator.

## Checkpoint 31 fixed-step experiment completed through the simulator

The interrupted AOT sweep resumed with:

```sh
Scripts/generate-jak1-aot.sh /private/tmp/GOALPad-aot-host
```

It exited 0. The sweep found 518 reachable GOAL source files, emitted 10,596 of
10,603 functions through the C AOT backend, retained 7 native functions, and
reported 0 source-file failures. The ignored generated
`Generated/jak1-aot/drawable.c` now contains the `*pc-fixed-step*` symbol, its
default-false top-level initialization, and the live conditional which forces
the `display-frame-start` ratio to 1.0. The Xcode builds below used fresh
DerivedData after that generation.

`GOALPadGameBoot.cpp` still owns the platform decision: after `play`, it resolves
and enables `*pc-fixed-step*` only under `TARGET_OS_IOS`, before the first
gameplay dispatcher. Named-simulator unified logs contain:

```text
Using one fixed 60 Hz simulation step per iPad display-link tick.
```

The missing-symbol warning did not occur. This proves the branch is generated,
linked, and active in the simulator build. It does not prove that the physical
one-second camera sway is gone.

The focused log query was:

```sh
xcrun simctl spawn 96C5C21A-B925-4213-82A3-90DCB8518339 \
  log show --style compact --last 20m \
  --predicate 'process == "GOALPad" AND (eventMessage CONTAINS "fixed 60 Hz" OR eventMessage CONTAINS "pc-fixed-step" OR eventMessage BEGINSWITH "frame " OR eventMessage CONTAINS "Session started" OR eventMessage CONTAINS[c] "dropped" OR eventMessage CONTAINS[c] "merc")'
```

## Complete touch branch port

The entire intentional change range from parent branch `wip/touch-controls`
was ported:

- `eccb5ee` — iPad touch implementation.
- `6d4ce70` — deterministic host harness.

All seven files in that range are represented in the current tree:

- `GOALPad/ContentView.swift`
- `GOALPad/Game/GameSession.swift`
- `GOALPad/Game/TouchControls.swift`
- `GOALPad/Game/TouchControlsView.swift`
- `GOALPad/Input/ControllerInput.swift`
- `Scripts/run-touch-controls-check.sh`
- `Scripts/touch-controls-check.swift`

The two overlapping files were manually adapted rather than cherry-picked:

- `ContentView` preserves Checkpoint 31 target-presentation-time forwarding,
  current renderer diagnostics, and the existing overlay order. The touch view
  is iOS-only and remains below diagnostics so Info/Hide and other controls are
  usable.
- `GameSession` preserves the synchronous `beginFrame -> input -> GOAL/send ->
  endFrame -> rumble` lifetime. It samples touch exactly once after a surface is
  armed and before GOAL runs.

The current port intentionally differs from the old branch where current
architecture or live validation required it:

- Non-iOS hosts retain the no-argument physical-controller path, including a
  disconnected port when no controller is present. iOS passes an optional
  touch state and therefore has a neutral connected virtual pad.
- Controller activity and stick precedence use a 32-count deadzone, matching
  the minimum deadzone in Jak 1's analog readers instead of allowing small
  physical drift to override touch.
- Shutdown, inactive, and background transitions reset touches, queued button
  pulses, D-pad repeat, fade state, and the remembered tap button.
- A current on-screen touch overrides the two-second physical-controller
  artwork suppression interval.
- The host wrapper uses an explicit `/tmp` Swift module cache because the
  sandbox cannot write the default user cache.
- The deterministic harness includes interrupted-input reset coverage.

`GOALPad/` is an Xcode filesystem-synchronized group, so the new Swift files
need no manual project membership. The scripts correctly remain outside the app
target.

## Deterministic validation and builds

```sh
Scripts/run-touch-controls-check.sh
```

Passed every check: stationary/full/partial/clamped/neutral stick state,
directional swipes and holds, repeated taps with release gaps, lingering and
simultaneous touches, synthesized D-pad edge/repeat, camera state-machine
movement, pill hit testing, visibility, and reset. The first sandboxed attempt
could not load Swift's macro plugin from its user cache; the exact same wrapper
passed after running with the required local tool access, and the wrapper now
uses `/tmp` for its module cache.

```sh
git diff --check
git -C OpenGOAL diff --check
plutil -lint GOALPad.xcodeproj/project.pbxproj
```

All passed after the touch integration and documentation edits.

```sh
xcodebuild -quiet -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/GOALPad-cp31-touch-mac -jobs 4 \
  CODE_SIGNING_ALLOWED=NO ENABLE_PREVIEWS=NO ENABLE_DEBUG_DYLIB=NO build
```

Passed as a fresh build and again after the final touch-source adjustment.
Established upstream warnings remain.

```sh
xcodebuild -quiet -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-cp31-touch-device -jobs 4 \
  -allowProvisioningUpdates ENABLE_PREVIEWS=NO ENABLE_DEBUG_DYLIB=NO build
```

Passed as a fresh build and again after the final touch-source adjustment. Xcode
warned that `zschwendi@gmail.com` has no `Xcode-Token`, but the available signing
identity still produced a signed thin-arm64 app. No credential state was
changed. The executable is 26,857,216 bytes and its SHA-256 is
`6f5fb61e30baf514541cfaff027696aea9f0f9c93afc07f041f133c9a5dc1563`.

```sh
xcodebuild -quiet -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=96C5C21A-B925-4213-82A3-90DCB8518339' \
  -derivedDataPath /private/tmp/GOALPad-cp31-touch-sim -jobs 4 \
  CODE_SIGNING_ALLOWED=NO ENABLE_PREVIEWS=NO ENABLE_DEBUG_DYLIB=NO build
```

Passed. The simulator executable SHA-256 is
`9fdd9eb568d5a8ed206f6ff4209bbd835f616258f253f66807cd0d93866fd57f`.

## Approved simulator interaction

The initially shut-down iPad Pro 11-inch (M5) simulator
`96C5C21A-B925-4213-82A3-90DCB8518339` was booted, update-installed without an
uninstall, and launched as `com.zephyrstudiosllc.GOALPad`. Its existing
`Documents/Jak1` data and save remained in place.

The combined build booted 8 KERNEL objects and 346 GAME objects in 0.3 seconds,
loaded `title+village1`, and reached the title screen. Direct UI interaction
then established:

- Diagnostics Hide/Info remained clickable through the full-screen touch view.
- The Start pill entered the main menu.
- A right-half tap emitted Cross and opened the new-game save flow.
- The existing save was detected and was not overwritten.
- Diagnostics scrolling and the internal-resolution picker remained usable;
  the resolution stayed at 2x.
- The touch layer reported a neutral connected `Gamepad`, GOAL pad reads
  advanced with frames, audio stayed live, and `PROT_EXEC granted` remained
  `NO`.

At frame 15,000, runtime logging reported tick chains `0/1/>1` as
`0/15000/0`, 15,000 drawables scheduled with 0 missed, and Merc at 16 models / 82
draws with 0 bad bone pointers and 0 rejected draw ranges. Later on-screen
diagnostics still had equal sent/encoded DMA counts and 0 dropped chains.

The simulator UI driver can deliver taps but cannot hold two simultaneous
hardware-like contacts, and its instantaneous drag did not establish live
stick/menu movement. The deterministic harness covers stick, D-pad, camera,
and multi-touch state transitions; actual movement, camera drag, and ergonomics
remain physical-touch gates. No claim is made that this combined build fixes
the visible camera sway or Merc deformation because gameplay was not entered in
this run. The simulator was shut down after validation because it was initially
off.

## Documentation and unrelated project-file state

`README.md`, `docs/PROJECT_OVERVIEW.md`, and `docs/BUILDING.md` now label touch
input Experimental, describe the iOS/non-iOS ownership boundary and lifecycle,
provide the host-check command, and separate simulator evidence from
physical-device evidence.

`GOALPad.xcodeproj/project.pbxproj` became dirty during this checkpoint without
an intentional project edit. It is a large serialization/normalization change;
semantic comparison found no touch membership requirement and only removal of
`alwaysOutOfDate = 0` from the Metal shader phase. It is preserved rather than
reset because its ownership is unknown. Review or discard it separately only
with maintainer direction.

## Remaining validation and next executable task

- The host harness does not directly test `ControllerInput`'s physical/touch
  merge. The affected macOS/iOS builds and simulator interactions pass, but a
  future focused pure merge test would close that deterministic gap.
- No physical controller, physical multitouch, haptics, or physical-device
  touch behavior was tested.
- No build from this checkpoint was installed or launched on `Z iPad Pro`.
- Fixed-step activation is proven on the simulator; the physical visual A/B is
  still required before declaring the slow sway fixed.
- Flat/balloon Jak remains an independent Merc investigation. Do not infer a
  fix from healthy simulator chain counts.

The next executable task requires a fresh explicit physical-device request:
update-install the Checkpoint 32 Release app, rotate for 10 seconds with
diagnostics hidden, release all input, idle for at least 30 seconds, and record
whether the one-second sway is gone and whether flat/balloon Jak remains. If
Merc deformation remains, implement the bounded producer/live/palette/uploaded
probe specified in Checkpoint 31 before making another speculative fix.

## Dirty state to preserve

Parent checkout:

- `GOALPad.xcodeproj/project.pbxproj` (unattributed normalization; not required
  by touch controls)
- `GOALPad/ContentView.swift`
- `GOALPad/Game/GameSession.swift`
- `GOALPad/Game/GameSurfaceView.swift`
- `GOALPad/Input/ControllerInput.swift`
- `GOALPad/Native/GOALPadGameBoot.cpp`
- `GOALPad/Native/GOALPadMetalHost.hpp`
- `GOALPad/Native/GOALPadMetalHost.mm`
- `GOALPad/Native/GOALPadRenderSurface.mm`
- `GOALPad/Native/GOALPadRuntimeBridge.h`
- `HANDOFF.md`
- `README.md`
- `docs/BUILDING.md`
- `docs/PROJECT_OVERVIEW.md`
- dirty nested `OpenGOAL` gitlink
- untracked `GOALPad/Game/TouchControls.swift`
- untracked `GOALPad/Game/TouchControlsView.swift`
- untracked executable `Scripts/run-touch-controls-check.sh`
- untracked `Scripts/touch-controls-check.swift`

Nested OpenGOAL checkout:

- `game/graphics/pipelines/metal/metal_pipeline.h`
- `game/graphics/pipelines/metal/metal_renderer.h`
- `game/graphics/pipelines/metal/metal_renderer.mm`
- `goal_src/jak1/engine/draw/drawable.gc`

Generated AOT output is ignored. No checkpoint commit was made so the existing
Checkpoint 30/31 work and this touch port remain together exactly as validated.

---

# Checkpoint 33: display-target cadence, Jak 1 joint parity, RW-only arena, and default-clean UI

Date: 2026-08-01. This is an intentionally uncommitted continuation checkpoint.
Parent branch `feat/ipados-native-boot` remains at
`8c7bbfe517aef11455bac7045d1e1940ef94eed2`, three commits ahead of its remote.
The parent gitlink and nested OpenGOAL branch `goalpad/ipad-demo-pacing` remain
at `7e69774a0c91ff804f165df574f919afc6e7b826`. Preserve the complete dirty state
listed below; the child pin alone does not reproduce these changes.

The maintainer explicitly authorized physical testing on **Z iPad Pro** during
this request. Device ID is `6A4111AB-1663-508A-98D9-F0C1A9EA7863`; bundle ID is
`com.zephyrstudiosllc.GOALPad`. Every device installation remained an
update-install, never an uninstall, so the existing `Documents/Jak1` data and
saves stayed in the application container.

## Rejected fixed-step A/B and restored artifact

Checkpoint 32's forced ratio-one display step was subsequently built and
update-installed on the physical iPad. The maintainer reported that camera
auto-rotation and blocker correction became substantially more aggressive than
the prior build. A follow-up variation was less severe but remained worse. This
was decisive physical rejection, not an invitation for another speculative
device build, so the forced-fixed-step source was removed.

The prior artifact was restored while the seams were investigated:

```text
/private/tmp/GOALPad-fixedtick-device/Build/Products/Release-iphoneos/GOALPad.app
SHA-256 7b6af06f70ef29ff0befbe9b5a6e8da116478798ac56e98655c4e2adef0d3c56
```

That restoration preserved the user's data and supplied the known physical
baseline. It is historical now that the integrated Checkpoint 33 artifact has
also been update-installed and launched, but the user's visual comparison of
that newest build remains pending.

## Camera root cause and target-presentation-time fix

The earlier iOS timer reset occurred immediately before `kernel-dispatcher`.
`display-frame-start` therefore measured callback dispatcher/render workload,
not consecutive display targets. A normal callback followed by a skipped
display interval could be presented to GOAL as ratios 2 then 1 instead of the
display's actual 1 then 2. Camera seeker acceleration and displacement both
consume that ratio, amplifying the phase error during auto-rotation and blocker
correction even when ordinary follow behavior looks healthy.

The replacement keeps OpenGOAL's normal timing boundary:

- `CADisplayLink.targetTimestamp` passes through `GameSession`, the Objective-C++
  bridge, and `GOALPadGameBoot::run_frame`.
- `GOALPadDisplayClock` rounds consecutive target intervals to 60 Hz steps and
  clamps them to 1 through 4. First, invalid, and lifecycle-reset samples return
  1.
- The native host writes the resulting float to
  `*host-display-time-ratio*`. Jak 1 `display-frame-start` consumes a positive
  host value immediately before `set-time-ratios`; zero keeps the upstream
  timer-derived behavior for other hosts.
- Resetting the timer still excludes CADisplayLink's outside wait from the
  fallback, but no longer decides the iOS frame ratio.

`Scripts/run-camera-timing-check.sh` passed normal cadence, skipped-display,
clamping, invalid-sample, and reset coverage. It also preserves the regression
case showing why callback-workload timing assigns the ratio to the wrong game
frame. The generated `drawable.c` contains and consumes the host-ratio symbol at
the intended frame-start boundary.

## Merc attack behavior and Jak 1/Jak 2/Jak 3 parity

The Merc investigation separated two different behaviors instead of treating
every visible size change as one renderer bug:

- Localized squash/stretch in Jak's positive-scale attack animation is authored
  behavior. The validated host path retains it; the timing and joint fixes do
  not normalize or suppress those positive authored scales.
- A separate real robustness defect existed in Jak 1's MIPS2C translation of
  `cspace<-parented-transformq-joint!`. With a negative parent scale,
  `mfc1`/`pcpyld` sign extension could put `0xffffffff` into `vf16.w`. The host
  interprets that lane as NaN, so multiplying the child basis by it can poison
  all three basis rows while leaving translation apparently valid.

Jak 2 and Jak 3 already clear the homogeneous W lane before the vector
multiply. Jak 1 now performs the same clear, preserving cross-game behavior
parity without changing authored scale values. The permanent
`jak1-mips2c-joint-regression-test` invokes the real translated function and
covers both ordinary and negative parent scale. The physical iOS build retains
the justified MIPS2C bones compatibility selection because that path restored
Jak's volumetric shape; the new lane fix hardens the producer it selects.

Temporary Merc hashing, inventory, and renderer probes were removed after the
first bad producer stage was proven. No `MERC_PROBE`, `--merc-inventory`, or
probe-only build remains in the final source or validation path.

## EE arena is read/write, never executable

The portable kernel previously tried an RWX anonymous mapping first and fell
back to RW only if the platform refused it. A physical build unexpectedly
granted the unused permission, leaving the GOAL heap and stacks writable and
executable even though all native code comes from signed AOT or MIPS2C text.

`kernel_core.cpp` now maps the arena RW directly by policy and has a compile-time
assertion forbidding `PROT_EXEC`. The exported state always reports the arena as
non-executable. Guard-page setup, stable allocation ownership, and teardown are
unchanged. On Apple hosts the AOT execution test uses `mach_vm_region` to require
the live mapping to remain `rw-` before and after real AOT calls, including the
GOAL-stack `(fact 10)` execution path.

The app's diagnostic label is now `EE arena executable`, not the misleading
`PROT_EXEC granted`; the validated simulator and physical runtime both reported
`NO`/`PROT_EXEC=no` respectively.

## Touch and diagnostics defaults

The complete Checkpoint 32 touch implementation remains. Per maintainer request,
the diagnostics overlay and internal-resolution picker are now hidden by
default. A compact top-right button using SwiftUI's `line.3.horizontal` symbol
opens or closes the diagnostics. The default game view therefore has no zoom
controls and no keyboard/ellipsis icon over the game.

The named simulator directly established that only the three-line button was
shown by default and that the diagnostics and resolution picker appeared after
opening it. `Scripts/run-touch-controls-check.sh` still passes the deterministic
touch state machine. Physical multitouch, ergonomics, controller mapping, and
haptics remain unvalidated.

## Deterministic and build validation

Both focused parent checks passed:

```sh
Scripts/run-camera-timing-check.sh
Scripts/run-touch-controls-check.sh
```

The three affected OpenGOAL tests passed 3/3:

```sh
cmake --build OpenGOAL/build/Release/bin --target \
  jak1-mips2c-joint-regression-test \
  jak1-kernel-core-smoke-test \
  jak1-aot-execution-test -j4

ctest --test-dir OpenGOAL/build/Release/bin --output-on-failure \
  -R 'jak1-(mips2c-joint-regression|kernel-core-smoke|aot-execution)-test'
```

The passing tests were:

- `jak1-mips2c-joint-regression-test`
- `jak1-kernel-core-smoke-test`
- `jak1-aot-execution-test`

Ahead-of-time regeneration also passed:

```sh
Scripts/generate-jak1-aot.sh /private/tmp/GOALPad-aot-host
```

The sweep found 518 reachable source files, emitted 10,596 of 10,603 functions,
retained seven native functions, and reported zero source-file failures.

Fresh ARM64 macOS Debug and named iPad Pro 11-inch (M5) simulator Debug builds
passed:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/GOALPad-cp33-macos \
  CODE_SIGNING_ALLOWED=NO ENABLE_PREVIEWS=NO build

xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=96C5C21A-B925-4213-82A3-90DCB8518339' \
  -derivedDataPath /private/tmp/GOALPad-cp33-sim \
  CODE_SIGNING_ALLOWED=NO ENABLE_PREVIEWS=NO build
```

The simulator build was update-installed without uninstalling, preserving its
data and save. The real runtime loaded the title and Village1 and produced 48
kHz audio. The captured diagnostics showed:

- zero Merc bad-bone-pointer and bad-draw-range rejects;
- zero drawable misses;
- `EE arena executable: NO`;
- display cadence 17.00/16.97/66.44 ms mean/p95/max;
- 2 callbacks below 12 ms and 10 callbacks at least 24 ms in that sample.

The simulator was shut down after validation.

## Signed generic iOS and physical runtime evidence

The fresh signed generic iOS Release build passed:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-cp33-device \
  -allowProvisioningUpdates ENABLE_PREVIEWS=NO ENABLE_DEBUG_DYLIB=NO build
```

The result is a thin ARM64 iPhoneOS executable with SHA-256:

```text
0b2e2ad81af7c3575e5ff9fb180c2957fec46a74daf61c956cad0588f4b9fcae
```

Parsed entitlements are only the development application identifier, team
identifier, and `get-task-allow`; there is no JIT or unsigned-executable-memory
entitlement. Standalone `codesign --verify --deep --strict` returned the known
`CSSMERR_TP_NOT_TRUSTED` local certificate-chain result.

The final binary also contains the exact Jak 1 parity instruction: its
`cspace_parented_transformq_joint::execute` stores zero to the translated
`vf16.w` lane before all three vector multiplies. The iOS boot function contains
the pre-`play` `*use-new-bones* = #f` selection, and neither source nor artifact
contains the temporary Merc probe markers.

CoreDevice accepted the same embedded signature. The update-install passed, and
the console launch succeeded and produced the runtime evidence below. Ending
that attachment with Ctrl-C also terminated the app with signal 2, so a final
detached `--activate` launch was run and passed:

```sh
xcrun devicectl device install app \
  --device 6A4111AB-1663-508A-98D9-F0C1A9EA7863 \
  /private/tmp/GOALPad-cp33-device/Build/Products/Release-iphoneos/GOALPad.app

xcrun devicectl device process launch \
  --device 6A4111AB-1663-508A-98D9-F0C1A9EA7863 \
  --console com.zephyrstudiosllc.GOALPad

xcrun devicectl device process launch \
  --device 6A4111AB-1663-508A-98D9-F0C1A9EA7863 \
  --activate com.zephyrstudiosllc.GOALPad
```

The attached physical console booted the real ARM64 kernel with
`PROT_EXEC=no`, loaded the title and Village1, and started 48 kHz audio. It then
discarded the title level, loaded the training level (`TRA.DGO`, 334 textures,
45.7 MB vertex data and 6.4 MB index data), and loaded the training sound bank.
After the final detached relaunch, a process query found the app live as PID
6970.

The console also repeatedly emitted the existing/runtime error
`sp-launch-particles called during processing, and queue is full`. Its cause and
whether it predates the Checkpoint 33 changes were not established; do not
attribute it to this checkpoint or hide it in later acceptance work.

## Not yet validated and next gate

The build, update-install, native kernel, level loading, renderer, and audio
paths are physically established. The maintainer has not yet visually accepted
the combined camera behavior or Merc appearance. Do not report either bug fixed
on physical hardware until that observation is recorded. Physical controller
mapping, physical multitouch ergonomics, and haptics also remain unvalidated.

The next executable task is one final maintainer visual acceptance on the
already-installed Checkpoint 33 build: exercise ordinary running, blocker and
auto-rotate camera correction, and attack animation. Compare against the
restored `7b6af06f...` baseline without installing another speculative variant.
If the result fails, use the deterministic seam evidence and the attached
runtime error as inputs to a new bounded investigation; do not resume dart-like
device A/B changes.

## Dirty state to preserve

Parent checkout (`git status --short`):

```text
 M GOALPad.xcodeproj/project.pbxproj
 M GOALPad/ContentView.swift
 M GOALPad/Game/GameSession.swift
 M GOALPad/Game/GameSurfaceView.swift
 M GOALPad/Input/ControllerInput.swift
 M GOALPad/Native/GOALPadGameBoot.cpp
 M GOALPad/Native/GOALPadGameBoot.hpp
 M GOALPad/Native/GOALPadMetalHost.hpp
 M GOALPad/Native/GOALPadMetalHost.mm
 M GOALPad/Native/GOALPadRenderSurface.mm
 M GOALPad/Native/GOALPadRuntimeBridge.h
 M GOALPad/Native/GOALPadRuntimeBridge.mm
 M HANDOFF.md
 m OpenGOAL
 M README.md
 M docs/BUILDING.md
 M docs/PROJECT_OVERVIEW.md
?? GOALPad/Game/TouchControls.swift
?? GOALPad/Game/TouchControlsView.swift
?? GOALPad/Native/GOALPadDisplayClock.hpp
?? Scripts/camera-timing-check.cpp
?? Scripts/run-camera-timing-check.sh
?? Scripts/run-touch-controls-check.sh
?? Scripts/touch-controls-check.swift
```

Nested OpenGOAL checkout (`git -C OpenGOAL status --short`):

```text
 M game/CMakeLists.txt
 M game/graphics/pipelines/metal/metal_pipeline.h
 M game/graphics/pipelines/metal/metal_renderer.h
 M game/graphics/pipelines/metal/metal_renderer.mm
 M game/kernel/core/README.md
 M game/kernel/core/aot_execution_test.cpp
 M game/kernel/core/host_smoke_test.cpp
 M game/kernel/core/kernel_core.cpp
 M game/kernel/core/kernel_core.h
 M game/mips2c/jak1_functions/joint.cpp
 M goal_src/jak1/engine/draw/drawable.gc
?? game/kernel/core/jak1_mips2c_joint_regression_test.cpp
```

`GOALPad.xcodeproj/project.pbxproj` remains the preserved unattributed
normalization change. The Checkpoint 30 renderer-lifetime files, Checkpoint 32
touch files, Checkpoint 33 camera/UI files, RW-only kernel files, Jak 1 parity
test, and documentation remain intentionally uncommitted together. Generated
AOT output is ignored. No temporary Merc renderer probe is present.

# Checkpoint 34: physical visual rejection, camera-zone contract, and context-reset handoff

Date: 2026-08-01. This is a documentation-only context-reset checkpoint. It
supersedes Checkpoint 33's pending visual-acceptance gate; it does not supersede
the deterministic build, binary, simulator, or physical boot evidence recorded
there.

The active parent checkout is
`/Users/zach/Developer/OS_Projects/GOALPad/GOALPad`, branch
`feat/ipados-native-boot`, HEAD
`8c7bbfe517aef11455bac7045d1e1940ef94eed2` (three commits ahead of its remote).
The nested checkout is `OpenGOAL`, branch `goalpad/ipad-demo-pacing`, HEAD
`7e69774a0c91ff804f165df574f919afc6e7b826`. Both contain the intentional dirty
state listed in Checkpoint 33; `git status --short` was rechecked immediately
before this handoff and the inventory is unchanged except for this additional
`HANDOFF.md` edit. No code was committed, discarded, reset, or cleaned.

The installed physical artifact remains the Checkpoint 33 Release app at:

```text
/private/tmp/GOALPad-cp33-device/Build/Products/Release-iphoneos/GOALPad.app
SHA-256 0b2e2ad81af7c3575e5ff9fb180c2957fec46a74daf61c956cad0588f4b9fcae
```

Do not infer renewed physical-device permission after the context reset. The
maintainer must explicitly authorize any later install, launch, log attachment,
screen capture, or other access to **Z iPad Pro** in the then-current request.

## Maintainer physical visual result

Physical visual acceptance of the combined Checkpoint 33 build **failed**. The
maintainer described it as one of the better builds so far and said the camera
is smoother in more sections, especially ordinary follow while Jak runs, but
the remaining camera behavior is still broken.

The current camera defect is an apparent fight between multiple positions or
states. It looks like z-fighting in camera space: the view shakes or teleports
back and forth between positions. The maintainer explicitly distinguished this
from the previous defect where auto-rotation or blocker correction became
extremely aggressive. Do not collapse these into one symptom, and do not treat
the target-presentation-time change as proof that the camera is fixed.

Jak's volumetric appearance is also regressing again in the same combined
build. Earlier physical observations in this sequence were that Jak's general
3D shape had recovered while the Merc could still enlarge strangely across his
whole body during attacks, like a whole-body version of big-head mode. The
latest observation is that Jak's volumetrics are having issues again. The
MIPS2C path selection, the Jak 1 W-lane correction, the Jak 2/Jak 3 parity audit,
and the signed-binary instruction proof remain valid evidence, but they are not
sufficient to claim the physical rendering defect solved.

Cross-game parity is a standing requirement for these seams: compare Jak 1,
Jak 2, and Jak 3 implementations when diagnosing shared transform, animation,
camera, or renderer behavior. Port parity fixes across the games when the seam
is shared; preserve a divergence only when repository evidence shows it is
intentional or game-specific, and document that reason.

## Touch layout contract for the next implementation

The current touch layout is not the desired final zoning. The next touch patch
must preserve these maintainer requirements:

- Reserve the upper portion of the display for camera gestures. The maintainer
  described this as the top half or top third; choose the exact boundary during
  implementation from the existing layout and ergonomic evidence rather than
  silently treating the current split as accepted.
- Reserve the lower half for movement and action touch controls.
- A tap on the left side must be able to emit the same tap action as a tap on
  the right side, so either finger/thumb can perform it. Movement ownership and
  tap recognition must coexist deterministically rather than stealing or
  cancelling each other unpredictably.
- Keep the zoom/resolution diagnostics hidden by default and retain the compact
  three-horizontal-line diagnostics button; do not restore the keyboard or
  ellipsis icon.

Add deterministic touch tests for zone ownership, boundary behavior,
simultaneous movement plus camera input, and equivalent left/right tap actions
before asking for physical ergonomics feedback.

## Workflow constraint and next executable tasks

Do not resume speculative build-to-build device A/B changes. The maintainer
explicitly asked for agents to own each seam until it is actually explained and
solved, with physical trials only after deterministic seam evidence and
simulator validation. Use independent subagents for non-overlapping camera,
volumetric/Merc, and touch investigations; keep their edits isolated and have
the primary agent review and validate every result. Preserve cross-game bug/fix
parity as described above.

Resume in this order:

1. Reproduce the current multi-position camera oscillation without changing
   cadence constants blindly. Trace one frame identity from camera-state
   production through DMA/render submission and presentation, looking for two
   competing update paths, stale/current state alternation, duplicate camera
   chains, or presentation of mismatched frame state. Establish the first bad
   seam with logs or a deterministic test before editing behavior.
2. Reproduce the physical volumetric regression across the producer, live joint
   state, palette, upload, and presented frame seams. The existing W-lane parity
   test only proves one producer invariant; it does not close the end-to-end
   visual bug. Preserve authored positive attack squash/stretch while isolating
   the unintended whole-body enlargement or loss of volume.
3. Implement the touch-zone contract as a separate patch with deterministic
   tests. Do not couple it to camera-timing or Merc-rendering experiments.
4. Build all affected host and simulator targets after the seam fixes. Do not
   access the physical iPad until the maintainer explicitly authorizes that in
   a new current request.

The repeated runtime warning
`sp-launch-particles called during processing, and queue is full` remains an
unattributed observation. Do not hide it or assume it causes either visual bug
without evidence. Physical controller mapping, physical multitouch ergonomics,
and haptics remain unvalidated.

## Delegation state at context clear

- `checkpoint33_docs_audit` completed its documentation audit; its shared
  checkout edits are the current `README.md`, `docs/BUILDING.md`, and
  `HANDOFF.md` changes already inventoried above.
- `merc_probe_audit` completed without edits. It confirmed the signed artifact
  contains the linked Jak 1 MIPS2C joint implementation and W-lane clear, that
  boot selects `*use-new-bones* = #f`, and that temporary probe markers are
  absent. Its only signing caveat was the already-recorded local
  `CSSMERR_TP_NOT_TRUSTED` result.
- `attack_timing_causality` never started (`pending_init`) and was interrupted
  before the context clear. It made no edits and supplied no result. Spawn a
  fresh bounded camera worker after resuming rather than assuming this audit ran.

## Context-clear validation

This checkpoint changed documentation only. The current branches, HEADs,
worktrees, and both dirty inventories were inspected with `git rev-parse`,
`git branch --show-current`, `git worktree list --porcelain`, and
`git status --short --branch`. `git diff --check` passed in both the parent and
nested checkout after this edit. No new build, simulator launch, installation,
or physical-device action was performed for Checkpoint 34.

# Checkpoint 35: end-to-end camera provenance instrumentation

Date: 2026-08-01. This checkpoint implements behavior-neutral diagnostics for
Checkpoint 34's first camera task. It does not change camera math, cadence
constants, DMA ordering, touch behavior, or Merc behavior, and it does not
claim that the physical camera defect is fixed.

The parent checkout remains
`/Users/zach/Developer/OS_Projects/GOALPad/GOALPad`, branch
`feat/ipados-native-boot`, HEAD
`8c7bbfe517aef11455bac7045d1e1940ef94eed2` (three commits ahead of its remote).
The nested checkout remains `OpenGOAL`, branch `goalpad/ipad-demo-pacing`, HEAD
`7e69774a0c91ff804f165df574f919afc6e7b826`. Both retain all intentional dirty
Checkpoint 30-34 work. Nothing was committed, reset, cleaned, or discarded.

## Camera seam result

The camera worker traced the live Jak 1 producer and found that
`add-pc-tfrag3-data` copies `*math-camera*`'s four `camera-temp` qwords and one
`trans` qword into every 25-qword tfrag, tie, and shrub PC-port packet. Existing
frame identity stopped at separate engine, host, chain, renderer, and drawable
counters; no value associated those seams end to end.

A sound-enabled host gameplay run captured frames 24793 through 24800 after the
title, clone animation, ground contact, walking, and jumping gates all passed.
Each frame had five background-camera packets. All 40 packets agreed exactly
within their frame. The camera transform fingerprint was unique on all eight
frames, no frame matched the frame two positions earlier, and there was no
`A -> B -> A` alternation. The translation qword was unchanged while the
combined camera transform evolved each frame. This rules out alternating or
mixed tfrag/tie/shrub camera packets in that eight-frame host window. It does
not rule out a live-producer mismatch outside the capture or physical Metal
presentation order.

The implemented diagnostic now carries one identity from the live producer to
the asynchronous presentation callback:

- `GOALPadGameBoot` snapshots the exact 80 producer bytes at the synchronous
  DMA-send seam and associates them with the dispatcher frame.
- `GOALPadMetalHost` attaches dispatcher frame, display-link tick, and chain
  ordinal to the renderer submission.
- the tfrag, tie, and shrub renderers fingerprint every background packet,
  compare it with the live snapshot and the chain's first packet, and attribute
  mismatches to the five source qwords and first bucket name;
- `MetalRenderer` records submission and drawable identity and, on iPhoneOS and
  macOS, the actual `presentedTime` callback with the matching frame/tick/chain;
- the bridge, diagnostics overlay, and ten-second Session log expose the
  counters. Only the first mismatch is logged loudly so a bad run remains
  readable.

`metal_camera_trace.h` is plain C++ and has a deterministic host test covering
the 80-byte layout, fingerprint stability, exact qword attribution,
producer-to-packet and packet-to-packet comparison, monotonic presentation
order, and a deliberately reversed presentation sequence.

The current iPhone Simulator 26.5 SDK omits `MTLDrawable`'s presentation
callback, presented-time, and drawable-ID members even though the iPhoneOS SDK
contains them. The first named-simulator build exposed this with four compiler
errors in `metal_renderer.mm`. The final implementation has a simulator-only
compile boundary: simulator runs retain frame, chain, camera, drawable-acquire,
and submission evidence while actual presentation counts and drawable IDs stay
zero; real iPhoneOS builds retain the callback path.

## Delegated audits

Three bounded read-only workers were used and reviewed:

- The camera worker found no second ordinary `update-camera` call per display
  loop, documented the legitimate combiner transition slaves, located the exact
  packet producer fields, and extracted the dynamic host capture above.
- The Merc worker found the first unclosed volumetric seam between live joint
  output and old-bones `pris-mtx`. The existing joint test stops before the
  bones producer and `metal-proof` starts from authored matrices. The next
  deterministic Merc task is a joint-to-bones-to-palette-to-alternating-pixel
  provenance ladder, not another camera edit.
- The touch worker confirmed that the current horizontal topology is the
  rejected layout. The later isolated patch should use the upper half for
  camera, lower-left for movement with tap coexistence, and the remaining lower
  region for action, with the half boundary owned deterministically by the
  lower region. It should not be mixed into this camera checkpoint.

## Validation

Host camera trace and related renderer tests:

```sh
cmake --build OpenGOAL/build/Release/bin \
  --target metal-camera-trace-test -j4
OpenGOAL/build/Release/bin/game/metal-camera-trace-test

ctest --test-dir OpenGOAL/build/Release/bin \
  -R 'metal-camera-trace-test|jak1-mips2c-joint-regression-test' \
  --output-on-failure

cmake --build OpenGOAL/build/Release/bin --target metal-proof -j4
OpenGOAL/build/Release/bin/game/metal-proof

Scripts/run-camera-timing-check.sh
Scripts/run-touch-controls-check.sh
```

Results: the trace binary passed all 13 assertions; focused CTest passed 2/2;
the Jak 1 joint regression passed both scale cases; `metal-proof` ended
`METAL PROOF PASSED`; the camera timing check passed; and the touch harness
passed all checks. The first sandboxed touch-script attempt failed because the
Observation macro plugin could not run under `sandbox-exec`; the same unchanged
script passed outside that sandbox.

The dynamic host capture used the player's existing local prepared data and a
temporary output directory only:

```sh
OpenGOAL/build/Release/bin/game/jak1-data-boot-test \
  --data-dir /Users/zach/Developer/OS_Projects/GOALPad/Jak1/projdata/out/jak1 \
  --play --frames 24800 \
  --press start@target-title-wait+60 \
  --press x@target-title-wait+160 \
  --press down@target-title-wait+240 \
  --press down@target-title-wait+260 \
  --press down@target-title-wait+280 \
  --press down@target-title-wait+300 \
  --press x@target-title-wait+340 \
  --stick 127,0@target-hit-ground+120:400 \
  --press x@target-walk+700 \
  --capture-dma-dir /private/tmp/GOALPad-cp34-camera-dynamic.fYRjwd \
  --capture-dma-frames 24793,24794,24795,24796,24797,24798,24799,24800 \
  --expect-state target-title-wait \
  --expect-state target-clone-anim \
  --expect-state target-hit-ground \
  --expect-state target-walk \
  --expect-state target-jump \
  --expect-travel 10
```

It exited 0 with all requested state and travel gates and all eight captures.
No retail data was added to Git.

Application builds:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/GOALPad-cp35-macos -jobs 4 \
  CODE_SIGNING_ALLOWED=NO ENABLE_PREVIEWS=NO build

xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=96C5C21A-B925-4213-82A3-90DCB8518339' \
  -derivedDataPath /private/tmp/GOALPad-cp35-sim -jobs 4 \
  CODE_SIGNING_ALLOWED=NO ENABLE_PREVIEWS=NO build

xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-cp35-device -jobs 4 \
  -allowProvisioningUpdates ENABLE_PREVIEWS=NO ENABLE_DEBUG_DYLIB=NO build
```

All three final builds succeeded. The first sandboxed macOS attempt failed only
because the shader phase's nested `sandbox-exec` was not permitted; the same
build succeeded outside that sandbox. The first simulator compile found the SDK
split described above; after the narrow conditional, the named simulator build
succeeded. Existing upstream and generated warnings remain.

The M5 simulator was already booted, so it was not booted or shut down by this
checkpoint. The Debug app was update-installed without uninstalling or erasing
its data and launched with bounded console capture. The existing local Jak 1
data booted through the intro and active renderer. Unified Session logs reached
frame 3600 with 3600 scheduled drawables, zero misses, exactly one chain per
tick, five camera packets in active frames, zero live-camera mismatches, and
zero within-chain packet mismatches. Presentation completion remains zero on
the simulator for the documented SDK reason.

The generic Release artifact is a thin ARM64 Mach-O signed by Xcode with team
`D2YYJ54Q6V`. Its executable SHA-256 is
`cc9620e7cc0fcc4e9c529c5d914a60e5ae79176a42c50403be7a194a9d395f5f`.
`codesign -d --entitlements -` reports only application identifier, team
identifier, and `get-task-allow = true`. A local strict trust-chain check
returned `CSSMERR_TP_NOT_TRUSTED`; this is not reported as a passing signature
verification. Xcode's compile, link, and CodeSign phases all succeeded.

`git diff --check` passed in both parent and nested checkouts after the code
changes and before this documentation append. Recheck it after any later edit.

## Not validated and next executable task

No install, launch, log attachment, screen capture, or other access to physical
**Z iPad Pro** occurred. Therefore actual device presentation callbacks,
physical display order, and the maintainer's camera visual result remain
pending. A generic signed build is build/signing evidence only.

The next camera step requires fresh explicit physical-device authorization:
update-install this Checkpoint 35 artifact, reproduce the multi-position camera
oscillation with diagnostics hidden, then read the bounded Session log. The
first nonzero live-camera, packet-camera, or presentation-order mismatch names
the first bad seam. If all remain zero while the defect is visible, capture the
matching frame/tick/chain identities before changing camera behavior.

While that physical gate is pending, the next independent deterministic task is
the Merc joint-to-bones-to-palette-to-pixel provenance ladder described above.
The touch zoning contract remains a separate later patch. Physical controller
mapping, multitouch ergonomics, haptics, the camera visual defect, and the Merc
visual defect are not validated by this checkpoint.

## Physical validation after explicit authorization

Later on 2026-08-01 the maintainer explicitly authorized running the build on
**Z iPad Pro**. The device was available and paired as CoreDevice identifier
`6A4111AB-1663-508A-98D9-F0C1A9EA7863`, physical UDID
`00008142-000A504C3CC2401C`, model `iPad17,1`, on iPadOS 26.6. The installed
bundle remained `com.zephyrstudiosllc.GOALPad` version/build `1.0 (1)`.

The exact Checkpoint 35 Release artifact was reverified before use:

```text
/private/tmp/GOALPad-cp35-device/Build/Products/Release-iphoneos/GOALPad.app
GOALPad SHA-256 cc9620e7cc0fcc4e9c529c5d914a60e5ae79176a42c50403be7a194a9d395f5f
```

It was update-installed and launched with bounded console attachment:

```sh
xcrun devicectl device install app \
  --device 6A4111AB-1663-508A-98D9-F0C1A9EA7863 \
  /private/tmp/GOALPad-cp35-device/Build/Products/Release-iphoneos/GOALPad.app

xcrun devicectl device process launch \
  --device 6A4111AB-1663-508A-98D9-F0C1A9EA7863 \
  --terminate-existing --console com.zephyrstudiosllc.GOALPad
```

Both commands succeeded. This was an update install only: the app was not
uninstalled, its container was not erased, and the existing user-local Jak 1
data booted from `Documents/Jak1`. The physical ARM64 kernel reported
`PROT_EXEC=no`; KERNEL.CGO, GAME.CGO, title, village1, and training loaded; the
Metal renderer loaded the corresponding art and gameplay ran for roughly 100
seconds under the attached console.

### Maintainer visual result

The maintainer reported during that exact attached run:

> it is jittering like crazy. this is one of the worser builds. and jak is
> sometiems going flat stanley on us again. overall very good representation of
> current bugs.

This is decisive physical visual rejection of Checkpoint 35 and a useful
combined reproduction of both active defects. The camera is not fixed. Jak's
volumetric/Merc deformation is not fixed. Keep this maintainer-observed visual
evidence separate from the agent-observed console evidence below.

### Agent-observed console result and limitation

Across the attached failure window the console emitted neither of the new loud
first-failure records:

- no `Metal camera provenance mismatch` line;
- no `Metal presentation order mismatch` line.

Because those are logged immediately on the first detected mismatch, the
attached output contains no evidence of a live-snapshot-to-background-packet
disagreement, within-chain camera-packet disagreement, or detected reversal of
presentation callback submission/time order during the observed run. This does
not prove that the live producer camera state was visually correct: producer
and packets can agree on the same wrong or alternating state. It also does not
close Merc, shader, compositor, cadence, or final scanout seams.

The structured ten-second Swift `Session` notices did not appear on
`devicectl --console`. A filtered attempt to collect the previous ten minutes
with:

```sh
/usr/bin/log collect --device-udid 00008142-000A504C3CC2401C \
  --last 10m --output /private/tmp/GOALPad-cp35-physical.logarchive \
  --size 20m \
  --predicate 'subsystem == "com.zephyrstudiosllc.GOALPad"'
```

failed without changing the device because macOS requires root to collect logs
from an attached device. No broad sysdiagnose was taken. Therefore exact
submission/completion counts and first/last frame/tick/chain values are not
available from this run and must not be invented.

The console did repeatedly emit the already-known
`sp-launch-particles called during processing, and queue is full` error during
training gameplay. It occurred in the same broad run but remains unattributed;
do not claim it causes either visual defect without a deterministic link.

Ending the console attachment forwarded SIGINT and terminated GOALPad, matching
the maintainer's stated intent to close the app. It did not uninstall the app
or remove its data. The app was not relaunched.

### Revised next step

Do not make another speculative camera timing change. The physical failure with
no loud producer-to-packet or presentation-order mismatch makes the next narrow
camera task a consecutive-frame live-producer provenance capture capable of
showing `A/B/A/B` camera fingerprints, rather than only ten-second cumulative
counters. That capture must write or print a bounded ring so it can be recovered
without privileged unified-log collection.

In parallel, implement the already-audited deterministic Merc
joint-to-bones-to-palette-to-pixel ladder. The same physical run reproduced
Flat-Stanley deformation, while the present W-lane and authored-matrix tests do
not cover that full path. Keep camera and Merc changes isolated and do not ask
for another physical A/B until one of those tests identifies a first bad seam.

# Checkpoint 36: recoverable camera returns and complete Merc palette proof

## Scope and interpretation

Checkpoint 36 implements the two next tasks named by Checkpoint 35 without
changing camera scheduling or hiding either visual defect:

- retain strong consecutive-frame `A/B/A` returns from the live Jak 1
  `*math-camera*` producer in a recoverable numeric cache record;
- execute the real Jak 1 joint-to-bones-to-Merc-palette-to-pixel path with
  deterministic synthetic inputs, including the first 16-bone batch boundary;
- count exact missing weighted Merc palette slots in live rendering without
  skipping the draw;
- preserve actual Metal presentation/drop evidence independently of callback
  arrival order.

The only pre-existing Jak 2/Jak 3 behavior carried into Jak 1 is the
homogeneous-W safety clear in the translated parented-joint routine. Jak 1 has
its own independently translated routine and had missed that three-instruction
clear. This is not evidence that Jak 2 or Jak 3 already contained a complete
fix for GOALPad's camera or Flat-Stanley defects.

## Implementation

`metal_camera_trace.{h,cpp}` now compares the 80-byte producer snapshot formed
from four `camera-temp` qwords plus `trans`. It records a return only when the
older-to-current normalized distance is at most half the smaller adjacent leg,
both adjacent legs are material, and engine frame IDs are consecutive. Duplicate
engine-frame chains and gaps reset the sequence. The first match is logged
loudly; durable event frame IDs, fingerprints, host tick/chain, packet
fingerprint, mismatch masks, distances, and the cumulative count are retained
until a later real match replaces them.

Presentation accounting retains a fixed 64-pair history of successful
presentations. A zero `presentedTime` is a dropped drawable, not a successful
completion or order reversal. A reversal is counted only when submission order
and actual presentation-time order disagree, so out-of-order callback delivery
does not create a false reversal. Drops do not replace last-presented identity.

The app writes one atomic, versioned, numeric-only record at:

```text
Library/Caches/GOALPadDiagnostics/camera-provenance-v1.log
```

Each session replaces the prior record with a random numeric run ID. The file
is refreshed at startup, every 600 frames, immediately on a new camera return
or Merc omission, on inactive/background transitions, and before kernel
shutdown. A failed write does not advance the persisted event cursor, so the
next periodic or lifecycle write retries it. The record contains no game-data
path, device identifier, raw asset data, or raw camera matrix.

The Merc proof now exercises the real Jak 1 parented joint, the real
`bones_mtx_calc::exec_mpg` routine, and the real `bones_mtx_calc::execute`
wrapper with its scratchpad, bones-init, and DMA input/output layout. It proves:

- direct and wrapper count-one output are bit-identical;
- an `A/B/A/B` joint sequence produces exact repeated 80x138 and 40x172 pixels
  after poisoning EE palette memory following synchronous submission;
- 17 bones force a 16-bone first batch plus bone 16 in the second batch, with
  all matrices distinct, sentinels 15/16 correct, expected 128-byte strides and
  padding, and guards intact.

Required Merc slots are precomputed per model effect as four immutable 64-bit
masks when a level is loaded. At runtime the renderer ORs only enabled-effect
masks, compares them with slots populated by valid 112-byte EE copies, and
enumerates individual slots only for the first error log. A missing required
slot remains zero and the draw still submits. The deterministic omitted-slot
case reports exactly one slot in one model and collapses the authored-origin
pixel to black; the complete packet reports zero.

The remaining unproved Merc seam is the outer GOAL calculation-list dispatcher
and larger live batches. The live counter also does not yet reject finite but
degenerate palette matrices.

## Deterministic and build validation

The final shared tree passed:

```sh
cd OpenGOAL
cmake --build build/Release/bin --target metal-camera-trace-test -j4
build/Release/bin/game/metal-camera-trace-test

cmake --build build/Release/bin --target jak1-mips2c-joint-regression-test -j4
build/Release/bin/game/jak1-mips2c-joint-regression-test

cmake --build build/Release/bin --target metal-proof -j4
build/Release/bin/game/metal-proof
```

The camera trace test passed all 23 assertions, the joint regression passed both
cases, and the Metal proof ended with `METAL PROOF PASSED`. The first sandboxed
Metal-proof launch could not access a display; the approved unsandboxed rerun
passed. Existing upstream/generated warnings remain.

All three application builds passed:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/GOALPad-cp36-macos -jobs 4 \
  CODE_SIGNING_ALLOWED=NO ENABLE_PREVIEWS=NO build

xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=96C5C21A-B925-4213-82A3-90DCB8518339' \
  -derivedDataPath /private/tmp/GOALPad-cp36-sim -jobs 4 \
  CODE_SIGNING_ALLOWED=NO ENABLE_PREVIEWS=NO build

xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-cp36-device -jobs 4 \
  -allowProvisioningUpdates ENABLE_PREVIEWS=NO ENABLE_DEBUG_DYLIB=NO build
```

The macOS build succeeded in 61.029 seconds, the corrected named-simulator
build in 58.840 seconds, and the signed Release build in 66.605 seconds. One
earlier simulator command omitted shell quoting around the destination and was
parsed as an ambiguous physical-iOS destination; it failed before building or
accessing a device. The corrected command above is the recorded result.

The signed binary is thin ARM64 with SHA-256:

```text
b30e8490fa9c2e223c6cf871b4a0dd45bff47c8b175c8f88011321fb15c1f704
```

Xcode signed it with team `D2YYJ54Q6V`; decoded entitlements are only the
application identifier, team identifier, and `get-task-allow = true`. The
embedded development profile expires `2026-08-06T23:51:59Z`. The local strict
trust-chain check returned `CSSMERR_TP_NOT_TRUSTED`, so it is not reported as a
passing independent trust verification; Xcode's CodeSign phase and the later
physical install/launch both succeeded.

## Simulator persistence result

The approved M5 simulator began `Shutdown`, was booted, update-installed without
an uninstall, launched against its preserved local data, and returned to
`Shutdown`. Its one-line record at frame 1800 contained:

```text
producer_alternations=3
live_mismatches=0 packet_mismatches=0
merc_missing_bone_slots_total=0 merc_models_with_missing_bone_slots_total=0
```

The retained return was engine frames 1090/1091/1092 with normalized distances
`0.011923487/0.009847786/0.004462195`. Simulator presentation completions remain
zero because the simulator build does not compile the physical drawable timing
API path.

## Authorized physical result

The maintainer's current-request authorization was used to refresh paired
**Z iPad Pro**, update-install the exact Checkpoint 36 artifact without an
uninstall or data erase, and launch the preserved user-local Jak 1 data with:

```sh
xcrun devicectl device install app \
  --device 6A4111AB-1663-508A-98D9-F0C1A9EA7863 \
  /private/tmp/GOALPad-cp36-device/Build/Products/Release-iphoneos/GOALPad.app

xcrun devicectl device process launch \
  --device 6A4111AB-1663-508A-98D9-F0C1A9EA7863 \
  --terminate-existing --console com.zephyrstudiosllc.GOALPad
```

The first loud producer-return record occurred at engine frames 815/816/817.
After roughly 8 minutes 45 seconds, the exact cache file was copied from only
the app data-container cache domain to:

```text
/private/tmp/GOALPad-cp36-camera-physical-final.log
SHA-256 b8b45f06e74a04ed05a321a12a369af1fada1414a9e4ffe344b3ef395f93cb6b
```

Its final values were:

```text
run=16568035587374465836 frame=31396 engine=31396 tick=31396 chain=1
chains_sent=31396 chains_rendered=31396 chains_dropped=0
frames_without_chain=0 frames_with_multiple_chains=0 drawable_misses=0
producer_alternations=4711
live_mismatches=0 packet_mismatches=0
presentations_completed=31394 presentation_drops=1 presentation_order_mismatches=0
merc_missing_bone_slots_total=0 merc_models_with_missing_bone_slots_total=0
```

The retained final return was engine frames 31394/31395/31396 with distances
`0.026232720/0.026596263/0.005119924`. Thus approximately 15 percent of physical
frames completed a strong consecutive producer `A/B/A` return, while the
submitted packets exactly matched that producer, physical presentation order
did not reverse, and no enabled Merc effect referenced an unpopulated palette
slot. This localizes the measured camera oscillation before the renderer packet
copy; it does not yet name which Jak 1 camera input or update is wrong.

No broad app container, retail data, unified log archive, screenshot, or
sysdiagnose was copied. After the final record was secured, PID 7385 received
normal SIGTERM and the attached console confirmed signal 15. The app remains
installed and its data remains intact.

### Maintainer visual result

After the bounded run, the maintainer reported that this was one of the best
runs yet. The camera had only slight "Parkinson's" rather than the violent
Checkpoint 35 jitter, and normal gameplay was enjoyable enough to collect
several power cells. This is a meaningful physical improvement, but not a full
camera fix.

Jak still became incorrectly oversized, and the volumetric/Flat-Stanley defect
returned. Therefore the Jak 1 W-lane addition is insufficient to fix live Merc
deformation. Keep that visual result paired with the numeric finding that every
required weighted palette slot was present: the next probe must validate the
values and provenance of those present matrices rather than rechecking slot
membership.

The console again repeated `sp-launch-particles called during processing, and
queue is full`. It remains unattributed and is not evidence for either visual
defect.

## Next executable task

For camera, inspect the Jak 1 live producer inputs and update ordering around
`cam-update`/`*camera-combiner*`; renderer packet copying, chain cadence, and
physical presentation order are now clean for the captured run. The next test
must classify which producer component returns and compare the same gameplay
path with the ordinary OpenGOAL host before changing behavior.

For Merc, add a bounded live diagnostic at the next unproved seam: validate
finite/non-degenerate required palette matrices after the GOAL calculation-list
dispatcher and before Metal upload. Keep it behavior-neutral until it identifies
the first invalid live value. Do not fold the unrelated particle queue into
either fix without a deterministic link.

# Checkpoint 37: fractional display debt, explicit touch controls, and Merc palette health

## Scope and implementation

Checkpoint 37 makes two related camera-cadence behavior changes and two
independent bounded additions.

`GOALPadDisplayClock` now accumulates fractional 60 Hz frame debt across
`CADisplayLink.targetTimestamp` intervals rather than rounding every callback
independently. It emits one through four integral game steps, carries only the
fractional residual, and clears residual debt after invalid input, lifecycle
reset, or a capped long stall. Complementary early/late intervals therefore do
not become a false alternating integral cadence. The display link also requests
a fixed 60 Hz minimum/maximum rather than the prior adaptive 30-through-60
range. Those changes must be separated in any causal A/B.

The touch layer now has a stationary left movement stick. Free camera dragging
is removed while generic face-button taps and up/left/right swipes remain. A
small yellow C-stick to the right of Start snaps outside its deadzone to eight
GameCube-like directions. A rectangular Roll control holds L1 continuously; an
upward drag pulses Cross for six frames without releasing L1, and finger-up
immediately clears L1.

The Merc renderer now inspects present, required weighted palette slots without
changing the draw. It counts non-finite matrices, degenerate bases, incoherent
source bases, and affected models. The bridge and diagnostics overlay expose
current and cumulative counts plus the latest numeric slot, model/matrix hashes,
axis norms, normalized determinant, and source-base evidence.

Checkpoint 34's camera-zone proposal remains historical. This checkpoint
supersedes that touch direction because the maintainer explicitly removed free
camera swipe in favor of an explicit C-stick.

## Deterministic and build validation

The final shared tree passed:

```sh
Scripts/run-camera-timing-check.sh
Scripts/run-touch-controls-check.sh

cmake --build OpenGOAL/build/Release/bin \
  --target metal-camera-trace-test \
           jak1-mips2c-joint-regression-test \
           metal-proof -j4

OpenGOAL/build/Release/bin/game/metal-camera-trace-test
OpenGOAL/build/Release/bin/game/jak1-mips2c-joint-regression-test
OpenGOAL/build/Release/bin/game/metal-proof
```

The camera timing and touch host checks passed. The camera trace passed 23/23,
the Jak 1 joint regression passed 2/2, and the deterministic Metal proof ended
with `METAL PROOF PASSED`, including healthy, missing, non-finite,
rank-deficient, coherent, and incoherent palette cases. The first sandboxed
touch invocation could not run Swift's Observation macro plugin, and the first
sandboxed Metal launch could not access an SDL display; the corresponding
approved unsandboxed reruns passed.

The following application builds passed:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/GOALPad-cp37-macos -jobs 4 \
  CODE_SIGNING_ALLOWED=NO ENABLE_PREVIEWS=NO build

xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=96C5C21A-B925-4213-82A3-90DCB8518339' \
  -derivedDataPath /private/tmp/GOALPad-cp37-sim -jobs 4 \
  CODE_SIGNING_ALLOWED=NO ENABLE_PREVIEWS=NO build

xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-cp37-device -jobs 4 \
  -allowProvisioningUpdates ENABLE_PREVIEWS=NO ENABLE_DEBUG_DYLIB=NO build
```

The approved M5 simulator was update-installed without an uninstall, launched
with preserved data, and returned to `Shutdown`. The signed Release executable
is thin ARM64 with SHA-256:

```text
5a64d0e15fb54715f5e2aea6bb5b626474a23a12829d73104e1a78dd3c41540f
```

Xcode signed it with team `D2YYJ54Q6V`; decoded entitlements remain limited to
the application identifier, team identifier, and `get-task-allow`. The embedded
development profile expires `2026-08-06T23:51:59Z`.

## Simulator diagnostic result

The simulator's final copied record reached frame 3,000 with matched live and
packet camera values, equal sent/rendered chains, and no missing Merc palette
slots. Earlier simulator sampling retained an intro-logo event; the exact final
record retained a later non-Jak model hash. The copied record is:

```text
/private/tmp/GOALPad-cp37-camera-sim.log
SHA-256 689c79cd737daa2cbd59b198ee0519ce7463830c5ca5e57810d1fcc060ed6de6
```

Simulator presentation completions remain zero because its SDK path omits the
physical drawable timing API.

## Authorized physical result

The maintainer explicitly kept physical access authorized. The signed
Checkpoint 37 app was update-installed on **Z iPad Pro** without uninstalling
or erasing its preserved data. The first launch's recoverable record stopped at
frame 1,681; its current palette health was zero and its retained non-finite
event was confined to the intro logo. At the maintainer's request, that process
was terminated and the same installed build was relaunched with an attached
console as PID 7692.

The second run lasted about eight minutes, reached Misty Island and later
Training, and ended at frame 29,666. The exact final cache was copied to:

```text
/private/tmp/GOALPad-cp37-camera-physical-final.log
SHA-256 18d8352ea285d2c5123dd73120175843e7ff748af4851e5762bdba79e490243f
```

Its final values were:

```text
run=9157121099970670899 frame=29666 engine=29666 tick=29666 chain=1
chains_sent=29666 chains_rendered=29666 chains_dropped=0
frames_without_chain=0 frames_with_multiple_chains=0 drawable_misses=0
late_present_submissions=41 producer_alternations=1661
live_mismatches=0 packet_mismatches=0
presentations_completed=29645 presentation_drops=21 presentation_order_mismatches=0
merc_missing_bone_slots_total=0 merc_models_with_missing_bone_slots_total=0
merc_nonfinite_bone_matrices_total=7706 merc_degenerate_bone_matrices_total=343
merc_incoherent_bone_sources_total=0 merc_models_with_palette_health_issues_total=1388
```

The final current-frame palette-health counts were zero. The retained event was
frame 27,647, model hash `1739199570720925712`, slot 4. Repository FNV matching
resolves the hash to `speaker-lod0`; slot 4 is its `speaker` joint. The earlier
event resolves to `logo-volumes-english-lod0`. Neither retained event is Jak,
so the diagnostic did not capture the reported Jak deformation and its totals
are not attributed to that visual bug.

All 29,666 sent chains rendered, producer and submitted camera packets matched,
and Metal recorded no presentation-order reversal. The strong producer-return
rate was about 5.6 percent, lower than Checkpoint 36's roughly 15 percent, yet
the maintainer found this camera visually worse. The return count is therefore
not a camera-quality score and does not validate the fractional-debt change.

Only the numeric cache file was copied. No broad app container, retail data,
unified log archive, screenshot, or sysdiagnose was captured. The attached
process shut down the kernel and exited with code zero. The app remains
installed and its data remains intact.

### Maintainer visual result

The maintainer reached the farthest point yet in a GOALPad run, which is useful
sustained-runtime evidence. Nevertheless, Checkpoint 37 felt worse than
Checkpoint 36 for camera movement, world-depth/z-fighting, and Merc deformation.
Metallic textures also developed a new flicker that looked like a localized
z-fight. Checkpoint 37 is physically rejected as a camera or visual-fidelity
improvement. No separate physical verdict was given for the revised touch
ergonomics, so physical multitouch remains unvalidated.

## Planned side-by-side media behavior

The maintainer requested Hearthstone-like iPad multitasking behavior: when
GOALPad remains visible beside another app, gameplay and game audio should keep
running while outside music or video audio also plays. `ROADMAP.md` Stage 6 now
records this as planned work. Implementation must distinguish actual iPad
multitasking/focus signals from true backgrounding and select an explicit audio-
mix policy; the current app still stops frames and audio on every inactive or
background transition.

## Next executable task

Do not tune the producer-return threshold or presentation path from this run.
For camera, run the smallest A/B that restores Checkpoint 36's interval rounding
while retaining all Checkpoint 37 diagnostics and holding the fixed-60 display-
link policy constant; the current provenance counters do not explain why
fractional debt looked worse.

For Merc, extend the existing behavior-neutral seam with a 28-bit non-finite
lane mask and Jak-only consecutive-frame scale/aspect tracking for
`eichar-lod0`. Retain previous/current hashes, axis norms, source base, slot, and
frame only when a finite scale or aspect discontinuity crosses a conspicuous
bounded threshold. This can capture uniform ultrasize and Flat-Stanley collapse
without conflating them with zero-scale intro or prop models.

Treat the new metallic-material flicker and the broader world-depth fighting as
separate renderer observations. A read-only audit found no Checkpoint 37 shader,
PSO, or material-state change; timing can expose an existing shimmer but does
not directly reach a Metal pipeline key. Two pre-existing seams now need
deterministic coverage: Merc's `SRC_0_DST_DST` Metal alpha factors differ from
the OpenGL blend formula, and Metal TIE batches coplanar envmap base passes for
all trees before their second passes while OpenGL pairs each tree's passes.

Extend `metal-proof` with overlapping translucent Merc envmap draws that assert
RGBA against the OpenGL blend formula, plus a two-tree TIE envmap fixture that
compares current category-batched order with paired order and proves repeated-A
color/depth hashes under nearby `A/B/A` cameras. For bounded live evidence, add
only display-ratio 1/2/3/4 totals and Merc envmap zero/nonzero transition counts.
Do not attribute either flicker to camera cadence, Merc matrices, or the
particle-queue warning until one of those proofs or a single-toggle physical A/B
identifies the seam.

# Checkpoint 38: original GOALPad app icon

## Scope

Checkpoint 38 adds one original app-icon design requested by the maintainer. It
uses a centered segmented ancient-machine glyph in dark forged metal, restrained
cyan recess reflections, a cold upper-edge glint, and hot orange backlight on an
opaque near-black field. The mark is intentionally abstract: it does not copy a
Jak character, franchise logo, Son of Mar seal, or Precursor rune.

The built-in image generation path produced one square raster master. The
selected art was resized into the normal iOS 1024-pixel slot and the complete
macOS 16-through-1024-pixel ladder in:

```text
GOALPad/Assets.xcassets/AppIcon.appiconset/
```

`Contents.json` names each of the 11 new PNGs. The existing optional iOS dark
and tinted appearances remain unassigned; iOS falls back to the normal dark
artwork rather than using an improvised monochrome variant.

## Validation

`jq empty` accepted `Contents.json`. Every PNG has the exact catalog dimension,
is opaque RGB with no alpha, and retains background pixels in all four corners;
the artwork has no baked rounded-corner mask. Visual checks at 64 and 32 pixels
kept the orange core and segmented silhouette recognizable.

Fresh unsigned builds passed:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/GOALPad-icon-macos -jobs 4 \
  CODE_SIGNING_ALLOWED=NO ENABLE_PREVIEWS=NO build

xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-icon-ios -jobs 4 \
  CODE_SIGNING_ALLOWED=NO ENABLE_PREVIEWS=NO build
```

The macOS build succeeded in 65.681 seconds. The generic iOS build succeeded in
64.615 seconds with no asset-catalog warning or notice and emitted opaque
120x120 iPhone and 152x152 iPad icons. Existing unrelated generated-source
warnings and the AppIntents metadata-skipped warning remain.

No simulator or physical device was accessed for this icon checkpoint. Actual
Home Screen/Dock appearance and dedicated dark/tinted variants remain
unvalidated.

# Checkpoint 39: distribution direction and iPhone shell launch

## Distribution direction

The maintainer selected App Store distribution as the preferred end-user path
so family and other users can install GOALPad without Xcode. Public presentation
should use original GOALPad branding and calm, neutral language such as **Add
compatible game data** rather than franchise-led marketing. Store metadata,
icons, screenshots, preview media, and first-run setup should not use supported
game names, characters, official artwork, logos, or recognizable franchise
symbols. Technical contributor documentation and App Review notes remain
precise and transparent; neutral product language is not concealment.

The executable/data boundary does not change. A public binary contains the
complete OpenGOAL/GOAL workload compiled ahead of time into the normally signed
application, but no retail game data. Each user supplies compatible prepared
data locally. App Store availability remains planned rather than approved and
requires separate licensing, intellectual-property, and App Review assessment.

`docs/PROJECT_OVERVIEW.md`, `ROADMAP.md`, and `docs/BUILDING.md` now require
GitHub, TestFlight, and App Store archives to fail closed when the expected AOT
manifest is absent or incomplete. At the current pin the preflight requires 519
generated C files: 518 AOT object translations plus `aot_boot_manifest.c`, whose
`goal_aot_boot_file_count` is 518. The buildable shell without those files is an
explicit development convenience, not a publishable artifact. Documentation is
now clear, but build-phase/CI enforcement remains follow-up implementation.

The documented preflight passed in the primary worktree:

```sh
test -f Generated/jak1-aot/aot_boot_manifest.c
test "$(find Generated/jak1-aot -maxdepth 1 -type f -name '*.c' | wc -l | tr -d ' ')" = 519
rg -q 'const int goal_aot_boot_file_count = 518;' \
  Generated/jak1-aot/aot_boot_manifest.c
```

## Physical iPhone launch

The exact complete-AOT Release artifact built from parent
`ef0bed9774a725d6ea9261d5eed9f35dcbcc3841` and OpenGOAL
`9f774b31232d7f642378ef13ef0ec7f75a46a357` was reused. Its thin arm64
executable SHA-256 is:

```text
7dc3c1587de9445756246908c8e8fb3ac2dc6be3d5842512f7a96b6ac30e9e12
```

The binary contains `_goal_aot_boot_files` and `_goal_aot_boot_file_count`. It
had already passed the full signed Release build and physically booted the real
kernel, `KERNEL.CGO`, `GAME.CGO`, title, Village 1, Metal, and 48 kHz audio on Z
iPad Pro.

CoreDevice resolved **Z iPhone Air** as connected, model `iPhone18,4`, identifier
`C0CAC382-DF64-5728-998E-A51F86A94E61`. The same app was installed without an
uninstall and launched successfully by bundle identifier:

```sh
xcrun devicectl device install app \
  --device C0CAC382-DF64-5728-998E-A51F86A94E61 \
  /private/tmp/GOALPad-cp38-aot-device.aOxKzE/Build/Products/Release-iphoneos/GOALPad.app

xcrun devicectl device process launch \
  --device C0CAC382-DF64-5728-998E-A51F86A94E61 \
  --terminate-existing --console com.zephyrstudiosllc.GOALPad
```

Installation and process launch passed. No retail data was copied or inspected.
iOS app containers are device-local, so the iPad's `Documents/Jak1` directory
does not accompany an app installation on iPhone. The phone correctly requires
its own user-directed compatible-data import. iPhone gameplay, Metal output,
audio, touch ergonomics, safe areas, lifecycle, memory behavior, and sustained
runtime remain unvalidated until that import is complete and the maintainer
performs a physical play pass. Landscape is the first recommended layout; the
current fixed touch geometry is expected to overlap in iPhone portrait.

# Checkpoint 40: standard-window visionOS port

The existing GOALPad target now builds for visionOS without adding a second
runtime or an immersive presentation path. Commit `b9b9f2e3` preserves the
ordinary SwiftUI `WindowGroup` and limits the port to four platform seams:

- visionOS uses `UIView.contentScaleFactor` because `UIWindow.screen` is
  unavailable there;
- the existing Apple display-time reset and MIPS2C bones fallback also apply to
  visionOS;
- the existing `AVAudioSession` lifecycle also applies to visionOS; and
- first-run copy directs visionOS users through the Import button and Files
  providers.

The isolated branch `feat/visionos-windowed-port` committed the source as
`302538f528d4a365def9ee46bcfef56a3c614858`; that commit was reviewed and
cherry-picked to the primary branch as `b9b9f2e3`. The OpenGOAL child remained
clean at `9f774b31232d7f642378ef13ef0ec7f75a46a357`, and the project file was not
changed by this checkpoint.

Generic visionOS, generic iOS, and ARM64 macOS Debug builds passed. The local
Vision Pro simulator build also passed, installed, and launched as PID `41986`.
A screenshot showed the expected standard window, and the fresh sandbox created
`Documents/Jak1/iso` and `Documents/Jak1/fr3`. The simulator was returned to its
original Shutdown state. Camera timing and touch-control deterministic checks
also passed.

For physical provisioning, the first generic Release build produced a signed
arm64 XROS executable but its local profile did not contain the Vision Pro. The
first install therefore failed with `0xe8008012`. Rebuilding against the exact
Xcode destination registered the headset UDID in a new profile:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Release \
  -destination 'id=00008112-001408160C78A01E' \
  -derivedDataPath /private/tmp/GOALPad-visionos-physical \
  -jobs 4 -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  ENABLE_PREVIEWS=NO ENABLE_DEBUG_DYLIB=NO build

xcrun devicectl device install app \
  --device 7C8DED98-3B86-55CE-B49D-C514E47F745A \
  /private/tmp/GOALPad-visionos-physical/Build/Products/Release-xros/GOALPad.app
```

The targeted build completed and update-install passed. Its executable SHA-256
is `6af9aff3423b9709496cf8d6d63088636f0a9a8cea48f17a63cdc14b2580dde6`, and
`nm` contains `_goal_aot_boot_files` and `_goal_aot_boot_file_count`. Physical
launch is still pending: visionOS denied the first launch because the local
developer profile has not yet been explicitly trusted on the headset. The
maintainer must complete Settings > General > VPN & Device Management >
Zachary Schwendiman > Trust or Allow & Restart, after which `devicectl` should
retry the launch. No app uninstall or data deletion was performed.

Physical visionOS gameplay, Metal output, controller input, audio, data import,
and sustained runtime remain unvalidated. With no prepared user data on the
headset, the next expected runtime evidence is only a live first-run setup
window.

# Checkpoint 41: raw-disc-image import clarity

The setup picker accepts `.folder` only, so Files intentionally dims a naked
`.iso`. The ISO is not still compressed: OpenGOAL must parse and verify its disc
filesystem, generate the prepared FR3 data, and rebuild the flat
`out/jak1/iso` layout. Merely allowing `.iso` in the picker would not produce
bootable GOALPad data.

`GameDataSetupView` now states beside the importer that it expects the prepared
`out/jak1` folder and that raw ISO files are dimmed because this build cannot
prepare them. `docs/PROJECT_OVERVIEW.md` labels on-device preparation as
**Investigating**, and `ROADMAP.md` records the staged path while preserving the
working prepared-folder importer and desktop-compatible output.

The read-only feasibility audit found a reusable in-process ISO reader, but the
current desktop extractor is not a safe mobile library boundary. Complete
preparation also needs the decompiler/FR3 path and offline `(mi)` output builder;
the current compiler target brings desktop listener/debugger code and JIT test
support, and the level extractor starts one worker per level. The next narrow
proof is therefore a streaming, bounds-checked ISO reader with recoverable
errors, cancellation/progress callbacks, and synthetic fixtures. It must not be
reported as playable import until the later FR3 and output-builder phases pass.

Validation from the exact primary branch:

```sh
xcodebuild -quiet -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-iso-ux-ios -jobs 4 \
  CODE_SIGNING_ALLOWED=NO ENABLE_PREVIEWS=NO build

xcodebuild -quiet -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'generic/platform=visionOS' \
  -derivedDataPath /private/tmp/GOALPad-iso-ux-vision -jobs 4 \
  CODE_SIGNING_ALLOWED=NO ENABLE_PREVIEWS=NO build
```

Both commands returned exit 0. Existing generated/OpenGOAL conversion warnings
remain. No game data was copied, read, or modified for this audit or validation.

# Checkpoint 42: local-first iCloud save engine and provisioning gate

Commit `3bd3abd3` adds the save-sync implementation, Settings UI, deterministic
tests, documentation, and the canonical iCloud Documents entitlements file.
The isolated worker source commit was `8f9f37dc`; it was reviewed and
cherry-picked onto the primary branch. The seven-line target capability wiring
remains isolated as `63808058` and is intentionally not present on the primary
branch because enabling it currently breaks signed-device builds.

Gameplay continues to use OpenGOAL's existing desktop-compatible local root:

```text
Library/Application Support/OpenGOAL/jak1/saves
```

The runtime never receives an iCloud path. When the capability is provisioned,
an actor mirrors stable file snapshots under the app's private ubiquity
container at `Documents/OpenGOAL/jak1/saves`. The merge state and local conflict
archive live separately under `Application Support/GOALPad`; the cloud conflict
archive also lives outside the canonical save mirror. This keeps raw paths such
as `BASCUS-97124AYBABTU!/bank0.bin` compatible with desktop OpenGOAL.

The engine synchronizes unconditionally at launch, on foreground/manual sync,
and after a coalesced completed-frame check detects a local save change. Native
memcard writes are synchronous and close before `runFrame` returns. File size
and modification dates are the cheap change trigger; SHA-256 is the merge and
conflict identity. A stored baseline distinguishes one-sided edits from true
divergence. Initial or two-sided divergence leaves both canonical copies
untouched, archives both versions with full hashes, and surfaces the file list
in Settings. Switching iCloud identities invalidates the old baseline. Missing
files are restored from the surviving side rather than propagating deletion.

All iCloud setup and file work runs off the main actor. Local files must produce
the same bytes and metadata across a settling interval before upload. Evicted
ubiquitous files are requested and awaited until their download status is
current before hashing. The engine records the exact local snapshots that were
merged, so a later save completed during cloud work remains detectable on the
next frame. Turning the Settings toggle off cancels a pending delayed scan and
prevents its result from replacing the disabled state. If iCloud identity or
the ubiquity URL is unavailable, gameplay remains local and Settings reports
that iCloud is unavailable.

The private mirror uses only these standard entitlements:

```text
com.apple.developer.icloud-container-identifiers =
  iCloud.com.zephyrstudiosllc.GOALPad
com.apple.developer.ubiquity-container-identifiers =
  iCloud.com.zephyrstudiosllc.GOALPad
com.apple.developer.icloud-services = CloudDocuments
```

`NSUbiquitousContainers` is intentionally absent. It controls iCloud Drive
presentation/sharing and public document scope defaults to false; this mirror
is private app state, not a user-managed Drive folder.

Deterministic synthetic validation passed:

```sh
Scripts/run-save-sync-check.sh
```

The suite covers iCloud unavailability, local-only upload, cloud-only download,
known one-sided changes, initial and two-sided conflicts, preserving both
archives, missing-side restoration, iCloud identity changes, a file changing
during its stable snapshot, and a second save completed after the first snapshot
but before cloud work finished.

Exact-primary unsigned builds also passed:

```sh
xcodebuild -quiet -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-iso-ux-ios -jobs 4 \
  CODE_SIGNING_ALLOWED=NO ENABLE_PREVIEWS=NO build

xcodebuild -quiet -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'generic/platform=visionOS' \
  -derivedDataPath /private/tmp/GOALPad-iso-ux-vision -jobs 4 \
  CODE_SIGNING_ALLOWED=NO ENABLE_PREVIEWS=NO build

xcodebuild -quiet -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/GOALPad-icon-macos -jobs 4 \
  CODE_SIGNING_ALLOWED=NO ENABLE_PREVIEWS=NO build
```

All three returned exit 0. Existing OpenGOAL conversion warnings remain.

Signed capability validation is blocked by product identity, not source
compilation. With the project's current `D2YYJ54Q6V` Personal Team, Xcode
reports that personal teams do not support iCloud and that the wildcard profile
lacks the iCloud capability, container, and three entitlements. A valid Zephyr
Studios LLC Apple Development identity for paid team `V729QMY3V6` is installed,
but a generic build override for that team failed with:

```text
The app identifier "com.zephyrstudiosllc.GOALPad" cannot be registered to your
development team because it is not available.
```

It also reported the missing iCloud container/profile entitlements and a stale
Xcode account credential with `missing Xcode-Token`. The existing bundle ID is
therefore tied to the Personal Team and cannot simply be reused on the company
team. The maintainer must choose a new paid-team bundle identifier before the
capability commit can be integrated. Changing team/application identity may
prevent an in-place update of current development installs, so preserve or
export the iPad's existing local saves before any device migration.

Real iCloud transfer, evicted-file behavior, actual conflict presentation,
iPad-to-iPhone migration, physical devices, and a signed iCloud-capable build
remain unvalidated. The next executable task is to select the paid-team bundle
identifier and refresh the Zephyr Studios LLC Xcode account, then provision the
container, integrate `63808058`, build signed artifacts, and test two devices
with user-owned saves. OpenGOAL remains clean at
`9f774b31232d7f642378ef13ef0ec7f75a46a357`.

# Checkpoint 43: Eco product identity and shared visionOS capability wiring

The public product name is now **Eco**, with App Store subtitle **Native
OpenGOAL Runtime**. The maintainer selected paid team `V729QMY3V6` and bundle
identifier `com.zephyrstudiosllc.eco` in Xcode. The matching private iCloud
Documents container is `iCloud.com.zephyrstudiosllc.eco`.

The repository, target, scheme, executable, source symbols, diagnostics paths,
and save-sync state directories remain named GOALPad. This keeps the change
narrow and preserves internal compatibility. `CFBundleDisplayName` and the few
visible product strings use Eco; logging subsystems use the shipping bundle
identifier. The new bundle identifier is a separate installed-app sandbox, so
existing GOALPad game data, settings, and local saves do not migrate
automatically. Preserve the old installation and export its saves before any
device migration.

The existing shared Apple target remains the visionOS implementation. It still
uses the ordinary SwiftUI `WindowGroup`; no new target, immersive space,
volumetric window, RealityKit path, renderer refactor, or asset-loader change
was added. Its existing Foundation Application Support, Documents,
security-scoped import, and ubiquity-container URLs remain sandbox-resolved on
visionOS.

The target now points both configurations at `GOALPad/GOALPad.entitlements`,
marks the standard iCloud capability, and uses only CloudDocuments plus the two
matching container arrays. No CloudKit, App Group, push, public iCloud Drive
scope, or private entitlement was added.

Deterministic identity and save validation passed:

```sh
plutil -lint GOALPad.xcodeproj/project.pbxproj \
  GOALPad/GOALPad.entitlements GOALPad-Info.plist

test -f Generated/jak1-aot/aot_boot_manifest.c
test "$(find Generated/jak1-aot -maxdepth 1 -type f -name '*.c' | wc -l | tr -d ' ')" = 519
rg -q 'const int goal_aot_boot_file_count = 518;' \
  Generated/jak1-aot/aot_boot_manifest.c

Scripts/run-save-sync-check.sh
```

All returned exit 0. The save suite still covers offline use, upload/download,
one- and two-sided divergence, conflict preservation, account switching,
stable snapshots, and saves completed during cloud work.

An unsigned ARM64 macOS Debug build completed with the full AOT set:

```sh
xcodebuild -quiet -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/Eco-mac -jobs 2 \
  CODE_SIGNING_ALLOWED=NO ENABLE_PREVIEWS=NO build
```

The final incremental verification returned exit 0. Its generated Info.plist
reports `com.zephyrstudiosllc.eco` and display name `Eco`. Existing OpenGOAL
conversion warnings remain.

Full recompilation for iOS and visionOS was intentionally not repeated after
the maintainer confirmed that the platform/runtime port was already built and
validated at Checkpoints 40 and 42. Read-only resolved-setting checks for both
generic destinations returned exit 0 and report:

```text
CODE_SIGN_ENTITLEMENTS = GOALPad/GOALPad.entitlements
DEVELOPMENT_TEAM = V729QMY3V6
INFOPLIST_KEY_CFBundleDisplayName = Eco
PRODUCT_BUNDLE_IDENTIFIER = com.zephyrstudiosllc.eco
SUPPORTED_PLATFORMS = iphoneos iphonesimulator macosx xros xrsimulator
TARGETED_DEVICE_FAMILY = 1,2,7
```

Signed capability validation remains blocked. The current keychain query
`security find-identity -v -p codesigning` reports `0 valid identities found`.
Restore or recreate the paid-team signing identity and refresh the Xcode
account, then provision the App ID and iCloud container before signed iOS or
visionOS builds. Real iCloud transfer/conflict behavior, cross-device save
migration, and physical Eco installs remain unvalidated. No device was accessed
and no user game data was read or changed in this checkpoint.

# Checkpoint 44: Eco Pro public-name correction

The App Store and display name is **Eco Pro** because **Eco** was unavailable.
This changes only public naming: the paid-team bundle identifier remains
`com.zephyrstudiosllc.eco`, the private iCloud container remains
`iCloud.com.zephyrstudiosllc.eco`, and the internal target, executable, source,
runtime, diagnostics, and save-state names remain GOALPad.

Both target configurations resolve `CFBundleDisplayName` to `Eco Pro`. The
first-run setup, diagnostics header, conflict explanation, current public docs,
and App Store metadata use the same name. The dark-sheen icon concepts contain
no text and remain valid; their recorded exact generation prompts retain the
then-current working name Eco rather than being rewritten after generation.

Validation for this naming-only correction is limited to plist/project parsing,
current-string consistency, and resolved build settings. It does not repeat the
already completed OpenGOAL/AOT platform compilation:

```sh
plutil -lint GOALPad.xcodeproj/project.pbxproj \
  GOALPad/GOALPad.entitlements GOALPad-Info.plist

xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO -showBuildSettings

xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'generic/platform=visionOS' \
  CODE_SIGNING_ALLOWED=NO -showBuildSettings
```

Both settings queries must continue to report paid team `V729QMY3V6`, bundle
`com.zephyrstudiosllc.eco`, display name `Eco Pro`, the shared platform list,
and `GOALPad/GOALPad.entitlements`. Signed provisioning and physical-device
validation remain pending for the reasons recorded in Checkpoint 43.

# Checkpoint 45: enforced Jak 1 release corpus and Jak II iPhoneOS link proof

The parent now has one generic generated-AOT verifier and host generators for
the mutually exclusive Jak 1 and Jak II corpora. `Scripts/generate-jak1-aot.sh`
and `Scripts/generate-jak2-aot.sh` clear only their fixed generated directories,
write `coverage.tsv`, and fail unless the complete build graph, manifest, file
counts, and coverage are complete. Current verified totals are 518 Jak 1
objects with 10,596 emitted and 7 native functions, and 840 Jak II objects with
18,479 emitted and 7 native functions. Generated C, headers, and coverage remain
ignored build products.

The GOALPad Xcode target runs the Jak 1 manifest-and-coverage preflight before
every Release compile. Its inputs are explicit so Xcode's user-script sandbox
can read them, and `coverage.tsv` is excluded from target membership so the
private build report is not copied into the application bundle. The generated
source compile and final application link prove the individual files are
present. A fresh generic iPhoneOS Release build with an empty DerivedData
directory passed. After excluding `coverage.tsv`, an unsigned generic iOS
Release rebuild explicitly removed that stale resource and produced no
`coverage.tsv` anywhere in the app bundle. Both builds produced the same thin
ARM64 app binary hash as the pre-phase clean-build audit:

```text
99ada6eaf3446bf0105df2995028fca8e9f0da2387021e9fdae565f94051781e
```

The same audit passed fresh ARM64 macOS Debug and generic iOS Release builds,
the camera/touch/save deterministic checks, and four focused host tests: Metal
camera trace, Jak 1 MIPS2C joint regression, kernel-core smoke, and representative
AOT execution. The artifact is unsigned build evidence; no device was accessed.

OpenGOAL commit `7a9341c461dde54928588aa26b5a1beb7ca4bb21` adds a separate strict
iPhoneOS/ARM64-only Jak II full-AOT final-link product. It validates exactly 840
manifest entries and generated C/header pairs, compiles all 840 translations
plus the manifest with `-fno-strict-aliasing`, and links only
`jak2-kernel-core`. The isolated implementation build produced a thin ARM64
iOS Mach-O, compiled 841 generated C files with the required aliasing flag, and
resolved the manifest, first/last corpus entries, Jak II kernel core, and zstd.
Fresh host regressions passed 3/3, and the explicit user-data `--with-game`
probe registered all 840 units, loaded KERNEL 8/8 and GAME 465/465, then ran 100
dispatcher frames. No signing, app launch, simulator, or device claim is made.

The generated games remain separate because their AOT symbols overlap. Jak II
is not wired into the Eco Pro application target and does not supersede Jak 1.
The active Jak 1 blocker is now the raw-disc preparation path: Checkpoint 41's
change only explained why a naked ISO is dimmed; it did not implement ISO to
`iso/` plus `fr3/` conversion. The next executable work is the bounded,
recoverable ISO reader and synthetic fixtures, followed by revision validation,
bounded FR3 generation, and the flat runtime `iso/` builder.

# Checkpoint 46: bounded Jak 1 ISO reader and fail-closed revision validation

OpenGOAL commit `5cffc4d10fa0f23feb7c2ae109d9f93417f25494` adds the first two
native raw-disc preparation phases without enabling the app picker. The
portable ISO9660 reader uses typed recoverable errors, strict descriptor,
extent, record, path, depth, entry, file, image, and total-output limits,
bounded chunked reads and writes, progress and cancellation callbacks,
incremental XXH64 hashing, and owned-staging cleanup. The legacy desktop
reader APIs remain as adapters, including the `WATER_AN.CGO` to
`WATER-AN.CGO` compatibility rewrite.

The second isolated library forces hashing, requires a root DGO directory and
exactly one game executable, and fails closed against the five Jak 1 revision
fingerprints already supported by OpenGOAL. It verifies serial, executable
hash, file count, and aggregate contents hash, then atomically writes the same
desktop-compatible `buildinfo.json`. Reader cancellation retains its typed
cause, and a pre-existing staging directory is never overwritten or removed.
The desktop extractor database now consumes the same catalog; its real lookup
caller and full extractor link passed.

Independent validation passed 11/11 safe-reader synthetic cases, the isolated
host CTest suites at 1/1 and 2/2, all nine direct revision-validator cases, the
desktop database parity test, and normal desktop extractor link/caller smoke.
Both isolated libraries compiled for generic iPhoneOS as thin ARM64 archives;
the validator archive SHA-256 was:

```text
463fdfb6029ae30e9e600528d00b44e26e733888243abca7dc9ba475495d351d
```

An inspection-only run of the new reader against the maintainer's local naked
ISO performed no writes and reported 337 files, 9 directories, a root DGO
directory, and executable `SCUS_971.24`. The existing extracted copy's
`buildinfo.json` identifies the matching `SCUS-97124` revision and known ELF
hash. No retail data was committed or copied into the repository.

This checkpoint is not a complete importer. It does not generate the 25 retail
FR3 files, `test-zone.fr3`, CGO/DGO archives, or the final 321-file runtime
`iso/` directory, and it does not add ZIP ingestion or change the folder-only
Swift picker. The next executable phase is a bounded, one-DGO-at-a-time FR3
preparer plus a checked test-zone retail catalog, followed by the isolated
offline Jak 1 output builder and only then the app bridge and raw-ISO UI.

# Checkpoint 47: checked Jak 1 preparation graph and full camera provenance

The parent baseline entering this checkpoint was `7e3d0e89`; the reviewed
nested OpenGOAL checkpoint is now `7cf217fea`.
`f03806f7` corrects the prepared-data contract to the exact 25-file FR3 corpus:
`GAME.fr3` plus 24 retail level files. `test-zone.fr3` is not a required player
output. `GameDataInspector` also accepts an explicit staging directory so a
future importer can validate a candidate install before changing the active
game directory. The only known parent dirt is the maintainer-owned
`GOALPad.xcodeproj/project.pbxproj` normalization; it remains unstaged and must
not be discarded or swept into an agent commit.

The Library-first shell from parent `0712ba8c` remains the launch surface. It
shows four game tiles, exposes import through the menu, boots only a ready Jak 1
install, preserves local user-selected artwork, and does not imply that Jak II,
Jak 3, or Jak X are playable. It does not yet enable raw ISO selection.

## Import preparation now implemented

The isolated OpenGOAL pipeline now contains:

- a bounded ISO9660 reader and fail-closed five-revision Jak 1 validator;
- checked DGO/CGO readers and writers, a strict prepared-retail catalog, and a
  bounded one-archive-at-a-time FR3 preparer;
- a deterministic output-recipe schema tied to supported revisions, an atomic
  output materializer, and an embedded public output graph;
- a real-catalog proof that matches the checked graph against the maintainer's
  existing extracted copy without reading unrelated objects;
- portable byte-exact generation for directory tpages, game count, and all 14
  game-text/subtitle flat outputs; and
- a bounded portable adapter from an already validated extracted tree into the
  typed generated-artifact inputs. It reads only fixed `CGO/GAME.CGO` and
  `TEXT/0COMMON.TXT` through `TEXT/6COMMON.TXT` paths, rejects symlinks and
  noncanonical GOAL objects, retains cancellation/progress context, and is
  deliberately limited to the initial SCUS-97124 revision supported by the
  current output recipe; and
- a deterministic 518-object public reconstructed-source pack plus a bounded
  portable validator. Generated packs remain ignored build products and no
  retail or generated object bytes were committed.

The real-catalog proof passed with 518 selected sources, 27 source archives,
645 prepared catalog entries, 628 retail occurrences, and aggregate XXH64
`5e920612f4055c04`. The independently generated public source pack contains 518
objects plus its manifest, totals 10,729,469 object bytes, and has aggregate
identity `e3ed59b376d6a079`. Three agent-generated packs were byte-identical; the
canonical checkout revalidated the portable reader and iPhoneOS link seam.

This is still not an end-to-end app importer. A read-only base-game graph audit
found that normal title/gameplay boot does not require repository dialogue or
the example test zone. The next narrow profile is `jak1-base-retail`: preserve
the seven retail COMMON text banks, project `TSZ.DGO` and its generated custom
actor/level outputs out of the graph, and generate seven structurally valid
zero-scene subtitle banks instead of bundling repository subtitle scenes. This
profile and its exact graph/recipe/materializer tests are planned, not yet
implemented. Remaining work also includes adapter-to-builder-to-materializer
composition, the Swift/Objective-C++ worker bridge, recoverable Application
Support staging and active-install switch, and an end-to-end app run. The
current prepared-folder importer must remain available. ZIP ingestion remains
out of this checkpoint.

## Camera, Merc, and material diagnostics

OpenGOAL now traces the exact 15-qword Jak 1 background view/projection packet
layout. The app samples that 240-byte live `*math-camera*` state synchronously
at the DMA send boundary, forwards it only as expected diagnostic state, and
retains full 15-bit live/packet mismatch masks on producer alternation events.
The existing five-qword producer subset remains separately labeled. No camera
math, pacing, DMA order, presentation threshold, or renderer behavior changed.

`80af1f0e2` restores Merc envmap destination-alpha blending and `818a3291d`
keeps the two TIE envmap passes adjacent per tree, matching the OpenGL order.
A read-only follow-up found no remaining source-proven blend/order or stale-
buffer patch: prior GPU work is awaited, Merc stream ranges are per frame and
flush, and the iOS host renders synchronously. Remaining Merc deformation is
still most plausibly upstream palette input. `b96b549b` bridges the existing
pre-upload `eichar-lod0` scale/aspect tracker through MetalHost and the C bridge
into the periodic log, persisted diagnostic snapshot, and diagnostics overlay.
It retains the first and latest discontinuity with frame/tick/chain identity,
matrix hashes, all three axis norms, scale, aspect, and palette source bases so
the next run can distinguish uniform oversizing from aspect collapse. This is
diagnostic-only and does not change a transform or renderer behavior. Metallic
flicker remains unattributed.
`3b2fa5549` adds the next deterministic gate: a nontrivial camera A/B/A TIE
base/shine color identity proof. Both moved camera states retain identical
coplanar base/shine coverage, and the repeated A frame is byte-identical after
the intervening B frame. The next visual step is a separately authorized
physical TIE-versus-Merc envmap isolation pass, not another speculative
renderer change.

## Validation

Canonical host compiler and importer checks:

```sh
cmake --build OpenGOAL/build/Release/bin --target compiler -j4

cmake -S OpenGOAL -B /private/tmp/GOALPad-jak1-public-generated-current \
  -DOPENGOAL_BUILD_JAK1_PUBLIC_GENERATED_ARTIFACTS_ONLY=ON \
  -DBUILD_TESTING=ON -DCMAKE_BUILD_TYPE=Release
cmake --build /private/tmp/GOALPad-jak1-public-generated-current \
  --target jak1-public-generated-artifacts-test \
           jak1-public-generated-artifacts-exactness-test -j4
ctest --test-dir /private/tmp/GOALPad-jak1-public-generated-current \
  --output-on-failure -R '^jak1-public-generated-artifacts' -j1

cmake --build OpenGOAL/build/Release/bin --target goalc-cbackend-sweep -j4
cmake -S OpenGOAL -B /private/tmp/GOALPad-jak1-source-pack-current \
  -DOPENGOAL_BUILD_JAK1_SOURCE_OBJECT_PACK_ONLY=ON \
  -DBUILD_TESTING=ON -DCMAKE_BUILD_TYPE=Release
cmake --build /private/tmp/GOALPad-jak1-source-pack-current \
  --target jak1-output-recipe-core-test jak1-source-object-pack-test \
           jak1-source-object-pack-link-proof -j4
ctest --test-dir /private/tmp/GOALPad-jak1-source-pack-current \
  --output-on-failure \
  -R 'jak1-output-recipe-core-test|jak1-source-object-pack-test' -j1
```

The compiler build passed with existing upstream warnings. Generated-artifact
tests passed 2/2 and reported all 16 outputs byte-identical to the desktop
generator. Source-pack tests passed 2/2. The first source-pack CTest attempt
had one Not Run result because only the pack target, not the registered recipe-
core test executable, had been built; building that target and rerunning the
same tests passed 2/2.

The isolated source-pack final-link proof also passed with:

```sh
cmake -S OpenGOAL \
  -B /private/tmp/GOALPad-jak1-source-pack-current-iphoneos \
  -DOPENGOAL_BUILD_JAK1_SOURCE_OBJECT_PACK_ONLY=ON \
  -DBUILD_TESTING=OFF -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
  -DCMAKE_BUILD_TYPE=Release
cmake --build /private/tmp/GOALPad-jak1-source-pack-current-iphoneos \
  --target jak1-source-object-pack-link-proof -j4
```

The result is thin ARM64, platform iOS, minimum iOS 15.0, SDK 26.5, SHA-256
`e8b66c51f5edbfa15a167b9e19d47cf0f72d66a551ae66cb672ffe65bccf1052`.

Extracted-tree generated-input adapter checks:

```sh
cmake -S OpenGOAL -B /private/tmp/goalpad-jak1-extracted-inputs-host -G Ninja \
  -DOPENGOAL_BUILD_JAK1_EXTRACTED_GENERATED_INPUTS_ONLY=ON \
  -DBUILD_TESTING=ON -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_C_COMPILER_LAUNCHER=/opt/homebrew/bin/ccache \
  -DCMAKE_CXX_COMPILER_LAUNCHER=/opt/homebrew/bin/ccache
CCACHE_DIR=/private/tmp/goalpad-jak1-extracted-inputs-ccache \
  cmake --build /private/tmp/goalpad-jak1-extracted-inputs-host \
  --target jak1-extracted-generated-inputs-test \
           jak1-extracted-generated-inputs-exactness-test \
           jak1-checked-dgo-test jak1-public-generated-artifacts-test \
           jak1-public-generated-artifacts-exactness-test \
           jak1-extracted-generated-inputs-link-proof -j4
ctest --test-dir /private/tmp/goalpad-jak1-extracted-inputs-host \
  --output-on-failure \
  -R 'jak1-(extracted-generated-inputs|checked-dgo|public-generated-artifacts)'

cmake -S OpenGOAL -B /private/tmp/goalpad-jak1-output-recipe-core-host -G Ninja \
  -DOPENGOAL_BUILD_JAK1_OUTPUT_RECIPE_CORE_ONLY=ON \
  -DBUILD_TESTING=ON -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_C_COMPILER_LAUNCHER=/opt/homebrew/bin/ccache \
  -DCMAKE_CXX_COMPILER_LAUNCHER=/opt/homebrew/bin/ccache
CCACHE_DIR=/private/tmp/goalpad-jak1-extracted-inputs-ccache \
  cmake --build /private/tmp/goalpad-jak1-output-recipe-core-host \
  --target jak1-output-recipe-core-test -j4
ctest --test-dir /private/tmp/goalpad-jak1-output-recipe-core-host \
  --output-on-failure -R 'jak1-output-recipe-core-test'

cmake -S OpenGOAL -B /private/tmp/goalpad-jak1-extracted-inputs-iphoneos \
  -G Ninja -DOPENGOAL_BUILD_JAK1_EXTRACTED_GENERATED_INPUTS_ONLY=ON \
  -DBUILD_TESTING=OFF -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.5.sdk \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER_LAUNCHER=/opt/homebrew/bin/ccache \
  -DCMAKE_CXX_COMPILER_LAUNCHER=/opt/homebrew/bin/ccache
CCACHE_DIR=/private/tmp/goalpad-jak1-extracted-inputs-ccache \
  cmake --build /private/tmp/goalpad-jak1-extracted-inputs-iphoneos \
  --target jak1-extracted-generated-inputs-link-proof -j4
```

The focused adapter/artifact/DGO suite passed 5/5 and the isolated recipe-core
regression passed 1/1. The adapter-only target graph contains no recipe-core
target. The iPhoneOS proof final-linked as a Mach-O arm64 executable. A
temporary read-only probe against the maintainer's already validated local tree
parsed 1,610 tpage entries, 16 game-count entries, and seven text banks; the
probe and its binary were not committed and were removed. No retail bytes were
added to a test fixture or source control.

The first ccache-launched build failed before compilation with
`ccache: error: Operation not permitted` because the sandbox could not write its
default Library cache. The successful build used the explicit temporary cache
shown above. That 12 MiB cache was then moved to the shared, bounded
`/private/tmp/GOALPad-ccache`, and the local ccache configuration now points
there with a 512 MiB maximum.

Renderer and Apple checks:

```sh
cmake --build OpenGOAL/build/Release/bin \
  --target metal-camera-trace-test metal-proof -j4
OpenGOAL/build/Release/bin/game/metal-camera-trace-test
OpenGOAL/build/Release/bin/game/metal-proof

Scripts/run-camera-timing-check.sh
xcrun swiftc -parse GOALPad/ContentView.swift \
  GOALPad/Game/GameSession.swift GOALPad/Data/GameData.swift
plutil -lint GOALPad.xcodeproj/project.pbxproj \
  GOALPad/GOALPad.entitlements GOALPad-Info.plist

xcodebuild -quiet -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug \
  -destination 'id=96C5C21A-B925-4213-82A3-90DCB8518339' \
  -derivedDataPath /private/tmp/GOALPad-sim -jobs 2 \
  CODE_SIGNING_ALLOWED=NO ENABLE_PREVIEWS=NO build
```

All 34 camera-trace assertions passed. The sandboxed Metal proof could not see
a display and failed renderer initialization; the proof passed outside the
sandbox and ended `METAL PROOF PASSED`. Its TIE camera sweep found 108,622
correct magenta pixels for camera A and 41,659 for camera B, with zero blue,
white, or otherwise unexpected colored pixels; the second camera A RGBA frame
was byte-identical to the first. Swift parsing, plist
validation, and camera timing passed. The compile-only approved M5 simulator
destination build passed with existing conversion warnings and did not boot
the simulator. Its app executable is thin ARM64 with SHA-256
`b6f7a9cd5608e03176eae7f1d5111a755f7055034f621b12abe2d0da4601708d`,
display name `Eco Pro`, and bundle identifier `com.zephyrstudiosllc.eco`.

The retained Merc transform test passed all 15 checks, including reversible
uniform-scale and flattened A/B/A sequences. The Swift/C bridge check, changed
Swift parse, shell syntax check, and focused Objective-C++ syntax checks for
`GOALPadRenderSurface.mm` and `GOALPadMetalHost.mm` also passed. No full
compiler, Metal, AOT, or Xcode matrix was repeated for this diagnostic-only
patch.

Build-cache discipline is now recorded in `AGENTS.md` and `docs/BUILDING.md`.
OpenGOAL has an opt-in `Release-macos-arm64-clang-ccache` preset while the normal
preset remains dependency-free. The existing canonical build was not
reconfigured, avoiding a duplicate rebuild. After preserving recorded results,
12 obsolete Xcode DerivedData directories, 16 clean OpenGOAL worktrees whose
commits are ancestors of canonical, and obsolete proof caches were removed.
Their Git commits remain recoverable; dirty/divergent worktrees and the recorded
camera DMA captures were preserved. Available disk space rose from under 1 GiB
to approximately 10 GiB.

No physical device was accessed. Camera quality, Merc deformation, world-depth
fighting, metallic flicker, real raw-ISO app import, custom outputs, and ZIP
handling remain unvalidated. The separately isolated Jak II 840-object AOT
final-link proof remains green but is not app-wired and does not displace Jak 1
as the active scope.

# Checkpoint 48: base-retail importer profile, existing-pack verification, and serial activation

The parent implementation commit is `a8f3d040d5ffa5aae0b5824ec5e20b9fd5538394`
(`feat(import): stage and atomically activate game data`). It adds the serial
staging/activation worker but does not make raw ISO files selectable. The final
Checkpoint 48 nested OpenGOAL gitlink is
`25ae476171340f349cc06a9fb581f316e924092d`. The reviewed child work includes
`fd20ddfcb` (`jak1-base-retail`), `211cbc4dd` (verification of an existing
public source-object pack), and `25ae47617` (the ARM64-only current-process
guard boundary).

## Current importer boundary

`jak1-base-retail` is implemented and tested in the isolated C++ pipeline. It
preserves the user's seven retail COMMON text banks, excludes `TSZ.DGO` and its
generated test-zone/custom-actor outputs, and writes seven structurally valid
zero-scene subtitle banks. The graph, recipe, and materializer checks passed.
The existing-source-pack verifier also passed against a 518-object pack with
aggregate identity `e3ed59b376d6a079` and `10,729,469` object bytes; an override
with the wrong expected identity failed as required.

Raw ISO selection remains deliberately disabled. It may be enabled only after
the C++ graph/builder/materializer composition, the Objective-C++ producer
bridge, and an end-to-end approved-simulator proof all pass. The prepared-folder
flow remains the supported app path throughout that work. The serial worker is
not evidence that the native producer exists or that an ISO can reach an active
install.

## Validation recorded for this checkpoint

- Host compiler pass, Metal target pass, all 34 camera assertions, and the
  Metal proof outside the sandbox passed.
- The Jak 1 AOT preflight passed with 518 objects, 10,596 emitted functions,
  and 7 native functions.
- The approved M5 simulator compile-only build, generic iPhoneOS build, and
  generic visionOS build passed. These are not physical-device evidence.
- The focused importer suite passed all named cases. The base-retail
  graph/recipe/materializer tests passed, as did the existing-pack identity
  verifier and its wrong-override rejection.
- The first generic macOS command requested both ARM64 and the intentionally
  unsupported x86-64 slice. It first exposed the older unguarded
  `ScopedCurrentProcess` use and, after that four-line guard was integrated,
  reached the next removed x86-64 API. The project-scoped ARM64 command passed:

  ```sh
  xcodebuild -quiet -project GOALPad.xcodeproj -scheme GOALPad \
    -configuration Debug -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath /private/tmp/GOALPad-sim -jobs 2 \
    CODE_SIGNING_ALLOWED=NO ENABLE_PREVIEWS=NO \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
  ```

No physical device was accessed for this checkpoint. Do not turn the successful
simulator or generic-platform builds into a physical-iPad claim.

## Checkpoint execution discipline

Use one Sol `xhigh` integration lane; up to two Sol `xhigh` implementation
lanes for importer architecture, renderer bugs, ABI/AOT, and unsafe file
handling; and one Terra `medium` or `high` mechanical lane for CMake,
documentation, fixtures, build-log triage, formatting, and API plumbing.
Workers run focused checks only. Run medium checks after integrating a subsystem,
then run the expensive compiler, Metal, AOT, and Xcode matrix once per
checkpoint.

Keep one canonical OpenGOAL build, `/private/tmp/GOALPad-sim` DerivedData, and
the bounded `/private/tmp/GOALPad-ccache`; never run heavy builds in parallel.
Generate the 518-object source pack once, then verify its recorded identity
unless the writer or embedded graph changes. Delete only obsolete disposable
build directories after recording their results. Pause visual work at a physical
A/B gate unless a deterministic hypothesis and test can still distinguish the
next change.

## Next executable work

1. Compose the checked C++ base-retail graph, builder, and materializer behind
   one bounded producer contract; retain failure, cancellation, and staging
   ownership semantics.
2. Add the narrow Objective-C++ producer bridge to the serial worker and prove
   the raw-ISO path end to end on the approved simulator before changing the
   picker.
3. Preserve the focused and checkpoint validation tiers. Do not use a generic
   universal macOS destination as an x86-64 support claim; this downstream
   runtime and its documented macOS baseline are ARM64-only.

# Checkpoint 49: active Jak 1 bones provenance on Z iPhone Air

## Exact Git and generated-artifact state

- Parent `feat/ipados-native-boot` is
  `e9c200b2a54988e71d30bd1d99b9c9e1e6863ffb`, matching
  `origin/feat/ipados-native-boot`.
- Nested OpenGOAL `goalpad/ipad-demo-pacing` is
  `39f0afaa4bd2d10c5c96d33dc04a447bdbf84593`, matching
  `origin/goalpad/ipad-demo-pacing`.
- The regenerated Jak 1 public source-object pack contains 518 objects with
  aggregate XXH64 `f1770cae6287a359` and 10,729,681 object bytes. The signed
  build used `/private/tmp/GOALPad-jak1-source-pack-generated-g` as its explicit
  source-pack root.
- The nested checkout is clean. The canonical parent retains only the existing
  user-owned `GOALPad.xcodeproj/project.pbxproj` normalization. It was not
  staged, committed, reset, or otherwise modified by this checkpoint.

The integrated diagnostic records the active Jak 1 bone calculation before
the new-bones/legacy selection, so the default `*use-new-bones* #t` path now
feeds the same fixed producer registry as the legacy path. The retained Merc
event can distinguish input-root A/B/A (`0x04`), output-only A/B/A (`0x08`),
camera-driven A/B/A (`0x10`), changed-input/frozen-output (`0x20`), and source-
mapping mismatch (`0x40`) in addition to the existing scale and aspect flags.
This is diagnostic-only; it does not change pose generation, camera behavior,
rendering, or timing.

## Signed iPhone Air build, install, and launch

Z iPhone Air was connected as:

```text
CoreDevice ID: C0CAC382-DF64-5728-998E-A51F86A94E61
Xcode destination: 00008150-0019189626FB801C
Model: iPhone Air (iPhone18,4)
```

The exact signed Release build command was:

```sh
xcodebuild -quiet -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Release \
  -destination id=00008150-0019189626FB801C \
  -derivedDataPath /private/tmp/GOALPad-sim -jobs 2 \
  ENABLE_PREVIEWS=NO \
  GOALPAD_JAK1_SOURCE_OBJECT_PACK_ROOT=/private/tmp/GOALPad-jak1-source-pack-generated-g \
  GOALPAD_CCACHE_DIR=/private/tmp/GOALPad-ccache \
  GOALPAD_BUILD_JOBS=2 build
```

Result: exit `0`, with the existing generated-code warning volume. Release
verification accepted all 518 objects and aggregate `f1770cae6287a359`. The
product is:

```text
/private/tmp/GOALPad-sim/Build/Products/Release-iphoneos/GOALPad.app
Bundle identifier: com.zephyrstudiosllc.eco
Team identifier: V729QMY3V6
Executable SHA-256: 5cf28b7b7e09972c1a754358b06845baa94425b10760f0e3bfe9142d0a5f2ec9
```

The executable contains `jak1-bones-provenance-observe` and
`goalpad_camera_provenance`. It was update-installed and launched with:

```sh
xcrun devicectl device install app \
  --device C0CAC382-DF64-5728-998E-A51F86A94E61 \
  /private/tmp/GOALPad-sim/Build/Products/Release-iphoneos/GOALPad.app

xcrun devicectl device process launch \
  --device C0CAC382-DF64-5728-998E-A51F86A94E61 \
  com.zephyrstudiosllc.eco
```

Both commands passed. This was an update install, not an uninstall, so the
existing app data container was preserved. It proves signed physical
installation and process launch on Z iPhone Air. It does not prove gameplay,
Metal correctness, camera quality, or Merc correctness. No retail game data is
bundled; the phone still needs its own user-imported compatible data if its
container does not already have a prepared game.

## Latest physical symptoms and next evidence gate

The latest gameplay feedback still comes from the pre-observer iPad build:

- Kick/spin whole-body enlargement appears mostly fixed.
- Jak still shakes and alternates between flat and volumetric forms while
  spinning. He can enlarge and turn toward the camera as the state changes.
- Visible facing can diverge from locomotion: Jak can move right while facing
  or running left, curve toward the intended direction, and then dash off-axis
  if Square is pressed while he is visibly misoriented.
- The camera is comparatively stable when Jak is centered with open space. It
  shakes most around the Geyser Rock portal exit, combat, edge-of-frame, and
  out-of-frame recovery; the character shake is present more broadly.

The new observer build has not yet received a physical gameplay pass. The next
gate is to reproduce the spin/facing symptom on Z iPhone Air, background the
app to force the atomic lifecycle snapshot, and copy the cache before another
launch replaces its random run ID. Use exactly:

```sh
xcrun devicectl device copy from \
  --device C0CAC382-DF64-5728-998E-A51F86A94E61 \
  --domain-type appDataContainer \
  --domain-identifier com.zephyrstudiosllc.eco \
  --source Library/Caches/GOALPadDiagnostics/camera-provenance-v1.log \
  --destination /private/tmp/camera-provenance-iphone-air-e9c200b2.log \
  --timeout 30
```

This reads one numeric-only cache file through the app-data-container domain;
it does not uninstall the app or erase its data and may copy a live atomic
snapshot. Prefer backgrounding first so the lifecycle write is current. Do not
relaunch before copying. The file exists only after a successful game boot has
started the diagnostics session.

## visionOS logger status

Parent `e9c200b2` widens only the camera/Merc diagnostics compilation gates
from iOS to iOS-or-visionOS. The existing cache path and payload are unchanged:

```text
Library/Caches/GOALPadDiagnostics/camera-provenance-v1.log
```

Focused iPhoneOS 26.5 and xros 26.5 Swift parses passed. No post-gate visionOS
Xcode build, installation, launch, game boot, or file copy has been performed.
The previously installed Vision Pro build predates this gate and should not be
expected to contain the logger. Once an `e9c200b2`-or-later xros build is
installed and successfully boots the game, use the same `appDataContainer`
domain syntax with Vision Pro CoreDevice ID
`7C8DED98-3B86-55CE-B49D-C514E47F745A`; that post-gate physical file copy is
still unvalidated.

## Next executable task

1. Have the maintainer reproduce the spin/flat/facing symptom on Z iPhone Air
   and background the app without relaunching it.
2. Run the exact one-file copy command above and preserve its SHA-256 before
   any new install or launch.
3. Classify the retained issue mask and the input/output/camera distances. Make
   one behavior change only after the trace identifies the active seam.
4. Rebuild and physically validate Jak 1 before beginning new Jak II-specific
   implementation.

# Checkpoint 50: Jak composition evidence and local ZIP-to-ISO preparation

## Exact Git and artifact state

- Parent `feat/ipados-native-boot` is `0cd1247c` before this checkpoint note.
- Nested OpenGOAL `goalpad/ipad-demo-pacing` is
  `47f768ed0ec1f2cbcc2014c85b38ab1b535566f2`, matching its pushed remote.
- The existing external Jak 1 source-object pack still verifies as 518 objects,
  aggregate `f1770cae6287a359`, and 10,729,681 bytes. The current generated AOT
  corpus still passes preflight with 518 objects, 10,596 emitted functions, and
  7 native functions. Neither artifact needed regeneration because this
  checkpoint changed native diagnostics and tests, not the GOAL source graph.
- The canonical parent still has only the maintainer-owned
  `GOALPad.xcodeproj/project.pbxproj` normalization outside committed work. It
  was not staged, reset, or modified by this checkpoint.

The nested diagnostic now snapshots the matching bind pose for Jak root slots
1 through 3 and compares the consumed Merc `t-mtx` against the producer's exact
`camera * bone * bind` composition. `0x80` identifies a composition mismatch.
Generic first/last provenance events retain any `0x04...0x80` issue, while
dedicated first/last composition and Jak-only palette-health events prevent an
intermittent Jak failure from being hidden by unrelated models or later event
classes. A read-only source audit confirmed the matrix order, basic-object
pointer bias, joint/bone/output strides, root-to-bind mapping, direct Merc
packet copy, and shader consumption. The non-commuting X/Y/Z regression covers
all three root mappings and rejects reversed order or crossed bind poses. The
focused Merc trace executable passes all 40 checks.

The parent v3 cache bridge exposes the new counts, bind hashes, previous/current
expected-output distances, non-finite lane masks, and dedicated first/last
events. This remains diagnostic-only: it does not change camera behavior, pose
generation, Merc rendering, or frame pacing.

## Local ZIP import

Eco Pro now accepts a user-selected standard ZIP32 archive containing exactly
one `.iso`, streams that member into private Application Support staging, checks
its declared size and CRC-32, then reuses the existing raw-ISO producer. Stored
and raw-DEFLATE members are supported, including data descriptors. The app
rejects ZIP64, encryption, multidisk archives, unsafe or ambiguous paths,
multiple ISO members, unsupported compression/options, unreasonable expansion,
local/central header disagreement, corruption, and insufficient storage.

The temporary ISO is a UUID-named sibling of the candidate, never candidate
content and never an active gameplay source. Success, failure, and cancellation
remove it. Before a later ZIP attempt, bounded cleanup removes at most four
exact app-owned uppercase UUID `.extracted.iso` regular-file siblings left by
an abnormal termination; candidates, directories, symlinks, lowercase names,
and ambiguous files are preserved. DEFLATE checks cancellation for every
produced output chunk and again before the potentially expensive final disk
flush. Member names must be ASCII or explicitly UTF-8; CP437 and ZIP64 are
deliberately unsupported.

An independent security review initially rejected the patch for abnormal-
termination orphaning and delayed DEFLATE cancellation. Both were fixed and
the final re-review returned GO. The parser is isolated in
`GOALPad/Data/ZIPISOCandidateProducer.swift`; the synchronized Xcode source
group includes it without a project-file edit, and the Apple SDK `zlib` module
auto-links `libz`.

Focused validation passed:

```sh
./Scripts/run-zip-iso-import-check.sh
./Scripts/run-game-data-import-source-check.sh
./Scripts/run-game-data-install-check.sh
./Scripts/run-merc-transform-diagnostics-check.sh
Scripts/verify-generated-aot.sh Generated/jak1-aot 518
OpenGOAL/build/Release/bin/goalc/jak1-source-object-pack-verify \
  /private/tmp/GOALPad-jak1-source-pack-generated-g \
  --expected-aggregate f1770cae6287a359
```

The ZIP suite covers stored, DEFLATE, data-descriptor, exact-output-buffer,
CRC/size, local/central disagreement, ambiguity, traversal, encryption,
unsupported method/options, ZIP64, multidisk, expansion/storage, downstream
reuse, success/failure cleanup, bounded stale cleanup, and stored/final-DEFLATE
cancellation cases. Strict iPhoneOS and visionOS Swift typechecks also passed in
the isolated implementation lane.

The combined parent/nested state passed one generic signed Release iPhoneOS
build using the canonical DerivedData and existing verified source pack:

```sh
xcodebuild -quiet -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-sim -jobs 2 \
  ENABLE_PREVIEWS=NO \
  GOALPAD_JAK1_SOURCE_OBJECT_PACK_ROOT=/private/tmp/GOALPad-jak1-source-pack-generated-g \
  GOALPAD_CCACHE_DIR=/private/tmp/GOALPad-ccache \
  GOALPAD_BUILD_JOBS=2 build
```

Result: exit `0`. The product is
`/private/tmp/GOALPad-sim/Build/Products/Release-iphoneos/GOALPad.app`, bundle
identifier `com.zephyrstudiosllc.eco`, display name `Eco Pro`, team
`V729QMY3V6`, and executable SHA-256
`35f4484dda2ac63a3c8448fbfb24c4afb3fd9df815ac2f5fdb47c273c1cf5e98`.
The executable contains both the ZIP64 rejection path and the new Merc
composition fields. This is build/signing evidence, not a physical gameplay or
real-archive import result.

## Preserved physical evidence and next gate

The latest iPhone feedback from the previous installed build reported the most
stable Geyser Rock teleporter exit yet, with the earlier roughly 45-degree
camera failure reduced to about 10 degrees. Camera stability remained good
while Jak was centered and still, but edge-of-frame, out-of-frame, and nearby
occluder cases could still return to roughly 45-degree yaw plus 10-degree roll
jitter. Jak still showed opposite-facing enlargement/Z fighting, incorrect
facing versus stick direction, curved steering, and off-axis Square attacks;
Flat Stanley deformation was improved but not eliminated.

The preserved live cache is:

```text
/private/tmp/camera-provenance-iphone-air-e9c200b2-live-20260802.log
SHA-256: 4936459ec1e4ec79322e87038702d6bec3c60203f9188a841fe4c5811505f09f
Size: 20,512 bytes
```

It recorded 35,295 sent/rendered chains with zero chain drops or drawable
misses, 12 presentation drops, 2,769 camera producer alternations/correction
events, zero live/packet camera mismatches, 7,247 global non-finite matrices,
and 21,158 global Merc transform discontinuities. The last global non-finite
event mapped to `speaker-lod0`, so it must not be used as Jak attribution.

The iPhone disconnected before a later read-only final copy could run. No new
app was installed or launched, so the previous app/container and its cache were
not replaced. When the phone is available again:

1. Copy `Library/Caches/GOALPadDiagnostics/camera-provenance-v1.log` from the
   existing app container before any install or launch, if the old cache is
   still present.
2. Update-install the combined signed Release app without uninstalling or
   erasing the container, then launch it.
3. Reproduce the spin/wrong-facing/edge-of-frame case and background the app.
4. Copy and classify the v3 cache. A nonzero dedicated `0x80` count identifies
   producer-to-Merc composition failure; a clean composition result moves the
   next bounded diagnostic to target-control/facing state rather than another
   speculative renderer change.
5. Separately run one user-selected real ZIP32 ISO import to validate Files
   provider materialization, available-space reporting, throughput, and the
   full native preparation pipeline. ZIP physical validation must not be
   conflated with gameplay validation.

Do not begin new Jak II-specific implementation until this Jak 1 physical gate
is resolved.
