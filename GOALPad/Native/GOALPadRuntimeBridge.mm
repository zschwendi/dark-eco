#import "GOALPadRuntimeBridge.h"

#include "GOALPadMetalHost.hpp"

#include "GOALPadEngineSeams.h"
#include "GOALPadGameBoot.hpp"
#include "GOALPadRuntimeCore.hpp"

#include <algorithm>
#include <string>

#if GOALPAD_HAVE_PAD_SEAM
// The app's button bits are the game's button bits. If either side ever moves, this build stops
// rather than silently sending Jak the wrong buttons.
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
#endif

@interface GOALPadKernelType ()
@property(nonatomic, readwrite) NSString *symbolName;
@property(nonatomic, readwrite) NSString *typeName;
@property(nonatomic, readwrite) NSString *parentName;
@property(nonatomic, readwrite) uint32_t typeOffset;
@property(nonatomic, readwrite) uint32_t allocatedSize;
@property(nonatomic, readwrite) uint32_t methodCount;
@end

@implementation GOALPadKernelType
@end

@interface GOALPadKernelStatus ()
@property(nonatomic, readwrite, getter=isRunning) BOOL running;
@property(nonatomic, readwrite) NSString *message;
@property(nonatomic, readwrite) NSString *architecture;
@property(nonatomic, readwrite) NSString *dataDirectory;
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
@property(nonatomic, readwrite) NSArray<GOALPadKernelType *> *types;
@end

@implementation GOALPadKernelStatus
@end

@interface GOALPadGameBootStatus ()
@property(nonatomic, readwrite, getter=isBooted) BOOL booted;
@property(nonatomic, readwrite) NSString *message;
@property(nonatomic, readwrite) int32_t kernelObjects;
@property(nonatomic, readwrite) int32_t gameObjects;
@property(nonatomic, readwrite) int32_t codeObjects;
@property(nonatomic, readwrite) int32_t dataObjects;
@property(nonatomic, readwrite) uint32_t kernelVersion;
@property(nonatomic, readwrite) uint32_t globalHeapUsedBytes;
@property(nonatomic, readwrite) int32_t symbolCount;
@property(nonatomic, readwrite, getter=isRendererInstalled) BOOL rendererInstalled;
@property(nonatomic, readwrite, getter=isSoundInstalled) BOOL soundInstalled;
@property(nonatomic, readwrite) int32_t soundSampleRate;
@property(nonatomic, readwrite, getter=didPlay) BOOL played;
@property(nonatomic, readwrite) NSTimeInterval duration;
@end

@implementation GOALPadGameBootStatus
@end

/// Kernel strings come out of the GOAL heap, so never hand Swift a nil for a nonnull property.
static NSString *GOALPadString(const std::string &value) {
  NSString *string = [NSString stringWithUTF8String:value.c_str()];
  return string ?: @"";
}

static GOALPadKernelStatus *GOALPadFailedStatus(NSString *message, NSString *dataDirectory) {
  GOALPadKernelStatus *status = [[GOALPadKernelStatus alloc] init];
  status.running = NO;
  status.message = message;
  status.architecture = @"";
  status.dataDirectory = dataDirectory ?: @"";
  status.types = @[];
  NSLog(@"GOALPad kernel: %@", message);
  return status;
}

static GOALPadGameMode GOALPadGameModeFromCore(goalpad::GameMode mode) {
  switch (mode) {
    case goalpad::GameMode::Gameplay:
      return GOALPadGameModeGameplay;
    case goalpad::GameMode::Pause:
      return GOALPadGameModePause;
    case goalpad::GameMode::Progress:
      return GOALPadGameModeProgress;
    case goalpad::GameMode::Menu:
      return GOALPadGameModeMenu;
    case goalpad::GameMode::Unknown:
      return GOALPadGameModeUnknown;
  }
}

static GOALPadTitleStartState GOALPadTitleStartStateFromCore(goalpad::TitleStartState state) {
  switch (state) {
    case goalpad::TitleStartState::Awaiting:
      return GOALPadTitleStartStateAwaiting;
    case goalpad::TitleStartState::TitleOpening:
      return GOALPadTitleStartStateTitleOpening;
    case goalpad::TitleStartState::TitleSequence:
      return GOALPadTitleStartStateTitleSequence;
    case goalpad::TitleStartState::NotAwaiting:
      return GOALPadTitleStartStateNotAwaiting;
    case goalpad::TitleStartState::Unknown:
      return GOALPadTitleStartStateUnknown;
  }
}

