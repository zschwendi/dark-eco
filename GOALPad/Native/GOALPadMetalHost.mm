#include "GOALPadMetalHost.hpp"

#include "GOALPadEngineSeams.h"
#include "GOALPadGameBoot.hpp"

#include <os/log.h>

#if GOALPAD_HAVE_GFX_SEAM

#include <algorithm>
#include <memory>
#include <thread>
#include <vector>

#include "common/dma/dma_copy.h"
#include "common/goal_constants.h"
#include "common/util/Timer.h"
#include "common/versions/versions.h"

#include "game/graphics/pipelines/metal/metal_level_data.h"
#include "game/graphics/pipelines/metal/metal_merc_model_pool.h"
#include "game/graphics/pipelines/metal/metal_renderer.h"
#include "game/graphics/pipelines/metal/metal_texture.h"
#include "game/graphics/texture/TexturePool.h"
#include "game/kernel/core/gfx_host.h"
#include "game/mips2c/jak1_bones_provenance_trace.h"
#include "game/runtime.h"

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#endif  // GOALPAD_HAVE_GFX_SEAM

namespace {

os_log_t gfx_log() {
  static os_log_t log = os_log_create("com.zephyrstudiosllc.eco", "Renderer");
  return log;
}

}  // namespace

#if GOALPAD_HAVE_GFX_SEAM

namespace {

/*!
 * Everything the renderer owns, in one place, all of it touched from one thread at a time - the
 * boot queue while the game boots, and the main thread from the first presented frame on.
 */
struct MetalHost {
  bool running = false;
  MetalRenderer* renderer = nullptr;
  std::shared_ptr<TexturePool> texture_pool;
  std::unique_ptr<FixedChunkDmaCopier> copier;

  float pmode_alp = 1.f;

  // Retained for one CADisplayLink tick. send_chain consumes each submitted chain synchronously
  // while its out-of-chain Merc bone pointers still name this frame's live EE data.
  CAMetalLayer* frame_layer = nil;
  goalpad::MetalHostFrame frame;
  std::thread::id frame_thread;
  bool frame_open = false;
  bool frame_rendered = false;
  std::uint64_t chains_in_frame = 0;
  bool reported_wrong_frame_thread = false;

  // the level art the game asked for, and what has been read off disk because of it
  std::string art_directory;
  std::vector<std::string> wanted;
  bool wanted_changed = false;
  bool common_loaded = false;
  bool reported_no_directory = false;
  std::vector<std::string> loaded;  // in load order, including levels that would not load

