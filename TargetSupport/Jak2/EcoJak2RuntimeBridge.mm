#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <mutex>
#include <string>
#include <vector>

#include "GOALPadPresentationGeometry.hpp"
#import "GOALPadRuntimeBridge.h"

#include "game/graphics/pipelines/metal/metal_jak2_host_bridge.h"
#include "game/kernel/core/jak2_runtime.h"
#include "game/kernel/core/kernel_game.h"
#include "game/kernel/core/pad.h"
#include "game/kernel/core/sound_rpc_jak2.h"

#include "Jak2DiagnosticCadence.hpp"

// kmemcard.h's OpenGOAL Ptr template conflicts with Apple's Ptr typedef in Objective-C++.
std::uint64_t kmemcard_successful_save_generation();

static_assert((uint32_t)GOALPadButtonSelect == (uint32_t)GOAL_PAD_SELECT, "pad bit drift");
static_assert((uint32_t)GOALPadButtonL3 == (uint32_t)GOAL_PAD_L3, "pad bit drift");
static_assert((uint32_t)GOALPadButtonR3 == (uint32_t)GOAL_PAD_R3, "pad bit drift");
static_assert((uint32_t)GOALPadButtonStart == (uint32_t)GOAL_PAD_START, "pad bit drift");
static_assert((uint32_t)GOALPadButtonUp == (uint32_t)GOAL_PAD_UP, "pad bit drift");
static_assert((uint32_t)GOALPadButtonRight == (uint32_t)GOAL_PAD_RIGHT, "pad bit drift");
static_assert((uint32_t)GOALPadButtonDown == (uint32_t)GOAL_PAD_DOWN, "pad bit drift");
static_assert((uint32_t)GOALPadButtonLeft == (uint32_t)GOAL_PAD_LEFT, "pad bit drift");
static_assert((uint32_t)GOALPadButtonL2 == (uint32_t)GOAL_PAD_L2, "pad bit drift");
static_assert((uint32_t)GOALPadButtonR2 == (uint32_t)GOAL_PAD_R2, "pad bit drift");
static_assert((uint32_t)GOALPadButtonL1 == (uint32_t)GOAL_PAD_L1, "pad bit drift");
static_assert((uint32_t)GOALPadButtonR1 == (uint32_t)GOAL_PAD_R1, "pad bit drift");
static_assert((uint32_t)GOALPadButtonTriangle == (uint32_t)GOAL_PAD_TRIANGLE, "pad bit drift");
static_assert((uint32_t)GOALPadButtonCircle == (uint32_t)GOAL_PAD_CIRCLE, "pad bit drift");
static_assert((uint32_t)GOALPadButtonCross == (uint32_t)GOAL_PAD_X, "pad bit drift");
static_assert((uint32_t)GOALPadButtonSquare == (uint32_t)GOAL_PAD_SQUARE, "pad bit drift");
static_assert(GOALPadAnalogNeutral == GOAL_PAD_ANALOG_NEUTRAL, "analog neutral drift");
static_assert(GOALPadPortCount == GOAL_PAD_PORTS, "port count drift");
static_assert(sizeof(goal_jak2_progress_menu_semantic_snapshot) == 16,
              "Jak II progress semantic ABI drift");
static_assert(sizeof(goal_jak2_player_context_snapshot) == 8,
              "Jak II player context ABI drift");
static_assert(sizeof(goal_jak2_face_prompt_touch_snapshot) == 12,
              "Jak II face prompt touch ABI drift");
static_assert((int32_t)GOALPadJak2TraversalStateUnknown ==
                  GOAL_JAK2_PLAYER_TRAVERSAL_UNKNOWN,
              "Jak II unknown traversal drift");
static_assert((int32_t)GOALPadJak2TraversalStateOnFoot ==
                  GOAL_JAK2_PLAYER_TRAVERSAL_ON_FOOT,
              "Jak II on-foot traversal drift");
static_assert((int32_t)GOALPadJak2TraversalStateJetboard ==
                  GOAL_JAK2_PLAYER_TRAVERSAL_JETBOARD,
              "Jak II jetboard traversal drift");
static_assert((int32_t)GOALPadJak2TraversalStateVehicleTransition ==
                  GOAL_JAK2_PLAYER_TRAVERSAL_VEHICLE_TRANSITION,
              "Jak II vehicle-transition traversal drift");
static_assert((int32_t)GOALPadJak2TraversalStateVehicleRiding ==
                  GOAL_JAK2_PLAYER_TRAVERSAL_VEHICLE_RIDING,
              "Jak II vehicle-riding traversal drift");
static_assert((int32_t)GOALPadLookAroundStateUnknown == GOAL_JAK2_PLAYER_LOOK_UNKNOWN,
              "Jak II unknown look-state drift");
static_assert((int32_t)GOALPadLookAroundStateNormal == GOAL_JAK2_PLAYER_LOOK_NORMAL,
              "Jak II normal look-state drift");
static_assert((int32_t)GOALPadLookAroundStateFirstPerson == GOAL_JAK2_PLAYER_LOOK_AROUND,
              "Jak II look-around state drift");
static_assert((int32_t)GOALPadJak2ProgressMenuPhaseSelectSaveTitle ==
                  GOAL_JAK2_PROGRESS_MENU_PHASE_SELECT_SAVE_TITLE,
              "Jak II progress phase drift");
static_assert((int32_t)GOALPadJak2ProgressMenuPhaseNoMemoryCard ==
                  GOAL_JAK2_PROGRESS_MENU_PHASE_NO_MEMORY_CARD,
              "Jak II progress phase drift");
static_assert((int32_t)GOALPadJak2ProgressMenuPhaseCreateGame ==
                  GOAL_JAK2_PROGRESS_MENU_PHASE_CREATE_GAME,
              "Jak II progress phase drift");
static_assert((int32_t)GOALPadJak2ProgressMenuPhaseCreating ==
                  GOAL_JAK2_PROGRESS_MENU_PHASE_CREATING,
              "Jak II progress phase drift");
static_assert((int32_t)GOALPadJak2ProgressMenuPhaseSaving ==
                  GOAL_JAK2_PROGRESS_MENU_PHASE_SAVING,
              "Jak II progress phase drift");
static_assert((int32_t)GOALPadJak2ProgressMenuPhaseExistingSaveOverwrite ==
                  GOAL_JAK2_PROGRESS_MENU_PHASE_ALREADY_EXISTS,
              "Jak II progress phase drift");
static_assert((int32_t)GOALPadJak2ProgressMenuPhaseSaveIconInformation ==
                  GOAL_JAK2_PROGRESS_MENU_PHASE_ICON_INFO,
              "Jak II progress phase drift");
static_assert((int32_t)GOALPadJak2ProgressMenuPhaseSelectLoad ==
                  GOAL_JAK2_PROGRESS_MENU_PHASE_SELECT_LOAD,
              "Jak II progress phase drift");
static_assert((int32_t)GOALPadJak2ProgressMenuPhaseSelectSave ==
                  GOAL_JAK2_PROGRESS_MENU_PHASE_SELECT_SAVE,
              "Jak II progress phase drift");
static_assert((int32_t)GOALPadJak2ProgressMenuPhaseLoading ==
                  GOAL_JAK2_PROGRESS_MENU_PHASE_LOADING,
              "Jak II progress phase drift");
static_assert((uint32_t)GOALPadJak2ProgressMenuActionUp ==
                  GOAL_JAK2_PROGRESS_MENU_ACTION_UP,
              "Jak II progress action drift");
static_assert((uint32_t)GOALPadJak2ProgressMenuActionDown ==
                  GOAL_JAK2_PROGRESS_MENU_ACTION_DOWN,
              "Jak II progress action drift");
static_assert((uint32_t)GOALPadJak2ProgressMenuActionLeft ==
                  GOAL_JAK2_PROGRESS_MENU_ACTION_LEFT,
              "Jak II progress action drift");
static_assert((uint32_t)GOALPadJak2ProgressMenuActionRight ==
                  GOAL_JAK2_PROGRESS_MENU_ACTION_RIGHT,
              "Jak II progress action drift");
static_assert((uint32_t)GOALPadJak2ProgressMenuActionConfirm ==
                  GOAL_JAK2_PROGRESS_MENU_ACTION_CONFIRM,
              "Jak II progress action drift");
static_assert((uint32_t)GOALPadJak2ProgressMenuActionBack ==
                  GOAL_JAK2_PROGRESS_MENU_ACTION_BACK,
              "Jak II progress action drift");

