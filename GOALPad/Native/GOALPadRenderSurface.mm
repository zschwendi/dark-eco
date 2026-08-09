#import "GOALPadRuntimeBridge.h"

#include "GOALPadEngineSeams.h"
#include "GOALPadMetalHost.hpp"
#include "GOALPadPresentationGeometry.hpp"

#import <Metal/Metal.h>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>

/*!
 * @file GOALPadRenderSurface.mm
 * The presentation surface: the CAMetalLayer the game is drawn into, and the geometry its present
 * pass works in.
 *
 * The game renders into an offscreen target at its own internal resolution and a PCRTC-style
 * present pass draws that target into a centred, letterboxed region of the drawable. That is what
 * `MetalRenderer::encode_present_pass` in the OpenGOAL fork does. Classic preserves that exact
 * 4:3 contract. The opt-in Hor+ path widens both the internal target and GOAL's existing automatic
 * camera aspect to the drawable while retaining the target height.
 *
 * The renderer itself is driven by the begin/end frame pair in GOALPadMetalHost.mm. This file
 * decides only where the game frame goes on the screen.
 */

static const int32_t kMaxInternalScale = 4;

@interface GOALPadStereoRenderTarget ()
@property(nonatomic, readwrite) uint64_t viewID;
@property(nonatomic, readwrite) id<MTLTexture> colorTexture;
@property(nonatomic, readwrite) id<MTLTexture> depthTexture;
@property(nonatomic, readwrite) simd_float4x4 clipFromGameClip;
@end

@implementation GOALPadStereoRenderTarget

- (instancetype)initWithViewID:(uint64_t)viewID
                  colorTexture:(id<MTLTexture>)colorTexture
                  depthTexture:(id<MTLTexture>)depthTexture
              clipFromGameClip:(simd_float4x4)clipFromGameClip {
  self = [super init];
  if (self) {
    _viewID = viewID;
    _colorTexture = colorTexture;
    _depthTexture = depthTexture;
    _clipFromGameClip = clipFromGameClip;
  }
  return self;
}

@end

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
          core.previous_producer_output_hash,
          core.current_producer_output_hash,
          core.previous_renderer_output_hash,
          core.current_renderer_output_hash,
          core.older_input_root_hash,
          core.previous_input_root_hash,
          core.current_input_root_hash,
          core.older_camera_hash,
          core.previous_camera_hash,
          core.current_camera_hash,
          core.previous_bind_pose_hash,
          core.current_bind_pose_hash,
          core.input_older_to_previous_distance,
          core.input_previous_to_current_distance,
          core.input_older_to_current_distance,
          core.output_older_to_previous_distance,
          core.output_previous_to_current_distance,
          core.output_older_to_current_distance,
          core.previous_output_expected_distance,
          core.current_output_expected_distance,
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

static GOALPadMercPaletteHealthEvent makeMercPaletteHealthEvent(
    const goalpad::MetalHostMercPaletteHealthEvent &core) {
  return {core.engine_frame_id,
          core.host_tick_id,
          core.chain_ordinal,
          core.issue_mask,
          core.nonfinite_lane_mask,
          (int32_t)core.bone_slot,
          core.model_name_hash,
          core.matrix_hash,
          core.axis_norm_x,
          core.axis_norm_y,
          core.axis_norm_z,
          core.normalized_abs_determinant,
          core.source_address,
          core.source_base,
          core.expected_source_base};
}

static GOALPadTargetControlEvent makeTargetControlEvent(
    const goalpad::MetalHostTargetControlEvent &core) {
  return {core.host_tick_id,
          core.chain_ordinal,
          core.issue_mask,
          core.engine_frame_id,
          core.producer_serial,
          core.source_base,
          core.target_state_id,
          core.previous_target_attack_id,
          core.current_target_attack_id,
          core.button0_abs,
          core.button0_rel,
          core.left_x,
          core.left_y,
          core.stick_direction,
          core.stick_speed,
          core.pad_magnitude,
          core.intent_forward_x,
          core.intent_forward_z,
          core.desired_forward_x,
          core.desired_forward_z,
          core.control_forward_x,
          core.control_forward_z,
          core.render_forward_x,
          core.render_forward_z,
          core.root_forward_x,
          core.root_forward_z,
          core.intent_control_dot,
          core.control_render_dot,
          core.render_root_dot};
}

static GOALPadTargetControlVector4 makeTargetControlVector4(
    const goalpad::MetalHostTargetControlVector4 &core) {
  return {core.x, core.y, core.z, core.w};
}

