#pragma once

#include "GOALPadCameraCorrectionTrace.hpp"

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
 * Threading: one thread does everything. See `metal_host_begin_frame`.
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
  double presentation_time = 0.0;
};

/*! Retained numeric evidence for one consecutive-frame eichar-lod0 transform discontinuity. */
struct MetalHostMercTransformEvent {
  std::uint64_t host_tick_id = 0;
  std::uint64_t chain_ordinal = 0;
  std::uint8_t issue_mask = 0;
  int bone_slot = -1;
  std::uint64_t model_name_hash = 0;
  std::uint64_t older_frame_id = 0;
  std::uint64_t previous_frame_id = 0;
  std::uint64_t current_frame_id = 0;
  std::uint64_t older_matrix_hash = 0;
  std::uint64_t previous_matrix_hash = 0;
  std::uint64_t current_matrix_hash = 0;
  double previous_axis_norm_x = 0.0;
  double previous_axis_norm_y = 0.0;
  double previous_axis_norm_z = 0.0;
  double current_axis_norm_x = 0.0;
  double current_axis_norm_y = 0.0;
  double current_axis_norm_z = 0.0;
  double previous_scale = 0.0;
  double current_scale = 0.0;
  double previous_aspect = 0.0;
  double current_aspect = 0.0;
  std::uint64_t older_source_base = 0;
  std::uint64_t previous_source_base = 0;
  std::uint64_t current_source_base = 0;
  int input_root_bone = -1;
  std::uint64_t older_producer_serial = 0;
  std::uint64_t previous_producer_serial = 0;
  std::uint64_t current_producer_serial = 0;
  std::uint64_t older_input_root_hash = 0;
  std::uint64_t previous_input_root_hash = 0;
  std::uint64_t current_input_root_hash = 0;
  std::uint64_t older_camera_hash = 0;
  std::uint64_t previous_camera_hash = 0;
  std::uint64_t current_camera_hash = 0;
  double input_older_to_previous_distance = 0.0;
  double input_previous_to_current_distance = 0.0;
  double input_older_to_current_distance = 0.0;
  double output_older_to_previous_distance = 0.0;
  double output_previous_to_current_distance = 0.0;
  double output_older_to_current_distance = 0.0;
  double output_expected_distance = 0.0;
  double camera_older_to_previous_distance = 0.0;
  double camera_previous_to_current_distance = 0.0;
  double camera_older_to_current_distance = 0.0;
  double previous_input_translation_x = 0.0;
  double previous_input_translation_y = 0.0;
  double previous_input_translation_z = 0.0;
  double current_input_translation_x = 0.0;
  double current_input_translation_y = 0.0;
  double current_input_translation_z = 0.0;

  bool valid() const { return issue_mask != 0; }
};

