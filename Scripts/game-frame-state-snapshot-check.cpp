#include "GOALPad/Native/GOALPadGameBoot.hpp"
#include "game/kernel/common/kmemcard.h"

#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <limits>
#include <type_traits>
#include <vector>

static_assert(std::is_standard_layout_v<goalpad::GameFrameStateSnapshot>);
static_assert(std::is_trivially_copyable_v<goalpad::GameFrameStateSnapshot>);
static_assert(std::is_standard_layout_v<goalpad::TargetFrameStateCapture>);
static_assert(std::is_trivially_copyable_v<goalpad::TargetFrameStateCapture>);
using FusedRunFrame = bool (*)(double, goalpad::GameFrameStateSnapshot*) noexcept;
using LegacyRunFrame = bool (*)(double) noexcept;
static_assert(std::is_same_v<
              decltype(static_cast<FusedRunFrame>(&goalpad::run_frame)), FusedRunFrame>);
static_assert(std::is_same_v<
              decltype(static_cast<LegacyRunFrame>(&goalpad::run_frame)), LegacyRunFrame>);

namespace {

void check(bool condition, const char* message) {
  if (!condition) {
    std::cerr << "FAIL: " << message << '\n';
    std::exit(1);
  }
}

template <typename T>
void write(std::vector<std::uint8_t>& memory, std::size_t offset, T value) {
  std::memcpy(memory.data() + offset, &value, sizeof(value));
}

}  // namespace

