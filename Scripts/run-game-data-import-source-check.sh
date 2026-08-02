#!/bin/sh
# Compile and run source-routing checks without game data or app resources.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
out=${TMPDIR:-/tmp}/goalpad-game-data-import-source-check
module_cache=${TMPDIR:-/tmp}/goalpad-game-data-import-source-module-cache
mkdir -p "$module_cache"

swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path "$module_cache" \
  -swift-version 6 \
  -strict-concurrency=complete \
  -warnings-as-errors \
  "$root/GOALPad/Data/GameDataImportSource.swift" \
  "$root/Scripts/game-data-import-source-check.swift" \
  -o "$out"

"$out"
