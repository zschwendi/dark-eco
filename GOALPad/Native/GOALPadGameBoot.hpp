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

enum class TitleStartState : std::uint8_t {
  Unknown,
  NotAwaiting,
  Awaiting,
  TitleOpening,
  TitleSequence,
};

enum class LookAroundState : std::uint8_t {
  Unknown,
  Normal,
  FirstPerson,
};

enum class SpeederState : std::uint8_t {
  Unknown,
  NotRiding,
  Riding,
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
  bool navigation_available = false;
  ProgressScreen starting_screen = ProgressScreen::Invalid;
  bool can_exit_with_start = false;
  bool can_go_back = false;
};

enum class WarpGateTouchState : std::int32_t {
  Unavailable = 0,
  CircleUseAvailable = 1,
  DestinationListActive = 2,
  Transitioning = 3,
};

struct WarpGateTouchSnapshot {
  bool valid = false;
  std::uint32_t sequence = 0;
  WarpGateTouchState state = WarpGateTouchState::Unavailable;
  std::int32_t selected_slot = -1;
  std::uint32_t permitted_mask = 0;
  bool selection_moving = false;
};

enum class CutsceneSkipTouchState : std::int32_t {
  Unavailable = 0,
  TriangleQueryAvailable = 1,
  CreditsTriangleAvailable = 2,
};

struct CutsceneSkipTouchSnapshot {
  bool valid = false;
  std::uint32_t sequence = 0;
  CutsceneSkipTouchState state = CutsceneSkipTouchState::Unavailable;
};

namespace cutscene_skip_touch_layout {

// checked_goal_object returns the bytes after the basic object's four-byte type tag.
constexpr std::size_t kRevisionOffset = 0;
constexpr std::size_t kSequenceOffset = 4;
constexpr std::size_t kStateOffset = 8;
constexpr std::size_t kOwnerOffset = 12;
constexpr std::size_t kHeartbeatOffset = 20;
constexpr std::size_t kRequiredObjectBytes = 0x18;
constexpr std::int32_t kRevision = 2;
constexpr std::uint64_t kMaximumStaleFrames = 2;

}  // namespace cutscene_skip_touch_layout

struct CutsceneSkipTouchRawSnapshot {
  bool valid = false;
  std::uint32_t sequence = 0;
  CutsceneSkipTouchState state = CutsceneSkipTouchState::Unavailable;
  std::uint64_t owner = 0;
  std::uint32_t heartbeat = 0;
};

inline CutsceneSkipTouchRawSnapshot validate_cutscene_skip_touch_snapshot(
    std::int32_t first_sequence,
    std::int32_t revision,
    std::int32_t state_value,
    std::uint64_t owner,
    std::int32_t heartbeat,
    std::int32_t final_sequence) noexcept {
  CutsceneSkipTouchRawSnapshot snapshot;
  if (revision != cutscene_skip_touch_layout::kRevision ||
      first_sequence != final_sequence ||
      (static_cast<std::uint32_t>(first_sequence) & 1u) != 0) {
    return snapshot;
  }

  const auto state = static_cast<CutsceneSkipTouchState>(state_value);
  switch (state) {
    case CutsceneSkipTouchState::Unavailable:
      if (owner != 0 || heartbeat != 0) {
        return snapshot;
      }
      break;
    case CutsceneSkipTouchState::TriangleQueryAvailable:
    case CutsceneSkipTouchState::CreditsTriangleAvailable:
      if (owner == 0) {
        return snapshot;
      }
      break;
    default:
      return snapshot;
  }

  snapshot.valid = true;
  snapshot.sequence = static_cast<std::uint32_t>(first_sequence);
  snapshot.state = state;
  snapshot.owner = owner;
  snapshot.heartbeat = static_cast<std::uint32_t>(heartbeat);
  return snapshot;
}

inline std::int32_t read_cutscene_skip_touch_field(const volatile std::uint8_t* bytes,
                                                   std::size_t offset) noexcept {
  std::int32_t value = 0;
  auto* value_bytes = reinterpret_cast<std::uint8_t*>(&value);
  for (std::size_t index = 0; index < sizeof(value); ++index) {
    value_bytes[index] = bytes[offset + index];
  }
  return value;
}