static GOALPadLookAroundState GOALPadLookAroundStateFromCore(goalpad::LookAroundState state) {
  switch (state) {
    case goalpad::LookAroundState::Normal:
      return GOALPadLookAroundStateNormal;
    case goalpad::LookAroundState::FirstPerson:
      return GOALPadLookAroundStateFirstPerson;
    case goalpad::LookAroundState::Unknown:
      return GOALPadLookAroundStateUnknown;
  }
}

static GOALPadSpeederState GOALPadSpeederStateFromCore(goalpad::SpeederState state) {
  switch (state) {
    case goalpad::SpeederState::Riding:
      return GOALPadSpeederStateRiding;
    case goalpad::SpeederState::NotRiding:
      return GOALPadSpeederStateNotRiding;
    case goalpad::SpeederState::Unknown:
      return GOALPadSpeederStateUnknown;
  }
}

static GOALPadProgressMenuSnapshot GOALPadProgressMenuSnapshotFromCore(
    const goalpad::ProgressMenuSnapshot &core) {
  GOALPadProgressMenuSnapshot snapshot = {
      core.available ? YES : NO,
      core.available ? static_cast<GOALPadProgressScreen>(core.screen)
                     : GOALPadProgressScreenUnknown,
      core.option_index,
      core.selected_option ? YES : NO,
      core.in_transition ? YES : NO,
      core.navigation_available ? YES : NO,
      core.navigation_available ? static_cast<GOALPadProgressScreen>(core.starting_screen)
                                : GOALPadProgressScreenUnknown,
      core.can_exit_with_start ? YES : NO,
      core.can_go_back ? YES : NO,
  };
  return snapshot;
}

static GOALPadWarpGateTouchSnapshot GOALPadWarpGateTouchSnapshotFromCore(
    const goalpad::WarpGateTouchSnapshot &core) {
  GOALPadWarpGateTouchSnapshot snapshot = {
      core.valid ? YES : NO,
      core.sequence,
      core.valid ? static_cast<GOALPadWarpGateTouchState>(core.state)
                 : GOALPadWarpGateTouchStateUnavailable,
      core.selected_slot,
      core.permitted_mask,
      core.selection_moving ? YES : NO,
  };
  return snapshot;
}

static GOALPadCutsceneSkipTouchSnapshot GOALPadCutsceneSkipTouchSnapshotFromCore(
    const goalpad::CutsceneSkipTouchSnapshot &core) {
  GOALPadCutsceneSkipTouchSnapshot snapshot = {
      core.valid ? YES : NO,
      core.sequence,
      core.valid ? static_cast<GOALPadCutsceneSkipTouchState>(core.state)
                 : GOALPadCutsceneSkipTouchStateUnavailable,
  };
  return snapshot;
}

static GOALPadFacePromptTouchSnapshot GOALPadFacePromptTouchSnapshotFromCore(
    const goalpad::FacePromptTouchSnapshot &core) {
  GOALPadFacePromptTouchSnapshot snapshot = {
      core.valid ? YES : NO,
      core.valid ? core.requested_buttons : 0,
      core.sequence,
  };
  return snapshot;
}

static GOALPadGameFrameStateSnapshot GOALPadGameFrameStateSnapshotFromCore(
    const goalpad::GameFrameStateSnapshot &core) {
  GOALPadGameFrameStateSnapshot snapshot = {};
  snapshot.exitToLibraryRequested = core.exit_to_library_requested ? YES : NO;
  snapshot.framesRun = core.frames_run;
  snapshot.successfulSaveGeneration = core.successful_save_generation;
  snapshot.gameMode = GOALPadGameModeFromCore(core.game_mode);
  snapshot.progressMenu = GOALPadProgressMenuSnapshotFromCore(core.progress_menu);
  snapshot.titleStartState = GOALPadTitleStartStateFromCore(core.title_start_state);
  snapshot.warpGateTouch = GOALPadWarpGateTouchSnapshotFromCore(core.warp_gate_touch);
  snapshot.cutsceneSkipTouch = GOALPadCutsceneSkipTouchSnapshotFromCore(core.cutscene_skip_touch);
  snapshot.facePromptTouch = GOALPadFacePromptTouchSnapshotFromCore(core.face_prompt_touch);
  snapshot.lookAroundState = GOALPadLookAroundStateFromCore(core.look_around_state);
  snapshot.speederState = GOALPadSpeederStateFromCore(core.speeder_state);
  return snapshot;
}

