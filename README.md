# GOALPad

> **This project is based on the incredible work of the [OpenGOAL](https://github.com/open-goal/jak-project)
> team. This fork focuses on bringing Jak and Daxter to Apple's platforms,
> including iPad, macOS, and visionOS.**

GOALPad is a native ARM64 port of OpenGOAL for Apple platforms. The first
supported game is *Jak and Daxter: The Precursor Legacy*, using game data
supplied and prepared by the user.

It is not a PS2 emulator, not a Swift rewrite of OpenGOAL, and not a source of
retail game data. See [Project Overview](docs/PROJECT_OVERVIEW.md) for the
binding architecture, scope, and content-separation rules.

## Current status

**The game runs.** Jak 1 boots, plays, and renders natively on Apple Silicon —
all executable GOAL code is compiled ahead of time and shipped inside the
normally signed application. There is no JIT, no writable-executable memory, and
no private entitlement anywhere in the build.

- **Implemented — compiler.** An AOT backend emits C from the GOAL IR so clang
  is the ARM64 code generator. **10,595 of Jak 1's 10,601 functions** compile
  this way; the remaining handful are hand-written ARM64 (GOAL's cooperative
  thread, catch-frame and state-entry routines, which manipulate the machine
  stack directly). All 518 object files compile for `arm64-apple-ios`.
- **Implemented — runtime.** The real OpenGOAL kernel initializes real heaps, a
  real symbol table and the real type system, loads the player's own DGO
  archives through GOAL's own loader, and runs `kernel-dispatcher` — the game's
  own main loop — indefinitely.
- **Implemented — renderer.** A Metal backend behind OpenGOAL's existing
  `GfxRendererModule` seam: sky, DirectRenderer, sprites, tfrag/tie/shrub world
  geometry, ocean, Merc characters, eyes, Generic2 and shadows. Shaders are
  compiled at build time and embedded; nothing is compiled at runtime.
- **Implemented — audio.** Upstream's 989snd sequencer and sound banks, driven
  through the real sound RPC, with a host-supplied output seam (CoreAudio on
  macOS, AVAudioEngine on iPadOS).
- **Implemented — input.** A narrow pad seam with no windowing dependency. A
  DualSense over SDL on macOS, GameController plus on-screen touch controls on
  iPadOS.
- **Experimental — iPad.** The game boots, renders and plays on the iPad
  simulator at 60 fps. **The physical device gate is still open**: nothing here
  is evidence of behaviour on real iPadOS hardware.
- **Planned.** Level streaming without frame stalls, streamed cutscene audio,
  the remaining fidelity renderers (TIE wind, depth cue, sprite distort/glow),
  and visionOS presentation.

Known issues and honest limits are tracked in `HANDOFF.md`.

## Architecture

One shared core, two thin hosts:

```text
game/kernel/core/          portable runtime: no SDL, no windowing, no input,
                           no audio backend, no graphics API
    + Metal renderer       behind OpenGOAL's GfxRendererModule seam
          |
          +-- goalpad-play     SDL window, SDL gamepad, CoreAudio    -> macOS
          +-- GOALPad.app      SwiftUI, CAMetalLayer, GameController,
                               AVAudioEngine, touch controls          -> iPadOS
```

Hosts meet the engine only at small C seams — `goal_pad_set_state`,
`goal_sound_pull_audio`, `goal_kernel_core_set_data_directory`, and the
`goal_gfx_host` table — so neither platform is privileged and a third
(visionOS) needs no engine changes.

## Repository layout

```text
GOALPad/                 SwiftUI application and narrow native bridge
GOALPad-Info.plist       Partial Info.plist: Files/Finder access to the game directory
GOALPad.xcodeproj/       Application project
Scripts/                 AOT generation and Metal shader compilation
docs/                    Project policy and build documentation
OpenGOAL/                Pinned OpenGOAL fork submodule
HANDOFF.md               Current state, open bugs, and next steps
ROADMAP.md               Implementation stages and exit gates
tests/native/            Deterministic signed-call boundary harnesses
```

## Build

Initialize submodules, then follow [Building](docs/BUILDING.md).

## Game data

GOALPad ships no game data and never will. Players supply their own legally
obtained copy of *Jak and Daxter: The Precursor Legacy* and prepare it with
OpenGOAL's own extraction tooling; see
[the data pipeline](docs/setup/jak1-data-pipeline-macos-arm64.md). On iPadOS the
prepared data is placed in the app's Documents directory via Finder or the Files
app.

## Content policy

Do not commit disc images, extracted retail files, prepared game packages,
signing identities, provisioning profiles, or secrets. Local game data and
prepared packages are ignored by default.

## Credits

GOALPad exists because of the [OpenGOAL](https://github.com/open-goal/jak-project)
project, which reimplemented the GOAL language, compiler, and runtime that Naughty
Dog built Jak and Daxter on. The compiler front end, the GOAL source, the object
and level formats, the 989snd sound implementation, and the renderer this port
translates are all their work. This fork adds an ARM64 ahead-of-time code path, a
Metal renderer, and Apple platform hosts on top of it.
