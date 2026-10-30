# Dark Eco for iPhone and iPad

Download the [experimental iOS/iPadOS Build 277 prerelease](https://github.com/zschwendi/dark-eco/releases/tag/ios-build277-preview).
The **2.0 / Build 277** package is
`DarkEco-iOS-2.0-build277-preview.ipa`. One native arm64 IPA supports both
iPhone and iPad on **iOS/iPadOS 26.5 or later**. It contains the app runtime and
reconstructed OpenGOAL code, with no retail game data.
Its device-family metadata is `1,2`; this is a physical-device build, not a
simulator app.

This native build adds **Graphics → Internal Resolution** alongside optional
on-screen face buttons. It includes the current
Jak II lookup-speed, Dark Jak allocation and shadow-rendering repairs, and
updated OpenGOAL importer resources. The Jak II repairs still need physical
gameplay acceptance; this is an experimental preview. A reported third-party
import failure has not been reproduced or diagnosed. Recipient signing, fresh
game import, gameplay and save-preserving refresh remain unverified.

**Known performance issue:** Jak 1 can microstutter with ProMotion enabled.
Start with **Graphics → ProMotion off** for 60 FPS, which was reported smooth
in current iPhone Air testing. Build 277 does not fix the 120 Hz issue.
Normal launches leave the optional developer timing recorder disabled.

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

Build 277's exact compiled source is [app `9277ff1`](https://github.com/zschwendi/dark-eco/commit/9277ff1edb41790e83a405422bd1f27aa81f54de)
and [engine `9088ff7a`](https://github.com/zschwendi/jak-pad/commit/9088ff7a252c8b48e01da39afd23e4a09b4b0435).
Original hashes, changes and limitations are recorded in
[IPA-IOS277-PROVENANCE.json](IPA-IOS277-PROVENANCE.json). The release includes
the complete package manifest and checksum. Local package checks are not
physical-device or gameplay acceptance.
