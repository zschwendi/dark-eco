#include "GOALPad/Native/GOALPadCameraCorrectionTrace.hpp"

#include <array>
#include <cstdio>
#include <cstring>

namespace {

using namespace goalpad::camera_correction_trace;

int failures = 0;

void check(bool condition, const char* description) {
  if (condition) {
    std::printf("ok   %s\n", description);
  } else {
    std::printf("FAIL %s\n", description);
    ++failures;
  }
}

template <std::size_t Size, typename T>
void write(std::array<std::uint8_t, Size>& object, std::size_t offset, const T& value) {
  std::memcpy(object.data() + offset, &value, sizeof(value));
}

Vector4 vector(float first) {
  return {{{first, first + 1.f, first + 2.f, first + 3.f}}};
}

SlaveSnapshot slave(std::uint32_t los_state, float first) {
  SlaveSnapshot out;
  out.valid = true;
  out.options = kLineOfSightOption | kMovementBlockedOption;
  out.los_state = los_state;
  out.transform = vector(first);
  out.view_flat = vector(first + 10.f);
  out.string_transform = vector(first + 20.f);
  out.desired_position = vector(first + 30.f);
  return out;
}

FrameSnapshot frame(std::uint64_t frame_id, std::uint32_t los_state, float first) {
  FrameSnapshot out;
  out.valid = true;
  out.engine_frame_id = frame_id;
  out.num_slaves = 1;
  out.slaves[0] = slave(los_state, first);
  return out;
}

}  // namespace

