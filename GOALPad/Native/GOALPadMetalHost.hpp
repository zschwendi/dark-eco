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

#include <array>
#include <cstdint>
#include <string>

#ifdef __OBJC__
@class CAMetalLayer;
@protocol MTLCommandBuffer;
@protocol MTLTexture;
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

/*! Enable the expensive per-frame renderer evidence retained for Developer Logs. */
void metal_host_set_detailed_frame_stats_enabled(bool enabled);

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
  std::uint64_t previous_producer_output_hash = 0;
  std::uint64_t current_producer_output_hash = 0;
  std::uint64_t previous_renderer_output_hash = 0;
  std::uint64_t current_renderer_output_hash = 0;
  std::uint64_t older_input_root_hash = 0;
  std::uint64_t previous_input_root_hash = 0;
  std::uint64_t current_input_root_hash = 0;
  std::uint64_t older_camera_hash = 0;
  std::uint64_t previous_camera_hash = 0;
  std::uint64_t current_camera_hash = 0;
  std::uint64_t previous_bind_pose_hash = 0;
  std::uint64_t current_bind_pose_hash = 0;
  double input_older_to_previous_distance = 0.0;
  double input_previous_to_current_distance = 0.0;
  double input_older_to_current_distance = 0.0;
  double output_older_to_previous_distance = 0.0;
  double output_previous_to_current_distance = 0.0;
  double output_older_to_current_distance = 0.0;
  double previous_output_expected_distance = 0.0;
  double current_output_expected_distance = 0.0;
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

/*! Retained numeric evidence for one unhealthy eichar-lod0 palette matrix. */
struct MetalHostMercPaletteHealthEvent {
  std::uint64_t engine_frame_id = 0;
  std::uint64_t host_tick_id = 0;
  std::uint64_t chain_ordinal = 0;
  std::uint8_t issue_mask = 0;
  std::uint32_t nonfinite_lane_mask = 0;
  int bone_slot = -1;
  std::uint64_t model_name_hash = 0;
  std::uint64_t matrix_hash = 0;
  double axis_norm_x = 0.0;
  double axis_norm_y = 0.0;
  double axis_norm_z = 0.0;
  double normalized_abs_determinant = 0.0;
  std::uint32_t source_address = 0;
  std::uint64_t source_base = 0;
  std::uint64_t expected_source_base = 0;

  bool valid() const { return issue_mask != 0; }
};

/*! Retained numeric evidence for one eichar-lod0 target/control disagreement or attack edge. */
struct MetalHostTargetControlEvent {
  std::uint64_t host_tick_id = 0;
  std::uint64_t chain_ordinal = 0;
  std::uint8_t issue_mask = 0;
  std::uint64_t engine_frame_id = 0;
  std::uint64_t producer_serial = 0;
  std::uint32_t source_base = 0;
  std::uint32_t target_state_id = 0;
  std::uint64_t previous_target_attack_id = 0;
  std::uint64_t current_target_attack_id = 0;
  std::uint32_t button0_abs = 0;
  std::uint32_t button0_rel = 0;
  std::uint8_t left_x = 0;
  std::uint8_t left_y = 0;
  double stick_direction = 0.0;
  double stick_speed = 0.0;
  double pad_magnitude = 0.0;
  double intent_forward_x = 0.0;
  double intent_forward_z = 0.0;
  double desired_forward_x = 0.0;
  double desired_forward_z = 0.0;
  double control_forward_x = 0.0;
  double control_forward_z = 0.0;
  double render_forward_x = 0.0;
  double render_forward_z = 0.0;
  double root_forward_x = 0.0;
  double root_forward_z = 0.0;
  double intent_control_dot = 0.0;
  double control_render_dot = 0.0;
  double render_root_dot = 0.0;

  bool valid() const { return issue_mask != 0; }
};

struct MetalHostTargetControlVector4 {
  double x = 0.0;
  double y = 0.0;
  double z = 0.0;
  double w = 0.0;
};

struct MetalHostTargetControlFacing {
  bool valid = false;
  double x = 0.0;
  double z = 0.0;
};

struct MetalHostTargetControlBasis {
  bool valid = false;
  double axis0_x = 0.0;
  double axis0_y = 0.0;
  double axis0_z = 0.0;
  double axis1_x = 0.0;
  double axis1_y = 0.0;
  double axis1_z = 0.0;
  double axis2_x = 0.0;
  double axis2_y = 0.0;
  double axis2_z = 0.0;
};

struct MetalHostTargetControlDeformation {
  bool valid = false;
  double axis_norm_x = 0.0;
  double axis_norm_y = 0.0;
  double axis_norm_z = 0.0;
  double aspect = 0.0;
  double normalized_abs_determinant = 0.0;
};

