#!/bin/sh
set -u

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
checker="$root/Scripts/jak2-task-smoke.py"

usage() {
  cat <<'EOF'
Usage:
  run-jak2-task-smoke.sh --simulator UDID --bundle-id ID --process NAME --artifacts NEW_DIR
                         [--timeout 120] [--dwell-seconds 10] [--frame-diagnostics] -- TASK=LEVEL ...

Launches each authored Jak II play task (GOALPAD_JAK2_DEBUG_PLAY_TASK=TASK) in its own fresh app
process on an already-booted, already-installed simulator. It never boots, installs, builds, or
shuts down a simulator, and only terminates BUNDLE_ID on the passed UDID.

Precondition (owned by the caller): a dedicated fixture simulator with cloud sync disabled. The
only observed save root is the app container's Library/Application Support/OpenGOAL/jak2/saves;
there is no override. Saves are hashed after the prior process is terminated and again after this
task's process is terminated; any difference fails the task. Nothing is written to game, save, or
cloud files.

A task passes only with an explicit resolved play-task marker for the exact task (queued/request
markers are not success), the expected level active (not merely desired), mode=game, smoke-target=1/1,
and ticks, completed chains/commands, acquired drawables and submitted drawables increasing across
at least 3 PID-matched runtime observations spanning DWELL wall seconds of unified-log time, with
no runtime/stack/foreground/renderer hard errors anywhere in the capture and the process still
alive immediately before the runner's own termination. Exactly three screenshots are taken as
the stable window progresses (start, half dwell, full dwell); all must be non-black. This is
capture triage only: it proves neither rendering nor audio correctness nor mission completion.
Presentation callbacks are unavailable on simulator (addPresentedHandler is excluded); counters
prove acquisition/submission/completion progress, not physical display. Drops still fail the task.
Zero callback-derived drops do not prove the absence of dropped frames on simulator.

Per-task artifacts (NEW_DIR/TASK/): launch.txt, launch-error.txt, stdout.log, stderr.log,
runtime.log, poll.tsv, before-saves.tsv, after-saves.tsv, shot-1..3.png, screenshots.tsv,
visual-selection.tsv, result.json. Batch: tasks.tsv, summary.tsv, summary.json. Every task runs
even after failures; exit status is nonzero if any task failed. NEW_DIR must not exist.
EOF
}

parse_launch_pid() {
  awk '
    match($0, /: [0-9]+$/) {
      if (found) { invalid = 1 } else { print substr($0, RSTART + 2, RLENGTH - 2); found = 1 }
    }
    END { exit(found && !invalid ? 0 : 1) }
  '
}

simulator= bundle_id= process= artifacts= timeout=120 dwell=10 frame_diagnostics=0
log_stream_pid= current_pid= current_launch=0
max_log_bytes=67108864

while [ "$#" -gt 0 ]; do
  case "$1" in
    --simulator|--bundle-id|--process|--artifacts|--timeout|--dwell-seconds)
      [ "$#" -ge 2 ] || { printf '%s\n' "$1 requires a value" >&2; exit 2; }
      case "$1" in
        --simulator) simulator=$2 ;; --bundle-id) bundle_id=$2 ;; --process) process=$2 ;;
        --artifacts) artifacts=$2 ;; --timeout) timeout=$2 ;; --dwell-seconds) dwell=$2 ;;
      esac
      shift 2 ;;
    --frame-diagnostics) frame_diagnostics=1; shift ;;
    --self-test)
      self_test_pid=$(printf '%s\n' 'com.zephyrstudiosllc.eco.jak2dev: 84926' | parse_launch_pid) || exit 1
      [ "$self_test_pid" = 84926 ] || exit 1
      if printf '%s\n%s\n' 'a: 1' 'b: 2' | parse_launch_pid >/dev/null; then exit 1; fi
      python3 "$checker" --self-test || exit 1
      printf '%s\n' 'run-jak2-task-smoke: self-test PASS'
      exit 0 ;;
    --help|-h) usage; exit 0 ;;
    --) shift; break ;;
    *) printf '%s\n' "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -z "$simulator" ] || [ -z "$bundle_id" ] || [ -z "$process" ] || [ -z "$artifacts" ]; then
  printf '%s\n' '--simulator, --bundle-id, --process, and --artifacts are required' >&2
  usage >&2
  exit 2
