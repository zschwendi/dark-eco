#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-presentation-geometry.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM

"${CXX:-c++}" -std=c++20 -Wall -Wextra -Wpedantic -Werror \
  -I"$root" "$root/Scripts/presentation-geometry-check.cpp" \
  -o "$build_dir/presentation-geometry-check"
"$build_dir/presentation-geometry-check"
