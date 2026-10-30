# Install Dark Eco without Xcode

Download the [Build 264.1 visionOS preview](https://github.com/zschwendi/dark-eco/releases/tag/visionos-build264.1-preview).
Choose **DarkEco-visionOS-2.0-build264.1-preview.ipa**. It contains the native
runtime and reconstructed OpenGOAL code, but **no retail game data**.

You need **visionOS 26.5 or later**, a compatible controller, and your own
supported Jak and Daxter game data. Start with **Jak and Daxter: The Precursor
Legacy**. This package includes an unfinished Jak II path from Build 264;
Jak II immersive play is not included, and later fixes are not in this package.

## Install the IPA with Windows, Linux or a Mac

You need a Vision Pro, an Apple account, a computer for the initial setup, and
both devices on the same Wi-Fi. Xcode is not needed for this route.

1. Download the desktop installer from [Apparition](https://apparition.illixion.com/).
   Use its current instructions for your operating system. Windows also needs
   an anisette service for Apple sign-in; its [setup documentation](https://github.com/illixion/Apparition#anisette)
   explains the available and self-hosted options.
2. On Vision Pro, open **Settings → General → Remote Devices**. Select the
   headset in Apparition on your computer and enter the pairing code.
3. Follow Apparition's prompts to sign in with **your own Apple account** and
   install Apparition on the headset. Complete Apple's verification prompts
   yourself. Enable **Developer Mode** under **Privacy & Security** if prompted;
   the headset restarts. A developer-trust prompt may also appear.
4. Download this repo's **visionOS `.ipa`** from the release linked above. The
   automatically generated **Source code.zip** is not the app.
5. On the headset, open the IPA from Files with Apparition, or use
   **Library → Install from a File**. Let Apparition sign it for your account
   and install it. You can also use Apparition's desktop IPA installer.
6. Open the installed app from Home View, then supply your game files using
   the instructions below.

These are native visionOS builds. Do not use an iPhone/iPad IPA or a simulator
build. No JIT/debugger step is required for these ports.

## Keep the app working

With a free Apple account, apps normally need refreshing every **7 days** and
there is a **3-app limit**, including the sideloader. Use Apparition's refresh
feature before expiry. Its desktop companion or LocalDevVPN must be available
for refreshes; follow its guide for a Shortcuts automation. Paid developer
profiles have different limits and must support the app's capabilities.

Keep the same signing account and app identifier for updates. A new signer or
identifier can produce a separate app with separate saves. Back up first and
install updates over the existing app. **Do not uninstall to fix a refresh
problem.** These preview packages use local saves; the maintainer's iCloud
containers and development profiles are not included.

## If something goes wrong

- **It will not install:** check that you selected the visionOS IPA, enabled
  Developer Mode, completed trust prompts, and have a free signing slot.
- **It stopped opening after a week:** refresh its signature in Apparition.
- **There is no game / Play is unavailable:** installing the app does not
  supply your game files. Complete this repo's data steps below.
- **The sideloader rejects a capability:** do not blindly remove entitlements.
  Report the exact error and signing method, without account details.
- **A newer install has no saves:** check the signing account and identifier;
  preserve the old installation until its saves are backed up.

This route is an **experimental preview**. Package structure, code signatures
and contents were checked locally. A fresh Windows-to-headset installation,
free-account launch, game import, and save-preserving update have **not** been
validated end to end. The earlier development builds' gameplay results do not
establish those checks. Report reproducible problems through this repo's Issues.

## Supply your own game data

For Jak and Daxter, use your own **SCUS-97124 NTSC v1 Black Label** disc image.
The importer accepts the ISO, a ZIP/7z containing one supported ISO, or a
prepared folder with the expected `iso/` and `fr3/` data. Unsupported revisions
are not made compatible by renaming the file.

1. Put your own ISO/archive or prepared folder somewhere accessible from
   Vision Pro's Files app. Download it locally first if it is in cloud storage.
   You can also access your computer through Files using Apple's
   [Connect to Server instructions](https://support.apple.com/guide/apple-vision-pro/connect-external-servers-tan7acdaa0e3/visionos).
2. Open **Dark Eco → Library → Jak and Daxter → Set Up Game Data → Continue →
   Choose game data…** and select your input.
3. Keep Dark Eco open until import and validation finish. Allow space for both
   the source and the prepared copy; a successful IPA install is only the first step.
4. Start in the ordinary game window with a controller. Try immersive mode
   after windowed play works. Immersive presentation still has known issues.

Do not upload ISOs, extracted game data, saves or account material to an issue.
For a failed import, report the disc revision, input type, app version and
redacted error. The [Vision Pro source guide](../AVP-INSTALL.md) has further
controls and platform limitations.

## What this preview contains

This is an audited repack of the existing **2.0 / Build 264** app, numbered
**264.1** for its sideload packaging. It was not rebuilt from the current
public `v2.0` branch. The release's package manifest records the original
source receipts; those exact historical source revisions are not currently
available from the public repository. See [IPA-RELEASE.md](IPA-RELEASE.md).

Executable code/data sections are unchanged. The package removes the private
provisioning profile and developer/iCloud signing, adds license notices and
uses an ad-hoc transport signature. Your sideloader signs it again for your
headset. Local package checks pass; a fresh third-party install and gameplay
remain unverified. `SHA256SUMS` and the complete file manifest are attached to
the release.
