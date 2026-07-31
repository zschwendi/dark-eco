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
- **Planned:** Compile representative OpenGOAL GOAL source into a build-time
  ARM64 artifact, link it into the application, and validate it in a signed
  physical-device build.

The current probe does not execute GOAL source, load Jak data, or boot the
OpenGOAL runtime.

See [Roadmap](ROADMAP.md) for the ten-stage path from the current probe to
playing Jak 1 on a signed physical iPad.

## Repository layout

```text
GOALPad/                 SwiftUI application and narrow native bridge
GOALPad.xcodeproj/       Application project
docs/                    Project policy and build documentation
OpenGOAL/                Pinned upstream source submodule
ROADMAP.md               Active implementation stages and exit gates
```

## Build

Initialize submodules, then follow [Building](docs/BUILDING.md). No retail game
data is required for the current build and compiler baselines.

## Content policy

Do not commit disc images, extracted retail files, prepared game packages,
signing identities, provisioning profiles, or secrets. Local game data and
prepared packages are ignored by default.