inline std::uint64_t read_cutscene_skip_touch_owner(const volatile std::uint8_t* bytes,
                                                    std::size_t offset) noexcept {
  std::uint64_t value = 0;
  auto* value_bytes = reinterpret_cast<std::uint8_t*>(&value);
  for (std::size_t index = 0; index < sizeof(value); ++index) {
    value_bytes[index] = bytes[offset + index];
  }
  return value;
}

inline CutsceneSkipTouchRawSnapshot read_cutscene_skip_touch_raw_snapshot(
    const void* memory,
    std::size_t memory_bytes,
    std::size_t low_protect_bytes,
    std::uint32_t object_offset,
    std::uint32_t expected_type) noexcept {
  const void* object = camera_correction_trace::checked_goal_object(
      memory, memory_bytes, low_protect_bytes, object_offset, expected_type,
      cutscene_skip_touch_layout::kRequiredObjectBytes, nullptr);
  if (!object) {
    return {};
  }

  const auto* bytes = static_cast<const volatile std::uint8_t*>(object);
  const auto first_sequence =
      read_cutscene_skip_touch_field(bytes, cutscene_skip_touch_layout::kSequenceOffset);
  const auto revision =
      read_cutscene_skip_touch_field(bytes, cutscene_skip_touch_layout::kRevisionOffset);
  const auto state =
      read_cutscene_skip_touch_field(bytes, cutscene_skip_touch_layout::kStateOffset);
  const auto owner =
      read_cutscene_skip_touch_owner(bytes, cutscene_skip_touch_layout::kOwnerOffset);
  const auto heartbeat =
      read_cutscene_skip_touch_field(bytes, cutscene_skip_touch_layout::kHeartbeatOffset);
  const auto final_sequence =
      read_cutscene_skip_touch_field(bytes, cutscene_skip_touch_layout::kSequenceOffset);
  return validate_cutscene_skip_touch_snapshot(first_sequence, revision, state, owner, heartbeat,
                                               final_sequence);
}

class CutsceneSkipTouchReader {
 public:
  CutsceneSkipTouchSnapshot read(const void* memory,
                                 std::size_t memory_bytes,
                                 std::size_t low_protect_bytes,
                                 std::uint32_t object_offset,
                                 std::uint32_t expected_type,
                                 std::uint64_t current_frame) noexcept {
    const auto raw = read_cutscene_skip_touch_raw_snapshot(
        memory, memory_bytes, low_protect_bytes, object_offset, expected_type);
    if (!raw.valid) {
      return {};
    }

    CutsceneSkipTouchSnapshot snapshot;
    snapshot.valid = true;
    snapshot.sequence = raw.sequence;
    snapshot.state = raw.state;
    if (raw.state == CutsceneSkipTouchState::Unavailable) {
      reset_freshness();
      return snapshot;
    }

    if (!has_freshness_ || raw.sequence != sequence_ || raw.owner != owner_ ||
        raw.heartbeat != heartbeat_ || current_frame < last_refresh_frame_) {
      has_freshness_ = true;
      sequence_ = raw.sequence;
      owner_ = raw.owner;
      heartbeat_ = raw.heartbeat;
      last_refresh_frame_ = current_frame;
      return snapshot;
    }

    if (current_frame - last_refresh_frame_ >
        cutscene_skip_touch_layout::kMaximumStaleFrames) {
      return {};
    }
    return snapshot;
  }

  void reset() noexcept {
    reset_freshness();
  }

 private:
  void reset_freshness() noexcept {
    has_freshness_ = false;
    sequence_ = 0;
    owner_ = 0;
    heartbeat_ = 0;
    last_refresh_frame_ = 0;
  }

  bool has_freshness_ = false;
  std::uint32_t sequence_ = 0;
  std::uint64_t owner_ = 0;
  std::uint32_t heartbeat_ = 0;
  std::uint64_t last_refresh_frame_ = 0;
};

struct FacePromptTouchSnapshot {
  bool valid = false;
  std::uint32_t sequence = 0;
  std::uint32_t requested_buttons = 0;
};

