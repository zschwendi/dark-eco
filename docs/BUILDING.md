# Building GOALPad

## Requirements

- Apple silicon Mac
- Xcode 26.6 or a compatible toolchain with the iOS 26.5 SDK
- CMake, Ninja, and OpenSSL 3 for the OpenGOAL host baseline

```sh
brew install cmake ninja go-task openssl@3
```

## Build-cache discipline

Use `OpenGOAL/build/Release/bin` as the single canonical host CMake build and
`/private/tmp/GOALPad-sim` as the current Xcode DerivedData directory. Run only
one heavy C++, AOT, Metal, or Xcode build at a time; agents can inspect, edit,
and review independently while that build owns the machine.

Name isolated proof configurations `/private/tmp/GOALPad-<proof>` and remove
them after their results are recorded and they are confirmed not to be source
worktrees. Do not create a second full host or Xcode cache for a focused test.

`ccache` is an optional local accelerator, not a product dependency. When it is
installed, new host worktrees can use the opt-in
`Release-macos-arm64-clang-ccache` preset; the normal preset remains portable to
machines without it. Do not reconfigure an active canonical build merely to
enable the launcher, because that invalidates the existing compilation commands
and can trigger the duplicate rebuild this rule is intended to avoid.
Sandboxed local agents must use one writable shared cache rather than a cache
per worktree. The current machine keeps that bounded cache at
`/private/tmp/GOALPad-ccache`; `ccache --show-config` must still report the
512 MiB limit before it is used.

### Checkpoint execution lanes

Use one Sol `xhigh` integration lane, up to two non-overlapping Sol `xhigh`
implementation lanes for importer architecture, renderer bugs, ABI/AOT, and
unsafe file handling, and one Terra `medium` or `high` mechanical lane for
CMake, docs, fixtures, build-log triage, formatting, and API plumbing. Each
worker runs focused checks only; run medium checks after integrating a subsystem,
then run the compiler, Metal, AOT, and Xcode matrix once per checkpoint.

Do not parallelize heavy builds. Generate the 518-object source pack once and
subsequently verify its recorded identity unless its writer or embedded graph
changes. At a physical visual A/B gate, stop speculative renderer work unless a
deterministic hypothesis and test can distinguish the next change.

### Raw-ISO importer Xcode products

**Implemented — build plumbing and target wiring.** The permanent Xcode target
builds the flattened Apple importer archive from an existing verified
518-object source pack without generating another pack:

```sh
Scripts/build-jak1-import-composer-apple.sh \
  --opengoal-root "$PWD/OpenGOAL" \
  --source-pack "$GOALPAD_JAK1_SOURCE_OBJECT_PACK_ROOT" \
  --derived-root "$GOALPAD_JAK1_IMPORT_BUILD_ROOT" \
  --platform "$PLATFORM_NAME"
```

The deterministic outputs are:

```text
<derived-root>/<platform>/jak1-import-composer-apple/libjak1-import-composer-apple.a
<derived-root>/macosx/jak1-source-object-pack-verify             # macosx
<derived-root>/macosx-host/jak1-source-object-pack-verify        # iOS/simulator
```

The build fails before the cross-platform archive build if the existing source
pack does not match the recorded 518-object identity. The supported archive
platforms are `macosx`, `iphoneos`, `iphonesimulator`, `xros`, and
`xrsimulator`, all ARM64. VisionOS uses CMake's `visionOS` system name and a
static try-compile with the matching SDK. Its compile/link proof passes, but raw
ISO import has not run on Vision Pro hardware or the visionOS simulator; target
wiring may enable the compiled importer macro without treating that as runtime
evidence. Ccache is used for the cross-platform composer when available,
defaults to a bounded cache below the derived root, and is not required. The
small macOS source-pack verifier deliberately bypasses ccache because Apple
clang's deployment-target environment affects its object platform without
appearing in the compile command hash.

Archive production and resource staging are separate because the archive must
exist before Xcode links while the final resource directory must already exist
before publication. A later resource phase invokes:

```sh
Scripts/stage-jak1-import-composer-resources.sh \
  --opengoal-root "$PWD/OpenGOAL" \
  --source-pack "$GOALPAD_JAK1_SOURCE_OBJECT_PACK_ROOT" \
  --derived-root "$GOALPAD_JAK1_IMPORT_BUILD_ROOT" \
  --platform "$PLATFORM_NAME" \
  --resources-destination "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
```

Both phases keep retail data and generated source-object packs outside the
repository. The resource phase reuses the atomic checked stager and revalidates
both its source and published copy.

The target wiring consumes these build settings without adding a machine path
to the project file:

```text
GOALPAD_OPENGOAL_ROOT = $(SRCROOT)/OpenGOAL
GOALPAD_JAK1_IMPORT_BUILD_ROOT = $(DERIVED_FILE_DIR)/Jak1ImportComposer
GOALPAD_JAK1_IMPORT_ARCHIVE = $(GOALPAD_JAK1_IMPORT_BUILD_ROOT)/$(PLATFORM_NAME)/jak1-import-composer-apple/libjak1-import-composer-apple.a
GOALPAD_JAK1_SOURCE_OBJECT_PACK_ROOT = $(SRCROOT)/build/jak1-source-object-pack
OTHER_LDFLAGS = $(inherited) "$(GOALPAD_JAK1_IMPORT_ARCHIVE)"
```

On a clean checkout, create the ignored public source pack at that Release
default before the first Release build:

```sh
Scripts/prepare-jak1-source-object-pack.sh
```

The command uses the pinned OpenGOAL source graph and canonical host build
directory, publishes `build/jak1-source-object-pack` only when it is absent,
and always runs the verifier that requires the recorded 518-object identity.
Running it again reuses and revalidates the existing pack; it never replaces a
corrupt or divergent directory. To use a separately managed pack, set
`GOALPAD_JAK1_SOURCE_OBJECT_PACK_ROOT` to an absolute path whose parent already
exists for both this command and the Xcode build. Historical checkpoint commands
that name a `/private/tmp` pack are recorded local evidence, not a Release
requirement.

Debug remains the prepared-folder-only fallback: the composer macro is `0`, no
importer archive is added to the link, and both importer phases exit without
touching their derived outputs. Release is deliberately ARM64-only and enables
the composer for `macosx`, `iphoneos`, `iphonesimulator`, `xros`, and
`xrsimulator`; this matches the native ARM64 port and the thin archive contract.
The checked xcconfigs inherit the target's existing inline settings. Both
importer configurations disable only Xcode's build-script sandbox. The custom
Metal phase creates transitive module-cache files below the derived sources
directory, and Release also needs CMake access to recursively discovered files
below the pinned `OpenGOAL` source tree and external source-object pack. This
does not disable the built app's runtime sandbox or change its entitlements.

Set `GOALPAD_JAK1_IMPORT_DEPLOYMENT_TARGET` from
`MACOSX_DEPLOYMENT_TARGET` for macOS and `IPHONEOS_DEPLOYMENT_TARGET` for
iPhoneOS and its simulator, or `XROS_DEPLOYMENT_TARGET` for visionOS and its
simulator. Put the archive script before compilation/linking and the resource
script after Copy Bundle Resources. Declare the script, `OpenGOAL` source
directory, and external source pack directory as inputs; declare the derived
importer build root and flattened archive as outputs. These declarations retain
dependency ordering even though Release must disable the build-script sandbox
for CMake's recursive source discovery. The later phase additionally reads both
stager scripts and writes
`OpenGOALProjectResources` and `Jak1SourceObjectPack` below the target's
unlocalized resource directory. Let both phases run each build; their CMake and
atomic staging operations are incremental and revalidate mutable external input.

## Initialize OpenGOAL

```sh
git submodule sync -- OpenGOAL
git submodule update --init --recursive
```

The authoritative child is the dedicated public fork
`https://github.com/zschwendi/jak-pad.git`, branch
`goalpad/ipad-demo-pacing`, pinned by the parent gitlink at
`db376b727c52ffeb19788df4ac453693a07c40c8`. Checkpoint 59 retains this pin and
incorporates the checked `jak1-base-retail` importer, source-pack verification,
Apple composer, Jak 1 renderer diagnostics, and the reviewed Jak II sound and
DGO RPC seams, including the bounded host `TITLE.DGO` play-frontier proof.
Do not substitute a different OpenGOAL checkout when recording validation
results, and pin that exact commit rather than a branch tip. The `sync` step
updates existing clones that still remember the former upstream URL.

The pin includes the portable `jak1-kernel-core`, Metal renderer,
display-time seam, and Jak 1 MIPS2C joint correction without replacing those
OpenGOAL systems.
`game/kernel/core/gfx_host.{cpp,h}` answers the machine layer's graphics
functions through plain C function pointers a host installs, and
`game/goalpad_play.cpp` is the desktop host that fills them in with the Metal
renderer and an SDL window. The iPad equivalent is
`GOALPad/Native/GOALPadMetalHost.mm`; see "The Metal renderer in the app" below.

## Generate Jak 1's ahead-of-time GOAL code

The app compiles Jak 1's own GOAL code. That code is compiled to C on this Mac
by goalc's AOT C backend and then compiled for `arm64-apple-ios` by Xcode like
any other source, so the game's code arrives in the app's ordinary signed
`__TEXT`; nothing is generated on the iPad.

```sh
Scripts/generate-jak1-aot.sh
```

Run it once after cloning and again whenever the submodule pin moves. It builds
the host `goalc-cbackend-sweep` and writes 1,039 files: one `.c` and one
`_generated.h` for each of Jak 1's 518 object files, both AOT manifest files,
and `coverage.tsv`. The directory is about 85 MB and generation takes a few
seconds once the host tool is built.

The output is never committed. `Generated/jak1-aot/` itself is, because the app
target picks the directory up as an Xcode synchronized folder and Xcode needs it
to exist; everything in it except `README.md` is ignored by Git.

A build without it still succeeds and still brings the kernel up. It reports
`Jak 1 GOAL code: not in this build` on screen and refuses to start a session,
rather than pretending to boot - see `GOALPAD_HAVE_GAME_BOOT` in
`GOALPad/Native/GOALPadEngineSeams.h`. That shell is a development convenience,
not a distributable product. GitHub, TestFlight, and App Store archives must
fail before Xcode builds when this generated output is absent or incomplete.

For the current pinned Jak 1 source, the release preflight is:

```sh
Scripts/verify-generated-aot.sh Generated/jak1-aot 518
```

The 519 C files are 518 generated object translations plus the manifest. A pin
that deliberately changes the supported build graph may change these numbers,
but updating the expected count must be an explicit reviewed release change.
The verifier also requires a coverage report with no source-file or function
failures and proves that emitted plus native functions equals the total. The
Xcode target runs it automatically for every Release build, so release
automation cannot silently publish the buildable shell. The sandboxed Xcode
phase reads the manifest and coverage report explicitly; the following source
compile and final link prove that every manifest entry is present.

At the current pin, generate the pack once on canonical code. Subsequent checks
must use the existing-pack verifier and require 518 objects, aggregate identity
`51d2b85ff1b53223`, and `10,756,270` object bytes. A caller-supplied wrong
expected identity must fail. Regenerate only when the source-pack writer or its
embedded graph changes; otherwise regeneration wastes the checkpoint's heavy
build budget without adding evidence.

Jak II's corresponding generated corpus is prepared separately:

```sh
Scripts/generate-jak2-aot.sh
Scripts/verify-generated-aot.sh Generated/jak2-aot 840
```

That output contains 841 C files: 840 object translations plus its manifest.
It is intentionally excluded from the Jak 1 app because the two games export
overlapping AOT symbols. Use the documented Jak II iPhoneOS link-check target
rather than adding both generated directories to one product.

The Jak II iPhoneOS final-link proof is a separate unsigned build product:

