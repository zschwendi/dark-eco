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
scene_source="$root/GOALPad/Vision/VisionPresentationScenes.swift"
proof_source="$root/GOALPad/Vision/VisionStereoCompositorProofRenderer.swift"
plan_source="$root/GOALPad/Vision/VisionStereoFramePlan.swift"
plan_check="$root/Scripts/vision-stereo-frame-plan-check.swift"
proof_shader="$root/GOALPad/Vision/VisionStereoProof.metal"
window_plan_source="$root/GOALPad/Vision/VisionWindowStereoClipPlan.swift"
window_plan_check="$root/Scripts/vision-window-stereo-clip-plan-check.swift"
window_tracker_source="$root/GOALPad/Vision/VisionWindowStereoHeadTracker.swift"
window_surface_source="$root/GOALPad/Vision/VisionWindowStereoSurface.swift"
window_material="$root/GOALPad/Vision/VisionStereoWindow.rkassets/VisionStereoWindowMaterial.usda"

mode_count=$(sed -n '/enum VisionPresentationMode:/,/var id:/p' "$mode_source" \
  | rg -c '^    case ')
test "$mode_count" -eq 5

for title in \
  "Comfort / Normal" \
  "Stereoscopic 3D" \
  "Tabletop / Volume" \
  "Room-scale World" \
  "First-person VR"
do
  rg -Fq "\"$title\"" "$mode_source"
done

rg -Fq 'graphicsProfile == .modern && stereoscopic3DEnabled' "$mode_source"
rg -Fq 'readiness: .stereoscopicWindow' "$mode_source"
rg -Fq 'readiness: .unavailable' "$mode_source"
test "$(rg -c '^        ImmersiveSpace\(' "$scene_source")" -eq 1
rg -Fq 'case .openHeadTracking:' "$scene_source"
rg -Fq 'EmptyView()' "$scene_source"
if rg -q 'VisionStereoCompositorProofContent\(coordinator:' "$scene_source"; then
  echo "Synthetic compositor proof must not be declared as a product scene" >&2
  exit 1
fi
test "$(rg -c 'TextureResource.DrawableQueue\(descriptor\)' "$window_surface_source")" -eq 1
rg -Fq 'let leftQueue = try makeQueue(' "$window_surface_source"
rg -Fq 'let rightQueue = try makeQueue(' "$window_surface_source"
rg -Fq 'pixelFormat: .bgra8Unorm' "$window_surface_source"
rg -Fq 'pixelFormat: .depth32Float_stencil8' "$window_surface_source"
rg -Fq 'from: "VisionStereoWindowMaterial"' "$window_surface_source"
test "$(rg -c 'presentOnSceneUpdate()' "$window_surface_source")" -eq 2
rg -Fq 'queryDeviceAnchor(atTimestamp:' "$window_tracker_source"
rg -Fq 'relativeTo: .immersiveSpace' "$window_tracker_source"
rg -Fq 'ND_realitykit_geometry_switch_cameraindex_color3' "$window_material"
rg -Fq 'inputs:leftEye' "$window_material"
rg -Fq 'inputs:rightEye' "$window_material"
if rg -q 'copied_chain_data|OpenGOAL/' "$window_surface_source"; then
  echo "Bounded window surface must not expose or copy the native frame chain" >&2
  exit 1
fi

# The old compositor stays buildable as a deterministic diagnostic, but no product scene opens it.
rg -Fq 'CompositorLayer(configuration: self)' "$scene_source"
rg -Fq 'configuration.layout = supportedLayouts.contains(.dedicated)' "$scene_source"
rg -Fq 'worldTracking.queryDeviceAnchor' "$proof_source"
rg -Fq 'drawable.computeProjection' "$proof_source"
rg -Fq 'sliceIndex: mapping.sliceIndex' "$proof_source"
rg -Fq 'VisionStereoFramePlanner.makePlan' "$proof_source"
rg -Fq 'nonisolated final class VisionStereoCompositorProofRenderer' "$proof_source"
rg -Fq 'drawable.encodePresent(commandBuffer: commandBuffer)' "$proof_source"
if rg -q 'GameSurfaceView|CAMetalLayer' "$proof_source"; then
  echo "Synthetic compositor proof must remain isolated from the game framebuffer" >&2
  exit 1
fi

host_sdk_path=$(xcrun --sdk macosx --show-sdk-path)
swiftc -parse-as-library \
  -sdk "$host_sdk_path" \
  -target arm64-apple-macosx26.5 \
  -module-cache-path "$temporary/plan-module-cache" \
  -warnings-as-errors \
  "$plan_source" \
  "$plan_check" \
  -o "$temporary/vision-stereo-frame-plan-check"
"$temporary/vision-stereo-frame-plan-check"

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
    "$root/GOALPad/GOALPadApp.swift" \
    "$root/GOALPad/Game/PresentationOwnershipState.swift" \
    "$root/GOALPad/Game/GameSurfaceView.swift" \
    "$mode_source" \
    "$scene_source" \
    "$plan_source" \
    "$proof_source" \
    "$window_plan_source" \
    "$window_tracker_source" \
    "$window_surface_source" \
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

  mkdir -p "$temporary/metal-module-cache"
  xcrun -sdk xros metal \
    -Wall \
    -Werror \
    -fmodules-cache-path="$temporary/metal-module-cache" \
    -o "$temporary/vision-stereo-proof.metallib" \
    "$proof_shader"
  echo "visionOS diagnostic synthetic geometry shader check passed"
fi

echo "visionOS bounded-window stereo, diagnostic proof, and selected Apple SDK checks passed"
