#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
project="$root/GOALPad.xcodeproj/project.pbxproj"
app="$root/GOALPad/GOALPadApp.swift"
library="$root/GOALPad/Library/GameLibraryView.swift"
touch="$root/GOALPad/Game/TouchControlsView.swift"
vision="$root/GOALPad/Vision/VisionPausedEcoOrnament.swift"
entitlements="$root/GOALPad/GOALPad.entitlements"

test "$(rg -Fc 'INFOPLIST_KEY_CFBundleDisplayName = "Dark Eco";' "$project")" -eq 2
test "$(rg -Fc 'INFOPLIST_KEY_CFBundleName = "Dark Eco";' "$project")" -eq 2
test "$(rg -Fc 'PRODUCT_BUNDLE_IDENTIFIER = com.zephyrstudiosllc.eco;' "$project")" -eq 2
test "$(rg -Fc 'PRODUCT_NAME = "Dark Eco";' "$project")" -eq 2
test "$(rg -Fc 'iCloud.com.zephyrstudiosllc.eco' "$entitlements")" -eq 2

rg -Fq 'fallback: "Dark Eco"' "$app"
rg -Fq 'Text("DARK ECO")' "$library"
rg -Fq 'Text("DARK ECO")' "$touch"
rg -Fq '.accessibilityLabel("Dark Eco Settings")' "$touch"
rg -Fq 'Text("DARK ECO")' "$vision"
rg -Fq '.accessibilityLabel("Dark Eco Settings")' "$vision"

if rg -Fq 'Text("ECO")' "$library" "$touch" "$vision"; then
  echo "a launcher or app-owned settings surface still uses the old ECO wordmark" >&2
  exit 1
fi

echo "product-name checks passed"
