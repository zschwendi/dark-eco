# Dark Eco release media plan

**Status:** Implemented locally for Dark Eco 1.0 (164). Nine simulator
screenshot candidates and opaque JPEG upload copies have been captured and
visually checked. This is not evidence that any App Store Connect media has
been uploaded or approved.

## Existing inventory

- [App Store metadata](metadata.md) contains product identity and disclosures.
- [Optional support](STOREKIT_TIPS.md) contains the IAP review-screen requirement.
- `docs/appstore/icon-concepts/` contains icon studies, not release screenshots
  or previews.
- `docs/BUILDING.md` records historical simulator screenshot commands and
  evidence. Those captures are not release media and must not be reused without
  checking this plan.
- The local, uncommitted capture set and its hashes are recorded in the
  workspace artifact `AppStoreAssets/DarkEco-1.0-164/CAPTURE_MANIFEST.md`,
  outside this Git repository.
- `ContentView` has a compile-time-only `GOALPAD_APPSTORE_CAPTURE` seam for the
  empty Library, Game Setup, and Settings states. It is absent from normal
  builds unless that Swift condition is explicitly supplied. The condition
  selects only the launch destination; it does not replace shipping labels or
  readiness behavior.
- No app preview was produced for Build 164. The preview is optional, and a
  UI-only video does not add enough information to this release's three still
  concepts.

## Content boundary

Capture only the shipping app UI. Do not bundle, add, commit, or download retail
game data for capture. The preferred release frames use an empty app container
and show Library, Game Setup, and Settings UI; they contain no gameplay, title
art, character, logo, or user-imported artwork. A user-provided data state may
be used only for private local validation, never as a substitute for rights or
branding review before public media is submitted.

Do not add marketing text outside the app UI to make unvalidated gameplay,
compatibility, or affiliation claims. Screenshots and preview frames must match
the submitted build and remain free of alpha or transparency.

## Three screenshot concepts per platform

Capture these same three truthful states separately at each required device
resolution. Do not resize a simulator capture to invent a required device size.

| Order | State | Visible message | Data needed |
| --- | --- | --- | --- |
| 1 | Library, empty container | Set Up Game Data / Not Imported, then two neutral Future Title cards marked Coming Soon and Planned | None |
| 2 | Game Setup | Streamlined local import/setup guidance that the app includes no game data | None |
| 3 | Settings | Controls, Graphics, iCloud, Saves, and Support without the unavailable Game picker | None |

Capture the Support Development page separately as the three consumables' App
Review screenshot; it is not one of the three customer-facing storefront
concepts.

For iPhone and iPad, create the three concepts for each supported platform’s
required family: one accepted iPhone 6.9-inch size matching the capture device
(1260 × 2736, 1290 × 2796, or 1320 × 2868 portrait; use its landscape
equivalent), and iPad 13-inch at 2064 × 2752 portrait or 2752 × 2064 landscape.
For Apple Vision Pro, create the three conventional-window concepts at 3840 ×
2160 landscape. The visionOS product remains a Comfort/2D shared-space window;
do not depict dormant stereo, volumetric, tracked, or immersive modes.

This yields three iPhone, three iPad, and three Apple Vision Pro storefront
frames from the same three states.

App Store Connect accepts one to ten PNG/JPG/JPEG screenshots per supported
platform. Keep all three frames in the same orientation per platform, use opaque
RGB exports, and recheck Apple’s specification table immediately before upload.

## Build 164 local capture result

The screenshot candidates were captured from Release simulator builds at UI
commit `eefc8e10` with build number 164. The capture-only builds supplied
`-DGOALPAD_APPSTORE_CAPTURE`; the three launch states were Library (default),
`-EcoCaptureGameSetup`, and `-EcoCaptureSettings`. They contained no game data
or user artwork.

| Platform folder | Simulator and runtime | JPEG dimensions | Frames |
| --- | --- | --- | --- |
| `iPhone-6.9` | iPhone 17 Pro Max, iOS 26.5 | 1320 × 2868 | Library, Game Setup, Settings |
| `iPad-13` | iPad Pro 13-inch, iOS 26.5 | 2064 × 2752 | Library, Game Setup, Settings |
| `Apple-Vision-Pro` | Apple Vision Pro, visionOS 26.5 | 3840 × 2160 | Library, Game Setup, Settings |

All nine JPEGs were checked as `jpeg` with `hasAlpha: no`, and a nine-frame
contact sheet was visually reviewed. PNG simulator masters remain beside the
JPEGs. The manifest records dimensions and SHA-256 values for the upload
copies.

The Vision Pro screenshots show the conventional 2D window, not an artificial
hover effect. The library card uses a full-card interaction and hover content
shape in the app, but physical gaze/hover acceptance remains a separate device
gate.

## Re-capture recipe

1. Build the exact release candidate using the documented simulator build path;
   never use a physical device for routine capture.
2. Start with an empty simulator app container. Do not install any game-data
   package or user artwork.
3. For deterministic empty-state capture, add
   `OTHER_SWIFT_FLAGS=$(inherited) -DGOALPAD_APPSTORE_CAPTURE` to the Release
   simulator build. Launch without an argument for Library, with
   `-EcoCaptureGameSetup` for Game Setup, or with `-EcoCaptureSettings` for
   Settings. These arguments route to the ordinary shipping empty state and do
   not substitute capture-only labels. Wait for the UI to settle, then capture with Xcode or
   `xcrun simctl io <simulator-udid> screenshot <path>`. For visionOS, use the
   simulator/Xcode capture that produces the required 3840 × 2160 frame.
4. Inspect every exported image with `sips -g pixelWidth -g pixelHeight -g
   format -g hasAlpha <path>` and confirm its state, dimensions, orientation,
   opaque pixels, and absence of retail/user artwork.
5. Export opaque JPEG upload copies, store candidate media outside the
   repository until the maintainer approves the release input, and record the
   build, device family, state, dimensions, and SHA-256 in the capture manifest.

`simctl` success proves only a simulator capture. It does not prove physical
device rendering, App Store upload, or App Review acceptance.

## App preview decision

No app preview is planned for this release candidate. Apple permits screenshots
without a preview, and the three still concepts already show the complete
asset-free release story. Reconsider only if the submitted build can add useful
motion or interaction without retail content. A future 15–30 second, UI-only
sequence could show Library → Game Setup → Settings.

Use H.264 or ProRes 422 (HQ only), no more than 30 fps, and a file no larger
than 500 MB. Use 1920 × 886 for the iPhone preview, 1600 × 1200 for the iPad
preview, and 3840 × 2160 for Apple Vision Pro. Use a legible 5-second poster
frame and do not add music, gameplay footage, or claims that the capture cannot
substantiate.

## Official Apple sources (checked 2026-08-10)

- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- [Upload app previews and screenshots](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/)
- [App preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications/)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
