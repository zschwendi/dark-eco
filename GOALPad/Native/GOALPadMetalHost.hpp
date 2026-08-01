#pragma once

/*!
 * @file GOALPadMetalHost.hpp
 * The iPad's renderer host: what `game/goalpad_play.cpp` is for the desktop window.
 *
 * The engine and the renderer meet at one place, `game/kernel/core/gfx_host.h`: a table of plain C
 * function pointers that the machine layer's graphics functions are answered out of. The kernel
 * library names no renderer and the renderer names no host, so the same seam serves the SDL/Metal
 * desktop shell and this application. This file fills that table with the Metal renderer and
 * drives it from the app's `CAMetalLayer`.
 *
 * What is deliberately not reused is `game/graphics/pipelines/metal/metal_pipeline.mm`. That file
 * is the desktop *display*: it creates an SDL window, owns the SDL event queue and runs a frame
 * limiter. The iPad's display is a `CAMetalLayer` on a `CADisplayLink`, so the pieces below - the
 * renderer, the texture pool, the DMA-chain handoff and the level-art loading - are wired the same
 * way but to that instead. `MetalRenderer` itself, and every bucket renderer under it, is the same
 * source the Mac plays the game with.
 *
 * Threading: one thread does everything. See `metal_host_render`.
 */

#include <cstdint>
#include <string>

#ifdef __OBJC__
@class CAMetalLayer;
#endif

namespace goalpad {

/*!
 * Bring the Metal renderer up: device, command queue, shader library, texture pool and the Jak 1
 * bucket-renderer table. Must be called before the game boots - the game uploads textures while
 * it loads GAME.CGO, and the pool has to be there to catch them.
 *
 * Idempotent; false with `error` filled in when Metal is unavailable.
 */
bool metal_host_start(std::string* error);

/*! Release the renderer and everything it loaded. */
void metal_host_stop();

bool metal_host_is_running();

/*!
 * Answer the machine layer's graphics functions out of the renderer started above. Call after
 * `goal_kernel_core_stub_machine_layer` and before the first DGO load, exactly where
 * `goalpad_play.cpp` calls `goal_gfx_host_install`.
 */
bool metal_host_install_seam();

/*!
 * Where the player's extracted `.fr3` level art lives - the `fr3` directory of their own prepared
 * data. The game names the levels it wants through `__pc-set-levels`; this is where they are read
 * from. Without it the world has no geometry and the renderer says so once.
 */
void metal_host_set_level_art_directory(const std::string& path);

/*! The letterbox the present pass draws the game frame into, in drawable pixels. */
struct MetalHostFrame {
  int game_res_w = 640;
  int game_res_h = 480;
  int draw_region_w = 0;
  int draw_region_h = 0;
};

/*! What the renderer has been asked to do, for the on-screen readout and the log. */
struct MetalHostStats {
  std::uint64_t chains_sent = 0;      // __send-gfx-dma-chain calls
  std::uint64_t chains_rendered = 0;  // chains that reached the GPU
  std::uint64_t chains_dropped = 0;   // chains replaced before a frame consumed them
  std::uint64_t texture_uploads = 0;
  int levels_loaded = 0;
  int level_failures = 0;
  double last_level_load_ms = 0;
  std::string levels_wanted;
  std::string levels_loaded_names;
  int last_draw_calls = 0;
  int last_triangles = 0;
};
MetalHostStats metal_host_stats();

#ifdef __OBJC__

/*!
 * Draw the chain the engine built into `layer`, and present it.
 *
 * Called from the main thread once per `CADisplayLink` tick, straight after the engine's own frame
 * ran on that same thread. That single-threaded arrangement is the whole locking story: on the
 * desktop the engine runs on its own thread and `__pc-texture-relocate` from the game races the
 * render thread's level loading inside `TexturePool`, which does not lock internally (its callers
 * are expected to hold `pool.mutex()`, see `Loader.cpp`). Here the GOAL frame, the texture calls,
 * the level loads and the render are all the same thread in the same tick, so there is nothing to
 * race with and nothing to lock. Boot is the one thing that runs elsewhere, on its own queue, and
 * no frame is rendered until it has finished.
 *
 * Returns false when there is no chain to draw - before the first game frame, or on a tick the
 * engine did not produce one.
 */
bool metal_host_render(CAMetalLayer* layer, const MetalHostFrame& frame);

/*! Point the layer at the renderer's device. Safe before `metal_host_start`. */
void metal_host_attach_layer(CAMetalLayer* layer);

#endif  // __OBJC__

}  // namespace goalpad