  goalpad::MetalHostStats stats;
  goalpad::camera_correction_trace::EventTrace camera_correction_trace;
};
MetalHost g_host;

std::string join_plus(const std::vector<std::string>& names) {
  std::string out;
  for (const auto& name : names) {
    if (!out.empty()) {
      out += '+';
    }
    out += name;
  }
  return out;
}

/*!
 * One level's art into both places it has to go: the background renderers' registry (tfrag / tie /
 * shrub geometry plus the level's textures) and the merc model pool (its character geometry).
 * Mirror of `load_level_art` in metal_pipeline.mm.
 */
bool load_level_art(const std::string& name, bool is_common) {
  const std::string path = g_host.art_directory + "/" + name + ".fr3";
  Timer timer;
  std::string error;
  auto* level = metal_level_data::load_fr3(g_host.renderer->device(), g_host.renderer->queue(),
                                           *g_host.texture_pool, path, is_common, &error);
  if (!level) {
    os_log_error(gfx_log(), "Level art %{public}s would not load: %{public}s", path.c_str(),
                 error.c_str());
    return false;
  }
  MetalMercModelPool::LoadResult merc;
  if (!metal_merc_models().load_fr3(path, is_common, &merc, &error)) {
    os_log_error(gfx_log(), "Merc models in %{public}s would not load: %{public}s", path.c_str(),
                 error.c_str());
    return false;
  }
  g_host.stats.last_level_load_ms = timer.getMs();
  os_log(gfx_log(),
         "Loaded level art %{public}s in %.0f ms - %d textures, %zu/%zu/%zu tfrag/tie/shrub trees, "
         "%d merc models.",
         name.c_str(), g_host.stats.last_level_load_ms, (int)level->textures.size(),
         level->tfrag[0].size(), level->tie[0].size(), level->shrub.size(), merc.models);
  return true;
}

/*!
 * Load whatever the game has asked for and does not have yet.
 *
 * This runs where the game asked - inside `__pc-set-levels`, on the thread the GOAL frame is on -
 * rather than being deferred to the next render. It has to: a texture page the game uploads is
 * pointed at its real data by `__pc-texture-relocate`, and the pool asserts when the level that
 * data lives in is not there yet. The desktop host gets away with deferring because its render
 * thread is already running frames while the game boots; here nothing renders until the boot has
 * finished, so the load has to happen when it is asked for. Nothing is drawing either way, which
 * is what makes both safe.
 *
 * Levels are not unloaded: nothing here knows when the last draw referencing a level's buffers has
 * retired, which is what the GL loader's reference counting is for. Memory therefore grows with
 * the number of distinct levels a session visits.
 */
void service_level_requests() {
  if (g_host.art_directory.empty()) {
    if (!g_host.wanted.empty() && !g_host.reported_no_directory) {
      g_host.reported_no_directory = true;
      os_log_error(gfx_log(),
                   "The game asked for level art (%{public}s) but no fr3 directory is set; the "
                   "world will draw with no geometry.",
                   join_plus(g_host.wanted).c_str());
    }
    return;
  }
  if (!g_host.wanted_changed && g_host.common_loaded) {
    return;
  }
  g_host.wanted_changed = false;

  // The shared level every other level's textures sit beside. The GL loader calls this one
  // "common" and loads it once at startup.
  if (!g_host.common_loaded) {
    g_host.common_loaded = true;
    if (!load_level_art("GAME", true)) {
      g_host.stats.level_failures++;
    }
  }

  for (const auto& name : g_host.wanted) {
    if (std::find(g_host.loaded.begin(), g_host.loaded.end(), name) != g_host.loaded.end()) {
      continue;
    }
    const bool ok = load_level_art(name, false);
    // Remembered either way, so a level whose art will not load is reported once rather than
    // retried every frame.
    g_host.loaded.push_back(name);
    if (ok) {
      g_host.stats.levels_loaded++;
      g_host.stats.levels_loaded_names = join_plus(g_host.loaded);
    } else {
      g_host.stats.level_failures++;
    }
  }
}

goalpad::MetalHostMercTransformEvent retain_merc_transform_event(
    const metal_merc_transform_trace::Event& event,
    std::uint64_t host_tick_id,
    std::uint64_t chain_ordinal) {
  goalpad::MetalHostMercTransformEvent retained;
  retained.host_tick_id = host_tick_id;
  retained.chain_ordinal = chain_ordinal;
  retained.issue_mask = event.issue_mask;
  retained.bone_slot = event.bone_slot;
  retained.model_name_hash = event.model_name_hash;
  retained.older_frame_id = event.older_frame_id;
  retained.previous_frame_id = event.previous_frame_id;
  retained.current_frame_id = event.current_frame_id;
  retained.older_matrix_hash = event.older_matrix_hash;
  retained.previous_matrix_hash = event.previous_matrix_hash;
  retained.current_matrix_hash = event.current_matrix_hash;
  retained.previous_axis_norm_x = event.previous_axis_norm_x;
  retained.previous_axis_norm_y = event.previous_axis_norm_y;
  retained.previous_axis_norm_z = event.previous_axis_norm_z;
  retained.current_axis_norm_x = event.current_axis_norm_x;
  retained.current_axis_norm_y = event.current_axis_norm_y;
  retained.current_axis_norm_z = event.current_axis_norm_z;
  retained.previous_scale = event.previous_scale;
  retained.current_scale = event.current_scale;
  retained.previous_aspect = event.previous_aspect;
  retained.current_aspect = event.current_aspect;
  retained.older_source_base = event.older_source_base;
  retained.previous_source_base = event.previous_source_base;
  retained.current_source_base = event.current_source_base;
  retained.input_root_bone = event.input_root_bone;
  retained.older_producer_serial = event.older_producer_serial;
  retained.previous_producer_serial = event.previous_producer_serial;
  retained.current_producer_serial = event.current_producer_serial;
  retained.older_input_root_hash = event.older_input_root_hash;
  retained.previous_input_root_hash = event.previous_input_root_hash;
  retained.current_input_root_hash = event.current_input_root_hash;
  retained.older_camera_hash = event.older_camera_hash;
  retained.previous_camera_hash = event.previous_camera_hash;
  retained.current_camera_hash = event.current_camera_hash;
  retained.previous_bind_pose_hash = event.previous_bind_pose_hash;
  retained.current_bind_pose_hash = event.current_bind_pose_hash;
  retained.input_older_to_previous_distance = event.input_older_to_previous_distance;
  retained.input_previous_to_current_distance = event.input_previous_to_current_distance;
  retained.input_older_to_current_distance = event.input_older_to_current_distance;
  retained.output_older_to_previous_distance = event.output_older_to_previous_distance;
  retained.output_previous_to_current_distance = event.output_previous_to_current_distance;
  retained.output_older_to_current_distance = event.output_older_to_current_distance;
  retained.previous_output_expected_distance = event.previous_output_expected_distance;
  retained.current_output_expected_distance = event.current_output_expected_distance;
  retained.camera_older_to_previous_distance = event.camera_older_to_previous_distance;
  retained.camera_previous_to_current_distance = event.camera_previous_to_current_distance;
  retained.camera_older_to_current_distance = event.camera_older_to_current_distance;
  retained.previous_input_translation_x = event.previous_input_translation_x;
  retained.previous_input_translation_y = event.previous_input_translation_y;
  retained.previous_input_translation_z = event.previous_input_translation_z;
  retained.current_input_translation_x = event.current_input_translation_x;
  retained.current_input_translation_y = event.current_input_translation_y;
  retained.current_input_translation_z = event.current_input_translation_z;
  return retained;
}

goalpad::MetalHostMercPaletteHealthEvent retain_merc_palette_health_event(
    const metal_renderer::MercPaletteHealthEvent& event,
    std::uint64_t engine_frame_id,
    std::uint64_t host_tick_id,
    std::uint64_t chain_ordinal) {
  goalpad::MetalHostMercPaletteHealthEvent retained;
  retained.engine_frame_id = engine_frame_id;
  retained.host_tick_id = host_tick_id;
  retained.chain_ordinal = chain_ordinal;
  retained.issue_mask = event.issue_mask;
  retained.nonfinite_lane_mask = event.nonfinite_lane_mask;
  retained.bone_slot = event.bone_slot;
  retained.model_name_hash = event.model_name_hash;
  retained.matrix_hash = event.matrix_hash;
  retained.axis_norm_x = event.axis_norm_x;
  retained.axis_norm_y = event.axis_norm_y;
  retained.axis_norm_z = event.axis_norm_z;
  retained.normalized_abs_determinant = event.normalized_abs_determinant;
  retained.source_address = event.source_address;
  retained.source_base = event.source_base;
  retained.expected_source_base = event.expected_source_base;
  return retained;
}

goalpad::MetalHostTargetControlEvent retain_target_control_event(
    const metal_merc_transform_trace::TargetControlEvent& event,
    std::uint64_t host_tick_id,
    std::uint64_t chain_ordinal) {
  goalpad::MetalHostTargetControlEvent retained;
  retained.host_tick_id = host_tick_id;
  retained.chain_ordinal = chain_ordinal;
  retained.issue_mask = event.issue_mask;
  retained.engine_frame_id = event.engine_frame_id;
  retained.producer_serial = event.producer_serial;
  retained.source_base = event.source_base;
  retained.target_state_id = event.target_state_id;
  retained.previous_target_attack_id = event.previous_target_attack_id;
  retained.current_target_attack_id = event.current_target_attack_id;
  retained.button0_abs = event.button0_abs;
  retained.button0_rel = event.button0_rel;
  retained.left_x = event.left_x;
  retained.left_y = event.left_y;
  retained.stick_direction = event.stick_direction;
  retained.stick_speed = event.stick_speed;
  retained.pad_magnitude = event.pad_magnitude;
  retained.intent_forward_x = event.intent_forward.x;
  retained.intent_forward_z = event.intent_forward.z;
  retained.desired_forward_x = event.desired_forward.x;
  retained.desired_forward_z = event.desired_forward.z;
  retained.control_forward_x = event.control_forward.x;
  retained.control_forward_z = event.control_forward.z;
  retained.render_forward_x = event.render_forward.x;
  retained.render_forward_z = event.render_forward.z;
  retained.root_forward_x = event.root_forward.x;
  retained.root_forward_z = event.root_forward.z;
  retained.intent_control_dot = event.intent_control_dot;
  retained.control_render_dot = event.control_render_dot;
  retained.render_root_dot = event.render_root_dot;
  return retained;
}

goalpad::MetalHostTargetControlVector4 retain_target_control_vector(
    const std::array<float, 4>& vector) {
  return {vector[0], vector[1], vector[2], vector[3]};
}

goalpad::MetalHostTargetControlFacing retain_target_control_facing(
    const metal_merc_transform_trace::FacingSnapshot& facing) {
  return {facing.valid, facing.x, facing.z};
}

goalpad::MetalHostTargetControlBasis retain_target_control_basis(
    const metal_merc_transform_trace::BasisSnapshot& basis) {
  return {basis.valid,
          basis.components[0],
          basis.components[1],
          basis.components[2],
          basis.components[3],
          basis.components[4],
          basis.components[5],
          basis.components[6],
          basis.components[7],
          basis.components[8]};
}

goalpad::MetalHostTargetControlDeformation retain_target_control_deformation(
    const metal_merc_transform_trace::DeformationSnapshot& deformation) {
  return {deformation.valid,
          deformation.axis_norm_x,
          deformation.axis_norm_y,
          deformation.axis_norm_z,
          deformation.aspect,
          deformation.normalized_abs_determinant};
}

goalpad::MetalHostTargetControlObservation retain_target_control_observation(
    const metal_merc_transform_trace::TargetControlObservation& observation,
    std::uint64_t host_tick_id,
    std::uint64_t chain_ordinal) {
  goalpad::MetalHostTargetControlObservation retained;
  retained.valid = observation.valid;
  retained.host_tick_id = host_tick_id;
  retained.chain_ordinal = chain_ordinal;
  retained.engine_frame_id = observation.engine_frame_id;
  retained.probe_bone_slot = observation.probe_bone_slot;
  retained.producer_serial = observation.producer_serial;
  retained.source_base = observation.source_base;
  retained.camera_hash = observation.camera_hash;
  retained.target_state_id = observation.target_state_id;
  retained.target_attack_id = observation.target_attack_id;
  retained.button0_abs = observation.button0_abs;
  retained.button0_rel = observation.button0_rel;
  retained.left_x = observation.left_x;
  retained.left_y = observation.left_y;
  retained.stick_direction = observation.stick_direction;
  retained.stick_speed = observation.stick_speed;
  retained.pad_magnitude = observation.pad_magnitude;
  retained.raw_dir_targ = retain_target_control_vector(observation.raw_dir_targ);
  retained.raw_quat_for_control =
      retain_target_control_vector(observation.raw_quat_for_control);
  retained.raw_render_quat = retain_target_control_vector(observation.raw_render_quat);
  retained.raw_turn_to_target = retain_target_control_vector(observation.raw_turn_to_target);
  retained.intent_forward = retain_target_control_facing(observation.intent_forward);
  retained.desired_forward = retain_target_control_facing(observation.desired_forward);
  retained.control_forward = retain_target_control_facing(observation.control_forward);
  retained.render_forward = retain_target_control_facing(observation.render_forward);
  retained.root_forward = retain_target_control_facing(observation.root_forward);
  retained.camera_basis = retain_target_control_basis(observation.camera_basis);
  retained.input_root_deformation =
      retain_target_control_deformation(observation.input_root_deformation);
  retained.output_deformation =
      retain_target_control_deformation(observation.output_deformation);
  retained.input_root_translation_x = observation.input_root_translation_x;
  retained.input_root_translation_y = observation.input_root_translation_y;
  retained.input_root_translation_z = observation.input_root_translation_z;
  return retained;
}

void render_chain() {
  MetalRenderOptions opts;
  opts.game_res_w = g_host.frame.game_res_w;
  opts.game_res_h = g_host.frame.game_res_h;
  opts.draw_region_w = g_host.frame.draw_region_w;
  opts.draw_region_h = g_host.frame.draw_region_h;
  opts.pmode_alp = g_host.pmode_alp;
  opts.presentation_time = g_host.frame.presentation_time;
  opts.host_tick_id = g_host.stats.frames_armed;
  opts.chain_ordinal = g_host.chains_in_frame;
  const auto camera = goalpad::current_camera_frame_identity();
  opts.engine_frame_id = camera.engine_frame_id;
  opts.expected_camera_valid = camera.camera_valid;
  if (camera.camera_valid) {
    std::copy(camera.camera.begin(), camera.camera.end(), opts.expected_camera.bytes.begin());
  }
  opts.expected_render_camera_valid = camera.render_camera_valid;
  if (camera.render_camera_valid) {
    std::copy(camera.render_camera.begin(), camera.render_camera.end(),
              opts.expected_render_camera.bytes.begin());
  }

  const auto& chain = g_host.copier->get_last_result();
  const bool drawable_acquired = g_host.renderer->render_chain_frame(
      opts, g_host.frame_layer, chain.data.data(), chain.start_offset);
  g_host.frame_rendered = drawable_acquired || g_host.frame_rendered;

  const auto stats = g_host.renderer->chain_stats();
  const bool producer_alternation =
      stats.producer_camera_alternations > g_host.stats.producer_camera_alternations;
  const auto camera_correction_event = g_host.camera_correction_trace.observe(
      camera.camera_correction, producer_alternation, stats.last_host_tick_id,
      stats.last_chain_ordinal);
  g_host.stats.camera_correction_events_total = g_host.camera_correction_trace.event_count();
  if (camera_correction_event.valid) {
    g_host.stats.last_camera_correction_event = camera_correction_event;
  }
  g_host.stats.merc_models = stats.merc_models;
  g_host.stats.merc_draws = stats.merc_draws;
  g_host.stats.merc_bone_vectors = stats.merc_bone_vectors;
  g_host.stats.merc_missing_bone_slots = stats.merc_missing_bone_slots;
  g_host.stats.merc_models_with_missing_bone_slots = stats.merc_models_with_missing_bone_slots;
  if (stats.merc_missing_bone_slots > 0) {
    g_host.stats.merc_missing_bone_slots_total += stats.merc_missing_bone_slots;
    g_host.stats.merc_models_with_missing_bone_slots_total +=
        stats.merc_models_with_missing_bone_slots;
    g_host.stats.last_merc_missing_bone_engine_frame_id = stats.last_engine_frame_id;
    g_host.stats.last_merc_missing_bone_host_tick_id = stats.last_host_tick_id;
    g_host.stats.last_merc_missing_bone_chain_ordinal = stats.last_chain_ordinal;
    g_host.stats.last_merc_missing_bone_slots = stats.merc_missing_bone_slots;
    g_host.stats.last_merc_models_with_missing_bone_slots =
        stats.merc_models_with_missing_bone_slots;
  }
  g_host.stats.merc_nonfinite_bone_matrices = stats.merc_nonfinite_bone_matrices;
  g_host.stats.merc_degenerate_bone_matrices = stats.merc_degenerate_bone_matrices;
  g_host.stats.merc_incoherent_bone_sources = stats.merc_incoherent_bone_sources;
  g_host.stats.merc_models_with_palette_health_issues =
      stats.merc_models_with_palette_health_issues;
  if (stats.merc_models_with_palette_health_issues > 0) {
    g_host.stats.merc_nonfinite_bone_matrices_total += stats.merc_nonfinite_bone_matrices;
    g_host.stats.merc_degenerate_bone_matrices_total += stats.merc_degenerate_bone_matrices;
    g_host.stats.merc_incoherent_bone_sources_total += stats.merc_incoherent_bone_sources;
    g_host.stats.merc_models_with_palette_health_issues_total +=
        stats.merc_models_with_palette_health_issues;
    g_host.stats.last_merc_palette_health_engine_frame_id = stats.last_engine_frame_id;
    g_host.stats.last_merc_palette_health_host_tick_id = stats.last_host_tick_id;
    g_host.stats.last_merc_palette_health_chain_ordinal = stats.last_chain_ordinal;
    const auto& event = stats.last_merc_palette_health_event;
    g_host.stats.last_merc_palette_health_issue_mask = event.issue_mask;
    g_host.stats.last_merc_palette_health_nonfinite_lane_mask = event.nonfinite_lane_mask;
    g_host.stats.last_merc_palette_health_bone_slot = event.bone_slot;
    g_host.stats.last_merc_palette_health_model_name_hash = event.model_name_hash;
    g_host.stats.last_merc_palette_health_matrix_hash = event.matrix_hash;
    g_host.stats.last_merc_palette_health_axis_norm_x = event.axis_norm_x;
    g_host.stats.last_merc_palette_health_axis_norm_y = event.axis_norm_y;
    g_host.stats.last_merc_palette_health_axis_norm_z = event.axis_norm_z;
    g_host.stats.last_merc_palette_health_normalized_abs_determinant =
        event.normalized_abs_determinant;
    g_host.stats.last_merc_palette_health_source_address = event.source_address;
    g_host.stats.last_merc_palette_health_source_base = event.source_base;
    g_host.stats.last_merc_palette_health_expected_source_base = event.expected_source_base;
  }
  g_host.stats.merc_eichar_transform_discontinuities =
      stats.merc_eichar_transform_discontinuities;
  if (stats.merc_eichar_transform_discontinuities > 0) {
    g_host.stats.merc_eichar_transform_discontinuities_total +=
        stats.merc_eichar_transform_discontinuities;
    if (!g_host.stats.first_merc_eichar_transform_discontinuity.valid()) {
      g_host.stats.first_merc_eichar_transform_discontinuity = retain_merc_transform_event(
          stats.first_merc_eichar_transform_discontinuity, stats.last_host_tick_id,
          stats.last_chain_ordinal);
    }
    g_host.stats.last_merc_eichar_transform_discontinuity = retain_merc_transform_event(
        stats.last_merc_eichar_transform_discontinuity, stats.last_host_tick_id,
        stats.last_chain_ordinal);
  }
  g_host.stats.merc_eichar_provenance_events = stats.merc_eichar_provenance_events;
  if (stats.merc_eichar_provenance_events > 0) {
    g_host.stats.merc_eichar_provenance_events_total += stats.merc_eichar_provenance_events;
    if (!g_host.stats.first_merc_eichar_provenance_event.valid()) {
      g_host.stats.first_merc_eichar_provenance_event = retain_merc_transform_event(
          stats.first_merc_eichar_provenance_event, stats.last_host_tick_id,
          stats.last_chain_ordinal);
    }
    g_host.stats.last_merc_eichar_provenance_event = retain_merc_transform_event(
        stats.last_merc_eichar_provenance_event, stats.last_host_tick_id,
        stats.last_chain_ordinal);
  }
  g_host.stats.merc_eichar_output_composition_mismatches =
      stats.merc_eichar_output_composition_mismatches;
  if (stats.merc_eichar_output_composition_mismatches > 0) {
    g_host.stats.merc_eichar_output_composition_mismatches_total +=
        stats.merc_eichar_output_composition_mismatches;
    if (!g_host.stats.first_merc_eichar_output_composition_mismatch.valid()) {
      g_host.stats.first_merc_eichar_output_composition_mismatch =
          retain_merc_transform_event(stats.first_merc_eichar_output_composition_mismatch,
                                      stats.last_host_tick_id, stats.last_chain_ordinal);
    }
    g_host.stats.last_merc_eichar_output_composition_mismatch = retain_merc_transform_event(
        stats.last_merc_eichar_output_composition_mismatch, stats.last_host_tick_id,
        stats.last_chain_ordinal);
  }
  g_host.stats.merc_eichar_palette_health_issues = stats.merc_eichar_palette_health_issues;
  if (stats.merc_eichar_palette_health_issues > 0) {
    g_host.stats.merc_eichar_palette_health_issues_total +=
        stats.merc_eichar_palette_health_issues;
    if (!g_host.stats.first_merc_eichar_palette_health_event.valid()) {
      g_host.stats.first_merc_eichar_palette_health_event = retain_merc_palette_health_event(
          stats.first_merc_eichar_palette_health_event, stats.last_engine_frame_id,
          stats.last_host_tick_id, stats.last_chain_ordinal);
    }
    g_host.stats.last_merc_eichar_palette_health_event = retain_merc_palette_health_event(
        stats.last_merc_eichar_palette_health_event, stats.last_engine_frame_id,
        stats.last_host_tick_id, stats.last_chain_ordinal);
  }
  g_host.stats.merc_eichar_target_control_events = stats.merc_eichar_target_control_events;
  g_host.stats.merc_eichar_target_control_divergences =
      stats.merc_eichar_target_control_divergences;
  g_host.stats.merc_eichar_target_control_attack_boundaries =
      stats.merc_eichar_target_control_attack_boundaries;
  if (stats.merc_eichar_target_control_events > 0) {
    g_host.stats.merc_eichar_target_control_events_total +=
        stats.merc_eichar_target_control_events;
    g_host.stats.merc_eichar_target_control_divergences_total +=
        stats.merc_eichar_target_control_divergences;
    g_host.stats.merc_eichar_target_control_attack_boundaries_total +=
        stats.merc_eichar_target_control_attack_boundaries;
    if (!g_host.stats.first_merc_eichar_target_control_event.valid()) {
      g_host.stats.first_merc_eichar_target_control_event = retain_target_control_event(
          stats.first_merc_eichar_target_control_event, stats.last_host_tick_id,
          stats.last_chain_ordinal);
    }
    g_host.stats.last_merc_eichar_target_control_event = retain_target_control_event(
        stats.last_merc_eichar_target_control_event, stats.last_host_tick_id,
        stats.last_chain_ordinal);
  }
  auto& target_control_telemetry = g_host.stats.target_control_telemetry;
  if (stats.merc_eichar_target_control_capture_attempts > 0) {
    target_control_telemetry.capture_attempts_total +=
        stats.merc_eichar_target_control_capture_attempts;
    target_control_telemetry.last_capture_stage = static_cast<std::uint8_t>(
        stats.last_merc_eichar_target_control_capture_stage);
    target_control_telemetry.last_capture_result = static_cast<std::uint8_t>(
        stats.last_merc_eichar_target_control_capture_result);
  }
  if (stats.merc_eichar_target_control_valid_observations > 0) {
    target_control_telemetry.valid_observations_total +=
        stats.merc_eichar_target_control_valid_observations;
    target_control_telemetry.last_observation = retain_target_control_observation(
        stats.last_merc_eichar_target_control_observation, stats.last_host_tick_id,
        stats.last_chain_ordinal);
  }
  g_host.stats.merc_bad_bone_pointers += stats.merc_bad_bone_pointers;
  g_host.stats.merc_bad_draw_ranges += stats.merc_bad_draw_ranges;
  g_host.stats.last_host_tick_id = stats.last_host_tick_id;
  g_host.stats.last_chain_ordinal = stats.last_chain_ordinal;
  g_host.stats.last_engine_frame_id = stats.last_engine_frame_id;
  g_host.stats.last_camera_fingerprint = stats.last_camera_fingerprint;
  g_host.stats.last_camera_packets = stats.last_camera_packets;
  g_host.stats.producer_camera_alternations = stats.producer_camera_alternations;
  g_host.stats.last_camera_alternation_older_frame_id =
      stats.last_camera_alternation_older_frame_id;
  g_host.stats.last_camera_alternation_previous_frame_id =
      stats.last_camera_alternation_previous_frame_id;
  g_host.stats.last_camera_alternation_current_frame_id =
      stats.last_camera_alternation_current_frame_id;
  g_host.stats.last_camera_alternation_older_fingerprint =
      stats.last_camera_alternation_older_fingerprint;
  g_host.stats.last_camera_alternation_previous_fingerprint =
      stats.last_camera_alternation_previous_fingerprint;
  g_host.stats.last_camera_alternation_current_fingerprint =
      stats.last_camera_alternation_current_fingerprint;
  g_host.stats.last_camera_alternation_host_tick_id =
      stats.last_camera_alternation_host_tick_id;
  g_host.stats.last_camera_alternation_chain_ordinal =
      stats.last_camera_alternation_chain_ordinal;
  g_host.stats.last_camera_alternation_packet_fingerprint =
      stats.last_camera_alternation_packet_fingerprint;
  g_host.stats.last_camera_alternation_live_mismatch_qwords =
      stats.last_camera_alternation_live_mismatch_qwords;
  g_host.stats.last_camera_alternation_packet_mismatch_qwords =
      stats.last_camera_alternation_packet_mismatch_qwords;
  g_host.stats.last_camera_alternation_render_live_mismatch_qwords =
      stats.last_camera_alternation_render_live_mismatch_qwords;
  g_host.stats.last_camera_alternation_render_packet_mismatch_qwords =
      stats.last_camera_alternation_render_packet_mismatch_qwords;
  g_host.stats.last_camera_older_to_previous_distance =
      stats.last_camera_older_to_previous_distance;
  g_host.stats.last_camera_previous_to_current_distance =
      stats.last_camera_previous_to_current_distance;
  g_host.stats.last_camera_older_to_current_distance = stats.last_camera_older_to_current_distance;
  g_host.stats.last_live_camera_mismatches = stats.last_live_camera_mismatches;
  g_host.stats.last_packet_camera_mismatches = stats.last_packet_camera_mismatches;
  g_host.stats.last_live_camera_mismatch_qwords = stats.last_live_camera_mismatch_qwords;
  g_host.stats.last_packet_camera_mismatch_qwords = stats.last_packet_camera_mismatch_qwords;
  g_host.stats.live_camera_mismatches = stats.live_camera_mismatches;
  g_host.stats.packet_camera_mismatches = stats.packet_camera_mismatches;
}

// ---------------------------------------------------------------------------------------------
// the seam: the C hooks in game/kernel/core/gfx_host.h, answered by the renderer above
// ---------------------------------------------------------------------------------------------

void host_send_chain(const void* ee_base, uint32_t chain_offset) {
  if (!g_host.copier) {
    return;
  }
  g_host.stats.chains_sent++;
  if (!g_host.frame_open || g_host.frame_layer == nil) {
    // Boot can send display chains before the first CADisplayLink tick. They cannot safely be
    // deferred because their live Merc bones will be gone, so there is deliberately no pending
    // chain outside an armed gameplay frame.
    g_host.stats.chains_dropped++;
    return;
  }
  if (g_host.frame_thread != std::this_thread::get_id()) {
    g_host.stats.chains_dropped++;
    if (!g_host.reported_wrong_frame_thread) {
      os_log_error(gfx_log(),
                   "Dropping a DMA chain sent from a thread other than the armed frame thread.");
      g_host.reported_wrong_frame_thread = true;
    }
    return;
  }
  g_host.chains_in_frame++;
  g_host.copier->set_input_data(ee_base, chain_offset, /*run*/ true);
  render_chain();
}

/*!
 * `syncv`. On the desktop this blocks the game thread until the render thread has presented, and
 * that is where the game's frame rate comes from. Here the game frame and the render are the same
 * thread in the same `CADisplayLink` tick, so blocking would deadlock: the display link is the
 * clock instead, and this only reports the even/odd frame the PS2's `sceGsSyncV` returned.
 */
uint32_t host_vsync(void) {
  return (uint32_t)(g_host.stats.chains_sent & 1);
}

/*!
 * `sync-path`: the game asking whether the renderer is done with the chain it sent. During a
 * display-link tick `host_send_chain` renders before returning, so both the copied DMA chain and
 * its live Merc bone matrices have been consumed and EE memory is free to be reused.
 */
uint32_t host_sync_path(void) {
  return 0;
}

void host_texture_upload_now(const uint8_t* tpage, int mode, uint32_t s7_ptr) {
  if (g_host.texture_pool) {
    g_host.stats.texture_uploads++;
    g_host.texture_pool->handle_upload_now(tpage, mode, g_ee_main_mem, s7_ptr, false);
  }
}

void host_texture_relocate(uint32_t dst, uint32_t src, uint32_t format) {
  if (g_host.texture_pool) {
    g_host.texture_pool->relocate(dst, src, format);
  }
}

void host_set_levels(const char* const* names, int count) {
  std::vector<std::string> levels;
  levels.reserve(count);
  for (int i = 0; i < count; i++) {
    levels.emplace_back(names[i]);
  }
  if (levels == g_host.wanted) {
    return;
  }
  g_host.wanted = std::move(levels);
  g_host.wanted_changed = true;
  g_host.stats.levels_wanted = join_plus(g_host.wanted);
  service_level_requests();
}

void host_set_pmode_alp(float alp) {
  g_host.pmode_alp = alp;
}

}  // namespace

