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

  static constexpr float maximum_ratio(int target_frame_rate) noexcept {
    // The 60 and 90 Hz paths retain the four-frame safety cap. A 120 Hz session additionally
    // represents ProMotion's 24 Hz fallback as five target frames in one callback.
    return normalize_target_frame_rate(target_frame_rate) == 120 ? 5.0f : 4.0f;
  }

  /*!
   * Elapsed target frames since the previous callback. The first callback, and the next one after a
   * reset, a non-finite timestamp or a backward timestamp, count as one frame. A repeated or
   * sub-quantum timestamp reports zero; the rounding carries forward so irregular deliveries stay on
   * the delivered timeline. Time beyond the catch-up cap is dropped rather than replayed.
   */
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

    const double delivered_frames =
        (target_presentation_time - previous_target_) * target_frame_rate_;
    if (!std::isfinite(delivered_frames) || delivered_frames < 0.0) {
      reset();
      return 1.0f;
    }
    previous_target_ = target_presentation_time;

    // Preserve the physically accepted 60 Hz integer cadence. High-refresh domains use half-frame
    // units so common adaptive fallback rates remain exact without timestamp-scale jitter.
    const double quantization = target_frame_rate_ > 60 ? 0.5 : 1.0;
    const double elapsed_frames = delivered_frames + remainder_;
    const double quantized =
        std::max(0.0, std::round(elapsed_frames / quantization) * quantization);
    const double maximum = maximum_ratio(target_frame_rate_);
    if (quantized > maximum) {
      remainder_ = 0.0;
      return static_cast<float>(maximum);
    }
    remainder_ = elapsed_frames - quantized;
    return static_cast<float>(quantized);
  }

  int advance(double target_presentation_time) noexcept {
    return static_cast<int>(advance(target_presentation_time, 60));
  }

  /*!
   * Advances the clock once for a display callback, before the callback reads any input. Zero means
   * no simulated time elapsed, so the caller runs nothing. Time prepared by a callback that then
   * could not run its frame stays pending for the next one, within the catch-up cap.
   */
  float prepare(double target_presentation_time, int target_frame_rate) noexcept {
    const float elapsed = advance(target_presentation_time, target_frame_rate);
    prepared_ = std::min(prepared_ + elapsed, maximum_ratio(target_frame_rate));
    return prepared_;
  }

  /*! Returns and clears the prepared frames for the dispatcher frame about to run. */
  float take_prepared() noexcept {
    const float prepared = prepared_;
    prepared_ = 0.0f;
    return prepared;
  }

  void reset() noexcept {
    previous_target_ = 0.0;
    has_previous_target_ = false;
    remainder_ = 0.0;
    prepared_ = 0.0f;
  }

 private:
  double previous_target_ = 0.0;
  bool has_previous_target_ = false;
  double remainder_ = 0.0;
  float prepared_ = 0.0f;
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
