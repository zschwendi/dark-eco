#include "GOALPadDisplayClock.hpp"

#include <algorithm>
#include <array>
#include <cassert>
#include <cmath>
#include <iostream>
#include <limits>
#include <string_view>
#include <vector>

namespace {

constexpr double kFramePeriod = 1.0 / 60.0;

void expect_trace(std::string_view name,
                  const std::vector<int>& actual,
                  const std::vector<int>& expected) {
  if (actual != expected) {
    std::cerr << name << " trace mismatch:";
    for (const int value : actual) {
      std::cerr << ' ' << value;
    }
    std::cerr << '\n';
    std::abort();
  }
}

void expect_float_trace(std::string_view name,
                        const std::vector<float>& actual,
                        const std::vector<float>& expected) {
  assert(actual.size() == expected.size());
  for (std::size_t index = 0; index < actual.size(); ++index) {
    if (std::abs(actual[index] - expected[index]) > 1e-6f) {
      std::cerr << name << " trace mismatch at " << index << ": " << actual[index] << " != "
                << expected[index] << '\n';
      std::abort();
    }
  }
}

std::vector<int> display_trace(const std::vector<double>& intervals) {
  goalpad::DisplayClock clock;
  constexpr double start = 100.0;
  assert(clock.advance(start) == 1);
  double target = start;
  std::vector<int> result;
  result.reserve(intervals.size());
  for (const double interval : intervals) {
    target += interval;
    result.push_back(clock.advance(target));
  }
  return result;
}

std::vector<int> display_trace(double first_interval, double second_interval) {
  return display_trace({first_interval, second_interval});
}

std::vector<float> high_frame_rate_trace(const std::vector<double>& intervals) {
  goalpad::DisplayClock clock;
  constexpr double start = 100.0;
  assert(clock.advance(start, 120) == 1.0f);
  double target = start;
  std::vector<float> result;
  result.reserve(intervals.size());
  for (const double interval : intervals) {
    target += interval;
    result.push_back(clock.advance(target, 120));
  }
  return result;
}

struct FractionalFrameCounters {
  double scaled_remainder = 0.0;
  double integral_remainder = 0.0;
  int scaled = 0;
  int integral = 0;

  void advance(double ratio, double time_factor) {
    const double scaled_value = ratio * time_factor + scaled_remainder;
    const int scaled_increment = static_cast<int>(scaled_value);
    scaled_remainder = scaled_value - scaled_increment;
    scaled += scaled_increment;

    const double integral_value = ratio + integral_remainder;
    const int integral_increment = static_cast<int>(integral_value);
    integral_remainder = integral_value - integral_increment;
    integral += integral_increment;
  }
};

std::array<int, 5> age_relative_pad_history(std::array<int, 5> history,
                                            int previous_callback_edge,
                                            int virtual_frames) {
  int carried_edge = previous_callback_edge;
  for (int frame = 0; frame < virtual_frames; ++frame) {
    for (std::size_t index = history.size() - 1; index > 0; --index) {
      history[index] = history[index - 1];
    }
    history[0] = carried_edge;
    carried_edge = 0;
  }
  return history;
}

struct PromotionSecondTrace {
  std::vector<float> display_ratios;
  int scaled_ticks = 0;
  int integral_target_units = 0;
  int sound_frames = 0;
  double callback_units = 0.0;
  int maximum_pad_steps = 0;
  std::array<int, 5> first_pad_history = {};
  std::array<int, 5> final_pad_history = {};
  bool duplicated_one_shot = false;
};

PromotionSecondTrace promotion_second_trace(int callbacks_per_second) {
  goalpad::DisplayClock display_clock;
  goalpad::SoundFrameClock sound_clock;
  FractionalFrameCounters counters;
  PromotionSecondTrace trace;
  trace.display_ratios.reserve(callbacks_per_second);

  double target = 100.0;
  assert(display_clock.advance(target, 120) == 1.0f);
  std::array<int, 5> pad_history = {};
  for (int callback = 0; callback < callbacks_per_second; ++callback) {
    target += 1.0 / static_cast<double>(callbacks_per_second);
    const float ratio = display_clock.advance(target, 120);
    trace.display_ratios.push_back(ratio);
    trace.callback_units += 0.5 * static_cast<double>(ratio);
    trace.sound_frames += sound_clock.advance(ratio, 120);

    const int previous_integral = counters.integral;
    counters.advance(ratio, 2.5);
    const int pad_steps = counters.integral - previous_integral;
    trace.maximum_pad_steps = std::max(trace.maximum_pad_steps, pad_steps);
    pad_history = age_relative_pad_history(pad_history, callback == 0 ? 1 : 0, pad_steps);
    if (callback == 0) {
      trace.first_pad_history = pad_history;
    }
    trace.duplicated_one_shot |=
        std::count(pad_history.begin(), pad_history.end(), 1) > 1;
  }

  trace.scaled_ticks = counters.scaled;
  trace.integral_target_units = counters.integral;
  trace.final_pad_history = pad_history;
  return trace;
}

int eye_timer_decrement(bool host_managed, int real_integral_delta) {
  return host_managed ? real_integral_delta : 1;
}

int work_timer_ratio(double work_milliseconds) {
  const double elapsed_frames = work_milliseconds * 60.0 / 1000.0;
  int ratio = static_cast<int>(elapsed_frames) + 1;
  if (elapsed_frames < 1.3) {
    ratio = 1;
  }
  return std::clamp(ratio, 1, 4);
}

double first_follow_response(int ratio) {
  // camera-h.gc's cam-float-seeker scales acceleration and then displacement by the ratio.
  constexpr double target = 1.0;
  constexpr double acceleration = 0.25;
  double value = 0.0;
  double velocity = 0.0;
  velocity += (target - value) * acceleration * ratio;
  value += velocity * ratio;
  return value;
}

double blocker_auto_rotate_limit(int ratio) {
  // cam-string-joystick uses 10922.667 * seconds-per-frame after LOS chooses its direction.
  return 10922.667 * (static_cast<double>(ratio) / 60.0);
}

bool near(double lhs, double rhs) {
  return std::abs(lhs - rhs) < 1e-9;
}

}  // namespace

