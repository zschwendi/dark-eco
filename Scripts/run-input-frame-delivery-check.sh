#!/bin/sh
# Compile and run the input frame delivery check on this Mac. See input-frame-delivery-check.swift.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-input-frame-delivery.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM

swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path "$build_dir/module-cache" \
  -import-objc-header "$root/GOALPad/Native/GOALPadRuntimeBridge.h" \
  -swift-version 5 \
  "$root/GOALPad/Game/TouchLayoutSettings.swift" \
  "$root/GOALPad/Game/TouchControls.swift" \
  "$root/GOALPad/Input/KeyboardMouseInput.swift" \
  "$root/GOALPad/Input/InputFrameDelivery.swift" \
  "$root/Scripts/input-frame-delivery-check.swift" \
  -o "$build_dir/input-frame-delivery-check"

"$build_dir/input-frame-delivery-check"