namespace face_prompt_touch_layout {

// checked_goal_object returns the bytes after the basic object's four-byte type tag.
constexpr std::size_t kRevisionOffset = 0;
constexpr std::size_t kSequenceOffset = 4;
constexpr std::size_t kRequestedButtonsOffset = 8;
constexpr std::size_t kOwnerOffset = 12;
constexpr std::size_t kHeartbeatOffset = 20;
constexpr std::size_t kRequiredObjectBytes = 0x18;
constexpr std::int32_t kRevision = 1;
constexpr std::uint32_t kTriangleButton = 1u << 12;
constexpr std::uint32_t kCircleButton = 1u << 13;
constexpr std::uint32_t kCrossButton = 1u << 14;
constexpr std::uint32_t kSquareButton = 1u << 15;
constexpr std::uint32_t kFaceButtonMask =
    kTriangleButton | kCircleButton | kCrossButton | kSquareButton;
constexpr std::uint64_t kMaximumStaleFrames = 2;

}  // namespace face_prompt_touch_layout

struct FacePromptTouchRawSnapshot {
  bool valid = false;
  std::uint32_t sequence = 0;
  std::uint32_t requested_buttons = 0;
  std::uint64_t owner = 0;
  std::uint32_t heartbeat = 0;
};

inline FacePromptTouchRawSnapshot validate_face_prompt_touch_snapshot(
    std::int32_t first_sequence,
    std::int32_t revision,
    std::int32_t requested_buttons_value,
    std::uint64_t owner,
    std::int32_t heartbeat,
    std::int32_t final_sequence) noexcept {
  FacePromptTouchRawSnapshot snapshot;
  const auto requested_buttons = static_cast<std::uint32_t>(requested_buttons_value);
  if (revision != face_prompt_touch_layout::kRevision ||
      first_sequence != final_sequence ||
      (static_cast<std::uint32_t>(first_sequence) & 1u) != 0 || owner == 0 ||
      requested_buttons == 0 ||
      (requested_buttons & ~face_prompt_touch_layout::kFaceButtonMask) != 0) {
    return snapshot;
  }

  snapshot.valid = true;
  snapshot.sequence = static_cast<std::uint32_t>(first_sequence);
  snapshot.requested_buttons = requested_buttons;
  snapshot.owner = owner;
  snapshot.heartbeat = static_cast<std::uint32_t>(heartbeat);
  return snapshot;
}

inline bool face_prompt_touch_symbols_available(std::uint32_t snapshot_symbol,
                                                bool type_symbol_found,
                                                std::uint32_t snapshot_type) noexcept {
  return snapshot_symbol != 0 && type_symbol_found && snapshot_type != 0;
}

inline std::int32_t read_face_prompt_touch_field(const volatile std::uint8_t* bytes,
                                                 std::size_t offset) noexcept {
  std::int32_t value = 0;
  auto* value_bytes = reinterpret_cast<std::uint8_t*>(&value);
  for (std::size_t index = 0; index < sizeof(value); ++index) {
    value_bytes[index] = bytes[offset + index];
  }
  return value;
}

inline std::uint64_t read_face_prompt_touch_owner(const volatile std::uint8_t* bytes,
                                                  std::size_t offset) noexcept {
  std::uint64_t value = 0;
  auto* value_bytes = reinterpret_cast<std::uint8_t*>(&value);
  for (std::size_t index = 0; index < sizeof(value); ++index) {
    value_bytes[index] = bytes[offset + index];
  }
  return value;
}

inline FacePromptTouchRawSnapshot read_face_prompt_touch_raw_snapshot(
    const void* memory,
    std::size_t memory_bytes,
    std::size_t low_protect_bytes,
    std::uint32_t object_offset,
    std::uint32_t expected_type) noexcept {
  const void* object = camera_correction_trace::checked_goal_object(
      memory, memory_bytes, low_protect_bytes, object_offset, expected_type,
      face_prompt_touch_layout::kRequiredObjectBytes, nullptr);
  if (!object) {
    return {};
  }

  const auto* bytes = static_cast<const volatile std::uint8_t*>(object);
  const auto first_sequence =
      read_face_prompt_touch_field(bytes, face_prompt_touch_layout::kSequenceOffset);
  const auto revision =
      read_face_prompt_touch_field(bytes, face_prompt_touch_layout::kRevisionOffset);
  const auto requested_buttons =
      read_face_prompt_touch_field(bytes, face_prompt_touch_layout::kRequestedButtonsOffset);
  const auto owner =
      read_face_prompt_touch_owner(bytes, face_prompt_touch_layout::kOwnerOffset);
  const auto heartbeat =
      read_face_prompt_touch_field(bytes, face_prompt_touch_layout::kHeartbeatOffset);
  const auto final_sequence =
      read_face_prompt_touch_field(bytes, face_prompt_touch_layout::kSequenceOffset);
  return validate_face_prompt_touch_snapshot(first_sequence, revision, requested_buttons, owner,
                                             heartbeat, final_sequence);
}

