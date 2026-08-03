#!/bin/sh
# Synthetic generation, reuse, expected-aggregate, and fail-closed checks for the Jak II wrapper.

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
preparer=$script_directory/prepare-jak2-source-object-pack.sh
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-jak2-source-pack-check.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT HUP INT TERM

fail() {
  echo "Jak II source-object pack preparation check failed: $*" >&2
  exit 1
}

opengoal_root=$temporary_root/OpenGOAL
source_pack=$temporary_root/output/jak2-source-object-pack
aggregate_record=$temporary_root/output/jak2-source-object-pack.expected-aggregate
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
printf 'FORMAT\tgoalc-source-object-pack-v1\nCOUNT\t840\nAGGREGATE_XXH64\t0123456789abcdef\n' >"$output/object_pack_manifest.tsv"
if [ "${FAKE_SWEEP_FAIL_AFTER_CREATE:-0}" = 1 ]; then
  exit 1
fi
SWEEP
cat >"$build_root/goalc/jak2-source-object-pack-verify" <<'VERIFY'
#!/bin/sh
set -eu
: "${FAKE_VERIFY_LOG:?}"
printf '%s\n' "$*" >>"$FAKE_VERIFY_LOG"
[ "${1:-}" != '' ] && [ "${2:-}" = --project-path ] && [ "${4:-}" = --expected-aggregate ] || exit 1
[ "${5:-}" = 0123456789abcdef ] || exit 1
[ -f "$1/synthetic.o" ]
[ "$(awk -F '\t' '$1 == "AGGREGATE_XXH64" { print $2 }' "$1/object_pack_manifest.tsv")" = 0123456789abcdef ]
printf 'Verified 840 Jak II source objects (aggregate 0123456789abcdef, 7 bytes).\n'
VERIFY
chmod +x "$build_root/goalc/goalc-cbackend-sweep" \
  "$build_root/goalc/jak2-source-object-pack-verify"
SH
chmod +x "$fake_cmake"

run_preparer() {
  FAKE_SWEEP_LOG=$sweep_log FAKE_VERIFY_LOG=$verify_log \
    FAKE_SWEEP_FAIL_AFTER_CREATE=${FAKE_SWEEP_FAIL_AFTER_CREATE:-0} \
    GOALPAD_CMAKE_EXECUTABLE=$fake_cmake \
    GOALPAD_OPENGOAL_ROOT=$opengoal_root \
    GOALPAD_JAK2_SOURCE_OBJECT_PACK_ROOT=$source_pack \
    GOALPAD_JAK2_SOURCE_OBJECT_PACK_BUILD_ROOT=$build_root \
    GOALPAD_JAK2_SOURCE_OBJECT_PACK_EXPECTED_AGGREGATE_FILE=$aggregate_record \
    GOALPAD_BUILD_JOBS=1 "$preparer"
}

FAKE_SWEEP_FAIL_AFTER_CREATE=1
if run_preparer >/dev/null 2>&1; then
  fail "failed initial generation was accepted"
fi
unset FAKE_SWEEP_FAIL_AFTER_CREATE
[ ! -e "$source_pack" ] || fail "failed initial generation published a partial pack"
[ ! -e "$aggregate_record" ] || fail "failed initial generation recorded an aggregate"
[ -z "$(find "$temporary_root/output" -mindepth 1 -maxdepth 1 \
  -name '.goalpad-jak2-source-pack.*' -print -quit)" ] || \
  fail "failed initial generation left a staging directory"

run_preparer
[ "$(wc -l <"$sweep_log" | tr -d ' ')" = 2 ] || fail "missing pack did not recover"
[ "$(wc -l <"$verify_log" | tr -d ' ')" = 1 ] || fail "generated pack was not verified"
[ "$(cat "$aggregate_record")" = 0123456789abcdef ] || \
  fail "generated pack did not record its expected aggregate"

run_preparer
[ "$(wc -l <"$sweep_log" | tr -d ' ')" = 2 ] || fail "existing pack was regenerated"
[ "$(wc -l <"$verify_log" | tr -d ' ')" = 2 ] || fail "existing pack was not reverified"

printf 'corrupt\n' >"$source_pack/object_pack_manifest.tsv"
if run_preparer >/dev/null 2>&1; then
  fail "corrupt existing pack was accepted"
fi
[ "$(wc -l <"$sweep_log" | tr -d ' ')" = 2 ] || fail "corrupt pack was overwritten"

echo "Jak II source-object pack preparation synthetic check passed."
