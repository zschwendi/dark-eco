#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
swift "$root/Scripts/mobile-menu-copy-check.swift" "$root"
xcrun swift -frontend -parse "$root/Scripts/mobile-menu-copy-check.swift"
