#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#import "GOALPadRuntimeBridge.h"

#include "game/graphics/pipelines/metal/metal_jak2_host_bridge.h"
#include "game/kernel/core/jak2_runtime.h"
#include "game/kernel/core/kernel_game.h"
#include "game/kernel/core/pad.h"

struct goal_jak2_metal_host {
  int marker;
};

namespace {

goal_jak2_metal_host g_host = {1};
goal_jak2_runtime_metrics g_runtime = {};
goal_jak2_progress_menu_snapshot g_progress = {};
goal_jak2_progress_menu_semantic_snapshot g_progress_semantic = {};
goal_jak2_progress_menu_diagnostics g_progress_diagnostics = {};
goal_jak2_metal_host_metrics g_metal = {};
goal_pad_state g_pad = {};
int g_pad_port = -1;
bool g_runtime_running = false;
bool g_host_active = false;
bool g_fail_configure = false;
std::string g_data_directory;
std::string g_saves_directory;
std::string g_fr3_directory;
CAMetalLayer* g_created_layer = nil;
std::vector<std::string> g_calls;

void check(bool condition, const char* message) {
  if (!condition) {
    std::fprintf(stderr, "FAILED: %s\n", message);
    std::exit(1);
  }
}

size_t call_index(const char* call) {
  const auto found = std::find(g_calls.begin(), g_calls.end(), call);
  check(found != g_calls.end(), call);
  return static_cast<size_t>(found - g_calls.begin());
}

}  // namespace

