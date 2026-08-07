#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
store="$root/GOALPad/Support/EcoTipStore.swift"
views="$root/GOALPad/Support/EcoSupportViews.swift"
library="$root/GOALPad/Library/GameLibraryView.swift"
app="$root/GOALPad/GOALPadApp.swift"

xcrun swiftc -parse "$store" "$views" "$library" "$app"

test "$(rg -c 'case .* = "com\.zephyrstudiosllc\.eco\.tip\.' "$store")" -eq 3
rg -Fq 'Product.products(for: EcoTip.allCases.map(\.rawValue))' "$store"
rg -Fq 'case .verified(let transaction):' "$store"
rg -Fq 'await transaction.finish()' "$store"
rg -Fq 'case .pending:' "$store"
rg -Fq 'case .userCancelled:' "$store"
rg -Fq 'Transaction.unfinished' "$store"
rg -Fq 'Transaction.updates' "$store"
rg -Fq '.task { await EcoTipTransactionObserver.run() }' "$app"
rg -Fq 'Text(product.displayPrice)' "$views"
rg -Fq 'Text("Unavailable")' "$views"
rg -Fq 'Text("The app is free. These are optional one-time tips that help fund development and maintenance. Thank you for your support.")' "$views"
rg -Fq 'SupportRow(title: "Contact"' "$views"
rg -Fq 'SupportRow(title: "About"' "$views"
rg -Fq 'SupportRow(title: "Donate"' "$views"

contact_line=$(rg -n -F 'SupportRow(title: "Contact"' "$views" | cut -d: -f1)
about_line=$(rg -n -F 'SupportRow(title: "About"' "$views" | cut -d: -f1)
donate_line=$(rg -n -F 'SupportRow(title: "Donate"' "$views" | cut -d: -f1)
test "$contact_line" -lt "$about_line"
test "$about_line" -lt "$donate_line"

if rg -qi 'restore purchase|restore purchases' "$store" "$views"; then
  echo "consumable tips must not offer a restore action" >&2
  exit 1
fi

settings_line=$(rg -n -F 'Label("Settings", systemImage: "gearshape")' "$library" | cut -d: -f1)
credits_line=$(rg -n -F 'Label("Credits", systemImage: "person.3")' "$library" | cut -d: -f1)
support_line=$(rg -n -F 'Label("Support", systemImage: "heart")' "$library" | cut -d: -f1)
test "$settings_line" -lt "$credits_line"
test "$credits_line" -lt "$support_line"

printf '%s\n' "support purchase checks passed"
