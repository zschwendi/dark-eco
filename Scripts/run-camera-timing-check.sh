#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-camera-timing.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM

xcrun clang++ -std=c++20 -Wall -Wextra -Werror \
  -I "$repo_root/GOALPad/Native" \
  "$repo_root/Scripts/camera-timing-check.cpp" \
  -o "$build_dir/camera-timing-check"

"$build_dir/camera-timing-check"
