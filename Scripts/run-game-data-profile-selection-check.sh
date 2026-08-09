#!/bin/sh
# Compile the data shell both as the unchanged public Jak 1 default and as an isolated Jak II shell.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
temporary=${TMPDIR:-/tmp}/goalpad-game-data-profile-selection
module_cache=$temporary/module-cache
mkdir -p "$module_cache"

sdk=$(xcrun --sdk macosx --show-sdk-path)
for profile in jak1 jak2; do
  output=$temporary/$profile-check
  condition=
  if [ "$profile" = jak2 ]; then
    condition="-D GOALPAD_JAK2"
  fi
  # Intentional word splitting supplies the optional two compiler arguments above.
  # shellcheck disable=SC2086
  swiftc -sdk "$sdk" \
    -disable-sandbox \
    -module-cache-path "$module_cache" \
    -swift-version 6 \
    -strict-concurrency=complete \
    -warnings-as-errors \
    $condition \
    "$root/GOALPad/Data/GameData.swift" \
    "$root/GOALPad/Library/GameLibrary.swift" \
    "$root/Scripts/game-data-profile-selection-check.swift" \
    -o "$output"
  "$output"
done
