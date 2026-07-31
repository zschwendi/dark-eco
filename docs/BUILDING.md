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
Its Preview split bundle places the AOT code in signed `GOALPad.debug.dylib`
with RX `__TEXT` and no `mmap`, `mprotect`, or JIT-protect imports, but the main
Debug stub imports `dlopen`/`dlsym` and contains Preview JIT strings. In
addition, `codesign` display inspection reports unavailable authority, an
unbound Info.plist, and invalid or ignored app-executable entitlements; the
embedded profile has no JIT entitlement. Do not treat this Debug output as
release-like no-JIT evidence. Record and inspect a Release-like signed build
before making that claim.

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
```

If that branch or worktree already exists, inspect and reuse it rather than
deleting it. Do not move the parent repository's official submodule gitlink to
the unpublished child commit.

The restored commits are patch-equivalent to `79f22008`, `149840cf`,
`32cf26ae`, `92c8f975`, `b78d7c28`, `1fc20e79`, `25917e27`, `1c80b667`,
`35d653f1`, and `f979c82c`, but `git am` normally assigns new committer
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

ctest --test-dir /private/tmp/GOALPadOpenGOAL-stage2-build \
  -R '^goalc-aot-artifact-pair$' --output-on-failure
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
/private/tmp/GOALPadOpenGOAL-stage2-build/goalc/goalc-aot \
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
/private/tmp/GOALPadOpenGOAL-stage2-build/goalc/goalc-aot \
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
  GOALPad/Native/GOALPadGoalStateWrapper.s \
  -o /private/tmp/goalpad_aot_export_registry_harness

/private/tmp/goalpad_aot_export_registry_harness
```

Exit `0` requires successful typed `false-func`, `true-func`, and `identity`
lookups; rejects cross-type/missing names; verifies `true-func` returns X21
plus eight; and proves the identity wrapper establishes X20/X21/X22 before
placing its argument in X0 while preserving caller state. It is not live GOAL
symbol-table, relocation, or runtime initialization evidence.

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