static GOALPadTargetControlFacing makeTargetControlFacing(
    const goalpad::MetalHostTargetControlFacing &core) {
  return {core.valid, core.x, core.z};
}

static GOALPadTargetControlBasis makeTargetControlBasis(
    const goalpad::MetalHostTargetControlBasis &core) {
  return {core.valid,   core.axis0_x, core.axis0_y, core.axis0_z, core.axis1_x,
          core.axis1_y, core.axis1_z, core.axis2_x, core.axis2_y, core.axis2_z};
}

static GOALPadTargetControlDeformation makeTargetControlDeformation(
    const goalpad::MetalHostTargetControlDeformation &core) {
  return {core.valid,
          core.axis_norm_x,
          core.axis_norm_y,
          core.axis_norm_z,
          core.aspect,
          core.normalized_abs_determinant};
}

static GOALPadTargetControlRootAnchor makeTargetControlRootAnchor(
    const goalpad::MetalHostTargetControlRootAnchor &core) {
  return {core.valid,
          makeTargetControlDeformation(core.deformation),
          core.scale_x,
          core.scale_y,
          core.scale_z,
          core.scale_w_bits};
}

static GOALPadTargetPostFlagObservation makeTargetPostFlagObservation(
    const goalpad::MetalHostTargetPostFlagObservation &core) {
  return {core.valid,
          core.host_tick_id,
          core.chain_ordinal,
          core.engine_frame_id,
          core.sample_serial,
          core.target_address,
          core.raw_draw_status,
          core.target_attack_id,
          core.hidden};
}

static GOALPadTargetControlObservation makeTargetControlObservation(
    const goalpad::MetalHostTargetControlObservation &core) {
  return {core.valid,
          core.host_tick_id,
          core.chain_ordinal,
          core.engine_frame_id,
          (int32_t)core.probe_bone_slot,
          core.producer_serial,
          core.source_base,
          core.camera_hash,
          core.target_state_id,
          core.target_attack_id,
          core.button0_abs,
          core.button0_rel,
          core.left_x,
          core.left_y,
          core.stick_direction,
          core.stick_speed,
          core.pad_magnitude,
          makeTargetControlVector4(core.raw_dir_targ),
          makeTargetControlVector4(core.raw_quat_for_control),
          makeTargetControlVector4(core.raw_render_quat),
          makeTargetControlVector4(core.raw_turn_to_target),
          makeTargetControlFacing(core.intent_forward),
          makeTargetControlFacing(core.desired_forward),
          makeTargetControlFacing(core.control_forward),
          makeTargetControlFacing(core.render_forward),
          makeTargetControlFacing(core.root_forward),
          makeTargetControlBasis(core.camera_basis),
          makeTargetControlDeformation(core.input_root_deformation),
          makeTargetControlDeformation(core.output_deformation),
          makeTargetControlRootAnchor(core.root_anchor_1),
          makeTargetControlRootAnchor(core.root_anchor_2),
          makeTargetControlRootAnchor(core.root_anchor_3),
          core.node3_parent_scale_cancellation_selected,
          core.input_root_translation_x,
          core.input_root_translation_y,
          core.input_root_translation_z};
}

static GOALPadTargetControlTelemetry makeTargetControlTelemetry(
    const goalpad::MetalHostTargetControlTelemetry &core) {
  return {core.capture_attempts_total,
          core.valid_observations_total,
          core.last_capture_stage,
          core.last_capture_result,
          makeTargetControlObservation(core.last_observation),
          core.post_flag_samples_total,
          core.hidden_samples_total,
          core.hidden_transitions_total,
          core.post_flag_serial_gaps_total,
          core.unframed_post_flag_samples_total,
          makeTargetPostFlagObservation(core.last_post_flag_sample),
          makeTargetPostFlagObservation(core.last_hidden_post_flag_sample)};
}

static GOALPadCameraCorrectionVector makeCameraCorrectionVector(
    const goalpad::camera_correction_trace::Vector4 &core) {
  return {core.values[0], core.values[1], core.values[2], core.values[3]};
}

