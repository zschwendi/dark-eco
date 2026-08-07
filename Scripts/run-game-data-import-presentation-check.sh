#!/bin/sh
# Compile and run import-copy checks without app resources or user game data.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
out=${TMPDIR:-/tmp}/goalpad-game-data-import-presentation-check
module_cache=${TMPDIR:-/tmp}/goalpad-game-data-import-presentation-module-cache
mkdir -p "$module_cache"

swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path "$module_cache" \
  -swift-version 6 \
  -strict-concurrency=complete \
  -warnings-as-errors \
  "$root/GOALPad/Data/GameDataImportPresentation.swift" \
  "$root/Scripts/game-data-import-presentation-check.swift" \
  -o "$out"

"$out"
swift "$root/Scripts/game-data-import-ui-check.swift" "$root"
