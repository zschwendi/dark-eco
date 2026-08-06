#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-look-around-state.XXXXXX")
module_cache="$temporary/module-cache"
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
mkdir -p "$module_cache"

xcrun clang++ -std=c++17 -Wall -Wextra -Werror -I"$root" \
  "$root/Scripts/game-look-around-state-check.cpp" \
  -o "$temporary/game-look-around-state-check"
"$temporary/game-look-around-state-check"

swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path "$module_cache" \
  -import-objc-header "$root/GOALPad/Native/GOALPadRuntimeBridge.h" \
  -swift-version 5 \
  "$root/Scripts/game-look-around-state-bridge-check.swift" \
  -o "$temporary/game-look-around-state-bridge-check"
"$temporary/game-look-around-state-bridge-check"

swiftc -frontend -parse "$root/GOALPad/Game/GameSession.swift"