class FacePromptTouchReader {
 public:
  FacePromptTouchSnapshot read(const void* memory,
                               std::size_t memory_bytes,
                               std::size_t low_protect_bytes,
                               std::uint32_t object_offset,
                               std::uint32_t expected_type,
                               std::uint64_t current_frame) noexcept {
    const auto raw = read_face_prompt_touch_raw_snapshot(
        memory, memory_bytes, low_protect_bytes, object_offset, expected_type);
    if (!raw.valid) {
      reset();
      return {};
    }

    if (!has_sample_ || raw.sequence != sequence_ || raw.owner != owner_ ||
        raw.requested_buttons != requested_buttons_ || current_frame < sample_frame_) {
      has_sample_ = true;
      freshness_confirmed_ = false;
      sequence_ = raw.sequence;
      owner_ = raw.owner;
      requested_buttons_ = raw.requested_buttons;
      heartbeat_ = raw.heartbeat;
      sample_frame_ = current_frame;
      last_refresh_frame_ = current_frame;
      return {};
    }

    if (current_frame == sample_frame_) {
      return {};
    }

    if (raw.heartbeat != heartbeat_) {
      freshness_confirmed_ = true;
      heartbeat_ = raw.heartbeat;
      last_refresh_frame_ = current_frame;
    } else if (!freshness_confirmed_ ||
               current_frame - last_refresh_frame_ >
                   face_prompt_touch_layout::kMaximumStaleFrames) {
      return {};
    }

    FacePromptTouchSnapshot snapshot;
    snapshot.valid = true;
    snapshot.sequence = raw.sequence;
    snapshot.requested_buttons = raw.requested_buttons;
    return snapshot;
  }

  void reset() noexcept {
    has_sample_ = false;
    freshness_confirmed_ = false;
    sequence_ = 0;
    owner_ = 0;
    requested_buttons_ = 0;
    heartbeat_ = 0;
    sample_frame_ = 0;
    last_refresh_frame_ = 0;
  }

 private:
  bool has_sample_ = false;
  bool freshness_confirmed_ = false;
  std::uint32_t sequence_ = 0;
  std::uint64_t owner_ = 0;
  std::uint32_t requested_buttons_ = 0;
  std::uint32_t heartbeat_ = 0;
  std::uint64_t sample_frame_ = 0;
  std::uint64_t last_refresh_frame_ = 0;
};

namespace warp_gate_touch_layout {

// checked_goal_object returns the bytes after the basic object's four-byte type tag.
constexpr std::size_t kRevisionOffset = 0;
constexpr std::size_t kSequenceOffset = 4;
constexpr std::size_t kStateOffset = 8;
constexpr std::size_t kSelectedSlotOffset = 12;
constexpr std::size_t kPermittedMaskOffset = 16;
constexpr std::size_t kSelectionMovingOffset = 20;
constexpr std::size_t kRequiredObjectBytes = 0x18;
constexpr std::int32_t kRevision = 1;
constexpr std::int32_t kDestinationCount = 5;
constexpr std::uint32_t kDestinationMask = (1u << kDestinationCount) - 1u;

}  // namespace warp_gate_touch_layout

inline WarpGateTouchSnapshot validate_warp_gate_touch_snapshot(
    std::int32_t first_sequence,
    std::int32_t revision,
    std::int32_t state_value,
    std::int32_t selected_slot,
    std::int32_t permitted_mask,
    std::int32_t selection_moving,
    std::int32_t final_sequence) noexcept {
  WarpGateTouchSnapshot snapshot;
  if (revision != warp_gate_touch_layout::kRevision || first_sequence != final_sequence ||
      (static_cast<std::uint32_t>(first_sequence) & 1u) != 0) {
    return snapshot;
  }

  const auto state = static_cast<WarpGateTouchState>(state_value);
  switch (state) {
    case WarpGateTouchState::Unavailable:
    case WarpGateTouchState::CircleUseAvailable:
    case WarpGateTouchState::Transitioning:
      if (selected_slot != -1 || permitted_mask != 0 || selection_moving != 0) {
        return snapshot;
      }
      break;
    case WarpGateTouchState::DestinationListActive: {
      if (selected_slot < 0 || selected_slot >= warp_gate_touch_layout::kDestinationCount ||
          permitted_mask <= 0 ||
          (static_cast<std::uint32_t>(permitted_mask) &
           ~warp_gate_touch_layout::kDestinationMask) != 0 ||
          (static_cast<std::uint32_t>(permitted_mask) & (1u << selected_slot)) == 0 ||
          (selection_moving != 0 && selection_moving != 1)) {
        return snapshot;
      }
      break;
    }
    default:
      return snapshot;
  }

  snapshot.valid = true;
  snapshot.sequence = static_cast<std::uint32_t>(first_sequence);
  snapshot.state = state;
  snapshot.selected_slot = selected_slot;
  snapshot.permitted_mask = static_cast<std::uint32_t>(permitted_mask);
  snapshot.selection_moving = selection_moving == 1;
  return snapshot;
}

