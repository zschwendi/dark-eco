#!/bin/sh
# Generate the checked Jak II public source-object pack once, then verify it on every run.

set -eu

fail() {
  echo "Jak II source-object pack preparation failed: $*" >&2
  exit 1
}

temporary_staging_root=
temporary_aggregate_record=
publish_lock=
cleanup() {
  if [ -n "$publish_lock" ]; then
    rmdir -- "$publish_lock" 2>/dev/null || true
  fi
  if [ -n "$temporary_staging_root" ]; then
    rm -rf -- "$temporary_staging_root"
  fi
  if [ -n "$temporary_aggregate_record" ]; then
    rm -f -- "$temporary_aggregate_record"
  fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repository_root=$(CDPATH= cd -- "$script_directory/.." && pwd -P)
opengoal_root=${GOALPAD_OPENGOAL_ROOT:-$repository_root/OpenGOAL}
source_pack=${GOALPAD_JAK2_SOURCE_OBJECT_PACK_ROOT:-$repository_root/build/jak2-source-object-pack}
build_root=${GOALPAD_JAK2_SOURCE_OBJECT_PACK_BUILD_ROOT:-$opengoal_root/build/Release/bin}
aggregate_record=${GOALPAD_JAK2_SOURCE_OBJECT_PACK_EXPECTED_AGGREGATE_FILE:-$repository_root/build/jak2-source-object-pack.expected-aggregate}
jobs=${GOALPAD_BUILD_JOBS:-2}

case "$jobs" in
  ''|*[!0-9]*) fail "GOALPAD_BUILD_JOBS must be a positive integer" ;;
esac
[ "$jobs" -gt 0 ] || fail "GOALPAD_BUILD_JOBS must be a positive integer"

for path_and_label in "$opengoal_root|OpenGOAL root" "$source_pack|source-object pack" \
                      "$build_root|host build root" "$aggregate_record|expected aggregate record"; do
  path=${path_and_label%%|*}
  label=${path_and_label#*|}
  case "$path" in
    /*) ;;
    *) fail "$label must be an absolute path" ;;
  esac
  [ "$path" != / ] || fail "$label may not be the filesystem root"
done

case "$aggregate_record" in
  "$source_pack"/*) fail "expected aggregate record must not be inside the source-object pack" ;;
esac

[ -f "$opengoal_root/CMakeLists.txt" ] && [ ! -L "$opengoal_root/CMakeLists.txt" ] || \
  fail "OpenGOAL is missing; run git submodule update --init --recursive"
[ ! -L "$source_pack" ] || fail "source-object pack may not be a symbolic link"
if [ -e "$source_pack" ]; then
  [ -d "$source_pack" ] || fail "source-object pack must be a directory"
else
  source_pack_parent=${source_pack%/*}
  if [ "$source_pack" = "$repository_root/build/jak2-source-object-pack" ]; then
    mkdir -p "$source_pack_parent"
  else
    [ -d "$source_pack_parent" ] && [ ! -L "$source_pack_parent" ] || \
      fail "custom source-object pack parent must be an existing direct directory"
  fi
fi

[ ! -L "$aggregate_record" ] || fail "expected aggregate record may not be a symbolic link"
if [ -e "$aggregate_record" ]; then
  [ -f "$aggregate_record" ] || fail "expected aggregate record must be a regular file"
else
  aggregate_record_parent=${aggregate_record%/*}
  if [ "$aggregate_record" = "$repository_root/build/jak2-source-object-pack.expected-aggregate" ]; then
    mkdir -p "$aggregate_record_parent"
  else
    [ -d "$aggregate_record_parent" ] && [ ! -L "$aggregate_record_parent" ] || \
      fail "custom expected aggregate record parent must be an existing direct directory"
  fi
fi

validate_aggregate() {
  aggregate=$1
  [ "${#aggregate}" -eq 16 ] && \
    [ -z "$(printf '%s' "$aggregate" | tr -d '0123456789abcdefABCDEF')" ] || \
    fail "expected aggregate is not one nonzero 16-digit hexadecimal value: $2"
  case "$aggregate" in
    0000000000000000) fail "expected aggregate must not be zero: $2" ;;
  esac
  printf '%s\n' "$aggregate"
}

read_manifest_aggregate() {
  aggregate=$(awk -F '\t' '$1 == "AGGREGATE_XXH64" { print $2 }' "$1") || \
    fail "could not read the expected aggregate from $1"
  validate_aggregate "$aggregate" "$1"
}

read_expected_aggregate_record() {
  aggregate=$(awk 'NR == 1 { value = $0; next } { invalid = 1 } END { if (NR != 1 || invalid) exit 1; print value }' "$1") || \
    fail "could not read the expected aggregate record: $1"
  validate_aggregate "$aggregate" "$1"
}

expected_aggregate=
if [ -e "$aggregate_record" ]; then
  expected_aggregate=$(read_expected_aggregate_record "$aggregate_record")
fi

cmake=${GOALPAD_CMAKE_EXECUTABLE:-cmake}
case "$cmake" in
  */*) ;;
  *) cmake=$(command -v "$cmake" 2>/dev/null || true) ;;
