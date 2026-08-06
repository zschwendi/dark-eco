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

# Controller activity suppresses every touch-control drawing without removing its semantic hit
# target. The first hidden touch must still perform its action and reclaim touch presentation.
if rg -Fq 'if isVisible {' "$root/GOALPad/Game/TouchControlsView.swift"; then
  echo "controller suppression still removes a semantic touch control" >&2
  exit 1
fi
rg -Fq '.opacity(isVisible ? 1 : 0)' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'isInteractive: nativeMenuControlsAreVisible' \
  "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'showsChrome: nativeMenuControlsAreVisible' \
  "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'isInteractive: warpGateTouchControlsAreVisible' \
  "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'showsChrome: warpGateTouchControlsAreVisible' \
  "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq '.allowsHitTesting(isInteractive)' "$root/GOALPad/Game/TouchControlsView.swift"

# Every title/pause right-stack command uses one fixed left-aligned content grid. Directional
# controls keep their existing centred D-pad geometry.
rg -Fq 'HStack(spacing: NativeMenuCommandLayout.iconTextSpacing)' \
  "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq '.padding(.horizontal, NativeMenuCommandLayout.horizontalInset)' \
  "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq '.frame(width: NativeMenuCommandLayout.iconColumnWidth,' \
  "$root/GOALPad/Game/TouchControlsView.swift"