namespace {

enum class SessionState {
  Idle,
  Prepared,
  Booting,
  Running,
  Exited,
  Failed,
  Stopping,
};

std::mutex g_mutex;
std::condition_variable g_boot_finished;
SessionState g_state = SessionState::Idle;
CAMetalLayer* g_attached_layer = nil;
CAMetalLayer* g_host_layer = nil;
NSString* g_data_directory = @"";
NSString* g_saves_directory = @"";
NSString* g_last_error = @"";
goal_jak2_metal_host* g_metal_host = nullptr;
goal_jak2_runtime_metrics g_runtime_metrics = {};
goal_jak2_metal_host_metrics g_metal_metrics = {};
NSInteger g_target_frame_rate = 60;
CGSize g_drawable_size = CGSizeZero;
bool g_horizontal_plus_enabled = false;
bool g_frame_armed = false;
uint64_t g_frame_baseline_chains = 0;
uint64_t g_frame_baseline_drawables = 0;
uint64_t g_frame_baseline_submissions = 0;
uint64_t g_frames_armed = 0;
uint64_t g_frames_without_chain = 0;
uint64_t g_frames_with_multiple_chains = 0;
uint64_t g_max_chains_per_frame = 0;
bool g_shadow_bucket195_capture_written = false;
bool g_shadow195_frame_capture_logged = false;
goalpad::jak2::DiagnosticCadence g_diagnostic_cadence;

NSString* string_from_utf8(const char* value) {
  if (!value || !value[0]) {
    return @"";
  }
  NSString* result = [NSString stringWithUTF8String:value];
  return result ?: @"";
}

NSString* architecture_name() {
#if defined(__arm64__)
  return @"arm64";
#elif defined(__x86_64__)
  return @"x86_64";
#else
  return @"unknown";
#endif
}

int32_t clamped_int32(uint64_t value) {
  return static_cast<int32_t>(
      std::min<uint64_t>(value, static_cast<uint64_t>(std::numeric_limits<int32_t>::max())));
}

bool bridge_session_is_live(SessionState state) {
  return state == SessionState::Prepared || state == SessionState::Booting ||
         state == SessionState::Running;
}

bool level_list_contains(const char* levels, const char* expected) {
  if (!levels || !expected || !expected[0]) {
    return false;
  }
  const size_t expected_length = std::strlen(expected);
  for (const char* candidate = levels; candidate && candidate[0];) {
    const char* separator = std::strchr(candidate, '+');
    const size_t candidate_length =
        separator ? static_cast<size_t>(separator - candidate) : std::strlen(candidate);
    if (candidate_length == expected_length &&
        std::strncmp(candidate, expected, expected_length) == 0) {
      return true;
    }
    candidate = separator ? separator + 1 : nullptr;
  }
  return false;
}

bool copy_runtime_metrics_locked() {
  goal_jak2_runtime_metrics metrics = {};
  if (goal_jak2_runtime_get_metrics(&metrics) != GOAL_JAK2_RUNTIME_OK) {
    return false;
  }
  g_runtime_metrics = metrics;
  return true;
}

bool copy_metal_metrics_locked() {
  if (!g_metal_host) {
    g_metal_metrics = {};
    return false;
  }
  goal_jak2_metal_host_metrics metrics = {};
  if (!goal_jak2_metal_host_get_metrics(g_metal_host, &metrics)) {
    return false;
  }
  g_metal_metrics = metrics;
  return true;
}

goalpad::PresentationGeometry presentation_geometry_locked() {
  return goalpad::presentation_geometry(static_cast<int32_t>(g_drawable_size.width),
                                        static_cast<int32_t>(g_drawable_size.height), 1,
                                        g_horizontal_plus_enabled);
}

void update_portable_display_locked(const goalpad::PresentationGeometry& geometry) {
  const bool has_drawable = geometry.drawable_width > 0 && geometry.drawable_height > 0;
  goal_kernel_core_set_portable_display_enabled(has_drawable);
  goal_kernel_core_set_portable_display_size(geometry.game_display_width,
                                             geometry.game_display_height);
}

bool update_metal_presentation_geometry(goal_jak2_metal_host* host,
                                        const goalpad::PresentationGeometry& geometry) {
  if (!host || geometry.internal_width <= 0 || geometry.internal_height <= 0 ||
      geometry.draw_region_width <= 0 || geometry.draw_region_height <= 0) {
    return false;
  }
  const goal_jak2_metal_presentation_geometry metal_geometry = {
      static_cast<uint32_t>(geometry.internal_width),
      static_cast<uint32_t>(geometry.internal_height),
      static_cast<uint32_t>(geometry.draw_region_width),
      static_cast<uint32_t>(geometry.draw_region_height),
  };
  return goal_jak2_metal_host_set_presentation_geometry(host, &metal_geometry) != 0;
}

bool should_log_jak2_diagnostics(uint64_t tick) {
  const char* preview_scene = std::getenv("GOALPAD_JAK2_DEBUG_PREVIEW_SCENE");
  const bool preview_active = preview_scene && preview_scene[0];
  return g_diagnostic_cadence.should_log(tick, preview_active);
}

bool environment_is_exact_one(const char* name) {
  const char* value = name ? std::getenv(name) : nullptr;
  return value && std::strcmp(value, "1") == 0;
}

bool read_positive_u64_environment(const char* name, uint64_t* result) {
  if (!name || !result) {
    return false;
  }
  const char* value = std::getenv(name);
  if (!value || !value[0]) {
    return false;
  }
  uint64_t parsed = 0;
  for (const char* cursor = value; *cursor; ++cursor) {
    if (*cursor < '0' || *cursor > '9') {
      return false;
    }
    const uint64_t digit = static_cast<uint64_t>(*cursor - '0');
    if (parsed > (std::numeric_limits<uint64_t>::max() - digit) / 10) {
      return false;
    }
    parsed = parsed * 10 + digit;
  }
  if (!parsed) {
    return false;
  }
  *result = parsed;
  return true;
}

void write_shadow_bucket195_capture_locked() {
  if (g_shadow_bucket195_capture_written || !g_metal_host ||
      !environment_is_exact_one("GOALPAD_JAK2_DEBUG_CAPTURE_SHADOW195")) {
    return;
  }

  uint64_t required_size = 0;
  uint64_t fingerprint = 0;
  constexpr uint64_t kMaximumCaptureBytes = 1 << 20;
  if (!goal_jak2_metal_host_copy_shadow_bucket195_plan_capture(
          g_metal_host, nullptr, 0, &required_size, &fingerprint) || !required_size ||
      required_size > kMaximumCaptureBytes) {
    return;
  }

  std::vector<uint8_t> bytes(required_size);
  uint64_t copied_size = 0;
  uint64_t copied_fingerprint = 0;
  if (!goal_jak2_metal_host_copy_shadow_bucket195_plan_capture(
          g_metal_host, bytes.data(), bytes.size(), &copied_size, &copied_fingerprint) ||
      copied_size != bytes.size() || copied_fingerprint != fingerprint) {
    return;
  }

  NSFileManager* files = [NSFileManager defaultManager];
  NSError* error = nil;
  NSURL* caches = [files URLForDirectory:NSCachesDirectory
                                inDomain:NSUserDomainMask
                       appropriateForURL:nil
                                  create:YES
                                   error:&error];
  if (!caches) {
    NSLog(@"GOALPAD_JAK2_SHADOW195_CAPTURE_STATE tick=%llu status=1 size=%llu "
           "fingerprint=%016llx error=%lld",
          static_cast<unsigned long long>(g_runtime_metrics.ticks),
          static_cast<unsigned long long>(required_size),
          static_cast<unsigned long long>(fingerprint), static_cast<long long>(error.code));
    return;
  }
  NSURL* directory = [caches URLByAppendingPathComponent:@"GOALPad/Jak2Diagnostics"
                                             isDirectory:YES];
  error = nil;
  if (![files createDirectoryAtURL:directory
       withIntermediateDirectories:YES
                        attributes:nil
                             error:&error]) {
    NSLog(@"GOALPAD_JAK2_SHADOW195_CAPTURE_STATE tick=%llu status=2 size=%llu "
           "fingerprint=%016llx error=%lld",
          static_cast<unsigned long long>(g_runtime_metrics.ticks),
          static_cast<unsigned long long>(required_size),
          static_cast<unsigned long long>(fingerprint), static_cast<long long>(error.code));
    return;
  }
  NSURL* output = [directory URLByAppendingPathComponent:@"shadow195-v1.j2s195p"
                                              isDirectory:NO];
  NSData* data = [NSData dataWithBytes:bytes.data() length:bytes.size()];
  error = nil;
  if (![data writeToURL:output options:NSDataWritingAtomic error:&error]) {
    NSLog(@"GOALPAD_JAK2_SHADOW195_CAPTURE_STATE tick=%llu status=3 size=%llu "
           "fingerprint=%016llx error=%lld",
          static_cast<unsigned long long>(g_runtime_metrics.ticks),
          static_cast<unsigned long long>(required_size),
          static_cast<unsigned long long>(fingerprint), static_cast<long long>(error.code));
    return;
  }
  g_shadow_bucket195_capture_written = true;
  NSLog(@"GOALPAD_JAK2_SHADOW195_CAPTURE_STATE tick=%llu status=0 size=%llu "
         "fingerprint=%016llx error=0",
        static_cast<unsigned long long>(g_runtime_metrics.ticks),
        static_cast<unsigned long long>(required_size),
        static_cast<unsigned long long>(fingerprint));
}

void log_shadow195_frame_capture_locked() {
  if (g_shadow195_frame_capture_logged || !g_metal_host) {
    return;
  }
  goal_jak2_shadow195_frame_capture_result capture = {};
  if (!goal_jak2_metal_host_get_shadow195_frame_capture(g_metal_host, &capture) ||
      (capture.status != GOAL_JAK2_SHADOW195_CAPTURE_COMPLETE &&
       capture.status != GOAL_JAK2_SHADOW195_CAPTURE_FAILED)) {
    return;
  }

  NSLog(@"GOALPAD_JAK2_SHADOW195_FRAME_STATE tick=%llu status=%u failure=%u "
         "selector=%u/%llu/%llu/%016llx selected=%llu/%llu/%llu/%016llx",
        static_cast<unsigned long long>(g_runtime_metrics.ticks), capture.status,
        capture.failure_reason, capture.selector.match,
        static_cast<unsigned long long>(capture.selector.host_tick_id),
        static_cast<unsigned long long>(capture.selector.engine_frame_id),
        static_cast<unsigned long long>(capture.selector.plan_fingerprint),
        static_cast<unsigned long long>(capture.selected_host_tick_id),
        static_cast<unsigned long long>(capture.selected_chain_ordinal),
        static_cast<unsigned long long>(capture.selected_engine_frame_id),
        static_cast<unsigned long long>(capture.selected_plan_fingerprint));
  NSLog(@"GOALPAD_JAK2_SHADOW195_FRAME_TARGET tick=%llu view=%llu external=%u "
         "size=%u/%u formats=%u/%u/%u slices=%u/%u/%u type=%u storage=%u "
         "samples=%u array=%u mips=%u load=%u/%u/%u store=%u/%u/%u "
         "viewport=%.3f/%.3f/%.3f/%.3f/%.6f/%.6f scissor=%u/%u/%u/%u/%u "
         "scale=%.6f/%.6f",
        static_cast<unsigned long long>(g_runtime_metrics.ticks),
        static_cast<unsigned long long>(capture.target_view_id), capture.target_external,
        capture.target_width, capture.target_height, capture.target_pixel_format,
        capture.target_depth_pixel_format, capture.target_stencil_pixel_format,
        capture.target_color_slice, capture.target_depth_slice, capture.target_stencil_slice,
        capture.target_texture_type, capture.target_storage_mode, capture.target_sample_count,
        capture.target_array_length, capture.target_mipmap_level_count,
        capture.target_color_load_action, capture.target_depth_load_action,
        capture.target_stencil_load_action, capture.target_color_store_action,
        capture.target_depth_store_action, capture.target_stencil_store_action,
        capture.target_viewport_origin_x, capture.target_viewport_origin_y,
        capture.target_viewport_width, capture.target_viewport_height,
        capture.target_viewport_znear, capture.target_viewport_zfar, capture.target_scissor_x,
        capture.target_scissor_y, capture.target_scissor_width, capture.target_scissor_height,
        capture.target_scissor_explicit, capture.target_render_scale_x,
        capture.target_render_scale_y);
  NSLog(@"GOALPAD_JAK2_SHADOW195_FRAME_PIXELS tick=%llu before=%016llx/%llu "
         "after=%016llx/%llu changed=%llu bounds=%u/%u/%u/%u/%u "
         "depth=%016llx/%016llx/%llu finite=%llu/%llu nonfinite=%llu/%llu "
         "range=%u/%.9g/%.9g/%u/%.9g/%.9g depth-bounds=%u/%u/%u/%u/%u",
        static_cast<unsigned long long>(g_runtime_metrics.ticks),
        static_cast<unsigned long long>(capture.before_hash),
        static_cast<unsigned long long>(capture.before_nonzero_pixels),
        static_cast<unsigned long long>(capture.after_hash),
        static_cast<unsigned long long>(capture.after_nonzero_pixels),
        static_cast<unsigned long long>(capture.changed_pixels), capture.changed_bounds.valid,
        capture.changed_bounds.min_x, capture.changed_bounds.min_y,
        capture.changed_bounds.max_x_exclusive, capture.changed_bounds.max_y_exclusive,
        static_cast<unsigned long long>(capture.before_depth.hash),
        static_cast<unsigned long long>(capture.after_depth.hash),
        static_cast<unsigned long long>(capture.changed_depth_pixels),
        static_cast<unsigned long long>(capture.before_depth.finite_pixels),
        static_cast<unsigned long long>(capture.after_depth.finite_pixels),
        static_cast<unsigned long long>(capture.before_depth.nonfinite_pixels),
        static_cast<unsigned long long>(capture.after_depth.nonfinite_pixels),
        capture.before_depth.finite_range_valid, capture.before_depth.min_finite,
        capture.before_depth.max_finite, capture.after_depth.finite_range_valid,
        capture.after_depth.min_finite, capture.after_depth.max_finite,
        capture.changed_depth_bounds.valid, capture.changed_depth_bounds.min_x,
        capture.changed_depth_bounds.min_y, capture.changed_depth_bounds.max_x_exclusive,
        capture.changed_depth_bounds.max_y_exclusive);
  NSLog(@"GOALPAD_JAK2_SHADOW195_FRAME_STENCIL tick=%llu "
         "hash=%016llx/%016llx/%016llx nonzero=%llu/%llu/%llu "
         "volume-changed=%llu bounds=%u/%u/%u/%u/%u final-changed=%llu "
         "final-bounds=%u/%u/%u/%u/%u renderer=%llu/%u/%u/%u/%u/%u/%u/%u/%u/%u/%u/%u/%u "
         "errors=%u/%u/%u/%u/%u boundary=%u",
        static_cast<unsigned long long>(g_runtime_metrics.ticks),
        static_cast<unsigned long long>(capture.before_stencil.hash),
        static_cast<unsigned long long>(capture.volume_stencil.hash),
        static_cast<unsigned long long>(capture.after_stencil.hash),
        static_cast<unsigned long long>(capture.before_stencil.nonzero_pixels),
        static_cast<unsigned long long>(capture.volume_stencil.nonzero_pixels),
        static_cast<unsigned long long>(capture.after_stencil.nonzero_pixels),
        static_cast<unsigned long long>(capture.volume_stencil_changed_pixels),
        capture.volume_stencil_changed_bounds.valid, capture.volume_stencil_changed_bounds.min_x,
        capture.volume_stencil_changed_bounds.min_y,
        capture.volume_stencil_changed_bounds.max_x_exclusive,
        capture.volume_stencil_changed_bounds.max_y_exclusive,
        static_cast<unsigned long long>(capture.final_stencil_changed_pixels),
        capture.final_stencil_changed_bounds.valid, capture.final_stencil_changed_bounds.min_x,
        capture.final_stencil_changed_bounds.min_y,
        capture.final_stencil_changed_bounds.max_x_exclusive,
        capture.final_stencil_changed_bounds.max_y_exclusive,
        static_cast<unsigned long long>(capture.renderer.completed_executions),
        capture.renderer.last_actual_executions, capture.renderer.last_actual_ready,
        capture.renderer.last_actual_input_batches, capture.renderer.last_actual_input_vertices,
        capture.renderer.last_actual_input_records, capture.renderer.last_actual_output_vertices,
        capture.renderer.last_actual_front_triangles,
        capture.renderer.last_actual_back_triangles, capture.renderer.last_actual_draws,
        capture.renderer.last_actual_triangles, capture.renderer.last_actual_darken_draws,
        capture.renderer.last_actual_lighten_draws,
        capture.renderer.last_actual_unexpected_dma, capture.renderer.last_actual_invalid_plan,
        capture.renderer.last_actual_nonfinite_projection, capture.renderer.last_actual_overflow,
        capture.renderer.last_actual_pipeline_failures,
        capture.renderer.last_actual_reached_boundary);
  g_shadow195_frame_capture_logged = true;
}

void log_jak2_diagnostics_locked() {
  const auto& runtime = g_runtime_metrics;
  const auto& metal = g_metal_metrics;
  goal_thread_stack_watermark_report stack = {};
  goal_thread_stack_watermark(&stack);
  goal_jak2_sound_stream_state sound_streams = {};
  goal_jak2_sound_stream_state_get(&sound_streams);
  goal_jak2_progress_menu_snapshot progress_menu = {};
  goal_jak2_runtime_get_progress_menu_snapshot(&progress_menu);
  goal_jak2_progress_menu_diagnostics progress_detail = {};
  goal_jak2_runtime_get_progress_menu_diagnostics(&progress_detail);
  write_shadow_bucket195_capture_locked();
  log_shadow195_frame_capture_locked();
  NSLog(@"GOALPAD_JAK2_RUNTIME_STATE tick=%llu mode=%s title=%s scene=%s target=%s "
         "pmode=%.3f desired=%s active=%s dgo=%s/%s result=%d failures=%d "
         "dma=%d/%d/%d bytes=%u/%u chains=%llu/%llu/%llu cmd=%llu/%llu/%llu "
         "cmd-last=%d/%lld drawable=%llu/%llu submit=%llu/%llu/%llu draws=%llu/%llu "
         "progress=%llu/%llu/%llu/%llu map=%llu/%u/%u buckets=%llu skipped=%llu error=%s",
        static_cast<unsigned long long>(runtime.ticks), runtime.master_mode,
        runtime.title_control_state, runtime.scene_player_state, runtime.target_state,
        runtime.host_last_pmode_alpha, runtime.host_desired_levels, runtime.host_active_levels,
        runtime.current_dgo_name, runtime.last_dgo_name, runtime.dgo_last_result,
        runtime.dgo_failures, runtime.dma_chains, runtime.dma_well_formed,
        runtime.dma_malformed, runtime.dma_valid_payload_bytes, runtime.dma_valid_copied_bytes,
        static_cast<unsigned long long>(metal.chains),
        static_cast<unsigned long long>(metal.completed_chains),
        static_cast<unsigned long long>(metal.failed_chains),
        static_cast<unsigned long long>(metal.command_buffers_committed),
        static_cast<unsigned long long>(metal.command_buffers_completed),
        static_cast<unsigned long long>(metal.command_buffer_errors),
        metal.last_command_buffer_status,
        static_cast<long long>(metal.last_command_buffer_error_code),
        static_cast<unsigned long long>(metal.drawables_acquired),
        static_cast<unsigned long long>(metal.drawable_misses),
        static_cast<unsigned long long>(metal.submissions),
        static_cast<unsigned long long>(metal.presentations),
        static_cast<unsigned long long>(metal.presentation_drops),
        static_cast<unsigned long long>(metal.draws),
        static_cast<unsigned long long>(metal.triangles),
        static_cast<unsigned long long>(metal.last_progress_draws),
        static_cast<unsigned long long>(metal.last_progress_triangles),
        static_cast<unsigned long long>(metal.last_progress_textured_draws),
        static_cast<unsigned long long>(metal.last_progress_missing_texture_draws),
        static_cast<unsigned long long>(metal.map_texture_uploads),
        metal.last_map_texture_upload.valid, metal.last_map_texture_upload.upload_count,
        static_cast<unsigned long long>(metal.last_buckets_dispatched),
        static_cast<unsigned long long>(metal.skipped_bucket_bytes),
        g_metal_host ? goal_jak2_metal_host_last_error(g_metal_host) : "");

  NSLog(@"GOALPAD_JAK2_OCEAN_GOAL_STATE tick=%llu valid=%d "
         "map=0x%08x/0x%08x object=0x%08x false=0x%08x "
         "mask=0x%016llx/0x%016llx blit=0x%08x menu=0x%08x "
         "flags=0x%08x/0x%08x/0x%08x/0x%08x work=0x%08x/0x%08x",
        static_cast<unsigned long long>(runtime.ticks), runtime.ocean_diagnostics_valid,
        static_cast<unsigned int>(runtime.ocean_map),
        static_cast<unsigned int>(runtime.ocean_map_city),
        static_cast<unsigned int>(runtime.ocean_object),
        static_cast<unsigned int>(runtime.ocean_false_object),
        static_cast<unsigned long long>(runtime.ocean_renderer_mask),
        static_cast<unsigned long long>(runtime.ocean_renderer_menu_mask),
        static_cast<unsigned int>(runtime.ocean_blit_displays_work),
        static_cast<unsigned int>(runtime.ocean_blit_menu_mode),
        static_cast<unsigned int>(runtime.ocean_off),
        static_cast<unsigned int>(runtime.ocean_near_off),
        static_cast<unsigned int>(runtime.ocean_mid_off),
        static_cast<unsigned int>(runtime.ocean_far_on),
        static_cast<unsigned int>(runtime.ocean_heights),
        static_cast<unsigned int>(runtime.ocean_verts));

  NSLog(@"GOALPAD_JAK2_SCENE_ACTOR_STATE tick=%llu valid=%d sequence=%u scene=%016llx "
         "count=%d total=%d overflow=%d",
        static_cast<unsigned long long>(runtime.ticks), runtime.scene_actor_diagnostics_valid,
        runtime.scene_actor_sequence,
        static_cast<unsigned long long>(runtime.scene_actor_scene_name_hash),
        runtime.scene_actor_count, runtime.scene_actor_total_count, runtime.scene_actor_overflow);
  const int32_t actor_count =
      std::clamp(runtime.scene_actor_count, 0, GOAL_JAK2_SCENE_ACTOR_DIAGNOSTIC_MAX);
  for (int32_t index = 0; index < actor_count; ++index) {
    const auto& actor = runtime.scene_actors[index];
    NSLog(@"GOALPAD_JAK2_SCENE_ACTOR_ITEM tick=%llu sequence=%u index=%d "
           "flags=%u level=%u bucket=%u skeleton=%u joints=%u",
          static_cast<unsigned long long>(runtime.ticks), runtime.scene_actor_sequence, index,
          actor.flags, actor.level_index, actor.merc_pris_bucket, actor.skeleton_status,
          actor.merc_joint_count);
  }

  NSLog(@"GOALPAD_JAK2_VISUAL_STATE tick=%llu raw=%llu/%llu/%llu "
         "progress=%llu/%llu/%llu debug-no-zbuf1=%llu/%llu/%llu "
         "screen-filter=%llu skipped=%llu "
         "blit=%u/%u/%u/tbp0x%08x/lookup%u/placeholder%u "
         "sky-texture=%u/%u/tbp0x%08x/tcc%u/decal%u/lookup%u/placeholder%u "
         "sky-blend=%u/%u/%u/%u/%u",
        static_cast<unsigned long long>(runtime.ticks),
        static_cast<unsigned long long>(metal.raw_image_publications),
        static_cast<unsigned long long>(metal.raw_image_texture),
        static_cast<unsigned long long>(metal.raw_image_pixels),
        static_cast<unsigned long long>(metal.last_progress_draws),
        static_cast<unsigned long long>(metal.last_progress_textured_draws),
        static_cast<unsigned long long>(metal.last_progress_missing_texture_draws),
        static_cast<unsigned long long>(metal.last_debug_no_zbuf1_draws),
        static_cast<unsigned long long>(metal.last_debug_no_zbuf1_textured_draws),
        static_cast<unsigned long long>(metal.last_debug_no_zbuf1_missing_texture_draws),
        static_cast<unsigned long long>(metal.last_screen_filter_draws),
        static_cast<unsigned long long>(metal.skipped_bucket_bytes),
        metal.last_blit_display_snapshot_requested,
        metal.last_blit_display_copy_back_requested,
        metal.last_blit_display_copy_back_performed,
        metal.last_blit_display_texture_tbp,
        metal.last_blit_display_texture_lookup_hit,
        metal.last_blit_display_used_placeholder,
        metal.last_sky_draw_batch_valid,
        metal.last_sky_draw_batch_textured,
        metal.last_sky_draw_batch_tex0_tbp,
        metal.last_sky_draw_batch_tex0_tcc,
        metal.last_sky_draw_batch_tex0_decal,
        metal.last_sky_draw_batch_texture_lookup_hit,
        metal.last_sky_draw_batch_used_placeholder,
        metal.last_sky_draw_batch_blend_enabled,
        metal.last_sky_draw_batch_blend_a,
        metal.last_sky_draw_batch_blend_b,
        metal.last_sky_draw_batch_blend_c,
        metal.last_sky_draw_batch_blend_d);

  NSLog(@"GOALPAD_JAK2_FOREGROUND_STATE tick=%llu "
         "merc=%llu/%llu/%llu malformed=%llu reject-reason=%u missing-models=%llu "
         "merc-anim=%llu/%llu merc-eyes=%llu/%llu/%llu/%llu merc-missing-textures=%llu "
         "bones=%llu/%llu/%llu/%llu "
         "generic=%llu/%llu/%llu missing-textures=%llu unexpected-dma=%llu "
         "eyes=%llu/%llu/%llu missing=%llu unexpected=%llu duplicate=%llu "
         "eye-source-placeholder=%llu/%llu/%llu/%llu "
         "eye-source-first=%u/0x%08x/0x%016llx/%ux%u/0x%08x "
         "eye-cmd=%llu/%llu/%llu pris=%llu/%llu/%llu "
         "sprite-placeholder=%llu/%llu first-valid=%u first-tbp=0x%08x first-mode=0x%08x",
        static_cast<unsigned long long>(runtime.ticks),
        static_cast<unsigned long long>(metal.last_merc_models),
        static_cast<unsigned long long>(metal.last_merc_draws),
        static_cast<unsigned long long>(metal.last_merc_triangles),
        static_cast<unsigned long long>(metal.last_merc_malformed_dma),
        metal.last_merc_preflight_rejection_reason,
        static_cast<unsigned long long>(metal.last_merc_missing_models),
        static_cast<unsigned long long>(metal.last_merc_anim_slot_draws),
        static_cast<unsigned long long>(metal.last_merc_anim_slot_placeholder_draws),
        static_cast<unsigned long long>(metal.last_merc_eye_draws),
        static_cast<unsigned long long>(metal.last_merc_eye_renderer_missing),
        static_cast<unsigned long long>(metal.last_merc_eye_lookup_failed),
        static_cast<unsigned long long>(metal.last_merc_eye_placeholder_draws),
        static_cast<unsigned long long>(metal.last_merc_missing_textures),
        static_cast<unsigned long long>(metal.last_merc_bad_bone_pointers),
        static_cast<unsigned long long>(metal.last_merc_missing_bone_slots),
        static_cast<unsigned long long>(metal.last_merc_nonfinite_bone_matrices),
        static_cast<unsigned long long>(metal.last_merc_degenerate_bone_matrices),
        static_cast<unsigned long long>(metal.last_generic_draw_buckets),
        static_cast<unsigned long long>(metal.last_generic_draws),
        static_cast<unsigned long long>(metal.last_generic_triangles),
        static_cast<unsigned long long>(metal.last_generic_missing_textures),
        static_cast<unsigned long long>(metal.last_generic_unexpected_dma),
        static_cast<unsigned long long>(metal.last_eye_composed),
        static_cast<unsigned long long>(metal.last_eye_draws),
        static_cast<unsigned long long>(metal.last_eye_triangles),
        static_cast<unsigned long long>(metal.last_eye_missing_textures),
        static_cast<unsigned long long>(metal.last_eye_unexpected_dma),
        static_cast<unsigned long long>(metal.last_eye_duplicate_slot_writes),
        static_cast<unsigned long long>(metal.last_eye_placeholder_textures),
        static_cast<unsigned long long>(metal.last_eye_placeholder_iris_textures),
        static_cast<unsigned long long>(metal.last_eye_placeholder_pupil_textures),
        static_cast<unsigned long long>(metal.last_eye_placeholder_lid_textures),
        metal.last_eye_first_placeholder_component,
        metal.last_eye_first_placeholder_tbp,
        static_cast<unsigned long long>(metal.last_eye_first_placeholder_handle),
        metal.last_eye_first_placeholder_width,
        metal.last_eye_first_placeholder_height,
        metal.last_eye_first_placeholder_texture_id,
        static_cast<unsigned long long>(metal.last_eye_command_buffers_committed),
        static_cast<unsigned long long>(metal.last_eye_command_buffers_completed),
        static_cast<unsigned long long>(metal.last_eye_command_buffer_errors),
        static_cast<unsigned long long>(metal.last_pris_eye_dispatches),
        static_cast<unsigned long long>(metal.last_pris_eye_present_dispatches),
        static_cast<unsigned long long>(metal.last_pris_eye_chunks),
        static_cast<unsigned long long>(metal.last_sprite_placeholder_batches),
        static_cast<unsigned long long>(metal.last_sprite_placeholder_sprites),
        metal.last_sprite_first_placeholder_valid,
        metal.last_sprite_first_placeholder_valid ? metal.last_sprite_first_placeholder_tbp : 0,
        metal.last_sprite_first_placeholder_valid ? metal.last_sprite_first_placeholder_draw_mode
                                                  : 0);

  NSLog(@"GOALPAD_JAK2_EYE_READBACK_STATE tick=%llu readbacks=%llu errors=%llu "
         "producer=%u slot=%u vertex=0x%016llx/0x%016llx "
         "output=0x%016llx quadrants=0x%016llx/0x%016llx/0x%016llx/0x%016llx "
         "corners=0x%08x/0x%08x/0x%08x/0x%08x "
         "iris=0x%016llx/%ux%u/0x%08x/0x%08x/0x%08x/0x%08x "
         "lid=0x%016llx/%ux%u/0x%08x/0x%08x/0x%08x/0x%08x",
        static_cast<unsigned long long>(runtime.ticks),
        static_cast<unsigned long long>(metal.last_eye_diagnostic_readbacks),
        static_cast<unsigned long long>(metal.last_eye_diagnostic_readback_errors),
        metal.last_eye_diagnostic_producer_bucket, metal.last_eye_diagnostic_slot,
        static_cast<unsigned long long>(metal.last_eye_source_vertex_fingerprint),
        static_cast<unsigned long long>(metal.last_eye_vertex_fingerprint),
        static_cast<unsigned long long>(metal.last_eye_diagnostic_output_hash),
        static_cast<unsigned long long>(metal.last_eye_diagnostic_output_quadrant_hashes[0]),
        static_cast<unsigned long long>(metal.last_eye_diagnostic_output_quadrant_hashes[1]),
        static_cast<unsigned long long>(metal.last_eye_diagnostic_output_quadrant_hashes[2]),
        static_cast<unsigned long long>(metal.last_eye_diagnostic_output_quadrant_hashes[3]),
        metal.last_eye_diagnostic_output_corners[0],
        metal.last_eye_diagnostic_output_corners[1],
        metal.last_eye_diagnostic_output_corners[2],
        metal.last_eye_diagnostic_output_corners[3],
        static_cast<unsigned long long>(metal.last_eye_diagnostic_iris_source_hash),
        metal.last_eye_diagnostic_iris_source_width, metal.last_eye_diagnostic_iris_source_height,
        metal.last_eye_diagnostic_iris_source_corners[0],
        metal.last_eye_diagnostic_iris_source_corners[1],
        metal.last_eye_diagnostic_iris_source_corners[2],
        metal.last_eye_diagnostic_iris_source_corners[3],
        static_cast<unsigned long long>(metal.last_eye_diagnostic_lid_source_hash),
        metal.last_eye_diagnostic_lid_source_width, metal.last_eye_diagnostic_lid_source_height,
        metal.last_eye_diagnostic_lid_source_corners[0],
        metal.last_eye_diagnostic_lid_source_corners[1],
        metal.last_eye_diagnostic_lid_source_corners[2],
        metal.last_eye_diagnostic_lid_source_corners[3]);

  NSLog(@"GOALPAD_JAK2_RENDERER_STATE tick=%llu "
         "ocean=%llu/%llu/%llu/%llu/%llu missing=%llu cmd=%llu/%llu/%llu "
         "phase=%d/%d transfers=%d/%d grammar=%d/%d calls=%d/%d "
         "tfrag=%llu/%llu tie=%llu/%llu background-missing=%llu/%llu unexpected=%llu "
         "eye=%llu/%llu/%llu vertex-stream=%llu/%llu/%u/0x%016llx",
        static_cast<unsigned long long>(runtime.ticks),
        static_cast<unsigned long long>(metal.ocean_texture_vertices),
        static_cast<unsigned long long>(metal.ocean_mid_vertices),
        static_cast<unsigned long long>(metal.ocean_near_vertices),
        static_cast<unsigned long long>(metal.ocean_draws),
        static_cast<unsigned long long>(metal.ocean_triangles),
        static_cast<unsigned long long>(metal.ocean_missing_textures),
        static_cast<unsigned long long>(metal.ocean_command_buffers_committed),
        static_cast<unsigned long long>(metal.ocean_command_buffers_completed),
        static_cast<unsigned long long>(metal.ocean_command_buffer_errors),
        metal.ocean_mid_phase_order, metal.ocean_near_phase_order,
        metal.ocean_mid_texture_transfers, metal.ocean_near_texture_transfers,
        metal.ocean_mid_texture_grammar_errors, metal.ocean_near_texture_grammar_errors,
        metal.ocean_mid_calls, metal.ocean_near_calls,
        static_cast<unsigned long long>(metal.last_tfrag_draws),
        static_cast<unsigned long long>(metal.last_tfrag_triangles),
        static_cast<unsigned long long>(metal.last_tie_draws),
        static_cast<unsigned long long>(metal.last_tie_triangles),
        static_cast<unsigned long long>(metal.last_background_missing_levels),
        static_cast<unsigned long long>(metal.last_background_missing_textures),
        static_cast<unsigned long long>(metal.last_background_unexpected_dma),
        static_cast<unsigned long long>(metal.last_eye_composed),
        static_cast<unsigned long long>(metal.last_eye_draws),
        static_cast<unsigned long long>(metal.last_eye_triangles),
        static_cast<unsigned long long>(metal.last_eye_vertex_stream_uploads),
        static_cast<unsigned long long>(metal.last_eye_vertex_bytes),
        metal.last_eye_vertex_buffer_offset,
        static_cast<unsigned long long>(metal.last_eye_vertex_fingerprint));

  const auto& firstPalette = metal.first_merc_palette_health_event;
  const auto& lastPalette = metal.last_merc_palette_health_event;
  NSLog(@"GOALPAD_JAK2_MERC_PALETTE_STATE tick=%llu "
         "first=%u/%016llx/%d/0x%08x/0x%08x/%016llx "
         "last=%u/%016llx/%d/0x%08x/0x%08x/%016llx",
        static_cast<unsigned long long>(runtime.ticks), firstPalette.issue_mask,
        static_cast<unsigned long long>(firstPalette.model_name_hash), firstPalette.bone_slot,
        firstPalette.nonfinite_lane_mask, firstPalette.source_address,
        static_cast<unsigned long long>(firstPalette.matrix_hash), lastPalette.issue_mask,
        static_cast<unsigned long long>(lastPalette.model_name_hash), lastPalette.bone_slot,
        lastPalette.nonfinite_lane_mask, lastPalette.source_address,
        static_cast<unsigned long long>(lastPalette.matrix_hash));

  const uint32_t mercModelDiagnosticCount =
      metal.last_merc_model_diagnostic_count < GOAL_JAK2_MERC_MODEL_DIAGNOSTIC_COUNT
          ? metal.last_merc_model_diagnostic_count
          : GOAL_JAK2_MERC_MODEL_DIAGNOSTIC_COUNT;
  for (uint32_t index = 0; index < mercModelDiagnosticCount; ++index) {
    const auto& diagnostic = metal.last_merc_model_diagnostics[index];
    NSLog(@"GOALPAD_JAK2_MERC_MODEL_STATE tick=%llu index=%u count=%u overflow=%llu "
           "bucket=%u model=%016llx packets=%llu draws=%llu triangles=%llu missing=%llu",
          static_cast<unsigned long long>(runtime.ticks),
          index,
          mercModelDiagnosticCount,
          static_cast<unsigned long long>(metal.last_merc_model_diagnostic_overflow_packets),
          diagnostic.bucket_id,
          static_cast<unsigned long long>(diagnostic.model_name_hash),
          static_cast<unsigned long long>(diagnostic.packets),
          static_cast<unsigned long long>(diagnostic.draws),
          static_cast<unsigned long long>(diagnostic.triangles),
          static_cast<unsigned long long>(diagnostic.missing_models));
  }

  NSLog(@"GOALPAD_JAK2_GLOW_STATE tick=%llu marked=%llu skipped=%llu "
         "parsed=%llu accepted=%llu rejected=%llu invalid=%llu "
         "force-visible=%llu/%llu/%llu/%llu/%llu",
        static_cast<unsigned long long>(runtime.ticks),
        static_cast<unsigned long long>(metal.last_sprite_glow_marked),
        static_cast<unsigned long long>(metal.last_sprite_glow_skipped),
        static_cast<unsigned long long>(metal.last_sprite_glow_parsed),
        static_cast<unsigned long long>(metal.last_sprite_glow_accepted),
        static_cast<unsigned long long>(metal.last_sprite_glow_rejected),
        static_cast<unsigned long long>(metal.last_sprite_glow_invalid_records),
        static_cast<unsigned long long>(metal.last_sprite_glow_force_visible_submitted),
        static_cast<unsigned long long>(metal.last_sprite_glow_force_visible_drawn),
        static_cast<unsigned long long>(metal.last_sprite_glow_force_visible_draws),
        static_cast<unsigned long long>(metal.last_sprite_glow_force_visible_triangles),
        static_cast<unsigned long long>(metal.last_sprite_glow_force_visible_missing_textures));

  NSLog(@"GOALPAD_JAK2_PRISON_CLUT_STATE tick=%llu prep=%llu publish=%llu "
         "textures=%llu,%llu,%llu,%llu,%llu,%llu "
         "tbps=0x%08x,0x%08x,0x%08x,0x%08x,0x%08x,0x%08x "
         "slots=%u,%u,%u,%u,%u,%u",
        static_cast<unsigned long long>(runtime.ticks),
        static_cast<unsigned long long>(metal.prison_clut_preparations),
        static_cast<unsigned long long>(metal.prison_clut_publications),
        static_cast<unsigned long long>(metal.prison_clut_textures[0]),
        static_cast<unsigned long long>(metal.prison_clut_textures[1]),
        static_cast<unsigned long long>(metal.prison_clut_textures[2]),
        static_cast<unsigned long long>(metal.prison_clut_textures[3]),
        static_cast<unsigned long long>(metal.prison_clut_textures[4]),
        static_cast<unsigned long long>(metal.prison_clut_textures[5]),
        metal.prison_clut_destination_tbps[0],
        metal.prison_clut_destination_tbps[1],
        metal.prison_clut_destination_tbps[2],
        metal.prison_clut_destination_tbps[3],
        metal.prison_clut_destination_tbps[4],
        metal.prison_clut_destination_tbps[5],
        metal.prison_clut_anim_slots[0],
        metal.prison_clut_anim_slots[1],
        metal.prison_clut_anim_slots[2],
        metal.prison_clut_anim_slots[3],
        metal.prison_clut_anim_slots[4],
        metal.prison_clut_anim_slots[5]);

  const auto& water252 = metal.water_texture_uploads[0];
  NSLog(@"GOALPAD_JAK2_DEFERRED_STATE tick=%llu deferred_count=%u "
         "deferred_top=%u/%llu,%u/%llu,%u/%llu,%u/%llu "
         "water252=%u cap=%llu present=%llu exec=%llu "
         "class=m%llu/a%llu/o%llu/n%llu/oa%llu/e%llu/g%llu "
         "xfer=%llu bytes=%llu inert=%llu ordinary=%llu direct=%llu gs=%llu "
         "anim=%llu/%llu/%llu op=%llu/%llu/%llu/%llu eye=%llu other=%llu malformed=%llu "
         "last=t%u/q%u/b%llu/v0k%u/v0i%u/v1k%u/v1i%u "
         "last_sprites_distort=%llu last_sprite_glow_parsed=%llu "
         "last_sprite_glow_accepted=%llu last_sprite_glow_rejected=%llu "
         "last_sprite_glow_force_visible_drawn=%llu last_sprite_glow_force_visible_draws=%llu "
         "last_sprite_glow_force_visible_triangles=%llu "
         "last_sprite_glow_force_visible_missing_textures=%llu",
        static_cast<unsigned long long>(runtime.ticks), metal.last_skipped_bucket_count,
        metal.last_skipped_bucket_ids[0],
        static_cast<unsigned long long>(metal.last_skipped_bucket_bytes[0]),
        metal.last_skipped_bucket_ids[1],
        static_cast<unsigned long long>(metal.last_skipped_bucket_bytes[1]),
        metal.last_skipped_bucket_ids[2],
        static_cast<unsigned long long>(metal.last_skipped_bucket_bytes[2]),
        metal.last_skipped_bucket_ids[3],
        static_cast<unsigned long long>(metal.last_skipped_bucket_bytes[3]),
        water252.bucket_id,
        static_cast<unsigned long long>(water252.captures),
        static_cast<unsigned long long>(water252.present_captures),
        static_cast<unsigned long long>(water252.executions),
        static_cast<unsigned long long>(water252.classifications[0]),
        static_cast<unsigned long long>(water252.classifications[1]),
        static_cast<unsigned long long>(water252.classifications[2]),
        static_cast<unsigned long long>(water252.classifications[3]),
        static_cast<unsigned long long>(water252.classifications[4]),
        static_cast<unsigned long long>(water252.classifications[5]),
        static_cast<unsigned long long>(water252.classifications[6]),
        static_cast<unsigned long long>(water252.transfers),
        static_cast<unsigned long long>(water252.payload_bytes),
        static_cast<unsigned long long>(water252.inert_transfers),
        static_cast<unsigned long long>(water252.ordinary_descriptors),
        static_cast<unsigned long long>(water252.direct_setup_transfers),
        static_cast<unsigned long long>(water252.gs_setup_transfers),
        static_cast<unsigned long long>(water252.animator_arrays),
        static_cast<unsigned long long>(water252.animator_body_transfers),
        static_cast<unsigned long long>(water252.animator_payload_bytes),
        static_cast<unsigned long long>(water252.opcode_counts[12]),
        static_cast<unsigned long long>(water252.opcode_counts[13]),
        static_cast<unsigned long long>(water252.opcode_counts[27]),
        static_cast<unsigned long long>(water252.opcode_counts[30]),
        static_cast<unsigned long long>(water252.eye_markers),
        static_cast<unsigned long long>(water252.other_transfers),
        static_cast<unsigned long long>(water252.malformed_transfers),
        static_cast<unsigned>(water252.last_nonordinary_tag_kind),
        static_cast<unsigned>(water252.last_nonordinary_qwc),
        static_cast<unsigned long long>(water252.last_nonordinary_payload_bytes),
        static_cast<unsigned>(water252.last_nonordinary_vif0_kind),
        static_cast<unsigned>(water252.last_nonordinary_vif0_immediate),
        static_cast<unsigned>(water252.last_nonordinary_vif1_kind),
        static_cast<unsigned>(water252.last_nonordinary_vif1_immediate),
        static_cast<unsigned long long>(metal.last_sprites_distort),
        static_cast<unsigned long long>(metal.last_sprite_glow_parsed),
        static_cast<unsigned long long>(metal.last_sprite_glow_accepted),
        static_cast<unsigned long long>(metal.last_sprite_glow_rejected),
        static_cast<unsigned long long>(metal.last_sprite_glow_force_visible_drawn),
        static_cast<unsigned long long>(metal.last_sprite_glow_force_visible_draws),
        static_cast<unsigned long long>(metal.last_sprite_glow_force_visible_triangles),
        static_cast<unsigned long long>(metal.last_sprite_glow_force_visible_missing_textures));

  NSMutableString* water_upload_state = [NSMutableString string];
  for (const auto& water : metal.water_texture_uploads) {
    [water_upload_state
        appendFormat:@"%@b%u cap=%llu present=%llu exec=%llu "
                     "class=m%llu/a%llu/o%llu/n%llu/oa%llu/e%llu/g%llu "
                     "xfer=%llu bytes=%llu inert=%llu ordinary=%llu direct=%llu gs=%llu "
                     "anim=%llu/%llu/%llu op=%llu/%llu/%llu/%llu eye=%llu other=%llu malformed=%llu "
                     "last=t%u/q%u/b%llu/v0k%u/v0i%u/v1k%u/v1i%u",
                     water_upload_state.length ? @" " : @"", water.bucket_id,
                     static_cast<unsigned long long>(water.captures),
                     static_cast<unsigned long long>(water.present_captures),
                     static_cast<unsigned long long>(water.executions),
                     static_cast<unsigned long long>(water.classifications[0]),
                     static_cast<unsigned long long>(water.classifications[1]),
                     static_cast<unsigned long long>(water.classifications[2]),
                     static_cast<unsigned long long>(water.classifications[3]),
                     static_cast<unsigned long long>(water.classifications[4]),
                     static_cast<unsigned long long>(water.classifications[5]),
                     static_cast<unsigned long long>(water.classifications[6]),
                     static_cast<unsigned long long>(water.transfers),
                     static_cast<unsigned long long>(water.payload_bytes),
                     static_cast<unsigned long long>(water.inert_transfers),
                     static_cast<unsigned long long>(water.ordinary_descriptors),
                     static_cast<unsigned long long>(water.direct_setup_transfers),
                     static_cast<unsigned long long>(water.gs_setup_transfers),
                     static_cast<unsigned long long>(water.animator_arrays),
                     static_cast<unsigned long long>(water.animator_body_transfers),
                     static_cast<unsigned long long>(water.animator_payload_bytes),
                     static_cast<unsigned long long>(water.opcode_counts[12]),
                     static_cast<unsigned long long>(water.opcode_counts[13]),
                     static_cast<unsigned long long>(water.opcode_counts[27]),
                     static_cast<unsigned long long>(water.opcode_counts[30]),
                     static_cast<unsigned long long>(water.eye_markers),
                     static_cast<unsigned long long>(water.other_transfers),
                     static_cast<unsigned long long>(water.malformed_transfers),
                     static_cast<unsigned>(water.last_nonordinary_tag_kind),
                     static_cast<unsigned>(water.last_nonordinary_qwc),
                     static_cast<unsigned long long>(water.last_nonordinary_payload_bytes),
                     static_cast<unsigned>(water.last_nonordinary_vif0_kind),
                     static_cast<unsigned>(water.last_nonordinary_vif0_immediate),
                     static_cast<unsigned>(water.last_nonordinary_vif1_kind),
                     static_cast<unsigned>(water.last_nonordinary_vif1_immediate)];
  }
  NSLog(@"GOALPAD_JAK2_WATER_UPLOAD_STATE tick=%llu %@",
        static_cast<unsigned long long>(runtime.ticks), water_upload_state);

  const auto& common_water306 = metal.common_water_texture_upload;
  NSLog(@"GOALPAD_JAK2_COMMON_WATER306_STATE tick=%llu bucket=%u captures=%llu "
         "present=%llu malformed-class=%llu transfers=%llu bytes=%llu ordinary=%llu "
         "anim=%llu/%llu/%llu op12=%llu op13=%llu op16=%llu direct=%llu gs=%llu "
         "eye=%llu other=%llu malformed=%llu executions=%llu",
        static_cast<unsigned long long>(runtime.ticks), common_water306.bucket_id,
        static_cast<unsigned long long>(common_water306.captures),
        static_cast<unsigned long long>(common_water306.present_captures),
        static_cast<unsigned long long>(common_water306.classifications[0]),
        static_cast<unsigned long long>(common_water306.transfers),
        static_cast<unsigned long long>(common_water306.payload_bytes),
        static_cast<unsigned long long>(common_water306.ordinary_descriptors),
        static_cast<unsigned long long>(common_water306.animator_arrays),
        static_cast<unsigned long long>(common_water306.animator_body_transfers),
        static_cast<unsigned long long>(common_water306.animator_payload_bytes),
        static_cast<unsigned long long>(common_water306.opcode_counts[12]),
        static_cast<unsigned long long>(common_water306.opcode_counts[13]),
        static_cast<unsigned long long>(common_water306.opcode_counts[16]),
        static_cast<unsigned long long>(common_water306.direct_setup_transfers),
        static_cast<unsigned long long>(common_water306.gs_setup_transfers),
        static_cast<unsigned long long>(common_water306.eye_markers),
        static_cast<unsigned long long>(common_water306.other_transfers),
        static_cast<unsigned long long>(common_water306.malformed_transfers),
        static_cast<unsigned long long>(common_water306.executions));

  NSMutableString* pris_upload_state = [NSMutableString string];
  for (const auto& pris : metal.pris_texture_uploads) {
    [pris_upload_state
        appendFormat:@"%@b%u cap=%llu present=%llu "
                     "class=m%llu/a%llu/o%llu/n%llu/oa%llu/e%llu/g%llu "
                     "xfer=%llu bytes=%llu inert=%llu ordinary=%llu direct=%llu gs=%llu "
                     "anim=%llu/%llu/%llu eye=%llu other=%llu malformed=%llu "
                     "last=t%u/q%u/b%llu/v0k%u/v0i%u/v1k%u/v1i%u",
                     pris_upload_state.length ? @" " : @"", pris.bucket_id,
                     static_cast<unsigned long long>(pris.captures),
                     static_cast<unsigned long long>(pris.present_captures),
                     static_cast<unsigned long long>(pris.classifications[0]),
                     static_cast<unsigned long long>(pris.classifications[1]),
                     static_cast<unsigned long long>(pris.classifications[2]),
                     static_cast<unsigned long long>(pris.classifications[3]),
                     static_cast<unsigned long long>(pris.classifications[4]),
                     static_cast<unsigned long long>(pris.classifications[5]),
                     static_cast<unsigned long long>(pris.classifications[6]),
                     static_cast<unsigned long long>(pris.transfers),
                     static_cast<unsigned long long>(pris.payload_bytes),
                     static_cast<unsigned long long>(pris.inert_transfers),
                     static_cast<unsigned long long>(pris.ordinary_descriptors),
                     static_cast<unsigned long long>(pris.direct_setup_transfers),
                     static_cast<unsigned long long>(pris.gs_setup_transfers),
                     static_cast<unsigned long long>(pris.animator_arrays),
                     static_cast<unsigned long long>(pris.animator_body_transfers),
                     static_cast<unsigned long long>(pris.animator_payload_bytes),
                     static_cast<unsigned long long>(pris.eye_markers),
                     static_cast<unsigned long long>(pris.other_transfers),
                     static_cast<unsigned long long>(pris.malformed_transfers),
                     static_cast<unsigned>(pris.last_nonordinary_tag_kind),
                     static_cast<unsigned>(pris.last_nonordinary_qwc),
                     static_cast<unsigned long long>(pris.last_nonordinary_payload_bytes),
                     static_cast<unsigned>(pris.last_nonordinary_vif0_kind),
                     static_cast<unsigned>(pris.last_nonordinary_vif0_immediate),
                     static_cast<unsigned>(pris.last_nonordinary_vif1_kind),
                     static_cast<unsigned>(pris.last_nonordinary_vif1_immediate)];
  }
  NSLog(@"GOALPAD_JAK2_PRIS_UPLOAD_STATE tick=%llu %@",
        static_cast<unsigned long long>(runtime.ticks), pris_upload_state);

  NSMutableString* pris_diagnostic_state = [NSMutableString string];
  const auto append_pris_diagnostic =
      [&](const goal_jak2_tfrag_texture_upload_metrics& upload) {
        [pris_diagnostic_state
            appendFormat:@"%@b%u cap=%llu present=%llu "
                         "class=m%llu/a%llu/o%llu/n%llu/oa%llu/e%llu/g%llu "
                         "xfer=%llu bytes=%llu inert=%llu ordinary=%llu direct=%llu gs=%llu "
                         "anim=%llu/%llu/%llu op12=%llu op13=%llu op22=%llu eye=%llu "
                         "other=%llu malformed=%llu exec=%llu "
                         "last=t%u/q%u/b%llu/v0k%u/v0i%u/v1k%u/v1i%u",
                         pris_diagnostic_state.length ? @" " : @"", upload.bucket_id,
                         static_cast<unsigned long long>(upload.captures),
                         static_cast<unsigned long long>(upload.present_captures),
                         static_cast<unsigned long long>(upload.classifications[0]),
                         static_cast<unsigned long long>(upload.classifications[1]),
                         static_cast<unsigned long long>(upload.classifications[2]),
                         static_cast<unsigned long long>(upload.classifications[3]),
                         static_cast<unsigned long long>(upload.classifications[4]),
                         static_cast<unsigned long long>(upload.classifications[5]),
                         static_cast<unsigned long long>(upload.classifications[6]),
                         static_cast<unsigned long long>(upload.transfers),
                         static_cast<unsigned long long>(upload.payload_bytes),
                         static_cast<unsigned long long>(upload.inert_transfers),
                         static_cast<unsigned long long>(upload.ordinary_descriptors),
                         static_cast<unsigned long long>(upload.direct_setup_transfers),
                         static_cast<unsigned long long>(upload.gs_setup_transfers),
                         static_cast<unsigned long long>(upload.animator_arrays),
                         static_cast<unsigned long long>(upload.animator_body_transfers),
                         static_cast<unsigned long long>(upload.animator_payload_bytes),
                         static_cast<unsigned long long>(upload.opcode_counts[12]),
                         static_cast<unsigned long long>(upload.opcode_counts[13]),
                         static_cast<unsigned long long>(upload.opcode_counts[22]),
                         static_cast<unsigned long long>(upload.eye_markers),
                         static_cast<unsigned long long>(upload.other_transfers),
                         static_cast<unsigned long long>(upload.malformed_transfers),
                         static_cast<unsigned long long>(upload.executions),
                         static_cast<unsigned>(upload.last_nonordinary_tag_kind),
                         static_cast<unsigned>(upload.last_nonordinary_qwc),
                         static_cast<unsigned long long>(upload.last_nonordinary_payload_bytes),
                         static_cast<unsigned>(upload.last_nonordinary_vif0_kind),
                         static_cast<unsigned>(upload.last_nonordinary_vif0_immediate),
                         static_cast<unsigned>(upload.last_nonordinary_vif1_kind),
                         static_cast<unsigned>(upload.last_nonordinary_vif1_immediate)];
      };
  append_pris_diagnostic(metal.common_pris_texture_upload);
  for (const auto& pris2 : metal.pris2_bucket_captures) {
    append_pris_diagnostic(pris2);
  }
  NSLog(@"GOALPAD_JAK2_PRIS_DIAGNOSTIC_STATE tick=%llu %@",
        static_cast<unsigned long long>(runtime.ticks), pris_diagnostic_state);

  const auto& effects315 = metal.effects_bucket315;
  const auto& effects315Execution = metal.effects_bucket315_execution;
  NSLog(@"GOALPAD_JAK2_EFFECTS315_STATE tick=%llu "
         "captures=%llu valid=%llu malformed=%llu absent=%llu lightning=%llu other=%llu "
         "payload-bytes=%llu last-transfers=%u last-fragments=%u last-vertices=%u "
         "last-payload-bytes=%llu last-fingerprint=%016llx last-classification=%u "
         "exec-callbacks=%llu exec-completed=%llu expected=%u/%u/%u/%u "
         "actual=%u/%u/%u/%u/%u missing=%u placeholders=%u unsupported=%u unexpected=%u "
         "overflow=%u",
        static_cast<unsigned long long>(runtime.ticks),
        static_cast<unsigned long long>(effects315.captures),
        static_cast<unsigned long long>(effects315.valid_captures),
        static_cast<unsigned long long>(effects315.malformed_captures),
        static_cast<unsigned long long>(effects315.absent_captures),
        static_cast<unsigned long long>(effects315.lightning_captures),
        static_cast<unsigned long long>(effects315.other_captures),
        static_cast<unsigned long long>(effects315.payload_bytes), effects315.last_transfer_count,
        effects315.last_fragment_count, effects315.last_vertex_count,
        static_cast<unsigned long long>(effects315.last_payload_bytes),
        static_cast<unsigned long long>(effects315.last_semantic_fingerprint),
        static_cast<unsigned>(effects315.last_classification),
        static_cast<unsigned long long>(effects315Execution.callback_dispatches),
        static_cast<unsigned long long>(effects315Execution.completed_executions),
        effects315Execution.last_expected_fragments, effects315Execution.last_expected_vertices,
        effects315Execution.last_expected_adgifs, effects315Execution.last_expected_draws,
        effects315Execution.last_actual_fragments, effects315Execution.last_actual_vertices,
        effects315Execution.last_actual_adgifs, effects315Execution.last_actual_draw_buckets,
        effects315Execution.last_actual_draws, effects315Execution.last_actual_missing_textures,
        effects315Execution.last_actual_placeholder_draws,
        effects315Execution.last_actual_unsupported_blends,
        effects315Execution.last_actual_unexpected_dma, effects315Execution.last_actual_overflow);

  const auto& shadow195 = metal.shadow_bucket195;
  NSLog(@"GOALPAD_JAK2_SHADOW195_STATE tick=%llu observations=%llu absent=%llu observed=%llu "
         "malformed=%llu limited=%llu last-status=%u boundary=%u transfers=%u "
         "v432=%u/%u v48=%u/%u direct=%u bytes=%llu/%llu/%llu "
         "terminal=%u/%u/%u/%u fingerprint=%016llx",
        static_cast<unsigned long long>(runtime.ticks),
        static_cast<unsigned long long>(shadow195.observations),
        static_cast<unsigned long long>(shadow195.absent),
        static_cast<unsigned long long>(shadow195.observed),
        static_cast<unsigned long long>(shadow195.malformed),
        static_cast<unsigned long long>(shadow195.limit_exceeded),
        static_cast<unsigned>(shadow195.last_status),
        static_cast<unsigned>(shadow195.last_reached_boundary), shadow195.last_transfer_count,
        shadow195.last_v4_32_transfer_count, shadow195.last_v4_32_unpack_count,
        shadow195.last_v4_8_transfer_count, shadow195.last_v4_8_unpack_count,
        shadow195.last_direct_transfer_count,
        static_cast<unsigned long long>(shadow195.last_total_payload_bytes),
        static_cast<unsigned long long>(shadow195.last_direct_payload_bytes),
        static_cast<unsigned long long>(shadow195.last_flusha_direct_payload_bytes),
        static_cast<unsigned>(shadow195.last_terminal_qwc),
        static_cast<unsigned>(shadow195.last_terminal_tag_kind),
        static_cast<unsigned>(shadow195.last_terminal_vif0_kind),
        static_cast<unsigned>(shadow195.last_terminal_vif1_kind),
        static_cast<unsigned long long>(shadow195.last_semantic_fingerprint));

  const auto& warp316 = metal.warp_texture_upload;
  NSLog(@"GOALPAD_JAK2_WARP316_STATE tick=%llu observations=%llu absent=%llu ordinary=%llu "
         "unclassified=%llu last-uploads=%u last-transfers=%u last-payload-bytes=%llu "
         "last-fingerprint=%016llx executions=%llu",
        static_cast<unsigned long long>(runtime.ticks),
        static_cast<unsigned long long>(warp316.observations),
        static_cast<unsigned long long>(warp316.absent),
        static_cast<unsigned long long>(warp316.ordinary),
        static_cast<unsigned long long>(warp316.unclassified), warp316.last_upload_count,
        warp316.last_transfer_count,
        static_cast<unsigned long long>(warp316.last_payload_bytes),
        static_cast<unsigned long long>(warp316.last_semantic_fingerprint),
        static_cast<unsigned long long>(metal.warp_texture_upload_executions));

  const auto& warp317 = metal.gmerc_warp_bucket317;
  const auto& warp317Execution = metal.gmerc_warp_bucket317_execution;
  NSLog(@"GOALPAD_JAK2_WARP317_STATE tick=%llu observations=%llu absent=%llu setup=%llu "
         "fragments=%llu malformed=%llu last-variant=%u transfers=%u fragments-last=%u "
         "continued=%u vertices=%u adgifs=%u bytes=%llu fingerprint=%016llx "
         "exec=%llu/%llu expected=%u/%u/%u/%u actual=%u/%u/%u/%u/%u/%u/%u "
         "missing=%u/%u/%u unsupported=%u unexpected=%u overflow=%u "
         "snapshot=%u/%u/%u/%u/%u handle=%llu",
        static_cast<unsigned long long>(runtime.ticks),
        static_cast<unsigned long long>(warp317.observations),
        static_cast<unsigned long long>(warp317.absent),
        static_cast<unsigned long long>(warp317.setup_only),
        static_cast<unsigned long long>(warp317.fragments),
        static_cast<unsigned long long>(warp317.malformed),
        static_cast<unsigned>(warp317.last_variant), warp317.last_transfer_count,
        warp317.last_fragment_count, warp317.last_continued_fragment_count,
        warp317.last_vertex_count, warp317.last_adgif_count,
        static_cast<unsigned long long>(warp317.last_payload_bytes),
        static_cast<unsigned long long>(warp317.last_semantic_fingerprint),
        static_cast<unsigned long long>(warp317Execution.callback_dispatches),
        static_cast<unsigned long long>(warp317Execution.completed_executions),
        warp317Execution.last_expected_fragments,
        warp317Execution.last_expected_continued_fragments,
        warp317Execution.last_expected_vertices, warp317Execution.last_expected_adgifs,
        warp317Execution.last_actual_fragments,
        warp317Execution.last_actual_continued_fragments,
        warp317Execution.last_actual_vertices, warp317Execution.last_actual_adgifs,
        warp317Execution.last_actual_draw_buckets, warp317Execution.last_actual_draws,
        warp317Execution.last_actual_triangles, warp317Execution.last_actual_missing_textures,
        warp317Execution.last_actual_placeholder_draws,
        warp317Execution.last_actual_missing_publications,
        warp317Execution.last_actual_unsupported_blends,
        warp317Execution.last_actual_unexpected_dma, warp317Execution.last_actual_overflow,
        warp317Execution.last_snapshot_publications, warp317Execution.last_snapshot_copies,
        warp317Execution.last_snapshot_allocations, warp317Execution.last_snapshot_replacements,
        warp317Execution.last_snapshot_failures,
        static_cast<unsigned long long>(warp317Execution.last_snapshot_texture));

  const auto& subtitle322 = metal.subtitle_capture;
  NSLog(@"GOALPAD_JAK2_SUBTITLE322_STATE tick=%llu bucket=%u captures=%llu present=%llu "
         "class=m%llu/a%llu/o%llu/n%llu/oa%llu/e%llu/g%llu transfers=%llu bytes=%llu "
         "ordinary=%llu direct=%llu gs=%llu anim=%llu/%llu/%llu op12=%llu op13=%llu "
         "op22=%llu eye=%llu other=%llu malformed=%llu executions=%llu",
        static_cast<unsigned long long>(runtime.ticks), subtitle322.bucket_id,
        static_cast<unsigned long long>(subtitle322.captures),
        static_cast<unsigned long long>(subtitle322.present_captures),
        static_cast<unsigned long long>(subtitle322.classifications[0]),
        static_cast<unsigned long long>(subtitle322.classifications[1]),
        static_cast<unsigned long long>(subtitle322.classifications[2]),
        static_cast<unsigned long long>(subtitle322.classifications[3]),
        static_cast<unsigned long long>(subtitle322.classifications[4]),
        static_cast<unsigned long long>(subtitle322.classifications[5]),
        static_cast<unsigned long long>(subtitle322.classifications[6]),
        static_cast<unsigned long long>(subtitle322.transfers),
        static_cast<unsigned long long>(subtitle322.payload_bytes),
        static_cast<unsigned long long>(subtitle322.ordinary_descriptors),
        static_cast<unsigned long long>(subtitle322.direct_setup_transfers),
        static_cast<unsigned long long>(subtitle322.gs_setup_transfers),
        static_cast<unsigned long long>(subtitle322.animator_arrays),
        static_cast<unsigned long long>(subtitle322.animator_body_transfers),
        static_cast<unsigned long long>(subtitle322.animator_payload_bytes),
        static_cast<unsigned long long>(subtitle322.opcode_counts[12]),
        static_cast<unsigned long long>(subtitle322.opcode_counts[13]),
        static_cast<unsigned long long>(subtitle322.opcode_counts[22]),
        static_cast<unsigned long long>(subtitle322.eye_markers),
        static_cast<unsigned long long>(subtitle322.other_transfers),
        static_cast<unsigned long long>(subtitle322.malformed_transfers),
        static_cast<unsigned long long>(subtitle322.executions));

  const auto& subtitleTyped = metal.subtitle_bucket322_typed;
  NSLog(@"GOALPAD_JAK2_SUBTITLE322_TYPED tick=%llu observed=%llu matched=%llu rejected=%llu "
         "mismatched=%llu variants=%llu/%llu/%llu/%llu/%llu status=%u variant=%u "
         "reject=%u/%u transfers=%u linker=%u direct=%u opaque=%u hud=%u images=%u "
         "bytes=%llu fingerprint=%016llx",
        static_cast<unsigned long long>(runtime.ticks),
        static_cast<unsigned long long>(subtitleTyped.observations),
        static_cast<unsigned long long>(subtitleTyped.matched),
        static_cast<unsigned long long>(subtitleTyped.rejected),
        static_cast<unsigned long long>(subtitleTyped.semantic_mismatches),
        static_cast<unsigned long long>(subtitleTyped.variants[0]),
        static_cast<unsigned long long>(subtitleTyped.variants[1]),
        static_cast<unsigned long long>(subtitleTyped.variants[2]),
        static_cast<unsigned long long>(subtitleTyped.variants[3]),
        static_cast<unsigned long long>(subtitleTyped.variants[4]),
        subtitleTyped.last_status, subtitleTyped.last_variant,
        subtitleTyped.last_reject_reason, subtitleTyped.last_reject_transfer_index,
        subtitleTyped.last_transfer_count, subtitleTyped.last_linker_transfers,
        subtitleTyped.last_direct_transfers, subtitleTyped.last_opaque_direct_transfers,
        subtitleTyped.last_hud_sprite_pairs, subtitleTyped.last_image_upload_count,
        static_cast<unsigned long long>(subtitleTyped.last_direct_payload_bytes),
        static_cast<unsigned long long>(subtitleTyped.last_semantic_fingerprint));

  NSLog(@"GOALPAD_JAK2_SKY_POST_STATE tick=%llu executions=%llu",
        static_cast<unsigned long long>(runtime.ticks),
        static_cast<unsigned long long>(metal.sky_post_texture_upload_executions));

  NSLog(@"GOALPAD_JAK2_MERC_ANIM_SLOT_STATE tick=%llu draws=%llu,%llu,%llu,%llu "
         "placeholders=%llu,%llu,%llu,%llu models=%016llx,%016llx,%016llx,%016llx",
        static_cast<unsigned long long>(runtime.ticks),
        static_cast<unsigned long long>(metal.last_merc_anim_slot_draws_by_slot[0]),
        static_cast<unsigned long long>(metal.last_merc_anim_slot_draws_by_slot[1]),
        static_cast<unsigned long long>(metal.last_merc_anim_slot_draws_by_slot[2]),
        static_cast<unsigned long long>(metal.last_merc_anim_slot_draws_by_slot[3]),
        static_cast<unsigned long long>(metal.last_merc_anim_slot_placeholder_draws_by_slot[0]),
        static_cast<unsigned long long>(metal.last_merc_anim_slot_placeholder_draws_by_slot[1]),
        static_cast<unsigned long long>(metal.last_merc_anim_slot_placeholder_draws_by_slot[2]),
        static_cast<unsigned long long>(metal.last_merc_anim_slot_placeholder_draws_by_slot[3]),
        static_cast<unsigned long long>(metal.last_merc_anim_slot_first_model_hashes[0]),
        static_cast<unsigned long long>(metal.last_merc_anim_slot_first_model_hashes[1]),
        static_cast<unsigned long long>(metal.last_merc_anim_slot_first_model_hashes[2]),
        static_cast<unsigned long long>(metal.last_merc_anim_slot_first_model_hashes[3]));

  NSLog(@"GOALPAD_JAK2_PROGRESS_STATE tick=%llu available=%d screen=%d option=%d "
         "selected=%d transition=%d navigation=%d starting=%d exit-start=%d back=%d",
        static_cast<unsigned long long>(runtime.ticks), progress_menu.available,
        progress_menu.screen, progress_menu.option_index, progress_menu.selected_option,
        progress_menu.in_transition, progress_menu.navigation_available,
        progress_menu.starting_screen, progress_menu.can_exit_with_start,
        progress_menu.can_go_back);

  NSLog(@"GOALPAD_JAK2_PROGRESS_DETAIL tick=%llu rejection=%d progress=%08x "
         "state=%08x/%08x scheduled=%08x options=%08x/%08x current=%08x/%08x "
         "next=%08x/%08x starting=%08x option=%d selected=%08x transition=%.3f",
        static_cast<unsigned long long>(runtime.ticks), progress_detail.rejection,
        progress_detail.progress, progress_detail.process_state,
        progress_detail.process_state_name, progress_detail.process_next_state,
        progress_detail.current_options, progress_detail.expected_options,
        progress_detail.current, progress_detail.expected_current, progress_detail.next,
        progress_detail.expected_next, progress_detail.starting_state,
        progress_detail.option_index, progress_detail.selected_option,
        progress_detail.menu_transition);

  NSLog(@"GOALPAD_JAK2_SCENE_STATE tick=%llu display=%d/%lld blackout=%lld/%lld "
         "settings=%d bg=%.3f/%.3f movie=%08x spool=%08x scene=%d/%d index=%d/%d "
         "identity=%s|%s|%s ptrs=%08x/%08x/%08x/%08x time=%lld/%lld "
         "skel=%d/%04x/%u anim=%d/%08x/%.3f/%.3f "
         "wait=%d/%d entry=%08x/%d art=%s/%08x gui=%08x/%d/%d/%d "
         "sound=%u/%u/%u/%u/%u/%u/%u/%u",
        static_cast<unsigned long long>(runtime.ticks), runtime.display_timing_valid,
        static_cast<long long>(runtime.display_base_frame_counter),
        static_cast<long long>(runtime.blackout_time),
        static_cast<long long>(runtime.blackout_remaining),
        runtime.settings_diagnostics_valid, runtime.background_alpha,
        runtime.background_alpha_force, runtime.movie_process, runtime.spooling_process,
        runtime.scene_diagnostics_valid, runtime.scene_identity_valid, runtime.scene_index,
        runtime.scene_list_length, runtime.scene_entity, runtime.scene_art_group,
        runtime.scene_animation_name, runtime.scene_list, runtime.scene,
        runtime.scene_animation, runtime.scene_next_animation,
        static_cast<long long>(runtime.scene_start_time),
        static_cast<long long>(runtime.scene_elapsed), runtime.skeleton_diagnostics_valid,
        static_cast<unsigned>(runtime.skeleton_status),
        static_cast<unsigned>(runtime.skeleton_active_channels),
        runtime.animation_diagnostics_valid, runtime.animation_frame_group,
        runtime.animation_frame, runtime.animation_aframe,
        runtime.scene_wait_diagnostics_valid, runtime.scene_wait_gate,
        runtime.scene_wait_entry_gui_id, runtime.scene_wait_entry_gui_status,
        runtime.scene_wait_art_file_status_name, runtime.scene_wait_art_file_status,
        runtime.scene_wait_art_gui_id, runtime.scene_wait_art_gui_channel,
        runtime.scene_wait_art_gui_action, runtime.scene_wait_art_gui_status,
        runtime.sound_player_batches,
        runtime.sound_player_commands, runtime.sound_play_requests, runtime.sound_sounds_started,
        runtime.sound_updates, runtime.sound_str_requests, runtime.sound_str_reads,
        runtime.sound_str_bytes);

  NSLog(@"GOALPAD_JAK2_STACK_STATE tick=%llu suspends=%d current=%d/%d "
        @"deepest=%d/%d fullest=%d/%d overflows=%d failures=%d",
        static_cast<unsigned long long>(runtime.ticks), stack.suspends,
        stack.current_used, stack.current_size, stack.deepest_used,
        stack.deepest_size, stack.fullest_used, stack.fullest_size,
        stack.overflow_failures, stack.validation_failures);

  NSLog(@"GOALPAD_JAK2_STREAM_CLOCK_STATE tick=%llu pulls=%llu/%llu",
        static_cast<unsigned long long>(runtime.ticks),
        static_cast<unsigned long long>(sound_streams.pull_calls),
        static_cast<unsigned long long>(sound_streams.pulled_frames));
  for (uint32_t i = 0; i < GOAL_JAK2_SOUND_STREAM_SLOT_COUNT; i++) {
    const auto& stream = sound_streams.slots[i];
    NSLog(@"GOALPAD_JAK2_STREAM_SLOT_STATE tick=%llu slot=%u active=%u id=%d "
           "published=%u/%d voices=%d/%d ring=0x%08x/0x%08x/0x%08x "
           "bytes=%u/%u/%llu rate=%u chunks=%u samples=%llu invalid=%llu "
           "wraps=%llu advances=%llu stalls=%llu halves=%llu flags=%u/%u/%u/%u",
          static_cast<unsigned long long>(runtime.ticks), i,
          static_cast<unsigned>(stream.active), stream.id, stream.published_status,
          stream.published_position, stream.primary_voice, stream.secondary_voice,
          stream.ring_base, stream.sampled_nax, stream.last_nax, stream.bytes_read,
          stream.total_bytes, static_cast<unsigned long long>(stream.played_bytes),
          stream.sample_rate, stream.chunks_loaded,
          static_cast<unsigned long long>(stream.clock_samples),
          static_cast<unsigned long long>(stream.invalid_nax_samples),
          static_cast<unsigned long long>(stream.ring_wraps),
          static_cast<unsigned long long>(stream.position_advances),
          static_cast<unsigned long long>(stream.position_stalls),
          static_cast<unsigned long long>(stream.half_transitions),
          static_cast<unsigned>(stream.playing), static_cast<unsigned>(stream.paused),
          static_cast<unsigned>(stream.finished), static_cast<unsigned>(stream.current_half));
  }
}

void clear_runtime_snapshots_locked() {
  g_runtime_metrics = {};
  g_metal_metrics = {};
  g_diagnostic_cadence.reset();
  g_frame_armed = false;
  g_frame_baseline_chains = 0;
  g_frame_baseline_drawables = 0;
  g_frame_baseline_submissions = 0;
  g_frames_armed = 0;
  g_frames_without_chain = 0;
  g_frames_with_multiple_chains = 0;
  g_max_chains_per_frame = 0;
  g_shadow_bucket195_capture_written = false;
  g_shadow195_frame_capture_logged = false;
  g_target_frame_rate = 60;
}

GOALPadProgressMenuSnapshot unavailable_progress_snapshot() {
  GOALPadProgressMenuSnapshot snapshot = {};
  snapshot.screen = GOALPadProgressScreenUnknown;
  snapshot.optionIndex = -1;
  snapshot.startingScreen = GOALPadProgressScreenUnknown;
  return snapshot;
}

GOALPadJak2ProgressMenuSemanticSnapshot unavailable_progress_semantic_snapshot() {
  GOALPadJak2ProgressMenuSemanticSnapshot snapshot = {};
  snapshot.phase = GOALPadJak2ProgressMenuPhaseUnavailable;
  snapshot.optionIndex = -1;
  return snapshot;
}

GOALPadJak2TraversalState traversal_state_from_core(goal_jak2_player_traversal_state state) {
  switch (state) {
    case GOAL_JAK2_PLAYER_TRAVERSAL_ON_FOOT:
      return GOALPadJak2TraversalStateOnFoot;
    case GOAL_JAK2_PLAYER_TRAVERSAL_JETBOARD:
      return GOALPadJak2TraversalStateJetboard;
    case GOAL_JAK2_PLAYER_TRAVERSAL_VEHICLE_TRANSITION:
      return GOALPadJak2TraversalStateVehicleTransition;
    case GOAL_JAK2_PLAYER_TRAVERSAL_VEHICLE_RIDING:
      return GOALPadJak2TraversalStateVehicleRiding;
    case GOAL_JAK2_PLAYER_TRAVERSAL_UNKNOWN:
      return GOALPadJak2TraversalStateUnknown;
  }
  return GOALPadJak2TraversalStateUnknown;
}

GOALPadLookAroundState look_state_from_core(goal_jak2_player_look_state state) {
  switch (state) {
    case GOAL_JAK2_PLAYER_LOOK_NORMAL:
      return GOALPadLookAroundStateNormal;
    case GOAL_JAK2_PLAYER_LOOK_AROUND:
      return GOALPadLookAroundStateFirstPerson;
    case GOAL_JAK2_PLAYER_LOOK_UNKNOWN:
      return GOALPadLookAroundStateUnknown;
  }
  return GOALPadLookAroundStateUnknown;
}

goal_jak2_player_context_snapshot current_player_context_snapshot() {
  std::lock_guard<std::mutex> lock(g_mutex);
  goal_jak2_player_context_snapshot snapshot = {};
  if (g_state != SessionState::Running ||
      goal_jak2_runtime_get_player_context_snapshot(&snapshot) != GOAL_JAK2_RUNTIME_OK) {
    return {};
  }
  return snapshot;
}

bool valid_progress_semantic_snapshot(
    const goal_jak2_progress_menu_semantic_snapshot& snapshot) {
  if (snapshot.available != 1) {
    return false;
  }
  switch (snapshot.phase) {
    case GOAL_JAK2_PROGRESS_MENU_PHASE_SELECT_SAVE_TITLE:
      return snapshot.option_index >= 0 && snapshot.option_index <= 4 &&
             snapshot.action_mask == (GOAL_JAK2_PROGRESS_MENU_ACTION_UP |
                                      GOAL_JAK2_PROGRESS_MENU_ACTION_DOWN |
                                      GOAL_JAK2_PROGRESS_MENU_ACTION_CONFIRM |
                                      GOAL_JAK2_PROGRESS_MENU_ACTION_BACK);
    case GOAL_JAK2_PROGRESS_MENU_PHASE_SELECT_LOAD:
    case GOAL_JAK2_PROGRESS_MENU_PHASE_SELECT_SAVE:
      return snapshot.option_index >= 0 && snapshot.option_index <= 3 &&
             snapshot.action_mask == (GOAL_JAK2_PROGRESS_MENU_ACTION_UP |
                                      GOAL_JAK2_PROGRESS_MENU_ACTION_DOWN |
                                      GOAL_JAK2_PROGRESS_MENU_ACTION_CONFIRM |
                                      GOAL_JAK2_PROGRESS_MENU_ACTION_BACK);
    case GOAL_JAK2_PROGRESS_MENU_PHASE_NO_MEMORY_CARD:
      return snapshot.option_index == 0 &&
             snapshot.action_mask == GOAL_JAK2_PROGRESS_MENU_ACTION_CONFIRM;
    case GOAL_JAK2_PROGRESS_MENU_PHASE_CREATE_GAME:
      return snapshot.option_index == 0 &&
             snapshot.action_mask == (GOAL_JAK2_PROGRESS_MENU_ACTION_LEFT |
                                      GOAL_JAK2_PROGRESS_MENU_ACTION_RIGHT |
                                      GOAL_JAK2_PROGRESS_MENU_ACTION_CONFIRM |
                                      GOAL_JAK2_PROGRESS_MENU_ACTION_BACK);
    case GOAL_JAK2_PROGRESS_MENU_PHASE_ALREADY_EXISTS:
      return snapshot.option_index == 0 &&
             snapshot.action_mask == (GOAL_JAK2_PROGRESS_MENU_ACTION_LEFT |
                                      GOAL_JAK2_PROGRESS_MENU_ACTION_RIGHT |
                                      GOAL_JAK2_PROGRESS_MENU_ACTION_CONFIRM |
                                      GOAL_JAK2_PROGRESS_MENU_ACTION_BACK);
    case GOAL_JAK2_PROGRESS_MENU_PHASE_ICON_INFO:
      return snapshot.option_index == 0 &&
             snapshot.action_mask == GOAL_JAK2_PROGRESS_MENU_ACTION_CONFIRM;
    case GOAL_JAK2_PROGRESS_MENU_PHASE_CREATING:
    case GOAL_JAK2_PROGRESS_MENU_PHASE_SAVING:
    case GOAL_JAK2_PROGRESS_MENU_PHASE_LOADING:
      return snapshot.option_index == 0 &&
             snapshot.action_mask == GOAL_JAK2_PROGRESS_MENU_ACTION_NONE;
    default:
      return false;
  }
}

GOALPadWarpGateTouchSnapshot unavailable_warp_gate_snapshot() {
  GOALPadWarpGateTouchSnapshot snapshot = {};
  snapshot.state = GOALPadWarpGateTouchStateUnavailable;
  return snapshot;
}

GOALPadCutsceneSkipTouchSnapshot unavailable_cutscene_snapshot() {
  GOALPadCutsceneSkipTouchSnapshot snapshot = {};
  snapshot.state = GOALPadCutsceneSkipTouchStateUnavailable;
  return snapshot;
}

bool valid_face_prompt_touch_snapshot(const goal_jak2_face_prompt_touch_snapshot& snapshot) {
  constexpr uint32_t kFaceButtonMask = GOALPadButtonTriangle | GOALPadButtonCircle |
                                       GOALPadButtonCross | GOALPadButtonSquare;
  return snapshot.available == 1 && !(snapshot.sequence & 1u) && snapshot.requested_buttons &&
         !(snapshot.requested_buttons & ~kFaceButtonMask);
}

}  // namespace

