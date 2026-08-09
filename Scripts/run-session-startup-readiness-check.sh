#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-session-startup.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
export CLANG_MODULE_CACHE_PATH="$temporary/clang-module-cache"
export SWIFT_MODULECACHE_PATH="$temporary/swift-module-cache"

swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  "$root/GOALPad/Data/GameData.swift" \
  "$root/GOALPad/Game/GameplayLifecycleState.swift" \
  "$root/Scripts/session-startup-readiness-check.swift" \
  -o "$temporary/session-startup-readiness-check"

"$temporary/session-startup-readiness-check"
