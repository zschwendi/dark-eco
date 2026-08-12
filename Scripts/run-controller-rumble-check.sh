#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-rumble-check.XXXXXX")
trap 'find "$temporary_root" -depth -delete' EXIT HUP INT TERM

xcrun swiftc \
  "$root/GOALPad/Input/ControllerRumblePolicy.swift" \
  "$root/Scripts/controller-rumble-check.swift" \
  -o "$temporary_root/controller-rumble-check"
"$temporary_root/controller-rumble-check" "$root/GOALPad/Input/ControllerInput.swift"
xcrun swift -frontend -parse "$root/GOALPad/Input/ControllerRumblePolicy.swift"
xcrun swift -frontend -parse "$root/Scripts/controller-rumble-check.swift"
