#!/bin/sh
# Build the flattened Apple Jak 1 importer archive and verify its existing source pack.

set -eu

usage() {
  cat >&2 <<'EOF'
Usage:
  build-jak1-import-composer-apple.sh \
    --opengoal-root DIRECTORY \
    --source-pack DIRECTORY \
    --derived-root DIRECTORY \
    --platform macosx|iphoneos|iphonesimulator|xros|xrsimulator \
    [--deployment-target VERSION]

Each option may instead be supplied through its corresponding build setting:
  GOALPAD_OPENGOAL_ROOT
  GOALPAD_JAK1_SOURCE_OBJECT_PACK_ROOT
  GOALPAD_JAK1_IMPORT_BUILD_ROOT
  PLATFORM_NAME
  GOALPAD_JAK1_IMPORT_DEPLOYMENT_TARGET

Optional tool settings:
  GOALPAD_CMAKE_EXECUTABLE
  GOALPAD_CMAKE_GENERATOR (Ninja or Unix Makefiles)
  GOALPAD_BUILD_JOBS
  GOALPAD_CCACHE (absolute executable, auto, or off)
  GOALPAD_CCACHE_DIR
  GOALPAD_CCACHE_MAXSIZE

The source pack is verified but never generated or modified.
EOF
}

fail() {
  echo "Jak 1 Apple importer build failed: $*" >&2
  exit 1
}

require_value() {
  option=$1
  value=$2
  [ -n "$value" ] || fail "missing $option"
}

ensure_safe_directory() {
  directory=$1
  label=$2

  case "$directory" in
    /*) ;;
    *) fail "$label must be an absolute path" ;;
  esac
  [ "$directory" != / ] || fail "$label may not be the filesystem root"
  case "$directory" in
    *'//'*) fail "$label contains an empty path component" ;;
  esac

  remainder=${directory#/}
  current=/
  while [ -n "$remainder" ]; do
    component=${remainder%%/*}
    case "$component" in
      ''|.|..) fail "$label contains an unsafe path component" ;;
    esac
    if [ "$current" = / ]; then
      current=/$component
    else
      current=$current/$component
    fi
    [ ! -L "$current" ] || fail "$label contains a symbolic link: $current"
    [ -d "$current" ] || fail "$label is missing a directory component: $current"
    case "$remainder" in
      */*) remainder=${remainder#*/} ;;
      *) remainder= ;;
    esac
  done
}

