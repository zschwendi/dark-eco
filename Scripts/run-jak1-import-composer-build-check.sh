#!/bin/sh
# Synthetic argument, platform, output-contract, and failure checks for the Xcode build plumbing.

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
game=${GOALPAD_IMPORT_COMPOSER_CHECK_GAME:-jak1}
case "$game" in
  jak1)
    display_name="Jak 1"
    builder=$script_directory/build-jak1-import-composer-apple.sh
    resource_phase=$script_directory/stage-jak1-import-composer-resources.sh
    verifier_target=jak1-source-object-pack-verify
    composer_target=jak1-import-composer-apple-archive
    composer_directory=jak1-import-composer-apple
    composer_archive=libjak1-import-composer-apple.a
    source_pack_env_name=GOALPAD_JAK1_SOURCE_OBJECT_PACK_ROOT
    build_root_env_name=GOALPAD_JAK1_IMPORT_BUILD_ROOT
    deployment_env_name=GOALPAD_JAK1_IMPORT_DEPLOYMENT_TARGET
    source_pack_only_option=OPENGOAL_BUILD_JAK1_SOURCE_OBJECT_PACK_ONLY
    composer_only_option=OPENGOAL_BUILD_JAK1_IMPORT_COMPOSER_ONLY
    contract_archive_name=GOALPAD_JAK1_IMPORT_ARCHIVE
    project_resource_name=OpenGOALProjectResources
    source_pack_resource_name=Jak1SourceObjectPack
    ;;
  jak2)
    display_name="Jak II"
    builder=$script_directory/build-jak2-import-composer-apple.sh
    resource_phase=$script_directory/stage-jak2-import-composer-resources.sh
    verifier_target=jak2-source-object-pack-verify
    composer_target=jak2-import-composer-apple-archive
    composer_directory=jak2-import-composer-apple
    composer_archive=libjak2-import-composer-apple.a
    source_pack_env_name=GOALPAD_JAK2_SOURCE_OBJECT_PACK_ROOT
    build_root_env_name=GOALPAD_JAK2_IMPORT_BUILD_ROOT
    deployment_env_name=GOALPAD_JAK2_IMPORT_DEPLOYMENT_TARGET
    source_pack_only_option=OPENGOAL_BUILD_JAK2_SOURCE_OBJECT_PACK_ONLY
    composer_only_option=OPENGOAL_BUILD_JAK2_IMPORT_COMPOSER_ONLY
    contract_archive_name=GOALPAD_JAK2_IMPORT_ARCHIVE
    project_resource_name=Jak2ProjectResources
    source_pack_resource_name=Jak2SourceObjectPack
    ;;
  *)
    echo "select an importer build check profile through its wrapper" >&2
    exit 2
    ;;
esac
temporary_base=${TMPDIR:-/tmp}
temporary_base=${temporary_base%/}
temporary_root=$(mktemp -d "$temporary_base/goalpad-$game-composer-build-check.XXXXXX")
temporary_root=$(CDPATH= cd -- "$temporary_root" && pwd -P)
trap 'rm -rf "$temporary_root"' EXIT HUP INT TERM

fail() {
  echo "$display_name composer build synthetic check failed: $*" >&2
  exit 1
}

expect_failure() {
  expected=$1
  shift
  if "$@" >"$temporary_root/failure.out" 2>"$temporary_root/failure.err"; then
    fail "command unexpectedly succeeded: $*"
  fi
  grep -F "$expected" "$temporary_root/failure.err" >/dev/null || {
    cat "$temporary_root/failure.err" >&2
    fail "failure did not contain: $expected"
  }
}

fixture_root="$temporary_root/fixture with spaces"
opengoal_root=$fixture_root/OpenGOAL
source_pack=$fixture_root/source-pack
resources=$fixture_root/resources
fake_cmake=$fixture_root/fake-cmake.sh
fake_builder=$fixture_root/fake-fr3-builder.py
cmake_log=$fixture_root/cmake.log

mkdir -p "$opengoal_root" "$source_pack" "$resources"
printf 'synthetic cmake project\n' >"$opengoal_root/CMakeLists.txt"
printf 'object\n' >"$source_pack/a.o"
printf 'recorded identity\n' >"$source_pack/object_pack_manifest.tsv"