@interface GOALPadKernelType ()
@property(nonatomic, readwrite) NSString* symbolName;
@property(nonatomic, readwrite) NSString* typeName;
@property(nonatomic, readwrite) NSString* parentName;
@property(nonatomic, readwrite) uint32_t typeOffset;
@property(nonatomic, readwrite) uint32_t allocatedSize;
@property(nonatomic, readwrite) uint32_t methodCount;
@end

@implementation GOALPadKernelType
@end

@interface GOALPadKernelStatus ()
@property(nonatomic, readwrite, getter=isRunning) BOOL running;
@property(nonatomic, readwrite) NSString* message;
@property(nonatomic, readwrite) NSString* architecture;
@property(nonatomic, readwrite) NSString* dataDirectory;
@property(nonatomic, readwrite, getter=isDataDirectoryAccepted) BOOL dataDirectoryAccepted;
@property(nonatomic, readwrite) uint64_t mainMemoryAddress;
@property(nonatomic, readwrite) uint32_t mainMemorySize;
@property(nonatomic, readwrite, getter=isMainMemoryExecutable) BOOL mainMemoryExecutable;
@property(nonatomic, readwrite) uint32_t globalHeapBaseOffset;
@property(nonatomic, readwrite) uint32_t globalHeapCurrentOffset;
@property(nonatomic, readwrite) uint32_t globalHeapTopBaseOffset;
@property(nonatomic, readwrite) uint32_t globalHeapUsedBytes;
@property(nonatomic, readwrite) uint32_t debugHeapBaseOffset;
@property(nonatomic, readwrite) uint32_t symbolTableOffset;
@property(nonatomic, readwrite) uint32_t s7Offset;
@property(nonatomic, readwrite) uint32_t lastSymbolOffset;
@property(nonatomic, readwrite) int32_t symbolCount;
@property(nonatomic, readwrite) NSArray<GOALPadKernelType*>* types;
@end

