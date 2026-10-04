#pragma once

#include <array>
#include <cstdint>

namespace goalpad::jak2 {

class DiagnosticCadence {
 public:
  void reset() { m_previous_tick = 0; }

  bool should_log(std::uint64_t tick, bool preview_active) {
    if (tick < m_previous_tick) {
      m_previous_tick = 0;
    }

    const std::uint64_t previous_tick = m_previous_tick;
    m_previous_tick = tick;
    if (tick == previous_tick) {
      return false;
    }

    constexpr std::array<std::uint64_t, 6> kStartupMilestones = {1, 10, 20, 30, 60, 120};
    for (const auto milestone : kStartupMilestones) {
      if (previous_tick < milestone && tick >= milestone) {
        return true;
      }
    }

    const std::uint64_t period = preview_active ? 120 : 600;
    return tick > 0 && tick / period > previous_tick / period;
  }

 private:
  std::uint64_t m_previous_tick = 0;
};

}  // namespace goalpad::jak2
