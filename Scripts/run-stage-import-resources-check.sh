#!/bin/sh
# Synthetic coverage for one checked importer-resource staging profile.

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
game=${GOALPAD_IMPORT_RESOURCE_CHECK_GAME:-}
case "$game" in
  jak1)
    display_name="Jak 1"
    stager=$script_directory/stage-jak1-import-resources.sh
    fr3_resource_name=OpenGOALProjectResources
    source_pack_resource_name=Jak1SourceObjectPack
    ;;
  jak2)
    display_name="Jak II"
    stager=$script_directory/stage-jak2-import-resources.sh
    fr3_resource_name=Jak2ProjectResources
    source_pack_resource_name=Jak2SourceObjectPack
    ;;
  *)
    echo "select a staging check profile through its wrapper" >&2
    exit 2
    ;;
esac
temporary_root=$(mktemp -d "/private/tmp/goalpad-$game-import-resource-stage.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT HUP INT TERM

opengoal_root=$temporary_root/opengoal
source_pack=$temporary_root/source-pack
resources=$temporary_root/resources
builder=$temporary_root/fake-fr3-builder.py
verifier=$temporary_root/fake-source-pack-verifier.sh

mkdir -p "$opengoal_root/scripts" "$source_pack" "$resources"

cat > "$builder" <<'PY'
#!/usr/bin/env python3
import pathlib
import sys

arguments = sys.argv[1:]
verify = arguments[-1] == "--verify-only"
path = pathlib.Path(arguments[-2] if verify else arguments[-1])
expected = {"manifest", "project.json"}
if verify:
    if not path.is_dir() or {item.name for item in path.iterdir()} != expected:
        raise SystemExit("invalid fake FR3 bundle")
    for name in expected:
        if not (path / name).is_file() or (path / name).is_symlink():
            raise SystemExit("unsafe fake FR3 bundle")
else:
    if path.exists():
        raise SystemExit("fake builder refuses an existing output")
    path.mkdir()
    (path / "manifest").write_text("fake-manifest\n", encoding="utf-8")
    (path / "project.json").write_text("{}\n", encoding="utf-8")
PY

cat > "$verifier" <<'SH'
#!/bin/sh
set -eu
root=$1
[ -d "$root" ] && [ ! -L "$root" ] || exit 1
actual=$(find "$root" -mindepth 1 -maxdepth 1 -print | sed 's#.*/##' | sort | tr '\n' ' ')
[ "$actual" = "a.o source-object-pack.manifest " ] || exit 1
[ -f "$root/a.o" ] && [ ! -L "$root/a.o" ] || exit 1
[ -f "$root/source-object-pack.manifest" ] && [ ! -L "$root/source-object-pack.manifest" ] || exit 1
SH
chmod +x "$verifier"

printf 'object\n' > "$source_pack/a.o"
printf 'manifest\n' > "$source_pack/source-object-pack.manifest"
mkdir -p "$resources/$fr3_resource_name" "$resources/$source_pack_resource_name"
printf 'stale\n' > "$resources/$fr3_resource_name/stale"
printf 'stale\n' > "$resources/$source_pack_resource_name/stale"

GOALPAD_FR3_BUNDLE_BUILDER=$builder "$stager" \
  --opengoal-root "$opengoal_root" \
  --source-pack "$source_pack" \
  --source-pack-verifier "$verifier" \
  --resources-destination "$resources"

[ ! -e "$resources/$fr3_resource_name/stale" ]
[ ! -e "$resources/$source_pack_resource_name/stale" ]
[ "$(find "$resources/$fr3_resource_name" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d ' ')" = 2 ]
[ "$(find "$resources/$source_pack_resource_name" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d ' ')" = 2 ]

printf 'unexpected\n' > "$source_pack/stale.o"
if GOALPAD_FR3_BUNDLE_BUILDER=$builder "$stager" \
  --opengoal-root "$opengoal_root" \
  --source-pack "$source_pack" \
  --source-pack-verifier "$verifier" \
  --resources-destination "$resources"; then
  echo "stager accepted a source pack with a stale file" >&2
  exit 1
fi

[ ! -e "$resources/$fr3_resource_name/stale" ]
[ ! -e "$resources/$source_pack_resource_name/stale" ]
[ "$(find "$resources/$fr3_resource_name" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d ' ')" = 2 ]
[ "$(find "$resources/$source_pack_resource_name" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d ' ')" = 2 ]

echo "$display_name importer resource staging synthetic check passed."
