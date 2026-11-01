#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-vision-per-eye.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
mac_sdk=$(xcrun --sdk macosx --show-sdk-path)
xros_sdk=$(xcrun --sdk xros --show-sdk-path)
contract="$root/GOALPad/Vision/Immersive/VisionImmersiveFrameContract.swift"
plan="$root/GOALPad/Vision/Immersive/VisionImmersivePresentationPlan.swift"
presenter="$root/GOALPad/Vision/Immersive/VisionImmersiveFramePresenter.swift"
evidence="$root/GOALPad/Vision/Immersive/VisionImmersiveRenderEvidence.swift"
shader="$root/GOALPad/Vision/Immersive/VisionImmersivePresentation.metal"

swiftc "$root/Scripts/vision-immersive-per-eye-integration-check.swift" \
  -o "$temporary/integration-check"
"$temporary/integration-check" "$root"

xcrun --sdk macosx swiftc -parse-as-library -sdk "$mac_sdk" \
  -target arm64-apple-macosx26.5 \
  -module-cache-path "$temporary/mac-module-cache" -warnings-as-errors \
  -D GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE \
  "$contract" "$plan" "$root/Scripts/vision-immersive-per-eye-camera-check.swift" \
  -o "$temporary/camera-check"
"$temporary/camera-check"

xcrun --sdk macosx swiftc -parse-as-library -sdk "$mac_sdk" \
  -target arm64-apple-macosx26.5 \
  -module-cache-path "$temporary/mac-module-cache" -warnings-as-errors \
  -D GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE \
  "$contract" "$plan" "$root/Scripts/vision-immersive-menu-plane-check.swift" \
  -o "$temporary/menu-plane-check"
"$temporary/menu-plane-check"

xcrun -sdk macosx metal -Wall -Werror \
  -fmodules-cache-path="$temporary/metal-module-cache" \
  -DGOALPAD_EXPERIMENTAL_VISION_IMMERSIVE=1 \
  "$shader" -o "$temporary/per-eye-resolve.metallib"
xcrun -sdk xros metal -Wall -Werror \
  -fmodules-cache-path="$temporary/metal-module-cache" \
  -DGOALPAD_EXPERIMENTAL_VISION_IMMERSIVE=1 -c \
  "$shader" -o "$temporary/per-eye-resolve-xros.air"
test "$(xcrun -sdk xros metal-nm "$temporary/per-eye-resolve-xros.air" \
  | grep -c ' T vision_immersive_screen_')" -eq 2
test "$(xcrun -sdk xros metal-nm "$temporary/per-eye-resolve-xros.air" \
  | grep -c ' T vision_immersive_sample_')" -eq 2
test "$(xcrun -sdk xros metal-nm "$temporary/per-eye-resolve-xros.air" \
  | grep -c ' T vision_immersive_menu_plane_fragment')" -eq 1

xcrun --sdk macosx swiftc -parse-as-library -sdk "$mac_sdk" \
  -target arm64-apple-macosx26.5 \
  -module-cache-path "$temporary/gpu-module-cache" -warnings-as-errors \
  -D GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE \
  "$plan" "$evidence" \
  "$root/Scripts/vision-immersive-per-eye-resolve-gpu-check.swift" \
  -o "$temporary/gpu-check"
MTL_DEBUG_LAYER=1 "$temporary/gpu-check" "$temporary/per-eye-resolve.metallib"

xcrun --sdk xros swiftc -typecheck -sdk "$xros_sdk" \
  -target arm64-apple-xros26.5 -module-name GOALPadPerEyePresenterCheck \
  -swift-version 5 -default-isolation MainActor \
  -enable-upcoming-feature DisableOutwardActorInference \
  -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
  -enable-upcoming-feature InferIsolatedConformances \
  -enable-upcoming-feature InferSendableFromCaptures \
  -enable-upcoming-feature NonisolatedNonsendingByDefault \
  -module-cache-path "$temporary/xros-module-cache" -warnings-as-errors \
  -D GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE \
  "$contract" "$plan" \
  "$root/GOALPad/Vision/Immersive/VisionImmersiveCameraContract.swift" \
  "$evidence" "$presenter" \
  "$root/GOALPad/Vision/Immersive/VisionImmersiveSessionStatus.swift" \
  "$root/GOALPad/Vision/Immersive/VisionImmersiveTrackingPolicy.swift" \
  "$root/GOALPad/Vision/Immersive/VisionImmersiveMappingRejection.swift" \
  "$root/Scripts/vision-immersive-per-eye-presenter-stub.swift"

echo "visionOS true per-eye camera, menu plane, resolve, GPU evidence, and presenter checks passed"
