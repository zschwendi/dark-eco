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

These commands validate compilation and linking only. The generic iOS build is
not physical-device validation.

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
```

If that branch or worktree already exists, inspect and reuse it rather than
deleting it. Do not move the parent repository's official submodule gitlink to
the unpublished child commit.

The restored commits are patch-equivalent to `79f22008`, `149840cf`,
`32cf26ae`, and `92c8f975`, but `git am` normally assigns new committer
metadata and therefore different commit SHAs. The exact objects are available
only in a checkout that already contains the original child commits. Compare
the resulting tree or stable patch identities when reconstructing them from
the preserved patches.

Configure and build the affected tools serially enough to avoid excess memory
pressure:

```sh
cmake -S /private/tmp/GOALPadOpenGOAL-stage2 \
  -B /private/tmp/GOALPadOpenGOAL-stage2-build \
  --preset=Release-macos-arm64-clang \
  -DOPENSSL_ROOT_DIR=/opt/homebrew/opt/openssl@3

test -e /private/tmp/GOALPadOpenGOAL-stage2-build/data || \
  ln -s /private/tmp/GOALPadOpenGOAL-stage2 \
  /private/tmp/GOALPadOpenGOAL-stage2-build/data

cmake --build /private/tmp/GOALPadOpenGOAL-stage2-build \
  --target goalc-aot goalc-test gk -j 4
```

Run the deterministic affected tests and the complete non-network suite:

```sh
/private/tmp/GOALPadOpenGOAL-stage2-build/goalc-test \
  --gtest_filter='Arm64Aot.*:ARM64EmitterLoads.*:ARM64EmitterIntegerMath.*:CodeTester.*:X86EmitterXMM.*:EmitterAVX.*'

/private/tmp/GOALPadOpenGOAL-stage2-build/goalc-test \
  --gtest_filter='-Listener.*'
```

Generate and compare the signed-build input:

```sh
/private/tmp/GOALPadOpenGOAL-stage2-build/goalc/goalc-aot \
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
/private/tmp/GOALPadOpenGOAL-stage2-build/goalc/goalc-aot \
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
/private/tmp/GOALPadOpenGOAL-stage2-build/goalc/goalc-aot \
  --project-path /private/tmp/GOALPadOpenGOAL-stage2 \
  --input \
  /private/tmp/GOALPadOpenGOAL-stage2/test/goalc/source_templates/arm64-aot/full-false-func-from-jak1-gcommon.gc \
  --function false-func \
  --output /private/tmp/goalpad_aot_full_false_func.s \
  --symbol goalpad_aot_false_func

cmp /private/tmp/goalpad_aot_full_false_func.s \
  GOALPad/Native/Generated/OpenGOALJak1FalseFunc.s

xcrun --sdk iphoneos clang -arch arm64 \
  -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" \
  -c /private/tmp/goalpad_aot_full_false_func.s \
  -o /private/tmp/goalpad_aot_full_false_func.o

xcrun llvm-objdump --macho --disassemble \
  /private/tmp/goalpad_aot_full_false_func.o
```

The selected body is exactly `mov x0, x21; ret`. The compiler processes the
complete `defun`, but the current artifact contains only the named signed text
function. It does not yet apply the surrounding top-level `define` or install
`false-func` in a live GOAL symbol table. That requires the Stage 4 static
export and runtime-data model; do not substitute the desktop V3 runtime
linker.

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
  GOALPad/Native/GOALPadGoalStateWrapper.s \
  -o /private/tmp/goalpad_jak1_full_false_func_state_harness

/private/tmp/goalpad_jak1_full_false_func_state_harness
```

Exit `0` is required. These values are never dereferenced, so this test proves
the signed static ABI/state boundary only. It does not prove real kernel,
symbol-table, or GOAL-memory initialization.

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
