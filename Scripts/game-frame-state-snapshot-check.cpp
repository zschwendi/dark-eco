#include "GOALPad/Native/GOALPadGameBoot.hpp"

#include <cstdlib>
#include <iostream>
#include <type_traits>

static_assert(std::is_standard_layout_v<goalpad::GameFrameStateSnapshot>);
static_assert(std::is_trivially_copyable_v<goalpad::GameFrameStateSnapshot>);

namespace {

void check(bool condition, const char* message) {
  if (!condition) {
    std::cerr << "FAIL: " << message << '\n';
    std::exit(1);
  }
}

}  // namespace

int main() {
  goalpad::GameFrameStateSnapshot snapshot;
  check(!snapshot.exit_to_library_requested && snapshot.frames_run == 0 &&
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
            snapshot.game_mode == goalpad::GameMode::Progress &&
            snapshot.progress_menu.screen == goalpad::ProgressScreen::FuelCells &&
            snapshot.title_start_state == goalpad::TitleStartState::TitleSequence &&
            snapshot.warp_gate_touch.sequence == 4 &&
            snapshot.cutscene_skip_touch.sequence == 6 &&
            snapshot.face_prompt_touch.requested_buttons == (1u << 14) &&
            snapshot.look_around_state == goalpad::LookAroundState::FirstPerson &&
            snapshot.speeder_state == goalpad::SpeederState::Riding,
        "the fixed snapshot carries every native state field independently");

  std::cout << "game frame-state snapshot checks passed\n";
}
