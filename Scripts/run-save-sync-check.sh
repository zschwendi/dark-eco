#!/bin/sh
# Compile and run the save mirror checks on this Mac. See save-sync-check.swift.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
out=${TMPDIR:-/tmp}/goalpad-save-sync-check
module_cache=${TMPDIR:-/tmp}/goalpad-save-sync-module-cache
mkdir -p "$module_cache"

swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path "$module_cache" \
  -swift-version 5 \
  "$root/GOALPad/Saves/SaveSyncEngine.swift" \
  "$root/Scripts/save-sync-check.swift" \
  -o "$out"

"$out"
