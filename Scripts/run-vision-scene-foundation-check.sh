#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-vision-scene.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
requested_sdk=${GOALPAD_VISION_SDK:-all}
case "$requested_sdk" in
  all|macosx|iphoneos|xros) ;;
  *)
    echo "GOALPAD_VISION_SDK must be all, macosx, iphoneos, or xros" >&2
    exit 2
    ;;
esac

mode_source="$root/GOALPad/Vision/VisionPresentationMode.swift"
window_plan_source="$root/GOALPad/Vision/VisionWindowStereoClipPlan.swift"
window_plan_check="$root/Scripts/vision-window-stereo-clip-plan-check.swift"
window_surface_source="$root/GOALPad/Vision/VisionWindowStereoSurface.swift"
submission_watchdog_source="$root/GOALPad/Vision/VisionStereoSubmissionWatchdog.swift"
controller_ornament_source="$root/GOALPad/Vision/VisionControllerStatusOrnament.swift"
touch_view_source="$root/GOALPad/Game/TouchControlsView.swift"
touch_guide_source="$root/GOALPad/Game/TouchControlsGuideView.swift"
window_material="$root/GOALPad/Vision/VisionStereoWindow.rkassets/VisionStereoWindowMaterial.usda"
app_source="$root/GOALPad/GOALPadApp.swift"
content_source="$root/GOALPad/ContentView.swift"

mode_count=$(sed -n '/enum VisionPresentationMode:/,/var id:/p' "$mode_source" \
  | rg -c '^    case ')
test "$mode_count" -eq 2

for title in \
  "Comfort / Normal" \
  "Stereoscopic 3D"
do
  rg -Fq "\"$title\"" "$mode_source"
done

rg -Fq 'graphicsProfile == .modern && stereoscopic3DEnabled' "$mode_source"
rg -Fq 'readiness: .stereoscopicWindow' "$mode_source"
test "$(rg -c '^        WindowGroup' "$app_source")" -eq 1
rg -Fq '.environment(visionPresentation)' "$app_source"

for forbidden in \
  'ImmersiveSpace' \
  'openImmersiveSpace' \
  'dismissImmersiveSpace' \
  'import ARKit' \
  'ARKitSession' \
  'WorldTrackingProvider' \
  'queryDeviceAnchor' \
  'HeadTracker' \
  'head tracking' \
  'head-relative' \
  'CompositorLayer'
do
  if rg -Fq "$forbidden" "$root/GOALPad"; then
    echo "Shared Space stereo must not contain $forbidden" >&2
    exit 1
  fi
done
if rg -q 'GOALPadVisionSpatialScenes|VisionPresentationSessionBridge|CompositorLayer' "$app_source"; then
  echo "The product App must declare only its bounded WindowGroup" >&2
  exit 1
fi
for forbidden in \
  'TextureResource.DrawableQueue' \
  'nextDrawable()' \
  'presentOnSceneUpdate()' \
  'pendingPresentation' \
  'VisionWindowStereoDrawableQuarantine' \
  'CADisplayLink'
do
  if rg -Fq "$forbidden" "$window_surface_source"; then
    echo "The LowLevelTexture stereo surface must not contain $forbidden" >&2
    exit 1
  fi
done
test "$(rg -c 'LowLevelTexture\(descriptor: descriptor\)' "$window_surface_source")" -eq 2
test "$(rg -c 'TextureResource\(from:' "$window_surface_source")" -eq 2
test "$(rg -c 'replace\(using: commandBuffer\)' "$window_surface_source")" -eq 2
rg -Fq 'VisionWindowStereoRenderSystem.registerSystem()' "$window_surface_source"
rg -Fq 'updatingSystemWhen: .rendering' "$window_surface_source"
rg -Fq 'pixelFormat: .bgra8Unorm' "$window_surface_source"
rg -Fq 'pixelFormat: .depth32Float_stencil8' "$window_surface_source"
rg -Fq 'from: "VisionStereoWindowMaterial"' "$window_surface_source"
rg -Fq 'VisionWindowStereoClipPlanner.makePlan()' "$window_surface_source"
if rg -q 'windowFromHead|headFromEyes|surfaceEntity.transformMatrix' "$window_surface_source" \
  "$window_plan_source"; then
  echo "The bounded stereo pair must be independent of viewer and window pose" >&2
  exit 1
