#include "GOALPadAOTExportRegistry.hpp"

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>

struct GoalCallProbe {
  std::uint64_t entry_process;
  std::uint64_t entry_symbol_table;
  std::uint64_t entry_offset_base;
  std::uint64_t result;
  std::uint64_t exit_process;
  std::uint64_t exit_symbol_table;
  std::uint64_t exit_offset_base;
  std::uint64_t restored_process;
  std::uint64_t restored_symbol_table;
  std::uint64_t restored_offset_base;
};

static_assert(sizeof(GoalCallProbe) == 80);
static_assert(offsetof(GoalCallProbe, entry_process) == 0);
static_assert(offsetof(GoalCallProbe, entry_symbol_table) == 8);
static_assert(offsetof(GoalCallProbe, entry_offset_base) == 16);
static_assert(offsetof(GoalCallProbe, result) == 24);
static_assert(offsetof(GoalCallProbe, exit_process) == 32);
static_assert(offsetof(GoalCallProbe, exit_symbol_table) == 40);
static_assert(offsetof(GoalCallProbe, exit_offset_base) == 48);
static_assert(offsetof(GoalCallProbe, restored_process) == 56);
static_assert(offsetof(GoalCallProbe, restored_symbol_table) == 64);
static_assert(offsetof(GoalCallProbe, restored_offset_base) == 72);

struct GoalCallProbe1 {
  std::uint64_t entry_process;
  std::uint64_t entry_symbol_table;
  std::uint64_t entry_offset_base;
  std::uint64_t entry_arg0;
  std::uint64_t result;
  std::uint64_t exit_process;
  std::uint64_t exit_symbol_table;
  std::uint64_t exit_offset_base;
  std::uint64_t restored_process;
  std::uint64_t restored_symbol_table;
  std::uint64_t restored_offset_base;
};

static_assert(sizeof(GoalCallProbe1) == 88);
static_assert(offsetof(GoalCallProbe1, entry_process) == 0);
static_assert(offsetof(GoalCallProbe1, entry_symbol_table) == 8);
static_assert(offsetof(GoalCallProbe1, entry_offset_base) == 16);
static_assert(offsetof(GoalCallProbe1, entry_arg0) == 24);
static_assert(offsetof(GoalCallProbe1, result) == 32);
static_assert(offsetof(GoalCallProbe1, exit_process) == 40);
static_assert(offsetof(GoalCallProbe1, exit_symbol_table) == 48);
static_assert(offsetof(GoalCallProbe1, exit_offset_base) == 56);
static_assert(offsetof(GoalCallProbe1, restored_process) == 64);
static_assert(offsetof(GoalCallProbe1, restored_symbol_table) == 72);
static_assert(offsetof(GoalCallProbe1, restored_offset_base) == 80);

struct GoalCallProbe2 {
  std::uint64_t entry_process;
  std::uint64_t entry_symbol_table;
  std::uint64_t entry_offset_base;
  std::uint64_t entry_arg0;
  std::uint64_t entry_arg1;
  std::uint64_t result;
  std::uint64_t exit_process;
  std::uint64_t exit_symbol_table;
  std::uint64_t exit_offset_base;
  std::uint64_t restored_process;
  std::uint64_t restored_symbol_table;
  std::uint64_t restored_offset_base;
};

static_assert(sizeof(GoalCallProbe2) == 96);
static_assert(offsetof(GoalCallProbe2, entry_process) == 0);
static_assert(offsetof(GoalCallProbe2, entry_symbol_table) == 8);
static_assert(offsetof(GoalCallProbe2, entry_offset_base) == 16);
static_assert(offsetof(GoalCallProbe2, entry_arg0) == 24);
static_assert(offsetof(GoalCallProbe2, entry_arg1) == 32);
static_assert(offsetof(GoalCallProbe2, result) == 40);
static_assert(offsetof(GoalCallProbe2, exit_process) == 48);
static_assert(offsetof(GoalCallProbe2, exit_symbol_table) == 56);
static_assert(offsetof(GoalCallProbe2, exit_offset_base) == 64);
static_assert(offsetof(GoalCallProbe2, restored_process) == 72);
static_assert(offsetof(GoalCallProbe2, restored_symbol_table) == 80);
static_assert(offsetof(GoalCallProbe2, restored_offset_base) == 88);

struct GoalCallProbe3 {
  std::uint64_t entry_process;
  std::uint64_t entry_symbol_table;
  std::uint64_t entry_offset_base;
  std::uint64_t entry_arg0;
  std::uint64_t entry_arg1;
  std::uint64_t entry_arg2;
  std::uint64_t result;
  std::uint64_t exit_process;
  std::uint64_t exit_symbol_table;
  std::uint64_t exit_offset_base;
  std::uint64_t restored_process;
  std::uint64_t restored_symbol_table;
  std::uint64_t restored_offset_base;
};