inline std::int32_t read_warp_gate_touch_field(const volatile std::uint8_t* bytes,
                                               std::size_t offset) noexcept {
  std::int32_t value = 0;
  auto* value_bytes = reinterpret_cast<std::uint8_t*>(&value);
  for (std::size_t index = 0; index < sizeof(value); ++index) {
    value_bytes[index] = bytes[offset + index];
  }
  return value;
}

/*! Read the GOAL-owned warp-gate publication without advancing or mutating GOAL. */
inline WarpGateTouchSnapshot read_warp_gate_touch_snapshot(const void* memory,
                                                           std::size_t memory_bytes,
                                                           std::size_t low_protect_bytes,
                                                           std::uint32_t object_offset,
                                                           std::uint32_t expected_type) noexcept {
  const void* object = camera_correction_trace::checked_goal_object(
      memory, memory_bytes, low_protect_bytes, object_offset, expected_type,
      warp_gate_touch_layout::kRequiredObjectBytes, nullptr);
  if (!object) {
    return {};
  }

  const auto* bytes = static_cast<const volatile std::uint8_t*>(object);
  const auto first_sequence =
      read_warp_gate_touch_field(bytes, warp_gate_touch_layout::kSequenceOffset);
  const auto revision =
      read_warp_gate_touch_field(bytes, warp_gate_touch_layout::kRevisionOffset);
  const auto state = read_warp_gate_touch_field(bytes, warp_gate_touch_layout::kStateOffset);
  const auto selected_slot =
      read_warp_gate_touch_field(bytes, warp_gate_touch_layout::kSelectedSlotOffset);
  const auto permitted_mask =
      read_warp_gate_touch_field(bytes, warp_gate_touch_layout::kPermittedMaskOffset);
  const auto selection_moving =
      read_warp_gate_touch_field(bytes, warp_gate_touch_layout::kSelectionMovingOffset);
  const auto final_sequence =
      read_warp_gate_touch_field(bytes, warp_gate_touch_layout::kSequenceOffset);
  return validate_warp_gate_touch_snapshot(first_sequence, revision, state, selected_slot,
                                           permitted_mask, selection_moving, final_sequence);
}

namespace progress_layout {

// The GOAL :offset-assert values include the four-byte basic-object tag. A basic pointer starts
// immediately after it, so every native field offset subtracts four.
constexpr std::size_t kDisplayStateOffset = 128 - 4;
constexpr std::size_t kOptionIndexOffset = 144 - 4;
constexpr std::size_t kSelectedOptionOffset = 148 - 4;
constexpr std::size_t kInTransitionOffset = 172 - 4;
constexpr std::size_t kRequiredObjectBytes = kInTransitionOffset + sizeof(std::uint32_t);
constexpr std::size_t kNextStateOffset = 76 - 4;
constexpr std::size_t kStartingStateOffset = 24 - 4;
constexpr std::size_t kStartingStateRequiredObjectBytes =
    kStartingStateOffset + sizeof(std::int64_t);
constexpr std::size_t kStateNameOffset = 4 - 4;
constexpr std::size_t kStateRequiredObjectBytes = kStateNameOffset + sizeof(std::uint32_t);
constexpr std::int64_t kMinimumScreen = -1;
constexpr std::int64_t kMaximumScreenExclusive = 67;

constexpr bool is_known_screen(std::int64_t screen) noexcept {
  return screen >= kMinimumScreen && screen < kMaximumScreenExclusive;
}

constexpr bool can_exit_with_start(std::int64_t screen,
                                   std::int64_t starting_screen,
                                   bool selected_option,
                                   bool in_transition,
                                   bool next_state_is_progress_normal) noexcept {
  if (selected_option || in_transition || !next_state_is_progress_normal) {
    return false;
  }
  if (screen >= 0 && screen <= 2) {
    return true;
  }
  const bool supported_origin =
      (starting_screen >= 0 && starting_screen <= 2) || starting_screen == 27 ||
      starting_screen == 64;
  if (!supported_origin) {
    return false;
  }
  switch (screen) {
    case 3:
    case 4:
    case 5:
    case 6:
    case 27:
    case 28:
    case 35:
    case 36:
    case 37:
    case 38:
    case 39:
    case 40:
    case 41:
    case 42:
    case 43:
    case 44:
    case 45:
    case 46:
    case 47:
    case 49:
    case 50:
    case 51:
    case 53:
    case 55:
    case 59:
    case 62:
    case 63:
    case 64:
    case 65:
    case 66:
      return true;
    default:
      return false;
  }
}

}  // namespace progress_layout