cat >"$fake_cmake" <<'SH'
#!/bin/sh
set -eu
: "${FAKE_CMAKE_LOG:?}"
printf 'cmake' >>"$FAKE_CMAKE_LOG"
printf ' env-iphone=<%s> env-xros=<%s> env-sdk=<%s> env-platform=<%s> env-triple=<%s>' \
  "${IPHONEOS_DEPLOYMENT_TARGET-unset}" "${XROS_DEPLOYMENT_TARGET-unset}" \
  "${SDKROOT-unset}" "${PLATFORM_NAME-unset}" "${LLVM_TARGET_TRIPLE_OS_VERSION-unset}" \
  >>"$FAKE_CMAKE_LOG"
for argument in "$@"; do
  printf ' <%s>' "$argument" >>"$FAKE_CMAKE_LOG"
done
printf '\n' >>"$FAKE_CMAKE_LOG"

if [ "${1:-}" = --build ]; then
  build_root=$2
  target=
  shift 2
  while [ "$#" -gt 0 ]; do
    if [ "$1" = --target ]; then
      target=$2
      break
    fi
    shift
  done
  case "$target" in
    "$FAKE_VERIFIER_TARGET")
      mkdir -p "$build_root"
      cat >"$build_root/$FAKE_VERIFIER_TARGET" <<'VERIFY'
#!/bin/sh
set -eu
root=$1
[ -d "$root" ] && [ ! -L "$root" ] || exit 1
actual=$(find "$root" -mindepth 1 -maxdepth 1 -type f -print | sed 's#.*/##' | sort | tr '\n' ' ')
[ "$actual" = "a.o object_pack_manifest.tsv " ] || exit 1
[ "$(cat "$root/object_pack_manifest.tsv")" = "recorded identity" ] || exit 1
echo "Verified synthetic source pack."
VERIFY
      chmod +x "$build_root/$FAKE_VERIFIER_TARGET"
      ;;
    "$FAKE_COMPOSER_TARGET")
      mkdir -p "$build_root/$FAKE_COMPOSER_DIRECTORY"
      printf 'synthetic archive\n' \
        >"$build_root/$FAKE_COMPOSER_DIRECTORY/$FAKE_COMPOSER_ARCHIVE"
      ;;
    *) exit 1 ;;
  esac
  exit 0
fi

build_root=
while [ "$#" -gt 0 ]; do
  if [ "$1" = -B ]; then
    build_root=$2
    break
  fi
  shift
done
[ -n "$build_root" ] || exit 1
mkdir -p "$build_root"
SH
chmod +x "$fake_cmake"

cat >"$fake_builder" <<'PY'
#!/usr/bin/env python3
import pathlib
import sys

arguments = sys.argv[1:]
verify = arguments[-1] == "--verify-only"
path = pathlib.Path(arguments[-2] if verify else arguments[-1])
expected = {"manifest", "project.json"}
if verify:
    if not path.is_dir() or {item.name for item in path.iterdir()} != expected:
        raise SystemExit("invalid synthetic FR3 bundle")
else:
    if path.exists():
        raise SystemExit("synthetic builder refuses an existing output")
    path.mkdir()
    (path / "manifest").write_text("synthetic\n", encoding="utf-8")
    (path / "project.json").write_text("{}\n", encoding="utf-8")
PY

expect_failure "missing --opengoal-root" env \
  GOALPAD_CMAKE_EXECUTABLE="$fake_cmake" GOALPAD_CCACHE=off "$builder"

expect_failure "unsupported Apple platform: tvos" env \
  GOALPAD_CMAKE_EXECUTABLE="$fake_cmake" GOALPAD_CCACHE=off "$builder" \
  --opengoal-root "$opengoal_root" --source-pack "$source_pack" \
  --derived-root "$fixture_root/tvos" --platform tvos

expect_failure "derived build root must be an absolute path" env \
  FAKE_CMAKE_LOG="$cmake_log" GOALPAD_CMAKE_EXECUTABLE="$fake_cmake" \
  GOALPAD_CCACHE=off "$builder" --opengoal-root "$opengoal_root" \
  --source-pack "$source_pack" --derived-root relative --platform iphoneos