static_assert(sizeof(GoalCallProbe3) == 104);
static_assert(offsetof(GoalCallProbe3, entry_process) == 0);
static_assert(offsetof(GoalCallProbe3, entry_symbol_table) == 8);
static_assert(offsetof(GoalCallProbe3, entry_offset_base) == 16);
static_assert(offsetof(GoalCallProbe3, entry_arg0) == 24);
static_assert(offsetof(GoalCallProbe3, entry_arg1) == 32);
static_assert(offsetof(GoalCallProbe3, entry_arg2) == 40);
static_assert(offsetof(GoalCallProbe3, result) == 48);
static_assert(offsetof(GoalCallProbe3, exit_process) == 56);
static_assert(offsetof(GoalCallProbe3, exit_symbol_table) == 64);
static_assert(offsetof(GoalCallProbe3, exit_offset_base) == 72);
static_assert(offsetof(GoalCallProbe3, restored_process) == 80);
static_assert(offsetof(GoalCallProbe3, restored_symbol_table) == 88);
static_assert(offsetof(GoalCallProbe3, restored_offset_base) == 96);

extern "C" std::uint64_t goalpad_probe_call_aot_with_state(
    std::uint64_t process, std::uint64_t symbol_table,
    std::uint64_t offset_base, goalpad::AOTEntry0 entry, GoalCallProbe* probe);

extern "C" std::uint64_t goalpad_probe_call_aot1_with_state(
    std::uint64_t process, std::uint64_t symbol_table,
    std::uint64_t offset_base, goalpad::AOTEntry1 entry, std::uint64_t arg0,
    GoalCallProbe1* probe);

extern "C" std::uint64_t goalpad_probe_call_aot2_with_state(
    std::uint64_t process, std::uint64_t symbol_table,
    std::uint64_t offset_base, goalpad::AOTEntry2 entry, std::uint64_t arg0,
    std::uint64_t arg1, GoalCallProbe2* probe);

extern "C" std::uint64_t goalpad_probe_call_aot3_with_state(
    std::uint64_t process, std::uint64_t symbol_table,
    std::uint64_t offset_base, goalpad::AOTEntry3 entry, std::uint64_t arg0,
    std::uint64_t arg1, std::uint64_t arg2, GoalCallProbe3* probe);

struct alignas(16) SyntheticGoalArena {
  std::array<std::byte, 0xc0> bytes{};
};

static_assert(alignof(SyntheticGoalArena) >= 16);
static_assert(offsetof(SyntheticGoalArena, bytes) == 0);

constexpr std::byte kSyntheticArenaGuard = static_cast<std::byte>(0xa5);
constexpr std::size_t kFirstOffsetBase = 0x10;
constexpr std::size_t kSecondOffsetBase = 0x70;
constexpr std::uint64_t kLevelGroupPointer = 0x4;
constexpr std::size_t kLoadCommandsOffset = 0x20;
constexpr std::size_t kFirstStoreOffset =
    kFirstOffsetBase + kLevelGroupPointer + kLoadCommandsOffset;
constexpr std::size_t kSecondStoreOffset =
    kSecondOffsetBase + kLevelGroupPointer + kLoadCommandsOffset;

static_assert(kFirstStoreOffset == 0x34);
static_assert(kSecondStoreOffset == 0x94);
static_assert(kSecondStoreOffset + sizeof(std::uint32_t) <= sizeof(SyntheticGoalArena::bytes));

void write_low_word(SyntheticGoalArena& arena, std::size_t offset, std::uint64_t value) {
  const auto low_word = static_cast<std::uint32_t>(value);
  std::memcpy(arena.bytes.data() + offset, &low_word, sizeof(low_word));
}

std::uint32_t read_word(const SyntheticGoalArena& arena, std::size_t offset) {
  std::uint32_t value = 0;
  std::memcpy(&value, arena.bytes.data() + offset, sizeof(value));
  return value;
}

bool has_guard_bytes(const SyntheticGoalArena& arena, std::size_t first, std::size_t last) {
  return std::all_of(arena.bytes.begin() + first, arena.bytes.begin() + last,
                     [](std::byte value) { return value == kSyntheticArenaGuard; });
}

bool has_expected_probe(const GoalCallProbe1& probe,
                        std::uint64_t process,
                        std::uint64_t symbol_table,
                        std::uint64_t offset_base,
                        std::uint64_t arg0,
                        std::uint64_t result) {
  return probe.entry_process == process && probe.entry_symbol_table == symbol_table &&
         probe.entry_offset_base == offset_base && probe.entry_arg0 == arg0 &&
         probe.result == result && probe.exit_process == process &&
         probe.exit_symbol_table == symbol_table && probe.exit_offset_base == offset_base &&
         probe.restored_process == 0x14 && probe.restored_symbol_table == 0x15 &&
         probe.restored_offset_base == 0x16;
}

