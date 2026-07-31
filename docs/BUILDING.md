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

It produced a monolithic ARM64 main executable with no `GOALPad.debug.dylib`
or `__preview.dylib`. The current complete `load-state::reset!` Export1 entry
is at `0x100004020`; its 58 instructions occupy 232 bytes and have raw
SHA-256
`2f0171fc455619ad95eb20ef2686b4a8db1642cd94a727e22121051420ab4edd`,
matching the checked-in `.long` stream. The main executable SHA-256 is
`aae97872933a7ba266ad8041e77c076e6769a26e85cb3fc3535e121d9f117c6b`.
The embedded provisioning profile remains unchanged; its SHA-256 is
`ef4a32f9aef6cca1709423e53e66518204e49a86af4d2752139de63d21244ad1`.
Its `__TEXT` initial protection is `0x5` (read/execute); undefined imports
contain none of `dlopen`,
`dlsym`, `mmap`, `mprotect`, or `pthread_jit`; and its strings contain no
Preview/JIT marker.

`codesign -d --entitlements -` reports application identifier, team identifier,
and `get-task-allow = true`; there is no JIT entitlement. This is an
Apple Development signature, not distribution or App Store evidence. The
current local profile expires at `2026-08-06T23:51:59Z`. The stricter local
`codesign --verify --deep --strict` check still returns
`CSSMERR_TP_NOT_TRUSTED`. This is a known local certificate-trust caveat, not a
substitute for successful Xcode signing or physical-device validation. No
physical-device installation or execution was performed; treat this Release
output as static build/signing evidence only.

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
Jak 1 node-name compiler/export child: fab37c1f755aa342304db8dbf27f1fa1c42423ac
Jak 1 node-name compiler/export patch: patches/OpenGOAL/0019-feat-arm64-AOT-compile-Jak-1-node-name-lookup-AI-ass.patch
X22-backed node-name host execution child: 1e43e767d66b6f554a6cc9aedb9fa024ca3130ee
X22-backed node-name host execution patch: patches/OpenGOAL/0020-test-arm64-execute-X22-backed-GOAL-field-load-AI-ass.patch
Level command store compiler child: cb1cc102ac2af46e9581ac5b47404fe797c5b582
Level command store compiler patch: patches/OpenGOAL/0021-feat-arm64-compile-Jak-1-level-command-store-AI-assi.patch
Reserved store operand guard child: 311be4773feaf85740427d844e1db65ba4fe5591
Reserved store operand guard patch: patches/OpenGOAL/0022-fix-arm64-reject-reserved-constant-store-operands-AI.patch
Level command store host execution child: 13672fadb3fa977f407d19f15989136c38f58d61
Level command store host execution patch: patches/OpenGOAL/0023-test-arm64-execute-Jak-1-level-command-store-AI-assi.patch
Want-vis compiler child: 3c6d7f871a86ecfa53a3cbd94e90237986c68219
Want-vis compiler patch: patches/OpenGOAL/0024-feat-arm64-compile-Jak-1-load-state-vis-store-AI-ass.patch
Want-vis layout child: d3492375caf8de14815133c3597eb65efb44bca2
Want-vis layout patch: patches/OpenGOAL/0025-test-arm64-preserve-want-vis-inline-layout-AI-assist.patch
Want-vis host execution child: 3b821e75b4995a6e9a81f2624beb2485191e4e96
Want-vis host execution patch: patches/OpenGOAL/0026-test-arm64-execute-Jak-1-want-vis-store-AI-assisted.patch
ARM64 encoder correction child: 732a99553a5208b0f58b70d43f146592496a8863
ARM64 encoder correction patch: patches/OpenGOAL/0027-fix-arm64-correct-AOT-encoder-primitives-AI-assisted.patch
Local control-flow child: e5daa70a8ebaa569859acf3f5d51a56a4f727287
Local control-flow patch: patches/OpenGOAL/0028-feat-arm64-materialize-local-AOT-control-flow-AI-ass.patch
Guarded integer-math child: 38e15824de976e4fd9d9ebbc9e2e3d70cbfbbee9
Guarded integer-math patch: patches/OpenGOAL/0029-feat-arm64-lower-guarded-AOT-integer-math-AI-assiste.patch
Signed-loop child: f514c40ff8205760d3219a4676747218f5418cb3
Signed-loop patch: patches/OpenGOAL/0030-feat-arm64-lower-signed-AOT-loop-backedges-AI-assist.patch
Complete want-levels compiler child: 0b461a5619397e3a6f1c9699436023b088ba6814
Complete want-levels compiler patch: patches/OpenGOAL/0031-feat-arm64-compile-complete-Jak-1-want-levels-body-A.patch
Want-levels Export3 child: 16123d8d317704e9f18cccbd124a1615824e5ae2
Want-levels Export3 patch: patches/OpenGOAL/0032-feat-aot-export-Jak-1-want-levels-with-three-argumen.patch
Want-levels host execution child: 71fc691895acf44746961b7c7a3910da376ed0fd
Want-levels host execution patch: patches/OpenGOAL/0033-test-arm64-execute-Jak-1-want-levels-branch-matrix-A.patch
Load-state reset compiler child: e96cedd236512ca629455e3e2bab97ae28e410a1
Load-state reset compiler patch: patches/OpenGOAL/0034-feat-arm64-compile-Jak-1-load-state-reset-body-AI-as.patch
Load-state reset Export1 child: 2229c13ea7f1563327e03e29951425f8ce345185
Load-state reset Export1 patch: patches/OpenGOAL/0035-feat-aot-export-direct-Jak-1-load-state-reset-AI-ass.patch
Load-state reset host execution child: bb4b2e7e8705f55e8629da10cad9fb25d10e6cba
Load-state reset host execution patch: patches/OpenGOAL/0036-test-arm64-execute-Jak-1-load-state-reset-body-AI-as.patch
Load-state symbol-value child: 0327eee4886f7a076d3b01f8e62afc3adddb8eeb
Load-state symbol-value patch: patches/OpenGOAL/0037-Add-ARM64-load-state-symbol-value-proof-AI-assisted.patch
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

