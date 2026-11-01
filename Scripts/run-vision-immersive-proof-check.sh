#!/bin/sh
# Aggregate checks for opt-in native per-eye visionOS presentation. They cover source integration,
# matrix/cadence/resolve evidence, lifecycle and activity reducers, controller menu navigation,
# normal-build gating, and both whole-app visionOS configurations without touching a device.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-vision-immersive.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
immersive="$root/GOALPad/Vision/Immersive"
shader="$immersive/VisionImmersivePresentation.metal"
lifecycle="$immersive/VisionImmersiveProofLifecycle.swift"
tracking_policy="$immersive/VisionImmersiveTrackingPolicy.swift"
mac_sdk=$(xcrun --sdk macosx --show-sdk-path)
xros_sdk=$(xcrun --sdk xros --show-sdk-path)

xcrun --sdk macosx swiftc -sdk "$mac_sdk" -module-cache-path "$temporary/mac-module-cache" \
  "$root/Scripts/vision-immersive-proof-integration-check.swift" \
  -o "$temporary/integration-check"
"$temporary/integration-check" "$root"

"$root/Scripts/run-vision-immersive-per-eye-check.sh"

xcrun --sdk macosx swiftc -parse-as-library -sdk "$mac_sdk" -target arm64-apple-macosx26.5 \
  -module-cache-path "$temporary/mac-module-cache" -warnings-as-errors \
  -D GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE \
  "$lifecycle" "$root/Scripts/vision-immersive-proof-lifecycle-check.swift" \
  -o "$temporary/lifecycle-check"
"$temporary/lifecycle-check"

xcrun --sdk macosx swiftc -parse-as-library -sdk "$mac_sdk" \
  -swift-version 5 -default-isolation MainActor \
  -module-cache-path "$temporary/mac-module-cache" -warnings-as-errors \
  -D GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE \
  "$immersive/VisionImmersiveMappingRejection.swift" \
  "$root/Scripts/vision-immersive-mapping-rejection-check.swift" \
  -o "$temporary/mapping-rejection-check"
"$temporary/mapping-rejection-check" "$root"

xcrun --sdk macosx swiftc -parse-as-library -sdk "$mac_sdk" -target arm64-apple-macosx26.5 \
  -module-cache-path "$temporary/mac-module-cache" -warnings-as-errors \
  -D GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE \
  "$tracking_policy" "$root/Scripts/vision-immersive-tracking-policy-check.swift" \
  -o "$temporary/tracking-policy-check"
"$temporary/tracking-policy-check"

"$root/Scripts/run-vision-immersive-activity-check.sh"
"$root/Scripts/run-vision-immersive-session-status-check.sh"
"$root/Scripts/run-controller-menu-navigation-check.sh"

# The per-eye runner validates opt-in shader symbols and pixels. This separate negative check keeps
# the same shader file empty in normal builds.
xcrun -sdk xros metal -Wall -Werror -fmodules-cache-path="$temporary/metal-module-cache" \
  -c "$shader" -o "$temporary/immersive-shipping.air"
if xcrun -sdk xros metal-nm "$temporary/immersive-shipping.air" 2>&1 \
  | grep -q 'vision_immersive_'; then
  echo "A normal build must not contain the immersive presentation shader" >&2
  exit 1
fi
echo "visionOS immersive shader compiles out of normal builds"

# The whole app module, with the real bridging header, in both visionOS configurations. The
# SevenZip importer source is omitted only because its PLzmaSDK package is resolved by Xcode.
typecheck() {
  find "$root/GOALPad" -name '*.swift' ! -name SevenZipISOExtractor.swift -print0 \
    | xargs -0 xcrun --sdk xros swiftc -typecheck -sdk "$xros_sdk" \
      -target arm64-apple-xros26.5 -module-name Dark_Eco -swift-version 5 \
      -default-isolation MainActor \
      -enable-upcoming-feature MemberImportVisibility \
      -enable-upcoming-feature DisableOutwardActorInference \
      -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
      -enable-upcoming-feature InferIsolatedConformances \
      -enable-upcoming-feature InferSendableFromCaptures \
      -enable-upcoming-feature NonisolatedNonsendingByDefault \
      -import-objc-header "$root/GOALPad/Native/GOALPad-Bridging-Header.h" \
      -module-cache-path "$temporary/xros-module-cache" "$@"
}
typecheck > "$temporary/shipping.log" 2>&1 || { cat "$temporary/shipping.log"; exit 1; }
typecheck -D GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE > "$temporary/optin.log" 2>&1 || {
  cat "$temporary/optin.log"
  exit 1
}
grep 'warning:' "$temporary/shipping.log" | sort > "$temporary/shipping-warnings.txt" || true
grep 'warning:' "$temporary/optin.log" | sort > "$temporary/optin-warnings.txt" || true
if ! diff "$temporary/shipping-warnings.txt" "$temporary/optin-warnings.txt"; then
  echo "The immersive opt-in adds Swift warnings" >&2
  exit 1
fi
echo "visionOS shipping and immersive opt-in app modules typecheck with no new warnings"

for native in GOALPadMetalHost.mm GOALPadRenderSurface.mm; do
  xcrun --sdk xros clang++ -fsyntax-only -x objective-c++ -std=gnu++20 -fobjc-arc -fmodules \
    -fmodules-cache-path="$temporary/clang-module-cache" -target arm64-apple-xros26.5 \
    -isysroot "$xros_sdk" -DFMT_HEADER_ONLY=1 -DGOALPAD_SND_NO_CUBEB=1 \
    -I "$root/GOALPad/Native" -I "$root/OpenGOAL" -I "$root/OpenGOAL/third-party" \
    -I "$root/OpenGOAL/third-party/fmt/include" -I "$root/OpenGOAL/third-party/SDL/include" \
    -I "$root/OpenGOAL/third-party/glad/include" -I "$root/OpenGOAL/third-party/zstd/lib" \
    -I "$root/OpenGOAL/third-party/zstd/lib/common" -I "$root/Generated/jak1-aot" \
    "$root/GOALPad/Native/$native"
done
echo "visionOS physical per-eye native bridge sources compile"

echo "visionOS native per-eye immersive checks passed"
