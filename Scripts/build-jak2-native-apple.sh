#!/bin/sh
# Build the isolated Jak II iOS runtime archives consumed by the Eco Jak II Dev target.

set -eu

fail() {
  echo "Jak II native build failed: $*" >&2
  exit 1
}

: "${SRCROOT:?}"
: "${DERIVED_FILE_DIR:?}"
: "${PLATFORM_NAME:?}"
: "${CONFIGURATION:?}"
: "${IPHONEOS_DEPLOYMENT_TARGET:?}"

case "$PLATFORM_NAME" in
  iphoneos|iphonesimulator) ;;
  *) fail "unsupported platform $PLATFORM_NAME" ;;
esac

source_root="$SRCROOT/OpenGOAL"
aot_root="$SRCROOT/Generated/jak2-aot"
build_root="${GOALPAD_JAK2_NATIVE_BUILD_ROOT:-$DERIVED_FILE_DIR/Jak2Native/$PLATFORM_NAME}"
configuration_directory="$build_root/$CONFIGURATION-$PLATFORM_NAME"
zstd_configuration_directory="$build_root/third-party/zstd/$CONFIGURATION-$PLATFORM_NAME"
jobs=${GOALPAD_BUILD_JOBS:-2}

case "$jobs" in
  ''|*[!0-9]*) fail "GOALPAD_BUILD_JOBS must be a positive integer" ;;
esac
[ "$jobs" -gt 0 ] || fail "GOALPAD_BUILD_JOBS must be a positive integer"

[ -f "$source_root/CMakeLists.txt" ] || \
  fail "OpenGOAL is unavailable; run git submodule update --init --recursive"
[ -f "$aot_root/aot_boot_manifest.c" ] || \
  fail "missing generated Jak II AOT corpus at $aot_root"

cmake -S "$source_root" -B "$build_root" -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT="$PLATFORM_NAME" \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$IPHONEOS_DEPLOYMENT_TARGET" \
  -DBUILD_TESTING=OFF \
  -DOPENGOAL_BUILD_JAK2_IPHONEOS_AOT_LINK_ONLY=ON \
  -DOPENGOAL_JAK2_AOT_DIR="$aot_root" \
  -DOPENGOAL_JAK2_IPHONEOS_DEVELOPMENT_TEAM=

cmake --build "$build_root" \
  --config "$CONFIGURATION" \
  --target jak2-iphoneos-runtime jak2-iphoneos-metal-host \
  --parallel "$jobs"

for archive in \
  "$configuration_directory/libopengoal-jak2-runtime.a" \
  "$configuration_directory/libjak2-iphoneos-metal-host.a" \
  "$configuration_directory/libopengoal-jak2-aot-corpus.a" \
  "$configuration_directory/libjak2-iphoneos-metal-product.a" \
  "$configuration_directory/libjak2-kernel-core.a" \
  "$zstd_configuration_directory/liblibzstd_static.a"
do
  [ -f "$archive" ] || fail "expected archive was not produced: $archive"
done