struct MetalHostTargetControlRootAnchor {
  bool valid = false;
  MetalHostTargetControlDeformation deformation;
  double scale_x = 0.0;
  double scale_y = 0.0;
  double scale_z = 0.0;
  std::uint32_t scale_w_bits = 0;
};

/*! The latest ordinary valid eichar-lod0 target/control sample, independent of issue events. */
struct MetalHostTargetControlObservation {
  bool valid = false;
  std::uint64_t host_tick_id = 0;
  std::uint64_t chain_ordinal = 0;
  std::uint64_t engine_frame_id = 0;
  int probe_bone_slot = -1;
  std::uint64_t producer_serial = 0;
  std::uint32_t source_base = 0;
  std::uint64_t camera_hash = 0;
  std::uint32_t target_state_id = 0;
  std::uint64_t target_attack_id = 0;
  std::uint32_t button0_abs = 0;
  std::uint32_t button0_rel = 0;
  std::uint8_t left_x = 0;
  std::uint8_t left_y = 0;
  double stick_direction = 0.0;
  double stick_speed = 0.0;
  double pad_magnitude = 0.0;
  MetalHostTargetControlVector4 raw_dir_targ;
  MetalHostTargetControlVector4 raw_quat_for_control;
  MetalHostTargetControlVector4 raw_render_quat;
  MetalHostTargetControlVector4 raw_turn_to_target;
  MetalHostTargetControlFacing intent_forward;
  MetalHostTargetControlFacing desired_forward;
  MetalHostTargetControlFacing control_forward;
  MetalHostTargetControlFacing render_forward;
  MetalHostTargetControlFacing root_forward;
  MetalHostTargetControlBasis camera_basis;
  MetalHostTargetControlDeformation input_root_deformation;
  MetalHostTargetControlDeformation output_deformation;
  MetalHostTargetControlRootAnchor root_anchor_1;
  MetalHostTargetControlRootAnchor root_anchor_2;
  MetalHostTargetControlRootAnchor root_anchor_3;
  bool node3_parent_scale_cancellation_selected = false;
  double input_root_translation_x = 0.0;
  double input_root_translation_y = 0.0;
  double input_root_translation_z = 0.0;
};

struct MetalHostTargetPostFlagObservation {
  bool valid = false;
  std::uint64_t host_tick_id = 0;
  std::uint64_t chain_ordinal = 0;
  std::uint64_t engine_frame_id = 0;
  std::uint64_t sample_serial = 0;
  std::uint32_t target_address = 0;
  std::uint32_t raw_draw_status = 0;
  std::uint64_t target_attack_id = 0;
  bool hidden = false;
};

struct PostFlagFrameDecision {
  bool accepted = false;
  bool hidden_transition = false;
  std::uint64_t serial_gap = 0;
};

/*! Keeps post-flag samples tied to the armed frame in which GOAL produced them. */
class PostFlagFrameGate {
 public:
  void reset() { *this = {}; }

  void begin_frame(std::uint64_t latest_serial) {
    account_unframed(latest_serial);
    m_frame_open = true;
  }

  void end_frame() { m_frame_open = false; }

  PostFlagFrameDecision observe(std::uint64_t serial, bool hidden) {
    PostFlagFrameDecision decision;
    if (!serial) {
      return decision;
    }
    if (!m_frame_open) {
      account_unframed(serial);
      return decision;
    }
    if (serial <= m_last_seen_serial) {
      return decision;
    }

    decision.accepted = true;
    decision.serial_gap = serial - m_last_seen_serial - 1;
    m_serial_gaps_total += decision.serial_gap;
    m_last_seen_serial = serial;
    m_samples_total++;
    if (hidden) {
      m_hidden_samples_total++;
    }
    if (m_has_previous_hidden && m_previous_hidden != hidden) {
      decision.hidden_transition = true;
      m_hidden_transitions_total++;
    }
    m_previous_hidden = hidden;
    m_has_previous_hidden = true;
    return decision;
  }

  std::uint64_t samples_total() const { return m_samples_total; }
  std::uint64_t hidden_samples_total() const { return m_hidden_samples_total; }
  std::uint64_t hidden_transitions_total() const { return m_hidden_transitions_total; }
  std::uint64_t serial_gaps_total() const { return m_serial_gaps_total; }
  std::uint64_t unframed_samples_total() const { return m_unframed_samples_total; }

 private:
  void account_unframed(std::uint64_t latest_serial) {
    if (latest_serial < m_last_seen_serial) {
      m_last_seen_serial = latest_serial;
      m_has_previous_hidden = false;
      return;
    }
    if (latest_serial > m_last_seen_serial) {
      m_unframed_samples_total += latest_serial - m_last_seen_serial;
      m_last_seen_serial = latest_serial;
    }
  }