extern "C" {

goal_jak2_metal_host* goal_jak2_metal_host_create_presenting(CAMetalLayer* layer) {
  g_calls.emplace_back("create");
  g_created_layer = layer;
  g_host_active = layer != nil;
  return g_host_active ? &g_host : nullptr;
}

int goal_jak2_metal_host_set_present_pacing(goal_jak2_metal_host* host, double seconds) {
  g_calls.emplace_back("pacing");
  return host == &g_host && seconds > 0;
}

int goal_jak2_metal_host_configure_level_art(goal_jak2_metal_host* host,
                                             const char* fr3_directory) {
  g_calls.emplace_back("configure");
  g_fr3_directory = fr3_directory ?: "";
  return host == &g_host && !g_fr3_directory.empty() && !g_fail_configure;
}

int goal_jak2_metal_host_copy_gfx_host(goal_jak2_metal_host* host, goal_gfx_host* out) {
  g_calls.emplace_back("copy");
  if (host != &g_host || !out) {
    return 0;
  }
  *out = {};
  return 1;
}

int goal_jak2_metal_host_get_metrics(goal_jak2_metal_host* host,
                                     goal_jak2_metal_host_metrics* out) {
  if (host != &g_host || !g_host_active || !out) {
    return 0;
  }
  *out = g_metal;
  return 1;
}

int goal_jak2_metal_host_wait_for_last_frame(goal_jak2_metal_host* host,
                                             double timeout_seconds,
                                             int require_presentation) {
  (void)timeout_seconds;
  (void)require_presentation;
  g_calls.emplace_back("wait");
  return host == &g_host;
}

void goal_jak2_metal_host_destroy(goal_jak2_metal_host* host) {
  check(host == &g_host, "destroy received the active host");
  g_calls.emplace_back("destroy");
  g_host_active = false;
}

const char* goal_jak2_metal_host_last_error(goal_jak2_metal_host* host) {
  if (host != &g_host || !g_host_active) {
    return "fake Metal host is inactive";
  }
  return g_fail_configure ? "fake level-art configuration failure" : "";
}

goal_jak2_runtime_status goal_jak2_runtime_start(const goal_jak2_runtime_config* config) {
  g_calls.emplace_back("start");
  if (!config || config->graphics != GOAL_JAK2_RUNTIME_GRAPHICS_EXTERNAL_HOST ||
      !config->external_gfx_host) {
    return GOAL_JAK2_RUNTIME_INVALID_ARGUMENT;
  }
  g_data_directory = config->data_directory ?: "";
  g_saves_directory = config->saves_directory ?: "";
  g_runtime_running = true;
  g_runtime = {};
  g_runtime.state = GOAL_JAK2_RUNTIME_RUNNING;
  g_runtime.kernel_version = 0x40000;
  g_runtime.kernel_objects = 8;
  g_runtime.game_objects = 465;
  g_runtime.game_code_objects = 300;
  g_runtime.game_data_objects = 165;
  g_runtime.global_heap_used_bytes = 1234;
  g_runtime.symbol_count = 567;
  g_runtime.play_boot_result = 1;
  g_runtime.sound_version_requests = 1;
  g_runtime.sound_info_ee = 0x1234;
  g_runtime.host_last_active_level_count = 1;
  std::strcpy(g_runtime.master_mode, "game");
  std::strcpy(g_runtime.title_control_state, "startup");
  std::strcpy(g_runtime.host_desired_levels, "title");
  std::strcpy(g_runtime.host_active_levels, "common+title");
  return GOAL_JAK2_RUNTIME_OK;
}

goal_jak2_runtime_status goal_jak2_runtime_tick(void) {
  if (!g_runtime_running) {
    return GOAL_JAK2_RUNTIME_NOT_RUNNING;
  }
  ++g_runtime.ticks;
  ++g_metal.chains;
  ++g_metal.completed_chains;
  ++g_metal.drawables_acquired;
  ++g_metal.submissions;
  ++g_metal.presentations;
  g_metal.texture_uploads += 2;
  g_metal.draws = 31;
  g_metal.triangles = 47;
  g_metal.last_merc_models = 3;
  g_metal.last_merc_draws = 5;
  g_metal.last_merc_missing_bone_slots = 7;
  g_metal.last_merc_nonfinite_bone_matrices = 11;
  g_metal.last_merc_degenerate_bone_matrices = 13;
  g_metal.last_merc_incoherent_bone_sources = 17;
  g_metal.last_merc_bad_bone_pointers = 19;
  g_metal.last_copied_bytes = 4096;
  return GOAL_JAK2_RUNTIME_OK;
}

goal_jak2_runtime_status goal_jak2_runtime_get_metrics(goal_jak2_runtime_metrics* out) {
  if (!out) {
    return GOAL_JAK2_RUNTIME_INVALID_ARGUMENT;
  }
  *out = g_runtime;
  return GOAL_JAK2_RUNTIME_OK;
}

goal_jak2_runtime_status goal_jak2_runtime_get_progress_menu_snapshot(
    goal_jak2_progress_menu_snapshot* out) {
  if (!out) {
    return GOAL_JAK2_RUNTIME_INVALID_ARGUMENT;
  }
  *out = g_progress;
  return GOAL_JAK2_RUNTIME_OK;
}

goal_jak2_runtime_status goal_jak2_runtime_get_progress_menu_semantic_snapshot(
    goal_jak2_progress_menu_semantic_snapshot* out) {
  if (!out) {
    return GOAL_JAK2_RUNTIME_INVALID_ARGUMENT;
  }
  *out = g_progress_semantic;
  return GOAL_JAK2_RUNTIME_OK;
}

goal_jak2_runtime_status goal_jak2_runtime_get_progress_menu_diagnostics(
    goal_jak2_progress_menu_diagnostics* out) {
  if (!out) {
    return GOAL_JAK2_RUNTIME_INVALID_ARGUMENT;
  }
  *out = g_progress_diagnostics;
  return GOAL_JAK2_RUNTIME_OK;
}

int goal_jak2_runtime_is_running(void) {
  return g_runtime_running;
}

void goal_jak2_runtime_shutdown(void) {
  g_calls.emplace_back("shutdown");
  g_runtime_running = false;
  g_runtime.state = GOAL_JAK2_RUNTIME_STOPPED;
}

const char* goal_jak2_runtime_last_error(void) {
  return "fake runtime failure";
}

void goal_pad_state_neutral(goal_pad_state* out) {
  *out = {};
  out->connected = 1;
  out->left_x = GOAL_PAD_ANALOG_NEUTRAL;
  out->left_y = GOAL_PAD_ANALOG_NEUTRAL;
  out->right_x = GOAL_PAD_ANALOG_NEUTRAL;
  out->right_y = GOAL_PAD_ANALOG_NEUTRAL;
}

goal_kernel_core_status goal_pad_set_state(int port, const goal_pad_state* state) {
  g_pad_port = port;
  g_pad = *state;
  return GOAL_KERNEL_CORE_OK;
}

goal_kernel_core_status goal_pad_get_rumble(int port, uint8_t* large, uint8_t* small) {
  if (port < 0 || !large || !small) {
    return GOAL_KERNEL_CORE_INVALID_ARGUMENT;
  }
  *large = 3;
  *small = 7;
  return GOAL_KERNEL_CORE_OK;
}

int goal_pad_read_count(int port) {
  return port == 0 ? 42 : 0;
}

}  // extern "C"

