#include "GOALPad/Native/GOALPadMetalHost.hpp"

#include <cstdio>

namespace {

int failures = 0;

void check(bool condition, const char* message) {
  if (!condition) {
    std::fprintf(stderr, "post-flag diagnostics check failed: %s\n", message);
    failures++;
  }
}

}  // namespace

int main() {
  goalpad::PostFlagFrameGate gate;

  gate.begin_frame(3);
  check(gate.unframed_samples_total() == 3,
        "samples produced before the first armed frame are counted as unframed");
  check(!gate.observe(3, false).accepted,
        "a pre-frame sample cannot be attributed to the newly armed frame");

  const auto first_visible = gate.observe(4, false);
  check(first_visible.accepted, "a sample produced during the armed frame is accepted");
  check(!first_visible.hidden_transition, "the first accepted sample is not a transition");
  check(first_visible.serial_gap == 0, "a consecutive in-frame sample has no serial gap");
  gate.end_frame();

  check(!gate.observe(5, true).accepted, "a sample produced with no armed frame is rejected");
  check(gate.unframed_samples_total() == 4, "the rejected no-frame sample is counted");

  gate.begin_frame(5);
  const auto hidden = gate.observe(6, true);
  check(hidden.accepted, "the next in-frame hidden sample is accepted");
  check(hidden.hidden_transition, "visible to hidden increments the transition count");

  const auto visible_again = gate.observe(8, false);
  check(visible_again.accepted, "a later in-frame visible sample is accepted");
  check(visible_again.hidden_transition, "hidden to visible increments the transition count");
  check(visible_again.serial_gap == 1, "a skipped in-frame serial is reported");
  gate.end_frame();

  check(gate.samples_total() == 3, "only accepted in-frame samples are retained");
  check(gate.hidden_samples_total() == 1, "hidden sample count is exact");
  check(gate.hidden_transitions_total() == 2, "both hidden-state transitions are counted");
  check(gate.serial_gaps_total() == 1, "serial gap total is exact");

  gate.reset();
  check(gate.samples_total() == 0, "reset clears accepted samples");
  check(gate.hidden_samples_total() == 0, "reset clears hidden samples");
  check(gate.hidden_transitions_total() == 0, "reset clears hidden transitions");
  check(gate.serial_gaps_total() == 0, "reset clears serial gaps");
  check(gate.unframed_samples_total() == 0, "reset clears unframed samples");

  if (failures) {
    return 1;
  }
  std::puts("post-flag diagnostics check passed");
  return 0;
}
