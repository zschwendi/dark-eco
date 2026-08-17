#!/bin/sh
# Check both unavailable-host and available-iOS compilation of the Jak II framework adapter.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-jak2-preparation-backend.XXXXXX")
trap 'rm -rf "$work"' EXIT

macos_sdk=$(xcrun --sdk macosx --show-sdk-path)
ios_sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
ios_version=$(xcrun --sdk iphonesimulator --show-sdk-version)
ios_target="arm64-apple-ios${ios_version}-simulator"
cp "$root/Scripts/jak2-native-preparation-framework-stub.h" \
  "$work/GOALPadJak2Runtime.h"
cp "$root/Scripts/jak2-native-preparation-framework.modulemap" \
  "$work/module.modulemap"

swift "$root/Scripts/jak2-native-preparation-backend-check.swift" "$root"

swiftc -sdk "$macos_sdk" \
  -module-cache-path "$work/macos-module-cache" \
  -swift-version 6 \
  -strict-concurrency=complete \
  -warnings-as-errors \
  -typecheck \
  "$root/GOALPad/Data/GameData.swift" \
  "$root/GOALPad/Data/GameDataNativePreparationBackend.swift" \
  "$root/GOALPad/Data/Jak2NativePreparationBackend.swift"

swiftc -sdk "$ios_sdk" \
  -target "$ios_target" \
  -module-cache-path "$work/ios-module-cache" \
  -I "$work" \
  -Xcc "-I$root/GOALPad/Native" \
  -import-objc-header "$root/GOALPad/Native/GOALPad-Bridging-Header.h" \
  -swift-version 6 \
  -strict-concurrency=complete \
  -warnings-as-errors \
  -typecheck \
  "$root/GOALPad/Data/GameData.swift" \
  "$root/GOALPad/Data/GameDataNativePreparationBackend.swift" \
  "$root/GOALPad/Data/Jak2NativePreparationBackend.swift"

echo "Jak II native preparation backend dual-compilation checks passed"
