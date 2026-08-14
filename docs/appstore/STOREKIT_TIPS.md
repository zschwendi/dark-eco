# Dark Eco optional support

**Release decision:** Dark Eco offers three repeatable **Consumable** StoreKit
purchases. They are optional payments that support continued development and
do not unlock features or content at this time. They do not grant status,
recognition, access, or any other benefit.

This document is a release-input checklist; it does not claim that App Store
Connect records exist.

## Permanent StoreKit contract and copy

| Reference name | Product ID (permanent) | Customer display name | Customer description | Intended US base price |
| --- | --- | --- | --- | --- |
| Small Support | `com.zephyrstudiosllc.eco.tip.coffee` | Small Support | Optional purchase supporting Dark Eco. | $4.99 |
| Development Support | `com.zephyrstudiosllc.eco.tip.development` | Development Support | Optional purchase supporting development. | $14.99 |
| Extra Support | `com.zephyrstudiosllc.eco.tip.topsupporter` | Extra Support | Optional extra support for Dark Eco. | $29.99 |

The existing product identifiers remain unchanged. The app displays StoreKit's
localized `Product.displayPrice`; the amounts above are App Store Connect
configuration targets, not hardcoded in-app copy.

## App Store Connect entry checklist

For each row, an authorized App Store Connect user must:

1. Create an In-App Purchase of type **Consumable** under Dark Eco with the
   exact Product ID and reference name above.
2. Add the customer display name and description above for at least one
   localization, set the intended US base price, select the applicable tax
   category, and choose availability deliberately.
3. Upload an App Review screenshot of the app's **Support Development** page
   showing all three choices. This review-only image is not customer-facing,
   must use a screenshot specification supported by the app, and must not
   contain retail game data. Do not configure promoted-IAP images for this
   release.
4. Add review notes: “These are optional consumable purchases that support Dark
   Eco development. They do not unlock features, content, status, recognition,
   or access at this time. The page is reachable from Settings > About > Support
   Development.”
5. Test all three identifiers in StoreKit testing and the App Store sandbox:
   available product, verified success and Thank You sheet, verification
   failure, Ask to Buy/pending, cancellation, unavailable product, interrupted
   transaction completion, and repeat purchase. Submit the first IAPs with the
   app version intended for review.

The Account Holder must have an active Paid Apps Agreement and complete
required banking and tax information. This is external release state and is not
created by a source-code build.

## Official Apple sources (checked 2026-08-14)

- [In-App Purchase types](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-types/)
- [Create consumable or non-consumable In-App Purchases](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases/)
- [Set a price for an In-App Purchase](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/set-a-price-for-an-in-app-purchase/)
- [Submit an In-App Purchase](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase/)
- [App Review Guidelines, 3.1.1](https://developer.apple.com/app-store/review/guidelines/)
