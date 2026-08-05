#!/bin/sh
# Compile and run deterministic local/cloud presentation-settings checks.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
out=${TMPDIR:-/tmp}/goalpad-presentation-settings-check
module_cache=${TMPDIR:-/tmp}/goalpad-presentation-settings-module-cache
mkdir -p "$module_cache"

swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path "$module_cache" \
  -swift-version 5 \
  "$root/GOALPad/Game/PresentationSettings.swift" \
  "$root/Scripts/presentation-settings-check.swift" \
  -o "$out"

"$out"
swift "$root/Scripts/presentation-settings-ui-check.swift" "$root"
