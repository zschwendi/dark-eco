# App Store Metadata

> **Status:** Approved product direction. The public bundle and display-name
> settings are implemented; App Store availability remains unvalidated.

## Product identity

- **Title:** Eco Pro
- **Subtitle:** Native OpenGOAL Runtime
- **Bundle identifier:** `com.zephyrstudiosllc.eco`
- **iCloud container:** `iCloud.com.zephyrstudiosllc.eco`

## Identity migration

Eco Pro intentionally uses a new paid-team application identity instead of the
earlier GOALPad development bundle identifier. Apple treats it as a separate
app and sandbox, so local game data, settings, and saves from an existing
GOALPad installation do not migrate automatically. Export or otherwise preserve
local saves before moving a device to Eco Pro; never uninstall the existing app
as part of migration testing.

## Platform presentation

The iPadOS, macOS, and visionOS builds share one runtime target. visionOS uses a
standard SwiftUI window. Volumetric and immersive presentation are not part of
the current App Store-facing product.