int main() {
  goalpad::GameFrameStateSnapshot snapshot;
  check(!snapshot.exit_to_library_requested && snapshot.frames_run == 0 &&
            snapshot.successful_save_generation == 0 &&
            snapshot.game_mode == goalpad::GameMode::Unknown &&
            !snapshot.progress_menu.available &&
            snapshot.title_start_state == goalpad::TitleStartState::Unknown &&
            !snapshot.warp_gate_touch.valid && !snapshot.cutscene_skip_touch.valid &&
            !snapshot.face_prompt_touch.valid &&
            snapshot.look_around_state == goalpad::LookAroundState::Unknown &&
            snapshot.speeder_state == goalpad::SpeederState::Unknown,
        "the fixed snapshot defaults every field to fail-closed state");

  snapshot.exit_to_library_requested = true;
  snapshot.frames_run = 42;
  snapshot.successful_save_generation = 17;
  snapshot.game_mode = goalpad::GameMode::Progress;
  snapshot.progress_menu.available = true;
  snapshot.progress_menu.screen = goalpad::ProgressScreen::FuelCells;
  snapshot.title_start_state = goalpad::TitleStartState::TitleSequence;
  snapshot.warp_gate_touch.valid = true;
  snapshot.warp_gate_touch.sequence = 4;
  snapshot.cutscene_skip_touch.valid = true;
  snapshot.cutscene_skip_touch.sequence = 6;
  snapshot.face_prompt_touch.valid = true;
  snapshot.face_prompt_touch.requested_buttons = 1u << 14;
  snapshot.look_around_state = goalpad::LookAroundState::FirstPerson;
  snapshot.speeder_state = goalpad::SpeederState::Riding;

  check(snapshot.exit_to_library_requested && snapshot.frames_run == 42 &&
            snapshot.successful_save_generation == 17 &&
            snapshot.game_mode == goalpad::GameMode::Progress &&
            snapshot.progress_menu.screen == goalpad::ProgressScreen::FuelCells &&
            snapshot.title_start_state == goalpad::TitleStartState::TitleSequence &&
            snapshot.warp_gate_touch.sequence == 4 &&
            snapshot.cutscene_skip_touch.sequence == 6 &&
            snapshot.face_prompt_touch.requested_buttons == (1u << 14) &&
            snapshot.look_around_state == goalpad::LookAroundState::FirstPerson &&
            snapshot.speeder_state == goalpad::SpeederState::Riding,
        "the fixed snapshot carries every native state field independently");

  KmemcardSuccessfulSaveGeneration save_generation;
  save_generation.record_close_result(-1);
  check(save_generation.value() == 0,
        "a failed native save close does not advance the host generation");
  save_generation.record_close_result(0);
  check(save_generation.value() == 1,
        "a successful native save close advances the host generation once");
  save_generation.reset();
  check(save_generation.value() == 0,
        "native memcard initialization can reset the host generation");
  KmemcardSuccessfulSaveGeneration wrapping_generation(std::numeric_limits<u64>::max());
  wrapping_generation.record_close_result(0);
  check(wrapping_generation.value() == 0,
        "the unsigned native save generation wraps without changing event semantics");

  constexpr std::size_t kLowProtect = 64;
  constexpr std::uint32_t kTargetType = 132;
  constexpr std::uint32_t kStateType = 196;
  constexpr std::uint32_t kWrongType = 260;
  constexpr std::uint32_t kTargetObject = 516;
  constexpr std::uint32_t kCurrentStateObject = 1284;
  constexpr std::uint32_t kNextStateObject = 1348;
  constexpr std::uint32_t kTitleWait = 1500;
  constexpr std::uint32_t kTitle = 1504;
  constexpr std::uint32_t kTitlePlay = 1508;
  constexpr std::uint32_t kRacing = 1512;
  constexpr std::uint32_t kLookAroundMode = 1516;
  constexpr std::array<std::uint32_t, 3> kRacingStates = {kRacing, 1520, 1524};
  std::vector<std::uint8_t> memory(2048);
  write(memory, kTargetType + 8, std::uint16_t{0x250});
  write(memory, kStateType + 8, std::uint16_t{36});
  write(memory, kWrongType + 8, std::uint16_t{36});
  write(memory, kTargetObject - 4, kTargetType);
  write(memory, kTargetObject + goalpad::live_state_layout::kProcessStateOffset,
        kCurrentStateObject);
  write(memory, kTargetObject + goalpad::live_state_layout::kProcessNextStateOffset,
        kNextStateObject);
  write(memory, kTargetObject + goalpad::target_frame_layout::kStateFlagsOffset,
        goalpad::kJak1FirstPersonModeFlag);
  write(memory, kTargetObject + goalpad::target_frame_layout::kCameraUserModeOffset,
        kLookAroundMode);
  write(memory, kCurrentStateObject - 4, kStateType);
  write(memory, kCurrentStateObject + goalpad::live_state_layout::kStateNameOffset, kTitleWait);
  write(memory, kNextStateObject - 4, kStateType);
  write(memory, kNextStateObject + goalpad::live_state_layout::kStateNameOffset, kRacing);

  const auto read_target = [&]() {
    return goalpad::read_target_frame_state_capture(
        memory.data(), memory.size(), kLowProtect, kTargetObject, kTargetType, kStateType);
  };
  auto target = read_target();
  check(target.target_valid && target.look_around_fields_valid &&
            target.current_state_name == kTitleWait && target.next_state_name == kRacing &&
            target.state_flags == goalpad::kJak1FirstPersonModeFlag &&
            target.camera_user_mode == kLookAroundMode,
        "one target capture carries independently checked title, look, and speeder fields");
  check(goalpad::classify_title_start_state(target.current_state_name, kTitleWait, kTitle,
                                            kTitlePlay) ==
            goalpad::TitleStartState::Awaiting &&
            goalpad::classify_look_around_state(target.look_around_fields_valid,
                                                target.state_flags, target.camera_user_mode,
                                                kLookAroundMode) ==
                goalpad::LookAroundState::FirstPerson &&
            goalpad::classify_speeder_state(target.next_state_name, kRacingStates) ==
                goalpad::SpeederState::Riding,
        "the target capture derives the same three public classifications");

  write(memory, kCurrentStateObject - 4, kWrongType);
  target = read_target();
  check(target.current_state_name == 0 && target.next_state_name == kRacing &&
            target.look_around_fields_valid,
        "a malformed current state fails title closed without suppressing look or speeder");
  write(memory, kCurrentStateObject - 4, kStateType);

  write(memory, kNextStateObject - 4, kWrongType);
  target = read_target();
  check(target.current_state_name == kTitleWait && target.next_state_name == 0 &&
            target.look_around_fields_valid,
        "a malformed next state fails speeder closed without suppressing title or look");
  write(memory, kNextStateObject - 4, kStateType);

  write(memory, kTargetObject + goalpad::live_state_layout::kProcessStateOffset,
        static_cast<std::uint32_t>(memory.size()));
  target = read_target();
  check(target.current_state_name == 0 && target.next_state_name == kRacing &&
            target.look_around_fields_valid,
        "an out-of-bounds current state remains independent of next state and look fields");
  write(memory, kTargetObject + goalpad::live_state_layout::kProcessStateOffset,
        kCurrentStateObject);

  write(memory, kTargetObject + goalpad::live_state_layout::kProcessNextStateOffset,
        static_cast<std::uint32_t>(memory.size()));
  target = read_target();
  check(target.current_state_name == kTitleWait && target.next_state_name == 0 &&
            target.look_around_fields_valid,
        "an out-of-bounds next state remains independent of current state and look fields");
  write(memory, kTargetObject + goalpad::live_state_layout::kProcessNextStateOffset,
        kNextStateObject);

  write(memory, kTargetObject - 4, kWrongType);
  target = read_target();
  check(!target.target_valid && !target.look_around_fields_valid &&
            target.current_state_name == 0 && target.next_state_name == 0,
        "a malformed target type fails every derived field closed");
  write(memory, kTargetObject - 4, kTargetType);

  write(memory, kTargetType + 8,
        static_cast<std::uint16_t>(goalpad::live_state_layout::kProcessRequiredObjectBytes + 4));
  target = read_target();
  check(target.target_valid && !target.look_around_fields_valid &&
            target.current_state_name == kTitleWait && target.next_state_name == kRacing,
        "a process-sized target preserves title and speeder while look bounds fail closed");

  write(memory, kTargetType + 8, static_cast<std::uint16_t>(
                                     goalpad::live_state_layout::kProcessRequiredObjectBytes + 3));
  target = read_target();
  check(!target.target_valid && !target.look_around_fields_valid &&
            target.current_state_name == 0 && target.next_state_name == 0,
        "a target shorter than its process fields fails every derived field closed");

  write(memory, kTargetType + 8, std::uint16_t{0x250});
  target = goalpad::read_target_frame_state_capture(
      memory.data(), kTargetObject + goalpad::target_frame_layout::kLookAroundRequiredObjectBytes,
      kLowProtect, kTargetObject, kTargetType, kStateType);
  check(!target.target_valid && !target.look_around_fields_valid &&
            target.current_state_name == 0 && target.next_state_name == 0,
        "a declared target allocation outside the backing memory fails closed");

  std::cout << "game frame-state snapshot checks passed\n";
}
