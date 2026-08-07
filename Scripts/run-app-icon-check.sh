#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
icon_dir="$root/GOALPad/Assets.xcassets/AppIcon.appiconset"
contents="$icon_dir/Contents.json"

jq empty "$contents"
test "$(rg -o 'AppIcon-build134-[^"]+\.png' "$contents" | wc -l | tr -d ' ')" = 11
if rg -Fq 'AppIcon-build131-' "$contents"; then
  echo "the asset catalog still references the rejected Build 131 icon" >&2
  exit 1
fi

check_icon() {
  file=$1
  expected=$2
  test -f "$icon_dir/$file"
  properties=$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$icon_dir/$file")
  width=$(printf '%s\n' "$properties" | awk '/pixelWidth:/{print $2}')
  height=$(printf '%s\n' "$properties" | awk '/pixelHeight:/{print $2}')
  alpha=$(printf '%s\n' "$properties" | awk '/hasAlpha:/{print $2}')
  test "$width" = "$expected"
  test "$height" = "$expected"
  test "$alpha" = no
}

check_icon AppIcon-build134-iOS-1024.png 1024
check_icon AppIcon-build134-mac-16.png 16
check_icon AppIcon-build134-mac-16@2x.png 32
check_icon AppIcon-build134-mac-32.png 32
check_icon AppIcon-build134-mac-32@2x.png 64
check_icon AppIcon-build134-mac-128.png 128
check_icon AppIcon-build134-mac-128@2x.png 256
check_icon AppIcon-build134-mac-256.png 256
check_icon AppIcon-build134-mac-256@2x.png 512
check_icon AppIcon-build134-mac-512.png 512
check_icon AppIcon-build134-mac-512@2x.png 1024

printf '%s\n' "Build 134 app icon checks passed"
