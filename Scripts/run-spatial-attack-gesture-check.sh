#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-spatial-attack.XXXXXX")
trap 'find "$temporary" -depth -delete' EXIT HUP INT TERM

xcrun swiftc \
  -swift-version 6 \
  -strict-concurrency=complete \
  -warnings-as-errors \
  "$root/GOALPad/Input/SpatialAttackGestureRecognizer.swift" \
  "$root/Scripts/spatial-attack-gesture-check.swift" \
  -o "$temporary/spatial-attack-gesture-check"
"$temporary/spatial-attack-gesture-check"

xros_sdk=$(xcrun --sdk xros --show-sdk-path)
module_cache="$temporary/module-cache"
mkdir -p "$module_cache"
xcrun swiftc -typecheck \
  -target arm64-apple-xros26.5 \
  -sdk "$xros_sdk" \
  -module-cache-path "$module_cache" \
  -swift-version 6 \
  -strict-concurrency=complete \
  -enable-upcoming-feature MemberImportVisibility \
  -warnings-as-errors \
  -D GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE \
  -D VISION_SENSE_API_STUBS \
  "$root/GOALPad/Input/SpatialAttackGestureRecognizer.swift" \
  "$root/GOALPad/Vision/Immersive/VisionSenseMotionInput.swift" \
  "$root/Scripts/spatial-attack-gesture-check.swift"

xcrun swift -frontend -parse "$root/GOALPad/Input/ControllerInput.swift"

rg -Fq 'func pushControllerFrame(allowSpatialAttacks: Bool = false,' \
  "$root/GOALPad/Input/ControllerInput.swift"
rg -Fq 'func setSpatialGesturesEnabled(_ enabled: Bool)' \
  "$root/GOALPad/Input/ControllerInput.swift"
rg -Fq 'func updateSpatialGestureReference(originFromDevice: simd_float4x4?' \
  "$root/GOALPad/Input/ControllerInput.swift"
rg -Fq 'senseMotionInput.startWatching()' "$root/GOALPad/Input/ControllerInput.swift"
rg -Fq 'senseMotionInput.stopWatching()' "$root/GOALPad/Input/ControllerInput.swift"
rg -Fq 'guard watching, !trackedControllers.isEmpty else { return nil }' \
  "$root/GOALPad/Vision/Immersive/VisionSenseMotionInput.swift"
! sed -n '/func controllerSample()/,/private func installObservers/p' \
  "$root/GOALPad/Vision/Immersive/VisionSenseMotionInput.swift" | rg -Fq 'motionEnabled'
! rg -Fq 'predictAnchor' "$root/GOALPad/Vision/Immersive/VisionSenseMotionInput.swift"
# Gesture positions come only from measured anchors, never from integrated inertial velocity.
! rg -q 'velocity|angularVelocity' "$root/GOALPad/Vision/Immersive/VisionSenseMotionInput.swift"
rg -Fq 'timestamp: anchor.timestamp,' \
  "$root/GOALPad/Vision/Immersive/VisionSenseMotionInput.swift"
rg -Fq 'sample: .init(timestamp: pose.timestamp' \
  "$root/GOALPad/Input/SpatialAttackGestureRecognizer.swift"
rg -Fq 'anchor.coordinateSpace(for: .aim, correction: .none)' \
  "$root/GOALPad/Vision/Immersive/VisionSenseMotionInput.swift"
rg -Fq 'router.updateAccessoryAim(' \
  "$root/GOALPad/Vision/Immersive/VisionSenseMotionInput.swift"
rg -Fq 'router.consume(allowed: allowed, reference: reference, now: now)' \
  "$root/GOALPad/Vision/Immersive/VisionSenseMotionInput.swift"
rg -Fq 'reference: spatialReference,' "$root/GOALPad/Input/ControllerInput.swift"
rg -Fq 'state.buttons.insert(.square)' "$root/GOALPad/Input/ControllerInput.swift"
rg -Fq 'state.buttons.insert(.circle)' "$root/GOALPad/Input/ControllerInput.swift"
rg -Fq 'if spatialAttacks.contains(.jump) { state.buttons.insert(.cross) }' \
  "$root/GOALPad/Input/ControllerInput.swift"

# Ordinary-window and immersive gameplay both allow attacks; menus still suppress them, and the
# frame's presentation names the single route that may emit.
session="$root/GOALPad/Game/GameSession.swift"
rg -Fq 'spatialReference: immersiveFrameLoopOwner == nil' "$session"
! rg -Fq '&& immersiveFrameLoopOwner != nil && !usesControllerMenuNavigation' "$session"
rg -Fq '&& !usesControllerMenuNavigation,' "$session"
sed -n '/func releaseImmersiveFrameLoop/,/^    }/p' "$session" \
  | rg -Fq 'defer { refreshSpatialGestureTracking() }'
sed -n '/private func applyScenePhase/,/let lifecyclePhase/p' "$session" \
  | rg -Fq 'refreshSpatialGestureTracking()'
sed -n '/private func refreshSpatialGestureTracking/,/^    }/p' "$session" \
  | rg -Fq 'isRunning && title == .jak1'

echo "spatial Sense input checks passed"
