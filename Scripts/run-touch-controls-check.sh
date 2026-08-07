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

# The title-specific regression must exercise a semantic SwiftUI Button, not merely prove that
# an idealized cached pill frame can emit the same Start bit.
rg -Fq 'Button { performTitleStart() }' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'controls.performNativeMenuAction(.start)' "$root/GOALPad/Game/TouchControlsView.swift"

# Gameplay must have one UIKit touch owner. A root zero-distance SwiftUI gesture can arbitrate the
# same streams away from TouchSurfaceView and make normal one-finger input appear only rarely.
if rg -Fq 'DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))' \
    "$root/GOALPad/Game/TouchControlsView.swift"; then
  echo "root zero-distance SwiftUI gesture still competes with gameplay touch" >&2
  exit 1
fi
rg -Fq 'reclaimTouchInput: reclaimTouchInput)' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'TouchControlsView.forwardGameplayTouchBatch(' \
  "$root/GOALPad/Game/TouchControlsView.swift"

# Zoom is one explicit semantic button. Reintroducing a full-screen pinch recognizer would compete
# with the accepted single-owner gameplay touch surface.
if rg -Fq 'UIPinchGestureRecognizer' "$root/GOALPad/Game/TouchControlsView.swift"; then
  echo "pinch recognizer still competes with gameplay touch" >&2
  exit 1
fi
rg -Fq 'Button { performZoomToggle() }' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'arrow.up.left.and.arrow.down.right' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'arrow.down.right.and.arrow.up.left' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'ModernTouchChromeLayout' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'pill(.stats)' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'chrome.centeredSessionFrame.midX' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'if isAwaitingTitleStart {' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq '.allowsHitTesting(zoomIsAvailable)' \
  "$root/GOALPad/Game/TouchControlsView.swift"
if rg -Fq 'Button { performCapturedStats() }' "$root/GOALPad/Game/TouchControlsView.swift"; then
  echo "captured start/pause menu still presents the redundant Stats pill" >&2
  exit 1
fi

# Controller activity and the shared idle timer suppress gameplay artwork without removing its
# raw or semantic hit target. A raw gameplay gesture suppresses all gameplay button/stick artwork
# until that same delivered gesture ends. Required title, native-menu, and captured-warp chrome
# stay on their dedicated visibility paths.
if rg -Fq 'if isVisible {' "$root/GOALPad/Game/TouchControlsView.swift"; then
  echo "controller suppression still removes a semantic touch control" >&2
  exit 1
fi
if rg -Fq '.opacity(isVisible ? 1 : 0)' "$root/GOALPad/Game/TouchControlsView.swift"; then
  echo "gameplay chrome visibility removed a mounted semantic control" >&2
  exit 1
fi
rg -Fq 'gameplayChromeIsVisible' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'hasActiveGameplayGesture: controls.hasActiveGameplayGesture' \
  "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'rightStickArtworkIsVisible' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq '.opacity(rightStickArtworkIsVisible ? 1 : 0)' \
  "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'ordinaryGameplayChromeIsVisible' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq '.opacity(ordinaryGameplayChromeIsVisible ? 1 : 0)' \
  "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'showsChrome: gameplayChromeIsVisible' \
  "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'facePromptActions.isEmpty' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq '.allowsHitTesting(zoomIsAvailable)' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'contextualFacePromptOwnsGameplayActions' "$root/GOALPad/Game/TouchControls.swift"
rg -Fq 'gameplayChromeFadeOutDelay: TimeInterval = 3' "$root/GOALPad/Game/TouchControls.swift"
rg -Fq 'noteScreenInteraction()' "$root/GOALPad/Game/TouchControls.swift"
rg -Fq 'isInteractive: nativeMenuControlsAreVisible' \
  "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'showsChrome: nativeMenuControlsAreVisible' \
  "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'isInteractive: warpGateTouchControlsAreVisible' \
  "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'showsChrome: warpGateTouchControlsAreVisible' \
  "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq '.allowsHitTesting(isInteractive)' "$root/GOALPad/Game/TouchControlsView.swift"

# The dynamic left movement artwork gains only an L label. Its accepted 66-point knob and
# movement-radius geometry remain the same as the deterministic byte checks above.
movement_stick_view=$(sed -n \
  '/private struct MovementStickArtwork: View {/,/private struct RightStickControl: View {/p' \
  "$root/GOALPad/Game/TouchControlsView.swift")
