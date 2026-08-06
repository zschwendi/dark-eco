#pragma once

#include "GOALPadCameraCorrectionTrace.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <string>

namespace goalpad {

enum class GameMode : std::uint8_t {
  Unknown,
  Gameplay,
  Pause,
  Progress,
  Menu,
};

enum class LookAroundState : std::uint8_t {
  Unknown,
  Normal,
  FirstPerson,
};

// Jak 1's original progress display states. PC-only states continue through 66; they remain valid
// native snapshots but deliberately have no touch semantics until their responders are proven.
enum class ProgressScreen : std::int32_t {
  Invalid = -1,
  FuelCells = 0,
  PrecursorOrbs = 1,
  ScoutFlies = 2,
  Settings = 3,
  GameSettings = 4,
  GraphicSettings = 5,
  SoundSettings = 6,
  MemoryCardNoSpace = 7,
  MemoryCardNotInserted = 8,
  MemoryCardNotFormatted = 9,
  MemoryCardFormat = 10,
  MemoryCardDataExists = 11,
  Loading = 12,
  Saving = 13,
  Formatting = 14,
  Creating = 15,
  LoadGame = 16,
  SaveGame = 17,
  SaveGameTitle = 18,
  Insert = 19,
  ErrorLoading = 20,
  ErrorSaving = 21,
  Removed = 22,
  NoData = 23,
  ErrorFormatting = 24,
  ErrorCreating = 25,
  AutoSaveError = 26,
  Title = 27,
  SettingsTitle = 28,
  AutoSave = 29,
  PalChange = 30,
  PalNow = 31,
  NoDisc = 32,
  BadDisc = 33,
  Quit = 34,
};

struct ProgressMenuSnapshot {
  bool available = false;
  ProgressScreen screen = ProgressScreen::Invalid;
  std::int32_t option_index = -1;
  bool selected_option = false;
  bool in_transition = false;
};

namespace progress_layout {

// The GOAL :offset-assert values include the four-byte basic-object tag. A basic pointer starts
// immediately after it, so every native field offset subtracts four.
constexpr std::size_t kDisplayStateOffset = 128 - 4;
constexpr std::size_t kOptionIndexOffset = 144 - 4;
constexpr std::size_t kSelectedOptionOffset = 148 - 4;
constexpr std::size_t kInTransitionOffset = 172 - 4;
constexpr std::size_t kRequiredObjectBytes = kInTransitionOffset + sizeof(std::uint32_t);
constexpr std::int64_t kMinimumScreen = -1;
constexpr std::int64_t kMaximumScreenExclusive = 67;

}  // namespace progress_layout

/*! Read a Jak 1 `progress` through `*progress-process*` without advancing or mutating GOAL. */
inline ProgressMenuSnapshot read_progress_menu_snapshot(const void* memory,
                                                         std::size_t memory_bytes,
                                                         std::size_t low_protect_bytes,
                                                         std::uint32_t goal_false,
                                                         std::uint32_t goal_true,
                                                         std::uint32_t progress_ppointer,
                                                         std::uint32_t expected_type) noexcept {
  ProgressMenuSnapshot snapshot;
  std::uint32_t progress_offset = 0;
  if (!goal_true || goal_true == goal_false ||
      !camera_correction_trace::resolve_goal_ppointer(
          memory, memory_bytes, low_protect_bytes, goal_false, progress_ppointer,
          &progress_offset)) {
    return snapshot;
  }

  const void* progress = camera_correction_trace::checked_goal_object(
      memory, memory_bytes, low_protect_bytes, progress_offset, expected_type,
      progress_layout::kRequiredObjectBytes, nullptr);
  if (!progress) {
    return snapshot;
  }

  const auto* bytes = static_cast<const std::uint8_t*>(progress);
  std::int64_t screen = 0;
  std::int32_t option_index = 0;
  std::uint32_t selected_option = 0;
  std::uint32_t in_transition = 0;
  std::memcpy(&screen, bytes + progress_layout::kDisplayStateOffset, sizeof(screen));
  std::memcpy(&option_index, bytes + progress_layout::kOptionIndexOffset, sizeof(option_index));
  std::memcpy(&selected_option, bytes + progress_layout::kSelectedOptionOffset,
              sizeof(selected_option));
  std::memcpy(&in_transition, bytes + progress_layout::kInTransitionOffset,
              sizeof(in_transition));

  const auto is_goal_boolean = [goal_false, goal_true](std::uint32_t value) {
    return value == goal_false || value == goal_true;
  };
  if (screen < progress_layout::kMinimumScreen ||
      screen >= progress_layout::kMaximumScreenExclusive || option_index < 0 ||
      !is_goal_boolean(selected_option) || !is_goal_boolean(in_transition)) {
    return snapshot;
  }

  snapshot.available = true;
  snapshot.screen = static_cast<ProgressScreen>(screen);
  snapshot.option_index = option_index;
  snapshot.selected_option = selected_option == goal_true;
  snapshot.in_transition = in_transition == goal_true;
  return snapshot;
}

// `state-flags` declares `first-person-mode` as bit 9 in Jak 1's game-h.gc.
constexpr std::uint32_t kJak1FirstPersonModeFlag = 1u << 9;

constexpr LookAroundState classify_look_around_state(bool state_available,
                                                     std::uint32_t state_flags,
                                                     std::uint32_t camera_user_mode,
                                                     std::uint32_t look_around_mode) noexcept {
  if (!state_available || !look_around_mode) {
    return LookAroundState::Unknown;
  }
  if ((state_flags & kJak1FirstPersonModeFlag) == 0) {
    return LookAroundState::Normal;
  }
  return camera_user_mode == look_around_mode ? LookAroundState::FirstPerson
                                               : LookAroundState::Unknown;
}

constexpr GameMode classify_game_mode(std::uint32_t current,
                                      std::uint32_t gameplay,
                                      std::uint32_t pause,
                                      std::uint32_t progress,
                                      std::uint32_t menu) noexcept {
  if (!current) {
    return GameMode::Unknown;
  }
  if (current == gameplay) {
    return GameMode::Gameplay;
  }
  if (current == pause) {
    return GameMode::Pause;
  }
  if (current == progress) {
    return GameMode::Progress;
  }
  if (current == menu) {
    return GameMode::Menu;
  }
  return GameMode::Unknown;
}

/*! What the boot did, read out of the live kernel. */
struct BootStatus {
  bool booted = false;
  std::string message;