@implementation GOALPadKernelStatus
@end

@interface GOALPadGameBootStatus ()
@property(nonatomic, readwrite, getter=isBooted) BOOL booted;
@property(nonatomic, readwrite) NSString* message;
@property(nonatomic, readwrite) int32_t kernelObjects;
@property(nonatomic, readwrite) int32_t gameObjects;
@property(nonatomic, readwrite) int32_t codeObjects;
@property(nonatomic, readwrite) int32_t dataObjects;
@property(nonatomic, readwrite) uint32_t kernelVersion;
@property(nonatomic, readwrite) uint32_t globalHeapUsedBytes;
@property(nonatomic, readwrite) int32_t symbolCount;
@property(nonatomic, readwrite, getter=isSoundInstalled) BOOL soundInstalled;
@property(nonatomic, readwrite) int32_t soundSampleRate;
@property(nonatomic, readwrite, getter=isRendererInstalled) BOOL rendererInstalled;
@property(nonatomic, readwrite, getter=didPlay) BOOL played;
@property(nonatomic, readwrite) NSTimeInterval duration;
@end

@implementation GOALPadGameBootStatus
@end

static GOALPadKernelStatus* failed_kernel_status(NSString* message, NSString* data_directory) {
  GOALPadKernelStatus* status = [[GOALPadKernelStatus alloc] init];
  status.running = NO;
  status.message = message;
  status.architecture = architecture_name();
  status.dataDirectory = data_directory ?: @"";
  status.dataDirectoryAccepted = NO;
  status.types = @[];
  return status;
}

