#!/bin/sh
# Typecheck the real touch-layout editor and its production dependencies for supported Apple SDKs.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-touch-layout-editor.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
requested_sdk=${GOALPAD_TOUCH_LAYOUT_SDK:-all}
case "$requested_sdk" in
  all|iphoneos|macosx) ;;
  *)
    echo "GOALPAD_TOUCH_LAYOUT_SDK must be all, iphoneos, or macosx" >&2
    exit 2
    ;;
esac

for sdk_and_target in \
  "iphoneos arm64-apple-ios26.5" \
  "macosx arm64-apple-macosx26.5"
do
  set -- $sdk_and_target
  sdk=$1
  target=$2
  if test "$requested_sdk" != all && test "$requested_sdk" != "$sdk"; then
    continue
  fi
  sdk_path=$(xcrun --sdk "$sdk" --show-sdk-path)
  swiftc -typecheck \
    -sdk "$sdk_path" \
    -target "$target" \
    -module-cache-path "$temporary/$sdk-module-cache" \
    -import-objc-header "$root/GOALPad/Native/GOALPadRuntimeBridge.h" \
    -module-name GOALPadTouchLayoutEditorCheck \
    -swift-version 5 \
    -warnings-as-errors \
    "$root/GOALPad/Input/KeyboardMouseInput.swift" \
    "$root/GOALPad/Game/TouchLayoutSettings.swift" \
    "$root/GOALPad/Game/PresentationSettings.swift" \
    "$root/GOALPad/Game/TouchControls.swift" \
    "$root/GOALPad/Game/TouchControlsView.swift" \
    "$root/GOALPad/Game/TouchLayoutEditorView.swift"
done

echo "Touch layout editor production Apple SDK typechecks passed"