static GOALPadCameraCorrectionRotationAxes makeCameraCorrectionRotationAxes(
    const goalpad::camera_correction_trace::RotationAxes &core) {
  return {makeCameraCorrectionVector(core.axes[0]),
          makeCameraCorrectionVector(core.axes[1]),
          makeCameraCorrectionVector(core.axes[2])};
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
  out.maxAngleOffset = core.max_angle_offset;
  out.maxAngleCurrent = core.max_angle_current;
  out.transform = makeCameraCorrectionVector(core.transform);
  out.trackingInverseMatrix =
      makeCameraCorrectionRotationAxes(core.tracking_inverse_matrix);
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
  out.mathCameraObjectOffset = core.math_camera_object_offset;
  out.mathCameraTypeOffset = core.math_camera_type_offset;
  out.masterObjectOffset = core.master_object_offset;
  out.masterTypeOffset = core.master_type_offset;
  out.combinerObjectOffset = core.combiner_object_offset;
  out.combinerTypeOffset = core.combiner_type_offset;
  out.slave0PpointerOffset = core.slave_ppointer_offsets[0];
  out.slave0ObjectOffset = core.slave_object_offsets[0];
  out.slave0TypeOffset = core.slave_type_offsets[0];
  out.slave1PpointerOffset = core.slave_ppointer_offsets[1];
  out.slave1ObjectOffset = core.slave_object_offsets[1];
  out.slave1TypeOffset = core.slave_type_offsets[1];
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
  out.combinerInverseCameraRotation =
      makeCameraCorrectionRotationAxes(core.combiner.inverse_camera_rotation);
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

static GOALPadCameraCorrectionTailInfo makeCameraCorrectionTailInfo(
    const goalpad::camera_correction_trace::Tail &core) {
  return {core.valid, core.complete, (uint32_t)core.count,
          core.trigger_engine_frame_id, core.trigger_orientation_degrees};
}

static GOALPadCameraCorrectionTailFrame makeCameraCorrectionTailFrame(
    const goalpad::camera_correction_trace::TailFrame &core) {
  GOALPadCameraCorrectionTailFrame out = {};
  out.valid = core.camera.valid;
  out.hostTickID = core.host_tick_id;
  out.chainOrdinal = core.chain_ordinal;
  out.renderCameraFingerprint = core.render_camera_fingerprint;
  out.camera = makeCameraCorrectionFrame(core.camera);
  return out;
}

@interface GOALPadCameraCorrectionTailSnapshot (NativeTail)
- (instancetype)initWithNativeTail:(const goalpad::camera_correction_trace::Tail *)tail;
@end

@implementation GOALPadCameraCorrectionTailSnapshot

- (instancetype)initWithNativeTail:(const goalpad::camera_correction_trace::Tail *)tail {
  self = [super init];
  if (self) {
    _nativeTail = new goalpad::camera_correction_trace::Tail(*tail);
  }
  return self;
}

- (void)dealloc {
  delete static_cast<goalpad::camera_correction_trace::Tail *>(_nativeTail);
}

- (GOALPadCameraCorrectionTailInfo)info {
  const auto *tail = static_cast<const goalpad::camera_correction_trace::Tail *>(_nativeTail);
  return tail ? makeCameraCorrectionTailInfo(*tail) : GOALPadCameraCorrectionTailInfo{};
}

- (GOALPadCameraCorrectionTailFrame)frameAtIndex:(uint32_t)index {
  const auto *tail = static_cast<const goalpad::camera_correction_trace::Tail *>(_nativeTail);
  if (!tail || index >= tail->count) {
    return {};
  }
  return makeCameraCorrectionTailFrame(tail->frames[index]);
}

@end

@interface GOALPadRenderSurface ()
@property(nonatomic, readwrite) NSString *lastError;
@end

@implementation GOALPadRenderSurface {
  CAMetalLayer *_layer;
  CGSize _drawableSize;
  int32_t _internalScale;
  BOOL _horizontalPlusEnabled;
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
    _horizontalPlusEnabled = NO;
    self.lastError = @"";
  }
  return self;
}

- (BOOL)isRendererLinked {
  return goalpad::metal_host_is_running();
}

