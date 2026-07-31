# Building GOALPad

## Requirements

- Apple silicon Mac
- Xcode 26.6 or a compatible toolchain with the iOS 26.5 SDK
- CMake, Ninja, and OpenSSL 3 for the OpenGOAL host baseline

```sh
brew install cmake ninja go-task openssl@3
```

## Initialize OpenGOAL

```sh
git submodule update --init --recursive
```

The submodule commit is the authoritative upstream version. Do not substitute a
different OpenGOAL checkout when recording validation results.

## Build the application

From the repository root:

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

The macOS and generic iOS commands validate compilation and linking only. The
generic iOS build is not physical-device validation. The generic simulator
invocation is documented below as an expected architecture mismatch, not a
required passing build.

For ARM64 runtime validation, do not substitute the generic simulator
destination for the named M5 simulator. The generic simulator build selected
x86_64 in the verified true-function checkpoint and failed during assembly of
the existing ARM64-only `GOALPadGoalStateWrapper.s`; no app launched and no
runtime probe ran. That expected architecture mismatch is not ARM64 simulator
evidence. Use the maintainer-created simulator instead:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug \
  -destination 'id=96C5C21A-B925-4213-82A3-90DCB8518339' \
  -derivedDataPath /private/tmp/GOALPad-sim -jobs 4 build
```

This command targets **iPad Pro 11-inch (M5)** and is the routine ARM64
simulator build path. Shut it down after a validation pass when it was not
already running.

The current Debug generic iOS build is limited signing/code-layout evidence.
Its Preview split bundle places the AOT code in signed `GOALPad.debug.dylib`:
`false-func` is at `0x4010`, `identity` at `0x4018`, `lognot` at `0x401c`, and
`true-func` at `0x4024`; its state-wrapper entries are at `0x44a0`, `0x44f4`,
`0x4540`, and `0x459c`. The dylib SHA-256 is
`38e41c1104a59257f29396b4603637f5a9d9f2709bcc473b0511bf466e9d79e6`.
It has RX `__TEXT` and no `mmap`, `mprotect`, or JIT-protect imports, but the
main Debug stub imports `dlopen`/`dlsym` and contains Preview JIT strings. Do
not treat this Debug output as release-like no-JIT evidence.

The verified Release generic iOS build uses the same existing device derived
data path while explicitly disabling both Preview and debug-dylib layout:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-device -jobs 4 \
  ENABLE_PREVIEWS=NO ENABLE_DEBUG_DYLIB=NO build
```

It produced a 216K monolithic app bundle with one 188,624-byte ARM64 main
executable and no `GOALPad.debug.dylib` or `__preview.dylib`. The main contains
false, identity, lognot, and true entries at `0x100004000`, `0x100004008`,
`0x10000400c`, and `0x100004014`, with state-wrapper entries at `0x1000040f0`,
`0x100004144`, `0x100004190`, and `0x1000041ec`. Its SHA-256 is
`3a5c94892fa8d71e53f38ba2d98d08f85d171d66cbf415f136a717d220f4d794`.
The embedded provisioning profile remains unchanged from the paired Debug
output; its SHA-256 is
`ef4a32f9aef6cca1709423e53e66518204e49a86af4d2752139de63d21244ad1`.
Its `__TEXT` segment is RX; undefined imports contain none of `dlopen`,
`dlsym`, `mmap`, `mprotect`, or `pthread_jit_write_protect_np`; and its strings
contain no Preview/JIT marker.

`codesign -d --entitlements -` reports application identifier, team identifier,
and `get-task-allow` entitlements; there is no JIT entitlement. The
`Authority=(unavailable)` and `Info.plist=not bound` fields appear in both
local Debug and Release display output, so they are display limits rather than
a Release-specific signing failure. No verification, installation, or
physical-device execution was performed; treat this Release output as static
build/signing evidence only.

## Build the pinned OpenGOAL ARM64 host baseline