printf '%s\n' "$movement_stick_view" | rg -Fq 'private let knobSize: CGFloat = 66'
printf '%s\n' "$movement_stick_view" | rg -Fq 'Text("L")'
printf '%s\n' "$movement_stick_view" \
  | rg -Fq '.font(.system(size: 13, weight: .bold, design: .rounded))'
printf '%s\n' "$movement_stick_view" | rg -Fq '.foregroundStyle(.black.opacity(0.82))'
printf '%s\n' "$movement_stick_view" | rg -Fq '.offset(knobOffset)'

# Every title/pause right-stack command uses one fixed left-aligned content grid. Directional
# controls keep their existing centred D-pad geometry.
rg -Fq 'HStack(spacing: NativeMenuCommandLayout.iconTextSpacing)' \
  "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq '.padding(.horizontal, NativeMenuCommandLayout.horizontalInset)' \
  "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq '.frame(width: NativeMenuCommandLayout.iconColumnWidth,' \
  "$root/GOALPad/Game/TouchControlsView.swift"

# A directional native menu always draws a complete D-pad. Per-direction enablement still comes
# from NativeMenuTouchAction.isEnabled, so unsupported directions remain inert.
rg -Fq 'private static let dpadActions: Set<NativeMenuTouchAction>' \
  "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'menuButton(.up)' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'menuButton(.left)' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'menuButton(.down)' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'menuButton(.right)' "$root/GOALPad/Game/TouchControlsView.swift"

# Contextual face prompts are semantic buttons layered above the still-mounted UIKit gameplay
# surface. Controller suppression hides only their chrome, and warp/cutscene owners stay primary.
rg -Fq 'facePromptTouchSnapshot: session.facePromptTouchSnapshot' \
  "$root/GOALPad/ContentView.swift"
rg -Fq 'TouchSurface(controls: controls,' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'Text(action.glyph)' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq '.opacity(showsChrome ? 1 : 0)' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq '.allowsHitTesting(isInteractive)' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq '_ = reclaimTouchInput()' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'warpGateControlsVisible: warpGateTouchControlsAreVisible' \
  "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'warpGateCapturesInput: capturesWarpGateTouchInput' \
  "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'cutsceneSkipAvailable: cutsceneSkipAvailable' \
  "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'VStack(alignment: .trailing, spacing: 12)' \
  "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq '.frame(width: NativeMenuCommandLayout.width,' \
  "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'height: NativeMenuCommandLayout.height)' \
  "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'in: RoundedRectangle(cornerRadius: 16)' \
  "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'alignment: .bottomTrailing)' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq '.padding(.bottom, max(20, proxy.safeAreaInsets.bottom))' \
  "$root/GOALPad/Game/TouchControlsView.swift"
face_prompt_view=$(sed -n \
  '/private struct NativeFacePromptTouchControls: View {/,/private struct NativeWarpGateTouchControls: View {/p' \
  "$root/GOALPad/Game/TouchControlsView.swift")
if printf '%s\n' "$face_prompt_view" | rg -Fq 'Color.clear'; then
  echo "contextual face prompts introduced a clear capture surface" >&2
  exit 1
fi
if printf '%s\n' "$face_prompt_view" | rg -q 'DragGesture|simultaneousGesture|highPriorityGesture'; then
  echo "contextual face prompts introduced a competing full-screen gesture" >&2
  exit 1
fi
if printf '%s\n' "$face_prompt_view" | rg -Fq '.frame(maxWidth: .infinity'; then
  echo "contextual face prompt controls expanded into a full-screen hit-test container" >&2
  exit 1
fi
if printf '%s\n' "$face_prompt_view" \
    | rg -q '^[[:space:]]*Label\(|Text\(action\.(label|accessibilityLabel)'; then
  echo "contextual face prompts added visible inferred action text" >&2
  exit 1
fi

# Session lifecycle reads the native snapshot after boot and each successful frame, then clears it
# on shutdown. The full runner can typecheck these properties after the native bridge lands.
rg -Fq 'GOALPadRuntimeBridge.facePromptTouchSnapshot' "$root/GOALPad/Game/GameSession.swift"
rg -Fq 'updateFacePromptTouchSnapshot(.invalid)' "$root/GOALPad/Game/GameSession.swift"
