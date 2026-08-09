#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-game-center.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

entitlements="$root/GOALPad/GOALPad.entitlements"
plutil -lint "$entitlements"
game_center_entitlement=$(plutil -extract 'com\.apple\.developer\.game-center' raw -expect bool "$entitlements")
test "$game_center_entitlement" = true
rg -Fq '@EnvironmentObject private var gameCenter: GameCenterService' \
  "$root/GOALPad/ContentView.swift"
rg -Fq 'gameCenter.setGameplayActive(isRunning)' "$root/GOALPad/ContentView.swift"

macos_sdk=$(xcrun --sdk macosx --show-sdk-path)
swiftc -sdk "$macos_sdk" \
  -module-cache-path "$temporary/state-module-cache" \
  -swift-version 5 \
  "$root/GOALPad/GameCenter/GameCenterAuthenticationState.swift" \
  "$root/Scripts/game-center-state-check.swift" \
  -o "$temporary/game-center-state-check"
"$temporary/game-center-state-check"

for sdk_and_target in \
  "macosx arm64-apple-macosx26.5" \
  "iphoneos arm64-apple-ios26.5" \
  "xros arm64-apple-xros26.5"
do
  set -- $sdk_and_target
  sdk=$1
  target=$2
  sdk_path=$(xcrun --sdk "$sdk" --show-sdk-path)
  swiftc -typecheck \
    -sdk "$sdk_path" \
    -target "$target" \
    -module-cache-path "$temporary/$sdk-module-cache" \
    -import-objc-header "$root/GOALPad/Native/GOALPadRuntimeBridge.h" \
    -module-name GOALPadGameCenterCheck \
    -swift-version 5 \
    -warnings-as-errors \
    "$root/GOALPad/GameCenter/GameCenterAuthenticationState.swift" \
    "$root/GOALPad/GameCenter/GameCenterService.swift" \
    "$root/GOALPad/GOALPadApp.swift" \
    "$root/GOALPad/Vision/VisionPresentationMode.swift" \
    "$root/Scripts/game-center-root-check.swift"
done

echo "Game Center entitlement, state, and Apple SDK checks passed"
