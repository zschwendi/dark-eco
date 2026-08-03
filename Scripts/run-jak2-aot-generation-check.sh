#!/bin/sh
# Synthetic command-contract check for the Jak II AOT generation wrapper.

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
generator=$script_directory/generate-jak2-aot.sh
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-jak2-aot-check.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT HUP INT TERM

fail() {
  echo "Jak II AOT generation check failed: $*" >&2
  exit 1
}

fixture_root=$temporary_root/project
build_root=$temporary_root/host-build
fake_bin=$temporary_root/bin
fake_cmake=$fake_bin/cmake
cmake_configure_args=$temporary_root/cmake-configure-args
cmake_build_args=$temporary_root/cmake-build-args
sweep_args=$temporary_root/sweep-args
verify_args=$temporary_root/verify-args

mkdir -p "$fixture_root/Scripts" "$fixture_root/OpenGOAL/goalc/aot" "$fake_bin"
fixture_root=$(CDPATH= cd -- "$fixture_root" && pwd -P)
cp "$generator" "$fixture_root/Scripts/generate-jak2-aot.sh"
touch "$fixture_root/OpenGOAL/goalc/aot/c_backend_sweep_main.cpp"

cat >"$fixture_root/Scripts/verify-generated-aot.sh" <<'SH'
#!/bin/sh
set -eu

: "${FAKE_VERIFY_ARGS:?}"
printf '%s\n' "$@" >"$FAKE_VERIFY_ARGS"
[ "$#" -eq 2 ]
[ "$2" = 840 ]
SH
chmod +x "$fixture_root/Scripts/verify-generated-aot.sh"

cat >"$fake_cmake" <<'SH'
#!/bin/sh
set -eu

: "${FAKE_CMAKE_CONFIGURE_ARGS:?}"
: "${FAKE_CMAKE_BUILD_ARGS:?}"
: "${FAKE_SWEEP_ARGS:?}"

if [ "${1:-}" = --build ]; then
  printf '%s\n' "$@" >"$FAKE_CMAKE_BUILD_ARGS"
  build_root=$2
  mkdir -p "$build_root/goalc"
  cat >"$build_root/goalc/goalc-cbackend-sweep" <<'SWEEP'
#!/bin/sh
set -eu

: "${FAKE_SWEEP_ARGS:?}"
printf '%s\n' "$@" >"$FAKE_SWEEP_ARGS"
SWEEP
  chmod +x "$build_root/goalc/goalc-cbackend-sweep"
  exit 0
fi

printf '%s\n' "$@" >"$FAKE_CMAKE_CONFIGURE_ARGS"
SH
chmod +x "$fake_cmake"

write_expected() {
  destination=$1
  shift
  printf '%s\n' "$@" >"$destination"
}

check_args() {
  actual=$1
  expected=$2
  label=$3
  if ! cmp -s "$actual" "$expected"; then
    echo "actual $label arguments:" >&2
    sed 's/^/  /' "$actual" >&2
    echo "expected $label arguments:" >&2
    sed 's/^/  /' "$expected" >&2
    fail "$label arguments changed"
  fi
}

expected_configure_args=$temporary_root/expected-configure-args
expected_sweep_args=$temporary_root/expected-sweep-args
expected_verify_args=$temporary_root/expected-verify-args
write_expected "$expected_configure_args" \
  -S "$fixture_root/OpenGOAL" -B "$build_root" --preset=Release-macos-arm64-clang \
  -DOPENSSL_ROOT_DIR=/opt/homebrew/opt/openssl@3
write_expected "$expected_sweep_args" \
  --game jak2 --project-path "$fixture_root/OpenGOAL" \
  --c-output-dir "$fixture_root/Generated/jak2-aot" \
  --report "$fixture_root/Generated/jak2-aot/coverage.tsv"
write_expected "$expected_verify_args" "$fixture_root/Generated/jak2-aot" 840

run_generator() {
  jobs=$1
  : >"$cmake_configure_args"
  : >"$cmake_build_args"
  : >"$sweep_args"
  : >"$verify_args"
  if [ "$jobs" = default ]; then
    unset GOALPAD_BUILD_JOBS
    PATH="$fake_bin:$PATH" FAKE_CMAKE_CONFIGURE_ARGS=$cmake_configure_args \
      FAKE_CMAKE_BUILD_ARGS=$cmake_build_args FAKE_SWEEP_ARGS=$sweep_args \
      FAKE_VERIFY_ARGS=$verify_args "$fixture_root/Scripts/generate-jak2-aot.sh" "$build_root"
  else
    PATH="$fake_bin:$PATH" GOALPAD_BUILD_JOBS=$jobs \
      FAKE_CMAKE_CONFIGURE_ARGS=$cmake_configure_args FAKE_CMAKE_BUILD_ARGS=$cmake_build_args \
      FAKE_SWEEP_ARGS=$sweep_args FAKE_VERIFY_ARGS=$verify_args \
      "$fixture_root/Scripts/generate-jak2-aot.sh" "$build_root"
  fi
}

assert_successful_contract() {
  jobs=$1
  expected_build_args=$temporary_root/expected-build-args
  write_expected "$expected_build_args" \
    --build "$build_root" --target goalc-cbackend-sweep -j "$jobs"
  check_args "$cmake_configure_args" "$expected_configure_args" "CMake configure"
  check_args "$cmake_build_args" "$expected_build_args" "CMake build"
  check_args "$sweep_args" "$expected_sweep_args" "sweep"
  check_args "$verify_args" "$expected_verify_args" "840-object verification"
}

output_directory=$fixture_root/Generated/jak2-aot
mkdir -p "$output_directory"
touch "$output_directory/stale.c" "$output_directory/stale_generated.h" \
  "$output_directory/coverage.tsv" "$output_directory/keep.txt"

run_generator default
assert_successful_contract 2
[ ! -e "$output_directory/stale.c" ] || fail "stale C output was not removed"
[ ! -e "$output_directory/stale_generated.h" ] || fail "stale header output was not removed"
[ ! -e "$output_directory/coverage.tsv" ] || fail "stale coverage output was not removed"
[ -f "$output_directory/keep.txt" ] || fail "unrelated output was removed"

run_generator 7
assert_successful_contract 7

for invalid_jobs in 0 -1 one 1.5; do
  : >"$cmake_configure_args"
  : >"$cmake_build_args"
  if output=$(PATH="$fake_bin:$PATH" GOALPAD_BUILD_JOBS=$invalid_jobs \
    FAKE_CMAKE_CONFIGURE_ARGS=$cmake_configure_args FAKE_CMAKE_BUILD_ARGS=$cmake_build_args \
    FAKE_SWEEP_ARGS=$sweep_args FAKE_VERIFY_ARGS=$verify_args \
    "$fixture_root/Scripts/generate-jak2-aot.sh" "$build_root" 2>&1); then
    fail "invalid GOALPAD_BUILD_JOBS=$invalid_jobs was accepted"
  fi
  case "$output" in
    *"GOALPAD_BUILD_JOBS must be a positive integer"*) ;;
    *) fail "invalid GOALPAD_BUILD_JOBS=$invalid_jobs returned the wrong error" ;;
  esac
  [ ! -s "$cmake_configure_args" ] || fail "invalid jobs reached CMake configure"
  [ ! -s "$cmake_build_args" ] || fail "invalid jobs reached CMake build"
done

echo "Jak II AOT generation command-contract check passed."
