#pragma once

#include <algorithm>
#include <cmath>

namespace goalpad {

/*! Converts the 60 Hz display link's target timestamps into Jak's integral 1..4 frame ratio. */
class DisplayClock {
 public:
  int advance(double target_presentation_time) noexcept {
    if (!std::isfinite(target_presentation_time)) {
      reset();
      return 1;
    }

    if (!has_previous_target_) {
      previous_target_ = target_presentation_time;
      has_previous_target_ = true;
      return 1;
    }

    const double elapsed_frames = (target_presentation_time - previous_target_) * 60.0;
    previous_target_ = target_presentation_time;
    if (!std::isfinite(elapsed_frames) || elapsed_frames <= 0.0) {
      reset();
      return 1;
    }
    if (elapsed_frames >= 4.0) {
      frame_debt_ = 0.0;
      return 4;
    }

    const double accumulated_debt = frame_debt_ + elapsed_frames - 1.0;
    const int extra_frames =
        std::clamp(static_cast<int>(std::floor(accumulated_debt + 1e-6)), 0, 3);
    frame_debt_ = std::clamp(accumulated_debt - extra_frames, -1.0, 1.0);
    return 1 + extra_frames;
  }

  void reset() noexcept {
    previous_target_ = 0.0;
    frame_debt_ = 0.0;
    has_previous_target_ = false;
  }

 private:
  double previous_target_ = 0.0;
  double frame_debt_ = 0.0;
  bool has_previous_target_ = false;
};

}  // namespace goalpad
