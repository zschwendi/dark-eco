#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-game-menu-state.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

xcrun clang++ -std=c++17 -Wall -Wextra -Werror -I"$root" \
  "$root/Scripts/game-menu-state-check.cpp" -o "$temporary/game-menu-state-check"
"$temporary/game-menu-state-check"

swiftc -frontend -parse "$root/GOALPad/Game/GameSession.swift"