static GOALPadGameBootStatus* failed_boot_status(NSString* message, NSTimeInterval duration) {
  GOALPadGameBootStatus* status = [[GOALPadGameBootStatus alloc] init];
  status.booted = NO;
  status.message = message;
  status.soundSampleRate = GOALPadAudioSampleRate();
  status.duration = duration;
  return status;
}

@implementation GOALPadRuntimeBridge

+ (BOOL)selectGame:(GOALPadGameIdentifier)gameIdentifier {
  return gameIdentifier == GOALPadGameIdentifierJak2 ? YES : NO;
}

+ (GOALPadGameIdentifier)activeGameIdentifier {
  return GOALPadGameIdentifierJak2;
}

+ (BOOL)isGameCodeLinkedForGame:(GOALPadGameIdentifier)gameIdentifier {
  return gameIdentifier == GOALPadGameIdentifierJak2 ? YES : NO;
}

+ (GOALPadKernelStatus*)startKernelWithDataDirectory:(NSString*)dataDirectory
                                      savesDirectory:(NSString*)savesDirectory {
  NSString* data_path = dataDirectory ?: @"";
  NSString* saves_path = savesDirectory ?: @"";
  std::lock_guard<std::mutex> lock(g_mutex);

  if (g_state != SessionState::Idle) {
    return failed_kernel_status(@"A Jak II bridge session is already active.", data_path);
  }
  if (data_path.length == 0 || saves_path.length == 0) {
    return failed_kernel_status(@"Jak II requires non-empty prepared-data and save directories.",
                                data_path);
  }
  if (!g_attached_layer) {
    return failed_kernel_status(@"Attach the Metal presentation surface before starting Jak II.",
                                data_path);
  }

  g_data_directory = [data_path copy];
  g_saves_directory = [saves_path copy];
  g_last_error = @"";
  // The shared shell calls bootGame on its boot queue, so real Jak II startup begins there.
  g_state = SessionState::Prepared;
  clear_runtime_snapshots_locked();

  GOALPadKernelStatus* status = [[GOALPadKernelStatus alloc] init];
  status.running = YES;
  status.message = @"Jak II startup is prepared; game boot will initialize the AOT runtime.";
  status.architecture = architecture_name();
  status.dataDirectory = g_data_directory;
  status.dataDirectoryAccepted = YES;
  status.mainMemoryExecutable = NO;
  status.types = @[];
  return status;
}

