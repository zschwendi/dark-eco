#!/bin/sh
# Compile and run deterministic title/profile routing checks without app or game data.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
out=${TMPDIR:-/tmp}/goalpad-title-data-routing-check
module_cache=${TMPDIR:-/tmp}/goalpad-title-data-routing-module-cache
mkdir -p "$module_cache"

swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path "$module_cache" \
  -swift-version 6 \
  -strict-concurrency=complete \
  -warnings-as-errors \
  "$root/GOALPad/Library/GameLibrary.swift" \
  "$root/GOALPad/Data/GameData.swift" \
  "$root/GOALPad/Data/GameTitleDataProfile.swift" \
  "$root/Scripts/title-data-routing-check.swift" \
  -o "$out"

"$out"
