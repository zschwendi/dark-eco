#!/bin/sh
# Compile and run deterministic local/cloud presentation-settings checks.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
out=${TMPDIR:-/tmp}/goalpad-presentation-settings-check
module_cache=${TMPDIR:-/tmp}/goalpad-presentation-settings-module-cache
input_stubs=${TMPDIR:-/tmp}/goalpad-presentation-settings-test-stubs.o
mkdir -p "$module_cache"

xcrun clang \
  -c "$root/Scripts/goalpad-input-test-stubs.m" \
  -o "$input_stubs"

swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path "$module_cache" \
  -import-objc-header "$root/GOALPad/Native/GOALPadRuntimeBridge.h" \
  -swift-version 5 \
  "$root/GOALPad/Input/KeyboardMouseInput.swift" \
  "$root/GOALPad/Game/TouchLayoutSettings.swift" \
  "$root/GOALPad/Game/RenderSettings.swift" \
  "$root/GOALPad/Game/PresentationSettings.swift" \
  "$root/Scripts/presentation-settings-check.swift" \
  "$input_stubs" \
  -o "$out"

"$out"
swift "$root/Scripts/presentation-settings-ui-check.swift" "$root"
