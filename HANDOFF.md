# GOALPad iPadOS Port Handoff

Date: 2026-07-30

Branch: `feat/ipados-native-boot`

Status: Partially complete. Stage 2 now compiles the real top-level GOAL
expression `42` to an ahead-of-time ARM64 assembly artifact, links that
artifact into GOALPad before code signing, and executes it on ARM64 macOS and
the iPad Pro M5 simulator. A normally signed physical-device build completed
and installed on the paired iPad Pro M5; the automated launch is pending only
because the device was locked. This proof is intentionally narrow and does
not yet initialize general OpenGOAL runtime state or load Jak 1 data.

## Active roadmap and delegated audit

`ROADMAP.md` is the active ten-stage path from the current probe through a
completable Jak 1 physical-iPad result. The implementation goal remains open
until all ten stage exit gates are satisfied.

The roadmap and Stage 2 checkpoints used parallel subagents. All used the
maintainer-requested fast `gpt-5.6-terra` model with `xhigh` reasoning:

| Delegation | Scope | Result |
| --- | --- | --- |
| Documentation and milestone audit | Project overview, handoff, build docs, and roadmap structure | Confirmed no prior roadmap; corrected evidence labels, stage ordering, and milestone mapping |
| OpenGOAL compiler audit | ARM64 registers, allocators, IR, CodeGenerator, AOT artifact, and tests | Defined the top-level GOAL literal `42` slice and recommended generated Apple assembly |
| Xcode and validation audit | Target configuration, simulator/device evidence, test surface, and memory-conscious validation | Confirmed simulator gates, physical authority boundaries, and a future need to narrow broad platform declarations |
| ARM64 register implementation | Register identity, calling convention, compiler target plumbing, and both allocators | Implemented target-aware X0-X7 arguments, X0 return, X20/X21/X22 special registers, distinct GPR/SIMD identities, and preserved x86 allocation order |
| ARM64 code-generation implementation | Minimal IR lowering, function emission, and raw non-V3 materialization | Implemented the exact literal-`42` slice without using the desktop runtime-linker object path |
| AOT artifact and test implementation | Writer, CLI, fixture, CMake wiring, and deterministic tests | Added `goalc-aot`, exact instruction tests, unsupported-source rejection, and Apple assembly output |
| Independent Stage 2 review | Cross-target register semantics, allocator regression risk, and next-boundary review | Found and prompted the x86 `hw_id` correction; identified call-clobber handling as the next compiler boundary |

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

## Repository state

The outer workspace is not a Git repository. The checkout is nested:

```text
/Users/zach/Developer/OS_Projects/GOALPad
└── GOALPad/                         # Git checkout
```

The outer workspace contains local proprietary inputs. None were read into,
copied into, or generated inside the Git checkout.

Current history:

```text
e77a402 Link compiler-generated ARM64 GOAL proof (AI-assisted)
bc82c3e Add ten-stage GOALPad implementation roadmap (AI-assisted)
7789350 Record iPad Pro M5 simulator validation (AI-assisted)
bddb6ad Document OpenGOAL baseline and next ARM64 checkpoint (AI-assisted)
89e4630 Pin OpenGOAL ARM64 baseline and project policy (AI-assisted)
350867b Checkpoint signed ARM64 platform probe (AI-assisted)
959cab6 Initial Commit
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
`zschwendi` account. No push, fork creation, or pull request was attempted
because choosing
`zephyrstudiosllc` versus `zschwendi` as the durable owner would change project
ownership and branding direction.

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
Worktree: /private/tmp/GOALPadOpenGOAL-stage2
Branch: goalpad/arm64-aot-proof
Commit: 79f22008c3119bf79297f41d586ab4f75725a36e
Patch: patches/OpenGOAL/0001-Add-minimal-ARM64-GOAL-AOT-proof-AI-assisted.patch
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
```

`GOALPadRuntimeCore.cpp` calls this compiler-generated function through the
ordinary static ARM64 ABI and verifies both the expected instruction bytes and
the returned value. The older handwritten probe remains preserved, but it no
longer supplies the displayed result.

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

## Verified GOALPad targets

Before Stage 2, the unsigned ARM64 macOS, generic iOS Simulator, and generic
iOS target builds all exited `0`. The compiler-generated Stage 2 artifact was
then verified through the exact simulator and signed-device builds below.

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug \
  -destination 'id=96C5C21A-B925-4213-82A3-90DCB8518339' \
  -derivedDataPath /private/tmp/GOALPad-sim -jobs 4 build

xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-device -jobs 4 build
```

Both commands exited `0`. Xcode compiled
`GOALPad/Native/Generated/OpenGOALConstant42.s` into the app. The generic iOS
build used the existing Apple Development identity and provisioning profile
and completed normal code signing.

The signed device app's `GOALPad.debug.dylib` contains
`_goalpad_aot_constant_42` at `0x4000`. `llvm-objdump` confirms:

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

The app installed and launched as `com.zephyrstudiosllc.GOALPad`, producing
PID `90815`. A settled screenshot showed:

```text
Signed ARM64 OpenGOAL AOT workload verified
architecture=arm64
result=42
```

Simulator logs independently recorded:

```text
GOALPad runtime probe: Signed ARM64 OpenGOAL AOT workload verified;
architecture=arm64; result=42
```

The screenshot is preserved locally as
`/private/tmp/GOALPad-open-goal-aot.png`. Builds used `-jobs 4`, no new
DerivedData tree was created, and the simulator was shut down immediately
after validation. The last resource check showed 12 GB free disk and 41% free
system memory.

This is real GOAL compiler/output evidence on the named simulator, but it does
not convert simulator evidence into physical-device execution evidence.

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

The launch was attempted three times. A console-attached attempt timed out
without application output. Two normal launch attempts, including the final
18:52 retry, returned the same actionable blocker:

```text
RequestDenied
Unable to launch com.zephyrstudiosllc.GOALPad because the device was not, or
could not be, unlocked.
```

Therefore the current independently captured evidence is: build passed, sign
passed, and install passed. Physical launch and the `42` runtime result remain
unvalidated until the iPad is unlocked and the launch is retried. An older
maintainer report says the prior handwritten platform probe worked on this
iPad; that does not substitute for executing the new compiler-generated
artifact.

## Confirmed compiler and runtime blockers

At Stage 2:

- The exact top-level literal `42` has a target-aware ARM64 compiler path.
  General functions and almost all other ARM64 IR operations remain
  unsupported and reject explicitly.
- `IR_FunctionCall::to_rai` still enumerates x86 call clobbers. Calls are
  rejected by the Stage 2 path, so this is safe for the current proof but must
  be fixed before enabling any call-bearing workload.
- The static entry currently uses the ordinary ARM64 ABI. It does not yet
  initialize OpenGOAL's X20/X21/X22 process, `st`, and offset-base state.
- `game/runtime.cpp` allocates the desktop EE region with read, write, and
  execute permissions.
- OpenGOAL v3 objects contain executable payloads that the desktop linker
  copies and patches at runtime; they are not normally signed Mach-O code.
- `_call_goal_asm_arm64` exists and uses X0-X7 arguments, X0 return, and
  X20/X21/X22 for OpenGOAL's process/st/offset-base state, but C++ runtime
  dispatch and Jak 1 trampolines are not a complete ARM64 path.
- The host runtime target is monolithic and carries desktop renderer, window,
  input, audio, listener, and debugging assumptions.

The lower-level ARM64 emitter, target-aware compiler slice, and static signed
artifact path are now real and tested. The next missing layer is a defined
static OpenGOAL call boundary and the next source-driven compiler subset.

## Highest-value next checkpoint

1. Unlock the paired iPad and retry the already installed Stage 2 app. Capture
   launch success and the displayed/logged compiler-generated result
   separately.
2. Choose the durable fork owner and authenticate that GitHub account. Publish
   child commit `79f22008`, preserve the official `upstream` remote, and only
   then update the parent submodule URL/gitlink to the fetchable fork commit.
3. Add a small static ARM64 wrapper that deliberately initializes and
   preserves OpenGOAL's X20/X21/X22 runtime-state contract before calling a
   compiler-generated entry. Validate it on ARM64 macOS, then the simulator,
   then the signed physical iPad.
4. Make `IR_FunctionCall::to_rai` target-aware before enabling calls. Continue
   Stage 3 from the next representative Jak 1 initialization-source failure,
   adding one compiler/IR boundary at a time.

Do not introduce `MAP_JIT`, writable executable memory, or the desktop V3
runtime-linker path. Stage 2 is not complete until the physical iPad executes
the generated workload through the defined OpenGOAL state convention.

## Next-session commands

```sh
cd /Users/zach/Developer/OS_Projects/GOALPad/GOALPad

git status --short
git log --oneline --decorate -5
git submodule status
git -C OpenGOAL status --short

git submodule update --init --recursive

xcrun devicectl device process launch \
  --device 6A4111AB-1663-508A-98D9-F0C1A9EA7863 \
  --terminate-existing com.zephyrstudiosllc.GOALPad
```

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
```

`git am` reconstructs a patch-equivalent commit but normally produces a
different SHA because committer metadata changes. `79f22008` is the exact
original child commit in the current isolated worktree; compare content and
patch identity when reconstructing it elsewhere.

Do not use proprietary inputs yet. The next static-wrapper/compiler checkpoint
still needs only source and synthetic constants.
