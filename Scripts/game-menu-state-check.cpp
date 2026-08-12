#include "GOALPad/Native/GOALPadGameBoot.hpp"

#include <cstdlib>
#include <array>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <vector>

namespace {

void expect(bool condition, const char* description) {
  if (!condition) {
    std::cerr << "FAIL  " << description << '\n';
    std::exit(1);
  }
  std::cout << "  ok   " << description << '\n';
}

template <typename T>
void write(std::vector<std::uint8_t>& memory, std::size_t offset, T value) {
  std::memcpy(memory.data() + offset, &value, sizeof(value));
}

}  // namespace

int main() {
  using goalpad::GameMode;
  using goalpad::classify_game_mode;

  expect(classify_game_mode(0, 1, 2, 3, 4) == GameMode::Unknown,
         "an unavailable master mode remains unknown");
  expect(classify_game_mode(1, 1, 2, 3, 4) == GameMode::Gameplay,
         "the game symbol reports active gameplay");
  expect(classify_game_mode(2, 1, 2, 3, 4) == GameMode::Pause,
         "the pause symbol reports the native pause menu");
  expect(classify_game_mode(3, 1, 2, 3, 4) == GameMode::Progress,
         "the progress symbol reports the native progress menu");
  expect(classify_game_mode(4, 1, 2, 3, 4) == GameMode::Menu,
         "the menu symbol reports the native debug menu");
  expect(classify_game_mode(9, 1, 2, 3, 4) == GameMode::Unknown,
         "an unexpected mode is not presented as a known menu");

  constexpr std::uint32_t kTargetType = 100;
  constexpr std::uint32_t kStateType = 124;
  constexpr std::uint32_t kTargetObject = 300;
  constexpr std::uint32_t kStateObject = 604;
  constexpr std::uint32_t kTitleWait = 700;
  constexpr std::uint32_t kTitle = 704;
  constexpr std::uint32_t kTitlePlay = 708;
  constexpr std::uint32_t kOtherState = 712;
  std::vector<std::uint8_t> memory(1024);
  write(memory, kTargetType + 8, std::uint16_t{128});
  write(memory, kStateType + 8, std::uint16_t{36});
  write(memory, kTargetObject - 4, kTargetType);
  write(memory, kTargetObject + goalpad::live_state_layout::kProcessStateOffset,
        kStateObject);
  write(memory, kStateObject - 4, kStateType);
  write(memory, kStateObject + goalpad::live_state_layout::kStateNameOffset, kTitleWait);
  expect(goalpad::read_title_start_state(memory.data(), memory.size(), 64, kTargetObject,
                                         kTargetType, kStateType, kTitleWait, kTitle,
                                         kTitlePlay) ==
             goalpad::TitleStartState::Awaiting,
         "target-title-wait is the exact native Start-prompt state");
  write(memory, kStateObject + goalpad::live_state_layout::kStateNameOffset, kTitle);
  expect(goalpad::read_title_start_state(memory.data(), memory.size(), 64, kTargetObject,
                                         kTargetType, kStateType, kTitleWait, kTitle,
                                         kTitlePlay) ==
             goalpad::TitleStartState::TitleOpening,
         "target-title is the visible Start opening before the title sequence");
  write(memory, kStateObject + goalpad::live_state_layout::kStateNameOffset, kTitlePlay);
  expect(goalpad::read_title_start_state(memory.data(), memory.size(), 64, kTargetObject,
                                         kTargetType, kStateType, kTitleWait, kTitle,
                                         kTitlePlay) ==
             goalpad::TitleStartState::TitleSequence,
         "target-title-play remains in the non-interactive title sequence");
  write(memory, kStateObject + goalpad::live_state_layout::kStateNameOffset, kOtherState);
  expect(goalpad::read_title_start_state(memory.data(), memory.size(), 64, kTargetObject,
                                         kTargetType, kStateType, kTitleWait, kTitle,
                                         kTitlePlay) ==
             goalpad::TitleStartState::NotAwaiting,
         "a non-title target state is classified as active gameplay");
  expect(goalpad::read_title_start_state(memory.data(), memory.size(), 64, 0, kTargetType,
                                         kStateType, kTitleWait, kTitle, kTitlePlay) ==
             goalpad::TitleStartState::Unknown,
         "missing target state fails closed");
  expect(goalpad::read_title_start_state(memory.data(), memory.size(), 64, kTargetObject,
                                         kTargetType, kStateType, kTitleWait, 0,
                                         kTitlePlay) ==
             goalpad::TitleStartState::Unknown,
         "missing title-flow symbols fail closed");

  constexpr std::array<std::uint32_t, 9> kRidingStates = {
      800, 804, 808, 812, 816, 820, 824, 828, 832,
  };
  write(memory, kTargetObject + goalpad::live_state_layout::kProcessNextStateOffset,
        kStateObject);
  for (const auto riding_state : kRidingStates) {
    write(memory, kStateObject + goalpad::live_state_layout::kStateNameOffset, riding_state);
    const auto state_name = goalpad::read_process_state_name(
        memory.data(), memory.size(), 64, kTargetObject, kTargetType, kStateType, true);
    expect(goalpad::classify_speeder_state(state_name, kRidingStates) ==
               goalpad::SpeederState::Riding,
           "each exact OpenGOAL racer state enables speeder controls");
  }
  write(memory, kStateObject + goalpad::live_state_layout::kStateNameOffset, kOtherState);
  expect(goalpad::classify_speeder_state(
             goalpad::read_process_state_name(memory.data(), memory.size(), 64, kTargetObject,
                                              kTargetType, kStateType, true),
             kRidingStates) == goalpad::SpeederState::NotRiding,
         "a checked unrelated target state keeps ordinary on-foot controls");
  auto incomplete_states = kRidingStates;
  incomplete_states[4] = 0;
  expect(goalpad::classify_speeder_state(kRidingStates[0], incomplete_states) ==
             goalpad::SpeederState::Unknown,
         "an incomplete level-bundled racer symbol set fails closed");
  expect(goalpad::classify_speeder_state(
             goalpad::read_process_state_name(memory.data(), memory.size(), 64, 0,
                                              kTargetType, kStateType, true),
             kRidingStates) == goalpad::SpeederState::Unknown,
         "an invalid target pointer cannot invent speeder controls");
  std::cout << "game menu state checks passed\n";
}
