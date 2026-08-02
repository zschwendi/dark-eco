#include "GOALPadDisplayClock.hpp"

#include <algorithm>
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
  const auto accumulated_slow = display_trace(1.5 * kFramePeriod, 1.5 * kFramePeriod);
  const auto capped_with_residual = display_trace({1.5 * kFramePeriod,
                                                   3.75 * kFramePeriod,
                                                   0.75 * kFramePeriod,
                                                   2.0 * kFramePeriod});
  expect_trace("late then early", late_then_early, {1, 1});
  expect_trace("early then late", early_then_late, {1, 1});
  expect_trace("repeated boundary jitter", boundary_jitter, {1, 1, 1, 1});
  expect_trace("accumulated slow cadence", accumulated_slow, {1, 2});
  expect_trace("capped interval preserves residual", capped_with_residual, {1, 4, 1, 2});

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
            << "1.5 + 0.5 targets      [1, 1]\n"
            << "0.5 + 1.5 targets      [1, 1]\n"
            << "1.5 + 1.5 targets      [1, 2]\n"
            << "capped residual        [1, 4, 1, 2]\n"
            << "workload-only targets  [1, 1]\n"
            << "pre-draw work timer    [2, 1]\n"
            << "rejected fixed step    [1, 1]\n"
            << "phase trace: follow gets 1x; blocker correction gets the real 2x interval\n"
            << "camera timing check: PASS\n";
}
