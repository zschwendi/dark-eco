#!/bin/sh

set -eu

usage() {
  echo "usage: GOALPAD_JAK2_DATA_DIR=<prepared-jak2-dir> $0 check|play" >&2
  echo "       optional: GOALPAD_JAK2_HOST_BUILD, GOALPAD_JAK2_SAVES_DIR, GOALPAD_BUILD_JOBS" >&2
  exit 2
}

fail() {
  echo "Jak II Stage 9 Mac check failed: $*" >&2
  exit 1
}

mode=${1:-}
[ "$mode" = check ] || [ "$mode" = play ] || usage

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/.." && pwd)
build_root=${GOALPAD_JAK2_HOST_BUILD:-/private/tmp/GOALPad-jak2-real-dma-host}
data_root=${GOALPAD_JAK2_DATA_DIR:-}
jobs=${GOALPAD_BUILD_JOBS:-2}
runtime="$build_root/game/jak2-metal-runtime-proof"

[ -n "$data_root" ] || fail "GOALPAD_JAK2_DATA_DIR is not set"
[ -f "$data_root/iso/KERNEL.CGO" ] || fail "missing $data_root/iso/KERNEL.CGO"
[ -f "$data_root/iso/GAME.CGO" ] || fail "missing $data_root/iso/GAME.CGO"
[ -f "$data_root/fr3/GAME.fr3" ] || fail "missing $data_root/fr3/GAME.fr3"
[ -f "$build_root/build.ninja" ] || fail "$build_root is not the configured canonical Ninja build"
configured_source=$(sed -n 's/^CMAKE_HOME_DIRECTORY:INTERNAL=//p' "$build_root/CMakeCache.txt")
[ -n "$configured_source" ] || fail "$build_root does not record its configured source tree"
configured_source=$(CDPATH= cd -- "$configured_source" && pwd)
expected_source=$(CDPATH= cd -- "$repository_root/OpenGOAL" && pwd)
[ "$configured_source" = "$expected_source" ] || \
  fail "$build_root belongs to $configured_source, not $expected_source"

stamp=$(date +%Y%m%d-%H%M%S)
saves_root=${GOALPAD_JAK2_SAVES_DIR:-/private/tmp/goalpad-jak2-stage9-$mode-$stamp-$$}

if [ "$mode" = play ]; then
  [ -x "$runtime" ] || fail "build the jak2-metal-runtime-proof target first"
  echo "Jak II controls: Return/Start, Space/South = X, arrows/D-pad, WASD and IJKL sticks."
  echo "Escape or closing the window ends the session. Saves/settings: $saves_root"
  exec "$runtime" \
    --data-dir "$data_root" \
    --saves-dir "$saves_root" \
    --interactive --report-pad --audio
fi

cmake --build "$build_root" --target \
  jak2-pad-seam-test \
  jak2-sound-rpc-test \
  jak2-metal-host-bridge-test \
  jak2-metal-runtime-proof \
  -j"$jobs"

"$build_root/game/jak2-pad-seam-test"
"$build_root/game/jak2-sound-rpc-test"
"$build_root/game/jak2-metal-host-bridge-test"

log_path=${GOALPAD_JAK2_STAGE9_LOG:-/private/tmp/goalpad-jak2-stage9-check-$stamp-$$.log}
status=0
"$runtime" \
  --data-dir "$data_root" \
  --saves-dir "$saves_root" \
  --ticks 40 --hidden --probe-pad >"$log_path" 2>&1 || status=$?

[ "$status" -eq 0 ] || fail "runtime exited $status; see $log_path"
grep -Fq "metal: chains=40 complete=40 failed=0" "$log_path" || \
  fail "the final 40/40 Metal gate is absent; see $log_path"
grep -Fq "frame: 640x480 bytes=1228800" "$log_path" || \
  fail "the final frame summary is absent; see $log_path"
grep -Fq "pad-probe: pushes=40" "$log_path" || \
  fail "the live runtime pad probe is absent; see $log_path"
grep -Fq "transitioned=1" "$log_path" || \
  fail "the live runtime did not read the pushed pad transition; see $log_path"
grep -Fq "PASS: bounded Jak II" "$log_path" || \
  fail "the bounded runtime did not produce its changing non-black title frame; see $log_path"

echo "Jak II Stage 9 focused Mac check passed."
echo "Log: $log_path"
shasum -a 256 "$log_path"
