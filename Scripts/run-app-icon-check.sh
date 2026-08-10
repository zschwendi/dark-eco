#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
icon_dir="$root/GOALPad/Assets.xcassets/AppIcon.appiconset"
contents="$icon_dir/Contents.json"
vision_dir="$root/GOALPad/Assets.xcassets/AppIcon.solidimagestack"
vision_contents="$vision_dir/Contents.json"
vision_layer="$vision_dir/Back.solidimagestacklayer"
vision_image_dir="$vision_layer/Content.imageset"
vision_image="AppIcon-build151-visionOS-1024.png"
vision_front_image_dir="$vision_dir/Front.solidimagestacklayer/Content.imageset"
vision_front_image="AppIcon-build134-visionOS-front-transparent-1024.png"

jq empty "$contents"
jq empty "$vision_contents"
jq empty "$vision_layer/Contents.json"
jq empty "$vision_image_dir/Contents.json"
jq empty "$vision_dir/Front.solidimagestacklayer/Contents.json"
jq empty "$vision_front_image_dir/Contents.json"
test "$(rg -o 'AppIcon-build151-[^"]+\.png' "$contents" | wc -l | tr -d ' ')" = 11
if rg -Fq 'AppIcon-build131-' "$contents" || rg -Fq 'AppIcon-build134-' "$contents"; then
  echo "the asset catalog still references an older Eco icon" >&2
  exit 1
fi

check_icon() {
  file=$1
  expected=$2
  case "$file" in
    /*) path=$file ;;
    *) path="$icon_dir/$file" ;;
  esac
  test -f "$path"
  properties=$(sips -g pixelWidth -g pixelHeight -g hasAlpha -g profile "$path")
  width=$(printf '%s\n' "$properties" | awk '/pixelWidth:/{print $2}')
  height=$(printf '%s\n' "$properties" | awk '/pixelHeight:/{print $2}')
  alpha=$(printf '%s\n' "$properties" | awk '/hasAlpha:/{print $2}')
  profile=$(printf '%s\n' "$properties" | awk -F': ' '/profile:/{print $2}')
  test "$width" = "$expected"
  test "$height" = "$expected"
  test "$alpha" = no
  test "$profile" = "sRGB IEC61966-2.1"
}

check_icon AppIcon-build151-iOS-1024.png 1024
check_icon AppIcon-build151-mac-16.png 16
check_icon AppIcon-build151-mac-16@2x.png 32
check_icon AppIcon-build151-mac-32.png 32
check_icon AppIcon-build151-mac-32@2x.png 64
check_icon AppIcon-build151-mac-128.png 128
check_icon AppIcon-build151-mac-128@2x.png 256
check_icon AppIcon-build151-mac-256.png 256
check_icon AppIcon-build151-mac-256@2x.png 512
check_icon AppIcon-build151-mac-512.png 512
check_icon AppIcon-build151-mac-512@2x.png 1024

test "$(jq -r '.layers | length' "$vision_contents")" = 2
test "$(jq -r '.layers[0].filename' "$vision_contents")" = "Front.solidimagestacklayer"
test "$(jq -r '.layers[1].filename' "$vision_contents")" = "Back.solidimagestacklayer"
test "$(jq -r '.images[0].idiom' "$vision_image_dir/Contents.json")" = vision
test "$(jq -r '.images[0].filename' "$vision_image_dir/Contents.json")" = "$vision_image"
test "$(jq -r '.images[0].scale' "$vision_image_dir/Contents.json")" = 2x
check_icon "$vision_dir/Back.solidimagestacklayer/Content.imageset/$vision_image" 1024
cmp -s "$icon_dir/AppIcon-build151-iOS-1024.png" \
       "$vision_image_dir/$vision_image"
test "$(jq -r '.images[0].idiom' "$vision_front_image_dir/Contents.json")" = vision
test "$(jq -r '.images[0].filename' "$vision_front_image_dir/Contents.json")" = "$vision_front_image"
test "$(jq -r '.images[0].scale' "$vision_front_image_dir/Contents.json")" = 2x
test -f "$vision_front_image_dir/$vision_front_image"
front_properties=$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$vision_front_image_dir/$vision_front_image")
front_width=$(printf '%s\n' "$front_properties" | awk '/pixelWidth:/{print $2}')
front_height=$(printf '%s\n' "$front_properties" | awk '/pixelHeight:/{print $2}')
front_alpha=$(printf '%s\n' "$front_properties" | awk '/hasAlpha:/{print $2}')
test "$front_width" = 1024
test "$front_height" = 1024
test "$front_alpha" = yes

printf '%s\n' "Build 151 app icon checks passed"
