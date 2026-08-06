#!/bin/sh
# Compile and run the pure keyboard/mouse input check on this Mac.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
out=${TMPDIR:-/tmp}/goalpad-keyboard-mouse-input-check
module_cache=${TMPDIR:-/tmp}/goalpad-keyboard-mouse-input-module-cache
mkdir -p "$module_cache"

swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path "$module_cache" \
  -import-objc-header "$root/GOALPad/Native/GOALPadRuntimeBridge.h" \
  -swift-version 5 \
  "$root/GOALPad/Input/KeyboardMouseInput.swift" \
  "$root/Scripts/keyboard-mouse-input-check.swift" \
  -o "$out"

"$out"
