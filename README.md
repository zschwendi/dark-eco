# GOALPad

> **This project is based on the incredible work of the [OpenGOAL](https://github.com/open-goal/jak-project)
> team. This fork focuses on bringing Jak and Daxter to Apple's platforms,
> including iPad, macOS, and visionOS.**

GOALPad is a native ARM64 port of OpenGOAL for Apple platforms. The first
supported game is *Jak and Daxter: The Precursor Legacy*, using game data
supplied and prepared by the user.

**Eco Pro** is the public App Store-facing product name; GOALPad remains the
repository, Xcode target, and internal runtime name.

It is not a PS2 emulator, not a Swift rewrite of OpenGOAL, and not a source of
retail game data. See [Project Overview](docs/PROJECT_OVERVIEW.md) for the
binding architecture, scope, and content-separation rules.

## Current status

**The game runs.** Jak 1 boots, plays, and renders natively on Apple Silicon —
all executable GOAL code is compiled ahead of time and shipped inside the
normally signed application. There is no JIT, no writable-executable memory, and
no private entitlement anywhere in the build.

- **Implemented — compiler.** An AOT backend emits C from the GOAL IR so clang
  is the ARM64 code generator. **10,596 of Jak 1's 10,603 functions** compile
  this way; the remaining seven are native routines (GOAL's cooperative
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
- **Implemented — controller input; Experimental — touch input.** A narrow pad
  seam with no windowing dependency. A DualSense uses SDL on macOS;
  GameController and the on-screen controls merge into one pad on iPadOS. The
  current Classic Mode touch layout creates the movement stick under the first
  left-half contact, keeps a continuous analog R stick at bottom right, and
  maps right-half swipes to Cross, Square, Circle, or held L1. Reversing an L1
  swipe upward adds Cross; short taps are deliberately inert. The deterministic
  host check and macOS/iOS builds pass, and the named M5 simulator launches.
  Physical multitouch ergonomics remain unvalidated. Diagnostics and resolution
  controls remain hidden behind the three-line menu button.
- **Experimental — iPad.** Jak 1 boots, renders, and plays on physical iPad. A
  forced fixed-step camera experiment was rejected on hardware and removed;
  current source instead requests fixed 60 Hz callbacks and independently
  rounds each display-target interval to Jak's integral 1-through-4 frame
  ratio. Deterministic checks, the named M5 simulator, signed
  physical launch, and real kernel/audio boot path pass. The Checkpoint 37 run
  reached the farthest gameplay yet, but was physically rejected: camera and
  depth fighting felt worse than Checkpoint 36, Merc deformation remained, and
  metallic materials gained a new flicker. The physical build retains the iOS
  MIPS2C bones compatibility path and Jak 1's homogeneous-W parity correction,
  but neither is presented as a complete deformation fix.
- **Experimental — visionOS.** The shared Apple target builds and launches in a
  conventional SwiftUI window. No immersive or volumetric presentation is
  included, and physical-headset gameplay remains unvalidated.
- **Experimental — macOS launcher.** The shared SwiftUI library, import flow,
  Metal surface, AOT runtime, and audio host build for Apple Silicon. A Release
  build imported prepared Jak 1 data and reached the title screen through the
  real runtime. A controller is still required for gameplay; keyboard mapping
  and a complete macOS gameplay pass remain unvalidated.
- **Planned.** Level streaming without frame stalls, streamed cutscene audio,
  and the remaining fidelity renderers (TIE wind, depth cue, sprite
  distort/glow).

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
                               AVAudioEngine                          -> macOS
                               + touch controls                       -> iPadOS
                                                                   -> visionOS window
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

## Saves

Gameplay uses OpenGOAL's desktop-compatible memcard files under Application
Support. The optional iCloud Saves setting mirrors those files into the app's
iCloud Documents container; the runtime never plays from iCloud paths. Eco Pro
treats OpenGOAL's alternating bank pairs as complete save slots, selects the
generation OpenGOAL's loader would use, and compares its checksummed completion
percentage. The farther valid slot wins as a unit, so banks from different
devices cannot form a hybrid save. A loadable valid slot always beats a corrupt
or unsupported peer. Slots where neither copy validates, and valid slots with
equal progress, use the newest modification date. Hashes identify equal bytes
but never rank saves. Divergent originals are archived locally and in iCloud
before the winning pair becomes canonical. Pair changes then use a durable,
phased intent containing the immutable source banks; restart recovery proceeds
only when the target and recorded phase match exactly. A committed local-target
intent can finish from its embedded banks while iCloud is unavailable or an
account changes; a cloud-target intent can instead be abandoned because the local
canonical source remains intact. A naturally missing odd bank without that intent
remains ordinary divergence and is ranked and reported. Save operations are FIFO
exclusive, and gameplay stays paused when unsafe local recovery cannot finish.
Launch and foreground syncs run while
gameplay is paused and may merge in either direction. Syncs triggered by completed
gameplay frames are upload-only: they archive a divergent iCloud pair before
mirroring the active local pair and never replace a local bank. Settings retains
the latest automatic-resolution details until they are replaced or dismissed,
without presenting them over gameplay.

Settings also provides **Import Saves** and **Export Saves**. These actions copy
the unchanged desktop layout under `OpenGOAL/jak1/saves`, so transfers remain
compatible with desktop OpenGOAL rather than introducing an Eco Pro save format.
Import accepts only the exact `OpenGOAL/jak1/saves` directory with its single
`BASCUS-97124AYBABTU!` slot, or that exact slot directory itself. Banks must be
direct children, use the raw `bank0.bin` through `bank7.bin` names and sizes, and
include at least one loadable Jak 1 pair that passes complete validation.

The mirror is implemented with Apple's standard iCloud Documents entitlements;
no CloudKit database or private entitlement is used. The canonical project now
wires the selected paid-team app identifier and private container. Signed
provisioning and real cross-device transfer remain validation gates; when
iCloud is unavailable, gameplay continues on local saves.

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
