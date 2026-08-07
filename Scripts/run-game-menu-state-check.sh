#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-game-menu-state.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

xcrun clang++ -std=c++17 -Wall -Wextra -Werror -I"$root" \
  "$root/Scripts/game-menu-state-check.cpp" -o "$temporary/game-menu-state-check"
"$temporary/game-menu-state-check"

xcrun swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -import-objc-header "$root/GOALPad/Native/GOALPadRuntimeBridge.h" \
  "$root/Scripts/game-speeder-state-bridge-check.swift" \
  -o "$temporary/game-speeder-state-bridge-check"
"$temporary/game-speeder-state-bridge-check"

swiftc -frontend -parse "$root/GOALPad/Game/GameSession.swift"