@implementation GOALPadRuntimeBridge

+ (GOALPadKernelStatus *)startKernelWithDataDirectory:(NSString *)dataDirectory
                                      savesDirectory:(NSString *)savesDirectory {
  NSString *path = dataDirectory ?: @"";
  NSString *savePath = savesDirectory ?: @"";

  // goalpad::start_kernel is noexcept and reports failure in its status, but the conversions below
  // allocate, so nothing C++ is allowed to escape into Objective-C either way.
  goalpad::KernelStatus core;
  try {
    core = goalpad::start_kernel(path.UTF8String ?: "", savePath.UTF8String ?: "");
  } catch (...) {
    goalpad::stop_kernel();
    return GOALPadFailedStatus(@"The native kernel bridge threw; no session is live.", path);
  }

  GOALPadKernelStatus *status = [[GOALPadKernelStatus alloc] init];
  status.running = core.running;
  status.message = GOALPadString(core.message);
  status.architecture = GOALPadString(core.architecture);
  status.dataDirectory = GOALPadString(core.data_directory);
  status.dataDirectoryAccepted = core.data_directory_accepted;
  status.mainMemoryAddress = core.main_memory_address;
  status.mainMemorySize = core.main_memory_size;
  status.mainMemoryExecutable = core.main_memory_executable;
  status.globalHeapBaseOffset = core.global_heap_base;
  status.globalHeapCurrentOffset = core.global_heap_current;
  status.globalHeapTopBaseOffset = core.global_heap_top_base;
  status.globalHeapUsedBytes = core.global_heap_used_bytes;
  status.debugHeapBaseOffset = core.debug_heap_base;
  status.symbolTableOffset = core.symbol_table;
  status.s7Offset = core.s7;
  status.lastSymbolOffset = core.last_symbol;
  status.symbolCount = core.symbol_count;

  NSMutableArray<GOALPadKernelType *> *types = [NSMutableArray arrayWithCapacity:core.types.size()];
  for (const auto &coreType : core.types) {
    GOALPadKernelType *type = [[GOALPadKernelType alloc] init];
    type.symbolName = GOALPadString(coreType.symbol_name);
    type.typeName = GOALPadString(coreType.type_name);
    type.parentName = GOALPadString(coreType.parent_name);
    type.typeOffset = coreType.type_offset;
    type.allocatedSize = coreType.allocated_size;
    type.methodCount = coreType.method_count;
    [types addObject:type];
  }
  status.types = types;

  NSLog(@"GOALPad kernel: %@ (arch=%@, s7=#x%08x, symbols=%d, PROT_EXEC=%@, data=%@)",
        status.message, status.architecture, status.s7Offset, status.symbolCount,
        status.isMainMemoryExecutable ? @"yes" : @"no",
        status.isDataDirectoryAccepted ? status.dataDirectory : @"not connected");
  return status;
}

+ (GOALPadGameBootStatus *)bootGame {
  return [self bootGameWithTargetFrameRate:60];
}

+ (GOALPadGameBootStatus *)bootGameWithTargetFrameRate:(NSInteger)targetFrameRate {
  goalpad::BootStatus core;
  try {
    core = goalpad::boot_game(static_cast<int>(targetFrameRate));
  } catch (...) {
    core = goalpad::BootStatus();
    core.message = "The native boot threw; no game is running.";
  }

  GOALPadGameBootStatus *status = [[GOALPadGameBootStatus alloc] init];
  status.booted = core.booted;
  status.message = GOALPadString(core.message);
  status.kernelObjects = core.kernel_objects;
  status.gameObjects = core.game_objects;
  status.codeObjects = core.code_objects;
  status.dataObjects = core.data_objects;
  status.kernelVersion = core.kernel_version;
  status.globalHeapUsedBytes = core.global_heap_used_bytes;
  status.symbolCount = core.symbol_count;
  status.rendererInstalled = core.renderer_installed;
  status.soundInstalled = core.sound_installed;
  status.soundSampleRate = core.sound_sample_rate;
  status.played = core.played;
  status.duration = core.seconds;
  return status;
}

