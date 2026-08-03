#!/bin/sh
# Emit the C for Jak II's 840 object files for the iPhoneOS AOT link proof.

set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
build=${1:-/private/tmp/GOALPad-jak2-aot-host}
out="$root/Generated/jak2-aot"
jobs=${GOALPAD_BUILD_JOBS:-2}

case "$jobs" in
  ''|*[!0-9]*)
    echo "GOALPAD_BUILD_JOBS must be a positive integer" >&2
    exit 1
    ;;
esac
[ "$jobs" -gt 0 ] || {
  echo "GOALPAD_BUILD_JOBS must be a positive integer" >&2
  exit 1
}

if [ ! -f "$root/OpenGOAL/goalc/aot/c_backend_sweep_main.cpp" ]; then
  echo "OpenGOAL/ is empty. Run: git submodule update --init --recursive" >&2
  exit 1
fi

cmake -S "$root/OpenGOAL" -B "$build" --preset=Release-macos-arm64-clang \
  -DOPENSSL_ROOT_DIR=/opt/homebrew/opt/openssl@3
cmake --build "$build" --target goalc-cbackend-sweep -j "$jobs"

mkdir -p "$out"
find "$out" -maxdepth 1 -type f \( -name '*.c' -o -name '*.h' -o -name 'coverage.tsv' \) \
  -delete
"$build/goalc/goalc-cbackend-sweep" \
  --game jak2 \
  --project-path "$root/OpenGOAL" \
  --c-output-dir "$out" \
  --report "$out/coverage.tsv"

"$root/Scripts/verify-generated-aot.sh" "$out" 840
