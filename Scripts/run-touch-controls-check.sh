#!/bin/sh
# Compile and run the on-screen controls check on this Mac. See touch-controls-check.swift.
set -eu

if ! command -v rg >/dev/null 2>&1; then
  rg() {
    case "$1" in
      *F*) grep "$@" ;;
      -*) option=$1; shift; grep -E "$option" "$@" ;;
      *) grep -E "$@" ;;
    esac
  }
fi

root=$(cd "$(dirname "$0")/.." && pwd)
out=${TMPDIR:-/tmp}/goalpad-touch-controls-check
module_cache=${TMPDIR:-/tmp}/goalpad-touch-controls-module-cache
touch_view_source=${TMPDIR:-/tmp}/goalpad-touch-controls-view-check.swift
mkdir -p "$module_cache"

# The product source is intentionally absent outside iOS. Strip only that verified outer guard
# from a temporary copy so this macOS-hosted deterministic test can keep exercising its helpers.
test "$(sed -n '1p' "$root/GOALPad/Game/TouchControlsView.swift")" = '#if os(iOS)'
test "$(tail -n 1 "$root/GOALPad/Game/TouchControlsView.swift")" = '#endif'
sed '1d;$d' "$root/GOALPad/Game/TouchControlsView.swift" > "$touch_view_source"

swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path "$module_cache" \
  -import-objc-header "$root/GOALPad/Native/GOALPadRuntimeBridge.h" \
  -swift-version 5 \
  "$root/GOALPad/Game/TouchLayoutSettings.swift" \
  "$root/GOALPad/Game/TouchControls.swift" \
  "$touch_view_source" \
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
rg -Fq 'controls?.reconcileActiveTouches(liveIdentifiers)' \
  "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'static func dismantleUIView' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'if window == nil { cancelAllTouches() }' \
  "$root/GOALPad/Game/TouchControlsView.swift"

# Artwork never owns gameplay hit testing. Suppression changes only opacity; the raw UIKit owner
# and explicit semantic buttons retain their targets through controller/touch transitions.
non_hit_test_artwork_count=$(rg -c '\.allowsHitTesting\(false\)' \
  "$root/GOALPad/Game/TouchControlsView.swift")
if [ "$non_hit_test_artwork_count" -lt 5 ]; then
  echo "gameplay artwork can still intercept a touch target" >&2
  exit 1
fi

# Zoom is one explicit semantic button. Reintroducing a full-screen pinch recognizer would compete
# with the accepted single-owner gameplay touch surface.
if rg -Fq 'UIPinchGestureRecognizer' "$root/GOALPad/Game/TouchControlsView.swift"; then
  echo "pinch recognizer still competes with gameplay touch" >&2
  exit 1
fi
rg -Fq 'Button { performZoomToggle() }' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'lookAroundState: lookAroundState' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'lookAroundState == .firstPerson' "$root/GOALPad/Game/TouchControls.swift"
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
# raw or semantic hit target. Every eligible gameplay ornament uses one shared opacity and one
# animation; invisible face/crouch swipe mapping must not suppress the remaining chrome.
if rg -Fq 'if isVisible {' "$root/GOALPad/Game/TouchControlsView.swift"; then
  echo "controller suppression still removes a semantic touch control" >&2
  exit 1
fi
if rg -Fq '.opacity(isVisible ? 1 : 0)' "$root/GOALPad/Game/TouchControlsView.swift"; then
  echo "gameplay chrome visibility removed a mounted semantic control" >&2
  exit 1
fi
rg -Fq 'gameplayChromeIsVisible' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'ordinaryGameplayChromeIsVisible' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq '.opacity(ordinaryGameplayChromeIsVisible ? 1 : 0)' \
  "$root/GOALPad/Game/TouchControlsView.swift"
if rg -Fq 'hasActiveGameplayGesture' "$root/GOALPad/Game/TouchControlsView.swift"; then
  echo "gesture activity still suppresses global gameplay chrome" >&2
  exit 1
fi
if test "$(rg -F -c '.opacity(ordinaryGameplayChromeIsVisible ? 1 : 0)' \
    "$root/GOALPad/Game/TouchControlsView.swift")" -ne 1; then
  echo "gameplay ornaments do not share exactly one idle opacity" >&2
  exit 1
fi
if test "$(rg -F -c 'value: ordinaryGameplayChromeIsVisible' \
    "$root/GOALPad/Game/TouchControlsView.swift")" -ne 1; then
  echo "gameplay ornaments do not share exactly one idle animation" >&2
  exit 1
fi
ordinary_layer=$(sed -n \
  '/private func ordinaryGameplayChrome(in proxy: GeometryProxy)/,/private func pill(/p' \
  "$root/GOALPad/Game/TouchControlsView.swift")
if printf '%s\n' "$ordinary_layer" | rg -Fq '.animation('; then
  echo "an ordinary gameplay child still owns a staggered animation" >&2
  exit 1
fi
if rg -q 'GestureRose|ForEach\(controls\.gestures\)' \
    "$root/GOALPad/Game/TouchControlsView.swift"; then
  echo "face/crouch swipe-guide artwork is still mounted" >&2
  exit 1
fi
rg -Fq 'case .gesture' "$root/GOALPad/Game/TouchControls.swift"
rg -Fq 'Self.swipeDirection(from: touch.origin, to: point)' \
  "$root/GOALPad/Game/TouchControls.swift"
rg -Fq 'rightStickArtworkIsAvailable' "$root/GOALPad/Game/TouchControlsView.swift"
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

# App-owned Dark Eco Settings occupies the ordinary Stats slot only after the exact initial title gate.
# Resume/Start keeps the paired session slot; the former top-right duplicate is gone.
rg -Fq 'NativeEcoSettingsPresentation.isVisible(' \
  "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'Button { openSettings() }' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq '.position(x: chrome.statsFrame.midX, y: chrome.statsFrame.midY)' \
  "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'ecoSettingsIsVisible ? chrome.startFrame.midX' \
  "$root/GOALPad/Game/TouchControlsView.swift"
eco_pill=$(sed -n \
  '/private var ecoSettingsPillLabel: some View {/,/^    }/p' \
  "$root/GOALPad/Game/TouchControlsView.swift")
printf '%s\n' "$eco_pill" | rg -Fq 'Image(systemName: "gearshape")'
printf '%s\n' "$eco_pill" | rg -Fq 'Text("DARK ECO")'
printf '%s\n' "$eco_pill" | rg -Fq '.frame(width: Self.pillWidth, height: 42)'
if rg -Fq 'session.isRunning && session.isNativeMenuOpen' \
    "$root/GOALPad/ContentView.swift"; then
  echo "redundant top-right Dark Eco Settings control is still mounted" >&2
  exit 1
fi
rg -Fq 'openSettings: { presentSettings(.jak1) }' "$root/GOALPad/ContentView.swift"
rg -Fq 'static let quit = 34' "$root/GOALPad/Game/TouchControls.swift"
rg -Fq 'static let quitTitle = 58' "$root/GOALPad/Game/TouchControls.swift"
rg -Fq 'static let memoryCardDataExists = 11' "$root/GOALPad/Game/TouchControls.swift"
rg -Fq 'return [.left, .right, .confirm]' "$root/GOALPad/Game/TouchControls.swift"

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