fi
rg -Fq 'ND_realitykit_geometry_switch_cameraindex_color3' "$window_material"
rg -Fq 'inputs:leftEye' "$window_material"
rg -Fq 'inputs:rightEye' "$window_material"
if rg -q 'copied_chain_data|OpenGOAL/' "$window_surface_source"; then
  echo "Bounded window surface must not expose or copy the native frame chain" >&2
  exit 1
fi

if ! sed -n '/if session.isRunning {/,/} else if session.isBooting/p' "$content_source" \
  | rg -Uq '(?s)#if !os\(visionOS\).*DiagnosticsOverlay'; then
  echo "visionOS gameplay must compile out DiagnosticsOverlay" >&2
  exit 1
fi
if ! rg -Uq '(?s)#if os\(iOS\).*TouchControlsView' "$content_source"; then
  echo "gameplay touch UI must remain iOS-only" >&2
  exit 1
fi
if ! rg -Uq '(?s)#if os\(iOS\).*TouchControlsGuideSheet' "$content_source"; then
  echo "the touch guide must remain iOS-only" >&2
  exit 1
fi
test "$(sed -n '1p' "$touch_view_source")" = '#if os(iOS)'
test "$(tail -n 1 "$touch_view_source")" = '#endif'
test "$(sed -n '1p' "$touch_guide_source")" = '#if os(iOS)'
test "$(tail -n 1 "$touch_guide_source")" = '#endif'

host_sdk_path=$(xcrun --sdk macosx --show-sdk-path)

swiftc -parse-as-library \
  -sdk "$host_sdk_path" \
  -target arm64-apple-macosx26.5 \
  -module-cache-path "$temporary/window-plan-module-cache" \
  -warnings-as-errors \
  "$window_plan_source" \
  "$window_plan_check" \
  -o "$temporary/vision-window-stereo-clip-plan-check"
"$temporary/vision-window-stereo-clip-plan-check"

for sdk_and_target in \
  "macosx arm64-apple-macosx26.5" \
  "iphoneos arm64-apple-ios26.5" \
  "xros arm64-apple-xros26.5"
do
  set -- $sdk_and_target
  sdk=$1
  target=$2
  if test "$requested_sdk" != all && test "$requested_sdk" != "$sdk"; then
    continue
  fi
  sdk_path=$(xcrun --sdk "$sdk" --show-sdk-path)
  module_cache=${GOALPAD_VISION_MODULE_CACHE:-$temporary/$sdk-module-cache}
  swiftc -typecheck \
    -sdk "$sdk_path" \
    -target "$target" \
    -module-cache-path "$module_cache" \
    -module-name GOALPadVisionSceneCheck \
    -swift-version 5 \
    -default-isolation MainActor \
    -enable-upcoming-feature DisableOutwardActorInference \
    -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
    -enable-upcoming-feature InferIsolatedConformances \
    -enable-upcoming-feature InferSendableFromCaptures \
    -enable-upcoming-feature NonisolatedNonsendingByDefault \
    -warnings-as-errors \
    "$app_source" \
    "$root/GOALPad/Game/PresentationOwnershipState.swift" \
    "$root/GOALPad/Game/GameSurfaceView.swift" \
    "$mode_source" \
    "$window_plan_source" \
    "$submission_watchdog_source" \
    "$window_surface_source" \
    "$controller_ornament_source" \
    "$root/Scripts/vision-scene-foundation-check.swift"
done

if test "$requested_sdk" = all || test "$requested_sdk" = xros; then
  xcrun realitytool compile \
    --output-reality "$temporary/VisionStereoWindowMaterial.reality" \
    --platform xros \
    --deployment-target 2.0 \
    --use-metal auto \
    "$root/GOALPad/Vision/VisionStereoWindow.rkassets"
  echo "visionOS camera-index ShaderGraph material check passed"
fi

echo "visionOS bounded Shared Space stereo and selected Apple SDK checks passed"
