#!/bin/sh
# Compile and run the pure touch-layout model, remap, drag, and clamp checks.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
out=${TMPDIR:-/tmp}/goalpad-touch-layout-settings-check
module_cache=${TMPDIR:-/tmp}/goalpad-touch-layout-settings-module-cache
mkdir -p "$module_cache"

swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path "$module_cache" \
  -swift-version 5 \
  "$root/GOALPad/Game/TouchLayoutSettings.swift" \
  "$root/Scripts/touch-layout-settings-check.swift" \
  -o "$out"

"$out"