git -C /private/tmp/GOALPadOpenGOAL-stage2 am \
  "$PWD/patches/OpenGOAL/0019-feat-arm64-AOT-compile-Jak-1-node-name-lookup-AI-ass.patch"

git -C /private/tmp/GOALPadOpenGOAL-stage2 am \
  "$PWD/patches/OpenGOAL/0020-test-arm64-execute-X22-backed-GOAL-field-load-AI-ass.patch"

git -C /private/tmp/GOALPadOpenGOAL-stage2 am \
  "$PWD/patches/OpenGOAL/0021-feat-arm64-compile-Jak-1-level-command-store-AI-assi.patch"
```

If that branch or worktree already exists, inspect and reuse it rather than
deleting it. Do not move the parent repository's official submodule gitlink to
the unpublished child commit.

Patches 0022 and 0023 are sibling child commits of 0021, not a verified linear
continuation after it. Preserve both mboxes, but use a fresh dedicated
restoration audit and combined build before choosing an `am --3way` or other
merge procedure. Do not claim that 0023 descends from 0022.

Do not append patches 0024-0036 blindly to that historical `git am` example.
Patches 0027-0032 form the reviewed literal compiler/export line
`732a9955 -> e5daa70a -> 38e15824 -> f514c40f -> 0b461a56 -> 16123d8d`.
Patch 0033 follows a runtime line based on 3b821e75 with stable-equivalent
replays of 0027-0032:

```text
3b821e75 -> a09cd329 -> ec0bcc31 -> 57ecc6e8
           -> 0291745c -> f1975b56 -> 93a97199 -> 71fc6918
