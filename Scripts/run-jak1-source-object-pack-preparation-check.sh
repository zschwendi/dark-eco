#!/bin/sh
# Synthetic generation, reuse, and fail-closed checks for the source-pack preparation wrapper.

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
preparer=$script_directory/prepare-jak1-source-object-pack.sh
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-source-pack-check.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT HUP INT TERM

fail() {
  echo "Jak 1 source-object pack preparation check failed: $*" >&2
  exit 1
}

opengoal_root=$temporary_root/OpenGOAL
source_pack=$temporary_root/output/jak1-source-object-pack
build_root=$temporary_root/host-build
fake_cmake=$temporary_root/fake-cmake
sweep_log=$temporary_root/sweep.log
verify_log=$temporary_root/verify.log
mkdir -p "$opengoal_root" "$temporary_root/output"
printf 'synthetic project\n' >"$opengoal_root/CMakeLists.txt"

cat >"$fake_cmake" <<'SH'
#!/bin/sh
set -eu
if [ "${1:-}" != --build ]; then
  while [ "$#" -gt 0 ]; do
    if [ "$1" = -B ]; then
      mkdir -p "$2"
      exit 0
    fi
    shift
  done
  exit 1
fi
build_root=$2
mkdir -p "$build_root/goalc"
cat >"$build_root/goalc/goalc-cbackend-sweep" <<'SWEEP'
#!/bin/sh
set -eu
: "${FAKE_SWEEP_LOG:?}"
printf 'run\n' >>"$FAKE_SWEEP_LOG"
output=
while [ "$#" -gt 0 ]; do
  if [ "$1" = --object-output-dir ]; then
    output=$2
    break
  fi
  shift
done
[ -n "$output" ] && [ ! -e "$output" ] || exit 1
mkdir "$output"
printf 'object\n' >"$output/synthetic.o"
printf 'recorded identity\n' >"$output/object_pack_manifest.tsv"
SWEEP
cat >"$build_root/goalc/jak1-source-object-pack-verify" <<'VERIFY'
#!/bin/sh
set -eu
: "${FAKE_VERIFY_LOG:?}"
printf 'run\n' >>"$FAKE_VERIFY_LOG"
[ -f "$1/synthetic.o" ]
[ "$(cat "$1/object_pack_manifest.tsv")" = 'recorded identity' ]
printf 'Verified 518 source objects (aggregate f1770cae6287a359, 10729681 bytes).\n'
VERIFY
chmod +x "$build_root/goalc/goalc-cbackend-sweep" \
  "$build_root/goalc/jak1-source-object-pack-verify"
SH
chmod +x "$fake_cmake"

run_preparer() {
  FAKE_SWEEP_LOG=$sweep_log FAKE_VERIFY_LOG=$verify_log \
    GOALPAD_CMAKE_EXECUTABLE=$fake_cmake \
    GOALPAD_OPENGOAL_ROOT=$opengoal_root \
    GOALPAD_JAK1_SOURCE_OBJECT_PACK_ROOT=$source_pack \
    GOALPAD_JAK1_SOURCE_OBJECT_PACK_BUILD_ROOT=$build_root \
    GOALPAD_BUILD_JOBS=1 "$preparer"
}

run_preparer
[ "$(wc -l <"$sweep_log" | tr -d ' ')" = 1 ] || fail "missing pack was not generated once"
[ "$(wc -l <"$verify_log" | tr -d ' ')" = 1 ] || fail "generated pack was not verified"

run_preparer
[ "$(wc -l <"$sweep_log" | tr -d ' ')" = 1 ] || fail "existing pack was regenerated"
[ "$(wc -l <"$verify_log" | tr -d ' ')" = 2 ] || fail "existing pack was not reverified"

printf 'corrupt\n' >"$source_pack/object_pack_manifest.tsv"
if run_preparer >/dev/null 2>&1; then
  fail "corrupt existing pack was accepted"
fi
[ "$(wc -l <"$sweep_log" | tr -d ' ')" = 1 ] || fail "corrupt pack was overwritten"

echo "Jak 1 source-object pack preparation synthetic check passed."
