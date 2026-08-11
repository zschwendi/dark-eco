# Dark Eco release media plan

**Status:** Planned. This is a local capture recipe and metadata plan, not
evidence that any App Store Connect media has been uploaded or approved.

## Existing inventory

- [App Store metadata](metadata.md) contains product identity and disclosures.
- [Optional tips](STOREKIT_TIPS.md) contains the IAP review-screen requirement.
- `docs/appstore/icon-concepts/` contains icon studies, not release screenshots
  or previews.
- `docs/BUILDING.md` records historical simulator screenshot commands and
  evidence. Those captures are not release media and must not be reused without
  checking this plan.
- No App Store screenshots, app previews, or capture automation are currently
  committed.

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
| 1 | Library, empty container | Truthful available, Coming Soon, and Planned library states; on visionOS, capture the normal full-card hover state after verifying it in the submitted build | None |
| 2 | Game Setup | Streamlined local import/setup guidance that the app includes no game data | None |
| 3 | Settings | The single input picker and compact settings categories | None |

Capture the Donate page separately as each consumable's App Review screenshot;
it is not one of the three customer-facing storefront concepts.

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

## Local capture recipe

1. Build the exact release candidate using the documented simulator build path;
   never use a physical device for routine capture.
2. Start with an empty simulator app container. Do not install any game-data
   package or user artwork.
3. Navigate manually to each state above, wait for all app UI to settle, then
   capture with Xcode or `xcrun simctl io <simulator-udid> screenshot <path>`.
   For visionOS, use the simulator/Xcode capture that produces the required
   3840 × 2160 Apple Vision Pro frame.
4. Inspect every exported image with `sips -g pixelWidth -g pixelHeight -g
   format -g hasAlpha <path>` and confirm its state, dimensions, orientation,
   opaque pixels, and absence of retail/user artwork.
5. Store candidate media outside the repository until the maintainer approves
   the release input. Record the submitted build, device family, state, output
   dimensions, and SHA-256 in the release checklist.

`simctl` success proves only a simulator capture. It does not prove physical
device rendering, App Store upload, or App Review acceptance.

## Optional honest app preview

Only make a preview if the submitted build can show the three UI states cleanly
without retail content. A 15–30 second, landscape, UI-only sequence may show
Library → Game Setup → Settings. No preview is required for this release.

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
