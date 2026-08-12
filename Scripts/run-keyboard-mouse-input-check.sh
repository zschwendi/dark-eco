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
rg -Fq 'guard Self.capturesRapidButtonEdge(from: element, on: pad) else { return }' \
  "$root/GOALPad/Input/ControllerInput.swift"
rg -Fq 'element is GCControllerButtonInput' "$root/GOALPad/Input/ControllerInput.swift"
rg -Fq 'element === pad.dpad' "$root/GOALPad/Input/ControllerInput.swift"
test "$(rg -Fc 'candidate.handlerQueue = .main' \
  "$root/GOALPad/Input/ControllerInput.swift")" = 3
test "$(rg -Fc 'MainActor.assumeIsolated {' \
  "$root/GOALPad/Input/ControllerInput.swift")" = 4
! sed -n '/private func adoptController/,/private func dropController/p' \
  "$root/GOALPad/Input/ControllerInput.swift" | rg -Fq 'DispatchQueue.main.async'
! sed -n '/private func adoptKeyboard/,/private func dropKeyboard/p' \
  "$root/GOALPad/Input/ControllerInput.swift" | rg -Fq 'DispatchQueue.main.async'
! sed -n '/private func adoptMouse/,/private func dropMouse/p' \
  "$root/GOALPad/Input/ControllerInput.swift" | rg -Fq 'DispatchQueue.main.async'

# Polling and rapid-edge callbacks share one fixed snapshot. Collection compatibility remains in
# the pure bindings layer, but the Apple hot path must not reconstruct it each display frame.
rg -Fq 'let controllerSnapshot = Self.controllerSnapshot(of: gamepad)' \
  "$root/GOALPad/Input/ControllerInput.swift"
rg -Fq 'let snapshot = Self.controllerSnapshot(of: pad)' \
  "$root/GOALPad/Input/ControllerInput.swift"
rg -Fq 'if touchpadPressed { buttons.insert(.select) }' \
  "$root/GOALPad/Input/ControllerInput.swift"
rg -Fq 'guard buttons != lastObservedControllerButtons else { return }' \
  "$root/GOALPad/Input/ControllerInput.swift"
rg -Fq 'controllerButtonSnapshots.append(buttons)' \
  "$root/GOALPad/Input/ControllerInput.swift"
rg -Fq 'return controllerButtonSnapshots.removeFirst()' \
  "$root/GOALPad/Input/ControllerInput.swift"
rg -Fq 'private(set) var pressedMask: UInt16' \
  "$root/GOALPad/Input/KeyboardMouseInput.swift"
rg -Fq 'private(set) var values: SIMD16<Float>' \
  "$root/GOALPad/Input/KeyboardMouseInput.swift"
! rg -Fq 'Set<Jak1ControllerControl>' "$root/GOALPad/Input/ControllerInput.swift"
! rg -Fq '[Jak1ControllerControl: Float]' "$root/GOALPad/Input/ControllerInput.swift"

consume_frame=$(sed -n '/mutating func consumeFrame/,/private static func digitalAxis/p' \
  "$root/GOALPad/Input/KeyboardMouseInput.swift")
printf '%s\n' "$consume_frame" | rg -Fq 'for control in heldControls'
printf '%s\n' "$consume_frame" | rg -Fq 'guard !heldControls.isEmpty'
! printf '%s\n' "$consume_frame" | rg '\.filter|compactMap|Set\('
