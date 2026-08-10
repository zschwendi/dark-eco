# App Store Metadata

> **Status:** Approved product direction. The public bundle and display-name
> settings are implemented; App Store availability remains unvalidated.

## Product identity

- **Title:** Dark Eco
- **Subtitle:** Native OpenGOAL Runtime
- **Bundle identifier:** `com.zephyrstudiosllc.eco`
- **iCloud container:** `iCloud.com.zephyrstudiosllc.eco`

## Build disclosures

Build 92 includes `PrivacyInfo.xcprivacy` in the shared app target. It declares
only required-reason API access: checking free space before local preparation,
reading file metadata in app/iCloud containers and user-selected locations,
and storing app-only preferences. These declarations do not replace the
separate App Store Connect privacy questionnaire.

Build 133 adds three optional consumable StoreKit tips. The app displays Apple's
localized prices and provides no feature, content, or entitlement in return.
Product identifiers, intended US price points, test cases, and required App Store
Connect setup are recorded in [Dark Eco optional tips](STOREKIT_TIPS.md).

`ITSAppUsesNonExemptEncryption` is `false`. The app implements no encryption;
CryptoKit is used only for one-way save-file identity hashes, while iCloud and
transport protection are operating-system services. This is the project's
technical configuration, not a legal or export-classification guarantee.

## Identity migration

Dark Eco intentionally uses a new paid-team application identity instead of the
earlier GOALPad development bundle identifier. Apple treats it as a separate
app and sandbox, so local game data, settings, and saves from an existing
GOALPad installation do not migrate automatically. Export or otherwise preserve
local saves before moving a device to Dark Eco; never uninstall the existing app
as part of migration testing.

## Platform presentation

The iPadOS, macOS, and visionOS builds share one runtime target. visionOS uses a
standard Shared Space SwiftUI window with Comfort presentation and an
experimental bounded stereoscopic game surface. Volumetric, tracked, and
immersive presentation are not part of the current App Store-facing product.