bool has_expected_probe(const GoalCallProbe2& probe,
                        std::uint64_t process,
                        std::uint64_t symbol_table,
                        std::uint64_t offset_base,
                        std::uint64_t arg0,
                        std::uint64_t arg1,
                        std::uint64_t result) {
  return probe.entry_process == process && probe.entry_symbol_table == symbol_table &&
         probe.entry_offset_base == offset_base && probe.entry_arg0 == arg0 &&
         probe.entry_arg1 == arg1 && probe.result == result &&
         probe.exit_process == process && probe.exit_symbol_table == symbol_table &&
         probe.exit_offset_base == offset_base && probe.restored_process == 0x14 &&
         probe.restored_symbol_table == 0x15 && probe.restored_offset_base == 0x16;
}

bool has_expected_probe(const GoalCallProbe3& probe,
                        std::uint64_t process,
                        std::uint64_t symbol_table,
                        std::uint64_t offset_base,
                        std::uint64_t arg0,
                        std::uint64_t arg1,
                        std::uint64_t arg2,
                        std::uint64_t result) {
  return probe.entry_process == process && probe.entry_symbol_table == symbol_table &&
         probe.entry_offset_base == offset_base && probe.entry_arg0 == arg0 &&
         probe.entry_arg1 == arg1 && probe.entry_arg2 == arg2 &&
         probe.result == result && probe.exit_process == process &&
         probe.exit_symbol_table == symbol_table && probe.exit_offset_base == offset_base &&
         probe.restored_process == 0x14 && probe.restored_symbol_table == 0x15 &&
         probe.restored_offset_base == 0x16;
}

bool has_expected_jak1_level_group_load_commands_set_arm64_code(goalpad::AOTEntry2 entry) {
#if defined(__arm64__)
  constexpr std::array<unsigned char, 20> expected = {
      0x10, 0x00, 0x16, 0x8b, 0x10, 0x82, 0x00, 0x91, 0x01, 0x02,
      0x00, 0xb9, 0xe0, 0x03, 0x01, 0xaa, 0xc0, 0x03, 0x5f, 0xd6,
  };
  std::array<unsigned char, expected.size()> actual{};
  std::memcpy(actual.data(), reinterpret_cast<const void*>(entry), actual.size());
  return actual == expected;
#else
  return false;
#endif
}

bool has_expected_jak1_want_vis_arm64_code(goalpad::AOTEntry2 entry) {
#if defined(__arm64__)
  constexpr std::array<unsigned char, 20> expected = {
      0x10, 0x00, 0x16, 0x8b, 0x10, 0x82, 0x00, 0x91, 0x01, 0x02,
      0x00, 0xb9, 0x00, 0x00, 0x00, 0xca, 0xc0, 0x03, 0x5f, 0xd6,
  };
  std::array<unsigned char, expected.size()> actual{};
  std::memcpy(actual.data(), reinterpret_cast<const void*>(entry), actual.size());
  return actual == expected;
#else
  return false;
#endif
}

bool has_expected_jak1_load_state_reset_arm64_code(goalpad::AOTEntry1 entry) {
#if defined(__arm64__)
  constexpr std::array<std::uint32_t, 58> expected = {
      0xaa1503e1, 0xb836e801, 0xaa1503e1, 0x8b160010, 0x91001210, 0xb9000201,
      0xaa1503e1, 0x8b160010, 0x91002210, 0xb9000201, 0xaa1503e1, 0x8b160010,
      0x91003210, 0xb9000201, 0xaa1503e1, 0x8b160010, 0x91004210, 0xb9000201,
      0xaa1503e1, 0x8b160010, 0x91005210, 0xb9000201, 0xaa1503e1, 0x8b160010,
      0x91006210, 0xb9000201, 0xaa1503e1, 0x8b160010, 0x91007210, 0xb9000201,
      0xaa1503e1, 0xd1002821, 0x8b160010, 0x91009210, 0xb9000201, 0xca010021,
      0x14000011, 0xaa1503e2, 0xaa0103e3, 0xd37ef463, 0xd2800504, 0x8b000084,
      0x8b040063, 0xb836e862, 0xca020042, 0xaa0103e3, 0xd37ef463, 0xd2808504,
      0x8b000084, 0x8b040063, 0xb836e862, 0xd2800022, 0x8b020021, 0xd2802002,
      0xeb02003f, 0x54fffdcb, 0xaa1503e1, 0xd65f03c0,
  };
  static_assert(expected.size() * sizeof(std::uint32_t) == 232);
  std::array<std::uint32_t, expected.size()> actual{};
  std::memcpy(actual.data(), reinterpret_cast<const void*>(entry),
              actual.size() * sizeof(std::uint32_t));
  return actual == expected;
#else
  return false;
#endif
}