- (void)attachLayer:(CAMetalLayer *)layer {
  if (layer == nil) {
    // Scene deactivation and view removal are both idempotent. Close any armed tick before
    // dropping the only retained presentation-layer reference.
    goalpad::metal_host_end_frame();
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
  [self updatePortableDisplaySize];
}

- (void)setInternalResolutionScale:(int32_t)scale {
  _internalScale = std::clamp(scale, (int32_t)1, kMaxInternalScale);
}

- (void)setHorizontalPlusEnabled:(BOOL)enabled {
  _horizontalPlusEnabled = enabled;
  [self updatePortableDisplaySize];
}

- (void)updatePortableDisplaySize {
#if GOALPAD_HAVE_SOUND_SEAM
  const auto geometry = goalpad::presentation_geometry(
      (int32_t)_drawableSize.width, (int32_t)_drawableSize.height, _internalScale,
      _horizontalPlusEnabled);
  goal_kernel_core_set_portable_display_enabled(_horizontalPlusEnabled);
  goal_kernel_core_set_portable_display_size(geometry.game_display_width,
                                             geometry.game_display_height);
#endif
}

- (GOALPadSurfaceGeometry)geometry {
  const auto calculated = goalpad::presentation_geometry(
      (int32_t)_drawableSize.width, (int32_t)_drawableSize.height, _internalScale,
      _horizontalPlusEnabled);
  GOALPadSurfaceGeometry geometry = {};
  geometry.drawableWidth = calculated.drawable_width;
  geometry.drawableHeight = calculated.drawable_height;
  geometry.internalWidth = calculated.internal_width;
  geometry.internalHeight = calculated.internal_height;
  geometry.drawRegionWidth = calculated.draw_region_width;
  geometry.drawRegionHeight = calculated.draw_region_height;
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
                                core.render_camera_alternations,
                                core.last_render_camera_alternation_older_frame_id,
                                core.last_render_camera_alternation_previous_frame_id,
                                core.last_render_camera_alternation_current_frame_id,
                                core.last_render_camera_alternation_older_fingerprint,
                                core.last_render_camera_alternation_previous_fingerprint,
                                core.last_render_camera_alternation_current_fingerprint,
                                core.last_render_camera_alternation_host_tick_id,
                                core.last_render_camera_alternation_chain_ordinal,
                                core.last_render_camera_alternation_packet_fingerprint,
                                core.last_render_camera_alternation_live_mismatch_qwords,
                                core.last_render_camera_alternation_packet_mismatch_qwords,
                                core.last_render_camera_older_to_previous_distance,
                                core.last_render_camera_previous_to_current_distance,
                                core.last_render_camera_older_to_current_distance,
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
                                core.last_merc_palette_health_nonfinite_lane_mask,
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
                                (int32_t)core.merc_eichar_provenance_events,
                                core.merc_eichar_provenance_events_total,
                                makeMercTransformEvent(
                                    core.first_merc_eichar_provenance_event),
                                makeMercTransformEvent(
                                    core.last_merc_eichar_provenance_event),
                                (int32_t)core.merc_eichar_output_composition_mismatches,
                                core.merc_eichar_output_composition_mismatches_total,
                                makeMercTransformEvent(
                                    core.first_merc_eichar_output_composition_mismatch),
                                makeMercTransformEvent(
                                    core.last_merc_eichar_output_composition_mismatch),
                                (int32_t)core.merc_eichar_palette_health_issues,
                                core.merc_eichar_palette_health_issues_total,
                                makeMercPaletteHealthEvent(
                                    core.first_merc_eichar_palette_health_event),
                                makeMercPaletteHealthEvent(
                                    core.last_merc_eichar_palette_health_event),
                                core.merc_bad_bone_pointers, core.merc_bad_draw_ranges,
                                core.camera_correction_events_total,
                                makeCameraCorrectionEvent(
                                    core.last_camera_correction_event),
                                (int32_t)core.merc_eichar_target_control_events,
                                core.merc_eichar_target_control_events_total,
                                (int32_t)core.merc_eichar_target_control_divergences,
                                core.merc_eichar_target_control_divergences_total,
                                (int32_t)core.merc_eichar_target_control_attack_boundaries,
                                core.merc_eichar_target_control_attack_boundaries_total,
                                makeTargetControlEvent(
                                    core.first_merc_eichar_target_control_event),
                                makeTargetControlEvent(
                                    core.last_merc_eichar_target_control_event),
                                core.jak1_tie_envmap_second_pass_enabled,
                                (int32_t)core.tie_envmap_second_pass_draws,
                                core.tie_envmap_second_pass_draws_total,
                                core.merc_eichar_weighted_profiled_base_draws,
                                core.merc_eichar_weighted_profiled_vertices,
                                core.merc_eichar_weighted_multi_bone_vertices,
                                core.merc_eichar_weighted_affected_vertices,
                                core.merc_eichar_weighted_static_multi_bone_vertices,
                                core.merc_eichar_weighted_static_affected_vertices,
                                core.merc_eichar_weighted_modified_multi_bone_vertices,
                                core.merc_eichar_weighted_modified_affected_vertices,
                                core.merc_eichar_weighted_tuple_groups,
                                core.merc_eichar_weighted_affected_tuple_groups,
                                core.merc_eichar_weighted_valid_basis_groups,
                                core.merc_eichar_weighted_invalid_basis_groups,
                                core.merc_eichar_weighted_affected_draws,
                                core.merc_eichar_weighted_affected_effects,
                                core.merc_eichar_weighted_profile_tuple_mismatches,
                                core.merc_eichar_weighted_profile_capacity_drops,
                                core.merc_eichar_weighted_maximum_axis_ratio,
                                core.merc_eichar_weighted_minimum_normalized_abs_determinant,
                                core.merc_eichar_weighted_coverage,
                                core.merc_eichar_packets,
                                core.merc_eichar_unique_source_bases,
                                core.merc_eichar_repeated_packets,
                                core.merc_eichar_repeated_packets_same_palette,
                                core.merc_eichar_repeated_packets_conflicting_palette,
                                core.merc_eichar_actual_base_draws,
                                core.merc_eichar_unique_base_draws,
                                core.merc_eichar_repeated_base_draws,
                                core.merc_eichar_repeated_base_draws_same_palette,
                                core.merc_eichar_repeated_base_draws_conflicting_palette,
                                core.merc_eichar_trace_capacity_drops,
                                core.merc_eichar_bound_palette_hash_mismatches,
                                core.merc_eichar_weighted_skin_evidence_total,
                                core.merc_eichar_weighted_issue_mask,
                                core.last_merc_eichar_weighted_skin_engine_frame_id,
                                core.last_merc_eichar_weighted_skin_host_tick_id,
                                core.last_merc_eichar_weighted_skin_chain_ordinal};
  stats.jak1ShadowOutputEnabled = core.jak1_shadow_output_enabled;
  return stats;
}

