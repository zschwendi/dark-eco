# Dark Eco (GOALPad)

> **Dark Eco is built on the incredible work of the [OpenGOAL](https://github.com/open-goal/jak-project)
> team.** This fork brings OpenGOAL to Apple platforms: iPad, Mac, and
> Apple Vision Pro.

**Dark Eco** is the public name. **GOALPad** is the repository, Xcode target,
and internal runtime name. It is a native ARM64 port of OpenGOAL. It is not a PS2
emulator, not a Swift rewrite, and not a source of game data. The binding
architecture and scope rules live in the [Project Overview](docs/PROJECT_OVERVIEW.md).

## Status

| Game | State |
| --- | --- |
| *Jak and Daxter: The Precursor Legacy* | Conventional windowed gameplay physically exercised on iPad and Vision Pro; the macOS app also builds and reaches the title screen. Full-game completion is not certified. |
| *Jak II* | Experimental. The [ordinary rendering, asset and audio baseline](docs/JAK2_ORDINARY_GATE_2026_10_26.md) is validated in the isolated iPad simulator and ready for immersion work. The maintainer handles broad gameplay verification. |
| *Jak 3* | Planned. |

Ordinary play supports a game controller. iPadOS also has touch controls, and
macOS has keyboard/mouse input. The conventional visionOS path uses a controller.

### Development sequence

1. Ordinary Jak II rendering, assets, and audio baseline — complete within the documented simulator scope.
2. Add Jak II immersion on Apple Vision Pro.
3. Finish ordinary Jak 3.
4. Add Jak 3 immersion.

Throughout, the accepted Jak 1 conventional baseline and per-title isolation are
preserved. Planned Jak II/Jak 3 immersion requires a standard DualSense
controller; existing ordinary touch
and keyboard paths stay available where supported. The maintainer owns broad
gameplay verification; this sequence does not require agents to complete every
mission, combat encounter, vehicle route, or checkpoint before immersion work.

A separate, opt-in **experimental Jak 1 immersive mode** is being tested by the
maintainer on Vision Pro in a separate source/build lane. Wearer acceptance is
still pending, and known visual gaps remain. Check the notes for a specific build
for availability; a canonical windowed build does not imply immersive support.
This experiment does not mean any step above is complete.

## Getting Dark Eco

The distribution path is GitHub-only source and normally signed release
artifacts, installed through supported sideloading when a build is published. It is not on the App Store or
TestFlight. All executable game code is compiled ahead of time into the signed
app: no JIT, no writable-executable memory, no private entitlements.

For an available signed release, follow that release's platform-specific
installation instructions. Otherwise, build from source: initialize the
submodules and follow
[Building](docs/BUILDING.md) (start with *Current product and branch*: build the
`GOALPad` scheme from branch `v2.0`). The older
[iOS Build and Archive](docs/IOS_BUILD_AND_ARCHIVE.md) runbook is useful for
host-artifact steps, but parts of it still describe the retired App Store
archive flow.

## Playing

Dark Eco never includes or downloads game data. You supply your own legally
obtained copy.

1. Open Dark Eco and choose a supported game in the **Library**. If prompted
   with **Set Up Game Data**, choose **Continue**.
2. Tap **Choose game data…** and select your own copy of the game:
   - In builds where disc preparation is enabled for that game: a supported
     **ISO**, or a **ZIP or 7z containing exactly one ISO**.
   - Alternatively: a compatible **prepared game data folder** (OpenGOAL's extracted
     `iso/` and `fr3/` output, or the folder that contains them).

   The setup screen lists exactly which sources the current build accepts.
3. Wait while Dark Eco prepares, validates, and imports the data on your device.
   **Keep Dark Eco open and in the foreground until setup finishes.**
4. Tap **Play Now**.

Prepared data is stored in the Dark Eco folder on your device. Keep that copy.
After setup completes, the original ISO, archive, or prepared source folder is
no longer needed by Dark Eco.

## Saves

Saves use OpenGOAL's desktop-compatible memory-card files, kept separately for
each game. Optional **iCloud Saves** mirrors them between your devices; gameplay
always runs from local copies and continues offline. Settings also offers
**Import Saves** and **Export Saves** for moving saves to or from desktop
OpenGOAL in its unchanged layout. Details are in the
[Project Overview](docs/PROJECT_OVERVIEW.md).

## Repository layout

```text
GOALPad/                 SwiftUI application and narrow native bridge
GOALPad.xcodeproj/       Application project
Scripts/                 AOT generation and Metal shader compilation
docs/                    Project policy and build documentation
OpenGOAL/                Pinned OpenGOAL fork submodule
HANDOFF.md               Current state, open bugs, and next steps
ROADMAP.md               Development sequence and stage history
tests/native/            Deterministic native harnesses
```

## Content policy

Do not commit disc images, extracted retail files, prepared game packages,
signing identities, provisioning profiles, or secrets.

## Credits

Dark Eco is an app by Zach Schwendiman, published by Zephyr Studios, and made
available free as a gift to fans of the Jak trilogy.

Dark Eco exists because of the [OpenGOAL](https://github.com/open-goal/jak-project)
project, which reimplemented the GOAL language, compiler, and runtime that
Naughty Dog built the Jak games on. The compiler front end, GOAL source, object
and level formats, 989snd sound implementation, and renderer this port builds on
are all their work. This fork adds an ARM64 ahead-of-time code path, a Metal
renderer, and Apple platform hosts.

Dark Eco is an unofficial community project and is not affiliated with Sony
Interactive Entertainment, Naughty Dog, or the OpenGOAL team.