bool verifies_level_group_load_commands_set(goalpad::AOTEntry2 entry,
                                            std::uint64_t process,
                                            std::uint64_t symbol_table) {
  constexpr std::uint64_t first_value = 0x0123456789abcdefULL;
  constexpr std::uint64_t second_value = 0xfedcba9876543210ULL;
  SyntheticGoalArena arena;
  arena.bytes.fill(kSyntheticArenaGuard);
  SyntheticGoalArena expected = arena;
  GoalCallProbe2 first_probe{};
  GoalCallProbe2 second_probe{};

  const auto first_offset_base = static_cast<std::uint64_t>(
      reinterpret_cast<std::uintptr_t>(arena.bytes.data() + kFirstOffsetBase));
  const auto second_offset_base = static_cast<std::uint64_t>(
      reinterpret_cast<std::uintptr_t>(arena.bytes.data() + kSecondOffsetBase));
  if ((first_offset_base & 0xf) != 0 || (second_offset_base & 0xf) != 0) {
    return false;
  }

  write_low_word(expected, kFirstStoreOffset, first_value);
  const auto first_result = goalpad_probe_call_aot2_with_state(
      process, symbol_table, first_offset_base, entry, kLevelGroupPointer, first_value, &first_probe);
  if (first_result != first_value ||
      !has_expected_probe(first_probe, process, symbol_table, first_offset_base,
                          kLevelGroupPointer, first_value, first_result) ||
      read_word(arena, kFirstStoreOffset) != static_cast<std::uint32_t>(first_value) ||
      !has_guard_bytes(arena, 0, kFirstStoreOffset) ||
      !has_guard_bytes(arena, kFirstStoreOffset + sizeof(std::uint32_t), arena.bytes.size()) ||
      arena.bytes != expected.bytes) {
    return false;
  }

  write_low_word(expected, kSecondStoreOffset, second_value);
  const auto second_result = goalpad_probe_call_aot2_with_state(
      process, symbol_table, second_offset_base, entry, kLevelGroupPointer, second_value,
      &second_probe);
  return second_result == second_value &&
         has_expected_probe(second_probe, process, symbol_table, second_offset_base,
                            kLevelGroupPointer, second_value, second_result) &&
         read_word(arena, kFirstStoreOffset) == static_cast<std::uint32_t>(first_value) &&
         read_word(arena, kSecondStoreOffset) == static_cast<std::uint32_t>(second_value) &&
         has_guard_bytes(arena, 0, kFirstStoreOffset) &&
         has_guard_bytes(arena, kFirstStoreOffset + sizeof(std::uint32_t), kSecondStoreOffset) &&
         has_guard_bytes(arena, kSecondStoreOffset + sizeof(std::uint32_t), arena.bytes.size()) &&
         arena.bytes == expected.bytes;
}

bool verifies_want_vis(goalpad::AOTEntry2 entry,
                       std::uint64_t process,
                       std::uint64_t symbol_table) {
  constexpr std::uint64_t first_value = 0xaabbccdd81234567ULL;
  constexpr std::uint64_t second_value = 0x11223344f2345678ULL;
  constexpr std::uint64_t load_state_pointer = 0x4;
  constexpr std::size_t emitted_store_offset = 0x20;
  constexpr std::size_t raw_vis_nick_offset = 0x24;
  constexpr std::size_t first_store_offset =
      kFirstOffsetBase + load_state_pointer + emitted_store_offset;
  constexpr std::size_t second_store_offset =
      kSecondOffsetBase + load_state_pointer + emitted_store_offset;
  static_assert(load_state_pointer + emitted_store_offset == raw_vis_nick_offset);
  static_assert(first_store_offset == 0x34);
  static_assert(second_store_offset == 0x94);
  static_assert(second_store_offset + sizeof(std::uint32_t) <= sizeof(SyntheticGoalArena::bytes));

  SyntheticGoalArena arena;
  arena.bytes.fill(kSyntheticArenaGuard);
  SyntheticGoalArena expected = arena;
  GoalCallProbe2 first_probe{};
  GoalCallProbe2 second_probe{};

  const auto first_offset_base = static_cast<std::uint64_t>(
      reinterpret_cast<std::uintptr_t>(arena.bytes.data() + kFirstOffsetBase));
  const auto second_offset_base = static_cast<std::uint64_t>(
      reinterpret_cast<std::uintptr_t>(arena.bytes.data() + kSecondOffsetBase));
  if ((first_offset_base & 0xf) != 0 || (second_offset_base & 0xf) != 0) {
    return false;
  }

  write_low_word(expected, first_store_offset, first_value);
  const auto first_result = goalpad_probe_call_aot2_with_state(
      process, symbol_table, first_offset_base, entry, load_state_pointer, first_value, &first_probe);
  if (first_result != 0 ||
      !has_expected_probe(first_probe, process, symbol_table, first_offset_base,
                          load_state_pointer, first_value, first_result) ||
      read_word(arena, first_store_offset) != static_cast<std::uint32_t>(first_value) ||
      !has_guard_bytes(arena, 0, first_store_offset) ||
      !has_guard_bytes(arena, first_store_offset + sizeof(std::uint32_t), arena.bytes.size()) ||
      arena.bytes != expected.bytes) {
    return false;
  }

  write_low_word(expected, second_store_offset, second_value);
  const auto second_result = goalpad_probe_call_aot2_with_state(
      process, symbol_table, second_offset_base, entry, load_state_pointer, second_value,
      &second_probe);
  return second_result == 0 &&
         has_expected_probe(second_probe, process, symbol_table, second_offset_base,
                            load_state_pointer, second_value, second_result) &&
         read_word(arena, first_store_offset) == static_cast<std::uint32_t>(first_value) &&
         read_word(arena, second_store_offset) == static_cast<std::uint32_t>(second_value) &&
         has_guard_bytes(arena, 0, first_store_offset) &&
         has_guard_bytes(arena, first_store_offset + sizeof(std::uint32_t), second_store_offset) &&
         has_guard_bytes(arena, second_store_offset + sizeof(std::uint32_t), arena.bytes.size()) &&
         arena.bytes == expected.bytes;
}