```sh
cmake -S OpenGOAL -B /private/tmp/GOALPad-jak2-ios-aot -G Ninja \
  -DOPENGOAL_BUILD_JAK2_IPHONEOS_AOT_LINK_ONLY=ON \
  -DOPENGOAL_JAK2_AOT_DIR="$PWD/Generated/jak2-aot" \
  -DBUILD_TESTING=OFF \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 \
  -DCMAKE_BUILD_TYPE=Release
cmake --build /private/tmp/GOALPad-jak2-ios-aot -j 4 \
  --target jak2-iphoneos-full-aot-link
```

This compiles the manifest and all 840 Jak II translations with
`-fno-strict-aliasing`, validates that the corpus exactly matches the manifest,
and final-links only `jak2-kernel-core`. It proves iPhoneOS compilation and
symbol resolution; it is not a signed app, launch, title-screen, or gameplay
claim.

The current separate ARM64 headless probe registers all 840 Jak II AOT units,
loads KERNEL 8/8 and GAME 465/465 from explicit user data, and runs 100 kernel
dispatcher frames. The corpus contains 18,479 emitted functions plus 7 shared
native routines with no coverage failures. This host result and the thin
iPhoneOS final-link product do not wire Jak II into Dark Eco, initialize its
renderer or audio on an Apple device, or establish signing, simulator, physical
device, title-screen, or gameplay support.

Two target build settings are not optional:

- `GCC_STRICT_ALIASING = NO`. GOAL reads and writes the same memory at several
  widths, exactly as the x86-64 backend does, so the generated C must not be
  optimized under strict aliasing rules. It is set for the whole target rather
  than per file because the file list is generated: a static per-file list would
  silently stop covering whatever the sweep emits next.
- `GCC_OPTIMIZATION_LEVEL = s` in **both** configurations. GOAL's cooperative
  threads copy their stacks in and out of backup buffers sized by
  `process-stack-save-size` in `kernel/gkernel-h.gc`, and those sizes are for
  optimized code generation. Unoptimized, the generated C's frames are large
  enough to overflow them: a Debug build at `-O0` reached the title level and
  then stopped at the loud guard in `goal_native_kernel.cpp` with
  `the cpu-thread 'code' ... used 1424 bytes of stack but its backup buffer is
  only 1280`. Swift is unaffected - `SWIFT_OPTIMIZATION_LEVEL` is still `-Onone`
  in Debug - so the app shell stays debuggable.

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

The macOS command builds the native Apple Silicon Dark Eco launcher. A Release
validation has exercised its library, prepared-data import, shared Metal host,
real Jak 1 AOT boot, and title screen. A controller is still required for
gameplay because the launcher does not yet map keyboard input, and a complete
macOS gameplay pass remains unvalidated. The generic iOS commands validate
compilation and linking only; a generic iOS build is not physical-device
validation. The generic simulator invocation is documented below as an
expected architecture mismatch, not a required passing build.

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

It produced a monolithic thin ARM64 executable with no `GOALPad.debug.dylib`
or `__preview.dylib`. Those two build settings are no longer required to get
that layout; the plain command below produces the same bundle.

The kernel-core checkpoint reran this as:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-device -jobs 4 \
  -allowProvisioningUpdates build
```

The kernel-core checkpoint's executable was thin `arm64`, SHA-256
`444513aa4fb82fc5e1d5b3ca6183539ee37d8cb3fbf148d32bf3f8a7598db134`. After the
app-shell change it is SHA-256
`a3797df3f7aa17204eb5c4b5d9834ab6f08f0505c3d6fa355483a3c3a487ab8b`.

**With Jak 1's own GOAL code in it** the executable is thin `arm64`, SHA-256
`529c07d4348e0d2807ba5ae6dd9fd1a63113d7a590f20ac276516912baa5ea06`, and
**25775776 bytes** - a 25 MB bundle, with no `GOALPad.debug.dylib`, no
`__preview.dylib`, and nothing else in the app root. That is the whole game's
code: `__TEXT` is 10715136 bytes, `__DATA_CONST` 5586944, `__DATA` 1343488, and
`__LINKEDIT` 9453568. For scale, the host's own `jak1-data-boot-test`, which
links the same generated C at `-O3`, is 22948976 bytes.

`codesign --verify --deep --strict` reports `valid on disk` and `satisfies its
Designated Requirement`; the authority is `Apple Development:
zschwendi@zephyrstudios.dev (BZ68MJN5R5)`, team `D2YYJ54Q6V`. Entitlements are
the application identifier, team identifier, and `get-task-allow = true`. There
is no JIT, unsigned-executable-memory, or other private entitlement, and no
app-root dynamic library.

**There is no writable-executable segment.** Every segment's `initprot` and
`maxprot` are the same and neither ever pairs write with execute:

| segment | initprot | maxprot |
| --- | --- | --- |
| `__PAGEZERO` | `0x0` | `0x0` |
| `__TEXT` | `0x5` (r-x) | `0x5` |
| `__DATA_CONST` | `0x3` (rw-) | `0x3` |
| `__DATA` | `0x3` (rw-) | `0x3` |
| `__LINKEDIT` | `0x1` (r--) | `0x1` |

Jak 1's GOAL code is in `__TEXT`, read-only and signed, like the rest of the
app.

**The binary does import `mmap` and `mprotect`.** Earlier checkpoints recorded
their absence; that is no longer true and is not a regression. The kernel maps
EE main memory read/write and traps its low 512 kB, so those imports are
expected. It never requests `PROT_EXEC`: a compile-time assertion enforces the
RW-only mapping policy, and `goal_kernel_core_state::main_memory_executable`
always reports false. There is no `dlopen`, `pthread_jit_write_protect_np`,
Preview, or JIT marker.

**The app-shell build also imports `dlsym`.** The kernel-core build did not; a
Release build of the immediately preceding tree was checked and has only `mmap`
and `mprotect`. No GOALPad object file references `dlsym` — every `.o` in the
link was scanned — so it arrives with the Apple runtime support the shell's new
frameworks pull in (AVFAudio, GameController, Core Haptics, Swift
`Synchronization`). It is a symbol lookup in already-loaded images, not code
generation, and there is still no `dlopen` to load anything new.

This is an Apple Development signature, not distribution or App Store evidence.
No physical-device installation or execution was performed for this checkpoint;
treat the Release output as static build/signing evidence only.

## Jak 1 running in the app

**Implemented.** The app boots the game and runs its frames. What it does not
have is the renderer: the picture is still the presentation surface's
placeholder.

`GOALPadGameBoot` boots the game the way the game boots, off the main thread,
in the order `jak1::InitHeapAndSymbol` and `jak1::InitMachineScheme` run:

1. register the 518 ahead-of-time translation units by DGO object name,
2. `KERNEL.CGO` - the GOAL kernel,
3. `InitListener`, the machine-layer stubs, the pad seam, the DGO and STR RPCs,
   the DMA chain measurement, and 989snd on the sound RPC,
4. `GAME.CGO` - the engine and the game,
5. record `engine`, `art` and `common` in `*kernel-packages*`, which is what the
   C kernel does for a release build's merged `GAME.CGO`,
6. the engine's own `play`, which allocates the level heaps and drives the title
   level's load through GOAL's own loader.

`GameSession.tick`, on the display link, then does one frame: arm the surface,
push the controller, run `kernel-dispatcher` and `goal_sound_frame`, present,
then read the vibration request back. It also forwards the display link's target
presentation time to the native runtime so GOAL consumes display cadence at its
normal `display-frame-start` boundary. That is `KernelCheckAndDispatch`'s loop
body without the listener half.

### The app's own machine layer

`game/kernel/core/` deliberately has no machine layer:
`goal_kernel_core_stub_machine_layer` puts a stub in each of its 117 symbols
that names itself once and returns 0. The app supplies the file half itself,
copied from `game/kernel/{common,jak1}/kmachine.cpp` for the same reason
`pad.cpp` copies `CPadOpen` - those translation units are the desktop machine
layer and are not in the library. `file-stream-open`, `-close`, `-length`,
`-seek`, `-read` and `-write` go through `ee::sceOpen` and friends, which
resolve every name under the configured data directory, and
`pc-filepath-exists?` answers with a real `stat`.

A stub is not good enough for either. GOAL's `#f` is `s7`, not 0, so a stub
answers "yes" to every predicate: the PC settings loader believed
`pc-filepath-exists?` and opened a settings file that is not there.
`(method new file-stream)` returns whatever `file-stream-open` returns, so the
stub handed GOAL a null stream and the next field read faulted in the guard
page. Upstream always returns the stream and records the failure inside it,
which is what lets `pc-settings` say "not found ... initializing with defaults"
instead of crashing.

Everything else in the machine layer is still a stub and still says so:
`scf-get-*`, `pc-get-os`, `pc-rand`, `reset-graph` and the rest of the display
functions. A frame's simulation is real; what it would have shown is not.

## The real Jak 1 kernel in the app

**Implemented.** The app target compiles the `jak1-kernel-core` source set
directly out of the `OpenGOAL/` submodule. There is no prebuilt archive, no
generated framework, and no absolute path in the project file: the Xcode group
`OpenGOAL Jak 1 Kernel Core` is rooted at `$(SRCROOT)/OpenGOAL` and its member
list mirrors `JAK1_KERNEL_CORE_SOURCES` in
`OpenGOAL/game/kernel/core/kernel_core.cmake`. Keep the two lists in step when
either changes; it is 86 files today, including the four overlord sound tables,
989snd, the Jak 1 mips2c function library, and the ARM64 GOAL thread routines.
`OpenGOAL/` sits outside the `GOALPad/` `PBXFileSystemSynchronizedRootGroup`, so
those files are listed explicitly; everything under `GOALPad/` and
`Generated/jak1-aot/` is still picked up automatically.

The target adds `FMT_HEADER_ONLY=1`, `GOALPAD_SND_NO_CUBEB=1` - 989snd's own
output backend needs a desktop audio device, and `goal_sound_pull_audio` is the
seam instead - and five header search paths (`OpenGOAL`,
`OpenGOAL/third-party`, `OpenGOAL/third-party/fmt/include`,
`OpenGOAL/third-party/SDL/include`, `Generated/jak1-aot`). The SDL path only
satisfies a declaration include reached through
`game/kernel/common/kmachine.h`; no SDL code is compiled and no SDL library is
linked.

`GOALPadRuntimeCore.{hpp,cpp}` wraps the C entry point in
`OpenGOAL/game/kernel/core/kernel_core.h`. `GOALPadRuntimeBridge.{h,mm}`
exposes `startKernelWithDataDirectory:` and `stopKernel` to Swift, plus a
read-only status object. Startup is all-or-nothing: any failure, including a
fundamental type that cannot be read back out of the heap, tears the session
down before returning, and no C++ exception can reach Objective-C.

On launch the app maps 128 MiB of EE main memory, initializes the global and
debug kernel heaps, and runs `jak1::InitSymbolAndTypes()`. The on-screen
readout is the live state, not a fixture. Observed on the iPad Pro 11-inch (M5)
simulator and identical to the ARM64 macOS host smoke test: global heap base
`#x0013fd20`, current `#x001c1f2a`, 533002 bytes used; `s7` `#x0018fe04`; 90
hashed symbols; and the bootstrapped `object`, `structure`, `basic`, `symbol`,
`type`, `string`, `function`, and `pair` types read out of the heap.

**Non-executable by policy.** The EE arena contains data, GOAL stacks, and
function objects, so the kernel maps it RW and never probes for `PROT_EXEC`. The
readout therefore reports `EE arena executable: NO`. No native code executes
out of the GOAL heap: a function object holds the 64-bit native entry point of
signed AOT or MIPS2C code in `__TEXT`, and `call_goal` loads it. On Apple hosts,
the AOT execution test also inspects the live VM region before and after real
AOT calls and requires it to remain `rw-`.

