#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-native-runtime-router.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
module_cache="$temporary/module-cache"
mkdir -p "$module_cache"

swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path "$module_cache" \
  "$root/Scripts/native-runtime-router-source-check.swift" \
  -o "$temporary/native-runtime-router-source-check"
"$temporary/native-runtime-router-source-check" "$root"

ios_sdk=$(xcrun --sdk iphoneos --show-sdk-path)
swiftc -typecheck -target arm64-apple-ios18.0 -sdk "$ios_sdk" \
  -module-cache-path "$module_cache" \
  -import-objc-header "$root/GOALPad/Native/GOALPadRuntimeBridge.h" \
  "$root/Scripts/native-runtime-router-bridge-check.swift"

opengoal=${GOALPAD_OPENGOAL_SOURCE:-"$root/OpenGOAL"}
if [ ! -f "$opengoal/game/kernel/core/kernel_core.h" ]; then
  echo "OpenGOAL source is required for native syntax checks: $opengoal" >&2
  exit 1
fi

compile_native() {
  framework_search=$1
  xcrun clang++ -std=c++17 -x objective-c++ -fobjc-arc -fblocks \
    -Wall -Wextra -Werror -fsyntax-only -target arm64-apple-ios18.0 -isysroot "$ios_sdk" \
    $framework_search -I"$root/GOALPad/Native" -I"$root" -I"$opengoal" \
    -I"$opengoal/third-party/SDL/include" -I"$opengoal/third-party/fmt/include" \
    -I"$root/Scripts/Fixtures/WarpGateTouchAOT" \
    "$root/GOALPad/Native/GOALPadRuntimeBridge.mm"
  xcrun clang++ -std=c++17 -x objective-c++ -fobjc-arc -fblocks \
    -Wall -Wextra -Werror -Wno-missing-field-initializers -fsyntax-only \
    -target arm64-apple-ios18.0 -isysroot "$ios_sdk" \
    $framework_search -I"$root/GOALPad/Native" -I"$root" -I"$opengoal" \
    -I"$opengoal/third-party/SDL/include" -I"$opengoal/third-party/fmt/include" \
    -I"$root/Scripts/Fixtures/WarpGateTouchAOT" \
    "$root/GOALPad/Native/GOALPadRenderSurface.mm"
}

compile_native ""

if [ -n "${GOALPAD_JAK2_RUNTIME_HEADER:-}" ]; then
  framework="$temporary/GOALPadJak2Runtime.framework"
  mkdir -p "$framework/Headers"
  ln -s "$GOALPAD_JAK2_RUNTIME_HEADER" "$framework/Headers/GOALPadJak2Runtime.h"
  compile_native "-F$temporary"
fi

echo "native runtime router compile-light checks passed"