fi
case "$simulator" in *[!0-9A-Fa-f-]*) printf '%s\n' 'simulator must be an explicit UDID' >&2; exit 2 ;; esac
case "$timeout:$dwell" in
  *[!0-9:]*|:*|*:) printf '%s\n' 'timeout and dwell must be positive integers' >&2; exit 2 ;;
esac
if [ "$dwell" -eq 0 ] || [ "$timeout" -le "$dwell" ]; then
  printf '%s\n' 'dwell must be positive and less than timeout' >&2
  exit 2
fi
pairs=$(python3 "$checker" --validate-pairs "$@") || exit 2
python3 "$checker" --prepare-artifacts "$artifacts" || exit 2
artifacts=$(CDPATH= cd -- "$artifacts" && pwd) || exit 2
printf '%s\n' "$pairs" > "$artifacts/tasks.tsv"

stop_log_stream() {
  if [ -n "$log_stream_pid" ]; then
    kill "$log_stream_pid" >/dev/null 2>&1 || true
    wait "$log_stream_pid" >/dev/null 2>&1 || true
    log_stream_pid=
  fi
}

terminate_app() {
  xcrun simctl terminate "$simulator" "$bundle_id" >/dev/null 2>&1 || true
}

cleanup() {
  stop_log_stream
  if [ "$current_launch" -eq 1 ]; then
    terminate_app
    current_pid= current_launch=0
  fi
}

trap cleanup EXIT
trap 'cleanup; trap - EXIT; exit 130' HUP INT TERM

# Simulator app processes are host processes; confirm the owned PID is still our executable.
process_alive() {
  comm=$(ps -p "$1" -o comm= 2>/dev/null) || return 1
  case "$comm" in "$process"|*/"$process") return 0 ;; *) return 1 ;; esac
}

file_bytes() {
  if [ -f "$1" ]; then wc -c < "$1" | tr -d ' '; else printf '0\n'; fi
}

