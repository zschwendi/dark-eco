# Dark Eco optional tips

Dark Eco uses three repeatable StoreKit consumables. They unlock no features or
content and are presented only as optional one-time tips to support development
and maintenance.

| Reference name | Product ID | Intended US price |
| --- | --- | --- |
| Buy me a coffee | `com.zephyrstudiosllc.eco.tip.coffee` | $2.99 |
| Support development | `com.zephyrstudiosllc.eco.tip.development` | $4.99 |
| Become a top supporter | `com.zephyrstudiosllc.eco.tip.top-supporter` | $9.99 |

The product identifiers are part of the shipped StoreKit contract and cannot be
edited after creation in App Store Connect. Create all three under Dark Eco as
**Consumable** In-App Purchases, configure their names, descriptions, price
points, tax category, review screenshot, and availability, and use the exact
identifiers above. The app always displays StoreKit's localized
`Product.displayPrice`; the US prices in this document are App Store Connect
configuration targets, not hardcoded storefront copy.

Before testing or submission, the Account Holder must have an active Paid Apps
Agreement plus completed banking and tax information. Exercise success,
verification failure, Ask to Buy/pending, cancellation, unavailable products,
and interrupted transactions in StoreKit testing and the App Store sandbox.
Submit Dark Eco's first consumable purchases with a new app version.
