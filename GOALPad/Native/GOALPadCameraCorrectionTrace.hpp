#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>

namespace goalpad::camera_correction_trace {

constexpr std::uint32_t kLineOfSightOption = 1u << 9;
constexpr std::uint32_t kMovementBlockedOption = 1u << 10;
constexpr std::uint8_t kLosTransitionReason = 1u << 0;
constexpr std::uint8_t kProducerAlternationReason = 1u << 1;

struct Vector4 {
  std::array<float, 4> values = {};
};

struct MasterSnapshot {
  bool valid = false;
  std::int32_t num_slaves = 0;
  bool being_attacked = false;
  std::array<std::uint32_t, 2> slave_offsets = {};
  Vector4 target_position;
  Vector4 adjusted_target_position;
};

struct SlaveSnapshot {
  bool valid = false;
  std::uint32_t options = 0;
  std::uint32_t los_state = 0;
  std::uint32_t string_velocity_direction = 0;
  float minimum_distance_override = 0.f;
  Vector4 transform;
  Vector4 view_flat;
  Vector4 string_transform;
  Vector4 desired_position;

  bool line_of_sight_enabled() const { return (options & kLineOfSightOption) != 0; }
  bool movement_blocked() const { return (options & kMovementBlockedOption) != 0; }
};

struct CombinerSnapshot {
  bool valid = false;
  float interpolation = 0.f;
  std::uint64_t tracking_status = 0;
  Vector4 transform;
};

struct FrameSnapshot {
  bool valid = false;
  std::uint64_t engine_frame_id = 0;
  float display_time_ratio = 1.f;
  std::int32_t num_slaves = 0;
  bool being_attacked = false;
  Vector4 target_position;
  Vector4 adjusted_target_position;
  std::array<SlaveSnapshot, 2> slaves;
  CombinerSnapshot combiner;
};

struct Event {
  bool valid = false;
  std::uint8_t reason_mask = 0;
  std::uint64_t host_tick_id = 0;
  std::uint64_t chain_ordinal = 0;
  FrameSnapshot older;
  FrameSnapshot previous;
  FrameSnapshot current;
};

namespace jak1_layout {

// The decompiler's :offset-assert values include the four-byte basic-object type tag. Live GOAL
// basic pointers address the first byte after that tag, so native reads subtract four.
constexpr std::size_t kBasicObjectTypeTagBytes = 4;

constexpr std::size_t kMasterNumSlavesOffset = 116 - kBasicObjectTypeTagBytes;
constexpr std::size_t kMasterSlaveOffsetsOffset = 120 - kBasicObjectTypeTagBytes;
constexpr std::size_t kMasterBeingAttackedOffset = 348 - kBasicObjectTypeTagBytes;
constexpr std::size_t kMasterTargetPositionOffset = 528 - kBasicObjectTypeTagBytes;
constexpr std::size_t kMasterAdjustedTargetPositionOffset = 576 - kBasicObjectTypeTagBytes;
constexpr std::size_t kMasterRequiredObjectBytes = kMasterAdjustedTargetPositionOffset + 16;
constexpr std::size_t kMasterDeclaredObjectBytes = 0x964 - kBasicObjectTypeTagBytes;

constexpr std::size_t kSlaveTransformOffset = 112 - kBasicObjectTypeTagBytes;
constexpr std::size_t kSlaveMinimumDistanceOverrideOffset = 432 - kBasicObjectTypeTagBytes;
constexpr std::size_t kSlaveViewFlatOffset = 448 - kBasicObjectTypeTagBytes;
constexpr std::size_t kSlaveStringVelocityDirectionOffset = 464 - kBasicObjectTypeTagBytes;
constexpr std::size_t kSlaveStringTransformOffset = 480 - kBasicObjectTypeTagBytes;
constexpr std::size_t kSlaveOptionsOffset = 2200 - kBasicObjectTypeTagBytes;
constexpr std::size_t kSlaveDesiredPositionOffset = 2224 - kBasicObjectTypeTagBytes;
constexpr std::size_t kSlaveLosStateOffset = 2244 - kBasicObjectTypeTagBytes;
constexpr std::size_t kSlaveRequiredObjectBytes = kSlaveLosStateOffset + sizeof(std::uint32_t);
constexpr std::size_t kSlaveDeclaredObjectBytes = 0xa04 - kBasicObjectTypeTagBytes;

constexpr std::size_t kCombinerTransformOffset = 112 - kBasicObjectTypeTagBytes;
constexpr std::size_t kCombinerInterpolationOffset = 196 - kBasicObjectTypeTagBytes;
constexpr std::size_t kCombinerTrackingStatusOffset = 256 - kBasicObjectTypeTagBytes;
constexpr std::size_t kCombinerRequiredObjectBytes =
    kCombinerTrackingStatusOffset + sizeof(std::uint64_t);
constexpr std::size_t kCombinerDeclaredObjectBytes = 0x1e0 - kBasicObjectTypeTagBytes;

static_assert(kMasterRequiredObjectBytes <= kMasterDeclaredObjectBytes);
static_assert(kSlaveRequiredObjectBytes <= kSlaveDeclaredObjectBytes);
static_assert(kCombinerRequiredObjectBytes <= kCombinerDeclaredObjectBytes);

}  // namespace jak1_layout

namespace detail {

template <typename T>
bool read_value(const void* object, std::size_t object_bytes, std::size_t offset, T* out) {
  if (!object || !out || offset > object_bytes || sizeof(T) > object_bytes - offset) {
    return false;
  }
  std::memcpy(out, static_cast<const std::uint8_t*>(object) + offset, sizeof(T));
  return true;
}

inline bool read_vector(const void* object,
                        std::size_t object_bytes,
                        std::size_t offset,
                        Vector4* out) {
  return read_value(object, object_bytes, offset, &out->values);
}

}  // namespace detail

inline const void* checked_goal_object(const void* memory,
                                       std::size_t memory_bytes,
                                       std::size_t low_protect_bytes,
                                       std::uint32_t object_offset,
                                       std::uint32_t expected_type,
                                       std::size_t required_bytes,
                                       std::size_t* available_bytes) {
  if (!memory || !expected_type ||
      object_offset < low_protect_bytes + jak1_layout::kBasicObjectTypeTagBytes ||
      object_offset >= memory_bytes || required_bytes > memory_bytes - object_offset) {
    return nullptr;
  }

  const auto* bytes = static_cast<const std::uint8_t*>(memory);
  std::uint32_t actual_type = 0;
  std::memcpy(&actual_type,
              bytes + object_offset - jak1_layout::kBasicObjectTypeTagBytes,
              sizeof(actual_type));
  if (actual_type != expected_type) {
    return nullptr;
  }
  if (available_bytes) {
    *available_bytes = memory_bytes - object_offset;
  }
  return bytes + object_offset;
}

inline bool try_read_jak1_master(const void* object,
                                 std::size_t object_bytes,
                                 std::uint32_t goal_false,
                                 MasterSnapshot* out) {
  if (!object || !out || object_bytes < jak1_layout::kMasterRequiredObjectBytes) {
    return false;
  }

  MasterSnapshot snapshot;
  std::uint32_t being_attacked = 0;
  if (!detail::read_value(object, object_bytes, jak1_layout::kMasterNumSlavesOffset,
                          &snapshot.num_slaves) ||
      !detail::read_value(object, object_bytes, jak1_layout::kMasterSlaveOffsetsOffset,
                          &snapshot.slave_offsets) ||
      !detail::read_value(object, object_bytes, jak1_layout::kMasterBeingAttackedOffset,
                          &being_attacked) ||
      !detail::read_vector(object, object_bytes, jak1_layout::kMasterTargetPositionOffset,
                           &snapshot.target_position) ||
      !detail::read_vector(object, object_bytes,
                           jak1_layout::kMasterAdjustedTargetPositionOffset,
                           &snapshot.adjusted_target_position) ||
      snapshot.num_slaves < 0 || snapshot.num_slaves > 2) {
    return false;
  }
  snapshot.being_attacked = being_attacked != 0 && being_attacked != goal_false;
  snapshot.valid = true;
  *out = snapshot;
  return true;
}

inline bool try_read_jak1_slave(const void* object,
                                std::size_t object_bytes,
                                SlaveSnapshot* out) {
  if (!object || !out || object_bytes < jak1_layout::kSlaveRequiredObjectBytes) {
    return false;
  }

  SlaveSnapshot snapshot;
  if (!detail::read_vector(object, object_bytes, jak1_layout::kSlaveTransformOffset,
                           &snapshot.transform) ||
      !detail::read_value(object, object_bytes,
                          jak1_layout::kSlaveMinimumDistanceOverrideOffset,
                          &snapshot.minimum_distance_override) ||
      !detail::read_vector(object, object_bytes, jak1_layout::kSlaveViewFlatOffset,
                           &snapshot.view_flat) ||
      !detail::read_value(object, object_bytes,
                          jak1_layout::kSlaveStringVelocityDirectionOffset,
                          &snapshot.string_velocity_direction) ||
      !detail::read_vector(object, object_bytes, jak1_layout::kSlaveStringTransformOffset,
                           &snapshot.string_transform) ||
      !detail::read_value(object, object_bytes, jak1_layout::kSlaveOptionsOffset,
                          &snapshot.options) ||
      !detail::read_vector(object, object_bytes, jak1_layout::kSlaveDesiredPositionOffset,
                           &snapshot.desired_position) ||
      !detail::read_value(object, object_bytes, jak1_layout::kSlaveLosStateOffset,
                          &snapshot.los_state) ||
      snapshot.los_state > 3) {
    return false;
  }
  snapshot.valid = true;
  *out = snapshot;
  return true;
}

inline bool try_read_jak1_combiner(const void* object,
                                   std::size_t object_bytes,
                                   CombinerSnapshot* out) {
  if (!object || !out || object_bytes < jak1_layout::kCombinerRequiredObjectBytes) {
    return false;
  }

  CombinerSnapshot snapshot;
  if (!detail::read_vector(object, object_bytes, jak1_layout::kCombinerTransformOffset,
                           &snapshot.transform) ||
      !detail::read_value(object, object_bytes, jak1_layout::kCombinerInterpolationOffset,
                          &snapshot.interpolation) ||
      !detail::read_value(object, object_bytes, jak1_layout::kCombinerTrackingStatusOffset,
                          &snapshot.tracking_status)) {
    return false;
  }
  snapshot.valid = true;
  *out = snapshot;
  return true;
}

inline bool has_los_transition(const FrameSnapshot& previous, const FrameSnapshot& current) {
  if (!previous.valid || !current.valid || previous.num_slaves != current.num_slaves) {
    return false;
  }
  for (std::size_t slot = 0; slot < current.slaves.size(); ++slot) {
    if (previous.slaves[slot].valid && current.slaves[slot].valid &&
        (previous.slaves[slot].line_of_sight_enabled() ||
         current.slaves[slot].line_of_sight_enabled()) &&
        previous.slaves[slot].los_state != current.slaves[slot].los_state) {
      return true;
    }
  }
  return false;
}

class EventTrace {
 public:
  Event observe(const FrameSnapshot& snapshot,
                bool producer_alternation,
                std::uint64_t host_tick_id,
                std::uint64_t chain_ordinal) {
    Event event;
    if (!snapshot.valid) {
      return event;
    }
    if (m_history_size &&
        snapshot.engine_frame_id == m_history[m_history_size - 1].engine_frame_id) {
      return event;
    }

    const bool consecutive =
        m_history_size &&
        snapshot.engine_frame_id == m_history[m_history_size - 1].engine_frame_id + 1;
    if (!consecutive) {
      m_history[0] = snapshot;
      m_history_size = 1;
      return event;
    }

    const auto previous = m_history[m_history_size - 1];
    const bool los_transition = has_los_transition(previous, snapshot);
    if (los_transition || producer_alternation) {
      event.valid = true;
      event.reason_mask =
          (los_transition ? kLosTransitionReason : 0) |
          (producer_alternation ? kProducerAlternationReason : 0);
      event.host_tick_id = host_tick_id;
      event.chain_ordinal = chain_ordinal;
      if (m_history_size == 2) {
        event.older = m_history[0];
      }
      event.previous = previous;
      event.current = snapshot;
      m_last_event = event;
      ++m_event_count;
    }

    if (m_history_size == 1) {
      m_history[1] = snapshot;
      m_history_size = 2;
    } else {
      m_history[0] = m_history[1];
      m_history[1] = snapshot;
    }
    return event;
  }

  std::uint64_t event_count() const { return m_event_count; }
  const Event& last_event() const { return m_last_event; }

 private:
  std::array<FrameSnapshot, 2> m_history;
  std::size_t m_history_size = 0;
  std::uint64_t m_event_count = 0;
  Event m_last_event;
};

}  // namespace goalpad::camera_correction_trace