esac
[ -n "$cmake" ] && [ -x "$cmake" ] || fail "CMake is unavailable"

"$cmake" -S "$opengoal_root" -B "$build_root" --preset=Release-macos-arm64-clang \
  "-DOPENSSL_ROOT_DIR=${OPENSSL_ROOT_DIR:-/opt/homebrew/opt/openssl@3}"
"$cmake" --build "$build_root" \
  --target goalc-cbackend-sweep jak2-source-object-pack-verify --parallel "$jobs"

sweep=$build_root/goalc/goalc-cbackend-sweep
verifier=$build_root/goalc/jak2-source-object-pack-verify
[ -x "$sweep" ] || fail "host source-pack writer was not built: $sweep"
[ -x "$verifier" ] || fail "host source-pack verifier was not built: $verifier"

verify_source_pack() {
  "$verifier" "$1" --expected-aggregate "$expected_aggregate"
}

write_aggregate_record() {
  [ -e "$aggregate_record" ] && return 0
  temporary_aggregate_record=$(mktemp "$aggregate_record_parent/.goalpad-jak2-source-pack-aggregate.XXXXXX") || \
    fail "could not stage the expected aggregate record"
  printf '%s\n' "$expected_aggregate" >"$temporary_aggregate_record"
  mv -- "$temporary_aggregate_record" "$aggregate_record"
  temporary_aggregate_record=
}

if [ ! -e "$source_pack" ]; then
  temporary_staging_root=$(mktemp -d "$source_pack_parent/.goalpad-jak2-source-pack.XXXXXX") || \
    fail "could not create source-object pack staging directory"
  staged_source_pack=$temporary_staging_root/pack
  "$sweep" \
    --game jak2 \
    --project-file goal_src/jak2/game.gp \
    --target GROUP:all-code \
    --project-path "$opengoal_root" \
    --object-output-dir "$staged_source_pack" \
    --report "$build_root/goalc/jak2-source-object-pack-report.tsv"
  discovered_aggregate=$(read_manifest_aggregate "$staged_source_pack/object_pack_manifest.tsv")
  if [ -n "$expected_aggregate" ] && [ "$expected_aggregate" != "$discovered_aggregate" ]; then
    fail "generated pack aggregate does not match the recorded expected aggregate"
  fi
  expected_aggregate=$discovered_aggregate
  verify_source_pack "$staged_source_pack"
  candidate_publish_lock=$source_pack_parent/.goalpad-jak2-source-pack.publish-lock
  if mkdir "$candidate_publish_lock" 2>/dev/null; then
    publish_lock=$candidate_publish_lock
  else
    fail "another source-object pack publication is in progress"
  fi
  [ ! -e "$source_pack" ] && [ ! -L "$source_pack" ] || \
    fail "source-object pack appeared while it was being prepared"
  mv -- "$staged_source_pack" "$source_pack"
  rmdir -- "$publish_lock"
  publish_lock=
  write_aggregate_record
else
  if [ -z "$expected_aggregate" ]; then
    expected_aggregate=$(read_manifest_aggregate "$source_pack/object_pack_manifest.tsv")
  fi
  verify_source_pack "$source_pack"
  write_aggregate_record
  echo "Reusing existing Jak II source-object pack: $source_pack"
fi
