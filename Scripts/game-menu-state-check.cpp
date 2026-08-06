#include "GOALPad/Native/GOALPadGameBoot.hpp"

#include <cstdlib>
#include <iostream>

namespace {

void expect(bool condition, const char* description) {
  if (!condition) {
    std::cerr << "FAIL  " << description << '\n';
    std::exit(1);
  }
  std::cout << "  ok   " << description << '\n';
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
  std::cout << "game menu state checks passed\n";
}