```sh
cmake -S OpenGOAL -B /private/tmp/GOALPad-pinned-opengoal-build \
  --preset=Release-macos-arm64-clang \
  -DOPENSSL_ROOT_DIR=/opt/homebrew/opt/openssl@3

cmake --build /private/tmp/GOALPad-pinned-opengoal-build \
  --target gk goalc-test -j 4

test -e /private/tmp/GOALPad-pinned-opengoal-build/data || \
  ln -s "$PWD/OpenGOAL" /private/tmp/GOALPad-pinned-opengoal-build/data

/private/tmp/GOALPad-pinned-opengoal-build/goalc-test \
  --gtest_filter='ARM64EmitterIntegerMath.*:CodeTester.*arm64'
```

This is the official pinned ARM64 macOS host baseline. It does not contain the
unpublished GOALPad ARM64 AOT child commit.

The `data` symlink is local build state. It lets OpenGOAL's test executable find
the pinned source tree when the build directory is outside the repository.

## Restore and validate the downstream OpenGOAL AOT work

Until a maintainer chooses and authenticates the durable OpenGOAL fork owner,
the verified downstream child commit is preserved as a patch while the
official submodule remains clean:

```text
Base: a4cb1ac1f0596c8740b1c26accb24a58505cda92
Child: 79f22008c3119bf79297f41d586ab4f75725a36e
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
True compiler child: 35d653f1fadc52e78925e952a507d60dc4c11245
True compiler patch: patches/OpenGOAL/0009-feat-aot-compile-exact-Jak-1-true-function-AI-assist.patch
True export child: f979c82cb6da50b847808ebd23ec10c4fa1c1c9e
True export patch: patches/OpenGOAL/0010-feat-aot-export-exact-Jak-1-true-function-AI-assiste.patch
Lognot compiler child: 2475b3c1f097dedb60e5e78a1fc4d88aab5ab052
Lognot compiler patch: patches/OpenGOAL/0011-feat-aot-compile-exact-Jak-1-lognot-function-AI-assi.patch
Lognot export child: 9acf4e79751d83626915f03aebcfc738e4d0c242
Lognot export patch: patches/OpenGOAL/0012-feat-aot-export-exact-Jak-1-lognot-function-AI-assis.patch
Data-arena header child: 5c5368598bf808e5e8a8494679360601d42c02b4
Data-arena header patch: patches/OpenGOAL/0013-feat-kernel-add-portable-Jak-1-data-arena-header-pro.patch
Apple SDK/test gate child: b094144b27af99abd2e3b6809e8f58f93d0fb15a
Apple SDK/test gate patch: patches/OpenGOAL/0014-fix-build-preserve-Apple-SDK-selections-for-host-tes.patch
Canonical data-arena bounds child: 5495181f304bb63b49a82e9067d59fd27a5dd6c8
Canonical data-arena bounds patch: patches/OpenGOAL/0015-fix-kernel-preserve-canonical-Jak-1-data-arena-bound.patch
Minimal iPhoneOS data-arena child: 5ad2efa3dac3febe642370aec39629b17039ead9
Minimal iPhoneOS data-arena patch: patches/OpenGOAL/0016-build-ios-add-portable-Jak-1-data-arena-target-AI-as.patch
Host ARM64 GOAL-call ABI child: 45e1897f7cd560e4951f515e264078a023a2d08c
Host ARM64 GOAL-call ABI patch: patches/OpenGOAL/0017-fix-arm64-verify-GOAL-call-context-ABI-AI-assisted.patch
Generated host AOT-call child: bd3f4752cea18e73fb1e5cbaec3efdd89ec38195
Generated host AOT-call patch: patches/OpenGOAL/0018-test-arm64-execute-generated-Jak-1-AOT-artifacts-AI-.patch
```

Restore it into an isolated worktree:

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

git -C /private/tmp/GOALPadOpenGOAL-stage2 am \
  "$PWD/patches/OpenGOAL/0013-feat-kernel-add-portable-Jak-1-data-arena-header-pro.patch"

git -C /private/tmp/GOALPadOpenGOAL-stage2 am \
  "$PWD/patches/OpenGOAL/0014-fix-build-preserve-Apple-SDK-selections-for-host-tes.patch"

git -C /private/tmp/GOALPadOpenGOAL-stage2 am \
  "$PWD/patches/OpenGOAL/0015-fix-kernel-preserve-canonical-Jak-1-data-arena-bound.patch"

