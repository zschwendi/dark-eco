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

rg -Fq 'graphicsProfile == .modern ? .stereoscopic3D : .comfortNormal' "$mode_source"
rg -Fq 'readiness: .syntheticCompositorProof' "$mode_source"
rg -Fq 'readiness: .unavailable' "$mode_source"
rg -Fq 'WindowGroup(id: VisionPresentationMode.tabletopVolume.sceneID)' "$scene_source"
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
    "$mode_source" \
    "$scene_source" \
    "$plan_source" \
    "$proof_source" \
    "$root/Scripts/vision-scene-foundation-check.swift"
done

if test "$requested_sdk" = all || test "$requested_sdk" = xros; then
  mkdir -p "$temporary/metal-module-cache"
  xcrun -sdk xros metal \
    -Wall \
    -Werror \
    -fmodules-cache-path="$temporary/metal-module-cache" \
    -o "$temporary/vision-stereo-proof.metallib" \
    "$proof_shader"
  echo "visionOS synthetic geometry shader check passed"
fi

echo "visionOS presentation modes, deterministic stereo plan, and selected Apple SDK checks passed"
