#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
store="$root/GOALPad/Support/EcoTipStore.swift"
views="$root/GOALPad/Support/EcoSupportViews.swift"
library="$root/GOALPad/Library/GameLibraryView.swift"
settings="$root/GOALPad/Saves/SaveSyncController.swift"
app="$root/GOALPad/GOALPadApp.swift"

xcrun swiftc -parse "$store" "$views" "$library" "$settings" "$app"

rg -Fqx '    case coffee = "com.zephyrstudiosllc.eco.tip.coffee"' "$store"
rg -Fqx '    case development = "com.zephyrstudiosllc.eco.tip.development"' "$store"
rg -Fqx '    case topSupporter = "com.zephyrstudiosllc.eco.tip.topsupporter"' "$store"
rg -Fq 'case .coffee: "Small Support"' "$store"
rg -Fq 'case .development: "Development Support"' "$store"
rg -Fq 'case .topSupporter: "Extra Support"' "$store"
rg -Fq 'Product.products(for: EcoTip.allCases.map(\.rawValue))' "$store"
rg -Fq 'case .verified(let transaction):' "$store"
rg -Fq 'await transaction.finish()' "$store"
rg -Fq 'case .pending:' "$store"
rg -Fq 'case .userCancelled:' "$store"
rg -Fq 'Transaction.unfinished' "$store"
rg -Fq 'Transaction.updates' "$store"
rg -Fq 'isShowingThankYou = true' "$store"
rg -Fq '.task { await EcoTipTransactionObserver.run() }' "$app"

rg -Fq 'Text(product.displayPrice)' "$views"
rg -Fq 'Text("Optional Support")' "$views"
rg -Fq 'SupportRow(title: "Contact"' "$views"
rg -Fq 'SupportRow(title: "Support Development"' "$views"
rg -Fq 'SupportPage(title: "About")' "$views"
rg -Fq 'SupportPage(title: "Support Development")' "$views"
rg -Fq 'SupportPage(title: "Thank You")' "$views"
rg -Fq 'Dark Eco is an unofficial native runtime for OpenGOAL developed by Zach Schwendiman.' "$views"
rg -Fq 'This app was built on the shoulders of the open-source OpenGOAL project and the work of its contributors.' "$views"
rg -Fq 'Label("Visit OpenGOAL project", systemImage: "arrow.up.right.square")' "$views"
rg -Fq 'Dark Eco is unofficial. These optional purchases do not unlock features or content at this time.' "$views"
rg -Fq 'This purchase does not unlock features or content at this time, but it is sincerely appreciated.' "$views"
rg -Fq 'mailto:contact@zephyrstudios.dev?subject=Dark%20Eco%20Support' "$views"

contact_line=$(rg -n -F 'SupportRow(title: "Contact"' "$views" | cut -d: -f1)
support_line=$(rg -n -F 'SupportRow(title: "Support Development"' "$views" | cut -d: -f1)
test "$contact_line" -lt "$support_line"

if rg -qi 'restore purchase|restore purchases' "$store" "$views"; then
  echo "consumable support purchases must not offer a restore action" >&2
  exit 1
fi
if rg -Fq 'AppIconEco' "$store" "$views"; then
  echo "support purchases must not include alternate-icon rewards" >&2
  exit 1
fi

settings_line=$(rg -n -F 'Label("Settings", systemImage: "gearshape")' "$library" | cut -d: -f1)
about_line=$(rg -n -F 'Label("About", systemImage: "info.circle")' "$settings" | cut -d: -f1)
reset_line=$(rg -n -F 'Button("Reset All to Defaults", role: .destructive)' "$settings" | cut -d: -f1 | head -n 1)
version_line=$(rg -n -F 'Text(GOALPadBuildIdentity.versionText)' "$settings" | cut -d: -f1)
test -n "$settings_line"
test "$reset_line" -lt "$about_line"
test "$about_line" -lt "$version_line"
if rg -q -F 'Label("About", systemImage: "info.circle")' "$library"; then
  echo "About must live at the bottom of Settings, not in the launcher menu" >&2
  exit 1
fi

printf '%s\n' "support purchase checks passed"
