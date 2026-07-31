# GOALPad

GOALPad is an early native ARM64 iPadOS platform port of
[OpenGOAL](https://github.com/open-goal/jak-project). The first supported game is
*Jak and Daxter: The Precursor Legacy*, using game data supplied and prepared by
the user.

The project is not a PS2 emulator, a Swift rewrite of OpenGOAL, or a source of
retail game data. See [Project Overview](docs/PROJECT_OVERVIEW.md) for the
binding architecture, scope, and content-separation rules.

## Current status

- **Implemented:** A SwiftUI application links Objective-C++ and C++ code and
  builds for ARM64 macOS, iOS Simulator, and generic iOS device destinations.
- **Experimental:** A statically linked ARM64 instruction probe verifies that
  executable code can be part of the normally signed application image.
- **Experimental:** The real OpenGOAL compiler compiles the initial top-level
  literal, the real Jak 1 `'#f` expression, and the complete real
  `false-func`, `true-func`, and `identity` definitions to deterministic ARM64
  assembly and guarded typed X-macro export metadata. The exact one-argument
  Jak 1 `lognot` definition compiles to `mvn x0, x0; ret`, exports through the
  guarded `Export1` lane, and executes through the existing signed X0 and
  X20/X21/X22 state boundary, returning the bitwise complement of its argument.
  The exact direct body of Jak 1
  `level-group-load-commands-set!` now compiles to a guarded two-argument
  `Export2` entry that stores the low 32 bits of X1 at X22 + X0 + `0x20`, then
  returns the full X1 value. GOALPad calls that checked-in static artifact only
  through a typed two-argument registry and wrapper, with two real synthetic
  X22 bases and whole-buffer guard checks. This is a direct defun-body proof;
  it does not install or dispatch the GOAL method. The compiler keeps its
  current GPR-only load guard and the store lowering is deliberately limited to
  this four-byte proof shape. The exact real Jak 1
  `load-state::want-vis` method body is now a second guarded Export2 entry. It
  stores the low 32 bits of its symbol argument at raw `vis-nick` field
  `#x24`, returns zero, and executes twice against separate aligned X22 bases
  while the app verifies exact stores, untouched guard bytes, and restored
  caller state. This proves only the direct method body; it does not install
  or dispatch `want-vis`. The complete real Jak 1
  `load-state::want-levels` body is now a distinct guarded three-argument
  `Export3` entry containing 142 deterministic ARM64 instructions. The host
  and app execute all six retained/replaced/duplicate/false argument cases
  against two inline `want` slots, with Jak 1 `#f` in X21, an aligned
  caller-owned arena in X22, whole-buffer equality, explicit canaries, and
  caller-register restoration. This remains a direct body proof; it does not
  install or dispatch `want-levels`. The complete real Jak 1
  `load-state::reset!` body is now a guarded one-argument `Export1` entry with
  58 deterministic ARM64 instructions (232 bytes). With X0 `this = 4`, Jak 1
  `#f` in X21, and two separate aligned X22 bases, the host and app proofs
  set all eight `want` words to `#f`, set `command-list` to the Jak 1
  empty-list value, write `#f` to all 256 `object-name` words, zero all 256
  `object-status` words, return the full `this` value, and verify the complete
  guarded arenas plus restored caller state. This is only the direct static
  method body; it does not install or dispatch `reset!`, initialize live GOAL
  globals, or boot the game.
  A separate zero-argument `load-state-value` artifact uses one signed 32-bit
  displacement in normal application data to read a 32-bit value cell at the
  Jak 1 symbol-table base in X21 plus that displacement and the X22 base. The
  app proof exercises zero, positive, and negative synthetic displacements,
  including a high-bit value and whole-arena guards, then restores the data
  cell. It proves the signed static code/data shape for the named
  `*load-state*` binding metadata only; it does not resolve a live runtime
  symbol or initialize a GOAL symbol table.
  GOALPad resolves the generated native entries through a small app-local
  registry; `true-func` returns X21 plus eight and `identity` receives its one
  object argument in Apple-ABI X0 only after that state is established. A
  host-only CMake artifact and serial dispatcher test now cover the exact
  maintained debug-only Jak 1 `glst-node-name` form. It performs a 32-bit field
  load from X22 + X0 + 8 against two logical X22 bases in one caller-owned
  arena, returning the zero-extended high-bit values `0x81234567` and
  `0xf2345678`. This is bounded host evidence for that exact field load, not a
  general ARM64 load or runtime claim. A direct iPhoneOS static archive also
  compiles the dispatcher and five generated entries, but is compatibility
  evidence only. The established app-local function/export checkpoint is
  verified on ARM64 macOS and the dedicated M5 simulator. The direct
  level-command, `want-vis`, complete `want-levels`, complete
  `load-state::reset!`, and `load-state-value` artifacts were also built on
  ARM64 macOS, run on the dedicated M5 simulator, and included in signed
  generic Release iOS builds.
  The Debug generic iOS build uses an Xcode
  Preview split bundle and is not no-JIT evidence. The Release build disables
  Preview/debug-dylib layout and contains a monolithic ARM64 executable, but
  is build/signing evidence only. Top-level GOAL symbol or method
  installation, live runtime initialization, relocation, and physical
  execution of the current AOT checkpoints remain pending.
- **Planned:** Initialize the full OpenGOAL runtime state, expand the ARM64
  compiler subset, and load user-prepared Jak 1 data.

The current proof executes intentionally narrow compiler-produced GOAL
workloads with synthetic state and guarded caller-owned memory. It does not
yet load Jak data or boot the general OpenGOAL runtime.

See [Roadmap](ROADMAP.md) for the ten-stage path from the current probe to
playing Jak 1 on a signed physical iPad.

## Repository layout

```text
GOALPad/                 SwiftUI application and narrow native bridge
GOALPad.xcodeproj/       Application project
docs/                    Project policy and build documentation
docs/APPLE_PLATFORM_DIRECTION.md
                         Future-facing Apple presentation constraints
OpenGOAL/                Pinned upstream source submodule
ROADMAP.md               Active implementation stages and exit gates
tests/native/             Deterministic signed-call boundary harnesses
```

## Build

Initialize submodules, then follow [Building](docs/BUILDING.md). No retail game
data is required for the current build and compiler baselines.

## Content policy

Do not commit disc images, extracted retail files, prepared game packages,
signing identities, provisioning profiles, or secrets. Local game data and
prepared packages are ignored by default.