#endif  // GOALPAD_HAVE_GFX_SEAM

namespace goalpad {

#if GOALPAD_HAVE_GFX_SEAM

bool metal_host_start(std::string* error) {
  if (g_host.running) {
    return true;
  }
  jak1_bones_provenance_trace::registry().reset();
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  if (device == nil) {
    *error = "No Metal device is available.";
    return false;
  }
  auto* renderer = new MetalRenderer();
  if (!renderer->init(device)) {
    delete renderer;
    *error = "The Metal renderer would not initialize.";
    return false;
  }
  g_host.renderer = renderer;

  g_host.texture_pool = std::make_shared<TexturePool>(GameVersion::Jak1);
  if (!metal_setup_placeholder(renderer->device(), renderer->queue(), *g_host.texture_pool)) {
    g_host.texture_pool.reset();
    delete renderer;
    g_host.renderer = nullptr;
    *error = "The placeholder texture could not be created.";
    return false;
  }
  renderer->init_bucket_renderers(g_host.texture_pool.get(), GameVersion::Jak1);
  g_host.copier = std::make_unique<FixedChunkDmaCopier>(EE_MAIN_MEM_SIZE);
  g_host.running = true;
  os_log(gfx_log(), "Metal renderer started on %{public}s.", [[device name] UTF8String]);
  return true;
}

void metal_host_stop() {
  if (!g_host.running) {
    return;
  }
  goal_gfx_host_install(nullptr);
  metal_level_data::clear();
  g_host.texture_pool.reset();
  g_host.copier.reset();
  delete g_host.renderer;
  g_host = MetalHost();
}

bool metal_host_is_running() {
  return g_host.running;
}

bool metal_host_install_seam() {
  if (!g_host.running) {
    return false;
  }
  goal_gfx_host host = {};
  host.send_chain = host_send_chain;
  host.vsync = host_vsync;
  host.sync_path = host_sync_path;
  host.texture_upload_now = host_texture_upload_now;
  host.texture_relocate = host_texture_relocate;
  host.set_levels = host_set_levels;
  host.set_pmode_alp = host_set_pmode_alp;
  return goal_gfx_host_install(&host) == GOAL_KERNEL_CORE_OK;
}

void metal_host_set_level_art_directory(const std::string& path) {
  g_host.art_directory = path;
  // GAME.fr3, the shared level every other level's textures sit beside, before the game starts
  // uploading texture pages that point into it.
  service_level_requests();
}

MetalHostStats metal_host_stats() {
  if (g_host.renderer) {
    const auto chain = g_host.renderer->chain_stats();
    g_host.stats.chains_rendered = chain.chains_rendered;
    g_host.stats.last_draw_calls = chain.draw_calls;
    g_host.stats.last_triangles = chain.triangles;
    g_host.stats.drawables_acquired = chain.drawables_acquired;
    g_host.stats.drawable_misses = chain.drawable_misses;
    g_host.stats.late_present_submissions = chain.late_present_submissions;
    g_host.stats.submissions = chain.submissions;
    g_host.stats.presentations_completed = chain.presentations_completed;
    g_host.stats.presentation_drops = chain.presentation_drops;
    g_host.stats.presentation_order_mismatches = chain.presentation_order_mismatches;
    g_host.stats.last_submission_id = chain.last_submission_id;
    g_host.stats.last_presented_submission_id = chain.last_presented_submission_id;
    g_host.stats.last_dropped_submission_id = chain.last_dropped_submission_id;
    g_host.stats.last_drawable_id = chain.last_drawable_id;
    g_host.stats.last_presented_drawable_id = chain.last_presented_drawable_id;
    g_host.stats.last_presented_engine_frame_id = chain.last_presented_engine_frame_id;
    g_host.stats.last_presented_host_tick_id = chain.last_presented_host_tick_id;
    g_host.stats.last_presented_chain_ordinal = chain.last_presented_chain_ordinal;
    g_host.stats.last_requested_presentation_time = chain.last_requested_presentation_time;
    g_host.stats.last_actual_presentation_time = chain.last_actual_presentation_time;
  }
  return g_host.stats;
}

MetalHostTargetControlTelemetry metal_host_target_control_telemetry() {
  return g_host.stats.target_control_telemetry;
}

void metal_host_attach_layer(CAMetalLayer* layer) {
  if (layer == nil) {
    return;
  }
  layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
  if (g_host.renderer) {
    layer.device = g_host.renderer->device();
  }
}

bool metal_host_begin_frame(CAMetalLayer* layer, const MetalHostFrame& frame) {
  if (!g_host.running || layer == nil) {
    return false;
  }
  if (layer.device == nil) {
    layer.device = g_host.renderer->device();
  }

  // Normally nothing to do: the loading happens where the game asks, in `host_set_levels`. This
  // only catches a request that arrived before the art directory was known.
  service_level_requests();

  if (g_host.frame_open) {
    os_log_error(gfx_log(), "Beginning a Metal frame before the previous frame was closed.");
    g_host.frame_layer = nil;
    g_host.frame_thread = std::thread::id();
    g_host.frame_open = false;
    g_host.frame_rendered = false;
  }

  g_host.frame_layer = layer;
  g_host.frame = frame;
  g_host.frame_thread = std::this_thread::get_id();
  g_host.frame_open = true;
  g_host.frame_rendered = false;
  g_host.chains_in_frame = 0;
  g_host.stats.frames_armed++;
  return true;
}

bool metal_host_end_frame() {
  const bool rendered = g_host.frame_open && g_host.frame_rendered;
  if (g_host.frame_open) {
    if (g_host.chains_in_frame == 0) {
      g_host.stats.frames_without_chain++;
    }
    if (g_host.chains_in_frame > 1) {
      g_host.stats.frames_with_multiple_chains++;
    }
    g_host.stats.max_chains_per_frame =
        std::max(g_host.stats.max_chains_per_frame, g_host.chains_in_frame);
  }
  g_host.frame_layer = nil;
  g_host.frame_thread = std::thread::id();
  g_host.frame_open = false;
  g_host.frame_rendered = false;
  g_host.chains_in_frame = 0;
  return rendered;
}

#else  // GOALPAD_HAVE_GFX_SEAM

bool metal_host_start(std::string* error) {
  *error = "This build has no renderer seam: the pinned OpenGOAL has no game/kernel/core/gfx_host.h.";
  os_log_error(gfx_log(), "%{public}s", error->c_str());
  return false;
}

void metal_host_stop() {}

bool metal_host_is_running() {
  return false;
}

bool metal_host_install_seam() {
  return false;
}

void metal_host_set_level_art_directory(const std::string&) {}

MetalHostStats metal_host_stats() {
  return {};
}

MetalHostTargetControlTelemetry metal_host_target_control_telemetry() {
  return {};
}

void metal_host_attach_layer(CAMetalLayer*) {}

bool metal_host_begin_frame(CAMetalLayer*, const MetalHostFrame&) {
  return false;
}

bool metal_host_end_frame() {
  return false;
}

#endif  // GOALPAD_HAVE_GFX_SEAM

}  // namespace goalpad