int goal_game_sound_sample_rate() {
  return 48000;
}

int goal_game_sound_pull_audio(int16_t* out, int frames) {
  if (!out || frames <= 0) {
    return 0;
  }
  std::fill(out, out + frames * 2, int16_t{11});
  return frames;
}

int main() {
  @autoreleasepool {
    GOALPadRenderSurface* surface = GOALPadRenderSurface.shared;
    GOALPadKernelStatus* no_layer =
        [GOALPadRuntimeBridge startKernelWithDataDirectory:@"/tmp/jak2-data"
                                            savesDirectory:@"/tmp/jak2-saves"];
    check(!no_layer.isRunning, "startup rejects a missing presentation layer");

    CAMetalLayer* first_layer = [[CAMetalLayer alloc] init];
    [surface attachLayer:first_layer];
    [surface setDrawableSize:CGSizeMake(1280, 960)];
    GOALPadKernelStatus* prepared =
        [GOALPadRuntimeBridge startKernelWithDataDirectory:@"/tmp/jak2-data"
                                            savesDirectory:@"/tmp/jak2-saves"];
    check(prepared.isRunning, "startup prepares the bridge session");
    check(prepared.isDataDirectoryAccepted, "startup accepts the data directory");
    check([prepared.dataDirectory isEqualToString:@"/tmp/jak2-data"],
          "startup retains the data directory");

    GOALPadGameBootStatus* boot = [GOALPadRuntimeBridge bootGame];
    check(boot.isBooted && boot.didPlay, "boot starts the Jak II runtime");
    check(boot.kernelObjects == 8 && boot.gameObjects == 465,
          "boot publishes runtime object counts");
    check(boot.isRendererInstalled && boot.isSoundInstalled,
          "boot publishes renderer and sound installation");
    check(g_created_layer == first_layer, "boot uses the cached presentation layer");
    check(g_data_directory == "/tmp/jak2-data" && g_saves_directory == "/tmp/jak2-saves",
          "boot passes the cached runtime directories");
    check(g_fr3_directory == "/tmp/jak2-data/fr3", "boot configures the Jak II fr3 directory");
    check(call_index("create") < call_index("pacing") &&
              call_index("pacing") < call_index("configure") &&
              call_index("configure") < call_index("copy") &&
              call_index("copy") < call_index("start"),
          "boot preserves Metal-host setup order");

    check(GOALPadRuntimeBridge.gameMode == GOALPadGameModeGameplay,
          "the shared game mode maps from Jak II metrics");
    check(GOALPadRuntimeBridge.titleStartState == GOALPadTitleStartStateTitleSequence,
          "Jak II title startup keeps Start disabled");
    std::strcpy(g_runtime.title_control_state, "wait");
    check(GOALPadRuntimeBridge.titleStartState == GOALPadTitleStartStateAwaiting,
          "Jak II title wait enables the shared Start control");
    std::strcpy(g_runtime.host_desired_levels, "intro+city");
    std::strcpy(g_runtime.host_active_levels, "common+intro+city");
    check(GOALPadRuntimeBridge.titleStartState == GOALPadTitleStartStateNotAwaiting,
          "leaving the title level enables ordinary gameplay controls");
    std::strcpy(g_runtime.title_control_state, "startup");
    std::strcpy(g_runtime.host_desired_levels, "title");
    std::strcpy(g_runtime.host_active_levels, "common+title");
    std::strcpy(g_runtime.master_mode, "progress");
    g_progress = {1, GOAL_JAK2_PROGRESS_SCREEN_TITLE, 0, 0, 0, 1,
                  GOAL_JAK2_PROGRESS_SCREEN_TITLE, 0, 0};
    GOALPadProgressMenuSnapshot progress = GOALPadRuntimeBridge.progressMenuSnapshot;
    check(progress.available && progress.screen == GOALPadProgressScreenTitle &&
              progress.startingScreen == GOALPadProgressScreenTitle && progress.optionIndex == 0 &&
              !progress.selectedOption && !progress.inTransition && progress.navigationAvailable &&
              !progress.canExitWithStart && !progress.canGoBack,
          "Jak II stable title snapshot enables the shared progress controls");
    g_progress.option_index = 3;
    g_progress.selected_option = 1;
    progress = GOALPadRuntimeBridge.progressMenuSnapshot;
    check(progress.available && progress.optionIndex == 3 && progress.selectedOption,
          "Jak II title selection maps through the shared snapshot ABI");
    g_progress.in_transition = 1;
    g_progress.navigation_available = 0;
    progress = GOALPadRuntimeBridge.progressMenuSnapshot;
    check(progress.available && progress.inTransition && !progress.navigationAvailable,
          "Jak II title transitions remain visible but navigation-disabled");
    g_progress.option_index = 4;
    progress = GOALPadRuntimeBridge.progressMenuSnapshot;
    check(progress.available && progress.optionIndex == 4,
          "Jak II preserves the shipping PC title menu's visible Quit index");
    g_progress.option_index = 5;
    check(!GOALPadRuntimeBridge.progressMenuSnapshot.available,
          "the Objective-C bridge rejects an invalid native title option");
    g_progress = {};

    const auto check_semantic = [](int32_t phase, int32_t option, uint32_t actions,
                                   GOALPadJak2ProgressMenuPhase expected_phase,
                                   const char* message) {
      g_progress_semantic = {1, phase, option, actions};
      const auto semantic = GOALPadRuntimeBridge.jak2ProgressMenuSemanticSnapshot;
      check(semantic.available && semantic.phase == expected_phase &&
                semantic.optionIndex == option && semantic.actionMask == actions,
            message);
    };
    check_semantic(GOAL_JAK2_PROGRESS_MENU_PHASE_SELECT_SAVE_TITLE, 4,
                   GOAL_JAK2_PROGRESS_MENU_ACTION_UP |
                       GOAL_JAK2_PROGRESS_MENU_ACTION_DOWN |
                       GOAL_JAK2_PROGRESS_MENU_ACTION_CONFIRM,
                   GOALPadJak2ProgressMenuPhaseSelectSaveTitle,
                   "the bridge preserves exact five-row save selection semantics");
    check_semantic(GOAL_JAK2_PROGRESS_MENU_PHASE_NO_MEMORY_CARD, 0,
                   GOAL_JAK2_PROGRESS_MENU_ACTION_CONFIRM,
                   GOALPadJak2ProgressMenuPhaseNoMemoryCard,
                   "the bridge preserves title-origin no-card Confirm");
    check_semantic(GOAL_JAK2_PROGRESS_MENU_PHASE_CREATE_GAME, 0,
                   GOAL_JAK2_PROGRESS_MENU_ACTION_LEFT |
                       GOAL_JAK2_PROGRESS_MENU_ACTION_RIGHT |
                       GOAL_JAK2_PROGRESS_MENU_ACTION_CONFIRM,
                   GOALPadJak2ProgressMenuPhaseCreateGame,
                   "the bridge preserves create-game Left, Right, and Confirm");
    check_semantic(GOAL_JAK2_PROGRESS_MENU_PHASE_ALREADY_EXISTS, 0,
                   GOAL_JAK2_PROGRESS_MENU_ACTION_LEFT |
                       GOAL_JAK2_PROGRESS_MENU_ACTION_RIGHT |
                       GOAL_JAK2_PROGRESS_MENU_ACTION_CONFIRM,
                   GOALPadJak2ProgressMenuPhaseExistingSaveOverwrite,
                   "the bridge preserves overwrite Left, Right, and Confirm");
    check_semantic(GOAL_JAK2_PROGRESS_MENU_PHASE_ICON_INFO, 0,
                   GOAL_JAK2_PROGRESS_MENU_ACTION_CONFIRM,
                   GOALPadJak2ProgressMenuPhaseSaveIconInformation,
                   "the bridge preserves save-icon information Confirm");
    check_semantic(GOAL_JAK2_PROGRESS_MENU_PHASE_CREATING, 0,
                   GOAL_JAK2_PROGRESS_MENU_ACTION_NONE,
                   GOALPadJak2ProgressMenuPhaseCreating,
                   "the bridge preserves an inert creating phase");
    check_semantic(GOAL_JAK2_PROGRESS_MENU_PHASE_SAVING, 0,
                   GOAL_JAK2_PROGRESS_MENU_ACTION_NONE,
                   GOALPadJak2ProgressMenuPhaseSaving,
                   "the bridge preserves an inert saving phase");

    g_progress_semantic = {1, GOAL_JAK2_PROGRESS_MENU_PHASE_SELECT_SAVE_TITLE, 5,
                           GOAL_JAK2_PROGRESS_MENU_ACTION_UP |
                               GOAL_JAK2_PROGRESS_MENU_ACTION_DOWN |
                               GOAL_JAK2_PROGRESS_MENU_ACTION_CONFIRM};
    check(!GOALPadRuntimeBridge.jak2ProgressMenuSemanticSnapshot.available,
          "the bridge rejects a sixth save row");
    g_progress_semantic = {1, GOAL_JAK2_PROGRESS_MENU_PHASE_NO_MEMORY_CARD, 0,
                           GOAL_JAK2_PROGRESS_MENU_ACTION_LEFT |
                               GOAL_JAK2_PROGRESS_MENU_ACTION_CONFIRM};
    check(!GOALPadRuntimeBridge.jak2ProgressMenuSemanticSnapshot.available,
          "the bridge rejects an action not proven for the phase");
    g_progress_semantic = {1, 99, 0, GOAL_JAK2_PROGRESS_MENU_ACTION_NONE};
    check(!GOALPadRuntimeBridge.jak2ProgressMenuSemanticSnapshot.available,
          "the bridge rejects an unknown semantic phase");
    g_progress_semantic = {};
    check(!GOALPadRuntimeBridge.warpGateTouchSnapshot.valid &&
              !GOALPadRuntimeBridge.cutsceneSkipTouchSnapshot.valid &&
              !GOALPadRuntimeBridge.facePromptTouchSnapshot.valid,
          "unsupported Jak II touch diagnostics fail closed");

    GOALPadControllerState controller = {};
    controller.buttons = GOALPadButtonCross | GOALPadButtonL2;
    controller.leftX = 10;
    controller.leftY = 20;
    controller.rightX = 30;
    controller.rightY = 40;
    controller.leftTrigger = 99;
    controller.rightTrigger = 101;
    GOALPadInputSetState(0, controller);
    check(g_pad_port == 0 && g_pad.connected && g_pad.buttons == controller.buttons,
          "controller state reaches the shared pad seam");
    check(g_pad.left_x == 10 && g_pad.right_y == 40 && g_pad.pressure[10] == 99 &&
              g_pad.pressure[11] == 101,
          "controller axes and trigger pressure are preserved");
    GOALPadRumble rumble = GOALPadInputRumble(0);
    check(rumble.large == 3 && rumble.small == 7 && GOALPadInputReadCount(0) == 42,
          "rumble and read telemetry use the shared pad seam");
    GOALPadInputSetDisconnected(0);
    check(!g_pad.connected, "controller disconnect reaches the shared pad seam");

    int16_t audio[8] = {};
    check(GOALPadAudioSampleRate() == 48000 && GOALPadAudioPull(audio, 4) == 4 && audio[0] == 11 &&
              audio[7] == 11,
          "audio uses the shared mixer seam");

    check([surface beginFrameAtTime:1.0], "the attached running surface arms a frame");
    check([GOALPadRuntimeBridge runFrameAtPresentationTime:1.0],
          "the runtime bridge ticks one frame");
    check([surface endFrame], "the surface reports a submitted drawable");
    check(GOALPadRuntimeBridge.framesRun == 1, "the runtime frame counter advances");
    GOALPadRendererStats stats = surface.stats;
    check(stats.chainsSent == 1 && stats.chainsRendered == 1 && stats.submissions == 1 &&
              stats.presentationsCompleted == 1 && stats.textureUploads == 2,
          "the surface maps conservative Jak II renderer counters");
    check(stats.lastDrawCalls == 31 && stats.lastTriangles == 47 && stats.mercModels == 3 &&
              stats.mercDraws == 5 && stats.mercMissingBoneSlots == 7 &&
              stats.mercNonfiniteBoneMatrices == 11 && stats.mercDegenerateBoneMatrices == 13 &&
              stats.mercIncoherentBoneSources == 17 && stats.mercBadBonePointers == 19,
          "the surface maps like-for-like Jak II draw and Merc health counters");
    check([surface.levelsWanted isEqualToString:@"title"] &&
              [surface.levelsLoaded isEqualToString:@"common+title"],
          "the surface maps Jak II level-set names");

    CAMetalLayer* replacement_layer = [[CAMetalLayer alloc] init];
    [surface attachLayer:replacement_layer];
    [surface setDrawableSize:CGSizeMake(1280, 960)];
    check(![surface beginFrameAtTime:2.0], "a live host rejects a replacement layer");
    check([surface.lastError containsString:@"restart"],
          "replacement-layer rejection explains the required restart");
    [surface attachLayer:first_layer];
    [GOALPadRuntimeBridge resetFrameTiming];

    GOALPadCameraCorrectionTailSnapshot* tail = surface.cameraCorrectionTailSnapshot;
    check(!tail.info.valid && ![tail frameAtIndex:0].valid,
          "Jak I camera diagnostics return explicit empty snapshots");
    check(!surface.targetControlTelemetry.lastObservation.valid,
          "Jak I target diagnostics return explicit empty telemetry");

    [GOALPadRuntimeBridge stopKernel];
    check(!GOALPadRuntimeBridge.isKernelRunning && !g_runtime_running && !g_host_active,
          "shutdown clears the bridge, runtime, and host");
    check(call_index("wait") < call_index("shutdown") &&
              call_index("shutdown") < call_index("destroy"),
          "shutdown quiesces frames and stops the runtime before destroying its host");

    g_calls.clear();
    g_fail_configure = true;
    [surface attachLayer:first_layer];
    GOALPadKernelStatus* retry =
        [GOALPadRuntimeBridge startKernelWithDataDirectory:@"/tmp/jak2-data"
                                            savesDirectory:@"/tmp/jak2-saves"];
    check(retry.isRunning, "a clean bridge can prepare another session");
    GOALPadGameBootStatus* failed_boot = [GOALPadRuntimeBridge bootGame];
    check(!failed_boot.isBooted && [failed_boot.message containsString:@"configuration failure"],
          "Metal configuration failure is reported without starting gameplay");
    check(!GOALPadRuntimeBridge.isKernelRunning && !g_runtime_running && !g_host_active,
          "failed boot preserves no live runtime or host");
    check(call_index("configure") < call_index("shutdown") &&
              call_index("shutdown") < call_index("destroy"),
          "failed boot stops the runtime before destroying its host");
    [GOALPadRuntimeBridge stopKernel];
    g_fail_configure = false;

    std::puts("EcoJak2RuntimeBridgeTest: PASS");
  }
  return 0;
}
