#pragma once

#include <cstdint>

namespace goalpad::merc_diagnostic_evidence {

enum Issue : std::uint8_t {
  AFFECTED_SKIN = 1 << 0,
  INVALID_PROFILE = 1 << 1,
  PACKET_PALETTE_CONFLICT = 1 << 2,
  BASE_DRAW_PALETTE_CONFLICT = 1 << 3,
  BOUND_PALETTE_MISMATCH = 1 << 4,
  CAPACITY_DROP = 1 << 5,
};

struct Observation {
  std::uint64_t affected_vertices = 0;
  std::uint64_t invalid_basis_groups = 0;
  std::uint64_t profile_tuple_mismatches = 0;
  std::uint64_t profile_capacity_drops = 0;
  std::uint64_t repeated_packets_conflicting_palette = 0;
  std::uint64_t repeated_base_draws_conflicting_palette = 0;
  std::uint64_t trace_capacity_drops = 0;
  std::uint64_t bound_palette_hash_mismatches = 0;
};

inline std::uint8_t issue_mask(const Observation& observation) {
  std::uint8_t mask = 0;
  if (observation.affected_vertices) {
    mask |= AFFECTED_SKIN;
  }
  if (observation.invalid_basis_groups || observation.profile_tuple_mismatches) {
    mask |= INVALID_PROFILE;
  }
  if (observation.repeated_packets_conflicting_palette) {
    mask |= PACKET_PALETTE_CONFLICT;
  }
  if (observation.repeated_base_draws_conflicting_palette) {
    mask |= BASE_DRAW_PALETTE_CONFLICT;
  }
  if (observation.bound_palette_hash_mismatches) {
    mask |= BOUND_PALETTE_MISMATCH;
  }
  if (observation.profile_capacity_drops || observation.trace_capacity_drops) {
    mask |= CAPACITY_DROP;
  }
  return mask;
}

inline bool should_update_retained_snapshot(bool has_retained_evidence, std::uint8_t mask) {
  return !has_retained_evidence || mask != 0;
}

class EpisodeTracker {
 public:
  void begin_frame() { m_current_frame_mask = 0; }

  std::uint8_t observe(std::uint8_t mask) {
    const std::uint8_t new_bits = mask & ~(m_previous_frame_mask | m_current_frame_mask);
    m_current_frame_mask |= mask;
    return new_bits;
  }

  void end_frame() {
    m_previous_frame_mask = m_current_frame_mask;
    m_current_frame_mask = 0;
  }

 private:
  std::uint8_t m_previous_frame_mask = 0;
  std::uint8_t m_current_frame_mask = 0;
};

}  // namespace goalpad::merc_diagnostic_evidence
