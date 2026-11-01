#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-controller-menu-navigation.XXXXXX")
trap 'find "$temporary" -depth -delete' EXIT HUP INT TERM

xcrun swiftc \
  -swift-version 6 \
  -strict-concurrency=complete \
  -warnings-as-errors \
  "$root/GOALPad/Input/ControllerMenuNavigation.swift" \
  "$root/Scripts/controller-menu-navigation-check.swift" \
  -o "$temporary/controller-menu-navigation-check"
"$temporary/controller-menu-navigation-check"

xcrun swift -frontend -parse "$root/GOALPad/Input/ControllerInput.swift"

rg -Fq 'func pushControllerFrame(allowSpatialAttacks: Bool = false,' \
  "$root/GOALPad/Input/ControllerInput.swift"
rg -Fq 'menuNavigationActive: Bool' "$root/GOALPad/Input/ControllerInput.swift"
rg -Fq 'x: gamepad.leftThumbstick.xAxis.value' "$root/GOALPad/Input/ControllerInput.swift"
rg -Fq 'x: sense.physicalLeftX' "$root/GOALPad/Input/ControllerInput.swift"
rg -Fq 'state.buttons.insert(Self.menuNavigationButton(for: direction))' \
  "$root/GOALPad/Input/ControllerInput.swift"

echo "controller menu navigation integration checks passed"