ensure_output_directory() {
  output_directory=$1
  output_label=$2
  case "$output_directory" in
    /*) ;;
    *) fail "$output_label must be an absolute path" ;;
  esac
  [ "$output_directory" != / ] || fail "$output_label may not be the filesystem root"
  case "$output_directory" in
    *'//'*) fail "$output_label contains an empty path component" ;;
  esac
  output_basename=${output_directory##*/}
  case "$output_basename" in
    ''|.|..) fail "$output_label has an unsafe final component" ;;
  esac
  output_parent=${output_directory%/*}
  output_parent=${output_parent:-/}
  [ -d "$output_parent" ] || \
    fail "$output_label parent is not an existing directory: $output_parent"
  output_physical_parent=$(CDPATH= cd -- "$output_parent" && pwd -P) || \
    fail "could not resolve $output_label parent: $output_parent"
  ensure_safe_directory "$output_physical_parent" "$output_label parent"
  output_directory=$output_physical_parent/$output_basename
  if [ "$output_label" = "derived build root" ]; then
    case "$output_directory/" in
      "$repository_root/"*) fail "$output_label may not be inside the repository source tree" ;;
      "$opengoal_root/"*) fail "$output_label may not be inside the OpenGOAL source tree" ;;
      "$source_pack/"*) fail "$output_label may not be inside the source object pack" ;;
    esac
  fi
  [ ! -L "$output_directory" ] || fail "$output_label may not be a symbolic link"
  if [ -e "$output_directory" ]; then
    [ -d "$output_directory" ] || fail "$output_label must be a directory"
  else
    mkdir "$output_directory" || fail "could not create $output_label"
  fi
  printf '%s\n' "$output_directory"
}

ensure_direct_regular_file() {
  file=$1
  label=$2
  [ ! -L "$file" ] || fail "$label may not be a symbolic link"
  [ -f "$file" ] && [ -s "$file" ] || fail "$label is missing or empty: $file"
}

resolve_executable() {
  requested=$1
  label=$2
  case "$requested" in
    */*) resolved=$requested ;;
    *) resolved=$(command -v "$requested" 2>/dev/null || true) ;;
  esac
  [ -n "$resolved" ] && [ -x "$resolved" ] || fail "$label is unavailable: $requested"
  case "$resolved" in
    /*) ;;
    *) fail "$label did not resolve to an absolute path: $resolved" ;;
  esac
  printf '%s\n' "$resolved"
}

append_common_cmake_options() {
  cmake_option_deployment_target=$1
  cmake_option_ccache=$2
  shift 2
  set -- "$@" \
    "-DCMAKE_BUILD_TYPE=Release" \
    "-DBUILD_TESTING=OFF" \
    "-DCMAKE_OSX_ARCHITECTURES=arm64"
  if [ -n "$cmake_option_deployment_target" ]; then
    set -- "$@" "-DCMAKE_OSX_DEPLOYMENT_TARGET=$cmake_option_deployment_target"
  fi
  if [ -n "$cmake_option_ccache" ]; then
    set -- "$@" \
      "-DCMAKE_C_COMPILER_LAUNCHER=$cmake_option_ccache" \
      "-DCMAKE_CXX_COMPILER_LAUNCHER=$cmake_option_ccache"
  fi
  "$@"
}

run_host_command() (
  unset ARCHS CURRENT_ARCH EFFECTIVE_PLATFORM_NAME PLATFORM_NAME SDKROOT
  unset DRIVERKIT_DEPLOYMENT_TARGET IPHONEOS_DEPLOYMENT_TARGET
  unset TVOS_DEPLOYMENT_TARGET WATCHOS_DEPLOYMENT_TARGET XROS_DEPLOYMENT_TARGET
  unset LLVM_TARGET_TRIPLE_OS_VERSION LLVM_TARGET_TRIPLE_SUFFIX LLVM_TARGET_TRIPLE_VENDOR
  "$@"
)

configure_host_verifier() (
  build_directory=$1
  # Apple clang selects a platform partly from deployment-target environment variables,
  # which are not represented in ccache's command hash. Keep this small host tool uncached
  # so a target-platform object can never be replayed into the executable that runs on macOS.
  run_host_command append_common_cmake_options \
    "" "" \
    "$cmake" -S "$opengoal_root" -B "$build_directory" -G "$generator" \
    "-DOPENGOAL_BUILD_JAK1_SOURCE_OBJECT_PACK_ONLY=ON" \
    "-DCMAKE_OSX_SYSROOT=macosx"
)

configure_composer() {
  build_directory=$1
  set -- "$cmake" -S "$opengoal_root" -B "$build_directory" -G "$generator" \
    "-DOPENGOAL_BUILD_JAK1_IMPORT_COMPOSER_ONLY=ON" \
    "-DCMAKE_OSX_SYSROOT=$platform"
  case "$platform" in
    iphoneos|iphonesimulator)
      set -- "$@" \
        "-DCMAKE_SYSTEM_NAME=iOS" \
        "-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY"
      ;;
    xros|xrsimulator)
      set -- "$@" \
        "-DCMAKE_SYSTEM_NAME=visionOS" \
        "-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY"
      ;;
  esac
  append_common_cmake_options "$deployment_target" "$ccache" "$@"
}

opengoal_root=${GOALPAD_OPENGOAL_ROOT:-}
source_pack=${GOALPAD_JAK1_SOURCE_OBJECT_PACK_ROOT:-}
derived_root=${GOALPAD_JAK1_IMPORT_BUILD_ROOT:-}
platform=${PLATFORM_NAME:-}
deployment_target=${GOALPAD_JAK1_IMPORT_DEPLOYMENT_TARGET:-}
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repository_root=$(CDPATH= cd -- "$script_directory/.." && pwd -P)

while [ "$#" -gt 0 ]; do
  case "$1" in
    --opengoal-root)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      opengoal_root=$2
      shift 2
      ;;
    --source-pack)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      source_pack=$2
      shift 2
      ;;
    --derived-root)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      derived_root=$2
      shift 2
      ;;
    --platform)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      platform=$2
      shift 2
      ;;
    --deployment-target)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      deployment_target=$2
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

require_value "--opengoal-root / GOALPAD_OPENGOAL_ROOT" "$opengoal_root"
require_value "--source-pack / GOALPAD_JAK1_SOURCE_OBJECT_PACK_ROOT" "$source_pack"
require_value "--derived-root / GOALPAD_JAK1_IMPORT_BUILD_ROOT" "$derived_root"
require_value "--platform / PLATFORM_NAME" "$platform"

case "$platform" in
  macosx|iphoneos|iphonesimulator|xros|xrsimulator) ;;
  *) fail "unsupported Apple platform: $platform" ;;
esac

if [ -n "$deployment_target" ]; then
  case "$deployment_target" in
    *[!0-9.]*|.*|*.) fail "deployment target must contain only dot-separated digits" ;;
  esac
fi

jobs=${GOALPAD_BUILD_JOBS:-2}
case "$jobs" in
  ''|*[!0-9]*) fail "GOALPAD_BUILD_JOBS must be a positive integer" ;;
esac
[ "$jobs" -gt 0 ] || fail "GOALPAD_BUILD_JOBS must be a positive integer"

ensure_safe_directory "$opengoal_root" "OpenGOAL root"
ensure_safe_directory "$source_pack" "source object pack"
[ -f "$opengoal_root/CMakeLists.txt" ] && [ ! -L "$opengoal_root/CMakeLists.txt" ] || \
  fail "OpenGOAL root has no direct CMakeLists.txt"

case "$derived_root/" in
  "$opengoal_root/"*) fail "derived root may not be inside the OpenGOAL source tree" ;;
  "$source_pack/"*) fail "derived root may not be inside the source object pack" ;;
esac
derived_root_contract=$derived_root
derived_root=$(ensure_output_directory "$derived_root" "derived build root")

cmake=$(resolve_executable "${GOALPAD_CMAKE_EXECUTABLE:-cmake}" "CMake")
generator=${GOALPAD_CMAKE_GENERATOR:-}
if [ -z "$generator" ]; then
  if command -v ninja >/dev/null 2>&1; then
    generator=Ninja
  else
    generator="Unix Makefiles"
  fi
fi
case "$generator" in
  Ninja|"Unix Makefiles") ;;
  *) fail "unsupported CMake generator: $generator" ;;
esac

ccache=
case "${GOALPAD_CCACHE:-auto}" in
  off) ;;
  auto)
    if command -v ccache >/dev/null 2>&1; then
      ccache=$(resolve_executable ccache ccache)
    fi
    ;;
  *) ccache=$(resolve_executable "$GOALPAD_CCACHE" ccache) ;;
esac
if [ -n "$ccache" ]; then
  ccache_directory=${GOALPAD_CCACHE_DIR:-$derived_root/ccache}
  ccache_directory=$(ensure_output_directory "$ccache_directory" "ccache directory")
  export CCACHE_DIR=$ccache_directory
  export CCACHE_MAXSIZE=${GOALPAD_CCACHE_MAXSIZE:-512M}
fi

platform_build_root=$derived_root/$platform
if [ "$platform" = macosx ]; then
  verifier_build_root=$platform_build_root
  configure_composer "$platform_build_root"
else
  verifier_build_root=$derived_root/macosx-host
  configure_host_verifier "$verifier_build_root"
fi

if [ "$platform" = macosx ]; then
  "$cmake" --build "$verifier_build_root" \
    --target jak1-source-object-pack-verify --parallel "$jobs"
else
  run_host_command "$cmake" --build "$verifier_build_root" \
    --target jak1-source-object-pack-verify --parallel "$jobs"
fi
verifier=$verifier_build_root/jak1-source-object-pack-verify
ensure_direct_regular_file "$verifier" "source object-pack verifier"
[ -x "$verifier" ] || fail "source object-pack verifier is not executable: $verifier"
if ! "$verifier" "$source_pack"; then
  fail "the existing source object pack did not match the recorded 518-object identity"
fi

if [ "$platform" != macosx ]; then
  configure_composer "$platform_build_root"
fi
"$cmake" --build "$platform_build_root" \
  --target jak1-import-composer-apple-archive --parallel "$jobs"

archive=$platform_build_root/jak1-import-composer-apple/libjak1-import-composer-apple.a
ensure_direct_regular_file "$archive" "flattened composer archive"

contract_archive=$derived_root_contract/$platform/jak1-import-composer-apple/libjak1-import-composer-apple.a
if [ "$platform" = macosx ]; then
  contract_verifier=$derived_root_contract/macosx/jak1-source-object-pack-verify
else
  contract_verifier=$derived_root_contract/macosx-host/jak1-source-object-pack-verify
fi
echo "GOALPAD_JAK1_IMPORT_ARCHIVE=$contract_archive"
echo "GOALPAD_JAK1_SOURCE_OBJECT_PACK_VERIFIER=$contract_verifier"
