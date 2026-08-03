#import "GOALPadRuntimeBridge.h"

#include "GOALPadMetalHost.hpp"

#import <Metal/Metal.h>

#include <algorithm>

/*!
 * @file GOALPadRenderSurface.mm
 * The presentation surface: the CAMetalLayer the game is drawn into, and the geometry its present
 * pass works in.
 *
 * The game renders into an offscreen target at its own internal resolution and a PCRTC-style
 * present pass draws that target into a centred, letterboxed region of the drawable. That is what
 * `MetalRenderer::encode_present_pass` in the OpenGOAL fork does, and it is the contract this
 * surface satisfies: a layer with a known drawable size and pixel format, an internal resolution,
 * and a draw region that keeps the game's 4:3 aspect.
 *
 * The renderer itself is driven by the begin/end frame pair in GOALPadMetalHost.mm. This file
 * decides only where the game frame goes on the screen.
 */

/*! The PS2's internal resolution, which the game's own render target is a multiple of. */
static const int32_t kGameBaseWidth = 640;
static const int32_t kGameBaseHeight = 480;
static const int32_t kMaxInternalScale = 4;

static GOALPadMercTransformEvent makeMercTransformEvent(
    const goalpad::MetalHostMercTransformEvent &core) {
  return {core.host_tick_id,
          core.chain_ordinal,
          core.issue_mask,
          (int32_t)core.bone_slot,
          core.model_name_hash,
          core.older_frame_id,
          core.previous_frame_id,
          core.current_frame_id,
          core.older_matrix_hash,
          core.previous_matrix_hash,
          core.current_matrix_hash,
          core.previous_axis_norm_x,
          core.previous_axis_norm_y,
          core.previous_axis_norm_z,
          core.current_axis_norm_x,
          core.current_axis_norm_y,
          core.current_axis_norm_z,
          core.previous_scale,
          core.current_scale,
          core.previous_aspect,
          core.current_aspect,
          core.older_source_base,
          core.previous_source_base,
          core.current_source_base,
          (int32_t)core.input_root_bone,
          core.older_producer_serial,
          core.previous_producer_serial,
          core.current_producer_serial,
          core.older_input_root_hash,
          core.previous_input_root_hash,
          core.current_input_root_hash,
          core.older_camera_hash,
          core.previous_camera_hash,
          core.current_camera_hash,
          core.input_older_to_previous_distance,
          core.input_previous_to_current_distance,
          core.input_older_to_current_distance,
          core.output_older_to_previous_distance,
          core.output_previous_to_current_distance,
          core.output_older_to_current_distance,
          core.camera_older_to_previous_distance,
          core.camera_previous_to_current_distance,
          core.camera_older_to_current_distance,
          core.previous_input_translation_x,
          core.previous_input_translation_y,
          core.previous_input_translation_z,
          core.current_input_translation_x,
          core.current_input_translation_y,
          core.current_input_translation_z};
}

static GOALPadCameraCorrectionVector makeCameraCorrectionVector(
    const goalpad::camera_correction_trace::Vector4 &core) {
  return {core.values[0], core.values[1], core.values[2], core.values[3]};
}

static GOALPadCameraCorrectionSlaveFrame makeCameraCorrectionSlave(
    const goalpad::camera_correction_trace::SlaveSnapshot &core) {
  GOALPadCameraCorrectionSlaveFrame out = {};
  out.valid = core.valid;
  out.options = core.options;
  out.losState = core.los_state;
  out.stringVelocityDirection = core.string_velocity_direction;
  out.lineOfSightEnabled = core.line_of_sight_enabled();
  out.movementBlocked = core.movement_blocked();
  out.minimumDistanceOverride = core.minimum_distance_override;
  out.transform = makeCameraCorrectionVector(core.transform);
  out.viewFlat = makeCameraCorrectionVector(core.view_flat);
  out.stringTransform = makeCameraCorrectionVector(core.string_transform);
  out.desiredPosition = makeCameraCorrectionVector(core.desired_position);
  return out;
}

static GOALPadCameraCorrectionFrame makeCameraCorrectionFrame(
    const goalpad::camera_correction_trace::FrameSnapshot &core) {
  GOALPadCameraCorrectionFrame out = {};
  out.valid = core.valid;
  out.engineFrameID = core.engine_frame_id;
  out.displayTimeRatio = core.display_time_ratio;
  out.numSlaves = core.num_slaves;
  out.beingAttacked = core.being_attacked;
  out.targetPosition = makeCameraCorrectionVector(core.target_position);
  out.adjustedTargetPosition = makeCameraCorrectionVector(core.adjusted_target_position);
  out.slave0 = makeCameraCorrectionSlave(core.slaves[0]);
  out.slave1 = makeCameraCorrectionSlave(core.slaves[1]);
  out.combinerValid = core.combiner.valid;
  out.combinerInterpolation = core.combiner.interpolation;
  out.combinerTrackingStatus = core.combiner.tracking_status;
  out.combinerTransform = makeCameraCorrectionVector(core.combiner.transform);
  return out;
}

