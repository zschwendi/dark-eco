#!/bin/sh
# Emit the C for Jak 1's 518 object files that the app target compiles.
#
# GOAL is compiled ahead of time, on this Mac, by goalc's C backend: goalc-cbackend-sweep reads the
# build order out of goal_src/jak1/game.gp and writes one .c per object file plus
# aot_boot_manifest.c. Xcode then compiles those for arm64-apple-ios like any other source, so the
# game's code arrives in the app's signed __TEXT and nothing is generated on the iPad.
#
# The output is not committed. Run this once after cloning, and again whenever the OpenGOAL
# submodule pin moves.
#
# Usage: Scripts/generate-jak1-aot.sh [host build directory]

set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
build=${1:-/private/tmp/GOALPad-aot-host}
out="$root/Generated/jak1-aot"

if [ ! -f "$root/OpenGOAL/goalc/aot/c_backend_sweep_main.cpp" ]; then
  echo "OpenGOAL/ is empty. Run: git submodule update --init --recursive" >&2
  exit 1
fi

# The sweep tool is a host tool: it runs here, not on the iPad, so it is built for macOS with the
# ordinary OpenGOAL preset rather than by Xcode.
cmake -S "$root/OpenGOAL" -B "$build" --preset=Release-macos-arm64-clang \
  -DOPENSSL_ROOT_DIR=/opt/homebrew/opt/openssl@3
cmake --build "$build" --target goalc-cbackend-sweep -j 4

mkdir -p "$out"
"$build/goalc/goalc-cbackend-sweep" \
  --project-path "$root/OpenGOAL" \
  --limit 518 \
  --c-output-dir "$out" \
  --report "$build/jak1-aot-coverage.tsv"

echo "Wrote $(ls "$out"/*.c | wc -l | tr -d ' ') C files to $out"