git -C /private/tmp/GOALPadOpenGOAL-stage2 am \
  "$PWD/patches/OpenGOAL/0016-build-ios-add-portable-Jak-1-data-arena-target-AI-as.patch"

git -C /private/tmp/GOALPadOpenGOAL-stage2 am \
  "$PWD/patches/OpenGOAL/0017-fix-arm64-verify-GOAL-call-context-ABI-AI-assisted.patch"

git -C /private/tmp/GOALPadOpenGOAL-stage2 am \
  "$PWD/patches/OpenGOAL/0018-test-arm64-execute-generated-Jak-1-AOT-artifacts-AI-.patch"
```

If that branch or worktree already exists, inspect and reuse it rather than
deleting it. Do not move the parent repository's official submodule gitlink to
the unpublished child commit.

The restored commits are patch-equivalent to `79f22008`, `149840cf`,
`32cf26ae`, `92c8f975`, `b78d7c28`, `1fc20e79`, `25917e27`, `1c80b667`,
`35d653f1`, `f979c82c`, `2475b3c1`, `9acf4e79`, `5c536859`, `b094144b`,
`5495181f`, `5ad2efa3`, `45e1897f`, and `bd3f4752`, but `git am` normally assigns new committer
metadata and therefore different commit SHAs. The exact objects are available
only in a checkout that already contains the original child commits. Compare
the resulting tree or stable patch identities when reconstructing them from the
preserved patches.

Patches 0013 through 0016 are an ordered unit: 0013 creates the data-arena
source, library, and test; 0014 changes that new test's registration; 0015
corrects 0013's arena bounds; and 0016 factors that exact library target into
the minimal mode below. Do not apply or preserve a partial suffix, and do not
reorder the series.

Patch 0017 follows that ordered data-arena unit but is a separate macOS ARM64
dispatcher and static-test checkpoint. It requires 0016 as its parent; it does
not extend the iPhoneOS data-arena build proof or establish an iPad runtime.

Patch 0018 follows 0017 and keeps the same macOS ARM64 host-test gate. It
generates and links static host artifacts; it is not an iPhoneOS target or an
iPad runtime proof.

### Validate the minimal iPhoneOS data-arena static library

Recorded validation used CMake 4.4.1 and builds only the portable
`jak1-data-arena` archive. Source declares CMake 3.10 compatibility, but CMake
3.10 was not executed. This is not an application, signing, simulator, device,
runtime, or GOAL-execution validation.

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
```

Both configurations and target builds exited `0`. The iPhoneOS cache records
the iOS system name, `iphoneos` sysroot, arm64, deployment target 18.0, and
the enabled minimal option. Its compile rule uses `-arch arm64`, the iPhoneOS
26.5 SDK, and `-miphoneos-version-min=18.0`; the archive contains only
`data_arena.cpp.o`. `lipo` reports arm64, the object reports `LC_BUILD_VERSION`
platform iOS/minimum 18.0/SDK 26.5, and `nm -um` reports only system `_bzero`.
The minimal Ninja graph has no curl, OpenSSL, SDL, runtime, goalc, gk, or gtest
target.

The post-0018 iPhoneOS minimal configure and `jak1-data-arena` build also
exited `0`. Its archive is at the build root,
`/private/tmp/GOALPadOpenGOAL-arm64-goal-call-iphoneos-0018-build/libjak1-data-arena.a`;
it remains arm64 with iOS minimum 18.0/SDK 26.5 and only `_bzero` undefined.
The first post-build `lipo` inspection incorrectly used a `game/` archive path
and failed with `No such file`; inspecting the root archive above passed. This
was an environment command-path error, not a source failure. The minimal graph
does not register the host `arm64-goal-call-abi-test` or generated AOT target.

The same source definition is also exercised through normal host mode. Its
focused data CTest passed 4/4, the pure compiler filter passed 122/122, and
the full CTest suite passed 5/5. Minimal mode deliberately rejects
`-DBUILD_TESTING=ON` before target generation; the expected rejected directory
contains no `build.ninja` or archive. An unset testing value is also off because
the mode returns before CTest is included. A cache file alone is not success.

### Validate the portable data-arena header proof

