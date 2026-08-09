#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-level-art-residency.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM

clang++ -std=c++17 -Wall -Wextra -Werror -I"$root" \
  "$root/Scripts/level-art-residency-check.cpp" \
  -o "$build_dir/level-art-residency-check"

"$build_dir/level-art-residency-check"