- (GOALPadCameraCorrectionTailInfo)cameraCorrectionTailInfo {
  return makeCameraCorrectionTailInfo(goalpad::metal_host_camera_correction_tail());
}

- (GOALPadCameraCorrectionTailSnapshot *)cameraCorrectionTailSnapshot {
  const auto &tail = goalpad::metal_host_camera_correction_tail();
  return [[GOALPadCameraCorrectionTailSnapshot alloc] initWithNativeTail:&tail];
}

- (GOALPadTargetControlTelemetry)targetControlTelemetry {
  return makeTargetControlTelemetry(goalpad::metal_host_target_control_telemetry());
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

- (BOOL)beginStereoFrameAtTime:(CFTimeInterval)presentationTime
                          size:(CGSize)size
                          left:(GOALPadStereoRenderTarget *)left
                         right:(GOALPadStereoRenderTarget *)right {
  if (size.width < 1 || size.height < 1 || !std::isfinite(size.width) ||
      !std::isfinite(size.height) || size.width > std::numeric_limits<int>::max() ||
      size.height > std::numeric_limits<int>::max()) {
    self.lastError = @"The stereoscopic render size is invalid.";
    return NO;
  }

  goalpad::MetalHostFrame frame;
  frame.game_res_w = (int)size.width;
  frame.game_res_h = (int)size.height;
  frame.draw_region_w = frame.game_res_w;
  frame.draw_region_h = frame.game_res_h;
  frame.presentation_time = presentationTime;

  goalpad::MetalHostStereoView leftView;
  leftView.view_id = left.viewID;
  leftView.color_texture = left.colorTexture;
  leftView.depth_texture = left.depthTexture;
  const simd_float4x4 leftTransform = left.clipFromGameClip;
  memcpy(leftView.clip_from_game_clip.data(), &leftTransform, sizeof(leftTransform));

  goalpad::MetalHostStereoView rightView;
  rightView.view_id = right.viewID;
  rightView.color_texture = right.colorTexture;
  rightView.depth_texture = right.depthTexture;
  const simd_float4x4 rightTransform = right.clipFromGameClip;
  memcpy(rightView.clip_from_game_clip.data(), &rightTransform, sizeof(rightTransform));

  const BOOL began = goalpad::metal_host_begin_stereo_frame(frame, leftView, rightView);
  self.lastError = began ? @"" : @"The stereoscopic render targets were rejected.";
  return began;
}

- (BOOL)endFrame {
  return goalpad::metal_host_end_frame();
}

- (GOALPadStereoFrameCompletion)endStereoFrame {
  switch (goalpad::metal_host_end_stereo_frame()) {
    case goalpad::MetalHostStereoFrameCompletion::skipped:
      self.lastError = @"";
      return GOALPadStereoFrameCompletionSkipped;
    case goalpad::MetalHostStereoFrameCompletion::completed:
      self.lastError = @"";
      return GOALPadStereoFrameCompletionCompleted;
    case goalpad::MetalHostStereoFrameCompletion::failed:
      self.lastError = @"The stereoscopic frame did not complete.";
      return GOALPadStereoFrameCompletionFailed;
  }
}

@end
