#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-camera-correction.XXXXXX")
module_cache="$build_dir/module-cache"
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
mkdir -p "$module_cache"

clang++ -std=c++17 -Wall -Wextra -Werror -I"$root" \
  "$root/Scripts/camera-correction-diagnostics-check.cpp" \
  -o "$build_dir/camera-correction-diagnostics-check"

"$build_dir/camera-correction-diagnostics-check"

swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path "$module_cache" \
  -import-objc-header "$root/GOALPad/Native/GOALPadRuntimeBridge.h" \
  -swift-version 5 \
  "$root/Scripts/camera-correction-diagnostics-bridge-check.swift" \
  -o "$build_dir/camera-correction-diagnostics-bridge-check"

"$build_dir/camera-correction-diagnostics-bridge-check"
