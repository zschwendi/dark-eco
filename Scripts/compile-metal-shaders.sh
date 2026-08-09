#!/bin/sh
# Compile the renderer's checked-in MSL to a metallib for the target's SDK, and write it out as a
# C byte array the app compiles into its own signed __TEXT.
#
# This is the Xcode equivalent of the metallib + embed_metallib.cmake step in
# OpenGOAL/game/CMakeLists.txt. Nothing is compiled on the iPad: a shader built at runtime is code
# the signature does not cover, and an ordinary iPadOS install will not run it.
#
# Run as a build phase, from the "Compile Metal shaders" phase of the GOALPad target.

set -eu

opengoal_root=${GOALPAD_OPENGOAL_ROOT:-$SRCROOT/OpenGOAL}
shader_dir="$opengoal_root/game/graphics/pipelines/metal/shaders"
out_dir="$DERIVED_SOURCES_DIR/goalpad-metal"
metallib="$out_dir/goalpad.metallib"
header="$out_dir/goalpad_metallib_embed.h"
module_cache="$out_dir/module-cache"

mkdir -p "$out_dir" "$module_cache"

xcrun -sdk "$PLATFORM_NAME" metal -Wall -Werror \
    -fmodules-cache-path="$module_cache" -o "$metallib" \
    "$shader_dir/scaffold.metal" \
    "$shader_dir/direct.metal" \
    "$shader_dir/eye.metal" \
    "$shader_dir/generic.metal" \
    "$shader_dir/shadow.metal" \
    "$shader_dir/sprite.metal" \
    "$shader_dir/background.metal" \
    "$shader_dir/ocean.metal" \
    "$shader_dir/merc2.metal"

python3 - "$metallib" "$header" <<'EMBED'
import sys

source, target = sys.argv[1], sys.argv[2]
data = open(source, "rb").read()
with open(target, "w") as out:
    out.write("/* generated from %s - do not edit */\n" % source)
    out.write("const unsigned char g_goalpad_metallib[] = {")
    out.write(",".join(str(b) for b in data))
    out.write("};\n")
    out.write("const unsigned long g_goalpad_metallib_size = sizeof(g_goalpad_metallib);\n")
EMBED

echo "note: compiled $(wc -c < "$metallib" | tr -d ' ') bytes of MSL for $PLATFORM_NAME"
