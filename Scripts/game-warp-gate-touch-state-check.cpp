#include "GOALPad/Native/GOALPadGameBoot.hpp"

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <vector>

namespace {

constexpr std::size_t kMemoryBytes = 1024;
constexpr std::size_t kLowProtectBytes = 64;
constexpr std::uint32_t kSnapshotType = 100;
constexpr std::uint32_t kIndirectSlot = 200;
constexpr std::uint32_t kSnapshotObject = 324;
constexpr std::uint16_t kSnapshotAllocatedBytes = 0x1c;

static_assert(goalpad::warp_gate_touch_layout::kRequiredObjectBytes == 0x18);
static_assert(kSnapshotAllocatedBytes ==
              goalpad::camera_correction_trace::jak1_layout::kBasicObjectTypeTagBytes +
                  goalpad::warp_gate_touch_layout::kRequiredObjectBytes);

[[noreturn]] void fail(const char* message) {
  std::cerr << "FAIL: " << message << '\n';
  std::exit(1);
}

void expect(bool condition, const char* message) {
  if (!condition) {
    fail(message);
  }
}

template <typename T>
void write(std::vector<std::uint8_t>& memory, std::size_t offset, T value) {
  std::memcpy(memory.data() + offset, &value, sizeof(value));
}

struct Fixture {
  std::vector<std::uint8_t> memory = std::vector<std::uint8_t>(kMemoryBytes);

  Fixture() {
    write(memory, kSnapshotObject - 4, kSnapshotType);
    write(memory, kSnapshotType + 8, kSnapshotAllocatedBytes);
    set_revision(1);
    set_sequence(2);
    set_state(0);
    set_selected_slot(-1);
    set_permitted_mask(0);
    set_selection_moving(0);
  }

  void set_revision(std::int32_t value) {
    set_field(goalpad::warp_gate_touch_layout::kRevisionOffset, value);
  }

  void set_sequence(std::int32_t value) {
    set_field(goalpad::warp_gate_touch_layout::kSequenceOffset, value);
  }

  void set_state(std::int32_t value) {
    set_field(goalpad::warp_gate_touch_layout::kStateOffset, value);
  }

  void set_selected_slot(std::int32_t value) {
    set_field(goalpad::warp_gate_touch_layout::kSelectedSlotOffset, value);
  }

  void set_permitted_mask(std::int32_t value) {
    set_field(goalpad::warp_gate_touch_layout::kPermittedMaskOffset, value);
  }

  void set_selection_moving(std::int32_t value) {
    set_field(goalpad::warp_gate_touch_layout::kSelectionMovingOffset, value);
  }

  goalpad::WarpGateTouchSnapshot read(std::size_t memory_bytes = kMemoryBytes,
                                      std::uint32_t object = kSnapshotObject,
                                      std::uint32_t expected_type = kSnapshotType) const {
    return goalpad::read_warp_gate_touch_snapshot(
        memory.data(), memory_bytes, kLowProtectBytes, object, expected_type);
  }

 private:
  void set_field(std::size_t offset, std::int32_t value) {
    write(memory, kSnapshotObject + offset, value);
  }
};

}  // namespace

