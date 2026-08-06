#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-game-progress-state.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

xcrun clang++ -std=c++17 -Wall -Wextra -Werror -I"$root" \
  "$root/Scripts/game-progress-state-check.cpp" -o "$temporary/game-progress-state-check"
"$temporary/game-progress-state-check"

module_cache="$temporary/module-cache"
mkdir -p "$module_cache"
swiftc -typecheck -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path "$module_cache" \
  -import-objc-header "$root/GOALPad/Native/GOALPadRuntimeBridge.h" \
  "$root/Scripts/game-progress-state-bridge-check.swift"

swiftc -frontend -parse "$root/GOALPad/Game/GameSession.swift"
swiftc -frontend -parse "$root/GOALPad/Game/TouchControlsView.swift"
swiftc -frontend -parse "$root/GOALPad/ContentView.swift"
