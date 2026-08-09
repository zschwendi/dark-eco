#!/bin/sh
# Compile and run synthetic candidate-staging and activation checks on this Mac.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
out=${TMPDIR:-/tmp}/goalpad-game-data-install-check
module_cache=${TMPDIR:-/tmp}/goalpad-game-data-install-module-cache
mkdir -p "$module_cache"

swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path "$module_cache" \
  -swift-version 6 \
  -strict-concurrency=complete \
  -warnings-as-errors \
  "$root/GOALPad/Data/GameData.swift" \
  "$root/GOALPad/Data/GameDataInstallWorker.swift" \
  "$root/Scripts/game-data-install-check.swift" \
  -o "$out"

"$out"

"$root/Scripts/run-game-data-import-lifecycle-check.sh"