int main() {
  using goalpad::WarpGateTouchState;

  Fixture unavailable;
  const auto unavailable_snapshot = unavailable.read();
  expect(unavailable_snapshot.valid && unavailable_snapshot.sequence == 2 &&
             unavailable_snapshot.state == WarpGateTouchState::Unavailable &&
             unavailable_snapshot.selected_slot == -1 &&
             unavailable_snapshot.permitted_mask == 0 &&
             !unavailable_snapshot.selection_moving,
         "a valid unavailable publication remains distinct from an invalid bridge read");

  Fixture circle;
  circle.set_sequence(4);
  circle.set_state(1);
  const auto circle_snapshot = circle.read();
  expect(circle_snapshot.valid && circle_snapshot.sequence == 4 &&
             circle_snapshot.state == WarpGateTouchState::CircleUseAvailable,
         "circle-use availability decodes without native gameplay inference");

  Fixture list;
  list.set_sequence(6);
  list.set_state(2);
  list.set_selected_slot(2);
  list.set_permitted_mask(0x15);
  list.set_selection_moving(1);
  const auto list_snapshot = list.read();
  expect(list_snapshot.valid && list_snapshot.sequence == 6 &&
             list_snapshot.state == WarpGateTouchState::DestinationListActive &&
             list_snapshot.selected_slot == 2 && list_snapshot.permitted_mask == 0x15 &&
             list_snapshot.selection_moving,
         "an active destination list preserves its selection, mask, motion, and generation");

  Fixture transitioning;
  transitioning.set_sequence(8);
  transitioning.set_state(3);
  expect(transitioning.read().valid &&
             transitioning.read().state == WarpGateTouchState::Transitioning,
         "a transitioning publication is valid but carries no actionable destination data");

  Fixture indirect;
  write(indirect.memory, kIndirectSlot, kSnapshotObject);
  expect(!indirect.read(kMemoryBytes, kIndirectSlot).valid,
         "the published value is a direct basic pointer, not a ppointer slot");

  Fixture wrong_type;
  write(wrong_type.memory, kSnapshotObject - 4, std::uint32_t{108});
  expect(!wrong_type.read().valid, "a wrong GOAL object type fails closed");
  expect(!Fixture().read(kMemoryBytes, kSnapshotObject, 108).valid,
         "a wrong expected GOAL type fails closed");

  Fixture undersized;
  write(undersized.memory, kSnapshotType + 8, std::uint16_t{0x18});
  expect(!undersized.read().valid, "an allocation without the full 0x18-byte payload fails closed");

  Fixture truncated;
  expect(!truncated
              .read(kSnapshotObject + goalpad::warp_gate_touch_layout::kRequiredObjectBytes - 1)
              .valid,
         "a truncated allocation span fails closed");
  expect(!truncated.read(kMemoryBytes, kSnapshotObject + 2).valid,
         "an unaligned direct object pointer fails closed");
  expect(!truncated.read(kMemoryBytes, kLowProtectBytes).valid,
         "a direct object pointer whose type tag enters low protection fails closed");
  expect(!truncated.read(kMemoryBytes, 0).valid, "a null direct object pointer fails closed");
  expect(!truncated.read(kMemoryBytes, kMemoryBytes).valid,
         "an out-of-bounds direct object pointer fails closed");

  Fixture revision;
  revision.set_revision(2);
  expect(!revision.read().valid, "an unknown schema revision fails closed");

  Fixture odd;
  odd.set_sequence(3);
  expect(!odd.read().valid, "an in-progress odd publication fails closed");
  expect(!goalpad::validate_warp_gate_touch_snapshot(2, 1, 0, -1, 0, 0, 4).valid,
         "a sequence changed across the payload read fails closed");

  Fixture unknown_state;
  unknown_state.set_state(-1);
  expect(!unknown_state.read().valid, "a negative state fails closed");
  unknown_state.set_state(4);
  expect(!unknown_state.read().valid, "an unknown positive state fails closed");

  Fixture neutral_selected;
  neutral_selected.set_selected_slot(0);
  expect(!neutral_selected.read().valid, "unavailable state rejects a selected destination");

  Fixture circle_mask;
  circle_mask.set_state(1);
  circle_mask.set_permitted_mask(1);
  expect(!circle_mask.read().valid, "circle-use state rejects a destination mask");

  Fixture transition_moving;
  transition_moving.set_state(3);
  transition_moving.set_selection_moving(1);
  expect(!transition_moving.read().valid, "transitioning state rejects selection motion");

  Fixture list_selected_low;
  list_selected_low.set_state(2);
  list_selected_low.set_selected_slot(-1);
  list_selected_low.set_permitted_mask(1);
  expect(!list_selected_low.read().valid, "destination state rejects a negative selected slot");

  Fixture list_selected_high;
  list_selected_high.set_state(2);
  list_selected_high.set_selected_slot(5);
  list_selected_high.set_permitted_mask(1);
  expect(!list_selected_high.read().valid, "destination state rejects a selected slot above four");

  Fixture list_empty;
  list_empty.set_state(2);
  list_empty.set_selected_slot(0);
  expect(!list_empty.read().valid, "destination state rejects an empty permitted mask");

  Fixture list_high_bit;
  list_high_bit.set_state(2);
  list_high_bit.set_selected_slot(0);
  list_high_bit.set_permitted_mask(0x21);
  expect(!list_high_bit.read().valid, "destination state rejects mask bits above 0x1f");

  Fixture list_selected_absent;
  list_selected_absent.set_state(2);
  list_selected_absent.set_selected_slot(2);
  list_selected_absent.set_permitted_mask(0x03);
  expect(!list_selected_absent.read().valid,
         "destination state rejects a selected slot absent from the permitted mask");

  Fixture list_moving_low;
  list_moving_low.set_state(2);
  list_moving_low.set_selected_slot(0);
  list_moving_low.set_permitted_mask(1);
  list_moving_low.set_selection_moving(-1);
  expect(!list_moving_low.read().valid, "destination state rejects negative selection motion");

  Fixture list_moving_high;
  list_moving_high.set_state(2);
  list_moving_high.set_selected_slot(0);
  list_moving_high.set_permitted_mask(1);
  list_moving_high.set_selection_moving(2);
  expect(!list_moving_high.read().valid, "destination state rejects selection motion above one");

  std::cout << "game warp-gate touch state check passed\n";
  return 0;
}