+ (GOALPadGameBootStatus*)bootGame {
  return [self bootGameWithTargetFrameRate:60];
}

+ (GOALPadGameBootStatus*)bootGameWithTargetFrameRate:(NSInteger)targetFrameRate {
  if (targetFrameRate != 60 && targetFrameRate != 120) {
    return failed_boot_status(@"Jak II supports only 60 or 120 Hz timing.", 0);
  }
  NSString* data_path = nil;
  NSString* saves_path = nil;
  CAMetalLayer* layer = nil;
  goalpad::PresentationGeometry presentation_geometry;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_state != SessionState::Prepared) {
      return failed_boot_status(@"The Jak II bridge is not prepared for boot.", 0);
    }
    g_state = SessionState::Booting;
    data_path = g_data_directory;
    saves_path = g_saves_directory;
    layer = g_attached_layer;
    presentation_geometry = presentation_geometry_locked();
    update_portable_display_locked(presentation_geometry);
  }

  const auto started_at = std::chrono::steady_clock::now();
  goal_jak2_metal_host* host = nullptr;
  NSString* failure = nil;
  goal_jak2_runtime_metrics runtime_metrics = {};
  goal_jak2_metal_host_metrics metal_metrics = {};

  try {
    host = goal_jak2_metal_host_create_presenting(layer);
    if (!host) {
      failure = @"The Jak II Metal presentation host could not be created.";
    }
    if (!failure && !update_metal_presentation_geometry(host, presentation_geometry)) {
      failure = @"The Jak II Metal presentation host rejected the app display geometry.";
    }
    const char* shadow195_capture_tick_value =
        std::getenv("GOALPAD_JAK2_DEBUG_CAPTURE_SHADOW195_FRAME_TICK");
    if (!failure && shadow195_capture_tick_value && shadow195_capture_tick_value[0]) {
      uint64_t shadow195_capture_tick = 0;
      if (!read_positive_u64_environment("GOALPAD_JAK2_DEBUG_CAPTURE_SHADOW195_FRAME_TICK",
                                         &shadow195_capture_tick)) {
        failure = @"GOALPAD_JAK2_DEBUG_CAPTURE_SHADOW195_FRAME_TICK must be a positive integer.";
      } else {
        goal_jak2_shadow195_frame_capture_selector selector = {};
        selector.match = GOAL_JAK2_SHADOW195_CAPTURE_MATCH_HOST_TICK;
        selector.host_tick_id = shadow195_capture_tick;
        if (!goal_jak2_metal_host_arm_shadow195_frame_capture(host, &selector)) {
          failure = @"The requested Jak II Shadow195 frame capture could not be armed.";
        }
      }
    }
    if (!failure &&
        !goal_jak2_metal_host_set_present_pacing(host, 1.0 / targetFrameRate)) {
      failure = string_from_utf8(goal_jak2_metal_host_last_error(host));
    }

    NSString* fr3_path = [data_path stringByAppendingPathComponent:@"fr3"];
    if (!failure &&
        !goal_jak2_metal_host_configure_level_art(host, fr3_path.fileSystemRepresentation)) {
      failure = string_from_utf8(goal_jak2_metal_host_last_error(host));
    }

    goal_gfx_host graphics_host = {};
    if (!failure && !goal_jak2_metal_host_copy_gfx_host(host, &graphics_host)) {
      failure = string_from_utf8(goal_jak2_metal_host_last_error(host));
    }

    if (!failure) {
      goal_jak2_runtime_config config = {};
      config.data_directory = data_path.fileSystemRepresentation;
      config.saves_directory = saves_path.fileSystemRepresentation;
      config.graphics = GOAL_JAK2_RUNTIME_GRAPHICS_EXTERNAL_HOST;
      config.external_gfx_host = &graphics_host;
      config.target_frame_rate = static_cast<int32_t>(targetFrameRate);
      if (goal_jak2_runtime_start(&config) != GOAL_JAK2_RUNTIME_OK) {
        failure = string_from_utf8(goal_jak2_runtime_last_error());
      }
    }

    if (!failure && goal_jak2_runtime_get_metrics(&runtime_metrics) != GOAL_JAK2_RUNTIME_OK) {
      failure = string_from_utf8(goal_jak2_runtime_last_error());
    }
    if (!failure && !goal_jak2_metal_host_get_metrics(host, &metal_metrics)) {
      failure = string_from_utf8(goal_jak2_metal_host_last_error(host));
    }
    const char* preview_scene = std::getenv("GOALPAD_JAK2_DEBUG_PREVIEW_SCENE");
    if (!failure && preview_scene && preview_scene[0] &&
        goal_jak2_runtime_request_scene_preview(preview_scene) != GOAL_JAK2_RUNTIME_OK) {
      failure = string_from_utf8(goal_jak2_runtime_last_error());
    }
  } catch (const std::exception& error) {
    failure = [NSString stringWithFormat:@"Jak II startup threw: %s", error.what()];
  } catch (...) {
    failure = @"Jak II startup threw an unknown exception.";
  }

  const auto elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now() - started_at);
  if (failure) {
    goal_jak2_runtime_shutdown();
    if (host) {
      goal_jak2_metal_host_destroy(host);
    }
    NSString* failure_message = nil;
    {
      std::lock_guard<std::mutex> lock(g_mutex);
      g_state = SessionState::Failed;
      g_last_error = failure.length ? failure : @"The Jak II runtime did not start.";
      failure_message = g_last_error;
      clear_runtime_snapshots_locked();
    }
    g_boot_finished.notify_all();
    return failed_boot_status(failure_message, elapsed.count());
  }

  {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_metal_host = host;
    g_host_layer = layer;
    g_runtime_metrics = runtime_metrics;
    g_metal_metrics = metal_metrics;
    g_target_frame_rate = targetFrameRate;
    g_state = SessionState::Running;
    if (g_attached_layer != g_host_layer) {
      g_last_error = @"The presentation layer changed during Jak II boot; restart the session.";
    } else {
      g_last_error = @"";
    }
  }
  g_boot_finished.notify_all();

  GOALPadGameBootStatus* status = [[GOALPadGameBootStatus alloc] init];
  status.booted = YES;
  status.message = @"Jak II AOT runtime, Metal host, controller, and audio seams started.";
  status.kernelObjects = runtime_metrics.kernel_objects;
  status.gameObjects = runtime_metrics.game_objects;
  status.codeObjects = runtime_metrics.game_code_objects;
  status.dataObjects = runtime_metrics.game_data_objects;
  status.kernelVersion = runtime_metrics.kernel_version;
  status.globalHeapUsedBytes = runtime_metrics.global_heap_used_bytes;
  status.symbolCount = runtime_metrics.symbol_count;
  status.soundInstalled =
      runtime_metrics.sound_version_requests > 0 && runtime_metrics.sound_info_ee != 0;
  status.soundSampleRate = GOALPadAudioSampleRate();
  status.rendererInstalled = YES;
  status.played = YES;
  status.duration = elapsed.count();
  return status;
}