bool verifies_want_levels(goalpad::AOTEntry3 entry, std::uint64_t process) {
  struct WantLevelsSlot {
    std::uint32_t name;
    std::uint32_t display;
    std::uint32_t force_vis;
    std::uint32_t force_inside;
  };
  struct WantLevelsCase {
    std::array<WantLevelsSlot, 2> initial;
    std::uint32_t argument0;
    std::uint32_t argument1;
    std::array<WantLevelsSlot, 2> expected;
  };

  constexpr std::uint64_t kFalse = 0x14fd24;
  constexpr std::uint64_t kThis = 4;
  constexpr std::size_t kSlotSize = 0x10;
  constexpr std::uint32_t kLevelA = 0x81234567;
  constexpr std::uint32_t kLevelB = 0xf2345678;
  constexpr std::uint32_t kLevelC = 0x89abcdef;
  constexpr std::uint32_t kLevelD = 0xcafebabe;
  constexpr std::uint32_t kFirstDisplay = 0x91a2b3c4;
  constexpr std::uint32_t kFirstForceVis = 0xa1b2c3d4;
  constexpr std::uint32_t kFirstForceInside = 0xb1c2d3e4;
  constexpr std::uint32_t kSecondDisplay = 0xc1d2e3f4;
  constexpr std::uint32_t kSecondForceVis = 0xd1e2f304;
  constexpr std::uint32_t kSecondForceInside = 0xe1f20314;
  constexpr WantLevelsSlot kSlotA{
      kLevelA, kFirstDisplay, kFirstForceVis, kFirstForceInside};
  constexpr WantLevelsSlot kSlotB{
      kLevelB, kSecondDisplay, kSecondForceVis, kSecondForceInside};
  constexpr WantLevelsSlot kSlotC{
      kLevelC, kFirstDisplay, kFirstForceVis, kFirstForceInside};
  constexpr WantLevelsSlot kSlotD{
      kLevelD, kSecondDisplay, kSecondForceVis, kSecondForceInside};
  constexpr WantLevelsSlot kSlotAReset{kLevelA, kFalse, kFalse, kFalse};
  constexpr WantLevelsSlot kSlotBReset{kLevelB, kFalse, kFalse, kFalse};
  constexpr std::array cases{
      WantLevelsCase{{kSlotA, kSlotB}, kLevelA, kLevelB, {kSlotA, kSlotB}},
      WantLevelsCase{{kSlotC, kSlotD}, kLevelA, kLevelB, {kSlotAReset, kSlotBReset}},
      WantLevelsCase{{kSlotA, kSlotC}, kLevelA, kLevelA, {kSlotA, kSlotAReset}},
      WantLevelsCase{
          {kSlotC, kSlotD},
          kFalse,
          kLevelB,
          {kSlotBReset,
           WantLevelsSlot{kFalse, kSecondDisplay, kSecondForceVis, kSecondForceInside}}},
      WantLevelsCase{
          {kSlotC, kSlotD},
          kLevelA,
          kFalse,
          {kSlotAReset,
           WantLevelsSlot{kFalse, kSecondDisplay, kSecondForceVis, kSecondForceInside}}},
      WantLevelsCase{
          {kSlotC, kSlotD},
          kFalse,
          kFalse,
          {WantLevelsSlot{kFalse, kFirstDisplay, kFirstForceVis, kFirstForceInside},
           WantLevelsSlot{kFalse, kSecondDisplay, kSecondForceVis, kSecondForceInside}}},
  };
  constexpr std::size_t kFirstWriteOffset = kFirstOffsetBase + kThis;
  constexpr std::size_t kEndWriteOffset = kFirstWriteOffset + 2 * kSlotSize;
  static_assert(kEndWriteOffset <= sizeof(SyntheticGoalArena::bytes));

  const auto write_slot = [](SyntheticGoalArena& arena,
                             std::size_t index,
                             const WantLevelsSlot& slot) {
    const auto offset = kFirstOffsetBase + kThis + index * kSlotSize;
    write_low_word(arena, offset, slot.name);
    write_low_word(arena, offset + 4, slot.display);
    write_low_word(arena, offset + 8, slot.force_vis);
    write_low_word(arena, offset + 12, slot.force_inside);
  };

  for (const auto& test_case : cases) {
    SyntheticGoalArena arena;
    arena.bytes.fill(kSyntheticArenaGuard);
    SyntheticGoalArena expected = arena;
    for (std::size_t index = 0; index < test_case.initial.size(); ++index) {
      write_slot(arena, index, test_case.initial[index]);
      write_slot(expected, index, test_case.expected[index]);
    }

    const auto offset_base = static_cast<std::uint64_t>(
        reinterpret_cast<std::uintptr_t>(arena.bytes.data() + kFirstOffsetBase));
    if ((offset_base & 0xf) != 0) {
      return false;
    }
    GoalCallProbe3 probe{};
    const auto result = goalpad_probe_call_aot3_with_state(
        process, kFalse, offset_base, entry, kThis, test_case.argument0,
        test_case.argument1, &probe);
    if (result != 0 ||
        !has_expected_probe(probe, process, kFalse, offset_base, kThis,
                            test_case.argument0, test_case.argument1, result) ||
        !has_guard_bytes(arena, 0, kFirstWriteOffset) ||
        !has_guard_bytes(arena, kEndWriteOffset, arena.bytes.size()) ||
        arena.bytes != expected.bytes) {
      return false;
    }
  }
  return true;
}