  bool m_frame_open = false;
  bool m_has_previous_hidden = false;
  bool m_previous_hidden = false;
  std::uint64_t m_last_seen_serial = 0;
  std::uint64_t m_samples_total = 0;
  std::uint64_t m_hidden_samples_total = 0;
  std::uint64_t m_hidden_transitions_total = 0;
  std::uint64_t m_serial_gaps_total = 0;
  std::uint64_t m_unframed_samples_total = 0;
};

/*! Retained capture health and latest ordinary target/control evidence. */
struct MetalHostTargetControlTelemetry {
  std::uint64_t capture_attempts_total = 0;
  std::uint64_t valid_observations_total = 0;
  std::uint8_t last_capture_stage = 0;
  std::uint8_t last_capture_result = 0;
  MetalHostTargetControlObservation last_observation;
  std::uint64_t post_flag_samples_total = 0;
  std::uint64_t hidden_samples_total = 0;
  std::uint64_t hidden_transitions_total = 0;
  std::uint64_t post_flag_serial_gaps_total = 0;
  std::uint64_t unframed_post_flag_samples_total = 0;
  MetalHostTargetPostFlagObservation last_post_flag_sample;
  MetalHostTargetPostFlagObservation last_hidden_post_flag_sample;
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
  std::uint64_t render_camera_alternations = 0;
  std::uint64_t last_render_camera_alternation_older_frame_id = 0;
  std::uint64_t last_render_camera_alternation_previous_frame_id = 0;
  std::uint64_t last_render_camera_alternation_current_frame_id = 0;
  std::uint64_t last_render_camera_alternation_older_fingerprint = 0;
  std::uint64_t last_render_camera_alternation_previous_fingerprint = 0;
  std::uint64_t last_render_camera_alternation_current_fingerprint = 0;
  std::uint64_t last_render_camera_alternation_host_tick_id = 0;
  std::uint64_t last_render_camera_alternation_chain_ordinal = 0;
  std::uint64_t last_render_camera_alternation_packet_fingerprint = 0;
  std::uint16_t last_render_camera_alternation_live_mismatch_qwords = 0;
  std::uint16_t last_render_camera_alternation_packet_mismatch_qwords = 0;
  double last_render_camera_older_to_previous_distance = 0.0;
  double last_render_camera_previous_to_current_distance = 0.0;
  double last_render_camera_older_to_current_distance = 0.0;
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
  std::uint32_t last_merc_palette_health_nonfinite_lane_mask = 0;
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
  int merc_eichar_provenance_events = 0;
  std::uint64_t merc_eichar_provenance_events_total = 0;
  MetalHostMercTransformEvent first_merc_eichar_provenance_event;
  MetalHostMercTransformEvent last_merc_eichar_provenance_event;
  int merc_eichar_output_composition_mismatches = 0;
  std::uint64_t merc_eichar_output_composition_mismatches_total = 0;
  MetalHostMercTransformEvent first_merc_eichar_output_composition_mismatch;
  MetalHostMercTransformEvent last_merc_eichar_output_composition_mismatch;
  int merc_eichar_palette_health_issues = 0;
  std::uint64_t merc_eichar_palette_health_issues_total = 0;
  MetalHostMercPaletteHealthEvent first_merc_eichar_palette_health_event;
  MetalHostMercPaletteHealthEvent last_merc_eichar_palette_health_event;
  std::uint64_t merc_bad_bone_pointers = 0;
  std::uint64_t merc_bad_draw_ranges = 0;
  std::uint64_t camera_correction_events_total = 0;
  camera_correction_trace::Event last_camera_correction_event;
  int merc_eichar_target_control_events = 0;
  std::uint64_t merc_eichar_target_control_events_total = 0;
  int merc_eichar_target_control_divergences = 0;
  std::uint64_t merc_eichar_target_control_divergences_total = 0;
  int merc_eichar_target_control_attack_boundaries = 0;
  std::uint64_t merc_eichar_target_control_attack_boundaries_total = 0;
  MetalHostTargetControlEvent first_merc_eichar_target_control_event;
  MetalHostTargetControlEvent last_merc_eichar_target_control_event;
  bool jak1_tie_envmap_second_pass_enabled = false;
  int tie_envmap_second_pass_draws = 0;
  std::uint64_t tie_envmap_second_pass_draws_total = 0;
  bool jak1_shadow_output_enabled = false;
  MetalHostTargetControlTelemetry target_control_telemetry;
  std::uint64_t merc_eichar_weighted_profiled_base_draws = 0;
  std::uint64_t merc_eichar_weighted_profiled_vertices = 0;
  std::uint64_t merc_eichar_weighted_multi_bone_vertices = 0;
  std::uint64_t merc_eichar_weighted_affected_vertices = 0;
  std::uint64_t merc_eichar_weighted_static_multi_bone_vertices = 0;
  std::uint64_t merc_eichar_weighted_static_affected_vertices = 0;
  std::uint64_t merc_eichar_weighted_modified_multi_bone_vertices = 0;
  std::uint64_t merc_eichar_weighted_modified_affected_vertices = 0;
  std::uint64_t merc_eichar_weighted_tuple_groups = 0;
  std::uint64_t merc_eichar_weighted_affected_tuple_groups = 0;
  std::uint64_t merc_eichar_weighted_valid_basis_groups = 0;
  std::uint64_t merc_eichar_weighted_invalid_basis_groups = 0;
  std::uint64_t merc_eichar_weighted_affected_draws = 0;
  std::uint64_t merc_eichar_weighted_affected_effects = 0;
  std::uint64_t merc_eichar_weighted_profile_tuple_mismatches = 0;
  std::uint64_t merc_eichar_weighted_profile_capacity_drops = 0;
  double merc_eichar_weighted_maximum_axis_ratio = 0.0;
  double merc_eichar_weighted_minimum_normalized_abs_determinant = 0.0;
  std::uint8_t merc_eichar_weighted_coverage = 0;
  std::uint64_t merc_eichar_packets = 0;
  std::uint64_t merc_eichar_unique_source_bases = 0;
  std::uint64_t merc_eichar_repeated_packets = 0;
  std::uint64_t merc_eichar_repeated_packets_same_palette = 0;
  std::uint64_t merc_eichar_repeated_packets_conflicting_palette = 0;
  std::uint64_t merc_eichar_actual_base_draws = 0;
  std::uint64_t merc_eichar_unique_base_draws = 0;
  std::uint64_t merc_eichar_repeated_base_draws = 0;
  std::uint64_t merc_eichar_repeated_base_draws_same_palette = 0;
  std::uint64_t merc_eichar_repeated_base_draws_conflicting_palette = 0;
  std::uint64_t merc_eichar_trace_capacity_drops = 0;
  std::uint64_t merc_eichar_bound_palette_hash_mismatches = 0;
  std::uint64_t merc_eichar_weighted_skin_evidence_total = 0;
  std::uint8_t merc_eichar_weighted_issue_mask = 0;
  std::uint64_t last_merc_eichar_weighted_skin_engine_frame_id = 0;
  std::uint64_t last_merc_eichar_weighted_skin_host_tick_id = 0;
  std::uint64_t last_merc_eichar_weighted_skin_chain_ordinal = 0;
};
MetalHostStats metal_host_stats();
const camera_correction_trace::Tail& metal_host_camera_correction_tail();
MetalHostTargetControlTelemetry metal_host_target_control_telemetry();