This is a pure C++ data-layout checkpoint. It does not bind the caller-owned
storage to `g_ee_main_mem`, initialize `kglobalheap` or the native `s7`,
`SymbolTable2`, `LastSymbol`, or `NumSymbols` globals, create types or native
trampolines, link game data, or execute GOAL code.

```sh
cmake -S /private/tmp/GOALPadOpenGOAL-data-arena-corrections \
  -B /private/tmp/GOALPadOpenGOAL-data-arena-corrections-build \
  -G Ninja -DCMAKE_BUILD_TYPE=Release

cmake --build /private/tmp/GOALPadOpenGOAL-data-arena-corrections-build \
  --target jak1-data-arena-test --parallel 4

ninja -C /private/tmp/GOALPadOpenGOAL-data-arena-corrections-build \
  goalc-test goalc-aot jak1-data-arena-test -j4

ctest --test-dir /private/tmp/GOALPadOpenGOAL-data-arena-corrections-build \
  -R '^Jak1DataArena\.' --output-on-failure

/private/tmp/GOALPadOpenGOAL-data-arena-corrections-build/goalc-test \
  --gtest_filter='Arm64Aot.*:ARM64EmitterLoads.*:ARM64EmitterIntegerMath.*:CodeTester.*:X86EmitterXMM.*:EmitterAVX.*'

ctest --test-dir /private/tmp/GOALPadOpenGOAL-data-arena-corrections-build \
  --output-on-failure
```

Recorded results: configuration, the focused target build, and Ninja build
exited `0`; the focused data-arena CTest run passed 4/4; the pure compiler
filter passed 122/122; and the complete CTest set passed 5/5, including the
existing `goalc-aot-artifact-pair` test.

The source itself was also compiled directly for iPhoneOS ARM64:

```sh
goalpad_iphoneos_sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos clang++ -std=c++20 -arch arm64 \
  -miphoneos-version-min=18.0 -isysroot "$goalpad_iphoneos_sdk" -I. \
  -c game/kernel/jak1/data_arena.cpp \
  -o /private/tmp/goalpad_jak1_data_arena_corrections_iphoneos.o
```

That command exited `0`; `otool` identified an 1848-byte `MH_MAGIC_64 ARM64`
object. This direct compile is not an iPhoneOS CMake or application build.

An iPhoneOS CMake configure preserving `CMAKE_OSX_SYSROOT=iphoneos` reached
vendored curl, then stopped at its first missing OpenSSL dependency. It did not
generate `build.ninja`, so it does not prove target generation or test-gate
behavior. The full desktop runtime test attempt is also not a pass: its
inherited runtime main-memory mapping reported `Permission denied`; a retry
progressed into `Jak1KernelTest` and was stopped with Ctrl-C (exit 130). Keep
the data-arena result scoped to the commands above.

### Validate the host ARM64 GOAL call ABI

Patch 0017 adds the macOS ARM64 `call_goal` dispatch to the existing
`call_goal_asm_arm64` helper and a static assembly probe. It is intentionally
separate from the portable data-arena archive: the new test links its probe,
`asm_funcs_arm64.s`, and GoogleTest, but not the OpenGOAL runtime or
CodeTester. The test does not execute compiler-produced GOAL code.

Recorded validation used a fresh disposable host build directory. CMake's
first configuration exposed a missing internal `CMAKE_ASM_COMPILE_OBJECT`
variable; patch 0017 fixes the source registration by enabling ASM inside the
Apple ARM64 host-test gate. The final fresh configuration below exited `0`
without a `CMAKE_ASM_COMPILE_OBJECT` override:

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

The focused ABI CTest passed 2/2, the data-arena CTest passed 4/4, the existing
host compiler filter passed 122/122 (with its usual `cpuid not implemented on
platform` warnings), and the full CTest set passed 7/7. `CodeTester.*` is part
of that separately invoked pre-existing host compiler filter; it is not linked
by, or evidence of JIT execution in, `arm64-goal-call-abi-test`.

