#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-game-lifecycle.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
export CLANG_MODULE_CACHE_PATH="$temporary/clang-module-cache"
export SWIFT_MODULECACHE_PATH="$temporary/swift-module-cache"

swiftc -warnings-as-errors \
  "$root/GOALPad/Game/GameplayLifecycleState.swift" \
  "$root/GOALPad/Game/PresentationOwnershipState.swift" \
  "$root/GOALPad/Audio/AudioPlaybackPolicy.swift" \
  "$root/Scripts/game-lifecycle-check.swift" \
  -o "$temporary/game-lifecycle-check"
"$temporary/game-lifecycle-check"

swiftc -frontend -parse \
  "$root/GOALPad/Game/GameSession.swift" \
  "$root/GOALPad/Game/GameSurfaceView.swift" \
  "$root/GOALPad/Audio/AudioOutput.swift"
