#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-game-data-import-lifecycle.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
export CLANG_MODULE_CACHE_PATH="$temporary/clang-module-cache"
export SWIFT_MODULECACHE_PATH="$temporary/swift-module-cache"

swiftc -warnings-as-errors \
  "$root/GOALPad/Data/GameDataImportLifecyclePolicy.swift" \
  "$root/Scripts/game-data-import-lifecycle-check.swift" \
  -o "$temporary/game-data-import-lifecycle-check"
"$temporary/game-data-import-lifecycle-check"

swiftc -frontend -parse \
  "$root/GOALPad/Data/GameDataImporter.swift" \
  "$root/GOALPad/Data/GameDataSetupView.swift" \
  "$root/GOALPad/Library/GameLibraryView.swift" \
  "$root/GOALPad/ContentView.swift" \
  "$root/GOALPad/Game/GameSession.swift"

swiftc -frontend -parse "$root/Scripts/game-data-import-lifecycle-check.swift"
