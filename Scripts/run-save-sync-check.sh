#!/bin/sh
# Compile and run the save mirror checks on this Mac. See save-sync-check.swift.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
out=${TMPDIR:-/tmp}/goalpad-save-sync-check
standalone_out=${TMPDIR:-/tmp}/goalpad-save-sync-standalone-profile-check
module_cache=${TMPDIR:-/tmp}/goalpad-save-sync-module-cache
input_stubs=${TMPDIR:-/tmp}/goalpad-input-test-stubs.o
mkdir -p "$module_cache"

xcrun clang \
  -c "$root/Scripts/goalpad-input-test-stubs.m" \
  -o "$input_stubs"

swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path "$module_cache" \
  -import-objc-header "$root/GOALPad/Native/GOALPadRuntimeBridge.h" \
  -swift-version 5 \
  "$root/GOALPad/Input/KeyboardMouseInput.swift" \
  "$root/GOALPad/Input/ControllerRumblePolicy.swift" \
  "$root/GOALPad/Game/TouchLayoutSettings.swift" \
  "$root/GOALPad/Game/TouchControls.swift" \
  "$root/GOALPad/Input/ControllerInput.swift" \
  "$root/GOALPad/Library/GameLibrary.swift" \
  "$root/GOALPad/Saves/SaveSyncEngine.swift" \
  "$root/GOALPad/Game/PresentationSettings.swift" \
  "$root/GOALPad/Saves/SaveSyncController.swift" \
  "$root/Scripts/save-sync-ui-test-stubs.swift" \
  "$root/Scripts/save-sync-check.swift" \
  "$input_stubs" \
  -o "$out"

"$out"

swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path "$module_cache" \
  -import-objc-header "$root/GOALPad/Native/GOALPadRuntimeBridge.h" \
  -swift-version 5 \
  -D GOALPAD_JAK2 \
  "$root/GOALPad/Input/KeyboardMouseInput.swift" \
  "$root/GOALPad/Input/ControllerRumblePolicy.swift" \
  "$root/GOALPad/Game/TouchLayoutSettings.swift" \
  "$root/GOALPad/Game/TouchControls.swift" \
  "$root/GOALPad/Input/ControllerInput.swift" \
  "$root/GOALPad/Library/GameLibrary.swift" \
  "$root/GOALPad/Saves/SaveSyncEngine.swift" \
  "$root/GOALPad/Game/PresentationSettings.swift" \
  "$root/GOALPad/Saves/SaveSyncController.swift" \
  "$root/Scripts/save-sync-ui-test-stubs.swift" \
  "$root/Scripts/save-sync-standalone-profile-check.swift" \
  "$input_stubs" \
  -o "$standalone_out"

(cd "$root" && "$standalone_out")
