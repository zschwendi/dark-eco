#include "GOALPad/Native/GOALPadCameraCorrectionTrace.hpp"

#include <array>
#include <cmath>
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
  out.math_camera_object_offset = static_cast<std::uint32_t>(0x0800 + frame_id);
  out.math_camera_type_offset = 0x804;
  out.master_object_offset = static_cast<std::uint32_t>(0x1000 + frame_id);
  out.master_type_offset = 0x1004;
  out.combiner_object_offset = static_cast<std::uint32_t>(0x2000 + frame_id);
  out.combiner_type_offset = 0x2004;
  out.slave_ppointer_offsets = {
      static_cast<std::uint32_t>(0x3000 + frame_id),
      static_cast<std::uint32_t>(0x4000 + frame_id)};
  out.slave_object_offsets = {
      static_cast<std::uint32_t>(0x5000 + frame_id),
      static_cast<std::uint32_t>(0x6000 + frame_id)};
  out.slave_type_offsets = {0x5004, 0x6004};
  out.num_slaves = 1;
  out.slaves[0] = slave(los_state, first);
  return out;
}

FrameSnapshot orientation_frame(std::uint64_t frame_id, float forward_x, float forward_z) {
  auto out = frame(frame_id, 0, 0.f);
  out.combiner.valid = true;
  out.combiner.inverse_camera_rotation.axes[0].values =
      {forward_z, 0.f, -forward_x, 0.f};
  out.combiner.inverse_camera_rotation.axes[1].values = {0.f, 1.f, 0.f, 0.f};
  out.combiner.inverse_camera_rotation.axes[2].values =
      {forward_x, 0.f, forward_z, 0.f};
  return out;
}

FrameSnapshot orientation_degrees_frame(std::uint64_t frame_id, double degrees) {
  const double radians = degrees * (3.14159265358979323846 / 180.0);
  return orientation_frame(frame_id, static_cast<float>(std::sin(radians)),
                           static_cast<float>(std::cos(radians)));
}

}  // namespace

