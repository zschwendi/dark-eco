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
rg -Fq 'magnifyingglass.plus' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'magnifyingglass.minus' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'ModernTouchChromeLayout' "$root/GOALPad/Game/TouchControlsView.swift"
rg -Fq 'pill(.stats)' "$root/GOALPad/Game/TouchControlsView.swift"