namespace live_state_layout {

constexpr std::size_t kProcessStateOffset = 56 - 4;
constexpr std::size_t kProcessNextStateOffset = 76 - 4;
constexpr std::size_t kStateNameOffset = 4 - 4;
constexpr std::size_t kProcessRequiredObjectBytes =
    kProcessNextStateOffset + sizeof(std::uint32_t);
constexpr std::size_t kStateRequiredObjectBytes = kStateNameOffset + sizeof(std::uint32_t);

}  // namespace live_state_layout

inline std::uint32_t read_process_state_name(const void* memory,
                                             std::size_t memory_bytes,
                                             std::size_t low_protect_bytes,
                                             std::uint32_t process_offset,
                                             std::uint32_t process_type,
                                             std::uint32_t state_type,
                                             bool read_next_state) noexcept {
  const void* process = camera_correction_trace::checked_goal_object(
      memory, memory_bytes, low_protect_bytes, process_offset, process_type,
      live_state_layout::kProcessRequiredObjectBytes, nullptr);
  if (!process) {
    return 0;
  }
  const auto state_field_offset = read_next_state ? live_state_layout::kProcessNextStateOffset
                                                  : live_state_layout::kProcessStateOffset;
  std::uint32_t state_offset = 0;
  std::memcpy(&state_offset, static_cast<const std::uint8_t*>(process) + state_field_offset,
              sizeof(state_offset));
  const void* state = camera_correction_trace::checked_goal_object(
      memory, memory_bytes, low_protect_bytes, state_offset, state_type,
      live_state_layout::kStateRequiredObjectBytes, nullptr);
  if (!state) {
    return 0;
  }
  std::uint32_t state_name = 0;
  std::memcpy(&state_name,
              static_cast<const std::uint8_t*>(state) + live_state_layout::kStateNameOffset,
              sizeof(state_name));
  return state_name;
}

template <std::size_t StateCount>
constexpr SpeederState classify_speeder_state(
    std::uint32_t state_name,
    const std::array<std::uint32_t, StateCount>& riding_state_names) noexcept {
  if (!state_name) {
    return SpeederState::Unknown;
  }
  for (const auto candidate : riding_state_names) {
    if (!candidate) {
      return SpeederState::Unknown;
    }
  }
  for (const auto candidate : riding_state_names) {
    if (state_name == candidate) {
      return SpeederState::Riding;
    }
  }
  return SpeederState::NotRiding;
}

inline TitleStartState read_title_start_state(const void* memory,
                                              std::size_t memory_bytes,
                                              std::size_t low_protect_bytes,
                                              std::uint32_t target_offset,
                                              std::uint32_t target_type,
                                              std::uint32_t state_type,
                                              std::uint32_t target_title_wait_symbol,
                                              std::uint32_t target_title_symbol,
                                              std::uint32_t target_title_play_symbol) noexcept {
  if (!target_title_wait_symbol || !target_title_symbol || !target_title_play_symbol) {
    return TitleStartState::Unknown;
  }
  const auto state_name = read_process_state_name(
      memory, memory_bytes, low_protect_bytes, target_offset, target_type, state_type, false);
  if (!state_name) {
    return TitleStartState::Unknown;
  }
  if (state_name == target_title_wait_symbol) {
    return TitleStartState::Awaiting;
  }
  if (state_name == target_title_symbol) {
    return TitleStartState::TitleOpening;
  }
  if (state_name == target_title_play_symbol) {
    return TitleStartState::TitleSequence;
  }
  return TitleStartState::NotAwaiting;
}

