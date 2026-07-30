# GOALPad iPadOS Port Handoff

Date: 2026-07-30

Branch: `feat/ipados-native-boot`

Status: Partially complete. The repository now has a reproducible, pinned
OpenGOAL ARM64 host baseline and a buildable Apple platform probe. Actual GOAL
source does not yet compile to signed ARM64 code, and no physical-device
install or launch has succeeded.

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
- Simulator and generic-device builds are compilation evidence only. Physical
  build, install, launch, and execution must be recorded separately.

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

`gh auth status` reported a valid active `zephyrstudiosllc` credential with
`repo` scope. It did not report an authenticated `zschwendi` account. No push,
fork creation, or pull request was attempted because choosing
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

## Verified OpenGOAL baseline

From the nested Git checkout:

```sh
cmake -S OpenGOAL -B /private/tmp/GOALPad-pinned-opengoal-build \
  --preset=Release-macos-arm64-clang \
  -DOPENSSL_ROOT_DIR=/opt/homebrew/opt/openssl@3

cmake --build /private/tmp/GOALPad-pinned-opengoal-build \
  --target gk goalc-test -j 12

ln -s "$PWD/OpenGOAL" /private/tmp/GOALPad-pinned-opengoal-build/data

/private/tmp/GOALPad-pinned-opengoal-build/goalc-test \
  --gtest_filter='ARM64EmitterIntegerMath.*:CodeTester.*arm64'

file /private/tmp/GOALPad-pinned-opengoal-build/game/gk \
  /private/tmp/GOALPad-pinned-opengoal-build/goalc-test
```

Results:

- CMake configure exited `0`.
- The 1,294-step `gk` and `goalc-test` build exited `0`; upstream and
  third-party warnings remain.
- 11 selected ARM64 tests from 2 suites passed.
- `game/gk` and `goalc-test` are both Mach-O 64-bit ARM64 executables.

The `data` symlink is local build state. OpenGOAL's test bootstrap looks for a
sibling source/data path when the test executable is outside a directory named
`jak-project`.

An initial configure using `/private/tmp/GOALPad-opengoal-build` failed because
that directory already contained a CMake cache for the earlier temporary
clone. `docs/BUILDING.md` now uses the distinct
`/private/tmp/GOALPad-pinned-opengoal-build` path shown above. The clean
configure and build at that documented path passed.

One earlier direct test run without that symlink exited `134` because the
source root could not be discovered. The documented symlink fixed the
invocation; no source change was needed.

## Verified GOALPad targets

These exact commands exited `0` after both checkpoints:

```sh
xcodebuild -quiet -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/GOALPad-mac \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -quiet -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/GOALPad-sim \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -quiet -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-device \
  CODE_SIGNING_ALLOWED=NO build
```

Xcode 26.6 emitted:

```text
IDERunDestination: Supported platforms for the buildables in the current
scheme is empty.
```

The message did not fail these three builds, but the scheme/platform
configuration should be narrowed to iPadOS when doing so does not disrupt the
macOS ARM64 development baseline.

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

Detailed inspection reported:

```text
ddiServicesAvailable: false
tunnelState: disconnected
Error: The tunnel was interrupted while establishing connectivity
```

The signed build attempt was:

```sh
xcodebuild -quiet -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug \
  -destination 'platform=iOS,id=00008142-000A504C3CC2401C' \
  -destination-timeout 15 \
  -derivedDataPath /private/tmp/GOALPad-physical build
```

It exited `70` before compilation/signing completed:

```text
xcodebuild: error: Timed out waiting for all destinations matching the
provided destination specifier to become available

Z iPad Pro may need to be unlocked to recover from previously reported
preparation errors
```

No app was installed or launched. No physical Metal or ARM64 workload result
has been validated. Unlock/connect the iPad, wait for developer services to
become available, then rerun build, install, launch, and log capture.

## Confirmed compiler and runtime blockers

At the pinned OpenGOAL commit:

- Both ARM64 function paths in `goalc/compiler/CodeGenerator.cpp` throw `NYI`.
- The ARM64 implementations for all current compiler IR operations in
  `goalc/compiler/IR.cpp` throw `NYI`.
- Compiler register allocation still relies on x86-oriented global register
  metadata. ARM64 code generation must not merely reinterpret those values.
- Compiler entry points still select x86 in normal host flows.
- `game/runtime.cpp` allocates the desktop EE region with read, write, and
  execute permissions.
- OpenGOAL v3 objects contain executable payloads that the desktop linker
  copies and patches at runtime; they are not normally signed Mach-O code.
- `_call_goal_asm_arm64` exists and uses X0-X7 arguments, X0 return, and
  X20/X21/X22 for OpenGOAL's process/st/offset-base state, but C++ runtime
  dispatch and Jak 1 trampolines are not a complete ARM64 path.
- The host runtime target is monolithic and carries desktop renderer, window,
  input, audio, listener, and debugging assumptions.

The lower-level ARM64 emitter is real and tested. The missing layer is
architecture-correct compiler/register behavior plus a static artifact path
that Apple can sign.

## Highest-value next checkpoint

First choose the durable GitHub owner for a public/open-source-compatible
OpenGOAL fork. Then:

1. Fork `open-goal/jak-project`, retain an `upstream` remote, and change the
   submodule URL to that fork while keeping the current commit pinned.
2. Add architecture-selected register/calling-convention metadata for ARM64.
   Test X0-X7 arguments, X0 return, and X20/X21/X22 special registers before
   relying on allocator output.
3. Implement only the compiler operations needed for a source-backed constant
   function: ARM64 function emission, `IR_LoadConstant64`, `IR_Return`, and
   `IR_Null`.
4. Add a deterministic compiler test that compiles an actual GOAL expression,
   such as `42`, and inspects the generated ARM64 instructions. Reject spills,
   saved-register handling, SIMD, or other unsupported paths explicitly rather
   than silently emitting questionable code.
5. Export that generated function as a build-time object or assembly artifact
   and link it into GOALPad before code signing.
6. Call it through the real OpenGOAL ARM64 convention and bridge, first on
   ARM64 macOS and then in a signed physical iPad build.

This checkpoint must not use `MAP_JIT` or copy code into writable executable
memory. Passing a macOS compiler test proves code generation only; the
physical signed run is the milestone.

## Next-session commands

```sh
cd /Users/zach/Developer/OS_Projects/GOALPad/GOALPad

git status --short
git log --oneline --decorate -5
git submodule status
git -C OpenGOAL status --short

git submodule update --init --recursive

xcrun devicectl device info details \
  --device 6A4111AB-1663-508A-98D9-F0C1A9EA7863
```

Before making upstream changes, confirm:

- Which GitHub account or organization owns the dedicated OpenGOAL fork.
- That the fork is accessible over the submodule's chosen HTTPS/SSH path.
- That the parent `zschwendi/GOALPad` remote is accessible for checkpoint
  publication.

Do not use proprietary inputs until the signed compiler-generated proof is
working. The next milestone needs only source and synthetic constants.
