#include "GOALPad/Native/GOALPadGameBoot.hpp"

#include <cstdlib>
#include <iostream>

int main() {
  goalpad::GameFrameStateSnapshot snapshot;
  snapshot.exit_to_library_requested = true;
  snapshot.frames_run = 42;
  snapshot.successful_save_generation = 17;
  snapshot.game_mode = goalpad::GameMode::Progress;
  snapshot.progress_menu.available = true;
  snapshot.title_start_state = goalpad::TitleStartState::TitleSequence;
  snapshot.warp_gate_touch.valid = true;
  snapshot.cutscene_skip_touch.valid = true;
  snapshot.face_prompt_touch.valid = true;
  snapshot.look_around_state = goalpad::LookAroundState::FirstPerson;
  snapshot.speeder_state = goalpad::SpeederState::Riding;

  const bool ran = goalpad::run_frame(0, &snapshot);
  if (ran || goalpad::run_frame(0) || goalpad::set_target_frame_rate(120) ||
      snapshot.exit_to_library_requested ||
      snapshot.frames_run != 0 ||
      snapshot.successful_save_generation != 0 ||
      snapshot.game_mode != goalpad::GameMode::Unknown || snapshot.progress_menu.available ||
      snapshot.title_start_state != goalpad::TitleStartState::Unknown ||
      snapshot.warp_gate_touch.valid || snapshot.cutscene_skip_touch.valid ||
      snapshot.face_prompt_touch.valid ||
      snapshot.look_around_state != goalpad::LookAroundState::Unknown ||
      snapshot.speeder_state != goalpad::SpeederState::Unknown) {
    std::cerr << "FAIL: an unavailable native frame did not return fail-closed output\n";
    return EXIT_FAILURE;
  }

  std::cout << "unavailable game frame-state output check passed\n";
  return EXIT_SUCCESS;
}