/*! What the renderer has been asked to do, for the on-screen readout and the log. */
struct MetalHostStats {
  std::uint64_t chains_sent = 0;      // __send-gfx-dma-chain calls
  std::uint64_t chains_rendered = 0;  // chains whose game passes were encoded and committed
  std::uint64_t chains_dropped = 0;   // chains replaced before a frame consumed them
  std::uint64_t frames_armed = 0;
  std::uint64_t frames_without_chain = 0;
  std::uint64_t frames_with_multiple_chains = 0;
  std::uint64_t max_chains_per_frame = 0;
  std::uint64_t drawables_acquired = 0;
  std::uint64_t drawable_misses = 0;
  std::uint64_t late_present_submissions = 0;
  std::uint64_t last_host_tick_id = 0;
  std::uint64_t last_chain_ordinal = 0;
  std::uint64_t last_engine_frame_id = 0;
  std::uint64_t last_camera_fingerprint = 0;
  int last_camera_packets = 0;
  std::uint64_t producer_camera_alternations = 0;
  std::uint64_t last_camera_alternation_older_frame_id = 0;
  std::uint64_t last_camera_alternation_previous_frame_id = 0;
  std::uint64_t last_camera_alternation_current_frame_id = 0;
  std::uint64_t last_camera_alternation_older_fingerprint = 0;
  std::uint64_t last_camera_alternation_previous_fingerprint = 0;
  std::uint64_t last_camera_alternation_current_fingerprint = 0;
  std::uint64_t last_camera_alternation_host_tick_id = 0;
  std::uint64_t last_camera_alternation_chain_ordinal = 0;
  std::uint64_t last_camera_alternation_packet_fingerprint = 0;
  std::uint8_t last_camera_alternation_live_mismatch_qwords = 0;
  std::uint8_t last_camera_alternation_packet_mismatch_qwords = 0;
  std::uint16_t last_camera_alternation_render_live_mismatch_qwords = 0;
  std::uint16_t last_camera_alternation_render_packet_mismatch_qwords = 0;
  double last_camera_older_to_previous_distance = 0.0;
  double last_camera_previous_to_current_distance = 0.0;
  double last_camera_older_to_current_distance = 0.0;
  int last_live_camera_mismatches = 0;
  int last_packet_camera_mismatches = 0;
  std::uint8_t last_live_camera_mismatch_qwords = 0;
  std::uint8_t last_packet_camera_mismatch_qwords = 0;
  std::uint64_t live_camera_mismatches = 0;
  std::uint64_t packet_camera_mismatches = 0;
  std::uint64_t submissions = 0;
  std::uint64_t presentations_completed = 0;
  std::uint64_t presentation_drops = 0;
  std::uint64_t presentation_order_mismatches = 0;
  std::uint64_t last_submission_id = 0;
  std::uint64_t last_presented_submission_id = 0;
  std::uint64_t last_dropped_submission_id = 0;
  std::uint64_t last_drawable_id = 0;
  std::uint64_t last_presented_drawable_id = 0;
  std::uint64_t last_presented_engine_frame_id = 0;
  std::uint64_t last_presented_host_tick_id = 0;
  std::uint64_t last_presented_chain_ordinal = 0;
  double last_requested_presentation_time = 0.0;
  double last_actual_presentation_time = 0.0;
  std::uint64_t texture_uploads = 0;
  int levels_loaded = 0;
  int level_failures = 0;
  double last_level_load_ms = 0;
  std::string levels_wanted;
  std::string levels_loaded_names;
  int last_draw_calls = 0;
  int last_triangles = 0;
  int merc_models = 0;
  int merc_draws = 0;
  int merc_bone_vectors = 0;
  int merc_missing_bone_slots = 0;
  int merc_models_with_missing_bone_slots = 0;
  std::uint64_t merc_missing_bone_slots_total = 0;
  std::uint64_t merc_models_with_missing_bone_slots_total = 0;
  std::uint64_t last_merc_missing_bone_engine_frame_id = 0;
  std::uint64_t last_merc_missing_bone_host_tick_id = 0;
  std::uint64_t last_merc_missing_bone_chain_ordinal = 0;
  int last_merc_missing_bone_slots = 0;
  int last_merc_models_with_missing_bone_slots = 0;
  int merc_nonfinite_bone_matrices = 0;
  int merc_degenerate_bone_matrices = 0;
  int merc_incoherent_bone_sources = 0;
  int merc_models_with_palette_health_issues = 0;
  std::uint64_t merc_nonfinite_bone_matrices_total = 0;
  std::uint64_t merc_degenerate_bone_matrices_total = 0;
  std::uint64_t merc_incoherent_bone_sources_total = 0;
  std::uint64_t merc_models_with_palette_health_issues_total = 0;
  std::uint64_t last_merc_palette_health_engine_frame_id = 0;
  std::uint64_t last_merc_palette_health_host_tick_id = 0;
  std::uint64_t last_merc_palette_health_chain_ordinal = 0;
  std::uint8_t last_merc_palette_health_issue_mask = 0;
  int last_merc_palette_health_bone_slot = -1;
  std::uint64_t last_merc_palette_health_model_name_hash = 0;
  std::uint64_t last_merc_palette_health_matrix_hash = 0;
  double last_merc_palette_health_axis_norm_x = 0.0;
  double last_merc_palette_health_axis_norm_y = 0.0;
  double last_merc_palette_health_axis_norm_z = 0.0;
  double last_merc_palette_health_normalized_abs_determinant = 0.0;
  std::uint32_t last_merc_palette_health_source_address = 0;
  std::uint64_t last_merc_palette_health_source_base = 0;
  std::uint64_t last_merc_palette_health_expected_source_base = 0;
  int merc_eichar_transform_discontinuities = 0;
  std::uint64_t merc_eichar_transform_discontinuities_total = 0;
  MetalHostMercTransformEvent first_merc_eichar_transform_discontinuity;
  MetalHostMercTransformEvent last_merc_eichar_transform_discontinuity;
  MetalHostMercTransformEvent first_merc_eichar_provenance_event;
  MetalHostMercTransformEvent last_merc_eichar_provenance_event;
  std::uint64_t merc_bad_bone_pointers = 0;
  std::uint64_t merc_bad_draw_ranges = 0;
  std::uint64_t camera_correction_events_total = 0;
  camera_correction_trace::Event last_camera_correction_event;
};
MetalHostStats metal_host_stats();

#ifdef __OBJC__

/*!
 * Arm one display-link tick with its presentation surface and geometry.
 *
 * Called from the main thread immediately before the engine's own frame runs. That lets
 * `send_chain` draw synchronously, before the engine can rewrite the live bone matrices that Merc
 * packets point at but do not copy into their DMA chain.
 *
 * The single-threaded arrangement is the whole locking story: on the
 * desktop the engine runs on its own thread and `__pc-texture-relocate` from the game races the
 * render thread's level loading inside `TexturePool`, which does not lock internally (its callers
 * are expected to hold `pool.mutex()`, see `Loader.cpp`). Here the GOAL frame, the texture calls,
 * the level loads and the render are all the same thread in the same tick, so there is nothing to
 * race with and nothing to lock. Boot is the one thing that runs elsewhere, on its own queue, and
 * no frame is rendered until it has finished.
 *
 * Returns false when the renderer or presentation surface is unavailable.
 */
bool metal_host_begin_frame(CAMetalLayer* layer, const MetalHostFrame& frame);

/*!
 * Close the armed display-link tick and report whether its chain scheduled a drawable.
 *
 * Rendering has already happened inside `send_chain`; this call only clears the retained layer
 * and lets the app update its scheduled-drawable count.
 */
bool metal_host_end_frame();

/*! Point the layer at the renderer's device. Safe before `metal_host_start`. */
void metal_host_attach_layer(CAMetalLayer* layer);

#endif  // __OBJC__

}  // namespace goalpad