struct alignas(16) GuardedLoadStateArena {
  std::array<std::byte, 16> leading_guard{};
  std::array<std::byte, 0x112c> storage{};
  std::array<std::byte, 16> trailing_guard{};
};

static_assert(alignof(GuardedLoadStateArena) >= 16);
static_assert(offsetof(GuardedLoadStateArena, storage) == 16);

void write_load_state_word(GuardedLoadStateArena& arena,
                           std::size_t offset,
                           std::uint32_t value) {
  std::memcpy(arena.storage.data() + offset, &value, sizeof(value));
}

std::uint32_t read_load_state_word(const GuardedLoadStateArena& arena, std::size_t offset) {
  std::uint32_t value = 0;
  std::memcpy(&value, arena.storage.data() + offset, sizeof(value));
  return value;
}

bool verifies_load_state_reset(goalpad::AOTEntry1 entry, std::uint64_t process) {
  constexpr std::size_t kThis = 4;
  constexpr std::size_t kSecondArenaBaseOffset = 0x900;
  constexpr std::size_t kLoadStateSize = 0x82c;
  constexpr std::size_t kWantOffset = 0x4;
  constexpr std::size_t kWantWordCount = 8;
  constexpr std::size_t kVisNickOffset = 0x24;
  constexpr std::size_t kCommandListOffset = 0x28;
  constexpr std::size_t kObjectNameOffset = 0x2c;
  constexpr std::size_t kObjectStatusOffset = 0x42c;
  constexpr std::size_t kObjectCount = 256;
  constexpr std::uint64_t kFalse = 0x14fd24;
  constexpr std::uint32_t kFalseWord = static_cast<std::uint32_t>(kFalse);
  constexpr std::uint32_t kEmpty = 0x14fd1a;

  static_assert(kThis == kWantOffset);
  static_assert(kWantOffset + kWantWordCount * sizeof(std::uint32_t) == kVisNickOffset);
  static_assert(kSecondArenaBaseOffset >= kLoadStateSize);
  static_assert(kSecondArenaBaseOffset + kLoadStateSize == 0x112c);

  GuardedLoadStateArena actual;
  std::size_t seed_index = 0;
  const auto seed_range = [&seed_index](auto& range) {
    for (auto& byte : range) {
      byte = static_cast<std::byte>(1 + (seed_index * 37) % 255);
      ++seed_index;
    }
  };
  seed_range(actual.leading_guard);
  seed_range(actual.storage);
  seed_range(actual.trailing_guard);
  GuardedLoadStateArena expected = actual;

  const auto reset_expected = [&expected](std::size_t base_offset) {
    for (std::size_t index = 0; index < kWantWordCount; ++index) {
      write_load_state_word(expected, base_offset + kWantOffset + index * sizeof(std::uint32_t),
                            kFalseWord);
    }
    write_load_state_word(expected, base_offset + kCommandListOffset, kEmpty);
    for (std::size_t index = 0; index < kObjectCount; ++index) {
      write_load_state_word(expected,
                            base_offset + kObjectNameOffset + index * sizeof(std::uint32_t),
                            kFalseWord);
      write_load_state_word(expected,
                            base_offset + kObjectStatusOffset + index * sizeof(std::uint32_t), 0);
    }
  };
  reset_expected(0);
  reset_expected(kSecondArenaBaseOffset);

  const auto first_offset_base = static_cast<std::uint64_t>(
      reinterpret_cast<std::uintptr_t>(actual.storage.data()));
  if ((first_offset_base & 0xf) != 0 ||
      ((first_offset_base + kSecondArenaBaseOffset) & 0xf) != 0) {
    return false;
  }

  GoalCallProbe1 first_probe{};
  GoalCallProbe1 second_probe{};
  const auto invoke = [&](std::size_t base_offset, GoalCallProbe1& probe) {
    const auto offset_base = first_offset_base + base_offset;
    const auto result = goalpad_probe_call_aot1_with_state(
        process, kFalse, offset_base, entry, kThis, &probe);
    return result == kThis &&
           has_expected_probe(probe, process, kFalse, offset_base, kThis, result);
  };
  if (!invoke(0, first_probe) || !invoke(kSecondArenaBaseOffset, second_probe)) {
    return false;
  }

  const auto has_expected_reset_fields = [&actual, &expected](std::size_t base_offset) {
    if (read_load_state_word(actual, base_offset) != read_load_state_word(expected, base_offset)) {
      return false;
    }
    for (std::size_t index = 0; index < kWantWordCount; ++index) {
      if (read_load_state_word(actual,
                               base_offset + kWantOffset + index * sizeof(std::uint32_t)) !=
          kFalseWord) {
        return false;
      }
    }
    if (read_load_state_word(actual, base_offset + kVisNickOffset) !=
            read_load_state_word(expected, base_offset + kVisNickOffset) ||
        read_load_state_word(actual, base_offset + kCommandListOffset) != kEmpty) {
      return false;
    }
    for (std::size_t index = 0; index < kObjectCount; ++index) {
      if (read_load_state_word(actual,
                               base_offset + kObjectNameOffset + index * sizeof(std::uint32_t)) !=
              kFalseWord ||
          read_load_state_word(actual,
                               base_offset + kObjectStatusOffset + index * sizeof(std::uint32_t)) !=
              0) {
        return false;
      }
    }
    return true;
  };

  const auto gap_matches = std::equal(
      actual.storage.begin() + kLoadStateSize,
      actual.storage.begin() + kSecondArenaBaseOffset,
      expected.storage.begin() + kLoadStateSize);
  return has_expected_reset_fields(0) &&
         has_expected_reset_fields(kSecondArenaBaseOffset) && gap_matches &&
         actual.leading_guard == expected.leading_guard && actual.storage == expected.storage &&
         actual.trailing_guard == expected.trailing_guard;
}