expect_failure "derived build root may not be inside the repository source tree" env \
  FAKE_CMAKE_LOG="$cmake_log" GOALPAD_CMAKE_EXECUTABLE="$fake_cmake" \
  GOALPAD_CCACHE=off "$builder" --opengoal-root "$opengoal_root" \
  --source-pack "$source_pack" --derived-root "$script_directory/forbidden-build" \
  --platform iphoneos
[ ! -e "$script_directory/forbidden-build" ] || \
  fail "repository-contained derived path was created before rejection"

run_build() {
  platform=$1
  derived_root=$fixture_root/build-$platform
  FAKE_CMAKE_LOG=$cmake_log FAKE_VERIFIER_TARGET=$verifier_target \
    FAKE_COMPOSER_TARGET=$composer_target FAKE_COMPOSER_DIRECTORY=$composer_directory \
    FAKE_COMPOSER_ARCHIVE=$composer_archive GOALPAD_CMAKE_EXECUTABLE=$fake_cmake \
    GOALPAD_CMAKE_GENERATOR=Ninja GOALPAD_CCACHE=off GOALPAD_BUILD_JOBS=1 \
    "$builder" --opengoal-root "$opengoal_root" --source-pack "$source_pack" \
    --derived-root "$derived_root" --platform "$platform" --deployment-target 17.0
  [ -s "$derived_root/$platform/$composer_directory/$composer_archive" ] || \
    fail "$platform archive was not produced"
  if [ "$platform" = macosx ]; then
    verifier=$derived_root/macosx/$verifier_target
  else
    verifier=$derived_root/macosx-host/$verifier_target
  fi
  [ -x "$verifier" ] || fail "$platform host verifier was not produced"
}

