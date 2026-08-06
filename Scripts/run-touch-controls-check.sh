#!/bin/sh
# Compile and run the on-screen controls check on this Mac. See touch-controls-check.swift.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
out=${TMPDIR:-/tmp}/goalpad-touch-controls-check
module_cache=${TMPDIR:-/tmp}/goalpad-touch-controls-module-cache
mkdir -p "$module_cache"

swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path "$module_cache" \
  -import-objc-header "$root/GOALPad/Native/GOALPadRuntimeBridge.h" \
  -swift-version 5 \
  "$root/GOALPad/Game/TouchLayoutSettings.swift" \
  "$root/GOALPad/Game/TouchControls.swift" \
  "$root/GOALPad/Game/TouchControlsView.swift" \
  "$root/Scripts/touch-controls-check.swift" \
  -o "$out"

"$out"
