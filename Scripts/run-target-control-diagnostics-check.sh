#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-target-control.XXXXXX")
module_cache="$build_dir/module-cache"
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
mkdir -p "$module_cache"

swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path "$module_cache" \
  -import-objc-header "$root/GOALPad/Native/GOALPadRuntimeBridge.h" \
  -swift-version 5 \
  "$root/Scripts/target-control-diagnostics-bridge-check.swift" \
  -o "$build_dir/target-control-diagnostics-bridge-check"

"$build_dir/target-control-diagnostics-bridge-check" \
  "$root/GOALPad/Game/GameSession.swift"