int main() {
  const auto* false_func = goalpad::find_aot_export0("false-func");
  const auto* true_func = goalpad::find_aot_export0("true-func");
  const auto* identity = goalpad::find_aot_export1("identity");
  const auto* lognot = goalpad::find_aot_export1("lognot");
  const auto* load_state_reset = goalpad::find_aot_export1("reset!");
  const auto* level_group_load_commands_set =
      goalpad::find_aot_export2("level-group-load-commands-set!");
  const auto* want_vis = goalpad::find_aot_export2("want-vis");
  const auto* want_levels = goalpad::find_aot_export3("want-levels");
  if (!false_func || false_func->goal_name != "false-func" ||
      !false_func->entry || !true_func || true_func->goal_name != "true-func" ||
      !true_func->entry || goalpad::find_aot_export0("identity") ||
      goalpad::find_aot_export0("lognot") ||
      goalpad::find_aot_export0("reset!") ||
      goalpad::find_aot_export0("level-group-load-commands-set!") ||
      goalpad::find_aot_export0("") || !identity ||
      identity->goal_name != "identity" || !identity->entry ||
      !lognot || lognot->goal_name != "lognot" || !lognot->entry ||
      !load_state_reset || load_state_reset->goal_name != "reset!" || !load_state_reset->entry ||
      goalpad::find_aot_export1("false-func") ||
      goalpad::find_aot_export1("true-func") ||
      goalpad::find_aot_export1("glst-node-name") ||
      goalpad::find_aot_export1("level-group-load-commands-set!") ||
      goalpad::find_aot_export1("want-vis") ||
      goalpad::find_aot_export1("want-levels") ||
      goalpad::find_aot_export1("missing") ||
      goalpad::find_aot_export1("") || !level_group_load_commands_set ||
      level_group_load_commands_set->goal_name != "level-group-load-commands-set!" ||
      !level_group_load_commands_set->entry || !want_vis || want_vis->goal_name != "want-vis" ||
      !want_vis->entry ||
      goalpad::find_aot_export2("false-func") || goalpad::find_aot_export2("true-func") ||
      goalpad::find_aot_export2("identity") || goalpad::find_aot_export2("lognot") ||
      goalpad::find_aot_export2("reset!") ||
      goalpad::find_aot_export0("want-vis") ||
      goalpad::find_aot_export2("want-levels") ||
      goalpad::find_aot_export2("") || !want_levels ||
      want_levels->goal_name != "want-levels" || !want_levels->entry ||
      goalpad::find_aot_export0("want-levels") ||
      goalpad::find_aot_export3("false-func") ||
      goalpad::find_aot_export3("true-func") ||
      goalpad::find_aot_export3("identity") ||
      goalpad::find_aot_export3("lognot") ||
      goalpad::find_aot_export3("reset!") ||
      goalpad::find_aot_export3("level-group-load-commands-set!") ||
      goalpad::find_aot_export3("want-vis") ||
      goalpad::find_aot_export3("")) {
    return 1;
  }

  constexpr std::uint64_t process = 0x1001;
  constexpr std::uint64_t symbol_table = 0x2002;
  constexpr std::uint64_t offset_base = 0x3003;
  constexpr std::uint64_t true_symbol_offset = 0x8;
  constexpr std::uint64_t identity_arg0 = 0x4a5b6c7d8e9fa0b1;
  constexpr std::uint64_t lognot_arg0 = 0x0123456789abcdefULL;
  constexpr std::uint64_t lognot_expected_result = 0xfedcba9876543210ULL;
  GoalCallProbe false_func_probe{};
  GoalCallProbe true_func_probe{};
  GoalCallProbe1 identity_probe{};
  GoalCallProbe1 lognot_probe{};
  const auto false_func_result = goalpad_probe_call_aot_with_state(
      process, symbol_table, offset_base, false_func->entry, &false_func_probe);
  const auto true_func_result = goalpad_probe_call_aot_with_state(
      process, symbol_table, offset_base, true_func->entry, &true_func_probe);
  const auto identity_result = goalpad_probe_call_aot1_with_state(
      process, symbol_table, offset_base, identity->entry, identity_arg0, &identity_probe);
  const auto lognot_result = goalpad_probe_call_aot1_with_state(
      process, symbol_table, offset_base, lognot->entry, lognot_arg0, &lognot_probe);

  return false_func_result == symbol_table &&
                 false_func_probe.entry_process == process &&
                 false_func_probe.entry_symbol_table == symbol_table &&
                 false_func_probe.entry_offset_base == offset_base &&
                 false_func_probe.result == false_func_result &&
                 false_func_probe.exit_process == process &&
                 false_func_probe.exit_symbol_table == symbol_table &&
                 false_func_probe.exit_offset_base == offset_base &&
                 false_func_probe.restored_process == 0x14 &&
                 false_func_probe.restored_symbol_table == 0x15 &&
                 false_func_probe.restored_offset_base == 0x16 &&
                 true_func_result == symbol_table + true_symbol_offset &&
                 true_func_probe.entry_process == process &&
                 true_func_probe.entry_symbol_table == symbol_table &&
                 true_func_probe.entry_offset_base == offset_base &&
                 true_func_probe.result == true_func_result &&
                 true_func_probe.exit_process == process &&
                 true_func_probe.exit_symbol_table == symbol_table &&
                 true_func_probe.exit_offset_base == offset_base &&
                 true_func_probe.restored_process == 0x14 &&
                 true_func_probe.restored_symbol_table == 0x15 &&
                 true_func_probe.restored_offset_base == 0x16 &&
                 identity_result == identity_arg0 &&
                 identity_probe.entry_process == process &&
                 identity_probe.entry_symbol_table == symbol_table &&
                 identity_probe.entry_offset_base == offset_base &&
                 identity_probe.entry_arg0 == identity_arg0 &&
                 identity_probe.result == identity_result &&
                 identity_probe.exit_process == process &&
                 identity_probe.exit_symbol_table == symbol_table &&
                 identity_probe.exit_offset_base == offset_base &&
                 identity_probe.restored_process == 0x14 &&
                 identity_probe.restored_symbol_table == 0x15 &&
                 identity_probe.restored_offset_base == 0x16 &&
                 lognot_result == lognot_expected_result &&
                 lognot_probe.entry_process == process &&
                 lognot_probe.entry_symbol_table == symbol_table &&
                 lognot_probe.entry_offset_base == offset_base &&
                 lognot_probe.entry_arg0 == lognot_arg0 &&
                 lognot_probe.result == lognot_result &&
                 lognot_probe.exit_process == process &&
                 lognot_probe.exit_symbol_table == symbol_table &&
                 lognot_probe.exit_offset_base == offset_base &&
                 lognot_probe.restored_process == 0x14 &&
                 lognot_probe.restored_symbol_table == 0x15 &&
                 lognot_probe.restored_offset_base == 0x16 &&
                 has_expected_jak1_load_state_reset_arm64_code(load_state_reset->entry) &&
                 verifies_load_state_reset(load_state_reset->entry, process) &&
                 has_expected_jak1_level_group_load_commands_set_arm64_code(
                     level_group_load_commands_set->entry) &&
                 verifies_level_group_load_commands_set(
                     level_group_load_commands_set->entry, process, symbol_table) &&
                 has_expected_jak1_want_vis_arm64_code(want_vis->entry) &&
                 verifies_want_vis(want_vis->entry, process, symbol_table) &&
                 verifies_want_levels(want_levels->entry, process)
             ? 0
             : 1;
}
