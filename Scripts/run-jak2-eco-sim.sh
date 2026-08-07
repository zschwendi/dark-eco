#!/bin/sh
# Build and exercise the development-only Jak II Eco Pro simulator target.

set -eu

usage() {
  echo "usage: GOALPAD_JAK2_DATA_DIR=<prepared-jak2-dir> $0 build|check|play" >&2
  echo "       optional: GOALPAD_JAK2_XCODE_BUILD, GOALPAD_JAK2_SIMULATOR_UDID," >&2
  echo "                 GOALPAD_JAK2_BUNDLE_ID" >&2
  exit 2
}

fail() {
  echo "Jak II Eco Pro simulator automation failed: $*" >&2
  exit 1
}

mode=${1:-}
case "$mode" in
  build|check|play) ;;
  *) usage ;;
esac

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repository_root=$(CDPATH= cd -- "$script_directory/.." && pwd -P)
xcode_build=${GOALPAD_JAK2_XCODE_BUILD:-/private/tmp/GOALPad-jak2-m5-xcode}
simulator=${GOALPAD_JAK2_SIMULATOR_UDID:-96C5C21A-B925-4213-82A3-90DCB8518339}
bundle_id=${GOALPAD_JAK2_BUNDLE_ID:-com.zephyrstudiosllc.eco.jak2dev}
data_root=${GOALPAD_JAK2_DATA_DIR:-}
aot_root="$repository_root/Generated/jak2-aot"
app_path="$xcode_build/Release-iphonesimulator/jak2-iphoneos-display-tick-proof.app"

[ -n "$data_root" ] || fail "GOALPAD_JAK2_DATA_DIR is not set"
[ -d "$data_root" ] || fail "missing prepared-data directory $data_root"
[ -f "$data_root/iso/KERNEL.CGO" ] || fail "missing $data_root/iso/KERNEL.CGO"
[ -f "$data_root/iso/GAME.CGO" ] || fail "missing $data_root/iso/GAME.CGO"
[ -f "$data_root/fr3/GAME.fr3" ] || fail "missing $data_root/fr3/GAME.fr3"

build() {
  "$repository_root/Scripts/verify-generated-aot.sh" "$aot_root" 840

  cmake -S "$repository_root/OpenGOAL" -B "$xcode_build" -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT=iphonesimulator \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 \
    -DBUILD_TESTING=OFF \
    -DOPENGOAL_BUILD_JAK2_IPHONEOS_AOT_LINK_ONLY=ON \
    -DOPENGOAL_JAK2_AOT_DIR="$aot_root" \
    -DOPENGOAL_JAK2_IPHONEOS_BUNDLE_IDENTIFIER=com.zephyrstudiosllc.eco.jak2linkproof \
    -DOPENGOAL_JAK2_IPHONEOS_DISPLAY_TICK_BUNDLE_IDENTIFIER="$bundle_id" \
    -DOPENGOAL_JAK2_IPHONEOS_DEVELOPMENT_TEAM=

  xcodebuild \
    -project "$xcode_build/jak.xcodeproj" \
    -scheme jak2-iphoneos-display-tick-proof \
    -configuration Release \
    -sdk iphonesimulator \
    -destination "platform=iOS Simulator,id=$simulator" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

  [ -d "$app_path" ] || fail "expected simulator app was not produced at $app_path"
  echo "Built simulator app: $app_path"
}

booted_here=false
check_cleanup() {
  xcrun simctl terminate "$simulator" "$bundle_id" >/dev/null 2>&1 || :
  if [ "$booted_here" = true ]; then
    xcrun simctl shutdown "$simulator" >/dev/null 2>&1 || :
  fi
}

ensure_booted() {
  if xcrun simctl list devices | rg -F "$simulator" | rg -Fq "(Booted)"; then
    return
  fi

  xcrun simctl boot "$simulator"
  xcrun simctl bootstatus "$simulator" -b
  booted_here=true
}

new_saves_directory() {
  mktemp -d "/private/tmp/goalpad-jak2-eco-$mode.XXXXXX"
}

install_and_launch() {
  saves_directory=$1
  xcrun simctl install "$simulator" "$app_path"
  SIMCTL_CHILD_GOALPAD_JAK2_DATA_DIR="$data_root" \
    SIMCTL_CHILD_GOALPAD_JAK2_SAVES_DIR="$saves_directory" \
    xcrun simctl launch --terminate-running-process "$simulator" "$bundle_id"
}

check() {
  [ -d "$app_path" ] || fail "missing built simulator app at $app_path; run '$0 build' first"

  stamp=$(date +%Y%m%d-%H%M%S)
  log_path="/private/tmp/goalpad-jak2-eco-check-$stamp-$$.log"
  screenshot_path="/private/tmp/goalpad-jak2-eco-check-$stamp-$$.png"
  saves_directory=$(new_saves_directory)
  trap check_cleanup 0 HUP INT TERM

  ensure_booted
  log_start=$(date '+%Y-%m-%d %H:%M:%S')
  install_and_launch "$saves_directory"
  sleep 10
  xcrun simctl spawn "$simulator" log show --style compact --start "$log_start" \
    --predicate 'process == "jak2-iphoneos-display-tick-proof"' \
    >"$log_path" 2>&1 || :
  xcrun simctl io "$simulator" screenshot "$screenshot_path"

  echo "Log: $log_path"
  echo "Screenshot: $screenshot_path"
  echo "Saves: $saves_directory"

  [ -s "$log_path" ] || fail "unified log capture is empty; see $log_path"
  rg -Fq "GOALPAD_JAK2_ECO_TITLE PASS" "$log_path" || \
    fail "title-loop success telemetry is absent; see $log_path"
  rg -Fq "GOALPAD_JAK2_ECO_INPUT_PROBE PASS" "$log_path" || \
    fail "bounded GOAL input-read proof is absent; see $log_path"
  rg -Fq "GOALPAD_JAK2_ECO_AUDIO RUNNING" "$log_path" || \
    fail "Apple audio output did not start; see $log_path"
  rg "GOALPAD_JAK2_ECO_AUDIO callbacks=[1-9][0-9]*" "$log_path" >/dev/null || \
    fail "Apple audio callback telemetry is absent; see $log_path"
  rg "GOALPAD_JAK2_ECO_TITLE PASS.*completed=[1-9][0-9]* failed=0" "$log_path" \
    >/dev/null || fail "successful Metal completion telemetry is absent; see $log_path"
  if rg -iq 'Terminating app due to uncaught exception|Exception Type:|Fatal error:|Assertion failed|SIGABRT|SIGSEGV|crash' "$log_path"; then
    fail "unified log contains an obvious runtime failure or crash; see $log_path"
  fi

  echo "Jak II Eco Pro simulator check passed."
}

play() {
  [ -d "$app_path" ] || fail "missing built simulator app at $app_path; run '$0 build' first"

  saves_directory=$(new_saves_directory)
  ensure_booted
  install_and_launch "$saves_directory"

  echo "Jak II Eco Pro is running on simulator $simulator."
  echo "Saves: $saves_directory"
  echo "Stop app: xcrun simctl terminate $simulator $bundle_id"
  echo "Shut down simulator: xcrun simctl shutdown $simulator"
}

case "$mode" in
  build) build ;;
  check) check ;;
  play) play ;;
esac