int main() {
  using namespace goalpad::camera_correction_trace;

  std::array<std::uint8_t, 128> goal_memory = {};
  constexpr std::uint32_t object_offset = 32;
  constexpr std::uint32_t object_type = 0x44556677;
  write(goal_memory, object_offset - jak1_layout::kBasicObjectTypeTagBytes, object_type);
  std::size_t available_bytes = 0;
  check(checked_goal_object(goal_memory.data(), goal_memory.size(), 16, object_offset,
                            object_type, 32, &available_bytes) ==
                goal_memory.data() + object_offset &&
            available_bytes == goal_memory.size() - object_offset &&
            !checked_goal_object(goal_memory.data(), goal_memory.size(), 32, object_offset,
                                 object_type, 1, nullptr) &&
            !checked_goal_object(goal_memory.data(), goal_memory.size(), 16, object_offset,
                                 object_type + 1, 1, nullptr) &&
            !checked_goal_object(goal_memory.data(), goal_memory.size(), 16, 120,
                                 object_type, 9, nullptr),
        "GOAL object views require a bounded object and the expected type tag");

  std::array<std::uint8_t, jak1_layout::kMasterDeclaredObjectBytes> master_bytes = {};
  const std::int32_t num_slaves = 2;
  const std::array<std::uint32_t, 2> slave_offsets = {0x1234, 0x5678};
  const std::uint32_t goal_false = 0x1000;
  const std::uint32_t goal_true = 0x1004;
  const auto target = vector(10.f);
  const auto adjusted_target = vector(20.f);
  write(master_bytes, jak1_layout::kMasterNumSlavesOffset, num_slaves);
  write(master_bytes, jak1_layout::kMasterSlaveOffsetsOffset, slave_offsets);
  write(master_bytes, jak1_layout::kMasterBeingAttackedOffset, goal_true);
  write(master_bytes, jak1_layout::kMasterTargetPositionOffset, target.values);
  write(master_bytes, jak1_layout::kMasterAdjustedTargetPositionOffset,
        adjusted_target.values);

  MasterSnapshot master;
  check(try_read_jak1_master(master_bytes.data(), master_bytes.size(), goal_false, &master) &&
            master.valid && master.num_slaves == 2 && master.being_attacked &&
            master.slave_offsets == slave_offsets &&
            master.target_position.values == target.values &&
            master.adjusted_target_position.values == adjusted_target.values,
        "the Jak 1 camera-master snapshot reads asserted fields after the basic tag");

  std::array<std::uint8_t, jak1_layout::kSlaveDeclaredObjectBytes> slave_bytes = {};
  const auto transform = vector(30.f);
  const auto view_flat = vector(40.f);
  const auto string_transform = vector(50.f);
  const auto desired_position = vector(60.f);
  const float minimum_distance = 70.f;
  const std::uint32_t string_direction = 6;
  const std::uint32_t options = kLineOfSightOption | kMovementBlockedOption;
  const std::uint32_t los_state = 2;
  write(slave_bytes, jak1_layout::kSlaveTransformOffset, transform.values);
  write(slave_bytes, jak1_layout::kSlaveMinimumDistanceOverrideOffset, minimum_distance);
  write(slave_bytes, jak1_layout::kSlaveViewFlatOffset, view_flat.values);
  write(slave_bytes, jak1_layout::kSlaveStringVelocityDirectionOffset, string_direction);
  write(slave_bytes, jak1_layout::kSlaveStringTransformOffset, string_transform.values);
  write(slave_bytes, jak1_layout::kSlaveOptionsOffset, options);
  write(slave_bytes, jak1_layout::kSlaveDesiredPositionOffset, desired_position.values);
  write(slave_bytes, jak1_layout::kSlaveLosStateOffset, los_state);

  SlaveSnapshot slave_snapshot;
  check(try_read_jak1_slave(slave_bytes.data(), slave_bytes.size(), &slave_snapshot) &&
            slave_snapshot.valid && slave_snapshot.los_state == 2 &&
            slave_snapshot.string_velocity_direction == 6 &&
            slave_snapshot.minimum_distance_override == minimum_distance &&
            slave_snapshot.line_of_sight_enabled() && slave_snapshot.movement_blocked() &&
            slave_snapshot.transform.values == transform.values &&
            slave_snapshot.view_flat.values == view_flat.values &&
            slave_snapshot.string_transform.values == string_transform.values &&
            slave_snapshot.desired_position.values == desired_position.values,
        "the Jak 1 camera-slave snapshot preserves LOS, options, and transforms");

  std::array<std::uint8_t, jak1_layout::kCombinerDeclaredObjectBytes> combiner_bytes = {};
  const auto combiner_transform = vector(80.f);
  const float interpolation = 0.375f;
  const std::uint64_t tracking_status = 3;
  write(combiner_bytes, jak1_layout::kCombinerTransformOffset, combiner_transform.values);
  write(combiner_bytes, jak1_layout::kCombinerInterpolationOffset, interpolation);
  write(combiner_bytes, jak1_layout::kCombinerTrackingStatusOffset, tracking_status);

  CombinerSnapshot combiner;
  check(try_read_jak1_combiner(combiner_bytes.data(), combiner_bytes.size(), &combiner) &&
            combiner.valid && combiner.interpolation == interpolation &&
            combiner.tracking_status == tracking_status &&
            combiner.transform.values == combiner_transform.values,
        "the Jak 1 camera combiner snapshot preserves interpolation, tracking, and transform");

  MasterSnapshot unchanged_master;
  unchanged_master.num_slaves = 17;
  SlaveSnapshot unchanged_slave;
  unchanged_slave.los_state = 17;
  CombinerSnapshot unchanged_combiner;
  unchanged_combiner.interpolation = 17.f;
  check(!try_read_jak1_master(master_bytes.data(),
                              jak1_layout::kMasterRequiredObjectBytes - 1, goal_false,
                              &unchanged_master) &&
            unchanged_master.num_slaves == 17 &&
            !try_read_jak1_slave(slave_bytes.data(),
                                 jak1_layout::kSlaveRequiredObjectBytes - 1,
                                 &unchanged_slave) &&
            unchanged_slave.los_state == 17 &&
            !try_read_jak1_combiner(combiner_bytes.data(),
                                    jak1_layout::kCombinerRequiredObjectBytes - 1,
                                    &unchanged_combiner) &&
            unchanged_combiner.interpolation == 17.f &&
            !try_read_jak1_master(nullptr, master_bytes.size(), goal_false, &master) &&
            !try_read_jak1_slave(slave_bytes.data(), slave_bytes.size(), nullptr),
        "null and truncated camera objects fail without changing caller-owned output");

  EventTrace trace;
  check(!trace.observe(frame(100, 0, 0.f), false, 10, 1).valid &&
            !trace.observe(frame(101, 0, 1.f), false, 11, 1).valid,
        "ordinary consecutive camera frames do not emit correction events");
  const auto los_event = trace.observe(frame(102, 1, 2.f), false, 12, 1);
  check(los_event.valid && los_event.reason_mask == kLosTransitionReason &&
            los_event.older.engine_frame_id == 100 &&
            los_event.previous.engine_frame_id == 101 &&
            los_event.current.engine_frame_id == 102 &&
            los_event.previous.slaves[0].los_state == 0 &&
            los_event.current.slaves[0].los_state == 1 && trace.event_count() == 1,
        "a LOS transition emits one retained three-frame event");
  check(!trace.observe(frame(103, 1, 3.f), false, 13, 1).valid &&
            trace.last_event().current.engine_frame_id == 102,
        "a later ordinary frame does not erase retained LOS evidence");
  const auto alternation_event = trace.observe(frame(104, 1, 2.f), true, 14, 2);
  check(alternation_event.valid &&
            alternation_event.reason_mask == kProducerAlternationReason &&
            alternation_event.current.engine_frame_id == 104 && trace.event_count() == 2,
        "an existing producer A/B/A observation emits even when LOS is stable");
  check(!trace.observe(frame(104, 2, 9.f), true, 99, 9).valid && trace.event_count() == 2,
        "a duplicate engine frame cannot emit the same event twice");

  EventTrace dual_trace;
  auto dual_first = frame(200, 0, 0.f);
  dual_first.num_slaves = 2;
  dual_first.slaves[1] = slave(2, 100.f);
  auto dual_second = frame(201, 0, 1.f);
  dual_second.num_slaves = 2;
  dual_second.slaves[1] = slave(3, 101.f);
  dual_trace.observe(dual_first, false, 20, 1);
  const auto dual_event = dual_trace.observe(dual_second, false, 21, 1);
  check(dual_event.valid && dual_event.current.slaves[0].los_state == 0 &&
            dual_event.current.slaves[1].los_state == 3 &&
            dual_event.current.slaves[0].transform.values !=
                dual_event.current.slaves[1].transform.values,
        "two active slave slots retain independent LOS and transform state");

  auto transition_start = frame(202, 3, 2.f);
  transition_start.num_slaves = 1;
  check(!dual_trace.observe(transition_start, false, 22, 1).valid,
        "a slave-count transition does not masquerade as a LOS transition");
  check(!dual_trace.observe(frame(204, 1, 4.f), true, 24, 1).valid,
        "a frame gap resets bounded correction history before event attribution");

  EventTrace disabled_los_trace;
  auto disabled_los_first = frame(300, 0, 0.f);
  auto disabled_los_second = frame(301, 1, 1.f);
  disabled_los_first.slaves[0].options = 0;
  disabled_los_second.slaves[0].options = 0;
  disabled_los_trace.observe(disabled_los_first, false, 30, 1);
  check(!disabled_los_trace.observe(disabled_los_second, false, 31, 1).valid,
        "a stale LOS enum change does not emit when line-of-sight correction is disabled");

  return failures ? 1 : 0;
}
