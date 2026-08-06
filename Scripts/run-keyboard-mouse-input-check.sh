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

# Apple delivers the supported extended profile through the declared Game Controllers capability,
# and the active controller must be adopted even when it was not the first connected device.
test "$(/usr/libexec/PlistBuddy -c 'Print :GCSupportsControllerUserInteraction' \
  "$root/GOALPad-Info.plist")" = true
test "$(/usr/libexec/PlistBuddy -c 'Print :GCSupportedGameControllers:0:ProfileName' \
  "$root/GOALPad-Info.plist")" = ExtendedGamepad
rg -Fq '.GCControllerDidBecomeCurrent' "$root/GOALPad/Input/ControllerInput.swift"
rg -Fq 'adoptController(Self.preferredController())' "$root/GOALPad/Input/ControllerInput.swift"
rg -Fq 'controllerDidConnect(note.object as? GCController)' \
  "$root/GOALPad/Input/ControllerInput.swift"
rg -Fq 'Self.preferredController(excluding: leaving)' \
  "$root/GOALPad/Input/ControllerInput.swift"
