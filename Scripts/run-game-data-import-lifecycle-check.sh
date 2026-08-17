#!/bin/sh
# Compile and run deterministic importer cancellation and idle-timer ownership checks.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
out=${TMPDIR:-/tmp}/goalpad-game-data-import-lifecycle-check
module_cache=${TMPDIR:-/tmp}/goalpad-game-data-import-lifecycle-module-cache
mkdir -p "$module_cache"

swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path "$module_cache" \
  -swift-version 6 \
  -strict-concurrency=complete \
  -warnings-as-errors \
  "$root/GOALPad/Data/GameData.swift" \
  "$root/GOALPad/Data/GameDataNativePreparationBackend.swift" \
  "$root/GOALPad/Data/GameDataImportSource.swift" \
  "$root/GOALPad/Data/GameDataInstallWorker.swift" \
  "$root/GOALPad/Data/GameDataImporter.swift" \
  "$root/Scripts/game-data-import-lifecycle-check.swift" \
  -o "$out"

"$out"