int main() {
  using namespace goalpad::camera_correction_trace;

  std::array<std::uint8_t, 512> goal_memory = {};
  constexpr std::size_t low_protect_bytes = 16;
  constexpr std::uint32_t goal_false = 0x14;
  constexpr std::uint32_t expected_type = 0x44;
  constexpr std::uint32_t derived_type = 0x64;
  constexpr std::uint32_t unrelated_type = 0x84;
  constexpr std::uint32_t cycle_type_a = 0xa4;
  constexpr std::uint32_t cycle_type_b = 0xc4;
  constexpr std::uint32_t out_of_range_parent_type = 0xe4;
  constexpr std::uint32_t undersized_type = 0x104;
  constexpr std::uint32_t ppointer_offset = 0x120;
  constexpr std::uint32_t object_offset = 0x144;
  constexpr std::uint16_t allocated_size = 64;
  constexpr std::uint16_t undersized_allocation = 20;

  write(goal_memory, expected_type + jak1_layout::kTypeAllocatedSizeOffset, allocated_size);
  write(goal_memory, derived_type + jak1_layout::kTypeParentOffset,
        expected_type | 0x80000000u);
  write(goal_memory, derived_type + jak1_layout::kTypeAllocatedSizeOffset, allocated_size);
  write(goal_memory, unrelated_type + jak1_layout::kTypeAllocatedSizeOffset, allocated_size);
  write(goal_memory, cycle_type_a + jak1_layout::kTypeParentOffset, cycle_type_b);
  write(goal_memory, cycle_type_a + jak1_layout::kTypeAllocatedSizeOffset, allocated_size);
  write(goal_memory, cycle_type_b + jak1_layout::kTypeParentOffset, cycle_type_a);
  write(goal_memory, cycle_type_b + jak1_layout::kTypeAllocatedSizeOffset, allocated_size);
  write(goal_memory, out_of_range_parent_type + jak1_layout::kTypeParentOffset, 0x80000404u);
  write(goal_memory, out_of_range_parent_type + jak1_layout::kTypeAllocatedSizeOffset,
        allocated_size);
  write(goal_memory, undersized_type + jak1_layout::kTypeParentOffset, expected_type);
  write(goal_memory, undersized_type + jak1_layout::kTypeAllocatedSizeOffset,
        undersized_allocation);

  write(goal_memory, object_offset - jak1_layout::kBasicObjectTypeTagBytes, expected_type);
  std::size_t available_bytes = 0;
  std::uint32_t actual_type = 0;
  check(checked_goal_object(goal_memory.data(), goal_memory.size(), low_protect_bytes,
                            object_offset | 0x80000000u, expected_type | 0x80000000u, 32,
                            &available_bytes, &actual_type) ==
                goal_memory.data() + object_offset &&
            available_bytes == allocated_size - jak1_layout::kBasicObjectTypeTagBytes &&
            actual_type == expected_type,
        "GOAL object views retain an exact normalized runtime type");

  write(goal_memory, object_offset - jak1_layout::kBasicObjectTypeTagBytes,
        derived_type | 0x80000000u);
  actual_type = 0;
  check(checked_goal_object(goal_memory.data(), goal_memory.size(), low_protect_bytes,
                            object_offset, expected_type, 32, nullptr, &actual_type) ==
                goal_memory.data() + object_offset &&
            actual_type == derived_type,
        "GOAL object views retain a bounded descendant runtime type");

  actual_type = 0;
  check(read_goal_object_type(goal_memory.data(), goal_memory.size(), low_protect_bytes,
                              object_offset | 0x80000000u, &actual_type) &&
            actual_type == derived_type,
        "GOAL object identity reads normalize object and runtime type pointers");

  write(goal_memory, object_offset - jak1_layout::kBasicObjectTypeTagBytes, unrelated_type);
  check(!checked_goal_object(goal_memory.data(), goal_memory.size(), low_protect_bytes,
                             object_offset, expected_type, 32, nullptr),
        "GOAL object views reject an unrelated runtime type");

  write(goal_memory, object_offset - jak1_layout::kBasicObjectTypeTagBytes, cycle_type_a);
  check(!checked_goal_object(goal_memory.data(), goal_memory.size(), low_protect_bytes,
                             object_offset, expected_type, 32, nullptr),
        "GOAL object views reject a cyclic parent chain");

  write(goal_memory, object_offset - jak1_layout::kBasicObjectTypeTagBytes,
        out_of_range_parent_type);
  check(!checked_goal_object(goal_memory.data(), goal_memory.size(), low_protect_bytes,
                             object_offset, expected_type, 32, nullptr),
        "GOAL object views reject an out-of-range parent type");

  write(goal_memory, object_offset - jak1_layout::kBasicObjectTypeTagBytes, undersized_type);
  check(!checked_goal_object(goal_memory.data(), goal_memory.size(), low_protect_bytes,
                             object_offset, expected_type, 32, nullptr),
        "GOAL object views reject a runtime type too small for requested fields");

  write(goal_memory, object_offset - jak1_layout::kBasicObjectTypeTagBytes, expected_type);
  check(!checked_goal_object(goal_memory.data(), goal_memory.size(), object_offset,
                             object_offset, expected_type, 1, nullptr) &&
            !checked_goal_object(goal_memory.data(), goal_memory.size(), low_protect_bytes,
                                 0x1fc, expected_type, 9, nullptr),
        "GOAL object views reject protected and truncated object spans");
  constexpr std::uint32_t truncated_allocation_offset = 0x1e4;
  write(goal_memory,
        truncated_allocation_offset - jak1_layout::kBasicObjectTypeTagBytes,
        expected_type);
  check(!checked_goal_object(goal_memory.data(), goal_memory.size(), low_protect_bytes,
                             truncated_allocation_offset, expected_type, 1, nullptr),
        "GOAL object views reject an allocated object span beyond EE memory");

  write(goal_memory, ppointer_offset, object_offset | 0x80000000u);
  std::uint32_t resolved_object = 0;
  check(resolve_goal_ppointer(goal_memory.data(), goal_memory.size(), low_protect_bytes,
                              goal_false, ppointer_offset | 0x80000000u,
                              &resolved_object) &&
            resolved_object == object_offset,
        "camera slave ppointers resolve one bounded process-object pointer");

  write(goal_memory, ppointer_offset, std::uint32_t{0});
  check(!resolve_goal_ppointer(goal_memory.data(), goal_memory.size(), low_protect_bytes,
                               goal_false, ppointer_offset, &resolved_object),
        "camera slave ppointers reject a null process object");
  write(goal_memory, ppointer_offset, goal_false);
  check(!resolve_goal_ppointer(goal_memory.data(), goal_memory.size(), low_protect_bytes,
                               goal_false, ppointer_offset, &resolved_object),
        "camera slave ppointers reject GOAL false");
  write(goal_memory, ppointer_offset, 0x80000404u);
  check(!resolve_goal_ppointer(goal_memory.data(), goal_memory.size(), low_protect_bytes,
                               goal_false, ppointer_offset, &resolved_object) &&
            !resolve_goal_ppointer(goal_memory.data(), goal_memory.size(), low_protect_bytes,
                                   goal_false, 0x80000400u, &resolved_object) &&
            !resolve_goal_ppointer(goal_memory.data(), goal_memory.size(), low_protect_bytes,
                                   goal_false, ppointer_offset + 1, &resolved_object),
        "camera slave ppointers reject out-of-range and unaligned pointer spans");

  std::array<std::uint8_t, jak1_layout::kMasterDeclaredObjectBytes> master_bytes = {};
  const std::int32_t num_slaves = 2;
  const std::array<std::uint32_t, 2> slave_offsets = {0x1234, 0x5678};
  const std::uint32_t snapshot_goal_false = 0x1000;
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
  check(try_read_jak1_master(master_bytes.data(), master_bytes.size(), snapshot_goal_false,
                             &master) &&
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
  const std::array<Vector4, 3> tracking_axes = {
      vector(100.f), vector(110.f), vector(120.f)};
  const float minimum_distance = 70.f;
  const float max_angle_offset = 80.f;
  const float max_angle_current = 75.f;
  const std::uint32_t string_direction = 6;
  const std::uint32_t options = kLineOfSightOption | kMovementBlockedOption;
  const std::uint32_t los_state = 2;
  write(slave_bytes, jak1_layout::kSlaveTransformOffset, transform.values);
  for (std::size_t axis = 0; axis < tracking_axes.size(); ++axis) {
    write(slave_bytes, jak1_layout::kSlaveTrackingInverseMatrixOffset + axis * 16,
          tracking_axes[axis].values);
  }
  write(slave_bytes, jak1_layout::kSlaveMinimumDistanceOverrideOffset, minimum_distance);
  write(slave_bytes, jak1_layout::kSlaveViewFlatOffset, view_flat.values);
  write(slave_bytes, jak1_layout::kSlaveStringVelocityDirectionOffset, string_direction);
  write(slave_bytes, jak1_layout::kSlaveStringTransformOffset, string_transform.values);
  write(slave_bytes, jak1_layout::kSlaveMaxAngleOffsetOffset, max_angle_offset);
  write(slave_bytes, jak1_layout::kSlaveMaxAngleCurrentOffset, max_angle_current);
  write(slave_bytes, jak1_layout::kSlaveOptionsOffset, options);
  write(slave_bytes, jak1_layout::kSlaveDesiredPositionOffset, desired_position.values);
  write(slave_bytes, jak1_layout::kSlaveLosStateOffset, los_state);

  SlaveSnapshot slave_snapshot;
  check(try_read_jak1_slave(slave_bytes.data(), slave_bytes.size(), &slave_snapshot) &&
            slave_snapshot.valid && slave_snapshot.los_state == 2 &&
            slave_snapshot.string_velocity_direction == 6 &&
            slave_snapshot.minimum_distance_override == minimum_distance &&
            slave_snapshot.max_angle_offset == max_angle_offset &&
            slave_snapshot.max_angle_current == max_angle_current &&
            slave_snapshot.line_of_sight_enabled() && slave_snapshot.movement_blocked() &&
            slave_snapshot.transform.values == transform.values &&
            slave_snapshot.tracking_inverse_matrix.axes[0].values == tracking_axes[0].values &&
            slave_snapshot.tracking_inverse_matrix.axes[1].values == tracking_axes[1].values &&
            slave_snapshot.tracking_inverse_matrix.axes[2].values == tracking_axes[2].values &&
            slave_snapshot.view_flat.values == view_flat.values &&
            slave_snapshot.string_transform.values == string_transform.values &&
            slave_snapshot.desired_position.values == desired_position.values,
        "the Jak 1 camera-slave snapshot preserves collision, angle, and rotation state");

  std::array<std::uint8_t, jak1_layout::kCombinerDeclaredObjectBytes> combiner_bytes = {};
  const auto combiner_transform = vector(80.f);
  const std::array<Vector4, 3> combiner_axes = {
      vector(130.f), vector(140.f), vector(150.f)};
  const float interpolation = 0.375f;
  const std::uint64_t tracking_status = 3;
  write(combiner_bytes, jak1_layout::kCombinerTransformOffset, combiner_transform.values);
  for (std::size_t axis = 0; axis < combiner_axes.size(); ++axis) {
    write(combiner_bytes, jak1_layout::kCombinerInverseCameraRotationOffset + axis * 16,
          combiner_axes[axis].values);
  }
  write(combiner_bytes, jak1_layout::kCombinerInterpolationOffset, interpolation);
  write(combiner_bytes, jak1_layout::kCombinerTrackingStatusOffset, tracking_status);

  CombinerSnapshot combiner;
  check(try_read_jak1_combiner(combiner_bytes.data(), combiner_bytes.size(), &combiner) &&
            combiner.valid && combiner.interpolation == interpolation &&
            combiner.tracking_status == tracking_status &&
            combiner.transform.values == combiner_transform.values &&
            combiner.inverse_camera_rotation.axes[0].values == combiner_axes[0].values &&
            combiner.inverse_camera_rotation.axes[1].values == combiner_axes[1].values &&
            combiner.inverse_camera_rotation.axes[2].values == combiner_axes[2].values,
        "the Jak 1 camera combiner snapshot preserves interpolation, tracking, transform, and rotation axes");

  MasterSnapshot unchanged_master;
  unchanged_master.num_slaves = 17;
  SlaveSnapshot unchanged_slave;
  unchanged_slave.los_state = 17;
  CombinerSnapshot unchanged_combiner;
  unchanged_combiner.interpolation = 17.f;
  check(!try_read_jak1_master(master_bytes.data(),
                              jak1_layout::kMasterRequiredObjectBytes - 1,
                              snapshot_goal_false,
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
            !try_read_jak1_master(nullptr, master_bytes.size(), snapshot_goal_false, &master) &&
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
            los_event.previous.master_object_offset == 0x1000 + 101 &&
            los_event.previous.master_type_offset == 0x1004 &&
            los_event.current.combiner_object_offset == 0x2000 + 102 &&
            los_event.current.combiner_type_offset == 0x2004 &&
            los_event.previous.slave_ppointer_offsets[0] == 0x3000 + 101 &&
            los_event.current.slave_object_offsets[0] == 0x5000 + 102 &&
            los_event.current.slave_type_offsets[0] == 0x5004 &&
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

  EventTrace orientation_trace;
  check(!orientation_trace.observe(orientation_frame(400, 0.f, 1.f), false, 40, 1).valid &&
            !orientation_trace
                 .observe(orientation_frame(401, 0.34202015f, 0.93969262f), false, 41, 1)
                 .valid,
        "a bounded camera rotation below thirty degrees does not emit");
  const auto orientation_event =
      orientation_trace.observe(orientation_frame(402, -1.f, 0.f), false, 42, 1);
  check(orientation_event.valid &&
            orientation_event.reason_mask == kLargeOrientationDeltaReason &&
            orientation_event.older.engine_frame_id == 400 &&
            orientation_event.previous.engine_frame_id == 401 &&
            orientation_event.current.engine_frame_id == 402 &&
            orientation_trace.event_count() == 1,
        "a large combined-camera orientation delta retains one three-frame event");

  auto degenerate_orientation = orientation_frame(403, 0.f, 0.f);
  check(!orientation_trace.observe(degenerate_orientation, false, 43, 1).valid &&
            orientation_trace.event_count() == 1,
        "a degenerate camera axis cannot fabricate an orientation event");

  EventTrace render_alternation_trace;
  render_alternation_trace.observe(orientation_degrees_frame(500, 0.0), false, false, 50, 1,
                                   5000);
  const auto render_event = render_alternation_trace.observe(
      orientation_degrees_frame(501, 0.0), false, true, 51, 2, 5001);
  check(render_event.valid && render_event.reason_mask == kRenderAlternationReason &&
            render_event.current.engine_frame_id == 501,
        "a full render-camera A/B/A emits independently of the producer subset");

  EventTrace repeated_reversal_trace;
  for (std::uint64_t offset = 0; offset < kTailFrameCapacity; ++offset) {
    const double degrees = (offset % 2 == 0) ? -8.0 : 8.0;
    repeated_reversal_trace.observe(orientation_degrees_frame(600 + offset, degrees), false,
                                    false, 700 + offset, 800 + offset, 900 + offset);
  }
  const auto& reversal_tail = repeated_reversal_trace.last_tail();
  check(reversal_tail.valid && reversal_tail.complete &&
            reversal_tail.count == kTailFrameCapacity &&
            reversal_tail.trigger_engine_frame_id == 601 &&
            reversal_tail.trigger_orientation_degrees >= 14.0 &&
            reversal_tail.trigger_orientation_degrees <= 20.0 &&
            reversal_tail.frames.front().camera.engine_frame_id == 600 &&
            reversal_tail.frames.back().camera.engine_frame_id == 617 &&
            reversal_tail.frames.front().host_tick_id == 700 &&
            reversal_tail.frames.back().chain_ordinal == 817 &&
            reversal_tail.frames.back().render_camera_fingerprint == 917,
        "repeated 14-20 degree reversals retain the trigger and sixteen post-trigger frames");

  repeated_reversal_trace.observe(orientation_degrees_frame(618, -8.0), false, false, 718, 818,
                                  918);
  const auto& preserved_complete_tail = repeated_reversal_trace.last_tail();
  check(preserved_complete_tail.valid && preserved_complete_tail.complete &&
            preserved_complete_tail.trigger_engine_frame_id == 601 &&
            preserved_complete_tail.frames.front().camera.engine_frame_id == 600 &&
            preserved_complete_tail.frames.back().camera.engine_frame_id == 617,
        "the next continuous reversal cannot replace the last completed camera tail");

  for (std::uint64_t offset = 0; offset < kTailFrameCapacity; ++offset) {
    const double degrees = (offset % 2 == 0) ? -9.0 : 9.0;
    repeated_reversal_trace.observe(orientation_degrees_frame(900 + offset, degrees), false,
                                    false, 1700 + offset, 1800 + offset, 1900 + offset);
  }
  const auto& replacement_tail = repeated_reversal_trace.last_tail();
  check(replacement_tail.valid && replacement_tail.complete &&
            replacement_tail.count == kTailFrameCapacity &&
            replacement_tail.trigger_engine_frame_id == 901 &&
            replacement_tail.frames.front().camera.engine_frame_id == 900 &&
            replacement_tail.frames.back().camera.engine_frame_id == 917 &&
            replacement_tail.frames.front().camera.master_object_offset == 0x1000 + 900 &&
            replacement_tail.frames.front().camera.math_camera_object_offset == 0x0800 + 900 &&
            replacement_tail.frames.back().camera.slave_ppointer_offsets[1] == 0x4000 + 917 &&
            replacement_tail.frames.back().camera.slave_object_offsets[1] == 0x6000 + 917 &&
            replacement_tail.frames.back().camera.slave_type_offsets[1] == 0x6004 &&
            replacement_tail.frames.front().host_tick_id == 1700 &&
            replacement_tail.frames.back().render_camera_fingerprint == 1917,
        "a later qualifying reversal window replaces an earlier completed camera tail");

  EventTrace smooth_pan_trace;
  for (std::uint64_t offset = 0; offset < 32; ++offset) {
    smooth_pan_trace.observe(orientation_degrees_frame(700 + offset, double(offset)), false,
                             false, 1000 + offset, 1, 2000 + offset);
  }
  check(!smooth_pan_trace.last_tail().valid,
        "a smooth pan of at most one degree per frame does not retain a camera tail");

  EventTrace malformed_tail_trace;
  malformed_tail_trace.observe(orientation_degrees_frame(800, 0.0), false, false, 1200, 1,
                               2200);
  malformed_tail_trace.observe(orientation_frame(801, 0.f, 0.f), false, false, 1201, 1, 2201);
  check(!malformed_tail_trace.last_tail().valid,
        "a malformed combiner basis cannot trigger the temporal camera tail");

  return failures ? 1 : 0;
}