The static probe verifies X0/X1/X2 argument mapping, X20 = X21 = synthetic
`st`, X22 = synthetic arena pointer, 16-byte entry-stack alignment, X0 return
propagation, restoration of caller X20/X21/X22 sentinels, and a false-like
entry returning X21. Link and symbol inspection identified an ARM64 Mach-O
test executable whose `_call_goal_asm_arm64` comes from its directly linked
`asm_funcs_arm64.s` object. Separately, `kscheme.cpp.o` references and
`libruntime.a` defines the same symbol in the normal runtime graph; the probe
does not link `libruntime.a`. This is host ABI evidence only, not live runtime
initialization, data-arena binding, app/signing, simulator, iPhoneOS, physical
iPad, or normally signed executable-GOAL evidence.

### Validate generated host Jak 1 AOT call artifacts

Patch 0018 keeps the existing macOS ARM64 host-test gate and uses one CMake
custom command to invoke `goalc-aot` sequentially for `false-func`,
`true-func`, `identity`, and `lognot`. Its eight explicit outputs are four
Mach-O ARM64 assembly files and four X-macro export headers. They are target
dependencies of `arm64-goal-call-abi-test`, which links the generated assembly,
the existing assembly dispatcher, `jak1-data-arena`, and GoogleTest; it does
not link the OpenGOAL runtime.

The final affected build and tests used the existing disposable macOS ARM64
host build directory:

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

The build exited `0` after 200 remaining curl/SDL/imgui and `goalc-test` steps;
it emitted one duplicate-zstd linker warning. ABI CTest passed 3/3, data-arena
CTest passed 4/4, the existing host compiler filter passed 122/122, and the
complete CTest set passed 8/8. All three discovered ABI tests use `RUN_SERIAL`
to keep the generated-artifact test's roughly 62.7 MiB local arena allocation
from competing with other CTest processes.

The generated functions execute through the production assembly dispatcher
with a local initialized arena and X20 = X21 = `s7`, X22 = the arena pointer.
Their current instruction streams intentionally use only X21/X0: false returns
X21, true returns X21 + 8, identity returns X0, and lognot returns `~X0`.
They do not dereference X22 or inspect arena contents. This proves generated
native artifact production, linkage, and bounded ABI calls; it does not prove
X22-relative addressing, a data-memory load, C++ `call_goal` runtime dispatch,
globals, runtime/JIT, iPhoneOS, app, signing, simulator, physical iPad, or
normally signed executable-GOAL behavior.

The same static inputs were also directly compiled for iPhoneOS ARM64 in
`/private/tmp/goalpad-ios-aot-context.RbzOUa`: the existing dispatcher assembly,
the four fresh host-generated assemblies, and the verified iPhoneOS
`data_arena.o` were archived and ranlib'd. The archive is arm64. The inspected
dispatcher, false-function, and data-arena objects report `LC_BUILD_VERSION`
platform iOS/minimum 18.0 (the assembly
objects have no SDK field and `data_arena.o` reports SDK 26.5). It defines
`initialize_data_arena_header`, `call_goal_asm_arm64`, and all four
`goalpad_aot_*` entries, with only `_bzero` undefined from the data-arena
object. This is direct iPhoneOS object/archive compatibility evidence only: it
does not link an executable or app, sign code, run in the simulator, access a
device, or execute a runtime.

Recorded from the 0018 child worktree, the direct proof command was:

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

With `ios_proof_dir=/private/tmp/goalpad-ios-aot-context.RbzOUa`, the following
inspection commands all exited `0`:

```sh
lipo -info "$ios_proof_dir/libopengoal-jak1-aot-context-ios.a"
xcrun vtool -show-build "$ios_proof_dir/asm_funcs_arm64.o"
xcrun vtool -show-build "$ios_proof_dir/OpenGOALJak1FalseFunc.o"
xcrun vtool -show-build "$ios_proof_dir/data_arena.o"
nm -gU "$ios_proof_dir/libopengoal-jak1-aot-context-ios.a" | \
  rg 'call_goal_asm_arm64|goalpad_aot_|initialize_data_arena_header'
nm -um "$ios_proof_dir/libopengoal-jak1-aot-context-ios.a"
```

Configure and build the affected tools serially enough to avoid excess memory
pressure:

