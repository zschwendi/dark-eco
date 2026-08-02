#!/bin/sh
# Stage the public Jak 1 importer resources into an Xcode app resource directory.

set -eu

usage() {
  cat >&2 <<'EOF'
Usage:
  stage-jak1-import-resources.sh \
    --opengoal-root DIRECTORY \
    --source-pack DIRECTORY \
    --source-pack-verifier EXECUTABLE \
    --resources-destination DIRECTORY

Each option may instead be supplied through its corresponding build setting:
  GOALPAD_OPENGOAL_ROOT
  GOALPAD_JAK1_SOURCE_OBJECT_PACK_ROOT
  GOALPAD_JAK1_SOURCE_OBJECT_PACK_VERIFIER
  GOALPAD_APP_RESOURCE_DESTINATION

For an Xcode build phase, TARGET_BUILD_DIR and UNLOCALIZED_RESOURCES_FOLDER_PATH
may provide the destination when GOALPAD_APP_RESOURCE_DESTINATION is unset.
EOF
}

fail() {
  echo "Jak 1 importer resource staging failed: $*" >&2
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

ensure_safe_existing_resource() {
  resource=$1
  label=$2
  if [ -L "$resource" ]; then
    fail "$label may not be a symbolic link"
  fi
  if [ -e "$resource" ] && [ ! -d "$resource" ]; then
    fail "$label must be a directory when it already exists"
  fi
}

ensure_safe_executable() {
  executable=$1
  label=$2
  case "$executable" in
    /*) ;;
    *) fail "$label must be an absolute path" ;;
  esac
  executable_parent=${executable%/*}
  executable_parent=${executable_parent:-/}
  ensure_safe_directory "$executable_parent" "$label parent"
  [ ! -L "$executable" ] || fail "$label may not be a symbolic link"
  [ -f "$executable" ] && [ -x "$executable" ] || fail "$label is missing or not executable"
}

ensure_safe_regular_file() {
  file=$1
  label=$2
  case "$file" in
    /*) ;;
    *) fail "$label must be an absolute path" ;;
  esac
  file_parent=${file%/*}
  file_parent=${file_parent:-/}
  ensure_safe_directory "$file_parent" "$label parent"
  [ ! -L "$file" ] || fail "$label may not be a symbolic link"
  [ -f "$file" ] && [ -r "$file" ] || fail "$label is missing or not readable"
}

remove_exact_directory() {
  directory=$1
  prefix=$2
  /usr/bin/python3 - "$resources_destination" "$directory" "$prefix" <<'PY'
import os
import shutil
import stat
import sys

parent, path, prefix = sys.argv[1:]
if os.path.dirname(path) != parent or not os.path.basename(path).startswith(prefix):
    raise SystemExit("refusing to remove a directory outside the staging contract")
try:
    status = os.lstat(path)
except FileNotFoundError:
    raise SystemExit(0)
if not stat.S_ISDIR(status.st_mode):
    raise SystemExit("refusing to remove a non-directory staging path")
shutil.rmtree(path)
PY
}

atomic_publish() {
  source=$1
  destination=$2
  /usr/bin/python3 - "$source" "$destination" <<'PY'
import ctypes
import errno
import os
import stat
import sys

source, destination = sys.argv[1:]
for path, label in ((source, "staged resource"),):
    status = os.lstat(path)
    if not stat.S_ISDIR(status.st_mode):
        raise SystemExit(f"{label} is not a direct directory")

destination_exists = os.path.lexists(destination)
if destination_exists:
    status = os.lstat(destination)
    if not stat.S_ISDIR(status.st_mode):
        raise SystemExit("existing resource destination is not a direct directory")

try:
    renamex_np = ctypes.CDLL(None, use_errno=True).renamex_np
except AttributeError:
    raise SystemExit("renamex_np is unavailable; refusing a non-atomic replacement")

renamex_np.argtypes = (ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint)
renamex_np.restype = ctypes.c_int
RENAME_SWAP = 0x00000002
RENAME_EXCL = 0x00000004
RENAME_NOFOLLOW_ANY = 0x00000010
flags = (RENAME_SWAP if destination_exists else RENAME_EXCL) | RENAME_NOFOLLOW_ANY
if renamex_np(os.fsencode(source), os.fsencode(destination), flags) != 0:
    error = ctypes.get_errno()
    raise SystemExit(f"atomic resource publish failed: {os.strerror(error)}")
print("swap" if destination_exists else "install")
PY
}

rollback_published_resource() {
  action=$1
  stage=$2
  destination=$3
  resource_prefix=$4
  case "$action" in
    swap)
      atomic_publish "$stage" "$destination" >/dev/null || \
        fail "could not restore the previous $resource_prefix after publication failure"
      remove_exact_directory "$stage" ".${resource_prefix}.stage."
      ;;
    install)
      remove_exact_directory "$destination" "$resource_prefix"
      ;;
    '') ;;
    *) fail "unknown rollback action $action" ;;
  esac
}

opengoal_root=${GOALPAD_OPENGOAL_ROOT:-}
source_pack=${GOALPAD_JAK1_SOURCE_OBJECT_PACK_ROOT:-}
source_pack_verifier=${GOALPAD_JAK1_SOURCE_OBJECT_PACK_VERIFIER:-}
resources_destination=${GOALPAD_APP_RESOURCE_DESTINATION:-}
fr3_builder=${GOALPAD_FR3_BUNDLE_BUILDER:-}

if [ -z "$resources_destination" ] && [ -n "${TARGET_BUILD_DIR:-}" ] && \
   [ -n "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]; then
  resources_destination=$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH
fi

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
    --source-pack-verifier)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      source_pack_verifier=$2
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
require_value "--source-pack-verifier / GOALPAD_JAK1_SOURCE_OBJECT_PACK_VERIFIER" \
  "$source_pack_verifier"
require_value "--resources-destination / GOALPAD_APP_RESOURCE_DESTINATION" \
  "$resources_destination"

ensure_safe_directory "$opengoal_root" "OpenGOAL root"
ensure_safe_directory "$source_pack" "source object pack"
ensure_safe_directory "$resources_destination" "app resource destination"
ensure_safe_executable "$source_pack_verifier" "source object-pack verifier"

if [ -z "$fr3_builder" ]; then
  fr3_builder=$opengoal_root/scripts/build-jak1-fr3-project-bundle.py
fi
ensure_safe_regular_file "$fr3_builder" "FR3 project-bundle builder"

fr3_destination=$resources_destination/OpenGOALProjectResources
pack_destination=$resources_destination/Jak1SourceObjectPack
ensure_safe_existing_resource "$fr3_destination" "OpenGOAL project resources"
ensure_safe_existing_resource "$pack_destination" "Jak 1 source object pack"

lock_directory=$resources_destination/.goalpad-jak1-import-resources.lock
if ! mkdir "$lock_directory" 2>/dev/null; then
  fail "another importer resource staging operation is already using this destination"
fi

fr3_stage=
pack_stage=
fr3_action=
pack_action=
cleanup() {
  if [ -n "$fr3_stage" ] && [ -d "$fr3_stage" ]; then
    remove_exact_directory "$fr3_stage" ".OpenGOALProjectResources.stage." || true
  fi
  if [ -n "$pack_stage" ] && [ -d "$pack_stage" ]; then
    remove_exact_directory "$pack_stage" ".Jak1SourceObjectPack.stage." || true
  fi
  rmdir "$lock_directory" 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM

# The verifier records the fixed 518-object identity; it never generates source objects.
"$source_pack_verifier" "$source_pack"

fr3_stage=$(mktemp -d "$resources_destination/.OpenGOALProjectResources.stage.XXXXXX") || \
  fail "could not allocate an FR3 staging directory"
rmdir "$fr3_stage" || fail "could not prepare the FR3 staging path"
/usr/bin/python3 "$fr3_builder" --source-root "$opengoal_root" "$fr3_stage"
/usr/bin/python3 "$fr3_builder" "$fr3_stage" --verify-only

pack_stage=$(mktemp -d "$resources_destination/.Jak1SourceObjectPack.stage.XXXXXX") || \
  fail "could not allocate a source-object-pack staging directory"
find "$source_pack" -mindepth 1 -maxdepth 1 -type f -exec cp -p '{}' "$pack_stage"/ ';'
"$source_pack_verifier" "$pack_stage"

if ! fr3_action=$(atomic_publish "$fr3_stage" "$fr3_destination"); then
  fail "could not publish OpenGOAL project resources"
fi
if [ "$fr3_action" = install ]; then
  fr3_stage=
fi

if ! pack_action=$(atomic_publish "$pack_stage" "$pack_destination"); then
  rollback_published_resource "$fr3_action" "$fr3_stage" "$fr3_destination" \
    OpenGOALProjectResources
  fr3_action=
  fail "could not publish the Jak 1 source object pack"
fi
if [ "$pack_action" = install ]; then
  pack_stage=
fi

# Recheck the published names. Atomic swaps cannot retain stale children, and these
# checks also catch a source changing between its preflight and copy.
if ! /usr/bin/python3 "$fr3_builder" "$fr3_destination" --verify-only || \
   ! "$source_pack_verifier" "$pack_destination"; then
  rollback_published_resource "$pack_action" "$pack_stage" "$pack_destination" \
    Jak1SourceObjectPack
  rollback_published_resource "$fr3_action" "$fr3_stage" "$fr3_destination" \
    OpenGOALProjectResources
  pack_action=
  fr3_action=
  fail "published resources did not pass their post-copy validation"
fi

if [ "$fr3_action" = swap ]; then
  remove_exact_directory "$fr3_stage" ".OpenGOALProjectResources.stage."
  fr3_stage=
fi
if [ "$pack_action" = swap ]; then
  remove_exact_directory "$pack_stage" ".Jak1SourceObjectPack.stage."
  pack_stage=
fi

echo "Staged validated Jak 1 importer resources into $resources_destination"
