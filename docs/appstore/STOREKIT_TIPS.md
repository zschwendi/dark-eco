# Dark Eco optional tips

**Release decision:** Dark Eco offers three repeatable **Consumable** StoreKit
tips. They are optional repeatable payments, unlock no features or content, and
do not grant status, recognition, access, or any other benefit. This document
is a release-input checklist; it does not claim that App Store Connect records
exist.

## Permanent StoreKit contract and copy

| Reference name (internal) | Product ID (permanent) | Customer display name | Customer description | Intended US base price |
| --- | --- | --- | --- | --- |
| Coffee tip | `com.zephyrstudiosllc.eco.tip.coffee` | Coffee tip | Optional tip for Dark Eco. | $2.99 |
| Development tip | `com.zephyrstudiosllc.eco.tip.development` | Development tip | Optional tip supporting development. | $4.99 |
| Extra support tip | `com.zephyrstudiosllc.eco.tip.top-supporter` | Extra support tip | Optional tip for extra support. | $9.99 |

The permanent identifiers above are already in the shipped StoreKit lookup.
Do not change them to match the revised non-coercive customer copy. The
customer display names are 10, 15, and 17 characters; the descriptions are 26,
36, and 31 characters, respectively, within Apple's current 2–30 and 45
character limits. The app displays StoreKit's localized `Product.displayPrice`;
the dollar amounts above are configuration targets, not hardcoded in-app copy.

## App Store Connect entry checklist

For each row, an authorized App Store Connect user must:

1. Create an In-App Purchase of type **Consumable** under Dark Eco with the
   exact Product ID and reference name above.
2. Add the customer display name and description above for at least one
   localization, set the intended US base price, select the applicable tax
   category, and choose availability deliberately.
3. Upload an App Review screenshot of the app's Donate page that clearly shows
   the optional tip offer. This review-only image is not customer-facing, must
   use a screenshot specification supported by the app, and must not contain
   retail game data. Do not configure a promoted IAP image in this release.
4. Add review notes: “These are optional consumable tips. They unlock no
   feature, content, entitlement, status, or recognition. The Donate page is
   reachable from Library > About > Donate.”
5. Test all three identifiers in StoreKit testing and the App Store sandbox:
   available product, success, verification failure, Ask to Buy/pending,
   cancellation, unavailable product, and interrupted transactions. Submit the
   first IAPs with the app version intended for review.

The Account Holder must accept an active Paid Apps Agreement before offering
IAPs; banking and tax information are also required for payment processing.
This is a release gate outside the repository.

## Official Apple sources (checked 2026-08-10)

- [Create consumable or non-consumable In-App Purchases](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases/)
- [In-App Purchase information](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information/)
- [Set a price for an In-App Purchase](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/set-a-price-for-an-in-app-purchase/)
- [Submit an In-App Purchase](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase/)
- [Sign and update agreements](https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements/)
- [App Review Guidelines, 3.1.1](https://developer.apple.com/app-store/review/guidelines/)