```sh
cmake -S /private/tmp/GOALPadOpenGOAL-stage2 \
  -B /private/tmp/GOALPadOpenGOAL-stage3-build \
  --preset=Release-macos-arm64-clang \
  -DOPENSSL_ROOT_DIR=/opt/homebrew/opt/openssl@3

test -e /private/tmp/GOALPadOpenGOAL-stage3-build/data || \
  ln -s /private/tmp/GOALPadOpenGOAL-stage2 \
  /private/tmp/GOALPadOpenGOAL-stage3-build/data

cmake --build /private/tmp/GOALPadOpenGOAL-stage3-build \
  --target goalc-aot goalc-test gk -j 4
```

Run the deterministic affected tests and the complete non-network suite:

```sh
/private/tmp/GOALPadOpenGOAL-stage3-build/goalc-test \
  --gtest_filter='Arm64Aot.*:ARM64EmitterLoads.*:ARM64EmitterIntegerMath.*:CodeTester.*:X86EmitterXMM.*:EmitterAVX.*'

/private/tmp/GOALPadOpenGOAL-stage3-build/goalc-test \
  --gtest_filter='-Listener.*'

ctest --test-dir /private/tmp/GOALPadOpenGOAL-stage3-build \
  -R '^goalc-aot-artifact-pair$' --output-on-failure
```

Generate and compare the signed-build input:

```sh
/private/tmp/GOALPadOpenGOAL-stage3-build/goalc/goalc-aot \
  --project-path /private/tmp/GOALPadOpenGOAL-stage2 \
  --input \
  /private/tmp/GOALPadOpenGOAL-stage2/test/goalc/source_templates/arm64-aot/constant-42.gc \
  --output /private/tmp/goalpad_aot_constant_42.s \
  --symbol goalpad_aot_constant_42

cmp /private/tmp/goalpad_aot_constant_42.s \
  GOALPad/Native/Generated/OpenGOALConstant42.s

xcrun --sdk iphoneos clang -arch arm64 \
  -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" \
  -c /private/tmp/goalpad_aot_constant_42.s \
  -o /private/tmp/goalpad_aot_constant_42.o

xcrun llvm-objdump --macho --disassemble \
  /private/tmp/goalpad_aot_constant_42.o
```

The expected function is exactly `mov x0, #42; ret`. The checked-in assembly is
a transitional generated artifact; it must remain byte-for-byte reproducible
from the documented child commit until the fork-backed build integration
replaces it.

Generate and compare the real Jak 1 false-form input:

```sh
/private/tmp/GOALPadOpenGOAL-stage3-build/goalc/goalc-aot \
  --project-path /private/tmp/GOALPadOpenGOAL-stage2 \
  --input \
  /private/tmp/GOALPadOpenGOAL-stage2/test/goalc/source_templates/arm64-aot/false-from-jak1-gcommon.gc \
  --output /private/tmp/goalpad_aot_false.s \
  --symbol goalpad_aot_false

cmp /private/tmp/goalpad_aot_false.s \
  GOALPad/Native/Generated/OpenGOALJak1False.s

xcrun --sdk iphoneos clang -arch arm64 \
  -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" \
  -c /private/tmp/goalpad_aot_false.s \
  -o /private/tmp/goalpad_aot_false.o

xcrun llvm-objdump --macho --disassemble \
  /private/tmp/goalpad_aot_false.o
```

The expected function is exactly `mov x0, x21; ret`. It returns OpenGOAL
`#f`, which is the X21 `st` base at offset zero.

Generate and compare the selected body from the complete real Jak 1
`false-func` definition:

```sh
/private/tmp/GOALPadOpenGOAL-stage3-build/goalc/goalc-aot \
  --project-path /private/tmp/GOALPadOpenGOAL-stage2 \
  --input \
  /private/tmp/GOALPadOpenGOAL-stage2/test/goalc/source_templates/arm64-aot/full-false-func-from-jak1-gcommon.gc \
  --function false-func \
  --output /private/tmp/goalpad_aot_full_false_func.s \
  --exports-output /private/tmp/goalpad_aot_full_false_func.exports.h \
  --symbol goalpad_aot_false_func

cmp /private/tmp/goalpad_aot_full_false_func.s \
  GOALPad/Native/Generated/OpenGOALJak1FalseFunc.s

cmp /private/tmp/goalpad_aot_full_false_func.exports.h \
  GOALPad/Native/Generated/OpenGOALJak1FalseFunc.exports.h

xcrun --sdk iphoneos clang -arch arm64 \
  -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" \
  -c /private/tmp/goalpad_aot_full_false_func.s \
  -o /private/tmp/goalpad_aot_full_false_func.o

xcrun llvm-objdump --macho --disassemble \
  /private/tmp/goalpad_aot_full_false_func.o
```

