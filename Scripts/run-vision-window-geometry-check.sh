#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-vision-window-geometry.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

swiftc -parse-as-library \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -target arm64-apple-macosx26.5 \
  -module-cache-path "$temporary/module-cache" \
  -warnings-as-errors \
  "$root/GOALPad/Vision/VisionWindowGeometry.swift" \
  "$root/Scripts/vision-window-geometry-check.swift" \
  -o "$temporary/vision-window-geometry-check"
"$temporary/vision-window-geometry-check"

xcrun --sdk xros swiftc -typecheck \
  -target arm64-apple-xros26.5 \
  -module-cache-path "$temporary/xros-module-cache" \
  -warnings-as-errors \
  "$root/GOALPad/Vision/VisionWindowGeometry.swift"

echo "visionOS window geometry SDK check passed"