/*! Read a Jak 1 `progress` through `*progress-process*` without advancing or mutating GOAL. */
inline ProgressMenuSnapshot read_progress_menu_snapshot(const void* memory,
                                                         std::size_t memory_bytes,
                                                         std::size_t low_protect_bytes,
                                                         std::uint32_t goal_false,
                                                         std::uint32_t goal_true,
                                                         std::uint32_t progress_ppointer,
                                                         std::uint32_t expected_type,
                                                         std::uint32_t progress_state_offset = 0,
                                                         std::uint32_t progress_state_type = 0,
                                                         std::uint32_t state_type = 0,
                                                         std::uint32_t progress_normal_symbol = 0) noexcept {
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
  if (!progress_layout::is_known_screen(screen) || option_index < 0 ||
      !is_goal_boolean(selected_option) || !is_goal_boolean(in_transition)) {
    return snapshot;
  }

  snapshot.available = true;
  snapshot.screen = static_cast<ProgressScreen>(screen);
  snapshot.option_index = option_index;
  snapshot.selected_option = selected_option == goal_true;
  snapshot.in_transition = in_transition == goal_true;

  const void* progress_state = camera_correction_trace::checked_goal_object(
      memory, memory_bytes, low_protect_bytes, progress_state_offset, progress_state_type,
      progress_layout::kStartingStateRequiredObjectBytes, nullptr);
  std::uint32_t next_state_offset = 0;
  std::memcpy(&next_state_offset, bytes + progress_layout::kNextStateOffset,
              sizeof(next_state_offset));
  const void* next_state = camera_correction_trace::checked_goal_object(
      memory, memory_bytes, low_protect_bytes, next_state_offset, state_type,
      progress_layout::kStateRequiredObjectBytes, nullptr);
  if (!progress_state || !next_state || !progress_normal_symbol) {
    return snapshot;
  }
  std::int64_t starting_screen = 0;
  std::uint32_t next_state_name = 0;
  std::memcpy(&starting_screen,
              static_cast<const std::uint8_t*>(progress_state) +
                  progress_layout::kStartingStateOffset,
              sizeof(starting_screen));
  std::memcpy(&next_state_name,
              static_cast<const std::uint8_t*>(next_state) + progress_layout::kStateNameOffset,
              sizeof(next_state_name));
  if (!progress_layout::is_known_screen(starting_screen)) {
    return snapshot;
  }
  snapshot.navigation_available = true;
  snapshot.starting_screen = static_cast<ProgressScreen>(starting_screen);
  snapshot.can_exit_with_start = progress_layout::can_exit_with_start(
      screen, starting_screen, snapshot.selected_option, snapshot.in_transition,
      next_state_name == progress_normal_symbol);
  snapshot.can_go_back = snapshot.can_exit_with_start ||
                         (!snapshot.selected_option && !snapshot.in_transition &&
                          next_state_name == progress_normal_symbol &&
                          (screen == 16 || screen == 17 || screen == 18));
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
BootStatus boot_game(int target_frame_rate) noexcept;
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
/*! True after Jak's title-menu Quit asks the app host to close the running session. */
bool exit_to_library_requested() noexcept;
/*! Jak's own `*master-mode*`, read without advancing or mutating the game. */
GameMode game_mode() noexcept;
TitleStartState title_start_state() noexcept;
/*! Jak's live target state; Billy and unavailable or inconsistent state remain unknown. */
LookAroundState look_around_state() noexcept;
/*! Whether Jak's checked next target state is one of OpenGOAL's driving states. */
SpeederState speeder_state() noexcept;
/*! Jak's live progress state. Malformed, absent, and internally inconsistent state is unavailable. */
ProgressMenuSnapshot progress_menu_snapshot() noexcept;
/*! GOAL-owned warp-gate touch semantics. Invalid publication and valid unavailable are distinct. */
WarpGateTouchSnapshot warp_gate_touch_snapshot() noexcept;
/*! GOAL-owned skippable spooled-animation availability. Invalid and stale reads fail closed. */
CutsceneSkipTouchSnapshot cutscene_skip_touch_snapshot() noexcept;
/*! GOAL-owned contextual face-button requests. First, malformed, and stale samples fail closed. */
FacePromptTouchSnapshot face_prompt_touch_snapshot() noexcept;

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
