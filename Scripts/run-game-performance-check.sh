#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-performance-check.XXXXXX")
trap 'find "$temporary_root" -depth -delete' EXIT HUP INT TERM

swiftc \
  "$root/GOALPad/Game/GamePerformanceSnapshot.swift" \
  "$root/Scripts/game-performance-check.swift" \
  -o "$temporary_root/game-performance-check"
"$temporary_root/game-performance-check" "$root"
xcrun swift -frontend -parse "$root/GOALPad/Game/GamePerformanceSnapshot.swift"
xcrun swift -frontend -parse "$root/Scripts/game-performance-check.swift"
