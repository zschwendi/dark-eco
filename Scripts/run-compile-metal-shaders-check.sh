#!/bin/sh

set -eu

fail() {
  echo "Metal shader build check failed: $*" >&2
  exit 1
}

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repository_root=$(CDPATH= cd -- "$script_directory/.." && pwd -P)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-metal-root-check.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT HUP INT TERM

source_root=$temporary_root/source-root
opengoal_root=$temporary_root/external-opengoal
shader_root=$opengoal_root/game/graphics/pipelines/metal/shaders
derived_sources=$temporary_root/derived
fake_bin=$temporary_root/bin
arguments=$temporary_root/xcrun-arguments
mkdir -p "$source_root" "$shader_root" "$derived_sources" "$fake_bin"

for shader in scaffold direct eye generic shadow sprite background ocean merc2; do
  : > "$shader_root/$shader.metal"
done

cat > "$fake_bin/xcrun" <<'FAKE_XCRUN'
#!/bin/sh
set -eu
printf '%s\n' "$@" > "$GOALPAD_XCRUN_ARGUMENTS"
output=
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then
    output=$2
    break
  fi
  shift
done
[ -n "$output" ] || exit 1
printf 'synthetic-metallib' > "$output"
FAKE_XCRUN
chmod +x "$fake_bin/xcrun"

PATH="$fake_bin:$PATH" \
  GOALPAD_XCRUN_ARGUMENTS="$arguments" \
  GOALPAD_OPENGOAL_ROOT="$opengoal_root" \
  SRCROOT="$source_root" \
  DERIVED_SOURCES_DIR="$derived_sources" \
  PLATFORM_NAME=iphoneos \
  "$script_directory/compile-metal-shaders.sh"

grep -Fqx "$shader_root/scaffold.metal" "$arguments" || \
  fail "the compiler did not receive the external scaffold shader"
grep -Fqx "$shader_root/merc2.metal" "$arguments" || \
  fail "the compiler did not receive the external merc2 shader"
if grep -Fq "$source_root/OpenGOAL" "$arguments"; then
  fail "the compiler used the default OpenGOAL root despite the override"
fi
grep -Fq 'g_goalpad_metallib' \
  "$derived_sources/goalpad-metal/goalpad_metallib_embed.h" || \
  fail "the synthetic metallib was not embedded"

project=$repository_root/GOALPad.xcodeproj/project.pbxproj
grep -Fq '"$(GOALPAD_OPENGOAL_ROOT)/game/graphics/pipelines/metal/shaders/scaffold.metal"' \
  "$project" || fail "the Xcode phase does not declare the external-root shader input"
if grep -Fq '"$(SRCROOT)/OpenGOAL/game/graphics/pipelines/metal/shaders/' "$project"; then
  fail "the Xcode phase still declares a hard-coded source-root shader input"
fi

echo "Metal shader external-root check passed"
