#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-vision-stereo-integration.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

swiftc "$root/Scripts/vision-stereo-integration-check.swift" \
  -o "$temporary/vision-stereo-integration-check"
"$temporary/vision-stereo-integration-check" "$root"

swiftc -parse-as-library \
  "$root/GOALPad/Vision/VisionStereoSubmissionWatchdog.swift" \
  "$root/Scripts/vision-stereo-submission-watchdog-check.swift" \
  -o "$temporary/vision-stereo-submission-watchdog-check"
"$temporary/vision-stereo-submission-watchdog-check"

xcrun clang++ -std=c++17 -Wall -Wextra -Werror -I"$root/OpenGOAL" \
  "$root/OpenGOAL/game/graphics/pipelines/metal/metal_external_submission_gate_test.cpp" \
  -o "$temporary/metal-external-submission-gate-test"
"$temporary/metal-external-submission-gate-test"

swiftc -typecheck \
  -sdk "$(xcrun --sdk xros --show-sdk-path)" \
  -target arm64-apple-xros26.5 \
  -module-cache-path "$temporary/xros-module-cache" \
  -import-objc-header "$root/GOALPad/Native/GOALPadRuntimeBridge.h" \
  "$root/Scripts/vision-stereo-native-bridge-check.swift"
echo "visionOS stereo native bridge typecheck passed"
