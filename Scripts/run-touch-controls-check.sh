#!/bin/sh
# Compile and run the on-screen controls check on this Mac. See touch-controls-check.swift.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
out=${TMPDIR:-/tmp}/goalpad-touch-controls-check

swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -import-objc-header "$root/GOALPad/Native/GOALPadRuntimeBridge.h" \
  -swift-version 5 \
  "$root/GOALPad/Game/TouchControls.swift" \
  "$root/Scripts/touch-controls-check.swift" \
  -o "$out"

"$out"