: >"$cmake_log"
run_build macosx
run_build iphoneos
run_build iphonesimulator
run_build xros
run_build xrsimulator
grep -F -- '<-DCMAKE_OSX_SYSROOT=macosx>' "$cmake_log" >/dev/null
grep -F -- '<-DCMAKE_OSX_SYSROOT=iphoneos>' "$cmake_log" >/dev/null
grep -F -- '<-DCMAKE_OSX_SYSROOT=iphonesimulator>' "$cmake_log" >/dev/null
grep -F -- '<-DCMAKE_OSX_SYSROOT=xros>' "$cmake_log" >/dev/null
grep -F -- '<-DCMAKE_OSX_SYSROOT=xrsimulator>' "$cmake_log" >/dev/null
grep -F -- '<-DCMAKE_SYSTEM_NAME=iOS>' "$cmake_log" >/dev/null
grep -F -- '<-DCMAKE_SYSTEM_NAME=visionOS>' "$cmake_log" >/dev/null
grep -F -- '<-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY>' "$cmake_log" >/dev/null
grep -F -- "<-D$source_pack_only_option=ON>" "$cmake_log" >/dev/null
grep -F -- "<-D$composer_only_option=ON>" "$cmake_log" >/dev/null
for platform in macosx iphoneos iphonesimulator xros xrsimulator; do
  awk -v build="/build-$platform/$platform>" '
    index($0, build) && index($0, "<-DCMAKE_OSX_DEPLOYMENT_TARGET=17.0>") { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$cmake_log" || fail "$platform target configure omitted its deployment target"
done
if awk '
  index($0, "/macosx-host>") && index($0, "<-DCMAKE_OSX_DEPLOYMENT_TARGET=") { found = 1 }
  END { exit found ? 0 : 1 }
' "$cmake_log"; then
  fail "macosx-host inherited a target-platform deployment setting"
fi

environment_build_root=$fixture_root/build-environment
env \
  "FAKE_CMAKE_LOG=$cmake_log" "FAKE_VERIFIER_TARGET=$verifier_target" \
  "FAKE_COMPOSER_TARGET=$composer_target" "FAKE_COMPOSER_DIRECTORY=$composer_directory" \
  "FAKE_COMPOSER_ARCHIVE=$composer_archive" "GOALPAD_CMAKE_EXECUTABLE=$fake_cmake" \
  GOALPAD_CMAKE_GENERATOR=Ninja GOALPAD_CCACHE=off GOALPAD_BUILD_JOBS=1 \
  "GOALPAD_OPENGOAL_ROOT=$opengoal_root" "$source_pack_env_name=$source_pack" \
  "$build_root_env_name=$environment_build_root" PLATFORM_NAME=iphoneos \
  "$deployment_env_name=17.0" "$builder"
[ -s "$environment_build_root/iphoneos/$composer_directory/$composer_archive" ] || \
  fail "build-setting arguments did not produce the archive"

: >"$cmake_log"
host_environment_build_root=$fixture_root/build-host-environment
FAKE_CMAKE_LOG=$cmake_log FAKE_VERIFIER_TARGET=$verifier_target \
  FAKE_COMPOSER_TARGET=$composer_target FAKE_COMPOSER_DIRECTORY=$composer_directory \
  FAKE_COMPOSER_ARCHIVE=$composer_archive GOALPAD_CMAKE_EXECUTABLE=$fake_cmake \
  GOALPAD_CMAKE_GENERATOR=Ninja GOALPAD_CCACHE=/usr/bin/true GOALPAD_BUILD_JOBS=1 \
  IPHONEOS_DEPLOYMENT_TARGET=99.1 XROS_DEPLOYMENT_TARGET=99.2 \
  SDKROOT=/synthetic/target-sdk PLATFORM_NAME=synthetic-target \
  LLVM_TARGET_TRIPLE_OS_VERSION=99.3 \
  "$builder" --opengoal-root "$opengoal_root" --source-pack "$source_pack" \
  --derived-root "$host_environment_build_root" --platform iphonesimulator \
  --deployment-target 17.0
awk '
  index($0, "/macosx-host>") &&
  index($0, "env-iphone=<unset>") &&
  index($0, "env-xros=<unset>") &&
  index($0, "env-sdk=<unset>") &&
  index($0, "env-platform=<unset>") &&
  index($0, "env-triple=<unset>") { found = 1 }
  END { exit found ? 0 : 1 }
' "$cmake_log" || fail "host verifier inherited target-platform build variables"
if awk '
  index($0, "/macosx-host>") && index($0, "CMAKE_CXX_COMPILER_LAUNCHER") { found = 1 }
  END { exit found ? 0 : 1 }
' "$cmake_log"; then
  fail "host verifier unexpectedly enabled ccache"
fi
grep -F "CMAKE_CXX_COMPILER_LAUNCHER=/usr/bin/true" "$cmake_log" >/dev/null || \
  fail "target composer did not retain ccache"

# Xcode may report /tmp-style paths whose existing parent is a platform symlink. The production
# script resolves that parent physically for containment while preserving the reported link path.
mkdir "$fixture_root/physical-derived-parent"
ln -s "$fixture_root/physical-derived-parent" "$fixture_root/reported-derived-parent"
reported_build_root=$fixture_root/reported-derived-parent/build
reported_output=$(FAKE_CMAKE_LOG=$cmake_log FAKE_VERIFIER_TARGET=$verifier_target \
  FAKE_COMPOSER_TARGET=$composer_target FAKE_COMPOSER_DIRECTORY=$composer_directory \
  FAKE_COMPOSER_ARCHIVE=$composer_archive GOALPAD_CMAKE_EXECUTABLE=$fake_cmake \
  GOALPAD_CMAKE_GENERATOR=Ninja GOALPAD_CCACHE=off GOALPAD_BUILD_JOBS=1 \
  "$builder" --opengoal-root "$opengoal_root" --source-pack "$source_pack" \
  --derived-root "$reported_build_root" --platform iphoneos --deployment-target 17.0)
printf '%s\n' "$reported_output" | \
  grep -F "$contract_archive_name=$reported_build_root/iphoneos/$composer_directory/$composer_archive" \
  >/dev/null || fail "reported derived path did not remain the linker output contract"
[ -s "$fixture_root/physical-derived-parent/build/iphoneos/$composer_directory/$composer_archive" ] || \
  fail "physically resolved derived parent did not receive the archive"

printf 'unexpected\n' >"$source_pack/stale.o"
expect_failure "$display_name Apple importer build failed" env \
  FAKE_CMAKE_LOG="$cmake_log" GOALPAD_CMAKE_EXECUTABLE="$fake_cmake" \
  FAKE_VERIFIER_TARGET="$verifier_target" FAKE_COMPOSER_TARGET="$composer_target" \
  FAKE_COMPOSER_DIRECTORY="$composer_directory" FAKE_COMPOSER_ARCHIVE="$composer_archive" \
  GOALPAD_CCACHE=off "$builder" --opengoal-root "$opengoal_root" \
  --source-pack "$source_pack" --derived-root "$fixture_root/mismatch" --platform iphoneos
rm "$source_pack/stale.o"

mkdir -p "$resources/$project_resource_name" "$resources/$source_pack_resource_name"
printf 'stale\n' >"$resources/$project_resource_name/stale"
printf 'stale\n' >"$resources/$source_pack_resource_name/stale"
GOALPAD_FR3_BUNDLE_BUILDER=$fake_builder "$resource_phase" \
  --opengoal-root "$opengoal_root" --source-pack "$source_pack" \
  --derived-root "$fixture_root/build-iphoneos" --platform iphoneos \
  --resources-destination "$resources"
[ ! -e "$resources/$project_resource_name/stale" ]
[ ! -e "$resources/$source_pack_resource_name/stale" ]

reported_resources=$fixture_root/reported-resources
mkdir "$reported_resources"
GOALPAD_FR3_BUNDLE_BUILDER=$fake_builder "$resource_phase" \
  --opengoal-root "$opengoal_root" --source-pack "$source_pack" \
  --derived-root "$reported_build_root" --platform iphoneos \
  --resources-destination "$reported_resources"
[ -d "$reported_resources/$project_resource_name" ]
[ -d "$reported_resources/$source_pack_resource_name" ]

physical_resources_parent=$fixture_root/physical-resources-parent
reported_resources_parent=$fixture_root/reported-resources-parent
mkdir -p "$physical_resources_parent/ResourceRoot"
ln -s "$physical_resources_parent" "$reported_resources_parent"
GOALPAD_FR3_BUNDLE_BUILDER=$fake_builder "$resource_phase" \
  --opengoal-root "$opengoal_root" --source-pack "$source_pack" \
  --derived-root "$fixture_root/build-iphoneos" --platform iphoneos \
  --resources-destination "$reported_resources_parent/ResourceRoot"
[ -d "$physical_resources_parent/ResourceRoot/$project_resource_name" ]
[ -d "$physical_resources_parent/ResourceRoot/$source_pack_resource_name" ]
ln -s "$physical_resources_parent/ResourceRoot" "$fixture_root/resources-leaf-link"
expect_failure "app resource destination may not be a symbolic link" env \
  GOALPAD_FR3_BUNDLE_BUILDER="$fake_builder" "$resource_phase" \
  --opengoal-root "$opengoal_root" --source-pack "$source_pack" \
  --derived-root "$fixture_root/build-iphoneos" --platform iphoneos \
  --resources-destination "$fixture_root/resources-leaf-link"

expect_failure "pre-link derived build root is missing" "$resource_phase" \
  --opengoal-root "$opengoal_root" --source-pack "$source_pack" \
  --derived-root "$fixture_root/not-built" --platform iphoneos \
  --resources-destination "$resources"
expect_failure "derived build root must be an absolute path" "$resource_phase" \
  --opengoal-root "$opengoal_root" --source-pack "$source_pack" \
  --derived-root relative --platform iphoneos --resources-destination "$resources"
expect_failure "unsupported Apple platform: watchos" "$resource_phase" \
  --opengoal-root "$opengoal_root" --source-pack "$source_pack" \
  --derived-root "$fixture_root/not-built" --platform watchos \
  --resources-destination "$resources"

vision_resources=$fixture_root/vision-resources
mkdir "$vision_resources"
GOALPAD_FR3_BUNDLE_BUILDER=$fake_builder "$resource_phase" \
  --opengoal-root "$opengoal_root" --source-pack "$source_pack" \
  --derived-root "$fixture_root/build-xrsimulator" --platform xrsimulator \
  --resources-destination "$vision_resources"
[ -d "$vision_resources/$project_resource_name" ]
[ -d "$vision_resources/$source_pack_resource_name" ]

echo "$display_name importer Xcode build plumbing synthetic check passed."
