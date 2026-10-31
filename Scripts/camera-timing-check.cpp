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

std::vector<float> high_frame_rate_trace(int target_frame_rate,
                                         const std::vector<double>& intervals) {
  goalpad::DisplayClock clock;
  constexpr double start = 100.0;
  assert(clock.advance(start, target_frame_rate) == 1.0f);
  double target = start;
  std::vector<float> result;
  result.reserve(intervals.size());
  for (const double interval : intervals) {
    target += interval;
    result.push_back(clock.advance(target, target_frame_rate));
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

PromotionSecondTrace high_refresh_second_trace(int target_frame_rate, int callbacks_per_second) {
  goalpad::DisplayClock display_clock;
  goalpad::SoundFrameClock sound_clock;
  FractionalFrameCounters counters;
  PromotionSecondTrace trace;
  trace.display_ratios.reserve(callbacks_per_second);

  double target = 100.0;
  assert(display_clock.advance(target, target_frame_rate) == 1.0f);
  std::array<int, 5> pad_history = {};
  for (int callback = 0; callback < callbacks_per_second; ++callback) {
    target += 1.0 / static_cast<double>(callbacks_per_second);
    const float ratio = display_clock.advance(target, target_frame_rate);
    trace.display_ratios.push_back(ratio);
    trace.callback_units +=
        60.0 / static_cast<double>(target_frame_rate) * static_cast<double>(ratio);
    trace.sound_frames += sound_clock.advance(ratio, target_frame_rate);

    const int previous_integral = counters.integral;
    counters.advance(ratio, 300.0 / static_cast<double>(target_frame_rate));
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
  static_assert(goalpad::DisplayClock::normalize_target_frame_rate(60) == 60);
  static_assert(goalpad::DisplayClock::normalize_target_frame_rate(90) == 90);
  static_assert(goalpad::DisplayClock::normalize_target_frame_rate(120) == 120);

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
  expect_trace("late then early", late_then_early, {2, 0});
  expect_trace("early then late", early_then_late, {1, 1});
  expect_trace("repeated boundary jitter", boundary_jitter, {2, 0, 2, 0});
  expect_trace("repeated slow cadence", repeated_slow, {2, 1});
  expect_trace("carried interval rounding", independently_rounded, {2, 3, 1, 2});

  const auto promotion_factors = high_frame_rate_trace(120,
      {1.0 / 120.0, 1.0 / 80.0, 1.0 / 60.0, 1.0 / 48.0, 1.0 / 40.0,
       1.0 / 30.0, 1.0 / 24.0});
  expect_float_trace("ProMotion factors", promotion_factors,
                     {1.0f, 1.5f, 2.0f, 2.5f, 3.0f, 4.0f, 5.0f});

  goalpad::DisplayClock rate_transition;
  assert(rate_transition.advance(10.0, 60) == 1.0f);
  assert(rate_transition.advance(10.0 + kFramePeriod, 60) == 1.0f);
  assert(rate_transition.advance(20.0, 120) == 1.0f);
  assert(rate_transition.advance(20.0 + 1.0 / 120.0, 120) == 1.0f);
  assert(rate_transition.advance(25.0, 90) == 1.0f);
  assert(rate_transition.advance(25.0 + 1.0 / 90.0, 90) == 1.0f);
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
           RefreshFactor{24, 5.0f, 2.5, 5, {0, 0, 0, 0, 1}},
       }) {
    const auto trace = high_refresh_second_trace(120, factor.callbacks_per_second);
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
  for (const auto factor : {
           RefreshFactor{90, 1.0f, 2.0 / 3.0, 1, {1, 0, 0, 0, 0}},
           RefreshFactor{60, 1.5f, 1.0, 2, {1, 0, 0, 0, 0}},
           RefreshFactor{45, 2.0f, 4.0 / 3.0, 2, {0, 1, 0, 0, 0}},
           RefreshFactor{30, 3.0f, 2.0, 3, {0, 0, 1, 0, 0}},
       }) {
    const auto trace = high_refresh_second_trace(90, factor.callbacks_per_second);
    assert(std::all_of(trace.display_ratios.begin(), trace.display_ratios.end(),
                       [&](float ratio) { return ratio == factor.display_ratio; }));
    assert(near((2.0 / 3.0) * trace.display_ratios.front(), factor.callback_factor));
    assert(near(trace.callback_units, 60.0));
    assert(trace.scaled_ticks == 300);
    assert(trace.integral_target_units == 90);
    assert(trace.sound_frames == 60);
    assert(trace.maximum_pad_steps == factor.maximum_pad_steps);
    assert(trace.first_pad_history == factor.first_pad_history);
    assert(!trace.duplicated_one_shot);
    assert((trace.final_pad_history == std::array<int, 5>{}));

    int eye_target_frames_remaining = 90;
    FractionalFrameCounters eye_counter;
    for (const float ratio : trace.display_ratios) {
      const int previous_integral = eye_counter.integral;
      eye_counter.advance(ratio, 300.0 / 90.0);
      const int integral_frames = eye_counter.integral - previous_integral;
      eye_target_frames_remaining =
          std::max(0, eye_target_frames_remaining - eye_timer_decrement(true, integral_frames));
    }
    assert(eye_target_frames_remaining == 0);
  }
  // Host-managed high-refresh paths consume elapsed target frames. Ordinary PC/PS2 timing retains
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
  assert((age_relative_pad_history(empty_pad_history, 1, 5)
          == std::array<int, 5>{0, 0, 0, 0, 1}));
  assert((age_relative_pad_history(empty_pad_history, 1, 0) == empty_pad_history));

  goalpad::SoundFrameClock sound_60;
  int sound_frames = 0;
  for (int frame = 0; frame < 60; ++frame) {
    sound_frames += sound_60.advance(1.0f, 60);
  }
  assert(sound_frames == 60);
  assert(sound_60.advance(2.0f, 60) == 1);
  assert(sound_60.advance(3.0f, 60) == 1);

  goalpad::SoundFrameClock sound_24_fallback;
  expect_trace("24 Hz sound fallback",
               {sound_24_fallback.advance(5.0f, 120),
                sound_24_fallback.advance(5.0f, 120)},
               {2, 3});

  goalpad::SoundFrameClock sound_90;
  expect_trace("90 Hz sound cadence",
               {sound_90.advance(1.0f, 90), sound_90.advance(1.0f, 90),
                sound_90.advance(1.0f, 90)},
               {0, 1, 1});

  goalpad::SoundFrameClock live_rate_transition;
  assert(live_rate_transition.advance(1.0f, 120) == 0);
  assert(live_rate_transition.advance(1.0f, 120) == 1);
  live_rate_transition.reset();
  assert(live_rate_transition.advance(1.0f, 90) == 0);
  assert(live_rate_transition.advance(1.0f, 90) == 1);
  live_rate_transition.reset();
  assert(live_rate_transition.advance(1.0f, 60) == 1);
  live_rate_transition.reset();
  assert(live_rate_transition.advance(1.0f, 120) == 0);

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

  // Irregular target timestamps keep elapsed time on the wall clock. A callback with no elapsed time
  // prepares zero, so the host reads no input and runs no dispatcher or sound frame for it.
  struct HostRun {
    double frames = 0.0;
    int dispatcher_frames = 0;
    int sound_frames = 0;
  };
  const auto host_run = [](int target_frame_rate, const std::vector<double>& intervals) {
    goalpad::DisplayClock clock;
    goalpad::SoundFrameClock sound;
    HostRun run;
    double target = 700.0;
    const auto callback = [&] {
      if (clock.prepare(target, target_frame_rate) <= 0.0f) {
        return;
      }
      const float ratio = clock.take_prepared();
      run.frames += ratio;
      run.dispatcher_frames++;
      run.sound_frames += sound.advance(ratio, target_frame_rate);
    };
    callback();
    for (const double interval : intervals) {
      target += interval;
      callback();
    }
    run.frames -= 1.0;  // The first callback has no history and counts as one frame.
    return run;
  };
  int elapsed_failures = 0;
  const auto expect_frames = [&](std::string_view name, double actual, double expected) {
    if (std::abs(actual - expected) > 1e-6) {
      std::cerr << name << " advanced " << actual << " frames for " << expected << '\n';
      ++elapsed_failures;
    }
  };
  std::vector<double> jitter_60;
  for (int pair = 0; pair < 30; ++pair) {
    jitter_60.push_back(1.6 * kFramePeriod);
    jitter_60.push_back(0.4 * kFramePeriod);
  }
  expect_frames("60 Hz 26.7/6.7 ms jitter", host_run(60, jitter_60).frames, 60.0);

  for (const int target_frame_rate : {60, 120}) {
    const double period = 1.0 / static_cast<double>(target_frame_rate);
    std::vector<double> repeated;
    for (int group = 0; group < 40; ++group) {
      repeated.push_back(0.0);
      repeated.push_back(3.0 * period);
    }
    const auto run = host_run(target_frame_rate, repeated);
    expect_frames(target_frame_rate == 60 ? "60 Hz repeated timestamps"
                                          : "120 Hz repeated timestamps",
                  run.frames, 120.0);
    if (run.dispatcher_frames != 41) {
      std::cerr << target_frame_rate << " Hz repeated timestamps ran " << run.dispatcher_frames
                << " dispatcher frames for 41\n";
      ++elapsed_failures;
    }
    if (target_frame_rate == 120 && std::abs(run.sound_frames - 60) > 1) {
      std::cerr << "120 Hz repeated timestamps produced " << run.sound_frames
                << " sound frames for 60\n";
      ++elapsed_failures;
    }
  }

  // Sub-period delivery in the 60 Hz domain: 8.3/16.7 ms callbacks run 2 dispatcher frames for
  // every 3 callbacks and stay on the delivered timeline.
  std::vector<double> alternating_60;
  for (int pair = 0; pair < 60; ++pair) {
    alternating_60.push_back(0.5 * kFramePeriod);
    alternating_60.push_back(kFramePeriod);
  }
  const auto sub_period = host_run(60, alternating_60);
  expect_frames("60 Hz 8.3/16.7 ms callbacks", sub_period.frames, 90.0);
  if (sub_period.dispatcher_frames > 91 || sub_period.sound_frames != sub_period.dispatcher_frames) {
    std::cerr << "60 Hz 8.3/16.7 ms callbacks ran " << sub_period.dispatcher_frames
              << " dispatcher and " << sub_period.sound_frames << " sound frames\n";
    ++elapsed_failures;
  }
  if (elapsed_failures != 0) {
    std::abort();
  }

  // On-grid ProMotion delivery alternating 8.3/16.7 ms is already exact and stays unchanged.
  std::vector<double> alternating_120;
  for (int pair = 0; pair < 40; ++pair) {
    alternating_120.push_back(1.0 / 120.0);
    alternating_120.push_back(2.0 / 120.0);
  }
  const auto on_grid = host_run(120, alternating_120);
  assert(near(on_grid.frames, 120.0));
  assert(on_grid.dispatcher_frames == 81);
  assert(std::abs(on_grid.sound_frames - 60) <= 1);

  // A duplicate prepares zero; the next positive interval carries the full elapsed time.
  goalpad::DisplayClock duplicate;
  assert(duplicate.prepare(800.0, 60) == 1.0f && duplicate.take_prepared() == 1.0f);
  assert(duplicate.prepare(800.0, 60) == 0.0f);
  assert(duplicate.prepare(800.0 + 2.0 * kFramePeriod, 60) == 2.0f);
  assert(duplicate.take_prepared() == 2.0f && duplicate.take_prepared() == 0.0f);
  // Time prepared for a callback whose frame never ran stays pending, within the catch-up cap.
  assert(duplicate.prepare(800.0 + 3.0 * kFramePeriod, 60) == 1.0f);
  assert(duplicate.prepare(800.0 + 3.0 * kFramePeriod, 60) == 1.0f);
  assert(duplicate.prepare(800.0 + 10.0 * kFramePeriod, 60) == 4.0f);
  assert(duplicate.take_prepared() == 4.0f);
  // Reset and a rate switch drop pending time and restart at one first frame.
  assert(duplicate.prepare(800.0 + 11.0 * kFramePeriod, 60) == 1.0f);
  duplicate.reset();
  assert(duplicate.take_prepared() == 0.0f);
  assert(duplicate.prepare(900.0, 60) == 1.0f && duplicate.take_prepared() == 1.0f);
  assert(duplicate.prepare(900.0 + 1.0 / 120.0, 120) == 1.0f);
  assert(duplicate.prepare(900.0 + 1.0 / 120.0, 120) == 1.0f);
  assert(duplicate.take_prepared() == 1.0f);

  std::cout << "ordinary targets       [1, 1]\n"
            << "skipped targets        [1, 2]\n"
            << "1.5 + 0.5 targets      [2, 0]\n"
            << "0.5 + 1.5 targets      [1, 1]\n"
            << "1.5 + 1.5 targets      [2, 1]\n"
            << "carried rounding       [2, 3, 1, 2]\n"
            << "workload-only targets  [1, 1]\n"
            << "pre-draw work timer    [2, 1]\n"
            << "rejected fixed step    [1, 1]\n"
            << "phase trace: follow gets 1x; blocker correction gets the real 2x interval\n"
            << "camera timing check: PASS\n";
}
