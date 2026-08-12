#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-game-frame-state.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

xcrun clang++ -std=c++17 -Wall -Wextra -Werror -I"$root" \
  "$root/Scripts/game-frame-state-snapshot-check.cpp" \
  -o "$temporary/game-frame-state-snapshot-check"
"$temporary/game-frame-state-snapshot-check"

module_cache="$temporary/module-cache"
mkdir -p "$module_cache"
macos_sdk=$(xcrun --sdk macosx --show-sdk-path)
swiftc -typecheck -sdk "$macos_sdk" \
  -module-cache-path "$module_cache" \
  -import-objc-header "$root/GOALPad/Native/GOALPadRuntimeBridge.h" \
  "$root/Scripts/game-frame-state-snapshot-bridge-check.swift"

opengoal=${GOALPAD_OPENGOAL_SOURCE:-"$root/OpenGOAL"}
if [ ! -f "$opengoal/game/kernel/core/kernel_core.h" ]; then
  echo "OpenGOAL source is required for native syntax checks: $opengoal" >&2
  exit 1
fi
aot_fixture="$root/Scripts/Fixtures/WarpGateTouchAOT"
ios_sdk=$(xcrun --sdk iphoneos --show-sdk-path)
native_includes="-I$aot_fixture -I$root -I$opengoal -I$opengoal/third-party/SDL/include -I$opengoal/third-party/fmt/include"

swiftc -c -target arm64-apple-ios18.0 -sdk "$ios_sdk" \
  -module-cache-path "$module_cache" \
  -import-objc-header "$root/GOALPad/Native/GOALPadRuntimeBridge.h" \
  "$root/Scripts/game-frame-state-snapshot-bridge-check.swift" \
  -o "$temporary/game-frame-state-snapshot-bridge-check.o"

xcrun clang++ -std=c++17 -Wall -Wextra -Werror -fsyntax-only -target arm64-apple-ios18.0 \
  -isysroot "$ios_sdk" $native_includes "$root/GOALPad/Native/GOALPadGameBoot.cpp"
xcrun clang++ -std=c++17 -x objective-c++ -fobjc-arc -Wall -Wextra -Werror \
  -fsyntax-only -target arm64-apple-ios18.0 -isysroot "$ios_sdk" $native_includes \
  "$root/GOALPad/Native/GOALPadRuntimeBridge.mm"