static GOALPadCameraCorrectionEvent makeCameraCorrectionEvent(
    const goalpad::camera_correction_trace::Event &core) {
  GOALPadCameraCorrectionEvent out = {};
  out.valid = core.valid;
  out.reasonMask = core.reason_mask;
  out.hostTickID = core.host_tick_id;
  out.chainOrdinal = core.chain_ordinal;
  out.older = makeCameraCorrectionFrame(core.older);
  out.previous = makeCameraCorrectionFrame(core.previous);
  out.current = makeCameraCorrectionFrame(core.current);
  return out;
}

@interface GOALPadRenderSurface ()
@property(nonatomic, readwrite) NSString *lastError;
@end

@implementation GOALPadRenderSurface {
  CAMetalLayer *_layer;
  CGSize _drawableSize;
  int32_t _internalScale;
}

+ (GOALPadRenderSurface *)shared {
  static GOALPadRenderSurface *shared = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    shared = [[GOALPadRenderSurface alloc] init];
  });
  return shared;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _drawableSize = CGSizeZero;
    _internalScale = 2;
    self.lastError = @"";
  }
  return self;
}

- (BOOL)isRendererLinked {
  return goalpad::metal_host_is_running();
}

- (void)attachLayer:(CAMetalLayer *)layer {
  if (layer == nil) {
    _layer = nil;
    return;
  }
  layer.framebufferOnly = NO;
  goalpad::metal_host_attach_layer(layer);
  _layer = layer;
  self.lastError = @"";
}

- (void)setDrawableSize:(CGSize)size {
  if (size.width < 1 || size.height < 1) {
    return;
  }
  _drawableSize = size;
  _layer.drawableSize = size;
}

- (void)setInternalResolutionScale:(int32_t)scale {
  _internalScale = std::clamp(scale, (int32_t)1, kMaxInternalScale);
}

- (GOALPadSurfaceGeometry)geometry {
  GOALPadSurfaceGeometry geometry = {};
  geometry.drawableWidth = (int32_t)_drawableSize.width;
  geometry.drawableHeight = (int32_t)_drawableSize.height;
  geometry.internalWidth = kGameBaseWidth * _internalScale;
  geometry.internalHeight = kGameBaseHeight * _internalScale;

  // The largest rectangle of the game's own aspect that fits in the drawable. The present pass
  // centres this and clears the rest to black.
  if (geometry.drawableWidth > 0 && geometry.drawableHeight > 0) {
    const int64_t byWidth = (int64_t)geometry.drawableWidth * geometry.internalHeight;
    const int64_t byHeight = (int64_t)geometry.drawableHeight * geometry.internalWidth;
    if (byWidth <= byHeight) {
      geometry.drawRegionWidth = geometry.drawableWidth;
      geometry.drawRegionHeight =
          (int32_t)(byWidth / std::max(geometry.internalWidth, (int32_t)1));
    } else {
      geometry.drawRegionHeight = geometry.drawableHeight;
      geometry.drawRegionWidth =
          (int32_t)(byHeight / std::max(geometry.internalHeight, (int32_t)1));
    }
  }
  return geometry;
}