run_task() {
  task=$1 level=$2 dir="$artifacts/$1" failure= pid=
  mkdir "$dir" || return 1
  printf 'elapsed\tstatus\twindow_ms\tobservations\treason\n' > "$dir/poll.tsv"
  printf 'shot\telapsed\twindow_ms\tobservations\n' > "$dir/screenshots.tsv"

  terminate_app
  if container=$(xcrun simctl get_app_container "$simulator" "$bundle_id" data 2> "$dir/container-error.txt"); then
    saves="$container/Library/Application Support/OpenGOAL/jak2/saves"
    python3 "$checker" --snapshot-saves "$saves" --output "$dir/before-saves.tsv" || failure="telemetry-failure:before-save snapshot failed"
  else
    failure="launch-error:app container lookup failed"
  fi

  if [ -z "$failure" ]; then
    : > "$dir/runtime.log"
    xcrun simctl spawn "$simulator" log stream --style compact --level debug \
      --predicate "process == '$process'" > "$dir/runtime.log" 2>&1 &
    log_stream_pid=$!
    sleep 1
    set -- env -u SIMCTL_CHILD_GOALPAD_JAK2_DEBUG_PREVIEW_SCENE SIMCTL_CHILD_GOALPAD_JAK2_DEBUG_PLAY_TASK="$task"
    [ "$frame_diagnostics" -eq 1 ] && set -- "$@" SIMCTL_CHILD_GOALPAD_FRAME_TIMING_DIAGNOSTICS=1
    current_launch=1
    if "$@" xcrun simctl launch --terminate-running-process --stdout="$dir/stdout.log" --stderr="$dir/stderr.log" \
        "$simulator" "$bundle_id" > "$dir/launch.txt" 2> "$dir/launch-error.txt" \
        && pid=$(parse_launch_pid < "$dir/launch.txt"); then
      current_pid=$pid
    else
      pid=
      failure="launch-error:simctl launch failed or printed no single PID"
    fi
  fi

  started=$(date +%s) shots=0 last_shot_count=0
  while [ -z "$failure" ]; do
    elapsed=$(( $(date +%s) - started ))
    if [ "$elapsed" -ge "$timeout" ]; then failure="timeout:no stable ${dwell}s window within ${timeout}s"; break; fi
    if ! process_alive "$pid"; then failure="process-died:PID $pid exited before planned termination"; break; fi
    if [ "$(file_bytes "$dir/runtime.log")" -gt "$max_log_bytes" ] || [ "$(file_bytes "$dir/stdout.log")" -gt "$max_log_bytes" ] || [ "$(file_bytes "$dir/stderr.log")" -gt "$max_log_bytes" ]; then
      failure="telemetry-failure:log exceeded $max_log_bytes bytes"; break
    fi
    poll=$(python3 "$checker" --poll --task "$task" --level "$level" --pid "$pid" --dwell "$dwell" \
      --log "$dir/runtime.log" --stdout-log "$dir/stdout.log")
    rc=$?
    printf '%s\t%s\n' "$elapsed" "$poll" >> "$dir/poll.tsv"
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 3 ]; then
      failure="telemetry-failure:$(printf '%s\n' "$poll" | awk -F '\t' 'NR == 1 { print $4 }')"; break
    fi
    window_ms=$(printf '%s\n' "$poll" | awk -F '\t' 'NR == 1 { print $2 + 0 }')
    count=$(printf '%s\n' "$poll" | awk -F '\t' 'NR == 1 { print $3 + 0 }')
    if [ "$shots" -lt 3 ] && [ "$count" -gt "$last_shot_count" ] && [ "$window_ms" -ge $((shots * dwell * 500)) ]; then
      shot="$dir/shot-$((shots + 1)).png"
      if ! xcrun simctl io "$simulator" screenshot "$shot" >/dev/null 2>&1 || ! sips -Z 1600 "$shot" >/dev/null 2>&1; then
        failure="screenshot-failure:could not capture $(basename "$shot")"; break
      fi
      shots=$((shots + 1)) last_shot_count=$count
      printf '%s\t%s\t%s\t%s\n' "$shots" "$elapsed" "$window_ms" "$count" >> "$dir/screenshots.tsv"
    fi
    if [ "$rc" -eq 0 ] && [ "$shots" -ge 3 ]; then break; fi
    sleep 2
  done

  if [ -n "$pid" ]; then
    if [ -z "$failure" ] && ! process_alive "$pid"; then
      failure="process-died:PID $pid exited before planned termination"
    fi
    terminate_app
    waited=0
    while process_alive "$pid" && [ "$waited" -lt 10 ]; do sleep 1; waited=$((waited + 1)); done
    if process_alive "$pid"; then failure=${failure:-"launch-error:PID $pid survived simctl terminate"}; fi
    current_pid=
  fi
  # A launch can succeed without a parseable PID; it must still be terminated before the next task.
  if [ "$current_launch" -eq 1 ]; then terminate_app; current_launch=0; fi
  stop_log_stream
  if [ -n "${saves:-}" ] && [ -f "$dir/before-saves.tsv" ]; then
    python3 "$checker" --snapshot-saves "$saves" --output "$dir/after-saves.tsv" || true
  fi

  set -- python3 "$checker" --final --task "$task" --level "$level" --dwell "$dwell" \
    --log "$dir/runtime.log" --stdout-log "$dir/stdout.log" \
    --save-before "$dir/before-saves.tsv" --save-after "$dir/after-saves.tsv" \
    --visual-report "$dir/visual-selection.tsv" --result "$dir/result.json" --runner-failure "$failure"
  [ -n "$pid" ] && set -- "$@" --pid "$pid"
  for n in 1 2 3; do [ -f "$dir/shot-$n.png" ] && set -- "$@" --screenshot "$dir/shot-$n.png"; done
  "$@"
}

# Redirected (not piped) so the loop runs in this shell and the signal trap sees the owned PIDs.
tab=$(printf '\t')
while IFS=$tab read -r task level; do
  saves=
  run_task "$task" "$level" </dev/null || true
done < "$artifacts/tasks.tsv"

python3 "$checker" --summarize "$artifacts"
status=$?
printf '%s\n' "summary: $artifacts/summary.tsv"
exit "$status"
