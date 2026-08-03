#!/bin/sh
# Generate the checked Jak 1 public source-object pack once, then verify it on every run.

set -eu

fail() {
  echo "Jak 1 source-object pack preparation failed: $*" >&2
  exit 1
}

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repository_root=$(CDPATH= cd -- "$script_directory/.." && pwd -P)
opengoal_root=${GOALPAD_OPENGOAL_ROOT:-$repository_root/OpenGOAL}
source_pack=${GOALPAD_JAK1_SOURCE_OBJECT_PACK_ROOT:-$repository_root/build/jak1-source-object-pack}
build_root=${GOALPAD_JAK1_SOURCE_OBJECT_PACK_BUILD_ROOT:-$opengoal_root/build/Release/bin}
jobs=${GOALPAD_BUILD_JOBS:-2}

case "$jobs" in
  ''|*[!0-9]*) fail "GOALPAD_BUILD_JOBS must be a positive integer" ;;
esac
[ "$jobs" -gt 0 ] || fail "GOALPAD_BUILD_JOBS must be a positive integer"

for path_and_label in "$opengoal_root|OpenGOAL root" "$source_pack|source-object pack" \
                      "$build_root|host build root"; do
  path=${path_and_label%%|*}
  label=${path_and_label#*|}
  case "$path" in
    /*) ;;
    *) fail "$label must be an absolute path" ;;
  esac
  [ "$path" != / ] || fail "$label may not be the filesystem root"
done

[ -f "$opengoal_root/CMakeLists.txt" ] && [ ! -L "$opengoal_root/CMakeLists.txt" ] || \
  fail "OpenGOAL is missing; run git submodule update --init --recursive"
[ ! -L "$source_pack" ] || fail "source-object pack may not be a symbolic link"
if [ -e "$source_pack" ]; then
  [ -d "$source_pack" ] || fail "source-object pack must be a directory"
else
  source_pack_parent=${source_pack%/*}
  if [ "$source_pack" = "$repository_root/build/jak1-source-object-pack" ]; then
    mkdir -p "$source_pack_parent"
  else
    [ -d "$source_pack_parent" ] && [ ! -L "$source_pack_parent" ] || \
      fail "custom source-object pack parent must be an existing direct directory"
  fi
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
  --target goalc-cbackend-sweep jak1-source-object-pack-verify --parallel "$jobs"

sweep=$build_root/goalc/goalc-cbackend-sweep
verifier=$build_root/goalc/jak1-source-object-pack-verify
[ -x "$sweep" ] || fail "host source-pack writer was not built: $sweep"
[ -x "$verifier" ] || fail "host source-pack verifier was not built: $verifier"

if [ ! -e "$source_pack" ]; then
  "$sweep" \
    --game jak1 \
    --project-file goal_src/jak1/game.gp \
    --target GROUP:all-code \
    --project-path "$opengoal_root" \
    --object-output-dir "$source_pack" \
    --report "$build_root/goalc/jak1-source-object-pack-report.tsv"
else
  echo "Reusing existing Jak 1 source-object pack: $source_pack"
fi

"$verifier" "$source_pack"
