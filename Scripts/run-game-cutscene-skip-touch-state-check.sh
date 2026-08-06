#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-game-cutscene-skip-touch-state.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

xcrun clang++ -std=c++17 -Wall -Wextra -Werror -I"$root" \
  "$root/Scripts/game-cutscene-skip-touch-state-check.cpp" \
  -o "$temporary/game-cutscene-skip-touch-state-check"
"$temporary/game-cutscene-skip-touch-state-check"

module_cache="$temporary/module-cache"
mkdir -p "$module_cache"
sdk=$(xcrun --sdk macosx --show-sdk-path)
swiftc -typecheck -sdk "$sdk" \
  -module-cache-path "$module_cache" \
  -import-objc-header "$root/GOALPad/Native/GOALPadRuntimeBridge.h" \
  "$root/Scripts/game-cutscene-skip-touch-state-bridge-check.swift"

opengoal=${GOALPAD_OPENGOAL_SOURCE:-"$root/OpenGOAL"}
if [ ! -f "$opengoal/game/kernel/core/kernel_core.h" ]; then
  echo "OpenGOAL source is required for native syntax checks: $opengoal" >&2
  exit 1
fi
aot_fixture="$root/Scripts/Fixtures/WarpGateTouchAOT"

xcrun clang++ -std=c++17 -Wall -Wextra -Werror -fsyntax-only -isysroot "$sdk" \
  -I"$aot_fixture" -I"$root" -I"$opengoal" "$root/GOALPad/Native/GOALPadGameBoot.cpp"
xcrun clang++ -std=c++17 -x objective-c++ -fobjc-arc -Wall -Wextra -Werror \
  -fsyntax-only -isysroot "$sdk" -I"$aot_fixture" -I"$root" -I"$opengoal" \
  "$root/GOALPad/Native/GOALPadRuntimeBridge.mm"

echo "game cutscene skip touch state checks passed"