+ (BOOL)setTargetFrameRate:(NSInteger)targetFrameRate {
  return goalpad::set_target_frame_rate(static_cast<int>(targetFrameRate)) ? YES : NO;
}

+ (BOOL)runFrameAtPresentationTime:(CFTimeInterval)targetPresentationTime {
  return goalpad::run_frame(targetPresentationTime) ? YES : NO;
}

+ (BOOL)runFrameAtPresentationTime:(CFTimeInterval)targetPresentationTime
                     stateSnapshot:(GOALPadGameFrameStateSnapshot *)stateSnapshot {
  goalpad::GameFrameStateSnapshot core;
  const bool ran = goalpad::run_frame(targetPresentationTime, &core);
  *stateSnapshot = GOALPadGameFrameStateSnapshotFromCore(core);
  return ran ? YES : NO;
}

+ (void)resetFrameTiming {
  goalpad::reset_frame_timing();
}

+ (uint64_t)framesRun {
  return goalpad::frames_run();
}

+ (BOOL)isGameBooted {
  return goalpad::game_is_booted() ? YES : NO;
}

+ (BOOL)exitToLibraryRequested {
  return goalpad::exit_to_library_requested() ? YES : NO;
}

+ (GOALPadGameMode)gameMode {
  return GOALPadGameModeFromCore(goalpad::game_mode());
}

+ (GOALPadTitleStartState)titleStartState {
  return GOALPadTitleStartStateFromCore(goalpad::title_start_state());
}

+ (GOALPadLookAroundState)lookAroundState {
  return GOALPadLookAroundStateFromCore(goalpad::look_around_state());
}

+ (GOALPadSpeederState)speederState {
  return GOALPadSpeederStateFromCore(goalpad::speeder_state());
}

+ (GOALPadProgressMenuSnapshot)progressMenuSnapshot {
  return GOALPadProgressMenuSnapshotFromCore(goalpad::progress_menu_snapshot());
}

+ (GOALPadJak2ProgressMenuSemanticSnapshot)jak2ProgressMenuSemanticSnapshot {
  GOALPadJak2ProgressMenuSemanticSnapshot snapshot = {};
  snapshot.phase = GOALPadJak2ProgressMenuPhaseUnavailable;
  snapshot.optionIndex = -1;
  return snapshot;
}

+ (GOALPadWarpGateTouchSnapshot)warpGateTouchSnapshot {
  return GOALPadWarpGateTouchSnapshotFromCore(goalpad::warp_gate_touch_snapshot());
}

+ (GOALPadCutsceneSkipTouchSnapshot)cutsceneSkipTouchSnapshot {
  return GOALPadCutsceneSkipTouchSnapshotFromCore(goalpad::cutscene_skip_touch_snapshot());
}

+ (GOALPadFacePromptTouchSnapshot)facePromptTouchSnapshot {
  return GOALPadFacePromptTouchSnapshotFromCore(goalpad::face_prompt_touch_snapshot());
}

+ (GOALPadGameFrameStateSnapshot)gameFrameStateSnapshot {
  return GOALPadGameFrameStateSnapshotFromCore(goalpad::game_frame_state_snapshot());
}

+ (GOALPadFrameChainStats)frameChainStats {
  const auto core = goalpad::frame_chain_stats();
  GOALPadFrameChainStats stats = {core.chains, core.last_payload_bytes,
                                  core.largest_payload_bytes, core.last_texture_uploads};
  return stats;
}

+ (void)stopKernel {
  goalpad::reset_game();
  goalpad::metal_host_stop();
  goalpad::stop_kernel();
  NSLog(@"GOALPad kernel: shut down.");
}

