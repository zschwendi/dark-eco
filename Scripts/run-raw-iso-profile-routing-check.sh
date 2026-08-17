#!/bin/sh
# Compile and run deterministic native-composer profile routing checks with synthetic jobs.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
out=${TMPDIR:-/tmp}/goalpad-raw-iso-profile-routing-check
module_cache=${TMPDIR:-/tmp}/goalpad-raw-iso-profile-routing-module-cache
mkdir -p "$module_cache"

run_check() {
  label=$1
  shift
  swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -module-cache-path "$module_cache" \
    -swift-version 6 \
    -strict-concurrency=complete \
    -warnings-as-errors \
    "$@" \
    "$root/GOALPad/Data/GameData.swift" \
    "$root/GOALPad/Data/GameDataInstallWorker.swift" \
    "$root/GOALPad/Data/GameDataNativePreparationBackend.swift" \
    "$root/GOALPad/Data/Jak2NativePreparationBackend.swift" \
    "$root/GOALPad/Data/RawISOCandidateProducer.swift" \
    "$root/Scripts/raw-iso-profile-routing-check.swift" \
    -o "$out-$label"

  "$out-$label"
}

run_check jak1
run_check jak2 -D GOALPAD_JAK2