  int kernel_objects = 0;
  int game_objects = 0;
  int code_objects = 0;
  int data_objects = 0;
  std::uint32_t kernel_version = 0;
  std::uint32_t global_heap_used_bytes = 0;
  std::int32_t symbol_count = 0;

  bool sound_installed = false;
  int sound_sample_rate = 0;

  /*! Whether the Metal renderer answered the machine layer's graphics functions. When it did not,
   *  the frame's DMA chain is only measured and nothing is drawn. */
  bool renderer_installed = false;

  bool played = false;
  double seconds = 0;
};

/*!
 * Boot Jak 1 the way the game boots: KERNEL.CGO, then the machine layer this port has - the pad,
 * the DGO and STR RPCs, the sound RPC - then GAME.CGO, then the engine's own `play`. Every object
 * file's code comes from the ahead-of-time C the app was built with; every object file's data comes
 * off the player's own disc image.
 *
 * The kernel must already be up (`start_kernel`) and pointed at the data directory. Takes seconds,
 * so call it off the main thread; nothing else may touch the kernel while it runs. Never throws.
 */
BootStatus boot_game() noexcept;

/*!
 * Run one frame of the game: the GOAL kernel's own `kernel-dispatcher`, which runs every process
 * and state, and then the overlord's vblank work, which is what moves the music along. This is
 * `KernelCheckAndDispatch`'s loop body without the listener half.
 *
 * False if the game is not booted. Never throws.
 */
bool run_frame(double target_presentation_time) noexcept;

/*! Drop display-link history so the first frame after a lifecycle pause starts at ratio 1. */
void reset_frame_timing() noexcept;

/*! The camera state that the current dispatcher frame will copy into its background packets. */
struct CameraFrameIdentity {
  std::uint64_t engine_frame_id = 0;
  bool camera_valid = false;
  std::array<std::uint8_t, 80> camera = {};
  bool render_camera_valid = false;
  std::array<std::uint8_t, 240> render_camera = {};
  camera_correction_trace::FrameSnapshot camera_correction;
};
CameraFrameIdentity current_camera_frame_identity() noexcept;

std::uint64_t frames_run() noexcept;
bool game_is_booted() noexcept;
/*! Jak's own `*master-mode*`, read without advancing or mutating the game. */
GameMode game_mode() noexcept;
/*! Jak's live target state; Billy and unavailable or inconsistent state remain unknown. */
LookAroundState look_around_state() noexcept;
/*! Jak's live progress state. Malformed, absent, and internally inconsistent state is unavailable. */
ProgressMenuSnapshot progress_menu_snapshot() noexcept;

/*! Forget the boot. The heap goes away with the kernel; this only drops what this file caches. */
void reset_game() noexcept;

/*! The DMA payload the last frame's chain carried, and the largest any frame has carried. Zero
 *  until a frame has built a chain. This is the measurement seam, not a renderer. */
struct FrameChainStats {
  int chains = 0;
  std::uint32_t last_payload_bytes = 0;
  std::uint32_t largest_payload_bytes = 0;
  int last_texture_uploads = 0;
};
FrameChainStats frame_chain_stats() noexcept;

}  // namespace goalpad
