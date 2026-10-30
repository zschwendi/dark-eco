**[Download the IPA / install without a Mac](docs/SIDELOADING.md)**

# Install Dark Eco on Apple Vision Pro

Dark Eco runs **Jak and Daxter** natively on Apple
Vision Pro using [OpenGOAL](https://github.com/open-goal/jak-project), the
pinned [jak-pad](https://github.com/zschwendi/jak-pad) engine fork, and a
native Apple app with Metal graphics. You supply your own game data.

This guide covers the public **`v2.0` source and its ordinary 2D game window**.
The experimental immersive Jak and Daxter build shown in the README is developed
separately and is not enabled by these build steps.

## Requirements

- An Apple silicon Mac with full Xcode and a visionOS SDK capable of building
  the project's **visionOS 26.5** deployment target.
- Apple Vision Pro on **visionOS 26.5 or later**, paired with Xcode, with
  Developer Mode enabled.
- Your own Apple development signing team and app identifier. The checked-in
  app requests iCloud Documents; use a team and provisioning profile that
  support that capability. The maintainer's identifiers cannot be reused by
  another team.
- Git, CMake, Ninja, go-task, and OpenSSL 3. With Homebrew:

  ```sh
  brew install cmake ninja go-task openssl@3
  ```

- A compatible gamepad, such as DualSense.
- A supported PlayStation 2 copy of Jak and Daxter, and storage for your source data,
  prepared data, and build products. Import needs additional temporary space;
  keep the app's storage checks enabled.

## Your game files

The repository supplies no game assets and does not download them. Prepare
an image from your own compatible disc, or bring compatible data already
prepared by OpenGOAL. The current on-device Jak and Daxter disc-preparation route
accepts **SCUS-97124, NTSC v1 / Black Label**.

After installing the app, choose **Jak and Daxter** in the Library, then
**Set Up Game Data → Continue → Choose game data…**. Select one of the formats
offered by your build:

- A supported ISO, or a ZIP/7z containing exactly one supported ISO.
- A prepared Jak and Daxter folder containing the matching `iso/` and `fr3/`
  directories from OpenGOAL's preparation output.

Keep Dark Eco in the foreground until preparation and verification finish.
The app reports unsupported revisions and missing files; renaming an archive
does not make an unsupported source compatible. The imported game data belongs
in the app's `Documents/Jak1/iso` and `Documents/Jak1/fr3` directories; the
importer handles that placement. Select **Play Now** when setup succeeds.

See [game-data setup](README.md#2-add-your-game-data) and
[game data on the device](docs/BUILDING.md#game-data-on-the-device) for details.

## Build from an existing checkout

Start in the root of the checkout supplied by the AVP Ports Index. Its clone
command selects the commit that was scanned. Keep that commit and its pinned
submodule revision; do not pull a newer branch or follow a second clone step
while building the scanned source.

Initialize the pinned OpenGOAL dependency, then generate the public source
pack and ahead-of-time code for Jak and Daxter. Run these commands sequentially:

```sh
git submodule sync -- OpenGOAL
git submodule update --init --recursive
Scripts/prepare-jak1-source-object-pack.sh
Scripts/generate-jak1-aot.sh "$PWD/OpenGOAL/build/Release/bin"
open GOALPad.xcodeproj
```

The source pack and generated code come from the pinned open-source engine;
they are separate from your retail game assets. The first build compiles the
host tools and can take substantial time. Wait for each command to succeed.
Use a normal local checkout path; the preparation scripts reject unsafe
symlink paths.

In Xcode:

1. Select the **GOALPad** scheme. The installed product is **Dark Eco**.
2. Add your Apple account under **Xcode → Settings → Accounts**. In the
   GOALPad target's **Signing & Capabilities**, choose your Team and a unique
   bundle identifier you control, with automatic signing enabled.
3. Configure **iCloud → iCloud Documents** with a container registered to your
   team. Replace both container identifiers in
   [`GOALPad/GOALPad.entitlements`](GOALPad/GOALPad.entitlements) with your own
   container. The app resolves its provisioned default container. Keep the
   same team, bundle ID, and container for future updates.
4. Allow Xcode to resolve the project's package dependencies. Under
   **Product → Scheme → Edit Scheme → Run → Info**, use **Release** for play.

The [build reference](docs/BUILDING.md) has additional source-generation and
platform notes. Historical checkpoint commands in that document describe
earlier builds; the checked-out submodule pin remains authoritative.

## Install and play

1. Pair the headset in Xcode's device manager, accept the trust prompts, and
   enable Developer Mode on Vision Pro when requested.
2. Select your **physical Vision Pro** as the GOALPad scheme's destination.
   Build and Run to sign, install, and launch your copy.
3. Complete the game-data import above. Pair your controller in the headset's
   Bluetooth settings before starting the game.
4. Play in the ordinary window. On a PlayStation-layout controller,
   **Cross jumps, Square punches, and Circle spins** in Jak and Daxter. Use the game's
   menus for saving and loading.

Before updating an existing installation, export a save backup through
Settings. Install over the existing app with the same signing identity and
bundle ID; uninstalling removes its local data. Optional iCloud sync requires
the correctly provisioned container; it does not transfer your game assets.

## Current limits and troubleshooting

- **Immersive mode:** the public `v2.0` build above uses the conventional
  window. Dormant stereo code and footage of a separate experimental build do
  not enable immersive play in this checkout.
- **Missing AOT/source-pack error:** finish the preparation and generation
  commands before building. Source alone is not a complete app build.
- **Signing or iCloud error:** check your own Team, bundle ID, container, and
  device provisioning. Do not use the maintainer's profile or identifiers.
- **Rejected game data:** use the supported disc revision or compatible
  prepared Jak and Daxter data. Keep the original source until import succeeds.
- **Game compatibility:** Jak and Daxter is playable, but a full-game completion pass
  is not certified. Follow the [current support notes](README.md#game-support).

For a reproducible problem, include the source commit, headset/OS, and exact
error in the [issue tracker](https://github.com/zschwendi/dark-eco/issues).
Keep game files, saves, signing material, and personal information private.
