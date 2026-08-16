#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
checker="$root/Scripts/jak2-scene-sweep.py"

usage() {
  cat <<'EOF'
Usage:
  run-jak2-scene-sweep.sh --simulator UDID --bundle-id ID --process NAME --artifacts DIR [options] -- scene ...

Runs each supplied debug preview scene in a new simulator process. It neither boots, installs,
builds, nor shuts down a simulator. The env-gated debug launch path starts the prepared session
only when GOALPAD_JAK2_DEBUG_PREVIEW_SCENE is non-empty. Each scene artifact directory receives
launch.txt, runtime.log, before-saves.tsv, after-saves.tsv, three to five bounded active-scene
sample-*.png files, completed.png, visual-samples.tsv, and visual-selection.tsv. The active-scene
samples are spaced by telemetry ticks and resampled to the requested maximum dimension. The
selection reports a central-crop non-black signal to avoid accepting a fade as the only visual
checkpoint; it is capture triage only and does not prove renderer or gameplay correctness.
`current-visual-samples.txt` is replaced at the start of each run and is the only sample list
passed to the final visual selection, so prior scene artifacts cannot satisfy a rerun.

A scene passes only when the Build20 telemetry observes its identity, aframe progress, no-save
completion, zero chain/command/submit/stack errors, unchanged save manifest, required levels as a
subset, and at least one content-bearing active-scene sample. Missing foreground models, textures,
eye publications, Sprite3 textures, malformed DMA, and invalid bone data also fail the scene.

Options:
  --timeout SECONDS              Maximum wait per scene (default: 180)
  --save-root PATH               Override the app-container save root
  --required-level SCENE=LEVEL   Repeatable subset requirement; does not require an exact level set
  --sample-count COUNT           Active-scene screenshots, from 1 through 5 (default: 4)
  --sample-minimum-ticks TICKS   Minimum telemetry-tick separation (default: 120)
  --sample-max-dimension PIXELS  Resample each screenshot's longest edge (default: 1600)
EOF
}

parse_launch_pid() {
  awk '
    match($0, /: [0-9]+$/) {
      if (found) {
        invalid = 1
      } else {
        print substr($0, RSTART + 2, RLENGTH - 2)
        found = 1
      }
    }
    END {
      exit(found && !invalid ? 0 : 1)
    }
  '
}

simulator=
bundle_id=
process=
artifacts=
save_root=
timeout=180
sample_target=4
sample_minimum_ticks=120
sample_max_dimension=1600

scene_file=$(mktemp "${TMPDIR:-/tmp}/goalpad-jak2-scenes.XXXXXX")
requirements_file=$(mktemp "${TMPDIR:-/tmp}/goalpad-jak2-requirements.XXXXXX")
trap 'rm -f "$scene_file" "$requirements_file"' EXIT HUP INT TERM

while [ "$#" -gt 0 ]; do
  case "$1" in
    --simulator) simulator=$2; shift 2 ;;
    --bundle-id) bundle_id=$2; shift 2 ;;
    --process) process=$2; shift 2 ;;
    --artifacts) artifacts=$2; shift 2 ;;
    --save-root) save_root=$2; shift 2 ;;
    --timeout) timeout=$2; shift 2 ;;
    --required-level) printf '%s\n' "$2" >> "$requirements_file"; shift 2 ;;
    --sample-count) sample_target=$2; shift 2 ;;
    --sample-minimum-ticks) sample_minimum_ticks=$2; shift 2 ;;
    --sample-max-dimension) sample_max_dimension=$2; shift 2 ;;
    --self-test)
      self_test_pid=$(printf '%s\n' 'com.zephyrstudiosllc.eco.jak2dev: 84926' | parse_launch_pid)
      [ "$self_test_pid" = 84926 ]
      printf '%s\n' 'run-jak2-scene-sweep: self-test PASS'
      exit 0
      ;;
    --help) usage; exit 0 ;;
    --) shift; break ;;
    *) printf '%s\n' "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -z "$simulator" ] || [ -z "$bundle_id" ] || [ -z "$process" ] || [ -z "$artifacts" ]; then
  printf '%s\n' 'simulator, bundle ID, process, and artifacts are required' >&2
  usage >&2
  exit 2
fi
case "$timeout" in
  *[!0-9]*|'') printf '%s\n' 'timeout must be a positive integer' >&2; exit 2 ;;
esac
if [ "$timeout" -eq 0 ]; then
  printf '%s\n' 'timeout must be a positive integer' >&2
  exit 2
fi
case "$sample_target:$sample_minimum_ticks:$sample_max_dimension" in
  *[!0-9:]*|*::*|:*|*:) printf '%s\n' 'sample options must be positive integers' >&2; exit 2 ;;