Run the host smoke test for the same values outside the app:

```sh
cd OpenGOAL
cmake --preset=Release-macos-arm64-clang
cmake --build build/Release/bin -j 4 --target jak1-kernel-core-smoke-test
./build/Release/bin/game/jak1-kernel-core-smoke-test
```

It is also registered with CTest, so `ctest --output-on-failure` in
`OpenGOAL/build/Release/bin` covers it alongside the rest of the suite.

## The Metal renderer in the app

**Implemented.** The game is drawn by OpenGOAL's Metal renderer, the same source
the Mac plays Jak 1 with. The app boots the game and runs it at the selected
60 Hz target or an adaptive target up to 120 Hz on supported iOS displays.
Deterministic timing, signed builds and simulator launch are validated; physical
adaptive-120 performance remains an explicit acceptance gate.

### Where the two halves meet

The kernel library names no renderer and the renderer names no host. Between
them is `OpenGOAL/game/kernel/core/gfx_host.h`: a table of plain C function
pointers - `send_chain`, `vsync`, `sync_path`, `texture_upload_now`,
`texture_relocate`, `set_levels`, `set_pmode_alp` - that `goal_gfx_host_install`
puts behind `__send-gfx-dma-chain`, `syncv`, `sync-path`,
`__pc-texture-upload-now`, `__pc-texture-relocate`, `__pc-set-levels` and
`put-display-env`, replacing the machine-layer stubs.

`GOALPad/Native/GOALPadMetalHost.mm` fills that table in. It is the iPad's
answer to `OpenGOAL/game/goalpad_play.cpp`, the desktop host, and it owns the
same renderer, texture-pool and level-art responsibilities. Unlike the
asynchronous desktop host, GOALPad does not snapshot the submitted chain with a
`FixedChunkDmaCopier`: it validates the live EE base and aligned root offset,
then consumes the chain synchronously before returning to GOAL.
`GOALPadGameBoot.cpp` starts it and installs the seam where `goalpad_play.cpp`
does - after `goal_kernel_core_stub_machine_layer` and before the first DGO load,
because the game uploads texture pages while GAME.CGO is read and a page that
arrives with no pool behind it is a texture missing for the rest of the session.

`OpenGOAL/game/graphics/pipelines/metal/metal_pipeline.mm` is deliberately not
compiled. That file is the desktop *display*: an SDL window, the SDL event queue
and a frame limiter. Everything below it - `MetalRenderer` and all fifteen bucket
renderers - is compiled unchanged.

### Threading and the TexturePool

**One thread does everything.** `CADisplayLink` calls `GameSession.tick()` on the
main thread; that arms the Metal surface, pushes the controller state, and runs
one `kernel-dispatcher` frame. `__send-gfx-dma-chain` decodes and renders the
live chain synchronously inside that frame, before the dispatcher can rewrite
either its packets or the Merc bone matrices referenced outside it. No chain
pointer survives the call. `__pc-texture-upload-now`,
`__pc-texture-relocate` and `__pc-set-levels` are all called from inside that
GOAL frame, on that thread. Boot is the one thing that runs elsewhere, on its
own queue; chains sent before the first armed display-link tick are discarded
rather than deferred with stale live pointers.

That is the whole locking story, and it is deliberate. `TexturePool` does not
lock internally - its callers are expected to hold `pool.mutex()`, as
`Loader.cpp:341,538,635,698` does - and the desktop host, whose engine runs on
its own thread, hit a real data race between the game thread's
`texture_relocate` and the render thread's level loading. Here there is no second
thread to race with, so nothing is taken and nothing can be forgotten.

Two seam functions change shape because of it:

- `syncv` returns immediately rather than blocking until the renderer presents.
  On the desktop that block is where the game's frame rate comes from; here it
  would wait for the same main thread's next display-link callback.
  `CADisplayLink` is the clock instead, which is what a display-linked
  application should be paced by.
- `sync_path` returns immediately as well, and correctly: `send_chain` copies
  the tagged DMA chunks and renders before it returns. The renderer has consumed
  both that snapshot and the matching live bone matrices, so EE memory is free
  to be reused.

`__pc-set-levels` also loads synchronously, where the game asked, rather than
being deferred to the next frame the way `metal_pipeline.mm` defers it. It has
to: `__pc-texture-relocate` points an uploaded texture page at its real data, and
the pool asserts (`!tex->is_placeholder`, `TexturePool.cpp:72`) when the level
that data lives in is not loaded yet. The desktop gets away with deferring
because its render thread is already running frames while the game boots. The
cost is the same on both: a level load is one very long frame.

Levels are never unloaded - nothing here knows when the last draw referencing a
level's buffers has retired, which is what the GL loader's reference counting is
for - so memory grows with the number of distinct levels a session visits.

### The renderer's sources in the Xcode target

The Xcode group `OpenGOAL Metal Renderer` is rooted at `$(SRCROOT)/OpenGOAL` and
mirrors the `goalpad-metal-gfx` target in `OpenGOAL/game/CMakeLists.txt`, minus
`metal_pipeline.mm` and `common/versions/versions.cpp` (which needs a generated
`revision.h` the app does not build). It is 62 files: the fourteen Metal
`.mm` translation units, `metal_host_seams.cpp` (the three runtime globals the
renderer reads, which live in the desktop `runtime` library upstream),
`metal_kernel_bridge.cpp`, `metal_texture_upload_handler.cpp`, the texture pool
and converter, the tpage directories, the ocean VU emulators, `dma_helpers.cpp`,
five `common/` translation units, four imgui sources (TexturePool's debug view
calls imgui; no debug UI is created), and zstd's twenty-five C files (`.fr3`
level art is zstd-compressed). `gfx_host.cpp` joins the kernel-core group, which
still mirrors `JAK1_KERNEL_CORE_SOURCES` in `kernel_core.cmake`.

Three build settings changed with it:

- `HEADER_SEARCH_PATHS` gained `OpenGOAL/third-party/glad/include`,
  `OpenGOAL/third-party/zstd/lib`, `OpenGOAL/third-party/zstd/lib/common`, and
  `$(DERIVED_SOURCES_DIR)/goalpad-metal`. glad is headers only - the Metal
  renderers include GL headers through `BucketRenderer.h`, but no GL symbol is
  referenced and no GL library is linked.
- **`GCC_PREPROCESSOR_DEFINITIONS` no longer defines `DEBUG=1`.** Jak 1's bucket
  enums have a member named `DEBUG`
  (`game/graphics/opengl_renderer/buckets.h:74,1066`), so Xcode's default
  `-DDEBUG=1` makes the renderer's own headers unparseable. Nothing in this
  repository reads the `DEBUG` macro. Swift's `DEBUG` condition is
  `SWIFT_ACTIVE_COMPILATION_CONDITIONS` and is unaffected.
- imgui and zstd compile with `-w`; they are third-party C the project's warning
  settings were never meant for.

### Shaders are compiled at build time, never at runtime

The "Compile Metal shaders" build phase runs `Scripts/compile-metal-shaders.sh`
before Compile Sources. It compiles the checked-in `.metal` files with
`xcrun -sdk "$PLATFORM_NAME" metal -Wall -Werror
-fmodules-cache-path=...` into
`$(DERIVED_SOURCES_DIR)/goalpad-metal/goalpad.metallib`, then writes that
metallib out as a C byte array in `goalpad_metallib_embed.h`.
`GOALPad/Native/GOALPadMetallib.c` includes that header, so the compiled GPU
library ends up in the app's own signed data and `MetalRenderer::init` loads it
with `newLibraryWithData:`. This is the Xcode equivalent of the metallib +
`embed_metallib.cmake` step in `game/CMakeLists.txt`. The base and reflective
TIE passes use the same vertex entry point, so their position calculation is
identical without conservative invariant compilation. The module cache lives
beside the generated metallib rather than in a user-global cache.

No shader is compiled on the iPad, for the same reason no GOAL code is: a shader
built at runtime is code the signature does not cover. The signed Release
binary has no `newLibraryWithSource:` reference and the bundle has no
`default.metallib`; the iPhoneOS-SDK metallib is 219,624 bytes and is inside the
executable.

### What was observed on the simulator

iPad Pro 11-inch (M5), `id=96C5C21A-B925-4213-82A3-90DCB8518339`, Debug, with the
player's own `iso/` and `fr3/` in the app container:

- **The Jak 1 title screen renders**: the Jak & Daxter logo, the sky, the ocean
  and Sandover Village, with "PRESS START". The renderer's own readout says
  `renderer: linked`.
- 60 fps, sustained: 600 dispatcher frames every 10.00-10.05 s over eleven
  consecutive ten-second reports, with 599 of every 600 presented.
- Drawable 2420x1668, internal 1280x960 (2x), draw region 2224x1668.
- 2915 DMA chains sent, 2915 drawn, **0 dropped**. The last frame drew 285 draw
  calls and 485,590 triangles.
- Level art: `title+village1` wanted, `title+village1` loaded, 0 failures.
  `GAME.fr3` (common) took 226 ms and gave 346 textures and 27 merc models,
  `title` 46 ms, `village1` 603 ms for 667 textures and 4/3/1 tfrag/tie/shrub
  trees and 50 merc models.
- Audio still produces every frame it is asked for: 48000 Hz, 517632/517632 in
  the first ten seconds.

Screenshots: `/private/tmp/goalpad-ipad-shots/jak1-title-ipad-sim.png` (the title
screen) and `jak1-title-ipad-sim-readout.png` (the same frame with the
diagnostics overlay showing the numbers above). `simctl io screenshot` captures
the unrotated framebuffer, so both were turned 90 degrees with `sips -r 90`.

**Not drawn yet.** The renderer reports each unported bucket once: `l0-tfrag-generic`,
`l1-tfrag-generic`, `l1-shrub-generic` and `common-alpha-generic` (240 bytes of
DMA each), the tfrag-trans content inside the sky-blend buckets (992 bytes), and
sprite distort (9 sprites consumed, not drawn). Those are ports that have not
been done in the fork yet, not iPad problems - the Mac skips exactly the same
buckets.

**Not validated.** No physical device. No controller input past the title screen
was exercised on the simulator, so nothing here says gameplay renders correctly;
the desktop host does play it. Only the landscape drawable was exercised.
Backgrounding and returning with the renderer live was not re-tested after the
renderer was linked.

### Camera and presentation provenance diagnostics

The Checkpoint 35 diagnostic path associates each synchronously submitted DMA
chain with its dispatcher frame, display-link tick, and chain ordinal. It also
fingerprints the exact five qwords that `add-pc-tfrag3-data` copies from
`*math-camera*` into every Jak 1 tfrag, tie, and shrub packet. The renderer
reports both packet-to-live-producer mismatches and disagreements between
packets in the same chain. These counters are diagnostic only; they do not
change camera math, frame cadence, DMA order, or rendering behavior.

The diagnostics overlay and ten-second Session log include:

- the engine frame, display-link tick, and chain ordinal;
- the first background-camera fingerprint and packet count;
- cumulative live-camera and within-chain packet mismatches, with a five-bit
  qword mask for the most recent chain;
- drawable submission and, on device builds, actual presentation identity and
  order.

Current iPhone Simulator SDK headers omit `MTLDrawable`'s presented-handler,
presented-time, and drawable-ID APIs. Simulator builds therefore validate
producer-to-packet association, chain identity, drawable acquisition, and
submission counts, but report zero completed presentations and drawable ID
zero. Generic and physical iPhoneOS builds compile the actual presentation
callback. A signed generic build proves that path compiles and signs; only a
physical run can establish the order in which frames reached the display.

Run the deterministic camera trace test with:

```sh
cmake --build OpenGOAL/build/Release/bin \
  --target metal-camera-trace-test -j 4

ctest --test-dir OpenGOAL/build/Release/bin \
  -R '^metal-camera-trace-test$' --output-on-failure
```

The test covers exact producer/packet equality, qword-level attribution,
packet disagreement, monotonic presentation order, and a deliberately reversed
presentation sequence.

The Checkpoint 35 Release build was subsequently update-installed on physical
**Z iPad Pro** after explicit maintainer authorization. It booted the preserved
user-local Jak 1 data and ran through training gameplay. The maintainer observed
severe camera jitter and intermittent Flat-Stanley deformation, so neither
visual defect is fixed.

The attached console emitted no `Metal camera provenance mismatch` or
`Metal presentation order mismatch` line during the reported failure window.
That is evidence against the two instrumented mismatch predicates firing, not
evidence that the live camera math was correct: producer and packets can agree
on the same oscillating state. The ten-second Swift Session records could not
be recovered because `devicectl --console` does not include them and macOS
requires root to collect an attached device's unified log archive. The next
diagnostic should therefore retain bounded consecutive-frame producer
fingerprints in a recoverable ring rather than depend on unified logging.

Checkpoint 36 implements that recoverable diagnostic. The app atomically
replaces and refreshes one numeric-only record at:

```text
Library/Caches/GOALPadDiagnostics/camera-provenance-v1.log
```

It writes at session start, every 600 frames, immediately on a new camera
return or Merc omission, on inactive/background transitions, and before kernel
shutdown. A random numeric run ID distinguishes launches. The file contains no
path, device identifier, raw game data, or raw camera matrix. It is a purgeable
cache, so copy it before relaunching or depending on it as long-term storage.

The consecutive producer detector consumes the exact four `camera-temp` qwords
and `trans` qword copied into Jak 1 background packets. It records an `A/B/A`
return only for consecutive engine frames when both adjacent normalized
distances are material and the older-to-current distance is at most half the
smaller adjacent leg. Gaps and duplicate-engine-frame chains reset the detector.
This detects a producer that strongly returns toward its two-frames-older state;
it does not by itself prove every detected return is visually wrong.

The final authorized physical Checkpoint 36 run produced 31,396 sent and
rendered chains with no dropped chain, missing drawable, zero-chain frame, or
multi-chain frame. It retained 4,711 strong producer returns, while live-to-
packet and within-chain packet mismatch totals remained zero. Physical Metal
reported 31,394 completed presentations, one initial drop, and zero actual
presentation-order reversals. The camera return therefore exists before the
renderer packet copy in that run; no presentation rescheduling has been added.

Presentation callbacks are intentionally interpreted using the documented
Metal semantics: a zero `presentedTime` is a drop, and callback arrival order is
not assumed to be presentation order. The diagnostic retains a fixed 64-pair
successful-presentation history and counts an inversion only when submission
order and actual presentation-time order disagree.

Run the expanded deterministic trace test directly after building it:

```sh
cmake --build OpenGOAL/build/Release/bin \
  --target metal-camera-trace-test -j 4

OpenGOAL/build/Release/bin/game/metal-camera-trace-test
```

The recorded Checkpoint 36 result is 23 passing assertions, including duplicate
and gap resets, smooth motion, real returns, durable event retention, callback
arrival reordering, actual presentation inversion, and zero-time drops.

The current A/B retains Checkpoint 37's fixed 60 Hz display-link range but
restores Checkpoint 36's independent per-callback interval rounding.
`Scripts/run-camera-timing-check.sh` covers ordinary cadence, skipped intervals,
complementary early/late intervals, repeated boundary and slow cadence, the
long-stall cap, invalid input, and lifecycle reset. The A/B changes only the
display-target conversion; it does not change the renderer's producer-to-packet
copy or Metal presentation accounting.

The final authorized physical Checkpoint 37 run produced 29,666 sent and
rendered chains with no chain drop, missing drawable, zero-chain frame, or
multi-chain frame. It retained 1,661 strong producer returns, with zero live-to-
packet or within-chain mismatch. Physical Metal reported 29,645 completed
presentations, 21 zero-time drops, 41 late-present submissions, and zero
presentation-order reversals. The return detector therefore fired on about 5.6
percent of this run rather than Checkpoint 36's roughly 15 percent, but the
maintainer found the camera visibly worse. These were different gameplay runs;
the detector is provenance incidence, not a camera-quality score, and the
fractional-debt behavior is not physically accepted.

### Jak 1 Merc palette provenance diagnostics

The deterministic Metal proof now executes the real Jak 1 parented-joint
routine, `bones_mtx_calc::exec_mpg`, and the outer `bones_mtx_calc::execute`
scratchpad/DMA wrapper. Direct and wrapper count-one output must be bit-identical.
An `A/B/A/B` sequence must produce exact repeated 80x138 and 40x172 pixels after
EE palette memory is poisoned following synchronous submission. A 17-bone case
must place bones 0-15 in the first buffer and bone 16 in the second, with all
matrices distinct, correct sentinels, 128-byte strides/padding, and intact
guards.

Live Merc required slots are precomputed at level load as four 64-bit masks per
model effect. Runtime work ORs enabled-effect masks, compares them with slots
populated by valid 112-byte EE copies, and enumerates slots only for the first
error log. A missing required slot remains zero and the draw still submits. The
complete deterministic packet reports zero omissions; the omitted-slot packet
reports exactly one slot in one model and collapses the authored-origin pixel to
black.

The same physical Checkpoint 36 record reported zero missing required Merc slots
and zero affected models across the full 31,396-frame run. This rules out the
instrumented missing-slot predicate for that run, not every possible deformation
failure. The outer GOAL calculation-list dispatcher, larger live batches, and
finite-but-degenerate palette matrices remain the next unproved seams. The only
Jak 2/Jak 3 behavior carried into Jak 1 here is the homogeneous-W clear in Jak
1's independently translated parented-joint routine; it is not a claim that
later games already solved GOALPad's full visual defect.

The maintainer described this exact physical run as one of the best yet: camera
jitter was slight instead of violent, and several power cells could be collected
comfortably. Jak still became incorrectly oversized, however, and the
volumetric/Flat-Stanley deformation returned. The W-lane addition is therefore
not a complete live Merc fix. The next behavior-neutral diagnostic should check
finite/non-degenerate values and source provenance for required matrices that
are present, before Metal upload and shader consumption.

Checkpoint 37 adds that behavior-neutral health check for present required
Merc matrices. It counts non-finite values, degenerate bases, and incoherent
source bases and retains numeric slot, model/matrix hashes, axis norms,
normalized determinant, and source-base evidence without altering the draw.
The final physical totals were 7,706 non-finite matrices, 343 degenerate
matrices, zero incoherent sources, and 1,388 affected model instances. Current-
frame health was zero at the end. The retained event was `speaker-lod0` slot 4
at frame 27,647; the earlier intro event was `logo-volumes-english-lod0`.
Neither retained model is Jak, so this probe did not capture the reported Jak
deformation and the totals must not be presented as its cause.

The same run reached the farthest gameplay yet but was physically worse than
Checkpoint 36 for camera motion, world-depth fighting, and Merc deformation.
The maintainer also observed a new flicker on metallic materials resembling a
localized z-fight. No physical touch-control verdict was reported. These are
four separate observations; the current counters do not attribute the new
material flicker or the broader depth fighting to camera cadence, Merc palette
health, or Metal presentation order.

### The signed generic iOS Release build

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-device -jobs 4 \
  -allowProvisioningUpdates build
