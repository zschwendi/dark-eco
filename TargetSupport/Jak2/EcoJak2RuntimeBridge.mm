#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <limits>
#include <mutex>
#include <string>

#include "GOALPadPresentationGeometry.hpp"
#import "GOALPadRuntimeBridge.h"

#include "game/graphics/pipelines/metal/metal_jak2_host_bridge.h"
#include "game/kernel/core/jak2_runtime.h"
#include "game/kernel/core/kernel_game.h"
#include "game/kernel/core/pad.h"

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
CGSize g_drawable_size = CGSizeZero;
bool g_frame_armed = false;
uint64_t g_frame_baseline_chains = 0;
uint64_t g_frame_baseline_drawables = 0;
uint64_t g_frame_baseline_submissions = 0;
uint64_t g_frames_armed = 0;
uint64_t g_frames_without_chain = 0;
uint64_t g_frames_with_multiple_chains = 0;
uint64_t g_max_chains_per_frame = 0;

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

void clear_runtime_snapshots_locked() {
  g_runtime_metrics = {};
  g_metal_metrics = {};
  g_frame_armed = false;
  g_frame_baseline_chains = 0;
  g_frame_baseline_drawables = 0;
  g_frame_baseline_submissions = 0;
  g_frames_armed = 0;
  g_frames_without_chain = 0;
  g_frames_with_multiple_chains = 0;
  g_max_chains_per_frame = 0;
}

GOALPadProgressMenuSnapshot unavailable_progress_snapshot() {
  GOALPadProgressMenuSnapshot snapshot = {};
  snapshot.screen = GOALPadProgressScreenUnknown;
  snapshot.startingScreen = GOALPadProgressScreenUnknown;
  return snapshot;
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
  NSString* data_path = nil;
  NSString* saves_path = nil;
  CAMetalLayer* layer = nil;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_state != SessionState::Prepared) {
      return failed_boot_status(@"The Jak II bridge is not prepared for boot.", 0);
    }
    g_state = SessionState::Booting;
    data_path = g_data_directory;
    saves_path = g_saves_directory;
    layer = g_attached_layer;
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
    if (!failure && !goal_jak2_metal_host_set_present_pacing(host, 1.0 / 60.0)) {
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

+ (BOOL)runFrameAtPresentationTime:(CFTimeInterval)targetPresentationTime {
  (void)targetPresentationTime;
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_state != SessionState::Running) {
    return NO;
  }
  const goal_jak2_runtime_status status = goal_jak2_runtime_tick();
  copy_runtime_metrics_locked();
  copy_metal_metrics_locked();
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

+ (void)resetFrameTiming {
  std::lock_guard<std::mutex> lock(g_mutex);
  g_frame_armed = false;
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
  return GOALPadTitleStartStateUnknown;
}

+ (GOALPadLookAroundState)lookAroundState {
  return GOALPadLookAroundStateUnknown;
}

+ (GOALPadSpeederState)speederState {
  return GOALPadSpeederStateUnknown;
}

+ (GOALPadProgressMenuSnapshot)progressMenuSnapshot {
  return unavailable_progress_snapshot();
}

+ (GOALPadWarpGateTouchSnapshot)warpGateTouchSnapshot {
  return unavailable_warp_gate_snapshot();
}

+ (GOALPadCutsceneSkipTouchSnapshot)cutsceneSkipTouchSnapshot {
  return unavailable_cutscene_snapshot();
}

+ (GOALPadFacePromptTouchSnapshot)facePromptTouchSnapshot {
  return {};
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
    g_last_error = @"Jak II cannot replace a live Metal layer; stop and restart the session.";
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
}

- (void)setInternalResolutionScale:(int32_t)scale {
  // The current Jak II host owns a fixed 640x480 game target.
  (void)scale;
}

- (void)setHorizontalPlusEnabled:(BOOL)enabled {
  // The current Jak II host exposes only its audited 4:3 draw region.
  (void)enabled;
}

- (GOALPadSurfaceGeometry)geometry {
  std::lock_guard<std::mutex> lock(g_mutex);
  const auto geometry =
      goalpad::presentation_geometry(static_cast<int32_t>(g_drawable_size.width),
                                     static_cast<int32_t>(g_drawable_size.height), 1, false);
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