+ (BOOL)isKernelRunning {
  return goalpad::kernel_is_running() ? YES : NO;
}

+ (BOOL)isDataSeamLinked {
  return GOALPAD_HAVE_DATA_SEAM ? YES : NO;
}

+ (BOOL)isInputSeamLinked {
  return GOALPAD_HAVE_PAD_SEAM ? YES : NO;
}

+ (BOOL)isAudioSeamLinked {
  return GOALPAD_HAVE_SOUND_SEAM ? YES : NO;
}

+ (BOOL)isGameCodeLinked {
  return GOALPAD_HAVE_GAME_BOOT ? YES : NO;
}

@end

#pragma mark - Controller input

void GOALPadInputSetState(int32_t port, GOALPadControllerState state) {
#if GOALPAD_HAVE_PAD_SEAM
  goal_pad_state pad;
  goal_pad_state_neutral(&pad);
  pad.buttons = state.buttons;
  pad.left_x = state.leftX;
  pad.left_y = state.leftY;
  pad.right_x = state.rightX;
  pad.right_y = state.rightY;

  // The DualShock 2 pressure bytes, in the order `hw-cpad`'s `abutton` reports them. Jak 1 reads
  // the digital word rather than these, so full pressure for a held button is enough; the two
  // triggers are the only ones the app has a real analog value for.
  const uint32_t pressure_button[GOAL_PAD_PRESSURE_BYTES] = {
      GOAL_PAD_RIGHT, GOAL_PAD_LEFT,   GOAL_PAD_UP, GOAL_PAD_DOWN,
      GOAL_PAD_TRIANGLE, GOAL_PAD_CIRCLE, GOAL_PAD_X,  GOAL_PAD_SQUARE,
      GOAL_PAD_L1,    GOAL_PAD_R1,     GOAL_PAD_L2, GOAL_PAD_R2};
  for (int i = 0; i < GOAL_PAD_PRESSURE_BYTES; ++i) {
    pad.pressure[i] = (state.buttons & pressure_button[i]) ? 255 : 0;
  }
  pad.pressure[10] = state.leftTrigger;
  pad.pressure[11] = state.rightTrigger;

  goal_pad_set_state(port, &pad);
#else
  (void)port;
  (void)state;
#endif
}

void GOALPadInputSetDisconnected(int32_t port) {
#if GOALPAD_HAVE_PAD_SEAM
  goal_pad_state pad;
  goal_pad_state_neutral(&pad);
  pad.connected = 0;
  goal_pad_set_state(port, &pad);
#else
  (void)port;
#endif
}

void GOALPadInputSetRumbleEnabled(int32_t port, BOOL enabled) {
#if GOALPAD_HAVE_PAD_SEAM
  goal_pad_set_rumble_enabled(port, enabled ? 1 : 0);
#else
  (void)port;
  (void)enabled;
#endif
}

GOALPadRumble GOALPadInputRumble(int32_t port) {
  GOALPadRumble rumble = {0, 0};
#if GOALPAD_HAVE_PAD_SEAM
  uint8_t large = 0;
  uint8_t small = 0;
  if (goal_pad_take_rumble(port, &large, &small) == GOAL_KERNEL_CORE_OK) {
    rumble.large = large;
    rumble.small = small;
  }
#else
  (void)port;
#endif
  return rumble;
}

int32_t GOALPadInputReadCount(int32_t port) {
#if GOALPAD_HAVE_PAD_SEAM
  return goal_pad_read_count(port);
#else
  (void)port;
  return 0;
#endif
}

#pragma mark - Audio output

int32_t GOALPadAudioSampleRate(void) {
#if GOALPAD_HAVE_SOUND_SEAM
  return goal_game_sound_sample_rate();
#else
  // The rate the engine's mixer runs at, so the device is opened at the right rate before the seam
  // lands and does not have to be reopened afterwards.
  return 48000;
#endif
}

int32_t GOALPadAudioPull(int16_t *out, int32_t frames) {
#if GOALPAD_HAVE_SOUND_SEAM
  return goal_game_sound_pull_audio(out, frames);
#else
  (void)out;
  (void)frames;
  return 0;
#endif
}