The selected body is exactly `mov x0, x21; ret`. Paired output also emits the
guarded C++ X-macro record
`OPENGOAL_AOT_EXPORT0("false-func", goalpad_aot_false_func)`. The pair is
published together with recovery if either destination cannot be replaced;
the CTest covers same-assembly output, invalid metadata, path aliases,
destination failures, and temporary-name collisions. The compiler processes
the complete `defun`, but the current artifact still does not apply the
surrounding top-level `define` or install `false-func` in a live GOAL symbol
table. Do not substitute the desktop V3 runtime linker.

Generate and compare the complete real Jak 1 `identity` definition:

```sh
/private/tmp/GOALPadOpenGOAL-stage3-build/goalc/goalc-aot \
  --project-path /private/tmp/GOALPadOpenGOAL-stage2 \
  --input \
  /private/tmp/GOALPadOpenGOAL-stage2/test/goalc/source_templates/arm64-aot/full-identity-from-jak1-gcommon.gc \
  --function identity \
  --output /private/tmp/goalpad_aot_identity.s \
  --exports-output /private/tmp/goalpad_aot_identity.exports.h \
  --symbol goalpad_aot_identity

cmp /private/tmp/goalpad_aot_identity.s \
  GOALPad/Native/Generated/OpenGOALJak1Identity.s

cmp /private/tmp/goalpad_aot_identity.exports.h \
  GOALPad/Native/Generated/OpenGOALJak1Identity.exports.h

xcrun --sdk iphoneos clang -arch arm64 \
  -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" \
  -c /private/tmp/goalpad_aot_identity.s \
  -o /private/tmp/goalpad_aot_identity.o

xcrun llvm-objdump --macho --disassemble \
  /private/tmp/goalpad_aot_identity.o
```

The exact supported one-argument body is `ret`: it preserves the ordinary
Apple-ABI X0 object argument as its return value. The paired metadata is
`OPENGOAL_AOT_EXPORT1("identity", goalpad_aot_identity)`. Cross-ABI metadata
or wrong-symbol requests fail without replacing existing output artifacts.

Generate and compare the complete real Jak 1 `true-func` definition:

```sh
/private/tmp/GOALPadOpenGOAL-stage3-build/goalc/goalc-aot \
  --project-path /private/tmp/GOALPadOpenGOAL-stage2 \
  --input \
  /private/tmp/GOALPadOpenGOAL-stage2/test/goalc/source_templates/arm64-aot/full-true-func-from-jak1-gcommon.gc \
  --function true-func \
  --output /private/tmp/goalpad_aot_true_func.s \
  --exports-output /private/tmp/goalpad_aot_true_func.exports.h \
  --symbol goalpad_aot_true_func

cmp /private/tmp/goalpad_aot_true_func.s \
  GOALPad/Native/Generated/OpenGOALJak1TrueFunc.s

cmp /private/tmp/goalpad_aot_true_func.exports.h \
  GOALPad/Native/Generated/OpenGOALJak1TrueFunc.exports.h

xcrun --sdk iphoneos clang -arch arm64 \
  -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" \
  -c /private/tmp/goalpad_aot_true_func.s \
  -o /private/tmp/goalpad_aot_true_func.o

xcrun llvm-objdump --macho --disassemble \
  /private/tmp/goalpad_aot_true_func.o
```

The exact zero-argument body is `mov x0, x21; add x0, x0, #8; ret`, returning
OpenGOAL `#t` as the `st` base plus eight. The paired metadata is
`OPENGOAL_AOT_EXPORT0("true-func", goalpad_aot_true_func)`. The compiler
rejects false-body, wrong-symbol, and cross-ABI requests without replacing
existing paired artifacts. The selected text is build-time native binding;
the surrounding top-level `define`, live GOAL symbol installation, and desktop
V3 runtime linker remain unsupported.

