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
constexpr std::uint32_t kSnapshotObject = 324;
constexpr std::uint16_t kSnapshotAllocatedBytes = 0x1c;

static_assert(goalpad::cutscene_skip_touch_layout::kRequiredObjectBytes == 0x18);
static_assert(kSnapshotAllocatedBytes ==
              goalpad::camera_correction_trace::jak1_layout::kBasicObjectTypeTagBytes +
                  goalpad::cutscene_skip_touch_layout::kRequiredObjectBytes);

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
  goalpad::CutsceneSkipTouchReader reader;

  Fixture() {
    write(memory, kSnapshotObject - 4, kSnapshotType);
    write(memory, kSnapshotType + 8, kSnapshotAllocatedBytes);
    set_revision(1);
    set_sequence(2);
    set_state(0);
    set_owner(0);
    set_heartbeat(0);
  }

  void set_revision(std::int32_t value) {
    set_field(goalpad::cutscene_skip_touch_layout::kRevisionOffset, value);
  }

  void set_sequence(std::int32_t value) {
    set_field(goalpad::cutscene_skip_touch_layout::kSequenceOffset, value);
  }

  void set_state(std::int32_t value) {
    set_field(goalpad::cutscene_skip_touch_layout::kStateOffset, value);
  }

  void set_owner(std::uint64_t value) {
    write(memory, kSnapshotObject + goalpad::cutscene_skip_touch_layout::kOwnerOffset, value);
  }

  void set_heartbeat(std::int32_t value) {
    set_field(goalpad::cutscene_skip_touch_layout::kHeartbeatOffset, value);
  }

  goalpad::CutsceneSkipTouchRawSnapshot read_raw(
      std::size_t memory_bytes = kMemoryBytes,
      std::uint32_t object = kSnapshotObject,
      std::uint32_t expected_type = kSnapshotType) const {
    return goalpad::read_cutscene_skip_touch_raw_snapshot(
        memory.data(), memory_bytes, kLowProtectBytes, object, expected_type);
  }

  goalpad::CutsceneSkipTouchSnapshot read(std::uint64_t current_frame) {
    return reader.read(memory.data(), kMemoryBytes, kLowProtectBytes, kSnapshotObject,
                       kSnapshotType, current_frame);
  }

 private:
  void set_field(std::size_t offset, std::int32_t value) {
    write(memory, kSnapshotObject + offset, value);
  }
};

}  // namespace

int main() {
  using goalpad::CutsceneSkipTouchState;

  Fixture unavailable;
  const auto unavailable_snapshot = unavailable.read(10);
  expect(unavailable_snapshot.valid && unavailable_snapshot.sequence == 2 &&
             unavailable_snapshot.state == CutsceneSkipTouchState::Unavailable,
         "a checked unavailable publication remains valid and inert");

  Fixture available;
  available.set_sequence(4);
  available.set_state(1);
  available.set_owner(0x1234000056780000ull);
  available.set_heartbeat(9);
  const auto first = available.read(100);
  expect(first.valid && first.sequence == 4 &&
             first.state == CutsceneSkipTouchState::TriangleQueryAvailable,
         "a current owner publication exposes only Triangle-query availability");
  expect(available.read(102).valid, "the bounded heartbeat grace accepts two run frames");
  expect(!available.read(103).valid, "an unchanged heartbeat beyond the grace is stale");
  available.set_heartbeat(10);
  expect(available.read(104).valid, "a new GOAL heartbeat restores freshness");
  available.set_sequence(6);
  available.set_owner(0x2234000056780000ull);
  available.set_heartbeat(1);
  expect(available.read(200).valid && available.read(200).sequence == 6,
         "a new even owner generation starts fresh without exposing the handle");

  Fixture wrong_type;
  write(wrong_type.memory, kSnapshotObject - 4, std::uint32_t{108});
  expect(!wrong_type.read_raw().valid, "a wrong GOAL object type fails closed");
  expect(!Fixture().read_raw(kMemoryBytes, kSnapshotObject, 108).valid,
         "a wrong expected type fails closed");

  Fixture undersized;
  write(undersized.memory, kSnapshotType + 8, std::uint16_t{0x18});
  expect(!undersized.read_raw().valid, "an undersized basic allocation fails closed");

  Fixture bounds;
  expect(!bounds.read_raw(kSnapshotObject +
                          goalpad::cutscene_skip_touch_layout::kRequiredObjectBytes - 1)
              .valid,
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
  expect(!goalpad::validate_cutscene_skip_touch_snapshot(
              2, 1, 0, 0, 0, 4)
              .valid,
         "a sequence change across the payload read is torn and fails closed");

  Fixture unknown;
  unknown.set_state(-1);
  expect(!unknown.read_raw().valid, "a negative state fails closed");
  unknown.set_state(2);
  expect(!unknown.read_raw().valid, "an unknown positive state fails closed");

  Fixture missing_owner;
  missing_owner.set_state(1);
  missing_owner.set_heartbeat(1);
  expect(!missing_owner.read_raw().valid, "available without an owner fails closed");

  Fixture dirty_unavailable_owner;
  dirty_unavailable_owner.set_owner(1);
  expect(!dirty_unavailable_owner.read_raw().valid,
         "unavailable rejects a retained owner");

  Fixture dirty_unavailable_heartbeat;
  dirty_unavailable_heartbeat.set_heartbeat(1);
  expect(!dirty_unavailable_heartbeat.read_raw().valid,
         "unavailable rejects a retained heartbeat");

  std::cout << "game cutscene skip touch state checks passed\n";
  return 0;
}
