#include "GOALPad/Native/GOALPadGameBoot.hpp"

#include <array>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <vector>

namespace {

constexpr std::size_t kMemoryBytes = 1024;
constexpr std::size_t kLowProtectBytes = 64;
constexpr std::uint32_t kSnapshotType = 100;
constexpr std::uint32_t kSnapshotObject = 324;
constexpr std::uint16_t kSnapshotAllocatedBytes = 0x1c;

static_assert(goalpad::face_prompt_touch_layout::kRequiredObjectBytes == 0x18);
static_assert(kSnapshotAllocatedBytes ==
              goalpad::camera_correction_trace::jak1_layout::kBasicObjectTypeTagBytes +
                  goalpad::face_prompt_touch_layout::kRequiredObjectBytes);
static_assert(goalpad::face_prompt_touch_layout::kRevisionOffset + 4 == 4);
static_assert(goalpad::face_prompt_touch_layout::kSequenceOffset + 4 == 8);
static_assert(goalpad::face_prompt_touch_layout::kRequestedButtonsOffset + 4 == 12);
static_assert(goalpad::face_prompt_touch_layout::kOwnerOffset + 4 == 16);
static_assert(goalpad::face_prompt_touch_layout::kHeartbeatOffset + 4 == 24);
static_assert(goalpad::face_prompt_touch_layout::kTriangleButton == (1u << 12));
static_assert(goalpad::face_prompt_touch_layout::kCircleButton == (1u << 13));
static_assert(goalpad::face_prompt_touch_layout::kCrossButton == (1u << 14));
static_assert(goalpad::face_prompt_touch_layout::kSquareButton == (1u << 15));

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
  goalpad::FacePromptTouchReader reader;

  Fixture() {
    write(memory, kSnapshotObject - 4, kSnapshotType);
    write(memory, kSnapshotType + 8, kSnapshotAllocatedBytes);
    set_revision(1);
    set_sequence(2);
    set_requested_buttons(goalpad::face_prompt_touch_layout::kCrossButton);
    set_owner(0x1234000056780000ull);
    set_heartbeat(10);
  }

  void set_revision(std::int32_t value) {
    set_field(goalpad::face_prompt_touch_layout::kRevisionOffset, value);
  }

  void set_sequence(std::int32_t value) {
    set_field(goalpad::face_prompt_touch_layout::kSequenceOffset, value);
  }

  void set_requested_buttons(std::uint32_t value) {
    set_field(goalpad::face_prompt_touch_layout::kRequestedButtonsOffset,
              static_cast<std::int32_t>(value));
  }

  void set_owner(std::uint64_t value) {
    write(memory, kSnapshotObject + goalpad::face_prompt_touch_layout::kOwnerOffset, value);
  }

  void set_heartbeat(std::int32_t value) {
    set_field(goalpad::face_prompt_touch_layout::kHeartbeatOffset, value);
  }

  void clear(std::int32_t sequence) {
    set_sequence(sequence);
    set_requested_buttons(0);
    set_owner(0);
    set_heartbeat(0);
  }

  goalpad::FacePromptTouchRawSnapshot read_raw(
      std::size_t memory_bytes = kMemoryBytes,
      std::uint32_t object = kSnapshotObject,
      std::uint32_t expected_type = kSnapshotType) const {
    return goalpad::read_face_prompt_touch_raw_snapshot(
        memory.data(), memory_bytes, kLowProtectBytes, object, expected_type);
  }

  goalpad::FacePromptTouchSnapshot read(std::uint64_t current_frame) {
    return reader.read(memory.data(), kMemoryBytes, kLowProtectBytes, kSnapshotObject,
                       kSnapshotType, current_frame);
  }

 private:
  void set_field(std::size_t offset, std::int32_t value) {
    write(memory, kSnapshotObject + offset, value);
  }
};

goalpad::FacePromptTouchSnapshot confirm(Fixture& fixture,
                                         std::uint32_t requested_buttons,
                                         std::uint64_t first_frame) {
  fixture.set_requested_buttons(requested_buttons);
  expect(!fixture.read(first_frame).valid, "the first valid sample must fail closed");
  fixture.set_heartbeat(11);
  return fixture.read(first_frame + 1);
}

}  // namespace

