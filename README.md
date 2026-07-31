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
  assembly and guarded typed X-macro export metadata. GOALPad resolves the
  generated native entries through a small app-local registry, then executes
  them through static X20/X21/X22 state boundaries; `true-func` returns X21
  plus eight and `identity` receives its one object argument in Apple-ABI X0
  only after that state is established. The literal is verified on a physical
  iPad Pro M5; this function/export checkpoint is verified on ARM64 macOS and
  the dedicated M5 simulator and is present in a normally signed generic iOS
  build. It is build-time native binding only: top-level GOAL symbol
  installation, live GOAL runtime state, and physical execution of this
  checkpoint remain pending.
- **Planned:** Initialize the full OpenGOAL runtime state, expand the ARM64
  compiler subset, and load user-prepared Jak 1 data.

The current proof executes intentionally narrow compiler-produced GOAL
workloads with synthetic, non-dereferenced state values. It does not yet load
Jak data or boot the general OpenGOAL runtime.

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
