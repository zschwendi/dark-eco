# GOALPad

> **This project is based on the incredible work of the [OpenGOAL](https://github.com/open-goal/jak-project)
> team. This fork focuses on bringing Jak and Daxter to Apple's platforms,
> including iPad, macOS, and visionOS.**

GOALPad is a native ARM64 port of OpenGOAL for Apple platforms. The first
supported game is *Jak and Daxter: The Precursor Legacy*, using game data
supplied and prepared by the user.

**Eco** is the public App Store-facing product name; GOALPad remains the
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
  is the ARM64 code generator. The current checked Jak 1 corpus emits **10,631
  functions** this way; seven additional routines remain native (GOAL's cooperative
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
- **Implemented — additive controller, keyboard/mouse, and touch input;
  Experimental — complete hardware coverage.** GameController and screen input
  always merge into one pad on iPhone/iPad; recent controller activity may hide
  touch artwork but never disables its targets. The accepted touch scheme uses
  dynamic movement and fixed camera sticks, bounded face/crouch gestures,
  contextual face prompts, Zoom, Stats/SKIP, and Start/Pause/Resume. Physical
  controls are remappable; whole-stick roles and camera/movement tuning preserve
  exact default bytes. Keyboard defaults use WASD, mouse/trackpad camera, arrow
  face directions, Escape for Start/Pause, and Tab for Stats. Build 135 adds
  stale-touch cleanup and a same-finger speeder acceleration-to-brake gesture;
  its physical acceptance remains pending.
- **Implemented — title-scoped settings; Experimental — real multi-device
  convergence.** The player-facing Jak 1 document exposes Controls, Graphics,
  one combined iCloud block, save import/export and preserved-copy promotion,
  and pause-gated developer logs. Graphics defaults to Modern with **Fit to
  Screen**; Classic preserves the compatibility presentation. Old Controls,
  Audio, UI, and touch-layout fields remain decodable for iCloud compatibility
  but do not expose rejected Classic touch/editor UI. Settings and saves have
  independent per-device sync toggles, and a real two-device conflict/provider
  pass remains an external validation gate.
- **Experimental — iPad/iPhone.** Jak 1 boots, renders, and plays on physical
  Apple devices. Build 130 is the accepted unified baseline for the exercised
  gameplay, Graphics/Fit-to-Screen, touch, settings, and iCloud scope. Build 135
  is signed but not physically accepted. No checkpoint certifies a complete
  playthrough, every level transition, every controller, or every supported
  device.
- **Experimental — visionOS.** The shared Apple target runs the conventional
  Comfort window, and a synthetic Compositor Services proof validates per-view
  timing, transforms, projections, targets, and reverse depth. Real game stereo,
  tabletop, room-scale, first-person VR, and room-as-level play remain planned;
  see the [visionOS implementation manual](docs/VISIONOS_PRESENTATION_MODES_IMPLEMENTATION_MANUAL.md).
- **Experimental — macOS launcher.** The shared SwiftUI library, import flow,
  Metal surface, AOT runtime, and audio host build for Apple Silicon. A Release
  build imported prepared Jak 1 data and reached the title screen through the
  real runtime. Keyboard/mouse mappings exist, but a complete macOS gameplay
  and physical-input pass remain unvalidated.
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
iCloud Documents container; the runtime never plays from iCloud paths. Eco
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
compatible with desktop OpenGOAL rather than introducing an Eco save format.
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

Eco is an app by Zach Schwendiman, published by Zephyr Studios, and made
available free as a gift to fans of the Jak trilogy. Zach created the native
Apple mobile port and its platform-runtime integration.

Eco exists because of the [OpenGOAL](https://github.com/open-goal/jak-project)
project, which reimplemented the GOAL language, compiler, and runtime that
Naughty Dog built Jak and Daxter on. The compiler front end, GOAL source, object
and level formats, 989snd sound implementation, and renderer this port translates
are all their work. This fork adds an ARM64 ahead-of-time code path, a Metal
renderer, and Apple platform hosts on top of it.

Eco is an unofficial community project and is not affiliated with Sony
Interactive Entertainment, Naughty Dog, or the OpenGOAL team.

## Support

The launcher Support screen provides project information, contact details, and
three optional one-time StoreKit tips. Tips unlock no features or content. Their
product identifiers and App Store Connect requirements are documented in
[Eco optional tips](docs/appstore/STOREKIT_TIPS.md).