Generate the exact real one-argument Jak 1 `lognot` definition and its paired
typed export metadata:

```sh
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

xcrun --sdk iphoneos clang -arch arm64 \
  -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" \
  -c /private/tmp/goalpad_aot_lognot.s \
  -o /private/tmp/goalpad_aot_lognot.o

xcrun llvm-objdump --macho --disassemble \
  /private/tmp/goalpad_aot_lognot.o
```

The selected one-argument `int` body is exactly `mvn x0, x0; ret`. Its paired
metadata is `OPENGOAL_AOT_EXPORT1("lognot", goalpad_aot_lognot)`. The compiler
rejects mismatched symbols and cross-ABI export requests atomically, preserving
the existing paired destinations. The checked-in artifact is bound by the
app-local registry and called through the existing signed X0/state wrapper; it
is not a live GOAL symbol, top-level definition, or relocation mechanism.

## Validate the static OpenGOAL ARM64 call boundary

The app-local boundary establishes the compiler contract's special registers:
X20 is process/`pp`, X21 is `st`, and X22 is the GOAL memory offset base. The
deterministic host harness uses distinct synthetic values, verifies them before
and after the generated call, and verifies that the wrapper restores the
caller's callee-saved values:

```sh
xcrun --sdk macosx clang -arch arm64 \
  tests/native/GOALPadAOTStateHarness.c \
  GOALPad/Native/Generated/OpenGOALJak1FalseFunc.s \
  GOALPad/Native/Generated/OpenGOALJak1TrueFunc.s \
  GOALPad/Native/GOALPadGoalStateWrapper.s \
  -o /private/tmp/goalpad_jak1_true_func_state_harness

/private/tmp/goalpad_jak1_true_func_state_harness
```

Exit `0` is required. These values are never dereferenced, so this test proves
the signed static ABI/state boundary only. It does not prove real kernel,
symbol-table, or GOAL-memory initialization.

## Validate the generated native export registry

The generated metadata is included only after the app-local registry defines
the matching `OPENGOAL_AOT_EXPORT0` or `OPENGOAL_AOT_EXPORT1` macro. The
registry exposes typed zero- and one-argument native entries outside the
legacy 32-bit GOAL symbol representation; it does not mutate a live GOAL
symbol table.

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

Exit `0` requires successful typed `false-func`, `true-func`, `identity`, and
`lognot` lookups; rejects cross-type/missing names; verifies `true-func`
returns X21 plus eight and `lognot` complements its X0 argument; and proves
the one-argument wrappers establish X20/X21/X22 before placing their arguments
in X0 while preserving caller state. It is not live GOAL symbol-table,
relocation, or runtime initialization evidence.

## Physical iPad validation

A physical-device pass is not a routine build step. Use the local iPad Pro
11-inch (M5) simulator by default. Do not run the commands in this section
against **Z iPad Pro** unless the maintainer explicitly requests physical
testing in the current task. A generic signed iOS build may still be run
without accessing the physical device and must be reported as build/signing
evidence only.

A signed physical-device build must omit `CODE_SIGNING_ALLOWED=NO`. A generic
iOS build can complete signing even while the device is locked:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-device -jobs 4 build

xcrun devicectl device install app \
  --device <coredevice-id> \
  /private/tmp/GOALPad-device/Build/Products/Debug-iphoneos/GOALPad.app

xcrun devicectl device process launch \
  --device <coredevice-id> \
  --terminate-existing com.zephyrstudiosllc.GOALPad

xcrun devicectl device process launch \
  --device <coredevice-id> \
  --terminate-existing --console --timeout 10 \
  com.zephyrstudiosllc.GOALPad
```

Unlock the iPad before the install/launch steps. Record build, signing, install,
launch, runtime logs, and observed screen behavior separately. Simulator,
generic-device build, or installation success must not be reported as
physical-device execution. A console command timing out after it has launched
the foreground app is expected; retain the runtime line that precedes the
timeout and perform a final normal launch.
