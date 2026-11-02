# Dark Eco for iPhone and iPad

Download the [experimental Build 286 prerelease](https://github.com/zschwendi/dark-eco/releases/tag/build286-preview).
The **2.0 / Build 286** iPhone/iPad package is
[`DarkEco-iOS-2.0-build286-preview.ipa`](https://github.com/zschwendi/dark-eco/releases/download/build286-preview/DarkEco-iOS-2.0-build286-preview.ipa).
One native arm64 IPA supports iPhone and iPad on **iOS/iPadOS 26.5 or later**.
It contains the app runtime and reconstructed OpenGOAL code, with no retail
game data. You supply your own game data and signing identity.

Build 286 is built from the one shared Apple source and build number that also
produces the separate Vision Pro package in the same release. Use the iOS IPA;
the visionOS IPA cannot substitute for it. No physical Build 286 tests have
been performed; the [Build 286 provenance](IPA-IOS286-PROVENANCE.json) records
its package checks and limits. See the [Build 286 validation](BUILD286-VALIDATION.md)
for exact checks and scoped simulator observations.

**ProMotion defaults to off (60 FPS)** for new or reset settings. Existing
explicit choices are preserved. You can opt into ProMotion in Graphics, but
the reported 120 Hz stutter is still unresolved.

**Fit to Screen** now fills the entire display in portrait and landscape. It
extends the camera's view with the matching projection instead of stretching
or narrowing the landscape picture. Turning Fit to Screen off keeps the
classic 4:3 picture. Presentation can still differ between devices.

**Build 286 portrait text:** default game text is smaller in conventional
iPhone/iPad Fit to Screen portrait, with the same anchor positions. Landscape,
Fit to Screen off, Mac and Vision Pro keep their existing font scale.
In an isolated Duo simulator, title/load-menu text was smaller at the same
anchors, an existing Geyser Rock save loaded, and a pause view rendered.
Build 286 has not had an Air visual check or physical-device testing.
Existing valid imports do not need re-importing for this font-code update.

iOS, iOS simulator, macOS and visionOS builds passed. Both native ABI checks
and both source-pack checks passed; these do not establish full gameplay,
performance or hardware acceptance. Exact results belong to the
[Build 286 validation record](BUILD286-VALIDATION.md).

**Experimental Duo laptop layout:** on iOS/iPadOS 27.1 or later, when the
device reports a partially open hinge and the app is in a portrait interface,
gameplay fills the upper half and the touch controls sit on a black lower
half. Fully opening the hinge restores normal full-screen play. The layout is
automatic, with no setting; unsupported OS versions, devices without a hinge
and unknown hinge states use the normal presentation. Physical-device, performance and full-game validation remain pending.

Build 286, like Build 282 before it, keeps Build 281's correction of a vertical flip when Jak II samples the rendered world for
a distortion effect. The old shader fails the focused top/bottom image test;
the corrected shader passes. This is a **test candidate**: it does not yet
establish a fix for the reported dark water plane or long coloured streaks.

It retains Build 280's ISO/archive picker compatibility, corrected Jak II
importer resources, saved Fit to Screen at game start for both titles,
Jak II pause-background sizing and idle display-loop changes. The Duo
simulator picker/invalid-disc checks were performed on Build 280. Importer
source was unchanged for Build 282; recipient-device selection and full
import acceptance remain pending. See [Build 280 validation](BUILD280-VALIDATION.md).

For the earlier Build 281 package, signed iOS, simulator, macOS and visionOS
build checks passed, along with four focused native GPU/plan tests. No
simulator gameplay tests or physical Build 281 tests were performed. See the
[Build 281 validation results](BUILD281-VALIDATION.md).

**Still open:** [ProMotion slowdown](https://github.com/zschwendi/dark-eco/issues/6),
[taillight blocks](https://github.com/zschwendi/dark-eco/issues/7),
[cutscene video freezes](https://github.com/zschwendi/dark-eco/issues/8),
[remaining water defects](https://github.com/zschwendi/dark-eco/issues/13), and
[Jak II's ignored internal-resolution setting](https://github.com/zschwendi/dark-eco/issues/14).
The [pause background](https://github.com/zschwendi/dark-eco/issues/11),
[Fit to Screen](https://github.com/zschwendi/dark-eco/issues/12) and
[recipient import](https://github.com/zschwendi/dark-eco/issues/9) candidates
remain pending physical acceptance. The maintainer accepted the previously
affected Jak II loading-chamber area in Build 279; this is not complete-game
certification. Start with **Graphics → ProMotion off** for the 60 FPS mode.

Optional **Settings → Graphics → Developer Logs** saves frame-timing reports
under **Files → Dark Eco → Diagnostics → jak1 or jak2**. It adds measurement
overhead, so leave it off for ordinary play. The detailed Jak II scene/animation
and stream diagnostics use the device console; they are not in that Files export.

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
Landscape remains the recommended orientation for this preview; portrait, the
Duo laptop layout and extreme custom stick placements still need ergonomic
testing.

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

The app does not request increased-memory-limit, extended-virtual-addressing
or JIT entitlements. The package does not remove a required memory
capability. Its ad-hoc transport signature must still be replaced by your
sideloader's signature for your device.

Build 286's compiled source, hashes and validation limits are recorded in
[IPA-IOS286-PROVENANCE.json](IPA-IOS286-PROVENANCE.json). The release includes
the complete package manifest and `SHA256SUMS`. Package checks do not establish
physical-device or gameplay acceptance.

## History

The earlier [Build 285 prerelease](https://github.com/zschwendi/dark-eco/releases/tag/build285-preview)
(`DarkEco-iOS-2.0-build285-preview.ipa`) remains available. Its original
[validation](BUILD285-VALIDATION.md) and [provenance](IPA-IOS285-PROVENANCE.json)
remain unchanged.

In an isolated Duo
simulator, the initial Build 285 layout checkpoint (`d09ad04`) showed Jak 1 Geyser Rock in the upper viewport,
pause/resume, movement by dragging in the lower controls and full-screen
restoration on opening. The final `e35b062` default-change build was separately
installed and launched with ProMotion off and laptop presentation intact.
Physical-device, performance and full-game validation
are pending.

The earlier [Build 282 prerelease](https://github.com/zschwendi/dark-eco/releases/tag/build282-preview)
(`DarkEco-iOS-2.0-build282-preview.ipa`) remains available. Its compiled
source, hashes and validation limits are recorded in
[IPA-IOS282-PROVENANCE.json](IPA-IOS282-PROVENANCE.json). No physical Build 282
tests were performed.

The earlier [Build 281 prerelease](https://github.com/zschwendi/dark-eco/releases/tag/ios-build281-preview)
(`DarkEco-iOS-2.0-build281-preview.ipa`) remains available. Its exact compiled source is [app `23c551c`](https://github.com/zschwendi/dark-eco/commit/23c551c054f056f5d7c70018406fecb38750491a)
and [engine `7d513d61`](https://github.com/zschwendi/jak-pad/commit/7d513d61d6014e869d974a687318d18ddb5754b3).
Original hashes, changes and limitations are recorded in
[IPA-IOS281-PROVENANCE.json](IPA-IOS281-PROVENANCE.json). The release includes
the complete package manifest and checksum. Package checks do not establish
physical-device or gameplay acceptance.
