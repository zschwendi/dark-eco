#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-immersive-status.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
mac_sdk=$(xcrun --sdk macosx --show-sdk-path)

xcrun --sdk macosx swiftc -parse-as-library -sdk "$mac_sdk" \
  -target arm64-apple-macosx26.5 -swift-version 5 -warnings-as-errors \
  -strict-concurrency=complete \
  -module-cache-path "$temporary/module-cache" \
  -D GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE \
  "$root/GOALPad/Vision/Immersive/VisionImmersiveSessionStatus.swift" \
  "$root/Scripts/vision-immersive-session-status-check.swift" \
  -o "$temporary/session-status-check"

"$temporary/session-status-check" "$temporary/immersive-session-status.json"
echo "visionOS immersive session status helper compiles with strict concurrency"
