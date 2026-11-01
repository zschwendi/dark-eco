#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-immersive-activity.XXXXXX")
trap 'find "$temporary" -depth -delete' EXIT HUP INT TERM

xcrun swiftc \
  -swift-version 6 \
  -strict-concurrency=complete \
  -warnings-as-errors \
  -D GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE \
  "$root/GOALPad/Vision/Immersive/VisionImmersiveActivity.swift" \
  "$root/Scripts/vision-immersive-activity-check.swift" \
  -o "$temporary/vision-immersive-activity-check"

"$temporary/vision-immersive-activity-check"

xcrun swift -frontend -parse \
  "$root/GOALPad/Vision/Immersive/VisionImmersiveActivity.swift"

echo "vision immersive activity integration checks passed"
