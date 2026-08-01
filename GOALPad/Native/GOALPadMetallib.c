/*!
 * @file GOALPadMetallib.c
 * The renderer's GPU shaders, as bytes in the app's own signed data.
 *
 * The six `.metal` files under `OpenGOAL/game/graphics/pipelines/metal/shaders/` are checked-in
 * source. The "Compile Metal shaders" build phase compiles them for the target's SDK with
 * `xcrun metal` and writes the resulting `metallib` out as the byte array this file includes;
 * `MetalRenderer::init` hands that array to `newLibraryWithData:`.
 *
 * Nothing is compiled on the iPad. That is the same reason Jak 1's GOAL code is compiled to C on
 * the Mac: a shader compiled at runtime is code the signature does not cover, and an ordinary
 * iPadOS install will not run it. This is the exact equivalent of the `embed_metallib.cmake` step
 * `game/CMakeLists.txt` runs for the desktop build.
 */

#include "goalpad_metallib_embed.h"