int main() {
  using namespace goalpad::face_prompt_touch_layout;

  const std::array<std::uint32_t, 4> single_buttons = {
      kTriangleButton,
      kCircleButton,
      kCrossButton,
      kSquareButton,
  };
  for (const auto button : single_buttons) {
    Fixture fixture;
    const auto snapshot = confirm(fixture, button, 100);
    expect(snapshot.valid && snapshot.sequence == 2 &&
               snapshot.requested_buttons == button,
           "each ordinary PS2 face-button bit survives a fresh two-sample read");
  }

  Fixture chord;
  const auto chord_mask = kCrossButton | kTriangleButton;
  const auto chord_snapshot = confirm(chord, chord_mask, 200);
  expect(chord_snapshot.valid && chord_snapshot.requested_buttons == chord_mask,
         "Cross plus Triangle survives as one exact requested mask");

  Fixture first_sample;
  expect(!first_sample.read(300).valid, "a stale first-frame publication is not exposed");
  expect(!first_sample.read(301).valid,
         "an unchanged first-sample heartbeat remains unavailable on a later frame");
  first_sample.set_heartbeat(11);
  expect(first_sample.read(302).valid,
         "a later heartbeat makes the unchanged owner and mask current");
  expect(first_sample.read(304).valid, "the bounded heartbeat grace accepts two run frames");
  expect(!first_sample.read(305).valid, "an unchanged heartbeat beyond the grace is stale");
  first_sample.set_heartbeat(12);
  expect(first_sample.read(306).valid, "a new heartbeat restores freshness");

  Fixture same_frame;
  expect(!same_frame.read(400).valid, "the first sample is unavailable");
  same_frame.set_heartbeat(11);
  expect(!same_frame.read(400).valid, "same-frame resampling cannot establish freshness");
  expect(same_frame.read(401).valid,
         "the fresh heartbeat is accepted only after the reader reaches a later frame");

  Fixture changed_owner;
  expect(confirm(changed_owner, kCircleButton, 500).valid,
         "the initial owner becomes current");
  changed_owner.set_sequence(4);
  changed_owner.set_owner(0x2234000056780000ull);
  changed_owner.set_heartbeat(1);
  expect(!changed_owner.read(502).valid, "a changed owner starts a new fail-closed sample");
  changed_owner.set_heartbeat(2);
  expect(changed_owner.read(503).valid,
         "the changed owner requires its own later-frame heartbeat");

  Fixture changed_mask;
  expect(confirm(changed_mask, kSquareButton, 600).valid,
         "the initial mask becomes current");
  changed_mask.set_sequence(4);
  changed_mask.set_requested_buttons(kCrossButton | kTriangleButton);
  changed_mask.set_heartbeat(1);
  expect(!changed_mask.read(602).valid, "a changed mask starts a new fail-closed sample");
  changed_mask.set_heartbeat(2);
  const auto changed_mask_snapshot = changed_mask.read(603);
  expect(changed_mask_snapshot.valid &&
             changed_mask_snapshot.requested_buttons == (kCrossButton | kTriangleButton),
         "the changed mask requires its own later-frame heartbeat");

  Fixture unavailable;
  expect(confirm(unavailable, kTriangleButton, 700).valid,
         "the publication is current before it clears");
  unavailable.clear(4);
  expect(!unavailable.read(702).valid, "a zeroed unavailable publication fails closed");
  unavailable.set_sequence(6);
  unavailable.set_requested_buttons(kTriangleButton);
  unavailable.set_owner(0x1234000056780000ull);
  unavailable.set_heartbeat(1);
  expect(!unavailable.read(703).valid,
         "availability after a clear starts from a new fail-closed sample");
  unavailable.set_heartbeat(2);
  expect(unavailable.read(704).valid,
         "availability after a clear requires a fresh later-frame heartbeat");

  Fixture zero_mask;
  zero_mask.set_requested_buttons(0);
  expect(!zero_mask.read_raw().valid, "a zero requested mask fails closed");

  Fixture non_face_mask;
  non_face_mask.set_requested_buttons(1u << 11);
  expect(!non_face_mask.read_raw().valid, "a non-face requested bit fails closed");
  non_face_mask.set_requested_buttons(kCrossButton | (1u << 16));
  expect(!non_face_mask.read_raw().valid,
         "a face mask contaminated by any non-face bit fails closed");

  Fixture missing_owner;
  missing_owner.set_owner(0);
  expect(!missing_owner.read_raw().valid, "an available mask without an owner fails closed");

  Fixture wrong_type;
  write(wrong_type.memory, kSnapshotObject - 4, std::uint32_t{108});
  expect(!wrong_type.read_raw().valid, "a wrong GOAL object type fails closed");
  expect(!Fixture().read_raw(kMemoryBytes, kSnapshotObject, 108).valid,
         "a wrong expected type fails closed");

  Fixture undersized;
  write(undersized.memory, kSnapshotType + 8, std::uint16_t{0x18});
  expect(!undersized.read_raw().valid, "an undersized basic allocation fails closed");

  Fixture bounds;
  expect(!bounds.read_raw(kSnapshotObject + kRequiredObjectBytes - 1).valid,
         "a truncated object span fails closed");
  expect(!bounds.read_raw(kMemoryBytes, 0).valid, "a missing snapshot fails closed");
  expect(!bounds.read_raw(kMemoryBytes, kSnapshotObject + 2).valid,
         "an unaligned direct basic pointer fails closed");

  Fixture revision;
  revision.set_revision(2);
  expect(!revision.read_raw().valid, "an unknown schema revision fails closed");

  Fixture odd;
  odd.set_sequence(3);
  expect(!odd.read_raw().valid, "an in-progress odd publication fails closed");
  expect(!goalpad::validate_face_prompt_touch_snapshot(
              2, 1, static_cast<std::int32_t>(kCrossButton), 1, 1, 4)
              .valid,
         "a sequence change across the payload read is torn and fails closed");

  expect(goalpad::face_prompt_touch_symbols_available(100, true, 200),
         "both discovered symbols and a nonzero type enable the bridge");
  expect(!goalpad::face_prompt_touch_symbols_available(0, true, 200),
         "a missing snapshot global fails symbol discovery closed");
  expect(!goalpad::face_prompt_touch_symbols_available(100, false, 200),
         "a missing type symbol fails discovery closed");
  expect(!goalpad::face_prompt_touch_symbols_available(100, true, 0),
         "a discovered type symbol with no type value fails closed");

  std::cout << "game face prompt touch state checks passed\n";
  return 0;
}