```

Patches 0034-0036 then depend on that reconstructed `71fc6918` runtime line,
not the historical 0021 `git am` example:

```text
71fc6918 -> e96cedd2 -> 2229c13e -> bb4b2e7e
```

Preserve all mboxes and stable patch IDs, then reconstruct and validate a
combined branch in a dedicated worktree. Do not claim literal ancestry between
the replay commits and original child objects.

The restoration commands above produce commits patch-equivalent to `79f22008`, `149840cf`,
`32cf26ae`, `92c8f975`, `b78d7c28`, `1fc20e79`, `25917e27`, `1c80b667`,
`35d653f1`, `f979c82c`, `2475b3c1`, `9acf4e79`, `5c536859`, `b094144b`,
`5495181f`, `5ad2efa3`, `45e1897f`, `bd3f4752`, `fab37c1f`, and `1e43e767`,
and `cb1cc102`. A later combined sibling-restoration audit may establish an
appropriate application procedure for the preserved `311be477` and `13672fad`
patches. `git am` normally assigns new committer metadata and therefore
different commit SHAs. The exact objects are available only in a checkout that
already contains the original child commits. Compare the resulting tree or
stable patch identities when reconstructing them from the preserved patches.

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

Patch 0019 follows 0018. It is a strict compiler/export-only checkpoint for
the exact maintained debug-only Jak 1 `glst-node-name` form. It does not add a
CMake generated artifact or execute through the host ABI test; those remain
the separate 0020 task. It is not a general ARM64 load, iPhoneOS, app, signing,
simulator, or device proof.

Patch 0020 follows 0019 and extends that existing macOS ARM64 host-test gate
only. It generates and links the exact `glst-node-name` artifact, dispatches it
through the existing one-arena serial ABI test, and verifies two X22 logical
bases against two unsigned fields. It is not a general ARM64 load, live
runtime, iPhoneOS executable, app, signing, simulator, or device proof.

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

### Validate the strict Jak 1 node-name compiler/export proof

Patch 0019 accepts only the exact maintained debug-only Jak 1
`glst-node-name` definition. The one `glst-named-node` argument is combined
with the X22 GOAL-memory logical base; the result loads the unsigned 32-bit
`privname` field at byte offset eight. The generated text is exactly:

```text
add x16, x0, x22, sxtx
ldur w0, [x16, #8]
ret
```

Its words are `8b36e010`, `b8408200`, and `d65f03c0`. The paired typed export
is `OPENGOAL_AOT_EXPORT1("glst-node-name", goalpad_aot_glst_node_name)`.
Body, name, field-type, field-offset, arity, cross-ABI, and symbol mismatches
are rejected before existing paired outputs are replaced.

Recorded validation built `goalc-test` and `goalc-aot` with `-j4`. The
`Arm64Aot.*` filter passed 41/41; the type/form regression passed 190/190; the
established compiler/emitter filter passed 129/129; the AOT CLI CTest passed
1/1; and full CTest passed 8/8. Host disassembly of the generated assembly
reported the three instructions above.

No generated CMake artifact was linked or executed for 0019. In particular,
this is not evidence for a general ARM64 load implementation, initialized
arena memory, C++ runtime dispatch, an iPhoneOS executable, an app, signing,
simulator, or physical hardware. The follow-on 0020 checkpoint was narrowly
scoped to a generated CMake artifact plus host-dispatcher execution: one
allocation, two distinct X22 logical bases, the same nonzero node offset, and
two high-bit unsigned 32-bit payloads at offset eight. It retains `RUN_SERIAL`
and the existing host-only claim boundary.

### Validate the host X22-backed Jak 1 node-name artifact

Patch 0020 extends the existing Apple ARM64 host-only CMake custom command
with `OpenGOALJak1GlstNodeName.s` and its guarded Export1 header. The generated
assembly links directly into `arm64-goal-call-abi-test` beside the existing
dispatcher, data-arena library, GoogleTest, and the four earlier AOT entries;
it does not link the OpenGOAL runtime.

The existing serial one-arena test uses the canonical nonzero
`global_heap_current` field as the same X0 node offset in both calls. It writes
the unsigned 32-bit values `0x81234567` and `0xf2345678` at that offset plus
eight under two X22 logical bases 0x40 bytes apart. The production dispatcher
sets the requested X22 base for each call, and the generated entry returns
`0x0000000081234567` then `0x00000000f2345678`; the high 32 bits and all
caller-state restoration checks pass. This is evidence for only the exact
`glst-node-name` field load, not general ARM64 loads, runtime/global binding,
the C++ `call_goal` path, JIT, an executable or app, signing, simulator, or
physical-device behavior.

The final host validation used the following commands:

```sh
cmake --build /private/tmp/GOALPadOpenGOAL-arm64-goal-call-host-final-build \
  --target runtime arm64-goal-call-abi-test jak1-data-arena-test goalc-test goalc-aot \
  -j 4

ctest --test-dir /private/tmp/GOALPadOpenGOAL-arm64-goal-call-host-final-build \
  -R '^Arm64GoalCallAbi\.' --output-on-failure

ctest --test-dir /private/tmp/GOALPadOpenGOAL-arm64-goal-call-host-final-build \
  -R '^Jak1DataArena\.' --output-on-failure

/private/tmp/GOALPadOpenGOAL-arm64-goal-call-host-final-build/goalc-test \
  --gtest_filter='Arm64Aot.*:ARM64EmitterLoads.*:ARM64EmitterIntegerMath.*:CodeTester.*:X86EmitterXMM.*:EmitterAVX.*'

ctest --test-dir /private/tmp/GOALPadOpenGOAL-arm64-goal-call-host-final-build \
  -R '^goalc-aot-artifact-pair$' --output-on-failure

ctest --test-dir /private/tmp/GOALPadOpenGOAL-arm64-goal-call-host-final-build \
  --output-on-failure
```

The build exited `0`; ABI CTest passed 3/3, data-arena CTest passed 4/4, the
established compiler/emitter filter passed 129/129, AOT CLI CTest passed 1/1,
and full CTest passed 8/8. A Ninja graph query confirmed
`goalc-aot -> arm64-goal-call-aot-artifacts -> arm64-goal-call-abi-test`.
Symbol inspection found the dispatcher and all five generated AOT entries.
Disassembly confirmed the dispatcher X22 setup and the exact generated
`add x16, x0, x22, sxtx; ldur w0, [x16, #8]; ret` sequence. Import inspection
found no forbidden imports.

An initial `clang-format` pass reordered the contiguous Export1 generated
includes, changing the order of the table that their expansions define. The
corrected declaration and table include blocks are now wrapped in
`clang-format off` / `clang-format on`, and order assertions protect
`identity`, `lognot`, then `glst-node-name`. Final review found no blockers.

The minimal iPhoneOS data-arena configuration was independently reconfigured
and built from `/private/tmp/GOALPadOpenGOAL-arm64-goal-call` using the existing
reused build directory:

```sh
cmake -S /private/tmp/GOALPadOpenGOAL-arm64-goal-call \
  -B /private/tmp/GOALPadOpenGOAL-arm64-goal-call-iphoneos-0018-build \
  -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 \
  -DOPENGOAL_BUILD_JAK1_DATA_ARENA_ONLY=ON -DBUILD_TESTING=OFF

cmake --build /private/tmp/GOALPadOpenGOAL-arm64-goal-call-iphoneos-0018-build \
  --target jak1-data-arena -j 4
```

Both commands passed. The direct archive proof at
`/private/tmp/goalpad-ios-aot-x22.38XD72/libopengoal-jak1-aot-context-ios.a`
also passed. It compiles the dispatcher and fifth generated assembly with the
other four host-generated entries, then archives them with the iPhoneOS
data-arena object. Run the following commands from
`/private/tmp/GOALPadOpenGOAL-arm64-goal-call`:

```sh
ios_proof_dir=/private/tmp/goalpad-ios-aot-x22.38XD72
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=18.0 \
  -c game/kernel/asm_funcs_arm64.s -o "$ios_proof_dir/asm_funcs_arm64.o"
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=18.0 \
  -c /private/tmp/GOALPadOpenGOAL-arm64-goal-call-host-final-build/generated-arm64-goal-call/OpenGOALJak1FalseFunc.s \
  -o "$ios_proof_dir/OpenGOALJak1FalseFunc.o"
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=18.0 \
  -c /private/tmp/GOALPadOpenGOAL-arm64-goal-call-host-final-build/generated-arm64-goal-call/OpenGOALJak1TrueFunc.s \
  -o "$ios_proof_dir/OpenGOALJak1TrueFunc.o"
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=18.0 \
  -c /private/tmp/GOALPadOpenGOAL-arm64-goal-call-host-final-build/generated-arm64-goal-call/OpenGOALJak1Identity.s \
  -o "$ios_proof_dir/OpenGOALJak1Identity.o"
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=18.0 \
  -c /private/tmp/GOALPadOpenGOAL-arm64-goal-call-host-final-build/generated-arm64-goal-call/OpenGOALJak1Lognot.s \
  -o "$ios_proof_dir/OpenGOALJak1Lognot.o"
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=18.0 \
  -c /private/tmp/GOALPadOpenGOAL-arm64-goal-call-host-final-build/generated-arm64-goal-call/OpenGOALJak1GlstNodeName.s \
  -o "$ios_proof_dir/OpenGOALJak1GlstNodeName.o"
cp /private/tmp/GOALPadOpenGOAL-arm64-goal-call-iphoneos-0018-build/CMakeFiles/jak1-data-arena.dir/game/kernel/jak1/data_arena.cpp.o \
  "$ios_proof_dir/data_arena.o"
xcrun ar qc "$ios_proof_dir/libopengoal-jak1-aot-context-ios.a" \
  "$ios_proof_dir/data_arena.o" "$ios_proof_dir/asm_funcs_arm64.o" \
  "$ios_proof_dir/OpenGOALJak1FalseFunc.o" "$ios_proof_dir/OpenGOALJak1TrueFunc.o" \
  "$ios_proof_dir/OpenGOALJak1Identity.o" "$ios_proof_dir/OpenGOALJak1Lognot.o" \
  "$ios_proof_dir/OpenGOALJak1GlstNodeName.o"
xcrun ranlib "$ios_proof_dir/libopengoal-jak1-aot-context-ios.a"
```

The inspected archive is arm64. The dispatcher and generated `glst-node-name`
object report iOS minimum 18.0 with SDK n/a; `data_arena.o` reports iOS minimum
18.0 with SDK 26.5. It defines the dispatcher and five AOT entry symbols, has
only `_bzero` undefined, and its iPhoneOS disassembly matches the exact three
instruction field load above. This is static compatibility evidence only: no
executable or app link, signing, simulator, physical device, or runtime
execution occurred.

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
the matching `OPENGOAL_AOT_EXPORT0`, `OPENGOAL_AOT_EXPORT1`,
`OPENGOAL_AOT_EXPORT2`, or `OPENGOAL_AOT_EXPORT3` macro. The registry exposes
two zero-argument, three one-argument, two two-argument, and one three-argument
native entry outside the legacy 32-bit GOAL symbol representation; it does not
mutate a live GOAL symbol table.

```sh
xcrun --sdk macosx clang++ -std=c++20 -arch arm64 \
  -I GOALPad/Native \
  tests/native/GOALPadAOTExportRegistryHarness.cpp \
  GOALPad/Native/GOALPadAOTExportRegistry.cpp \
  GOALPad/Native/Generated/OpenGOALJak1FalseFunc.s \
  GOALPad/Native/Generated/OpenGOALJak1TrueFunc.s \
  GOALPad/Native/Generated/OpenGOALJak1Identity.s \
  GOALPad/Native/Generated/OpenGOALJak1Lognot.s \
  GOALPad/Native/Generated/OpenGOALJak1LevelGroupLoadCommandsSet.s \
  GOALPad/Native/Generated/OpenGOALJak1WantVis.s \
  GOALPad/Native/Generated/OpenGOALJak1WantLevels.s \
  GOALPad/Native/Generated/OpenGOALJak1LoadStateReset.s \
  GOALPad/Native/GOALPadGoalStateWrapper.s \
  -o /private/tmp/goalpad_aot_export_registry_harness_load_state_reset

/private/tmp/goalpad_aot_export_registry_harness_load_state_reset
```

Exit `0` requires successful typed `false-func`, `true-func`, `identity`,
`lognot`, direct `level-group-load-commands-set!`, direct `want-vis`, and
complete direct `want-levels` and `reset!` lookups; rejects every cross-type or
missing name; verifies `true-func`
returns X21 plus eight and `lognot` complements its X0 argument; and proves
the two-argument wrapper establishes X20/X21/X22 before placing its values in
X0/X1. The level-command proof checks full-width returns and W1 stores. The
`want-vis` proof uses X0 `0x4` and two aligned synthetic X22 bases, checks
low-word stores only at raw offsets `0x34` and `0x94`, requires a zero return,
preserves the first write across the second call, verifies whole-buffer guard
bytes, and checks caller-register restoration. It is not live GOAL
symbol-table, method-installation, dispatch, relocation, or
runtime-initialization evidence. The `want-levels` proof supplies X0
`this = 4`, two level arguments in X1/X2, Jak 1 `#f = 0x14fd24` in X21, and
an aligned arena in X22. It verifies all six retained/replaced/duplicate/false
argument cases, the exact two inline `want` slots, whole-arena equality,
explicit guard regions, and caller-register restoration. The `reset!` proof
uses X0 `this = 4`, Jak 1 `#f` in X21, and two disjoint aligned X22 arena
bases. It checks all eight `want` fields, the empty-list `command-list`, all
256 `object-name` and 256 `object-status` entries, the complete untouched gap
and canaries, the full-width return, and caller-register restoration. It is a
direct static method-body proof, not installation or virtual dispatch.

The checked-in method-body artifacts must match the compiler outputs exactly:

```text
718e440c35491569102a22ea6bf9fb204ec60fa6ade91c54dbb4602c25c081f0  OpenGOALJak1WantVis.s
18bc127bd7bfd2af14bd40a6db0277d0a0ce0ce97778f7fd2ead4fc78493d23f  OpenGOALJak1WantVis.exports.h
b02fe8ba458f85597d1900c854dca08cdaf001e9b56b854e6de81f16259e8f96  OpenGOALJak1WantLevels.s
840388bd896ceb4b98e6b6365175fe7328f0096f6cd659fbd301e923d509effc  OpenGOALJak1WantLevels.exports.h
b6c9baab7b6bb5b94a282013aeaf28adf29894644adeacff0f27873740110964  OpenGOALJak1LoadStateReset.s
51df1b61f6a9e134307300958564bd0fa66c3fc6fddda385040f7abdcf0371fb  OpenGOALJak1LoadStateReset.exports.h
```

### Historical Checkpoint 11 validation evidence

The then-current `want-vis` registry harness command compiled and exited `0`.
The corresponding ARM64 macOS Debug build also passed:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/GOALPad-mac -jobs 4 \
  CODE_SIGNING_ALLOWED=NO build
```

`GOALPad.debug.dylib` has SHA-256
`5d802533222b9a89a1d599562b8e99673f5457c62d3bd1f00700ae4e75d84de0`.
It contains `_goalpad_aot_load_state_want_vis` at `0x15fc` with:

```text
add x16, x0, x22
add x16, x16, #0x20
str w1, [x16]
eor x0, x0, x0
ret
```

The dedicated M5 simulator build used only destination
`id=96C5C21A-B925-4213-82A3-90DCB8518339`. Build, install, and launch passed;
the runtime log reported the exact `want-vis AOT proof verified` status with
`architecture=arm64; result=8194`, followed by
`First Metal frame submitted`. The settled green screenshot is
`/private/tmp/goalpad-want-vis-m5-sim.png`, SHA-256
`bffe8a0de4fd0c4b06af9d51b90393ffa5da3c57153ed171be29c5e2db9bd2c9`.
The simulator was `Shutdown` before the pass and again after explicit cleanup.
This is simulator evidence only.

The normally signed generic Release command was:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-device -jobs 4 \
  ENABLE_PREVIEWS=NO ENABLE_DEBUG_DYLIB=NO build
```

Compilation and Xcode signing passed. The monolithic main executable SHA-256
is `0f9174ef92687a036af6ea0b6400d9f01d4fedab4532fb261253c8931ff67c94`;
`_goalpad_aot_load_state_want_vis` is at `0x100004034` with the exact five
instructions above. Mach-O `__TEXT` maximum and initial protections are both
`0x5`. Inspection found no app-root dylibs, forbidden dynamic-executable-memory
imports, Preview artifacts, or JIT markers. The entitlements include the
app/team identifiers and `get-task-allow`; the embedded profile SHA-256 is
still `ef4a32f9aef6cca1709423e53e66518204e49a86af4d2752139de63d21244ad1`.
Strict verification reports the expected local `CSSMERR_TP_NOT_TRUSTED`
certificate-trust caveat. This is build, signing, and layout evidence only,
not installability or physical-device execution evidence.

### Checkpoint 12 validation evidence

The updated registry command above compiled and executed with exit `0`. It
requires the complete `want-levels` Export3 body to pass all six guarded
semantic cases.

The combined OpenGOAL runtime worktree at commit `71fc6918` was built with
Release Ninja and `-j 4`. Its focused branch-matrix test passed 1/1,
`Arm64GoalCallAbi` passed 5/5, `Jak1DataArena` passed 4/4, the paired-artifact
CTest passed 1/1, the ARM64 emitter/AOT filter passed 99/99, and full CTest
passed 10/10.

The current ARM64 macOS Debug command is:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/GOALPad-mac -jobs 4 \
  CODE_SIGNING_ALLOWED=NO build
```

It succeeded outside the execution sandbox. The initial sandboxed run failed
only because the Swift Preview macro could not apply its nested
`sandbox-exec` profile. The resulting `GOALPad.debug.dylib` SHA-256 is
`b4a2b583a9ab52af9ffc591de3fe3e4d8955d947f094a2da6fdb58a30f8a315d`;
`_goalpad_aot_load_state_want_levels` is at `0x15fc`.

The exact M5 simulator build used:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug \
  -destination 'id=96C5C21A-B925-4213-82A3-90DCB8518339' \
  -derivedDataPath /private/tmp/GOALPad-sim -jobs 4 build
```

Build, boot, install, and launch succeeded only on that named simulator.
Launch returned PID `15755`. The green UI reported the complete
`want-levels AOT proof verified`, `Architecture: arm64`, and
`AOT result: 8,194`. Screenshot
`/private/tmp/GOALPad-want-levels-M5.png` has SHA-256
`17348c1dab472dc1012029daa708b5696ec378a4b1f3282ab18e99246aab2646`.
Explicit shutdown succeeded, and the M5 was confirmed `Shutdown`. No Freemote
simulator was accessed. This is simulator evidence only.

The normally signed generic Release command is:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-device -jobs 4 \
  ENABLE_PREVIEWS=NO ENABLE_DEBUG_DYLIB=NO build
```

Compilation and Xcode signing passed. The monolithic ARM64 main executable
SHA-256 is
`1e7fb1f902794bf0104516974ce84b6fceaa2aff7c71a12df977927693116bee`.
It contains `_goalpad_aot_load_state_want_levels` at `0x100004034`; its 142
instructions occupy 568 bytes and have raw SHA-256
`a4a511c21f024e5e5fc3c9dc0c03513b7aab3415604521258559361231b8e6ea`.
`__TEXT` maximum and initial protections are `0x5` (read/execute), data
segments are non-executable, and there are no app-root dylibs. Undefined-
import and string scans found no `dlopen`, `dlsym`, `mmap`, `mprotect`,
`pthread_jit`, Preview, or JIT marker.

`codesign -d --entitlements -` reports the app/team identifiers and
`get-task-allow`, with no JIT entitlement. The embedded profile SHA-256 remains
`ef4a32f9aef6cca1709423e53e66518204e49a86af4d2752139de63d21244ad1`.
Strict verification still reports the known local
`CSSMERR_TP_NOT_TRUSTED` caveat. This is static build, signing, and layout
evidence only, not trust, installability, or physical-device execution.

### Checkpoint 13 validation evidence

The complete real Jak 1 `load-state::reset!` body is preserved as three
ordered OpenGOAL patches while the official submodule remains clean at
`a4cb1ac1f0596c8740b1c26accb24a58505cda92`:

| Patch | Child commit | SHA-256 | Stable patch ID |
| --- | --- | --- | --- |
| `0034-feat-arm64-compile-Jak-1-load-state-reset-body-AI-as.patch` | `e96cedd236512ca629455e3e2bab97ae28e410a1` | `fd7dccae28bd9b6ef44213dc61a1fff1f780598f31481d5edee9a7e59a3860fb` | `a5c7198d70c35be5695a5ac288b7b6cc2bb3404b` |
| `0035-feat-aot-export-direct-Jak-1-load-state-reset-AI-ass.patch` | `2229c13ea7f1563327e03e29951425f8ce345185` | `a8eb87d556812780b1abaf9a205e297ddd4e507bbdcfafa847c988e9233117f3` | `b850708e2df5c0c4486e49b093fd155e3bd4deb1` |
| `0036-test-arm64-execute-Jak-1-load-state-reset-body-AI-as.patch` | `bb4b2e7e8705f55e8629da10cad9fb25d10e6cba` | `58b3a5f1ad13d691bbed9ca310e6275faaf4a6a5e6d822585915ab15ccf40ab8` | `47ef21e55cd67d023bf7c17c4143b4bb57967064` |

Their literal child sequence is:

```text
71fc6918 -> e96cedd2 -> 2229c13e -> bb4b2e7e
```

The compiler artifact is an exact 50-IR match for the source body at
`goal_src/jak1/engine/level/load-boundary.gc:1027-1040`. It emits 58 ARM64
instructions (232 bytes), and the guarded metadata maps only:

```text
reset! -> goalpad_aot_load_state_reset
```

The combined OpenGOAL worktree is
`/private/tmp/GOALPadOpenGOAL-arm64-load-state-reset-runtime`, branch
`goalpad/arm64-load-state-reset-runtime`, at `bb4b2e7e`. Its Release build tree
is `/private/tmp/GOALPadOpenGOAL-arm64-load-state-reset-runtime-build`.
Memory-heavy builds were serialized with `-j 4`. The verified results were:

```text
Arm64GoalCallAbi:             6/6 passed
Jak1DataArena:                4/4 passed
goalc-aot-artifact-pair:      1/1 passed
compiler/emitter selection: 186/186 passed
full CTest:                  11/11 passed
```

The first direct `goalc-test` command failed before tests because its
executable path did not contain the required `jak-project` component. Temporary
no-copy aliases
`/private/tmp/load-state-reset-jak-project` and
`/private/tmp/load-state-reset-jak-project-build` resolved that path
requirement. A disposable export-child build also exposed an incomplete
generated cubeb archive; after confirming that no active process owned it, a
clean rebuild of that disposable output passed. Neither was a source-test
failure. The runtime implementation's first commands were interrupted by a
short tool yield; the same work completed in a persistent terminal.

The checked-in artifact and app integration are parent commits:

```text
d843e17 feat(aot): add generated Jak 1 load-state reset artifact (AI-assisted)
cabb027 feat(aot): integrate direct Jak 1 load-state reset proof (AI-assisted)
```

The parent native registry harness command above compiled and ran with exit
`0`. The ARM64 macOS build was:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/GOALPad-mac -jobs 4 \
  CODE_SIGNING_ALLOWED=NO build
```

It succeeded. The resulting `GOALPad.debug.dylib` SHA-256 is
`b39e999f78d75a755490f6ca87eac26beb3f86207c321cbf3d33eeccd3ecf42d`;
`_goalpad_aot_load_state_reset` is at `0x15e8` and contains the exact 58
instructions.

Only the approved local iPad Pro 11-inch (M5) simulator UDID
`96C5C21A-B925-4213-82A3-90DCB8518339` was used:

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
xcrun simctl shutdown 96C5C21A-B925-4213-82A3-90DCB8518339
```

Build, boot, install, and launch passed. The launch PID was `1794`; the log and
green UI reported the direct load-state reset AOT proof, `Architecture: arm64`,
and `AOT result: 8,194`. Screenshot
`/private/tmp/GOALPad-load-state-reset-M5.png` is 1668 by 2420 pixels with
SHA-256
`353dd362039be3486a65c49006800f9bc8fbc9ce687009598b10884a43af7d9f`.
The simulator was confirmed `Shutdown` afterward.

The generic normally signed Release build used the command documented above
and succeeded. The current monolithic ARM64 binary is
`/private/tmp/GOALPad-device/Build/Products/Release-iphoneos/GOALPad.app/GOALPad`.
Its SHA-256 is
`aae97872933a7ba266ad8041e77c076e6769a26e85cb3fc3535e121d9f117c6b`.
The reset symbol is at `0x100004020`; exactly 232 bytes have SHA-256
`2f0171fc455619ad95eb20ef2686b4a8db1642cd94a727e22121051420ab4edd`.
`__TEXT` maximum and initial protections are `0x5` (read/execute), while
`__DATA_CONST` and `__DATA` are `0x3` (read/write), with no execute
permission. Inspection found no app-root dylibs and no `dlopen`, `dlsym`,
`mmap`, `mprotect`, `pthread_jit`, Preview, or JIT import/string marker.

The exact static-inspection commands were:

```sh
app=/private/tmp/GOALPad-device/Build/Products/Release-iphoneos/GOALPad.app
binary="$app/GOALPad"
profile="$app/embedded.mobileprovision"

file "$binary"
xcrun lipo -archs "$binary"
shasum -a 256 "$binary" "$profile"
xcrun nm -nm "$binary" |
  rg 'goalpad_aot_load_state_reset|goalpad_probe_call_aot1_with_state'
xcrun otool -l "$binary"
xcrun otool -L "$binary"
find "$app" -maxdepth 1 -type f -name '*.dylib'
xcrun nm -u "$binary" |
  rg -i '(^|_)(dlopen|dlsym|mmap|mprotect|pthread_jit)'
strings -a "$binary" |
  rg -i 'pthread_jit|mprotect|mmap|dlopen|dlsym|preview|jit'

symbol_address=$(xcrun nm -nm "$binary" |
  awk '$NF == "_goalpad_aot_load_state_reset" { print "0x" $1; exit }')
read -r text_address text_offset <<< "$(
  xcrun otool -l "$binary" |
    awk '
      $1 == "sectname" { section = $2 }
      $1 == "segname" { segment = $2 }
      $1 == "addr" && section == "__text" && segment == "__TEXT" { address = $2 }
      $1 == "offset" && section == "__text" && segment == "__TEXT" {
        print address, $2
        exit
      }'
)"
body_offset=$((text_offset + symbol_address - text_address))
dd if="$binary" bs=1 skip="$body_offset" count=232 2>/dev/null |
  shasum -a 256

codesign -d --entitlements - "$app"
openssl smime -inform der -verify -noverify -in "$profile" 2>/dev/null |
  plutil -extract Entitlements xml1 -o - - |
  plutil -p -
codesign --verify --deep --strict --verbose=4 "$app"
```

The empty `find`, undefined-import, and string scans are required results. An
unexpected match is a failure; do not hide it with a shell fallback.

The app entitlements contain only the expected application identifier, team
identifier, and `get-task-allow = true`; this is Apple Development signing,
not distribution evidence. The decoded local provisioning profile has the
same identifiers, expires at `2026-08-06T23:51:59Z`, and has no JIT or
unsigned-executable-memory entitlement.
The profile SHA-256 remains
`ef4a32f9aef6cca1709423e53e66518204e49a86af4d2752139de63d21244ad1`.
Strict verification exits `1` with the known local
`CSSMERR_TP_NOT_TRUSTED` certificate-trust caveat. Xcode's build/signing step
itself succeeded. This is static build, signature, and layout evidence, not
physical-device installation or execution.

A first sandboxed `security cms -D` inspection returned `cert import failed`
and `problem decoding`; the identical read-only decode outside the sandbox
succeeded. The local non-network OpenSSL CMS command above also succeeded in
the restricted environment. Use
`codesign -d --entitlements -`, not the deprecated `:-` output-path spelling,
with the current local toolchain.

No physical device, **Z iPad Pro**, Freemote simulator, remote, proprietary
game data, or push was accessed for this checkpoint.

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

## Checkpoint 14: signed `*load-state*` value-cell proof

Checkpoint 14 adds the checked-in, compiler-produced
`OpenGOALJak1LoadStateValue.s` artifact. It uses one writable, signed-image
`int32_t` displacement cell and signed static ARM64 text to read the low 32
bits of a symbol value cell. The host and app tests use caller-owned synthetic
symbol arenas; they do not resolve a live OpenGOAL symbol, execute a top-level
definition, install a method, relocate code, load Jak data, or boot the game.

The downstream OpenGOAL child is
`0327eee4886f7a076d3b01f8e62afc3adddb8eeb`, preserved as patch 0037. The
official submodule remains at its fetchable pin. The exact patch SHA-256 is
`b45b36e77252b7cb31f000b497f7339c27bbfb7549d8bbe375a4e7cab5783226` and its
stable patch ID is `e23e6a2dfefbfc5d7907264ee897b9a2416faa52`.

Use the registry harness to validate the current artifact set:

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

The current parent harness exited `0`. The OpenGOAL child test suite passed
12/12. A sandboxed ARM64 macOS build attempt failed because of the environment;
the same build outside that sandbox succeeded in 5.501 seconds. Its
`GOALPad.debug.dylib` SHA-256 is
`a0b8b31e8dd19f84951acd4ae50f025eb6b1b520139457f5d058af483b195b57`.

The approved local iPad Pro 11-inch (M5) simulator Debug build completed in
2.225 seconds, launched PID `32186`, and logged:

```text
GOALPad runtime probe: Signed ARM64 Jak 1 false-func, true-func, identity, lognot, and direct level-group-load-commands-set!, want-vis, want-levels, and load-state reset body plus load-state symbol-value AOT proof verified; architecture=arm64; result=8194
```

The captured UI was
`/private/tmp/GOALPad-load-state-value-M5.png` (1668 by 2420 pixels,
SHA-256 `5e8b29ac11a4ee212f4ea144ce1b0f1aa69d1f242ba933e18f3c07440eca6139`).
The simulator was then confirmed `Shutdown`. This remains simulator evidence,
not physical-device evidence.

The normally signed generic iOS Release build completed in 2.929 seconds. Its
monolithic ARM64 executable SHA-256 is
`606b7698c53bb034fee2ce3c2c860a4a8e3ba64e4186a239f4400277863dd64f`.
`_goalpad_aot_load_state_value` is at `0x100004108`; the signed data cell is
at `0x100014960`. Mach-O inspection reports `__TEXT` read/execute (`0x5`) and
`__DATA` read/write (`0x3`). Strict code-signature verification passed. The
embedded profile SHA-256 is
`ef4a32f9aef6cca1709423e53e66518204e49a86af4d2752139de63d21244ad1`, with
expiry `2026-08-06T23:51:59Z`. Undefined-import, app-root-dylib, and string
scans had no JIT or dynamic-library loading hits.

Memory pressure was checked at 67% free before this validation sequence and
64% free afterward. No physical device, **Z iPad Pro**, other simulator,
remote, or retail game data was accessed for Checkpoint 14. Parent checkpoint
`8e3b4ac` was pushed to `origin/feat/ipados-native-boot`. The next
implementation task is to prove a read-only existing-symbol value-cell resolver
with synthetic fixtures. Production callers may invoke it only after real
link/top-level initialization has created symbol metadata; only then consider
guarded method binding and dispatch.