```

Build evidence only; nothing was installed on a device. The executable is thin
`arm64`, 26,466,656 bytes, SHA-256
`8adcabf623df9c4d8dde1bc7ae51e88e56a235fb94a3102a54b564a772f379c6`.
`codesign --verify --deep --strict` reports `valid on disk` and `satisfies its
Designated Requirement`, team `D2YYJ54Q6V`. Entitlements are unchanged: the
application identifier, the team identifier, and `get-task-allow = true`, and
nothing else.

**No writable-executable segment.** `__TEXT` is `r-x` (initprot and maxprot both
`0x5`), `__DATA` and `__DATA_CONST` are `rw-` (`0x3`), `__LINKEDIT` is `r--`, and
`__PAGEZERO` is `---`. No segment is `0x7`. There is no app-root dynamic library.
The imports are still `mmap`, `mprotect` and `dlsym` and no others of interest -
the same three the kernel-core and app-shell checkpoints recorded, for the same
reasons - with no `dlopen`, no `pthread_jit_write_protect_np`, and no
`newLibraryWithSource:`.

## The iPad app shell

**Implemented**, except where noted. This is everything around the engine and
the renderer: game data on the device, controller input, audio output, the
presentation surface, and app lifecycle.

### Engine seams and why they are gated

The shell is written against four narrow C seams in
`OpenGOAL/game/kernel/core/`:

| Seam | Header | What the shell calls |
| --- | --- | --- |
| game data | `kernel_core.h` (ships with `dgo_loader.h`) | `goal_kernel_core_set_data_directory` |
| controller | `pad.h` | `goal_pad_state_neutral`, `goal_pad_set_state`, `goal_pad_get_rumble`, `goal_pad_read_count` |
| audio | `sound_rpc.h` | `goal_sound_sample_rate`, `goal_sound_pull_audio`, `goal_sound_shutdown` |
| renderer | `gfx_host.h` | `goal_gfx_host_install` |

**All four are in the pinned submodule and all four are linked.**
`GOALPad/Native/GOALPadEngineSeams.h` is the only file that knows how to tell:
it detects each seam with `__has_include` and defines `GOALPAD_HAVE_DATA_SEAM`,
`GOALPAD_HAVE_PAD_SEAM`, `GOALPAD_HAVE_SOUND_SEAM` and `GOALPAD_HAVE_GFX_SEAM`,
plus `GOALPAD_HAVE_GAME_BOOT` for the generated `aot_boot_manifest.h`. Where a
seam is missing the shell reports its absence on screen and in the log rather
than pretending to work. The readout says `linked` for all five today.

`GOALPadRuntimeBridge.mm` static-asserts every button bit, the analog neutral
value, and the port count against `goal_pad_button` whenever the pad seam is
present, so the two definitions cannot drift apart silently.

### Game data on the device

The player's own prepared data lives in `Documents/Jak1/iso` and
`Documents/Jak1/fr3` — the `iso/` and `fr3/` directories the OpenGOAL Jak 1
extraction produces, about 1.5 GB. No game data ships with GOALPad, none is
downloaded, and `Documents/Jak1` is marked `isExcludedFromBackup`.

`GOALPad-Info.plist` supplies `UIFileSharingEnabled` and
`LSSupportsOpeningDocumentsInPlace`, which together expose that directory to
Finder and the Files app. Xcode's generated `Info.plist` does not emit
`UIFileSharingEnabled` from an `INFOPLIST_KEY_` build setting — it was tried and
silently dropped — so the target sets `INFOPLIST_FILE = GOALPad-Info.plist` and
Xcode merges the generated keys into that partial file. The file deliberately
sits outside the `GOALPad/` synchronized group so it is not also copied in as a
bundle resource.

Copying the two directories in from Finder or Files is the primary route: it
writes the data once. `GameDataImporter` is the secondary route, for data on an
external drive or in iCloud Drive; it copies file by file with progress and
cancellation, skips files already present at the same size, and needs the free
space twice over. It only ever reads the folder the player picked.

`GameDataInspector` reports what is actually on disk against the manifest in
`GameData.swift`: `KERNEL.CGO` and `GAME.CGO` (without which the game cannot
boot), 25 level DGOs, and 25 `.fr3` files. Missing names are listed individually.
The resolved directory is handed to `GOALPadRuntimeBridge.startKernel(withDataDirectory:)`.

The app can only read inside its own container. A symlink from
`Documents/Jak1/iso` to a directory elsewhere on the host reads as empty, which
was confirmed on the simulator; the data has to actually be in `Documents`.

### Controller

`ControllerInput` uses GameController: connect/disconnect notifications,
wireless discovery, and `GCExtendedGamepad`. GameController names face buttons by
position and the DualSense's are where the PS2's were, so A/B/X/Y map to
cross/circle/square/triangle directly. Shoulders are L1/R1, triggers are L2/R2
plus an analog pressure byte, thumbstick buttons are L3/R3, `buttonMenu`
(Options) is Start, and both `buttonOptions` (Create) and the DualSense or
DualShock touchpad button are Select. Sticks become a byte per axis with 127 at
rest, growing right and down — the Y axis is negated
because GameController reports up as positive and the PS2 pad did not. With no
controller attached on a non-iOS host, the port is pushed as disconnected. On
iOS the on-screen controls provide a neutral connected pad, merged with
GameController once per successfully armed display-link frame.

### Modern and Classic settings

`PresentationSettings` stores one versioned document for the Controls,
Graphics, Audio, and UI sections. Each section has an independent
Classic/Modern profile. The top preset sets all four profiles without deleting
their customized option values and displays Mixed when they differ. Section
Restore Defaults resets only that section's options for its selected profile;
fresh settings and Reset All select Classic Controls, Modern Graphics with Fill
Width enabled, Classic Audio, and Classic UI. This intentional default appears
as Mixed. Existing local or iCloud documents retain their saved profiles and
option overrides.

The local document is
`Library/Application Support/GOALPad/Settings/presentation-v1.json`. When
available, the same complete document is merged through
`Documents/GOALPad/Settings/presentation-v1.json` in the app's iCloud container
using modification time and a stable writer ID. Unresolved iCloud file versions
participate in that merge. The `Sync settings with iCloud` switch is stored only
on the current device and is separate from `iCloud Saves`.

Graphics Modern currently exposes Fill Width (Hor+). On a drawable wider than
4:3 it preserves internal target height, widens the target, fills the drawable,
and reports the wide aspect to GOAL. Classic keeps the prior 4:3 target,
letterbox, and machine-query behavior. On portrait or narrower drawables Hor+
does not reduce the Classic horizontal field of view.

The deterministic checks are:

```sh
Scripts/run-presentation-settings-check.sh
Scripts/run-presentation-geometry-check.sh
```

These checks cover settings defaults, Mixed profiles, option preservation,
restores, Reset All, first cloud write, conflict ranking, save-sync isolation,
and exact geometry. They do not replace the bounded physical Hor+ acceptance
and do not establish a full Classic/Hor+ A/B, orientation/performance coverage,
or real two-device iCloud convergence.

#### Experimental on-screen controls

The iOS Classic Mode touch layer creates a movement stick under the first
left-half contact and keeps a continuous analog R stick at bottom right.
Right-half swipes map up/left/right to Cross/Square/Circle; a downward swipe
holds L1 directly for as long as its finger remains down, and reversing that
drag upward adds one bounded Cross pulse without releasing L1. Short right-half
taps are deliberately inert. Start and Select remain fixed pills. There is no
free camera drag outside the R stick. Strong movement-stick pushes still
synthesize D-pad edges and bounded repeats for menus.

Physical-controller buttons are unioned with touch buttons, and a physical
stick outside the engine's minimum deadzone takes priority over the matching
touch stick. Recent physical input hides the artwork without disabling touch.
The diagnostics overlay and its internal-resolution picker are hidden by
default. A compact button using the `line.3.horizontal` symbol opens them; the
default game view has no zoom controls or keyboard/ellipsis icon over the game.

Touch state is cleared on shutdown and whenever the scene becomes inactive or
backgrounded. The deterministic state-machine check is:

```sh
Scripts/run-touch-controls-check.sh
```

It covers the movable movement origin and analog clamp, absence of free camera
gestures, face-button swipes with inert short taps, continuous analog R-stick
deadzone/travel/release behavior, continuous L1 through the reverse-to-Cross
gesture, immediate L1 release, D-pad repeat, simultaneous controls, pill hit
testing, visibility, and reset. The macOS and generic iOS builds pass, and the
named M5 simulator launches. The harness does not directly cover
`ControllerInput` merging, UIKit delivery, physical multitouch ergonomics, or
physical-iPad latency.

Rumble consumes the strongest motor request latched by `goal_pad_take_rumble`
once per presented frame and drives finite Core Haptics players. On DualSense,
`.leftHandle` receives the low on/off motor and `.rightHandle` receives the sharp
analog motor at a twofold, clamped gain. A consumed zero lets the DualSense's
finite 120 ms event finish; disabling rumble, suspending gameplay, or
disconnecting still silences it immediately. Other controllers retain the
original scale and default-locality fallback. The DualSense's adaptive triggers
are deliberately not driven: the PS2 pad had none, so nothing in the game asks
for them.

**Not validated:** Build 197's revised strength, pulse length, and left/right
feel still require physical DualSense acceptance. The previous physical report
was weak overall and perceptible only on the right side.

### Audio

`AudioOutput` opens an `AVAudioEngine` source node at `GOALPadAudioSampleRate()`
— 48 kHz stereo — and connects it to the main mixer with that format, so the
engine's output chain resamples to whatever the hardware is running at rather
than asking 989snd for a different rate. The render block is real-time safe: it
pulls into a preallocated 4096-frame interleaved `Int16` buffer, converts to the
node's two deinterleaved float channels, allocates nothing and takes no
Objective-C path. When the seam returns 0 frames it sets the silence flag and
zeroes the buffers.

The session category is `.playback`. Interruptions suspend and resume on
`.shouldResume`, losing the old route (headphones out) suspends,
`mediaServicesWereReset` and `AVAudioEngineConfigurationChange` rebuild the
graph, and backgrounding gives up the device entirely.

### Presentation surface

`GameSurfaceView` hosts a `UIView` whose `layerClass` is `CAMetalLayer` and hands
the layer to `GOALPadRenderSurface`, which sets the device, `BGRA8Unorm`, and
`framebufferOnly`. A `CADisplayLink` at a preferred 60 Hz drives one frame.

The geometry matches what `MetalRenderer::encode_present_pass` in the OpenGOAL
fork expects: the game renders into an offscreen target at its internal
resolution, and a present pass draws that target into a centred, letterboxed
draw region of the drawable. The draw region is the largest rectangle of the
game's own aspect that fits the drawable.

**Internal render resolution is 2x — 1280x960 — by default,** settable to 1x, 2x,
3x or 4x and persisted in `UserDefaults`. The scale is a whole multiple of the
PS2's 640x480 so the game keeps its 4:3 aspect and its HUD keeps its
proportions. 2x is clearly better than the PS2 and leaves headroom; 3x
(1920x1440) is close to one-to-one with an 11-inch iPad's 1668-pixel short edge
and is the obvious next step. The default should be revisited once the fused
renderer can be measured on hardware — it was chosen for headroom, not from a
measurement.

`-[GOALPadRenderSurface beginFrame]` turns that geometry into a
`MetalRenderOptions` - `game_res_w/h` from the internal resolution and
`draw_region_w/h` from the letterbox - and arms `GOALPadMetalHost` before GOAL
runs. `-[GOALPadRenderSurface endFrame]` clears that one-tick presentation
context and records whether `send_chain` drew. `rendererLinked` reports `YES`.

### Lifecycle

`GameSession` owns the kernel session, controller and touch input, the audio
device and the frame loop. One frame is: arm the presentation surface, push the
merged pad state, run one `kernel-dispatcher` frame and one `goal_sound_frame`
while its DMA send renders synchronously, close the presentation context, then
read the vibration request back out. GOAL does not advance when no valid
surface can be armed.

On iOS, consecutive `CADisplayLink.targetTimestamp` values pass through Swift
and the Objective-C++ bridge to `DisplayClock`. The clock independently rounds
each interval to an integral 60 Hz ratio from 1 through 4. The first sample, an
invalid or non-positive sample, and a sample after lifecycle reset return 1;
long intervals remain capped. The runtime stores the result in
`*host-display-time-ratio*`, which `display-frame-start` consumes immediately
before `set-time-ratios`. A zero host value preserves the upstream fallback on
other hosts.

Booting runs the game's own startup - two DGO archives and `play` - so it runs
on its own queue and the UI says `Booting Jak 1` until it finishes. The frame
loop and the boot never overlap: the loop only starts once the boot has
returned. 989snd is the exception and is designed to be: it takes its own lock,
so the audio device's render thread pulls from it while the game frame runs on
the main thread.

`scenePhase` drives it. Going inactive or background synchronously closes frame
eligibility, suspends the audio device, stops rumble, and resets in-flight touch
state. The surface view separately invalidates its display link and detaches its
`CAMetalLayer`, closing any armed presentation tick before releasing the layer.
On activation it reattaches the layer and creates a new display link. Gameplay
and audio remain suspended until the existing save-recovery gate completes for
the latest active-scene generation; a completion from an older activation can
only start preparation for the latest generation, never reopen frames itself.
Audio interruptions and route changes also remain subordinate to that lifecycle
permission. The idle timer is disabled only while an active session can run.
`willTerminate` shuts the session down cleanly through the bridge. A memory
warning is counted and logged; the kernel's 128 MiB is fixed for the life of the
session so the shell has nothing to give back, and dropping cached level data
will be the fused renderer's decision.

### What was observed on the simulator

iPad Pro 11-inch (M5), `id=96C5C21A-B925-4213-82A3-90DCB8518339`, Debug, with the
player's own `iso/` and `fr3/` hard-linked into the app container. **The game
boots and runs.**

- Seams: `game data: linked`, `controller: linked`, `audio: linked`,
  `Jak 1 GOAL code: linked`, `renderer: not in this build`.
- Boot, in 0.1 s: `KERNEL.CGO: 8 objects`, then
  `GAME.CGO: 346 objects: 326 code, 20 data` - the code from the ahead-of-time
  path, the data off the player's own disc image - `GOAL kernel version 2.0`,
  55472784 bytes of global heap and 5721 symbols. The host's
  `jak1-data-boot-test` reports the same 8 and 346 and the same heap.
- `play` ran: `(play :use-vis 0 :init-game 0) has been called!`,
  `begin load title-vis [tit.DGO]`, `TIT.DGO: 15 objects`,
  `GAMEPLAY: enter title`, then `village1` streaming in behind the logo
  (`VI1.DGO`, the 7.3 MB `village1-vis`, `Swapping in vi1 VIS`,
  `Displaying level village1`).
- Frames: 6000 consecutive `kernel-dispatcher` frames in 100.0 s - exactly 600
  per 10 s, so a full 60 fps - with no drift and no fault. Each frame built a
  DMA chain; payloads ran 97 kB to 195792 bytes with 10 texture uploads in the
  last one, which is the title screen with Sandover Village behind it.
- **Audio: 4808192 frames asked for and 4808192 produced, 48000 Hz stereo, peak
  sample 3709 of 32767.** 989snd loaded `common`, `empty1`, `empty2` and
  `village1` and started `VILLAGE1.MUS`; the peak matches the 3416 the host
  records for the same title theme, which is the game's own volume - the PC
  port's music default is 40 of 100. Nothing is silent and nothing is clipped.
- Controller: the simulator's virtual `Gamepad` was discovered and adopted, and
  `reads by GOAL` tracked the frame count exactly (5996 reads at frame 6000).
- Surface: drawable 1668x2420, internal 1280x960, draw region 1668x1251, one
  presented frame per game frame.
- Memory warnings: 0.

Only the portrait drawable was exercised, so the draw region's width-limited
branch is the one with evidence; the height-limited branch is the same
arithmetic with the operands swapped.

Nothing is drawn. `renderer: not in this build` is the truth: the frame's DMA
chain is measured by `dma_capture.cpp` and dropped, and the surface presents its
placeholder. What a frame *computes* is real; what it would have *shown* is not.

To reproduce, stage the data into the app container rather than symlinking it -
the app can only read inside its own container:

```sh
DEV=96C5C21A-B925-4213-82A3-90DCB8518339
C=$(xcrun simctl get_app_container "$DEV" com.zephyrstudiosllc.GOALPad data)
SRC=/path/to/out/jak1
mkdir -p "$C/Documents/Jak1/iso" "$C/Documents/Jak1/fr3"
for d in iso fr3; do
  for f in "$SRC/$d"/*; do
    t="$C/Documents/Jak1/$d/$(basename "$f")"
    [ -e "$t" ] || ln "$f" "$t"
  done
done
```

Hard links keep the 1.5 GB in one place and never write to the source. Launch
the app detached - `nohup xcrun simctl launch --console-pty ... &` - because
`--console-pty` ties the app's lifetime to the launching process, and a shell
that is interrupted takes the app down with it.

### Checkpoint 32 fixed-step and touch simulator evidence

The combined fixed-step/touch Debug build was update-installed on the approved
iPad Pro 11-inch (M5) simulator. It booted the complete user-local Jak 1 data,
loaded 8 KERNEL objects and 346 GAME objects, and reached the title screen. The
on-screen Start pill entered the main menu; right-half tap/Cross opened the new
game save flow without modifying the existing save. Diagnostics Hide/Info,
scrolling, and the internal-resolution picker remained accessible through the
full-screen touch layer.

Runtime logging confirmed `Using one fixed 60 Hz simulation step per iPad
display-link tick.` and did not emit the missing-`*pc-fixed-step*` warning. At
frame 15,000, tick chains `0/1/>1` were `0/15000/0`, 15,000 drawables had been
scheduled with 0 missed, and Merc reported 0 bad bone pointers and 0 rejected
draw ranges. Later diagnostics showed the sent and encoded DMA totals still
matched with 0 dropped.

This is simulator-only evidence that the fixed-step branch was active, the
runtime advances, and the tested touch actions reach GOAL. It does not prove
that the physical one-second camera sway is gone, that the flat/balloon Merc
deformation is fixed, or that stick/camera multitouch is correct on hardware.
At Checkpoint 32, that combined build had not been installed or launched on a
physical device. The later physical result and its replacement are below.

### Checkpoint 33 display timing, joint parity, and device evidence

The Checkpoint 32 forced-fixed-step build was subsequently update-installed on
physical **Z iPad Pro**. The maintainer found its blocker/auto-rotate camera
correction substantially more aggressive than the previous build; a follow-up
variation was less severe but still worse. That experiment was removed. The
older artifact at
`/private/tmp/GOALPad-fixedtick-device/Build/Products/Release-iphoneos/GOALPad.app`,
executable SHA-256
`7b6af06f70ef29ff0befbe9b5a6e8da116478798ac56e98655c4e2adef0d3c56`,
was restored before the evidence-backed replacement was prepared.

The root timing error was phase, not merely magnitude. Resetting
`*timer-reset-value*` immediately before `kernel-dispatcher` made
`display-frame-start` measure the preceding callback's dispatcher/render work.
A normal callback followed by a skipped display interval could therefore reach
GOAL as ratios 2 then 1 instead of the display's actual 1 then 2. Camera seeker
acceleration and displacement both consume the ratio, so the phase error is
especially visible in auto-rotation and blocker correction. The
target-presentation-time path described above replaces that experiment.

The Merc investigation separated two behaviors. Localized squash/stretch in
Jak's positive-scale attack animation is authored and remains unchanged.
Separately, Jak 1's MIPS2C translation of
`cspace<-parented-transformq-joint!` allowed a negative scale to sign-extend
through `mfc1`/`pcpyld`, putting a NaN in the homogeneous `vf16.w` lane and
poisoning child basis rows. Jak 2 and Jak 3 already clear that lane before the
vector multiply; Jak 1 now does the same. The physical iOS build retains the
MIPS2C bones compatibility selection that restored Jak's volumetric shape.

Focused validation passed:

```sh
Scripts/run-camera-timing-check.sh
Scripts/run-touch-controls-check.sh

cmake --build OpenGOAL/build/Release/bin --target \
  jak1-mips2c-joint-regression-test \
  jak1-kernel-core-smoke-test \
  jak1-aot-execution-test -j4

ctest --test-dir OpenGOAL/build/Release/bin --output-on-failure \
  -R 'jak1-(mips2c-joint-regression|kernel-core-smoke|aot-execution)-test'
```

CTest passed 3/3:
`jak1-mips2c-joint-regression-test`, `jak1-kernel-core-smoke-test`, and
`jak1-aot-execution-test`. The joint test covers ordinary and negative parent
scale, and the AOT test proves the live Apple VM mapping remains `rw-` across
real ahead-of-time native calls. AOT regeneration emitted 10,596 of 10,603 functions,
retained seven native functions, and reported zero failed source files.

Fresh ARM64 macOS and named-M5-simulator builds passed:

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

The simulator was update-installed without removing its data and launched. The
real runtime loaded the title and Village1 with 48 kHz audio. Diagnostics showed
zero Merc pointer or draw-range rejects, zero drawable misses,
`EE arena executable: NO`, and display cadence of 17.00/16.97/66.44 ms
mean/p95/max with 2 callbacks below 12 ms and 10 at least 24 ms in the captured
sample. The default UI showed only the three-line button; diagnostics and the
resolution picker appeared after opening it. The simulator was shut down after
validation.

The generic signed iOS Release build also passed:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-cp33-device \
  -allowProvisioningUpdates ENABLE_PREVIEWS=NO ENABLE_DEBUG_DYLIB=NO build
```

The executable is thin ARM64 with SHA-256
`0b2e2ad81af7c3575e5ff9fb180c2957fec46a74daf61c956cad0588f4b9fcae`.
Its entitlements are limited to the development application identifier, team
identifier, and `get-task-allow`; there is no JIT entitlement. Standalone
`codesign --verify --deep --strict` returned `CSSMERR_TP_NOT_TRUSTED` for the
known local certificate-chain condition. CoreDevice nevertheless accepted an
update-install on the explicitly authorized **Z iPad Pro**. An attached launch
produced the evidence below; after detaching terminated that process, a final
non-console relaunch passed and was left live. The physical console booted the
real ARM64 kernel with `PROT_EXEC=no`, loaded the title and Village1, and started
48 kHz audio.

Those facts prove the combined build, install, and native runtime path. They do
not establish the requested visual result: the maintainer has not yet accepted
the current camera behavior or Merc appearance. Physical controller mapping,
multitouch ergonomics, and haptics also remain unvalidated.

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

This builds the currently pinned GOALPad OpenGOAL fork series, including the
published ARM64 AOT and data-arena/invoker work. Use the exact current pin from
the initialization section above; older hashes in historical recovery sections
are not the normal build target.

The `data` symlink is local build state. It lets OpenGOAL's test executable find
the pinned source tree when the build directory is outside the repository.

## Historical patch recovery for the downstream OpenGOAL AOT work

The normal build uses the published pinned fork above. The ordered patches
below remain recovery and review artifacts for reconstructing historical
commits; they are not the normal submodule initialization path.

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
three zero-argument, three one-argument, two two-argument, and one three-argument
native entry outside the legacy 32-bit GOAL symbol representation; it does not
mutate a live GOAL symbol table.

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
  --terminate-existing com.zephyrstudiosllc.eco

xcrun devicectl device process launch \
  --device <coredevice-id> \
  --terminate-existing --console --timeout 10 \
  com.zephyrstudiosllc.eco
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

## Checkpoint 15: portable existing-symbol value-cell resolver

Patches 0038 and 0039 preserve child commits
`da6cfe9eaf245db3d92cc69bc0074a4496b02f9d` and
`deebafd603f702f54133a8a9e8f5ce500a113231`. Parent checkpoint
`b89ff6cccef73952c5f57415905d893d23267f46` is pushed to
`origin/feat/ipados-native-boot`; the official submodule remains at its
fetchable pin. The patches and stable identities are:

| Patch | SHA-256 | Stable patch ID |
| --- | --- | --- |
| `0038-feat-data-arena-add-read-only-symbol-value-lookup-AI.patch` | `a7ab385d97511c126766e5cb756eca564a1be0c3f550b2cf9d030368c7066b89` | `369d7a19a863e8dae653f0dc12ab3ef41542b5d6` |
| `0039-fix-data-arena-validate-canonical-symbol-table-tags-.patch` | `3effeea99ea54d96fde7f1489c16357d773646f282e2e955cbfbe72bc54697eb` | `8ddab02469c04970285d73a5f632ce17e05de5ea` |

The portable `find_data_arena_symbol_value_cell` API searches only
already-staged caller-owned synthetic arena metadata. It validates the
canonical header and symbol-table tags, uses the compatible stateless CRC path
and bounded probe order, and returns a GOAL value-cell offset plus its signed
`s7` displacement. It is read-only and does not read the value cell itself.
It does not create symbols, call `intern_from_c`, bind `g_ee_main_mem`,
initialize a live runtime, execute GOAL, link top-level code, dispatch a
method, load game data, or boot Jak 1.

The host validation used the existing configured build tree:

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

The no-copy `jak-project` aliases used only for the direct `goalc-test` command
point to the resolver source and build directories; the CTest target does not
need them. Before the prerequisite build, the first full CTest invocation
reported `arm64-goal-call-abi-test_NOT_BUILT` and a missing `goalc-aot`
executable after the resolver tests. That was an incomplete-target
infrastructure failure, not a source-test failure. After the targeted builds,
the focused data-arena suite passed 23/23, the established compiler and emitter
filter passed 191/191, and the complete CTest suite passed 31/31.

The fresh iPhoneOS static-library proof used no desktop runtime target:

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

The archive contains one `data_arena.cpp.o` arm64 object. Its
`LC_BUILD_VERSION` is iOS 18.0 with SDK 26.5; it exports
`initialize_data_arena_header` and `find_data_arena_symbol_value_cell`, and
imports only `_bzero`, `_memchr`, and `_memcmp`. This is iPhoneOS
static-library compatibility evidence only, not an executable, signed app,
simulator, or physical-device result. No simulator, physical device, Xcode app
build, remote, or retail game data was accessed for this checkpoint.

The next seam is resolver-backed synthetic composition through the signed
`load-state-value` and direct `reset!` artifacts. It must remain a guarded
synthetic proof rather than live linking, top-level initialization, virtual
method dispatch, or a Jak boot claim.

## Checkpoint 16: synthetic resolver and reset composition

Patch 0040 preserves child commit
`a13b42f7c8e67eb123f01ad0bca9ba07ad27bf96`, reviewed from source commit
`9a830552`, through parent checkpoint
`bea65508b83261b58b11cde89efb1daa445aeaa6`, which is pushed to
`origin/feat/ipados-native-boot`:

| Patch | SHA-256 | Stable patch ID |
| --- | --- | --- |
| `0040-test-arm64-compose-load-state-resolver-and-reset-cov.patch` | `c90826e4d56bbff5b91c9a11b74f1c01488b1e64ec1899021446eb37b129d975` | `34929147e5b019a1b9298b0c27ae5fa604c5498a` |

The one new ARM64 ABI test manually stages a synthetic Jak 1 symbol, string,
value cell, and `load-state` object in one guarded arena. It resolves the
existing `*load-state*` cell, applies the resulting signed displacement to the
existing signed `load-state-value` artifact, and passes that value to the
direct `reset!` export. It verifies reset output, preserved staged metadata,
object and outer guards, and restored caller registers. The test allocates one
roughly 66 MiB arena and does not add a duplicate allocation.

The exact host validation was:

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

The incremental ABI target build passed. Focused ABI CTest passed 8/8, full
CTest passed 32/32, and the established direct compiler/emitter filter passed
191/191. No iPhoneOS rebuild was run because the `jak1-data-arena` library
source is unchanged. No simulator, physical device, Xcode app build, remote,
or retail game data was accessed.

This is test-only, manually staged synthetic composition. It does not advance
the heap, link code, initialize types or a live runtime, dispatch a method,
load game data, or boot Jak 1. Production symbol staging is rejected now: a
fresh arena has zero `symbol` and `string` Type values, so staging would
formalize synthetic fixture work before fundamental-type and top-level bootstrap
exists. The next task is a guarded existing-object type/method binding plus
32-bit GOAL method-value-to-signed-native mapping audit/proof, without a
hard-coded direct dispatch. It remains separate from linking, live runtime
initialization, general type creation, game data, and boot.

## Checkpoint 17: read-only BASIC method-value lookup

Patch 0041 preserves child commit
`0ee4a48f9f58ea1504e84c500f6a0942bc8047ce` through parent checkpoint
`98a007148619c9e2a8e1bcddb01a09ae4af2e8f3`. The official OpenGOAL submodule
remains at its fetchable pin. The exact preserved patch identity is:

| Patch | SHA-256 | Stable patch ID |
| --- | --- | --- |
| `0041-feat-data-arena-add-read-only-BASIC-method-lookup-AI.patch` | `92fb8c378e666626c8656473451a8d024a2eb4b9f78dcf99e3bc6b518d6089cb` | `477d57e981399206ca7c890f66235153eee5554c` |

The ordered 0038-0041 replay exactly matches the `0ee4a48f` tree, and the
reverse patch check passed.

The portable `read_data_arena_basic_method_value` API reads a caller-owned
synthetic BASIC object's method-table word only after validating the header,
BASIC representation, actual object type, Type-Type root and tag, object size,
and slot bounds. It returns the raw 32-bit GOAL method value with the actual
object type and validated sizes; it does not mutate storage, cast a method word
to native code, inspect a function object, map to signed text, or invoke GOAL.
The retained synthetic fixture uses `method_id = 9`, `allocated_size = 0x82c`,
and `padded_size = 0x830` for the next `load-state` binding seam.

Recorded host validation used the existing configured build tree:

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

The focused data-arena target build passed; `Jak1DataArena` CTest passed 31/31.
The ARM64 goal-call ABI target build passed, full CTest passed 40/40, and the
already-existing direct compiler binary passed the compiler/emitter filter
191/191.

The fresh iPhoneOS minimal archive proof used:

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
inspections reported one ARM64 Mach-O object whose build version is iOS minimum
18.0 with SDK 26.5. It exports
`initialize_data_arena_header`, `find_data_arena_symbol_value_cell`, and
`read_data_arena_basic_method_value`, and imports only `bzero`, `memchr`, and
`memcmp`. This remains static-library compatibility evidence only: no app or
runtime integration, signing, simulator, or physical-device validation occurred
in Checkpoint 17.

Commit B is the next task: bind the exact `load-state` method by actual
`object_type`, `method_id = 9`, raw `method_value`, and exact
`0x82c`/`0x830` sizes to an immutable, statically linked signed entry. Do not
cast the raw method word to a native address or add JIT; keep the caller-owned
arena stable and exclusively owned through lookup, binding, and invocation.

## Checkpoint 18: portable trusted-native BASIC method binding

Patch 0042 preserves child commit
`7aaaf29942f5836dda311e173865dfcd0ea6de64` through parent checkpoint
`eaa649934ce3ba7523529bef30b39729c06d4af4`. The official OpenGOAL submodule
remains at its fetchable pin. The exact preserved patch identity is:

| Patch | SHA-256 | Stable patch ID |
| --- | --- | --- |
| `0042-feat-data-arena-bind-trusted-native-BASIC-methods-AI.patch` | `7bc05ccdd163742fd0701d7bd350bebecef79ccb5d1b422be403085adf428af3` | `9ddfba8fcf1a5c1416266aae51c6d66c7fbe7c73` |

The ordered 0038-0042 replay exactly matches the `7aaaf299` tree, and the
reverse patch check passed.

The portable `invoke_data_arena_native_basic_method1` API synchronously reads
the actual BASIC method, validates its Function tag, and accepts a
caller-provided native entry only when actual object type, method id, raw GOAL
method value, allocated and padded sizes, and arity one all exact-match the
binding tuple. The fixture uses `method_id = 9` and exact sizes
`0x82c`/`0x830`. The raw GOAL word remains data: it is never cast to native code
and the only callable entry originates in the binding table.

`native` is intentionally neutral: this portable C++ boundary does not prove
static linkage, code signing, native-entry provenance, or the platform ABI.
Production callers provide those properties and keep the arena, header, binding
span, and aliases alive and exclusively serialized through lookup, binding, and
invocation. The boundary supplies no internal synchronization.

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

The focused data-arena target build passed; `Jak1DataArena` CTest passed 37/37.
The ARM64 goal-call ABI target build passed, full CTest passed 46/46, and the
existing direct compiler binary passed the compiler/emitter filter 191/191.

The fresh iPhoneOS minimal archive proof used:

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

The fresh configure and `jak1-data-arena` build passed. The archive contains
one ARM64 Mach-O object with iOS minimum 18.0 and SDK 26.5. It exports
`initialize_data_arena_header`, `find_data_arena_symbol_value_cell`,
`read_data_arena_basic_method_value`, and
`invoke_data_arena_native_basic_method1`; it imports only `bzero`, `memchr`,
and `memcmp`. This remains static-library compatibility evidence only: no app,
runtime, signing, simulator, physical-device, or AOT ABI invocation validation
occurred in Checkpoint 18.

The next task is to invoke the actual generated `load-state::reset!` Export1
through the typed binding and a `call_goal_asm_arm64` invoker in guarded
synthetic arena(s). Preserve caller-register and guard checks and fail closed
for nonmatching tuples; do not add a raw-address cast, JIT, app/runtime
integration, signing claim, or live data path.

## Checkpoint 19: generated reset! ARM64 ABI composition (test-only)

Patch `0043-test-arm64-compose-native-load-state-reset-binding-A.patch`
preserves child `e60fb292b28168ad62d9345e8e0a33eea9356d82` with SHA-256
`b1c82bdde66acecabb5a0f1fd5c1db713e3512fb8a64d634bd340683d2ba7374` and
stable patch ID `ac085c91b06863f4b7f3362b7eb93f6c3eaedb5d`. Ordered 0038-0043
replay exactly matches that child, and the patch reverse check passed against
the preserved child tree.

The change is limited to `test/test_arm64_goal_call_abi.cpp`. It uses the
generated `kArm64GoalExports1[3].entry` for `load-state::reset!` through the
existing typed binding and `call_goal_asm_arm64` outer wrapper. The raw GOAL
method word is never a native pointer. Two guarded synthetic arenas verify the
expected reset state, guards, caller-register preservation, and fail-closed
no-mutation behavior for a mismatched binding.

Recorded host validation used:

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

The ARM64 goal-call ABI target build passed; focused `Arm64GoalCallAbi` CTest
passed 9/9; full CTest passed 47/47; and the direct compiler/emitter binary
passed 191/191. No iPhoneOS static-library rebuild was run because this
test-only patch did not change production library inputs. No application build,
runtime integration, signing, simulator, physical-device, or game-data proof
occurred. The next step is an audit of the smallest app/runtime integration
boundary before any production integration change.

## Checkpoint 21: pinned OpenGOAL reset composition in GOALPad

Parent commits `1c64426`, `b5922f5`, `d9910ab`, and `0b413b9` publish and pin
the dedicated fork, link the pinned production data-arena/invoker sources in
Xcode, correct the canonical fixture, and execute the generated
`load-state::reset!` Export1 through the production typed binding path inside
GOALPad.

The Checkpoint 21 OpenGOAL pin was:

```text
remote: https://github.com/zschwendi/jak-pad.git
branch: goalpad/arm64-aot-0044
commit: 9eecb9c3193ed8cb5175c9199cecbe9cfd2baa42
```

Validate the affected OpenGOAL target:

```sh
cmake --build \
  /private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup-build \
  --target arm64-goal-call-abi-test -j 4

ctest --test-dir \
  /private/tmp/GOALPadOpenGOAL-data-arena-symbol-value-lookup-build \
  -R '^Arm64GoalCallAbi\\.' --output-on-failure -j 1
```

The recorded corrected result is build exit `0` and 10/10 focused ABI cases.

Build and run the current host composition harness with the command in
“Validate the generated native export registry” above. Exit `0` is required.
Confirm the production composition symbols are linked:

```sh
xcrun nm -n -C /private/tmp/goalpad_pinned_runtime_composition_harness | \
  rg 'goalpad_aot_load_state_reset|jak1_data_arena_call_native_method1_arm64|invoke_data_arena_native_method1_arm64|invoke_data_arena_native_basic_method1'
```

Build the ARM64 macOS app:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/GOALPad-mac -jobs 4 \
  CODE_SIGNING_ALLOWED=NO ENABLE_PREVIEWS=NO ENABLE_DEBUG_DYLIB=NO build
```

Build and run only the approved M5 simulator:

```sh
goalpad_simulator=96C5C21A-B925-4213-82A3-90DCB8518339
goalpad_sim_app=/private/tmp/GOALPad-sim/Build/Products/Debug-iphonesimulator/GOALPad.app

xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$goalpad_simulator" \
  -derivedDataPath /private/tmp/GOALPad-sim -jobs 4 \
  CODE_SIGNING_ALLOWED=NO ENABLE_PREVIEWS=NO build

xcrun simctl boot "$goalpad_simulator"
xcrun simctl bootstatus "$goalpad_simulator" -b
xcrun simctl install "$goalpad_simulator" "$goalpad_sim_app"
xcrun simctl launch --terminate-running-process \
  "$goalpad_simulator" com.zephyrstudiosllc.GOALPad
xcrun simctl spawn "$goalpad_simulator" log show --last 2m --style compact \
  --predicate 'process == "GOALPad"' | \
  rg 'data-arena-bound load-state reset.*architecture=arm64; result=8194'
xcrun simctl io "$goalpad_simulator" screenshot \
  /private/tmp/GOALPad-data-arena-reset-M5.png
xcrun simctl shutdown "$goalpad_simulator"
```

The recorded launch PID was `99701`; the runtime message ended with:

```text
data-arena-bound load-state reset plus load-state symbol-value AOT proof verified; architecture=arm64; result=8194
```

The inspected screenshot
`/private/tmp/GOALPad-data-arena-reset-M5.png` has SHA-256
`45647e0001a53147b4c43ea0bb9a9f99866eff4c95e78848d210f070c824d2df`.
The simulator was confirmed `Shutdown` afterward.

Build the normally signed generic iOS Release app:

```sh
xcodebuild -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-device -jobs 4 \
  ENABLE_PREVIEWS=NO ENABLE_DEBUG_DYLIB=NO build
```

Inspect the current artifact:

```sh
goalpad_app=/private/tmp/GOALPad-device/Build/Products/Release-iphoneos/GOALPad.app
goalpad_binary="$goalpad_app/GOALPad"

file "$goalpad_binary"
xcrun lipo -archs "$goalpad_binary"
xcrun nm -n -C "$goalpad_binary" | \
  rg 'goalpad_aot_load_state_reset|jak1_data_arena_call_native_method1_arm64|invoke_data_arena_native_method1_arm64|invoke_data_arena_native_basic_method1'
xcrun llvm-objdump --macho --disassemble \
  --dis-symname _jak1_data_arena_call_native_method1_arm64 "$goalpad_binary"
xcrun otool -l "$goalpad_binary"
xcrun otool -L "$goalpad_binary"
find "$goalpad_app" -maxdepth 1 -type f \
  \( -name '*.dylib' -o -name '*.so' -o -name '*.bundle' \) -print
xcrun nm -u -C "$goalpad_binary" | \
  rg -i 'dlopen|dlsym|mmap|mprotect|pthread_jit'
strings -a -t x "$goalpad_binary" | \
  rg -i 'dlopen|dlsym|mmap|mprotect|pthread_jit|MAP_JIT|PROT_EXEC|executable.?memory|(^|[^[:alnum:]_])jit([^[:alnum:]_]|$)'
codesign --verify --deep --strict --verbose=4 "$goalpad_app"
codesign -d --verbose=4 "$goalpad_app"
codesign -d --entitlements - "$goalpad_app"
openssl smime -inform der -verify -noverify \
  -in "$goalpad_app/embedded.mobileprovision" \
  -out /private/tmp/GOALPad-runtime-composition-profile.plist
plutil -p /private/tmp/GOALPad-runtime-composition-profile.plist
shasum -a 256 "$goalpad_binary" "$goalpad_app/embedded.mobileprovision"
```

The recorded artifact is thin ARM64. Its executable and profile hashes are:

```text
f7fc6b8e5533105eeaa7fc3890701fb56e74ccefeea6f1d74ddf767ed26c7cd0  GOALPad
ef4a32f9aef6cca1709423e53e66518204e49a86af4d2752139de63d21244ad1  embedded.mobileprovision
```

The restricted trust-store check first returned `CSSMERR_TP_NOT_TRUSTED`; the
same strict verification rerun with read-only access to the host Keychain trust
store passed with `valid on disk` and `satisfies its Designated Requirement`.
There is no writable/executable Mach-O
segment, app-root dynamic library, dynamic-loading/JIT import, JIT string, JIT
entitlement, or unsigned-executable-memory entitlement. The profile is a local
Xcode-managed development profile and expires `2026-08-06T23:51:59Z`.

This validates synthetic runtime composition and the presence of the same code
in a normally signed generic iOS artifact. It is not physical-device execution,
live OpenGOAL initialization, Jak data loading, title-screen boot, gameplay, or
distribution evidence.

## Build the isolated Jak 1 raw-ISO preparation foundations

The first two raw-disc preparation phases deliberately build without the full
desktop decompiler/compiler dependency graph. Build and test the bounded ISO
reader on the host with:

```sh
cmake -S OpenGOAL -B /private/tmp/GOALPad-jak1-iso-reader -G Ninja \
  -DOPENGOAL_BUILD_SAFE_ISO_READER_ONLY=ON \
  -DBUILD_TESTING=ON \
  -DCMAKE_BUILD_TYPE=Debug
cmake --build /private/tmp/GOALPad-jak1-iso-reader -j 4
ctest --test-dir /private/tmp/GOALPad-jak1-iso-reader \
  --output-on-failure -j 1
```

Build the fail-closed Jak 1 revision validator with:

```sh
cmake -S OpenGOAL -B /private/tmp/GOALPad-jak1-iso-validation -G Ninja \
  -DOPENGOAL_BUILD_JAK1_ISO_VALIDATION_ONLY=ON \
  -DBUILD_TESTING=ON \
  -DCMAKE_BUILD_TYPE=Release
cmake --build /private/tmp/GOALPad-jak1-iso-validation -j 4
ctest --test-dir /private/tmp/GOALPad-jak1-iso-validation \
  --output-on-failure -j 1
```

The corresponding generic iPhoneOS compile proof is:

```sh
cmake -S OpenGOAL -B /private/tmp/GOALPad-jak1-iso-validation-ios -G Ninja \
  -DOPENGOAL_BUILD_JAK1_ISO_VALIDATION_ONLY=ON \
  -DBUILD_TESTING=OFF \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 \
  -DCMAKE_BUILD_TYPE=Release
cmake --build /private/tmp/GOALPad-jak1-iso-validation-ios \
  --target jak1-iso-validation -j 4
```

These isolated targets prove safe parsing, exact supported-revision validation,
staging ownership, and iPhoneOS compilation. They do not by themselves produce
`fr3/`, the flat runtime `iso/` directory, or a playable app import. The
integrated Checkpoint 50 Release path described below composes those later
phases while keeping the prepared-folder importer available.

## Checkpoint 50 importer and platform status

The checked `jak1-base-retail` graph/recipe/materializer is composed behind the
native producer and narrow Objective-C++ bridge. Release builds can select a
supported raw ISO or a standard ZIP32 archive containing exactly one ISO,
prepare a private candidate, validate it, and atomically activate it. Prepared
folders remain supported. The ZIP path streams stored or raw-DEFLATE content,
validates size and CRC-32, and rejects ZIP64, encryption, multidisk, ambiguous,
unsafe, unsupported, or corrupt archives without changing active data.
Build 187 coordinated the selected Files-provider URL and tolerated legal short
reads, but a physical retry showed that a stable provider-supplied descriptor can
still contain a tail with no valid ZIP end record. Build 189 instead holds an
ordinary coordinated read while copying every source byte into app-private
staging, then parses only that local file. The materialized ZIP is removed after
success, failure, or cancellation; bounded cleanup recognizes an exact
app-generated UUID suffix after an interrupted attempt. Privacy-safe diagnostics
record only byte counts, normalized error codes, and ZIP-tail structure facts.
A synthetic provider-placeholder fixture reproduces the reported
`ZIP end-of-directory record is missing` failure and verifies the local-copy path.
Build 191 adds a bounded chunked compatibility scan for an otherwise valid ZIP32 central
directory followed by nonstandard trailing data within the four-GiB ZIP32 archive limit. The directory
must still end exactly at the discovered end record, and all existing member,
path, compression, CRC, size, and expansion checks remain in force. Archives
over the ZIP32 size boundary remain rejected.

Focused raw-source, install-worker, ZIP, resource-staging, and composer checks
pass. A generic signed iOS Release build passed with the current 518-object AOT
corpus and verified public source pack. The Build 187 physical Files-provider ZIP
retry reproduced the missing-end-record failure; Build 189 physical import,
available-space behavior, throughput, and activation remain unrecorded,
non-blocking presentation/distribution evidence rather than Jak 1 gameplay or
Jak II continuation gates.

The Checkpoint 50 release preflight remains `518/10596/7`. The external public
source pack verifies as 518 objects, aggregate `f1770cae6287a359`, and
10,729,681 object bytes. The combined generic iOS Release build passed with:

```sh
xcodebuild -quiet -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-sim -jobs 2 \
  ENABLE_PREVIEWS=NO \
  GOALPAD_JAK1_SOURCE_OBJECT_PACK_ROOT=/private/tmp/GOALPad-jak1-source-pack-generated-g \
  GOALPAD_CCACHE_DIR=/private/tmp/GOALPad-ccache \
  GOALPAD_BUILD_JOBS=2 build
```

It produced a normally signed thin ARM64 app containing the ZIP64 rejection and
Merc-composition diagnostic paths. This is compilation, linking, and signing
evidence only; Checkpoint 50 did not install, launch, import, or validate
gameplay on a physical device.

## Checkpoint 51 Jak target/control provenance

The existing native Jak 1 bones observer now captures a bounded, read-only
snapshot of `*target*`, its `control`, and the selected `cpad` after validating
their runtime types, allocated sizes, and EE-memory spans. The snapshot retains
target state and attack identity, left-stick and button input, `turn-to-target`,
`dir-targ`, and `quat-for-control`. Metal attaches it only to the matching
`eichar-lod0` producer/output record and compares normalized +Z facings through
pad intent, GOAL control, render quaternion, and the Merc input root basis.

The tracker reports an active facing divergence only when stick speed and pad
magnitude are both at least `0.7` and intent versus control has a negative dot
product. It also retains a Square press edge or a consecutive target attack-ID
change as an attack-boundary observation. A Square edge can represent an
attempted input even when GOAL rejects the attack, so the retained button and
attack fields must be interpreted together. Repeated observations for the same
bone slot and engine frame are ignored without changing history.

The parent bridge preserves all v3 fields and the existing cache filename while
bumping the record to `v=4`. It adds current and session-total event,
divergence, and attack-boundary counts plus numeric first/last events with host
tick, chain, producer, input, facing, and dot-product evidence. New events
trigger the same bounded atomic persistence path as the earlier camera and Merc
diagnostics. No camera, control, animation, renderer, or frame-pacing behavior
is changed.

Focused validation passed:

```sh
cmake --build OpenGOAL/build/Release/bin \
  --target metal-merc-transform-trace-test -j2
OpenGOAL/build/Release/bin/game/metal-merc-transform-trace-test
./Scripts/run-merc-transform-diagnostics-check.sh
./Scripts/run-target-control-diagnostics-check.sh
xcrun swiftc -parse GOALPad/Game/GameSession.swift
```

The Metal trace executable passed all 50 checks, including duplicate-frame
suppression and unpoisoned next-frame history. The generic signed iOS Release
build passed against the unchanged verified 518-object source pack after Xcode
was allowed to use its existing provisioning profile. The resulting thin ARM64
executable has SHA-256
`4b776ea11fc0ed45eedb7669ec80a63f3a2634bfec203351dac057208c7f1445`;
`codesign` verifies it as valid and satisfying its designated requirement. No
device install, launch, gameplay capture, or timing measurement was performed.

## Checkpoint 52 reproducible Jak 1 build inputs

The app's raw-ISO and ZIP-contained-ISO routes now have a deterministic
synthetic integration check through candidate validation and atomic activation:

```sh
./Scripts/run-zip-iso-import-check.sh
```

The check proves that the old active install is preserved until the candidate
is valid, activation swaps the new data and preparation summary together, and
temporary staging is removed. It uses no retail data and does not claim a real
media import. Maintainer direction makes real-disc or real-ISO hardware import
a non-blocking presentation/distribution follow-up rather than a Jak 1 gameplay
or Jak II continuation gate.

Prepare the public Jak 1 source-object pack at its default ignored path with:

```sh
CMAKE_C_COMPILER_LAUNCHER=ccache \
  CMAKE_CXX_COMPILER_LAUNCHER=ccache \
  CCACHE_DIR=/private/tmp/GOALPad-ccache \
  GOALPAD_BUILD_JOBS=2 \
  Scripts/prepare-jak1-source-object-pack.sh
```

The script generates a missing pack in a same-parent staging directory,
verifies it, and publishes it atomically. It reverifies and reuses an existing
valid pack, removes private staging after failure, and refuses to replace an
existing corrupt final pack. Its deterministic regression is:

```sh
sh -n Scripts/prepare-jak1-source-object-pack.sh \
  Scripts/run-jak1-source-object-pack-preparation-check.sh
./Scripts/run-jak1-source-object-pack-preparation-check.sh
```

Canonical and exact-source clean-checkout generation both produced 518 source
objects, aggregate `f1770cae6287a359`, and 10,729,681 object bytes. Generated
AOT preflight passed with 518 objects, 10,596 emitted functions, and 7 native
functions.

From the clean non-symlink checkout at
`/Users/zach/Developer/OS_Projects/GOALPad/GP-clean-jak1-validation`, unsigned
Release builds passed for ARM64 macOS, the approved M5 iPad simulator, and
generic visionOS. Use a real workspace path for importer builds: Xcode
canonicalizes `/private/tmp` through `/tmp`, and the importer's source-root
safety check intentionally rejects that symlink path. The exact matrix commands
and products are recorded in `HANDOFF.md` Checkpoint 52. These builds are
compile/link evidence only; they are not simulator gameplay, physical-device,
visual, or real-media import proof.
