# iOS/Xcode build and archive (current)

This is the practical path to build and archive the app from a clean checkout.
An archive is only a build artifact. App Store Connect distribution additionally
requires a valid Apple Distribution identity, an App Store provisioning profile,
and a successful Organizer validation or export/upload.

## Requirements

- macOS on Apple silicon (Intel may work but is slower for many steps)
- Xcode (with iOS SDK and command-line tools)
- `cmake`, `ninja`, `go-task`, `openssl@3`

```bash
brew install cmake ninja go-task openssl@3
```

## 0) One-time repo bootstrap

```bash
cd /path/to/GOALPad
git submodule update --init --recursive
```

## 1) Generate required host artifacts before iOS archive

1. Build/verify source-object pack

```bash
Scripts/prepare-jak1-source-object-pack.sh
```

2. Generate AOT C output for Jak 1 (this is needed by the app target)

```bash
Scripts/generate-jak1-aot.sh /private/tmp/GOALPad-aot-host
```

3. Verify AOT completeness

```bash
Scripts/verify-generated-aot.sh Generated/jak1-aot 518
```

4. (Optional sanity check) compile Metal shaders locally

```bash
SRCROOT=$PWD DERIVED_SOURCES_DIR=/private/tmp/GOALPad-metal PLATFORM_NAME=iphoneos Scripts/compile-metal-shaders.sh
```

If steps 1–3 finish, Xcode has the required inputs for the first Release archive.

## 2) Archive from Xcode (GUI)

1. Open `GOALPad.xcodeproj` in Xcode.
2. Select scheme `GOALPad`, build configuration `Release`.
3. Choose **Any iOS Device (arm64)** (or Generic iOS Device).
4. In **Product > Archive**, run Archive.
5. In Organizer, validate the archive, then use **Distribute App** and choose App
   Store Connect or export an IPA as needed.
6. Ensure:
   - Signing Team + Provisioning Profile are selected
   - Bundle ID matches your App Store Connect app
   - Export options are correct for your distribution target

## 2b) Archive from CLI

This verifies compilation and archive assembly without a signing pass:

```bash
xcodebuild \
  -project GOALPad.xcodeproj \
  -scheme GOALPad \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-xc \
  -jobs 4 \
  CODE_SIGNING_ALLOWED=NO \
  archive \
  -archivePath /tmp/GOALPad-archive/GOALPad.xcarchive
```

This unsigned archive is not uploadable and does not prove App Store signing or
delivery. A development-signed archive is likewise not uploaded as-is: Organizer
must export or upload it with App Store distribution signing. Use Xcode Organizer
or `xcodebuild -exportArchive` with an App Store Connect `ExportOptions.plist`,
then retain the successful validation or upload result as the distribution gate.

## Build 140 phase-script repair

Build 140's generic iOS archive was reproduced successfully after two project
repairs:

- The importer configurations use `ENABLE_USER_SCRIPT_SANDBOXING = NO` because
  the custom Metal phase creates transitive module-cache files below Xcode's
  derived sources directory and the Release importer also recursively reads the
  pinned OpenGOAL checkout. This changes Xcode's build-script sandbox only; it
  does not disable the built app's runtime sandbox.
- `Scripts/build-jak1-import-composer-apple.sh` supplies the usual Homebrew paths
  before locating `cmake`, `ninja`, and other host tools. Xcode's GUI environment
  does not necessarily inherit the shell's `PATH`.

If Xcode reports only `Command PhaseScriptExecution failed with a nonzero exit
code`, open the build report and inspect the first failing script line. Do not
change OpenGOAL or generated runtime code to work around one of these host-build
environment failures.

## What must exist before archive

- `build/jak1-source-object-pack/` (from step 1)
- `Generated/jak1-aot/` (`aot_boot_manifest.c`, `*.c`, `*.h`, `coverage.tsv`)
- On archive:
  - `GOALPad.xcarchive`
  - `GOALPad.xcarchive/Products/Applications/Dark Eco.app`
  - `GOALPad.xcarchive/dSYMs/Dark Eco.app.dSYM`
- Xcode will also produce generated import/shader artifacts in DerivedData during build.

## Troubleshooting fast checks

- If AOT verification fails, rerun step 1 and step 2 (same host toolchain).
- If a source-pack verifier reports a mismatch, rerun step 1.
- If AOT generation hits a stale CMake cache error, use a clean host build dir
  (for example `Scripts/generate-jak1-aot.sh /private/tmp/goalpad-aot-host-clean`)
  and rerun step 2.
- If CMake reports missing `OpenGOAL`, rerun the submodule sync command in step 0.

For fuller background and historical notes, keep using `docs/BUILDING.md` and
`docs/PROJECT_OVERVIEW.md`.
