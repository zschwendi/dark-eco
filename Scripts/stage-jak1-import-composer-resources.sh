#!/bin/sh
# Stage one importer's resources after its flattened archive pre-link build has completed.

set -eu

game=${GOALPAD_IMPORT_COMPOSER_GAME:-jak1}
case "$game" in
  jak1)
    display_name="Jak 1"
    script_name=stage-jak1-import-composer-resources.sh
    source_pack_env_name=GOALPAD_JAK1_SOURCE_OBJECT_PACK_ROOT
    import_build_root_env_name=GOALPAD_JAK1_IMPORT_BUILD_ROOT
    source_pack_env_value=${GOALPAD_JAK1_SOURCE_OBJECT_PACK_ROOT:-}
    import_build_root_env_value=${GOALPAD_JAK1_IMPORT_BUILD_ROOT:-}
    verifier_name=jak1-source-object-pack-verify
    composer_directory=jak1-import-composer-apple
    composer_archive=libjak1-import-composer-apple.a
    resource_stager_name=stage-jak1-import-resources.sh
    ;;
  jak2)
    display_name="Jak II"
    script_name=stage-jak2-import-composer-resources.sh
    source_pack_env_name=GOALPAD_JAK2_SOURCE_OBJECT_PACK_ROOT
    import_build_root_env_name=GOALPAD_JAK2_IMPORT_BUILD_ROOT
    source_pack_env_value=${GOALPAD_JAK2_SOURCE_OBJECT_PACK_ROOT:-}
    import_build_root_env_value=${GOALPAD_JAK2_IMPORT_BUILD_ROOT:-}
    verifier_name=jak2-source-object-pack-verify
    composer_directory=jak2-import-composer-apple
    composer_archive=libjak2-import-composer-apple.a
    resource_stager_name=stage-jak2-import-resources.sh
    ;;
  *)
    echo "Apple importer resource phase failed: select a supported game through its wrapper." >&2
    exit 2
    ;;
esac

usage() {
  cat >&2 <<EOF
Usage:
  $script_name \
    --opengoal-root DIRECTORY \
    --source-pack DIRECTORY \
    --derived-root DIRECTORY \
    --platform macosx|iphoneos|iphonesimulator|xros|xrsimulator \
    --resources-destination DIRECTORY

The corresponding environment variables are GOALPAD_OPENGOAL_ROOT,
$source_pack_env_name, $import_build_root_env_name,
PLATFORM_NAME, and GOALPAD_APP_RESOURCE_DESTINATION. When the resource
destination is omitted, the underlying stager may derive it from Xcode's
TARGET_BUILD_DIR and UNLOCALIZED_RESOURCES_FOLDER_PATH settings.
EOF
}

fail() {
  echo "$display_name Apple importer resource phase failed: $*" >&2
  exit 1
}

require_value() {
  option=$1
  value=$2
  [ -n "$value" ] || fail "missing $option"
}

opengoal_root=${GOALPAD_OPENGOAL_ROOT:-}
source_pack=$source_pack_env_value
derived_root=$import_build_root_env_value
platform=${PLATFORM_NAME:-}
resources_destination=${GOALPAD_APP_RESOURCE_DESTINATION:-}

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
    --resources-destination)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      resources_destination=$2
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
require_value "--source-pack / $source_pack_env_name" "$source_pack"
require_value "--derived-root / $import_build_root_env_name" "$derived_root"
require_value "--platform / PLATFORM_NAME" "$platform"

case "$platform" in
  macosx)
    verifier_relative=macosx/$verifier_name
    ;;
  iphoneos|iphonesimulator|xros|xrsimulator)
    verifier_relative=macosx-host/$verifier_name
    ;;
  *) fail "unsupported Apple platform: $platform" ;;
esac

case "$derived_root" in
  /*) ;;
  *) fail "derived build root must be an absolute path" ;;
esac
[ "$derived_root" != / ] || fail "derived build root may not be the filesystem root"
[ -d "$derived_root" ] || fail "the pre-link derived build root is missing: $derived_root"
derived_root=$(CDPATH= cd -- "$derived_root" && pwd -P) || \
  fail "could not resolve the pre-link derived build root: $derived_root"

archive=$derived_root/$platform/$composer_directory/$composer_archive
verifier=$derived_root/$verifier_relative
[ ! -L "$archive" ] && [ -f "$archive" ] && [ -s "$archive" ] || \
  fail "the pre-link flattened archive is missing: $archive"
[ ! -L "$verifier" ] && [ -f "$verifier" ] && [ -x "$verifier" ] || \
  fail "the host source object-pack verifier is missing: $verifier"

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
stager=$script_directory/$resource_stager_name
[ -x "$stager" ] || fail "the importer resource stager is missing: $stager"

set -- "$stager" \
  --opengoal-root "$opengoal_root" \
  --source-pack "$source_pack" \
  --source-pack-verifier "$verifier"
if [ -n "$resources_destination" ]; then
  set -- "$@" --resources-destination "$resources_destination"
fi
exec "$@"
