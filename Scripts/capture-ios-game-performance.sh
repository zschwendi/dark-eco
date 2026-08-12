#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage:
  Scripts/capture-ios-game-performance.sh \
    --device DEVICE --mode 60|hfr --kind overview|metal|cpu|power \
    --output DIRECTORY [--duration DURATION] [--dry-run]

The signed app must already be installed, running, and positioned at the start
of the test route. This script never installs or launches the app. It attaches
Instruments to the process named "Dark Eco", records one run, and exports the
trace table of contents next to it.

Default durations are 30s for overview, Metal, and CPU captures, and 5m for a
power capture. --duration accepts xctrace values such as 30s or 5m.
EOF
}

fail() {
  printf 'capture-ios-game-performance: %s\n' "$1" >&2
  exit 2
}

device=
mode=
kind=
output_directory=
duration=
dry_run=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --device)
      [ "$#" -ge 2 ] || fail "--device requires a value"
      device=$2
      shift 2
      ;;
    --mode)
      [ "$#" -ge 2 ] || fail "--mode requires a value"
      mode=$2
      shift 2
      ;;
    --kind)
      [ "$#" -ge 2 ] || fail "--kind requires a value"
      kind=$2
      shift 2
      ;;
    --output)
      [ "$#" -ge 2 ] || fail "--output requires a value"
      output_directory=$2
      shift 2
      ;;
    --duration)
      [ "$#" -ge 2 ] || fail "--duration requires a value"
      duration=$2
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

[ -n "$device" ] || fail "an explicit --device is required"
[ -n "$output_directory" ] || fail "an explicit --output directory is required"

case "$mode" in
  60|hfr) ;;
  *) fail "--mode must be 60 or hfr" ;;
esac

case "$kind" in
  overview)
    template='Game Performance Overview'
    default_duration=30s
    ;;
  metal)
    template='Metal System Trace'
    default_duration=30s
    ;;
  cpu)
    template='Time Profiler'
    default_duration=30s
    ;;
  power)
    template='Power Profiler'
    default_duration=5m
    ;;
  *)
    fail "--kind must be overview, metal, cpu, or power"
    ;;
esac

if [ -z "$duration" ]; then
  duration=$default_duration
fi
printf '%s\n' "$duration" | grep -Eq '^[1-9][0-9]*(ms|s|m|h)$' \
  || fail "--duration must be an xctrace duration such as 30s or 5m"

trace_path="$output_directory/dark-eco-build207-$mode-$kind.trace"
toc_path="$output_directory/dark-eco-build207-$mode-$kind-toc.xml"
metadata_path="$output_directory/dark-eco-build207-$mode-$kind-metadata.txt"
run_name="Dark Eco Build 207 $mode $kind"

if [ "$dry_run" -eq 1 ]; then
  printf 'Device: %s\n' "$device"
  printf 'Mode: %s\n' "$mode"
  printf 'Template: %s\n' "$template"
  printf 'Duration: %s\n' "$duration"
  printf 'Trace: %s\n' "$trace_path"
  printf 'Command: xcrun xctrace record --device DEVICE --template TEMPLATE '
  printf -- '--attach Dark Eco --time-limit DURATION --run-name RUN_NAME --output TRACE\n'
  exit 0
fi

[ ! -e "$output_directory" ] || fail "output directory already exists: $output_directory"
mkdir -p "$output_directory"

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
outer_head=$(git -C "$repo_root" rev-parse HEAD)
nested_head=$(git -C "$repo_root/OpenGOAL" rev-parse HEAD)
captured_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

{
  printf 'captured_at_utc=%s\n' "$captured_at"
  printf 'device=%s\n' "$device"
  printf 'mode=%s\n' "$mode"
  printf 'kind=%s\n' "$kind"
  printf 'template=%s\n' "$template"
  printf 'duration=%s\n' "$duration"
  printf 'process=Dark Eco\n'
  printf 'outer_head=%s\n' "$outer_head"
  printf 'nested_head=%s\n' "$nested_head"
  xcrun xctrace version
} > "$metadata_path"

printf 'Recording %s for %s. Drive the prepared route now.\n' "$run_name" "$duration"
xcrun xctrace record \
  --device "$device" \
  --template "$template" \
  --attach 'Dark Eco' \
  --time-limit "$duration" \
  --run-name "$run_name" \
  --output "$trace_path"

xcrun xctrace export --input "$trace_path" --toc --output "$toc_path"
printf 'Trace: %s\n' "$trace_path"
printf 'Table of contents: %s\n' "$toc_path"
printf 'Metadata: %s\n' "$metadata_path"
