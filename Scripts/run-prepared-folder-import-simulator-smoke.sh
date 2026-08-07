#!/bin/sh
# Run the simulator-only prepared-folder import smoke against an already-built Eco app.
set -eu

usage() {
  echo "usage: $0 /path/to/GOALPad.app" >&2
  echo "Set GOALPAD_PREPARED_IMPORT_SMOKE_UDID to select an approved M5 simulator." >&2
  exit 64
}

[ "$#" -eq 1 ] || usage
app=$1
[ -d "$app" ] || {
  echo "prepared-folder import simulator smoke: app not found: $app" >&2
  exit 66
}

bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")
[ -n "$bundle_id" ] || {
  echo "prepared-folder import simulator smoke: app has no bundle identifier" >&2
  exit 65
}

device_name='iPad Pro 11-inch (M5)'
udid=${GOALPAD_PREPARED_IMPORT_SMOKE_UDID:-}
if [ -z "$udid" ]; then
  udid=$(xcrun simctl list devices available | rg -F "$device_name" \
    | sed -nE 's/.*\(([0-9A-Fa-f-]{36})\).*/\1/p' | head -n 1)
fi
[ -n "$udid" ] || {
  echo "prepared-folder import simulator smoke: no available $device_name simulator" >&2
  exit 69
}

device_line=$(xcrun simctl list devices available | rg -F "$udid" | head -n 1 || true)
echo "$device_line" | rg -F "$device_name" >/dev/null || {
  echo "prepared-folder import simulator smoke: $udid is not an available $device_name" >&2
  exit 69
}

booted_by_script=0
bundle_installed=0
cleanup() {
  if [ "$bundle_installed" -eq 1 ]; then
    xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
  fi
  if [ "$booted_by_script" -eq 1 ]; then
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

if ! echo "$device_line" | rg -F '(Booted)' >/dev/null; then
  xcrun simctl boot "$udid"
  booted_by_script=1
fi
xcrun simctl bootstatus "$udid" -b >/dev/null
xcrun simctl install "$udid" "$app"
bundle_installed=1

container=$(xcrun simctl get_app_container "$udid" "$bundle_id" data)
token=$(uuidgen | tr '[:upper:]' '[:lower:]')
result_name="goalpad-prepared-folder-import-smoke-$token.json"
result="$container/tmp/$result_name"
artifact="${TMPDIR:-/tmp}/GOALPad-prepared-folder-import-smoke-$token.json"
launch_log="${TMPDIR:-/tmp}/GOALPad-prepared-folder-import-smoke-$token-launch.log"

if ! xcrun simctl launch --terminate-running-process "$udid" "$bundle_id" \
  "--goalpad-prepared-folder-import-smoke=$token" >"$launch_log" 2>&1; then
  echo "prepared-folder import simulator smoke: launch failed; log: $launch_log" >&2
  exit 1
fi

remaining=120
while [ ! -f "$result" ] && [ "$remaining" -gt 0 ]; do
  sleep 1
  remaining=$((remaining - 1))
done

if [ ! -f "$result" ]; then
  echo "prepared-folder import simulator smoke: timed out; launch log: $launch_log" >&2
  exit 1
fi

cp "$result" "$artifact"
status=$(plutil -extract status raw -o - "$artifact")
schema=$(plutil -extract schemaVersion raw -o - "$artifact")
reported_token=$(plutil -extract token raw -o - "$artifact")
if [ "$status" != 'PASS' ] || [ "$schema" != '1' ] || [ "$reported_token" != "$token" ]; then
  echo "prepared-folder import simulator smoke: FAIL; result: $artifact" >&2
  exit 1
fi

expected_files=$(plutil -extract expectedFileCount raw -o - "$artifact")
copied_files=$(plutil -extract successFilesCopied raw -o - "$artifact")
failure_code=$(plutil -extract failureCode raw -o - "$artifact")
preserved_candidates=$(plutil -extract preservedCandidateCount raw -o - "$artifact")
if [ "$copied_files" != "$expected_files" ] \
  || [ "$failure_code" != 'activationFailed' ] \
  || [ "$preserved_candidates" != '1' ]; then
  echo "prepared-folder import simulator smoke: inconsistent PASS result: $artifact" >&2
  exit 1
fi

echo "prepared-folder import simulator smoke passed"
echo "device=$device_name udid=$udid"
echo "files=$copied_files/$expected_files forced_failure=$failure_code preserved_candidates=$preserved_candidates"
echo "result=$artifact"
echo "launch_log=$launch_log"