- (GOALPadRendererStats)stats {
  const auto core = goalpad::metal_host_stats();
  GOALPadRendererStats stats = {core.chains_sent,   core.chains_rendered,  core.chains_dropped,
                                core.frames_armed, core.frames_without_chain,
                                core.frames_with_multiple_chains, core.max_chains_per_frame,
                                core.drawables_acquired, core.drawable_misses,
                                core.late_present_submissions, core.last_host_tick_id,
                                core.last_chain_ordinal, core.last_engine_frame_id,
                                core.last_camera_fingerprint, (int32_t)core.last_camera_packets,
                                core.producer_camera_alternations,
                                core.last_camera_alternation_older_frame_id,
                                core.last_camera_alternation_previous_frame_id,
                                core.last_camera_alternation_current_frame_id,
                                core.last_camera_alternation_older_fingerprint,
                                core.last_camera_alternation_previous_fingerprint,
                                core.last_camera_alternation_current_fingerprint,
                                core.last_camera_alternation_host_tick_id,
                                core.last_camera_alternation_chain_ordinal,
                                core.last_camera_alternation_packet_fingerprint,
                                core.last_camera_alternation_live_mismatch_qwords,
                                core.last_camera_alternation_packet_mismatch_qwords,
                                core.last_camera_alternation_render_live_mismatch_qwords,
                                core.last_camera_alternation_render_packet_mismatch_qwords,
                                core.last_camera_older_to_previous_distance,
                                core.last_camera_previous_to_current_distance,
                                core.last_camera_older_to_current_distance,
                                (int32_t)core.last_live_camera_mismatches,
                                (int32_t)core.last_packet_camera_mismatches,
                                core.last_live_camera_mismatch_qwords,
                                core.last_packet_camera_mismatch_qwords,
                                core.live_camera_mismatches, core.packet_camera_mismatches,
                                core.submissions, core.presentations_completed,
                                core.presentation_drops, core.presentation_order_mismatches,
                                core.last_submission_id, core.last_presented_submission_id,
                                core.last_dropped_submission_id, core.last_drawable_id,
                                core.last_presented_drawable_id,
                                core.last_presented_engine_frame_id,
                                core.last_presented_host_tick_id,
                                core.last_presented_chain_ordinal,
                                core.last_requested_presentation_time,
                                core.last_actual_presentation_time,
                                core.texture_uploads,
                                (int32_t)core.levels_loaded, (int32_t)core.level_failures,
                                (int32_t)core.last_draw_calls, (int32_t)core.last_triangles,
                                (int32_t)core.merc_models, (int32_t)core.merc_draws,
                                (int32_t)core.merc_bone_vectors,
                                (int32_t)core.merc_missing_bone_slots,
                                (int32_t)core.merc_models_with_missing_bone_slots,
                                core.merc_missing_bone_slots_total,
                                core.merc_models_with_missing_bone_slots_total,
                                core.last_merc_missing_bone_engine_frame_id,
                                core.last_merc_missing_bone_host_tick_id,
                                core.last_merc_missing_bone_chain_ordinal,
                                (int32_t)core.last_merc_missing_bone_slots,
                                (int32_t)core.last_merc_models_with_missing_bone_slots,
                                (int32_t)core.merc_nonfinite_bone_matrices,
                                (int32_t)core.merc_degenerate_bone_matrices,
                                (int32_t)core.merc_incoherent_bone_sources,
                                (int32_t)core.merc_models_with_palette_health_issues,
                                core.merc_nonfinite_bone_matrices_total,
                                core.merc_degenerate_bone_matrices_total,
                                core.merc_incoherent_bone_sources_total,
                                core.merc_models_with_palette_health_issues_total,
                                core.last_merc_palette_health_engine_frame_id,
                                core.last_merc_palette_health_host_tick_id,
                                core.last_merc_palette_health_chain_ordinal,
                                core.last_merc_palette_health_issue_mask,
                                (int32_t)core.last_merc_palette_health_bone_slot,
                                core.last_merc_palette_health_model_name_hash,
                                core.last_merc_palette_health_matrix_hash,
                                core.last_merc_palette_health_axis_norm_x,
                                core.last_merc_palette_health_axis_norm_y,
                                core.last_merc_palette_health_axis_norm_z,
                                core.last_merc_palette_health_normalized_abs_determinant,
                                core.last_merc_palette_health_source_address,
                                core.last_merc_palette_health_source_base,
                                core.last_merc_palette_health_expected_source_base,
                                (int32_t)core.merc_eichar_transform_discontinuities,
                                core.merc_eichar_transform_discontinuities_total,
                                makeMercTransformEvent(
                                    core.first_merc_eichar_transform_discontinuity),
                                makeMercTransformEvent(
                                    core.last_merc_eichar_transform_discontinuity),
                                core.merc_bad_bone_pointers, core.merc_bad_draw_ranges,
                                core.camera_correction_events_total,
                                makeCameraCorrectionEvent(
                                    core.last_camera_correction_event)};
  return stats;
}

- (NSString *)levelsWanted {
  return @(goalpad::metal_host_stats().levels_wanted.c_str());
}

- (NSString *)levelsLoaded {
  return @(goalpad::metal_host_stats().levels_loaded_names.c_str());
}

- (BOOL)beginFrameAtTime:(CFTimeInterval)presentationTime {
  if (_layer == nil) {
    return NO;
  }
  const GOALPadSurfaceGeometry geometry = [self geometry];
  if (geometry.drawRegionWidth <= 0 || geometry.drawRegionHeight <= 0) {
    return NO;
  }

  goalpad::MetalHostFrame frame;
  frame.game_res_w = geometry.internalWidth;
  frame.game_res_h = geometry.internalHeight;
  frame.draw_region_w = geometry.drawRegionWidth;
  frame.draw_region_h = geometry.drawRegionHeight;
  frame.presentation_time = presentationTime;
  return goalpad::metal_host_begin_frame(_layer, frame);
}

- (BOOL)endFrame {
  return goalpad::metal_host_end_frame();
}

@end