esac
if [ "$sample_target" -lt 1 ] || [ "$sample_target" -gt 5 ] || [ "$sample_minimum_ticks" -eq 0 ] || [ "$sample_max_dimension" -eq 0 ]; then
  printf '%s\n' 'sample count must be 1 through 5; tick separation and max dimension must be positive' >&2
  exit 2
fi
if [ "$#" -eq 0 ]; then
  printf '%s\n' 'at least one scene name is required after --' >&2
  usage >&2
  exit 2
fi

mkdir -p "$artifacts"
printf '%s\n' "$@" > "$scene_file"

capture_log() {
  xcrun simctl spawn "$simulator" log show --last 5m --style compact \
    --predicate "process == '$process'" > "$1"
}

capture_screenshot() {
  xcrun simctl io "$simulator" screenshot "$1"
  sips -Z "$sample_max_dimension" "$1" >/dev/null
}

while IFS= read -r scene; do
  case "$scene" in
    ''|*[!A-Za-z0-9._-]*)
      printf '%s\n' "unsafe scene name: $scene" >&2
      exit 2
      ;;
  esac
  scene_artifacts="$artifacts/$scene"
  mkdir -p "$scene_artifacts"
  current_samples="$scene_artifacts/current-visual-samples.txt"
  : > "$current_samples"
  if [ -n "$save_root" ]; then
    scene_saves="$save_root"
  else
    container=$(xcrun simctl get_app_container "$simulator" "$bundle_id" data)
    scene_saves="$container/Library/Application Support/OpenGOAL/jak2/saves"
  fi
  python3 "$checker" --snapshot-saves "$scene_saves" --output "$scene_artifacts/before-saves.tsv"

  xcrun simctl terminate "$simulator" "$bundle_id" >/dev/null 2>&1 || true
  SIMCTL_CHILD_GOALPAD_JAK2_DEBUG_PREVIEW_SCENE="$scene" \
    xcrun simctl launch --terminate-running-process "$simulator" "$bundle_id" > "$scene_artifacts/launch.txt"
  pid=$(parse_launch_pid < "$scene_artifacts/launch.txt")
  if [ -z "$pid" ]; then
    printf '%s\n' "could not read launch PID for $scene" >&2
    exit 1
  fi

  elapsed=0
  sample_captured=0
  last_sample_tick=0
  completed=0
  printf 'sample\ttick\taframe\n' > "$scene_artifacts/visual-samples.tsv"
  while [ "$elapsed" -lt "$timeout" ]; do
    capture_log "$scene_artifacts/runtime.log"
    if [ "$sample_captured" -lt "$sample_target" ] && sample_info=$(python3 "$checker" --scene "$scene" --log "$scene_artifacts/runtime.log" --pid "$pid" --event sample --sample-after-tick "$last_sample_tick" --sample-minimum-ticks "$sample_minimum_ticks"); then
      sample_tick=$(printf '%s\n' "$sample_info" | awk -F '\t' 'NR == 1 { print $1 }')
      sample_aframe=$(printf '%s\n' "$sample_info" | awk -F '\t' 'NR == 1 { print $2 }')
      sample_index=$((sample_captured + 1))
      sample_path="$scene_artifacts/$(printf 'sample-%02d-tick-%s.png' "$sample_index" "$sample_tick")"
      capture_screenshot "$sample_path"
      printf '%s\t%s\t%s\n' "$(basename "$sample_path")" "$sample_tick" "$sample_aframe" >> "$scene_artifacts/visual-samples.tsv"
      printf '%s\n' "$sample_path" >> "$current_samples"
      sample_captured=$sample_index
      last_sample_tick=$sample_tick
    fi
    if python3 "$checker" --scene "$scene" --log "$scene_artifacts/runtime.log" --pid "$pid" --event completed; then
      capture_screenshot "$scene_artifacts/completed.png"
      completed=1
      break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
  minimum_samples=$sample_target
  if [ "$minimum_samples" -gt 3 ]; then
    minimum_samples=3
  fi
  if [ "$sample_captured" -lt "$minimum_samples" ] || [ "$completed" -eq 0 ]; then
    printf '%s\n' "$scene: captured $sample_captured active-scene visual samples before completion; need at least $minimum_samples" >&2
    exit 1
  fi

  python3 "$checker" --snapshot-saves "$scene_saves" --output "$scene_artifacts/after-saves.tsv"
  xcrun simctl terminate "$simulator" "$bundle_id" >/dev/null 2>&1 || true

  set -- python3 "$checker" --scene "$scene" --log "$scene_artifacts/runtime.log" --pid "$pid" \
    --save-before "$scene_artifacts/before-saves.tsv" --save-after "$scene_artifacts/after-saves.tsv" \
    --screenshot "$scene_artifacts/completed.png" --visual-sample-list "$current_samples" \
    --visual-report "$scene_artifacts/visual-selection.tsv"
  while IFS= read -r requirement; do
    set -- "$@" --required-level "$requirement"
  done < "$requirements_file"
  "$@"
done < "$scene_file"