#ifdef __OBJC__

struct MetalHostStereoView {
  std::uint64_t view_id = 0;
  id<MTLTexture> color_texture = nullptr;
  id<MTLTexture> depth_texture = nullptr;
  std::array<float, 16> clip_from_game_clip = {};
};

enum class MetalHostStereoFrameCompletion {
  skipped,
  submitted,
  failed,
};

enum class MetalHostStereoFrameReservation {
  reserved,
  busy,
  failed,
};

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

/*! Reserve the shared stream allocator without waiting for an in-flight submission. */
MetalHostStereoFrameReservation metal_host_reserve_stereo_frame();

/*! Arm one tick after the host lazily acquires both LowLevelTexture replacements. */
bool metal_host_begin_reserved_stereo_frame(const MetalHostFrame& frame,
                                            id<MTLCommandBuffer> command_buffer,
                                            const MetalHostStereoView& left,
                                            const MetalHostStereoView& right);

/*! Release a reservation that did not reach a submitted DMA chain. */
void metal_host_cancel_reserved_stereo_frame();

/*! Keep Comfort mode nonblocking if the last external stereo submission stopped completing. */
void metal_host_prepare_stereo_fallback();

/*!
 * Close the armed display-link tick and report whether its chain scheduled a drawable.
 *
 * Rendering has already happened inside `send_chain`; this call only clears the retained layer
 * and lets the app update its scheduled-drawable count.
 */
bool metal_host_end_frame();

/*! Commit the paired stereo command buffer once without waiting. */
MetalHostStereoFrameCompletion metal_host_end_stereo_frame();

/*! Point the layer at the renderer's device. Safe before `metal_host_start`. */
void metal_host_attach_layer(CAMetalLayer* layer);

#endif  // __OBJC__

}  // namespace goalpad
