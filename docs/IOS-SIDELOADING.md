# Dark Eco for iPhone and iPad

Download the [experimental iOS/iPadOS Build 279 prerelease](https://github.com/zschwendi/dark-eco/releases/tag/ios-build279-preview).
The **2.0 / Build 279** package is
`DarkEco-iOS-2.0-build279-preview.ipa`. One native arm64 IPA supports both
iPhone and iPad on **iOS/iPadOS 26.5 or later**. It contains the app runtime and
reconstructed OpenGOAL code, with no retail game data.
Its device-family metadata is `1,2`; this is a physical-device build, not a
simulator app.

Build 279 is a **performance test candidate**. It corrects irregular-callback
time accounting in both games, preserves input across callbacks that run no
game step, and avoids presenting Jak II's intermediate catch-up frames while
still executing every game step and render pass. These changes passed focused
logic tests and synthetic Metal output checks; they are not yet confirmed to
resolve the reported stutter or persistent slowdown on a device.

Optional reports remain available through **Settings → Graphics → Developer
Logs**, enabled before starting a game. Reports appear in **Files → Dark Eco →
Diagnostics → jak1 or jak2**. Each title keeps one report that is replaced on the
next write. Developer Logs adds measurement overhead; leave it off for ordinary
play and smoothness comparisons.

[ProMotion stutter](https://github.com/zschwendi/dark-eco/issues/6) and
[Jak II persistent world slow motion](https://github.com/zschwendi/dark-eco/issues/10)
remain open. Library stutter has no proven cause or fix in this build. Those
issues contain the separate physical acceptance steps.
The timing recorder covers game frames and menus, not Library animation.
Start with **Graphics → ProMotion off** for 60 FPS, which was reported smooth
in earlier iPhone Air testing. This does not resolve the separate Jak II world
slowdown. Keep one ProMotion mode and resolution per game boot when recording.

Optional touch buttons, the internal-resolution selector, earlier Jak II
lookup-speed/Dark Jak/shadow repairs, and importer resources are retained.
A reported recipient import failure remains undiagnosed. Build 279 has not
been installed or tested on a physical device; recipient signing, fresh import,
gameplay and save-preserving refresh remain unverified for this package.

## Install with your own signing identity

1. Download the `.ipa` release asset and its `SHA256SUMS`; leave the IPA intact.
   GitHub's source-code ZIP is not an app installer.
2. Set up a sideloader that supports your device and native iOS IPAs. For
   [Apparition](https://github.com/illixion/Apparition#getting-started), install
   its desktop app on Windows, macOS or Linux. The first iPhone/iPad pairing
   uses a USB cable: unlock the device, select **Trust** if prompted and enter
   the device passcode. Vision Pro's Remote Devices pairing steps do not apply.
   On Windows, install/open [Apple Devices](https://support.apple.com/guide/devices-windows/welcome/windows)
   so the PC can recognize and trust the device. On Linux, `usbmuxd` must be
   installed and running; follow your distribution's package/service instructions.
3. Use **your own Apple Account** or your own eligible paid developer
   certificate and device provisioning profile. The maintainer never needs
   your password, verification codes, private key or certificate. Apparition's
   free-account sign-in currently needs a compatible external anisette service
   or supported Mac/macOS-VM source; its old Android-library/Linux Docker
   provider does not satisfy Apple's October 2026 change. Follow the
   [current anisette instructions](https://github.com/illixion/Apparition#anisette).
   The shared guide has the same [Windows startup](SIDELOADING.md#1-download-and-open-apparition-on-windows)
   and [anisette/sign-in steps](SIDELOADING.md#3-set-the-anisette-server-then-sign-in).
   Replace its Vision Pro pairing instructions with the USB trust step above.
4. Install Apparition on the device and complete its connection/signing setup.
   Enable **Settings → Privacy & Security → Developer Mode** and trust your
   developer identity under **Settings → General → VPN & Device Management**
   if prompted. Keep its desktop companion reachable for this setup.
   Use the shared guide's [Companion setup](SIDELOADING.md#4-install-apparition-on-the-headset)
   on your iPhone/iPad; its references to the headset mean your device here.
5. Download the Dark Eco IPA in device Safari, then choose
   **Apparition → Library → Install from a File**. Select the IPA from Files,
   review the app/signing choice and confirm installation. This adds the app
   to Apparition's managed library for refreshes.
6. Open **Dark Eco** normally from the Home Screen. **Launch with JIT is not
   required:** its game code is compiled ahead of time.

You can instead install from the desktop with **Install something else →
Advanced → An app file**, selecting the Dark Eco IPA before choosing
**Install**. Apps installed this way are not automatically managed by the
device library. Renew that installation from the PC using the same
account and App ID, keeping existing app data. An entry under **Other Apps**
or a **Launch with JIT** button does not establish managed refresh.

## Supply your game data

Start with Jak and Daxter: The Precursor Legacy. Use your own **SCUS-97124
NTSC v1 Black Label** disc image. The importer accepts the ISO, a ZIP/7z
containing one supported ISO, or a prepared folder with the expected `iso/`
and `fr3/` data. Renaming another revision does not make it compatible.

Put the input in Files on the device and download cloud files completely.
Open **Dark Eco → Library → Jak and Daxter → Set Up Game Data → Continue →
Choose game data…**. Keep the app open until import and validation finish;
allow storage for both the input and imported data. Jak II remains experimental
and still needs gameplay validation of its latest repairs. Do not upload retail
files or saves to GitHub.

To try explicit touch buttons, open **Settings → Controls → Touch Actions →
Buttons**. Gestures remain the default. This setting replaces action swipes with
Cross, Square, Circle, Triangle and L1 while keeping movement and camera sticks.
Use landscape orientation for this preview; portrait and extreme custom stick
placements still need ergonomic testing.

## Keep the app and saves

Free-account signing normally expires after **seven days**. Refresh managed
apps in Apparition before expiry, or re-sign/reinstall a desktop-installed
copy with the same identity and App ID. Do not uninstall merely to renew it.
Free signing allows three active apps per device, including the sideloader;
account App ID and certificate limits also apply.

This package uses **local saves**. It removes the maintainer's iCloud
entitlements and provisioning profile. Back up saves before updating or
changing signers; a different App ID can create a separate app and save
container. Check that a new save survives closing and reopening the app.

The original app did not request increased-memory-limit, extended-virtual-
addressing or JIT entitlements. The repack does not remove a required memory
capability. Its ad-hoc transport signature must still be replaced by your
sideloader's signature for your device.

Build 279's exact compiled source is [app `3ed4df9`](https://github.com/zschwendi/dark-eco/commit/3ed4df9c2571cf8be81730d61e783539c242d1b7)
and [engine `32dc7d80`](https://github.com/zschwendi/jak-pad/commit/32dc7d8039751d26e1eb9aad7987cfc2488c0fb9).
Original hashes, changes and limitations are recorded in
[IPA-IOS279-PROVENANCE.json](IPA-IOS279-PROVENANCE.json). The release includes
the complete package manifest and checksum. Local package checks are not
physical-device or gameplay acceptance.
