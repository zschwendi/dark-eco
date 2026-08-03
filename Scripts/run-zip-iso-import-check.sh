#!/bin/sh
# Compile and run streaming ZIP-to-ISO checks without game data or app resources.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
out=${TMPDIR:-/tmp}/goalpad-zip-iso-import-check
module_cache=${TMPDIR:-/tmp}/goalpad-zip-iso-import-module-cache
mkdir -p "$module_cache"

swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path "$module_cache" \
  -swift-version 6 \
  -strict-concurrency=complete \
  -warnings-as-errors \
  "$root/GOALPad/Data/GameData.swift" \
  "$root/GOALPad/Data/GameDataImportSource.swift" \
  "$root/GOALPad/Data/GameDataInstallWorker.swift" \
  "$root/GOALPad/Data/ZIPISOCandidateProducer.swift" \
  "$root/Scripts/zip-iso-import-check.swift" \
  -o "$out"

"$out"
