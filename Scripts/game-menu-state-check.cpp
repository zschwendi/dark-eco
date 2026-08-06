#include "GOALPad/Native/GOALPadGameBoot.hpp"

#include <cstdlib>
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
  constexpr std::uint32_t kOtherState = 704;
  std::vector<std::uint8_t> memory(1024);
  write(memory, kTargetType + 8, std::uint16_t{128});
  write(memory, kStateType + 8, std::uint16_t{36});
  write(memory, kTargetObject - 4, kTargetType);
  write(memory, kTargetObject + goalpad::live_state_layout::kProcessStateOffset,
        kStateObject);
  write(memory, kStateObject - 4, kStateType);
  write(memory, kStateObject + goalpad::live_state_layout::kStateNameOffset, kTitleWait);
  expect(goalpad::read_title_start_state(memory.data(), memory.size(), 64, kTargetObject,
                                         kTargetType, kStateType, kTitleWait) ==
             goalpad::TitleStartState::Awaiting,
         "target-title-wait is the exact native Start-prompt state");
  write(memory, kStateObject + goalpad::live_state_layout::kStateNameOffset, kOtherState);
  expect(goalpad::read_title_start_state(memory.data(), memory.size(), 64, kTargetObject,
                                         kTargetType, kStateType, kTitleWait) ==
             goalpad::TitleStartState::NotAwaiting,
         "a different validated target state is not mislabeled Start");
  expect(goalpad::read_title_start_state(memory.data(), memory.size(), 64, 0, kTargetType,
                                         kStateType, kTitleWait) ==
             goalpad::TitleStartState::Unknown,
         "missing target state fails closed");
  std::cout << "game menu state checks passed\n";
}
