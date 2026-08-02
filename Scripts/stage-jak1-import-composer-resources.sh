#!/bin/sh
# Stage importer resources after the flattened archive's pre-link build has completed.

set -eu

usage() {
  cat >&2 <<'EOF'
Usage:
  stage-jak1-import-composer-resources.sh \
    --opengoal-root DIRECTORY \
    --source-pack DIRECTORY \
    --derived-root DIRECTORY \
    --platform macosx|iphoneos|iphonesimulator|xros|xrsimulator \
    --resources-destination DIRECTORY

The corresponding environment variables are GOALPAD_OPENGOAL_ROOT,
GOALPAD_JAK1_SOURCE_OBJECT_PACK_ROOT, GOALPAD_JAK1_IMPORT_BUILD_ROOT,
PLATFORM_NAME, and GOALPAD_APP_RESOURCE_DESTINATION. When the resource
destination is omitted, the underlying stager may derive it from Xcode's
TARGET_BUILD_DIR and UNLOCALIZED_RESOURCES_FOLDER_PATH settings.
EOF
}

fail() {
  echo "Jak 1 Apple importer resource phase failed: $*" >&2
  exit 1
}

require_value() {
  option=$1
  value=$2
  [ -n "$value" ] || fail "missing $option"
}

opengoal_root=${GOALPAD_OPENGOAL_ROOT:-}
source_pack=${GOALPAD_JAK1_SOURCE_OBJECT_PACK_ROOT:-}
derived_root=${GOALPAD_JAK1_IMPORT_BUILD_ROOT:-}
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
require_value "--source-pack / GOALPAD_JAK1_SOURCE_OBJECT_PACK_ROOT" "$source_pack"
require_value "--derived-root / GOALPAD_JAK1_IMPORT_BUILD_ROOT" "$derived_root"
require_value "--platform / PLATFORM_NAME" "$platform"

case "$platform" in
  macosx)
    verifier_relative=macosx/jak1-source-object-pack-verify
    ;;
  iphoneos|iphonesimulator|xros|xrsimulator)
    verifier_relative=macosx-host/jak1-source-object-pack-verify
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

archive=$derived_root/$platform/jak1-import-composer-apple/libjak1-import-composer-apple.a
verifier=$derived_root/$verifier_relative
[ ! -L "$archive" ] && [ -f "$archive" ] && [ -s "$archive" ] || \
  fail "the pre-link flattened archive is missing: $archive"
[ ! -L "$verifier" ] && [ -f "$verifier" ] && [ -x "$verifier" ] || \
  fail "the host source object-pack verifier is missing: $verifier"

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
stager=$script_directory/stage-jak1-import-resources.sh
[ -x "$stager" ] || fail "the importer resource stager is missing: $stager"

set -- "$stager" \
  --opengoal-root "$opengoal_root" \
  --source-pack "$source_pack" \
  --source-pack-verifier "$verifier"
if [ -n "$resources_destination" ]; then
  set -- "$@" --resources-destination "$resources_destination"
fi
exec "$@"