+ (BOOL)setTargetFrameRate:(NSInteger)targetFrameRate {
  std::lock_guard<std::mutex> lock(g_mutex);
  if ((targetFrameRate != 60 && targetFrameRate != 120) ||
      g_state != SessionState::Running || !g_metal_host) {
    return NO;
  }
  if (targetFrameRate == g_target_frame_rate) {
    return YES;
  }
  const NSInteger previousFrameRate = g_target_frame_rate;
  if (!goal_jak2_metal_host_set_present_pacing(g_metal_host, 1.0 / targetFrameRate)) {
    return NO;
  }
  if (goal_jak2_runtime_set_target_frame_rate(static_cast<int32_t>(targetFrameRate)) !=
      GOAL_JAK2_RUNTIME_OK) {
    (void)goal_jak2_metal_host_set_present_pacing(g_metal_host, 1.0 / previousFrameRate);
    return NO;
  }
  g_target_frame_rate = targetFrameRate;
  return YES;
}

+ (BOOL)runFrameAtPresentationTime:(CFTimeInterval)targetPresentationTime {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_state != SessionState::Running) {
    return NO;
  }
  const goal_jak2_runtime_status status = goal_jak2_runtime_tick_at(targetPresentationTime);
  copy_runtime_metrics_locked();
  copy_metal_metrics_locked();
  if (should_log_jak2_diagnostics(g_runtime_metrics.ticks)) {
    log_jak2_diagnostics_locked();
  }
  if (status == GOAL_JAK2_RUNTIME_EXITED) {
    g_state = SessionState::Exited;
    g_last_error = @"Jak II requested a clean runtime exit.";
    return NO;
  }
  if (status != GOAL_JAK2_RUNTIME_OK) {
    g_state = SessionState::Failed;
    g_last_error = string_from_utf8(goal_jak2_runtime_last_error());
    return NO;
  }
  return YES;
}

+ (BOOL)runFrameAtPresentationTime:(CFTimeInterval)targetPresentationTime
                     stateSnapshot:(GOALPadGameFrameStateSnapshot*)stateSnapshot {
  const BOOL ran = [self runFrameAtPresentationTime:targetPresentationTime];
  *stateSnapshot = [self gameFrameStateSnapshot];
  return ran;
}

+ (void)resetFrameTiming {
  std::lock_guard<std::mutex> lock(g_mutex);
  g_frame_armed = false;
  goal_jak2_runtime_reset_frame_timing();
}

+ (uint64_t)framesRun {
  std::lock_guard<std::mutex> lock(g_mutex);
  copy_runtime_metrics_locked();
  return g_runtime_metrics.ticks;
}

+ (BOOL)isGameBooted {
  std::lock_guard<std::mutex> lock(g_mutex);
  return g_state == SessionState::Running && goal_jak2_runtime_is_running();
}

+ (BOOL)exitToLibraryRequested {
  // Jak II has no managed library-exit request contract in this target bridge.
  return NO;
}

+ (GOALPadGameMode)gameMode {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (!copy_runtime_metrics_locked()) {
    return GOALPadGameModeUnknown;
  }
  if (std::strcmp(g_runtime_metrics.master_mode, "game") == 0) {
    return GOALPadGameModeGameplay;
  }
  if (std::strcmp(g_runtime_metrics.master_mode, "pause") == 0) {
    return GOALPadGameModePause;
  }
  if (std::strcmp(g_runtime_metrics.master_mode, "progress") == 0) {
    return GOALPadGameModeProgress;
  }
  if (std::strcmp(g_runtime_metrics.master_mode, "menu") == 0) {
    return GOALPadGameModeMenu;
  }
  return GOALPadGameModeUnknown;
}

+ (GOALPadTitleStartState)titleStartState {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (!copy_runtime_metrics_locked() || std::strcmp(g_runtime_metrics.master_mode, "game") != 0) {
    return GOALPadTitleStartStateUnknown;
  }
  if ((g_runtime_metrics.host_desired_levels[0] ||
       g_runtime_metrics.host_active_levels[0]) &&
      !level_list_contains(g_runtime_metrics.host_desired_levels, "title") &&
      !level_list_contains(g_runtime_metrics.host_active_levels, "title")) {
    return GOALPadTitleStartStateNotAwaiting;
  }
  if (std::strcmp(g_runtime_metrics.title_control_state, "wait") == 0) {
    return GOALPadTitleStartStateAwaiting;
  }
  if (std::strcmp(g_runtime_metrics.title_control_state, "startup") == 0 ||
      std::strcmp(g_runtime_metrics.title_control_state, "idle") == 0 ||
      std::strcmp(g_runtime_metrics.title_control_state, "scrap-book") == 0) {
    return GOALPadTitleStartStateTitleSequence;
  }
  return GOALPadTitleStartStateUnknown;
}

+ (GOALPadLookAroundState)lookAroundState {
  return look_state_from_core(current_player_context_snapshot().look_state);
}

+ (GOALPadJak2TraversalState)jak2TraversalState {
  return traversal_state_from_core(current_player_context_snapshot().traversal);
}

+ (GOALPadSpeederState)speederState {
  return GOALPadSpeederStateUnknown;
}