int main() {
  const auto ordinary = display_trace(kFramePeriod, kFramePeriod);
  const auto skipped = display_trace(kFramePeriod, 2.0 * kFramePeriod);
  expect_trace("ordinary cadence", ordinary, {1, 1});
  expect_trace("skipped cadence", skipped, {1, 2});

  // Callback workload is deliberately absent from DisplayClock's input. A slow first callback and
  // a fast second callback cannot change regular target timestamps into a false [2, 1] trace.
  const auto workload_only_delay = display_trace(kFramePeriod, kFramePeriod);
  expect_trace("workload-only delay", workload_only_delay, {1, 1});

  const auto late_then_early = display_trace(1.5 * kFramePeriod, 0.5 * kFramePeriod);
  const auto early_then_late = display_trace(0.5 * kFramePeriod, 1.5 * kFramePeriod);
  const auto boundary_jitter = display_trace({1.5 * kFramePeriod,
                                              0.5 * kFramePeriod,
                                              1.5 * kFramePeriod,
                                              0.5 * kFramePeriod});
  const auto repeated_slow = display_trace(1.5 * kFramePeriod, 1.5 * kFramePeriod);
  const auto independently_rounded = display_trace({1.5 * kFramePeriod,
                                                     3.75 * kFramePeriod,
                                                     0.75 * kFramePeriod,
                                                     2.0 * kFramePeriod});
  expect_trace("late then early", late_then_early, {2, 1});
  expect_trace("early then late", early_then_late, {1, 2});
  expect_trace("repeated boundary jitter", boundary_jitter, {2, 1, 2, 1});
  expect_trace("repeated slow cadence", repeated_slow, {2, 2});
  expect_trace("independent interval rounding", independently_rounded, {2, 4, 1, 2});

  const auto promotion_factors = high_frame_rate_trace(
      {1.0 / 120.0, 1.0 / 80.0, 1.0 / 60.0, 1.0 / 48.0, 1.0 / 40.0,
       1.0 / 30.0, 1.0 / 24.0});
  expect_float_trace("ProMotion factors", promotion_factors,
                     {1.0f, 1.5f, 2.0f, 2.5f, 3.0f, 4.0f, 4.0f});

  goalpad::DisplayClock rate_transition;
  assert(rate_transition.advance(10.0, 60) == 1.0f);
  assert(rate_transition.advance(10.0 + kFramePeriod, 60) == 1.0f);
  assert(rate_transition.advance(20.0, 120) == 1.0f);
  assert(rate_transition.advance(20.0 + 1.0 / 120.0, 120) == 1.0f);
  assert(rate_transition.advance(30.0, 60) == 1.0f);

  struct RefreshFactor {
    int callbacks_per_second;
    float display_ratio;
    double callback_factor;
    int maximum_pad_steps;
    std::array<int, 5> first_pad_history;
  };
  for (const auto factor : {
           RefreshFactor{120, 1.0f, 0.5, 1, {1, 0, 0, 0, 0}},
           RefreshFactor{80, 1.5f, 0.75, 2, {1, 0, 0, 0, 0}},
           RefreshFactor{60, 2.0f, 1.0, 2, {0, 1, 0, 0, 0}},
           RefreshFactor{40, 3.0f, 1.5, 3, {0, 0, 1, 0, 0}},
           RefreshFactor{30, 4.0f, 2.0, 4, {0, 0, 0, 1, 0}},
       }) {
    const auto trace = promotion_second_trace(factor.callbacks_per_second);
    assert(std::all_of(trace.display_ratios.begin(), trace.display_ratios.end(),
                       [&](float ratio) { return ratio == factor.display_ratio; }));
    assert(near(0.5 * trace.display_ratios.front(), factor.callback_factor));
    assert(near(trace.callback_units, 60.0));
    assert(trace.scaled_ticks == 300);
    assert(trace.integral_target_units == 120);
    assert(trace.sound_frames == 60);
    assert(trace.maximum_pad_steps == factor.maximum_pad_steps);
    assert(trace.first_pad_history == factor.first_pad_history);
    assert(!trace.duplicated_one_shot);
    assert((trace.final_pad_history == std::array<int, 5>{}));

    int eye_target_frames_remaining = 120;
    FractionalFrameCounters eye_counter;
    for (const float ratio : trace.display_ratios) {
      const int previous_integral = eye_counter.integral;
      eye_counter.advance(ratio, 2.5);
      const int integral_frames = eye_counter.integral - previous_integral;
      eye_target_frames_remaining =
          std::max(0, eye_target_frames_remaining - eye_timer_decrement(true, integral_frames));
    }
    assert(eye_target_frames_remaining == 0);
  }
  // The host-managed 120 Hz path consumes elapsed target frames. Ordinary PC/PS2 timing retains
  // the original one blink-countdown unit per callback, even after a missed presentation.
  for (const int legacy_integral_delta : {1, 2, 3, 4}) {
    assert(eye_timer_decrement(false, legacy_integral_delta) == 1);
  }

  // service-cpads computes the new edge after aging history. A prior callback's edge therefore
  // ages by every elapsed virtual frame, while skipped samples remain zero and never repeat it.
  const std::array<int, 5> empty_pad_history = {};
  assert((age_relative_pad_history(empty_pad_history, 1, 1)
          == std::array<int, 5>{1, 0, 0, 0, 0}));
  assert((age_relative_pad_history(empty_pad_history, 1, 2)
          == std::array<int, 5>{0, 1, 0, 0, 0}));
  assert((age_relative_pad_history(empty_pad_history, 1, 4)
          == std::array<int, 5>{0, 0, 0, 1, 0}));
  assert((age_relative_pad_history(empty_pad_history, 1, 0) == empty_pad_history));

  goalpad::SoundFrameClock sound_60;
  int sound_frames = 0;
  for (int frame = 0; frame < 60; ++frame) {
    sound_frames += sound_60.advance(1.0f, 60);
  }
  assert(sound_frames == 60);
  assert(sound_60.advance(2.0f, 60) == 1);
  assert(sound_60.advance(3.0f, 60) == 1);

  goalpad::DisplayClock promotion_lifecycle;
  goalpad::SoundFrameClock sound_120;
  sound_frames = 0;
  double lifecycle_target = 500.0;
  float lifecycle_ratio = promotion_lifecycle.advance(lifecycle_target, 120);
  sound_frames += sound_120.advance(lifecycle_ratio, 120);
  for (int frame = 1; frame < 119; ++frame) {
    lifecycle_target += 1.0 / 120.0;
    lifecycle_ratio = promotion_lifecycle.advance(lifecycle_target, 120);
    sound_frames += sound_120.advance(lifecycle_ratio, 120);
  }
  assert(sound_frames == 59);
  // Suspension drops timestamp history but retains the half-vblank sound debt already earned by
  // active callbacks. Resumption neither imports wall-clock pause time nor drops that debt.
  promotion_lifecycle.reset();
  lifecycle_target += 600.0;
  lifecycle_ratio = promotion_lifecycle.advance(lifecycle_target, 120);
  const int resumed_sound_frame = sound_120.advance(lifecycle_ratio, 120);
  sound_frames += resumed_sound_frame;
  assert(sound_frames == 60);
  lifecycle_target += 1.0 / 120.0;
  lifecycle_ratio = promotion_lifecycle.advance(lifecycle_target, 120);
  const int following_sound_frame = sound_120.advance(lifecycle_ratio, 120);
  expect_trace("suspend/resume retained debt", {resumed_sound_frame, following_sound_frame},
               {1, 0});

  // A full session reset clears both clocks. The new session starts a fresh half-vblank pair.
  promotion_lifecycle.reset();
  sound_120.reset();
  lifecycle_target += 600.0;
  lifecycle_ratio = promotion_lifecycle.advance(lifecycle_target, 120);
  const int reset_first_sound_frame = sound_120.advance(lifecycle_ratio, 120);
  lifecycle_target += 1.0 / 120.0;
  lifecycle_ratio = promotion_lifecycle.advance(lifecycle_target, 120);
  const int reset_second_sound_frame = sound_120.advance(lifecycle_ratio, 120);
  expect_trace("full timing reset", {reset_first_sound_frame, reset_second_sound_frame}, {0, 1});

  goalpad::DisplayClock lifecycle;
  assert(lifecycle.advance(200.0) == 1);
  assert(lifecycle.advance(200.0 + 2.0 * kFramePeriod) == 2);
  lifecycle.reset();
  assert(lifecycle.advance(900.0) == 1);
  assert(lifecycle.advance(900.0 + kFramePeriod) == 1);

  goalpad::DisplayClock bounds;
  assert(bounds.advance(300.0) == 1);
  assert(bounds.advance(300.0 + 10.0 * kFramePeriod) == 4);
  assert(bounds.advance(300.0 + 11.0 * kFramePeriod) == 1);
  assert(bounds.advance(1e200) == 4);
  assert(bounds.advance(std::numeric_limits<double>::quiet_NaN()) == 1);
  assert(bounds.advance(400.0) == 1);
  assert(bounds.advance(399.0) == 1);
  assert(bounds.advance(500.0) == 1);

  // Reproduce the current clock-domain mismatch. With 22 ms then 8 ms of pre-draw work, the
  // timer-reset seam reports [2, 1]. The display targets for a normal interval followed by one
  // skipped interval report [1, 2]. Fixed-step reports [1, 1].
  const std::vector<int> work_derived = {work_timer_ratio(22.0), work_timer_ratio(8.0)};
  const std::vector<int> fixed_step = {1, 1};
  expect_trace("work-derived", work_derived, {2, 1});
  expect_trace("fixed-step", fixed_step, {1, 1});
  expect_trace("display-derived", skipped, {1, 2});

  // Phase one is ordinary spring follow. Phase two begins after LOS selects blocker correction.
  // Moving the 2x interval to phase one overdrives the spring by 4x and leaves correction at 1x;
  // fixed-step avoids the false spring impulse but still discards the correction's missed interval.
  const double expected_follow = first_follow_response(1);
  assert(near(first_follow_response(work_derived[0]), 4.0 * expected_follow));
  assert(near(first_follow_response(skipped[0]), expected_follow));
  assert(near(first_follow_response(fixed_step[0]), expected_follow));

  const double one_frame_correction = blocker_auto_rotate_limit(1);
  assert(near(blocker_auto_rotate_limit(work_derived[1]), one_frame_correction));
  assert(near(blocker_auto_rotate_limit(fixed_step[1]), one_frame_correction));
  assert(near(blocker_auto_rotate_limit(skipped[1]), 2.0 * one_frame_correction));

  std::cout << "ordinary targets       [1, 1]\n"
            << "skipped targets        [1, 2]\n"
            << "1.5 + 0.5 targets      [2, 1]\n"
            << "0.5 + 1.5 targets      [1, 2]\n"
            << "1.5 + 1.5 targets      [2, 2]\n"
            << "independent rounding   [2, 4, 1, 2]\n"
            << "workload-only targets  [1, 1]\n"
            << "pre-draw work timer    [2, 1]\n"
            << "rejected fixed step    [1, 1]\n"
            << "phase trace: follow gets 1x; blocker correction gets the real 2x interval\n"
            << "camera timing check: PASS\n";
}
