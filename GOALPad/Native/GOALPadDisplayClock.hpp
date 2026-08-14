#pragma once

#include <algorithm>
#include <cmath>

namespace goalpad {

/*! Converts display-link target timestamps into Jak's bounded simulation-frame ratio. */
class DisplayClock {
 public:
  static constexpr int normalize_target_frame_rate(int target_frame_rate) noexcept {
    if (target_frame_rate == 90) {
      return 90;
    }
    return target_frame_rate >= 120 ? 120 : 60;
  }

  float advance(double target_presentation_time, int target_frame_rate) noexcept {
    const int normalized_frame_rate = normalize_target_frame_rate(target_frame_rate);
    if (normalized_frame_rate != target_frame_rate_) {
      reset();
      target_frame_rate_ = normalized_frame_rate;
    }

    if (!std::isfinite(target_presentation_time)) {
      reset();
      return 1.0f;
    }

    if (!has_previous_target_) {
      previous_target_ = target_presentation_time;
      has_previous_target_ = true;
      return 1.0f;
    }

    const double elapsed_frames =
        (target_presentation_time - previous_target_) * target_frame_rate_;
    previous_target_ = target_presentation_time;
    if (!std::isfinite(elapsed_frames) || elapsed_frames <= 0.0) {
      reset();
      return 1.0f;
    }

    // Preserve the physically accepted 60 Hz integer cadence. High-refresh domains use half-frame
    // units so common adaptive fallback rates remain exact without timestamp-scale jitter.
    const double quantization = target_frame_rate_ > 60 ? 0.5 : 1.0;
    const double quantized = std::round(elapsed_frames / quantization) * quantization;
    // The 60 and 90 Hz paths retain the four-frame safety cap. A 120 Hz session additionally
    // represents ProMotion's 24 Hz fallback as five target frames in one callback.
    const double maximum_ratio = target_frame_rate_ == 120 ? 5.0 : 4.0;
    return static_cast<float>(std::clamp(quantized, 1.0, maximum_ratio));
  }

  int advance(double target_presentation_time) noexcept {
    return static_cast<int>(advance(target_presentation_time, 60));
  }

  void reset() noexcept {
    previous_target_ = 0.0;
    has_previous_target_ = false;
  }

 private:
  double previous_target_ = 0.0;
  bool has_previous_target_ = false;
  int target_frame_rate_ = 60;
};

/*! Converts the simulation ratio back into the sound system's established 60 Hz vblank clock. */
class SoundFrameClock {
 public:
  int advance(float display_time_ratio, int target_frame_rate) noexcept {
    const int normalized_frame_rate = DisplayClock::normalize_target_frame_rate(target_frame_rate);
    if (normalized_frame_rate != target_frame_rate_) {
      reset();
      target_frame_rate_ = normalized_frame_rate;
    }
    if (!std::isfinite(display_time_ratio) || display_time_ratio <= 0.0f) {
      reset();
      return 0;
    }
    // The accepted 60 Hz path advances sound once per dispatcher callback, including after a
    // missed presentation. Debt conversion is only needed when the dispatcher target exceeds 60 Hz.
    if (target_frame_rate_ == 60) {
      return 1;
    }

    debt_ += static_cast<double>(display_time_ratio) * 60.0 / target_frame_rate_;
    constexpr double kIntegralBoundaryTolerance = 1e-9;
    const int frames =
        std::clamp(static_cast<int>(debt_ + kIntegralBoundaryTolerance), 0, 4);
    debt_ -= frames;
    if (debt_ < 0.0 && debt_ > -kIntegralBoundaryTolerance) {
      debt_ = 0.0;
    }
    return frames;
  }

  void reset() noexcept { debt_ = 0.0; }

 private:
  double debt_ = 0.0;
  int target_frame_rate_ = 60;
};

}  // namespace goalpad