+ (GOALPadProgressMenuSnapshot)progressMenuSnapshot {
  std::lock_guard<std::mutex> lock(g_mutex);
  goal_jak2_progress_menu_snapshot core = {};
  if (goal_jak2_runtime_get_progress_menu_snapshot(&core) != GOAL_JAK2_RUNTIME_OK ||
      !core.available) {
    return unavailable_progress_snapshot();
  }
  const auto is_bool = [](int32_t value) { return value == 0 || value == 1; };
  if (core.available != 1 || core.screen != GOAL_JAK2_PROGRESS_SCREEN_TITLE ||
      core.starting_screen != GOAL_JAK2_PROGRESS_SCREEN_TITLE || core.option_index < 0 ||
      core.option_index > 4 || !is_bool(core.selected_option) || !is_bool(core.in_transition) ||
      !is_bool(core.navigation_available) || !is_bool(core.can_exit_with_start) ||
      !is_bool(core.can_go_back) || core.can_exit_with_start || core.can_go_back ||
      core.navigation_available == core.in_transition) {
    return unavailable_progress_snapshot();
  }

  GOALPadProgressMenuSnapshot snapshot = {};
  snapshot.available = YES;
  snapshot.screen = GOALPadProgressScreenTitle;
  snapshot.optionIndex = core.option_index;
  snapshot.selectedOption = core.selected_option ? YES : NO;
  snapshot.inTransition = core.in_transition ? YES : NO;
  snapshot.navigationAvailable = core.navigation_available ? YES : NO;
  snapshot.startingScreen = GOALPadProgressScreenTitle;
  return snapshot;
}

+ (GOALPadJak2ProgressMenuSemanticSnapshot)jak2ProgressMenuSemanticSnapshot {
  std::lock_guard<std::mutex> lock(g_mutex);
  goal_jak2_progress_menu_semantic_snapshot core = {};
  if (goal_jak2_runtime_get_progress_menu_semantic_snapshot(&core) !=
          GOAL_JAK2_RUNTIME_OK ||
      !valid_progress_semantic_snapshot(core)) {
    return unavailable_progress_semantic_snapshot();
  }

  GOALPadJak2ProgressMenuSemanticSnapshot snapshot = {};
  snapshot.available = YES;
  snapshot.phase = static_cast<GOALPadJak2ProgressMenuPhase>(core.phase);
  snapshot.optionIndex = core.option_index;
  snapshot.actionMask = core.action_mask;
  return snapshot;
}

+ (GOALPadWarpGateTouchSnapshot)warpGateTouchSnapshot {
  return unavailable_warp_gate_snapshot();
}

+ (GOALPadCutsceneSkipTouchSnapshot)cutsceneSkipTouchSnapshot {
  return unavailable_cutscene_snapshot();
}

+ (GOALPadFacePromptTouchSnapshot)facePromptTouchSnapshot {
  std::lock_guard<std::mutex> lock(g_mutex);
  goal_jak2_face_prompt_touch_snapshot core = {};
  if (g_state != SessionState::Running ||
      goal_jak2_runtime_get_face_prompt_touch_snapshot(&core) != GOAL_JAK2_RUNTIME_OK ||
      !valid_face_prompt_touch_snapshot(core)) {
    return {};
  }

  GOALPadFacePromptTouchSnapshot snapshot = {};
  snapshot.valid = YES;
  snapshot.requestedButtons = core.requested_buttons;
  snapshot.sequence = core.sequence;
  return snapshot;
}

+ (GOALPadGameFrameStateSnapshot)gameFrameStateSnapshot {
  GOALPadGameFrameStateSnapshot snapshot = {};
  snapshot.progressMenu = unavailable_progress_snapshot();
  snapshot.warpGateTouch = unavailable_warp_gate_snapshot();
  snapshot.cutsceneSkipTouch = unavailable_cutscene_snapshot();
  if (![self isGameBooted]) {
    return snapshot;
  }

  snapshot.framesRun = [self framesRun];
  snapshot.gameMode = [self gameMode];
  snapshot.progressMenu = [self progressMenuSnapshot];
  snapshot.titleStartState = [self titleStartState];
  snapshot.warpGateTouch = [self warpGateTouchSnapshot];
  snapshot.cutsceneSkipTouch = [self cutsceneSkipTouchSnapshot];
  snapshot.facePromptTouch = [self facePromptTouchSnapshot];
  const auto player_context = current_player_context_snapshot();
  snapshot.lookAroundState = look_state_from_core(player_context.look_state);
  snapshot.jak2TraversalState = traversal_state_from_core(player_context.traversal);
  snapshot.speederState = [self speederState];
  snapshot.exitToLibraryRequested = NO;
  snapshot.successfulSaveGeneration = kmemcard_successful_save_generation();
  return snapshot;
}

+ (GOALPadFrameChainStats)frameChainStats {
  std::lock_guard<std::mutex> lock(g_mutex);
  copy_metal_metrics_locked();
  GOALPadFrameChainStats result = {};
  result.chains = clamped_int32(g_metal_metrics.chains);
  result.lastPayloadBytes = g_metal_metrics.last_copied_bytes;
  return result;
}

+ (void)stopKernel {
  goal_jak2_metal_host* host = nullptr;
  {
    std::unique_lock<std::mutex> lock(g_mutex);
    g_boot_finished.wait(lock, [] { return g_state != SessionState::Booting; });
    if (g_state == SessionState::Idle) {
      return;
    }
    g_state = SessionState::Stopping;
    host = g_metal_host;
    g_metal_host = nullptr;
  }

  if (host) {
    goal_jak2_metal_host_wait_for_last_frame(host, 1.0, 0);
  }
  goal_jak2_runtime_shutdown();
  if (host) {
    goal_jak2_metal_host_destroy(host);
  }

  {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_host_layer = nil;
    g_data_directory = @"";
    g_saves_directory = @"";
    g_last_error = @"";
    clear_runtime_snapshots_locked();
    g_state = SessionState::Idle;
  }
  g_boot_finished.notify_all();
  NSLog(@"GOALPad Jak II runtime: shut down.");
}

+ (BOOL)isKernelRunning {
  std::lock_guard<std::mutex> lock(g_mutex);
  return bridge_session_is_live(g_state) ? YES : NO;
}

+ (BOOL)isDataSeamLinked {
  return YES;
}

+ (BOOL)isInputSeamLinked {
  return YES;
}

+ (BOOL)isAudioSeamLinked {
  return YES;
}

+ (BOOL)isGameCodeLinked {
  return YES;
}

@end

#pragma mark - Shared controller and audio seams

void GOALPadInputSetState(int32_t port, GOALPadControllerState state) {
  goal_pad_state pad;
  goal_pad_state_neutral(&pad);
  pad.buttons = state.buttons;
  pad.left_x = state.leftX;
  pad.left_y = state.leftY;
  pad.right_x = state.rightX;
  pad.right_y = state.rightY;

  const uint32_t pressure_buttons[GOAL_PAD_PRESSURE_BYTES] = {
      GOAL_PAD_RIGHT,    GOAL_PAD_LEFT,   GOAL_PAD_UP, GOAL_PAD_DOWN,
      GOAL_PAD_TRIANGLE, GOAL_PAD_CIRCLE, GOAL_PAD_X,  GOAL_PAD_SQUARE,
      GOAL_PAD_L1,       GOAL_PAD_R1,     GOAL_PAD_L2, GOAL_PAD_R2,
  };
  for (int index = 0; index < GOAL_PAD_PRESSURE_BYTES; ++index) {
    pad.pressure[index] = (state.buttons & pressure_buttons[index]) ? 255 : 0;
  }
  pad.pressure[10] = state.leftTrigger;
  pad.pressure[11] = state.rightTrigger;
  goal_pad_set_state(port, &pad);
}

void GOALPadInputSetDisconnected(int32_t port) {
  goal_pad_state pad;
  goal_pad_state_neutral(&pad);
  pad.connected = 0;
  goal_pad_set_state(port, &pad);
}

void GOALPadInputSetRumbleEnabled(int32_t port, BOOL enabled) {
  goal_pad_set_rumble_enabled(port, enabled ? 1 : 0);
}

GOALPadRumble GOALPadInputRumble(int32_t port) {
  GOALPadRumble result = {};
  goal_pad_get_rumble(port, &result.large, &result.small);
  return result;
}

int32_t GOALPadInputReadCount(int32_t port) {
  return goal_pad_read_count(port);
}

int32_t GOALPadAudioSampleRate(void) {
  return goal_game_sound_sample_rate();
}

int32_t GOALPadAudioPull(int16_t* out, int32_t frames) {
  if (!out || frames <= 0) {
    return 0;
  }
  return goal_game_sound_pull_audio(out, frames);
}

#pragma mark - Presentation surface

@implementation GOALPadCameraCorrectionTailSnapshot

- (GOALPadCameraCorrectionTailInfo)info {
  return {};
}

- (GOALPadCameraCorrectionTailFrame)frameAtIndex:(uint32_t)index {
  (void)index;
  return {};
}

@end

@implementation GOALPadRenderSurface

+ (GOALPadRenderSurface*)shared {
  static GOALPadRenderSurface* shared = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    shared = [[GOALPadRenderSurface alloc] init];
  });
  return shared;
}

- (void)attachLayer:(CAMetalLayer*)layer {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (layer) {
    layer.framebufferOnly = NO;
  }
  g_attached_layer = layer;
  if (!g_metal_host) {
    g_last_error = @"";
    return;
  }
  if (!layer) {
    g_last_error = @"The Jak II surface is detached; its current host retains the original layer.";
  } else if (layer != g_host_layer) {
    if (goal_jak2_metal_host_rebind_presenting_layer(g_metal_host, layer)) {
      g_host_layer = layer;
      g_last_error = @"";
    } else {
      g_last_error = @"Jak II could not bind the replacement Metal layer.";
    }
  } else {
    g_last_error = @"";
  }
}

- (void)setDrawableSize:(CGSize)size {
  if (size.width < 1 || size.height < 1) {
    return;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  g_drawable_size = size;
  if (g_attached_layer) {
    g_attached_layer.drawableSize = size;
  }
  const auto geometry = presentation_geometry_locked();
  update_portable_display_locked(geometry);
  if (g_metal_host && !update_metal_presentation_geometry(g_metal_host, geometry)) {
    g_last_error = @"Jak II could not apply the updated presentation geometry.";
  }
}

- (void)setInternalResolutionScale:(int32_t)scale {
  // The current Jak II host owns a fixed 640x480 game target.
  (void)scale;
}

- (void)setHorizontalPlusEnabled:(BOOL)enabled {
  std::lock_guard<std::mutex> lock(g_mutex);
  g_horizontal_plus_enabled = enabled;
  const auto geometry = presentation_geometry_locked();
  update_portable_display_locked(geometry);
  if (g_metal_host && !update_metal_presentation_geometry(g_metal_host, geometry)) {
    g_last_error = @"Jak II could not apply the selected presentation geometry.";
  }
}

- (void)setDetailedFrameStatsEnabled:(BOOL)enabled {
  // The Jak II host exposes only its fixed conservative metric set.
  (void)enabled;
}

- (GOALPadSurfaceGeometry)geometry {
  std::lock_guard<std::mutex> lock(g_mutex);
  const auto geometry = presentation_geometry_locked();
  return {
      geometry.drawable_width,  geometry.drawable_height,   geometry.internal_width,
      geometry.internal_height, geometry.draw_region_width, geometry.draw_region_height,
  };
}

- (BOOL)beginFrameAtTime:(CFTimeInterval)presentationTime {
  (void)presentationTime;
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_state != SessionState::Running || !g_metal_host || !g_attached_layer ||
      g_attached_layer != g_host_layer || g_drawable_size.width < 1 || g_drawable_size.height < 1 ||
      !copy_metal_metrics_locked()) {
    g_frame_armed = false;
    return NO;
  }
  g_frame_baseline_chains = g_metal_metrics.chains;
  g_frame_baseline_drawables = g_metal_metrics.drawables_acquired;
  g_frame_baseline_submissions = g_metal_metrics.submissions;
  g_frame_armed = true;
  ++g_frames_armed;
  return YES;
}

- (BOOL)endFrame {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (!g_frame_armed || !copy_metal_metrics_locked()) {
    g_frame_armed = false;
    return NO;
  }
  g_frame_armed = false;
  const uint64_t chains = g_metal_metrics.chains - g_frame_baseline_chains;
  if (chains == 0) {
    ++g_frames_without_chain;
  } else if (chains > 1) {
    ++g_frames_with_multiple_chains;
  }
  g_max_chains_per_frame = std::max(g_max_chains_per_frame, chains);
  return g_metal_metrics.drawables_acquired > g_frame_baseline_drawables &&
         g_metal_metrics.submissions > g_frame_baseline_submissions;
}

- (BOOL)isRendererLinked {
  std::lock_guard<std::mutex> lock(g_mutex);
  return g_metal_host ? YES : NO;
}

- (GOALPadRendererStats)stats {
  std::lock_guard<std::mutex> lock(g_mutex);
  copy_runtime_metrics_locked();
  copy_metal_metrics_locked();
  GOALPadRendererStats result = {};
  result.chainsSent = g_metal_metrics.chains;
  result.chainsRendered = g_metal_metrics.completed_chains;
  result.chainsDropped = g_metal_metrics.failed_chains;
  result.framesArmed = g_frames_armed;
  result.framesWithoutChain = g_frames_without_chain;
  result.framesWithMultipleChains = g_frames_with_multiple_chains;
  result.maxChainsPerFrame = g_max_chains_per_frame;
  result.drawablesAcquired = g_metal_metrics.drawables_acquired;
  result.drawableMisses = g_metal_metrics.drawable_misses;
  result.latePresentSubmissions = g_metal_metrics.late_present_submissions;
  result.submissions = g_metal_metrics.submissions;
  result.presentationsCompleted = g_metal_metrics.presentations;
  result.presentationDrops = g_metal_metrics.presentation_drops;
  result.presentationOrderMismatches = g_metal_metrics.presentation_order_mismatches;
  result.textureUploads = g_metal_metrics.texture_uploads;
  result.levelsLoaded = g_runtime_metrics.host_last_active_level_count;
  result.lastDrawCalls = clamped_int32(g_metal_metrics.draws);
  result.lastTriangles = clamped_int32(g_metal_metrics.triangles);
  result.mercModels = clamped_int32(g_metal_metrics.last_merc_models);
  result.mercDraws = clamped_int32(g_metal_metrics.last_merc_draws);
  result.mercMissingBoneSlots = clamped_int32(g_metal_metrics.last_merc_missing_bone_slots);
  result.mercNonfiniteBoneMatrices =
      clamped_int32(g_metal_metrics.last_merc_nonfinite_bone_matrices);
  result.mercDegenerateBoneMatrices =
      clamped_int32(g_metal_metrics.last_merc_degenerate_bone_matrices);
  result.mercIncoherentBoneSources =
      clamped_int32(g_metal_metrics.last_merc_incoherent_bone_sources);
  result.mercBadBonePointers = g_metal_metrics.last_merc_bad_bone_pointers;
  return result;
}

- (GOALPadCameraCorrectionTailInfo)cameraCorrectionTailInfo {
  return {};
}

- (GOALPadCameraCorrectionTailSnapshot*)cameraCorrectionTailSnapshot {
  return [[GOALPadCameraCorrectionTailSnapshot alloc] init];
}

- (GOALPadTargetControlTelemetry)targetControlTelemetry {
  return {};
}

- (NSString*)levelsWanted {
  std::lock_guard<std::mutex> lock(g_mutex);
  copy_runtime_metrics_locked();
  return string_from_utf8(g_runtime_metrics.host_desired_levels);
}

- (NSString*)levelsLoaded {
  std::lock_guard<std::mutex> lock(g_mutex);
  copy_runtime_metrics_locked();
  return string_from_utf8(g_runtime_metrics.host_active_levels);
}

- (NSString*)lastError {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_last_error.length) {
    return g_last_error;
  }
  if (g_metal_host) {
    return string_from_utf8(goal_jak2_metal_host_last_error(g_metal_host));
  }
  return @"";
}

@end
