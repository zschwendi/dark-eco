#include "GOALPadRuntimeCore.hpp"

#include "GOALPadAOTExportRegistry.hpp"

#include "common/goal_constants.h"
#include "common/symbols.h"
#include "game/kernel/common/kmalloc.h"
#include "game/kernel/jak1/data_arena.h"
#include "game/kernel/jak1/data_arena_arm64_invoker.h"
#include "game/kernel/jak1/kscheme.h"

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <memory>
#include <type_traits>
#include <vector>

namespace {

struct GoalCallProbe {
  std::uint64_t entry_process = 0;
  std::uint64_t entry_symbol_table = 0;
  std::uint64_t entry_offset_base = 0;
  std::uint64_t result = 0;
  std::uint64_t exit_process = 0;
  std::uint64_t exit_symbol_table = 0;
  std::uint64_t exit_offset_base = 0;
  std::uint64_t restored_process = 0;
  std::uint64_t restored_symbol_table = 0;
  std::uint64_t restored_offset_base = 0;
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
  std::uint64_t entry_process = 0;
  std::uint64_t entry_symbol_table = 0;
  std::uint64_t entry_offset_base = 0;
  std::uint64_t entry_arg0 = 0;
  std::uint64_t result = 0;
  std::uint64_t exit_process = 0;
  std::uint64_t exit_symbol_table = 0;
  std::uint64_t exit_offset_base = 0;
  std::uint64_t restored_process = 0;
  std::uint64_t restored_symbol_table = 0;
  std::uint64_t restored_offset_base = 0;
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
  std::uint64_t entry_process = 0;
  std::uint64_t entry_symbol_table = 0;
  std::uint64_t entry_offset_base = 0;
  std::uint64_t entry_arg0 = 0;
  std::uint64_t entry_arg1 = 0;
  std::uint64_t result = 0;
  std::uint64_t exit_process = 0;
  std::uint64_t exit_symbol_table = 0;
  std::uint64_t exit_offset_base = 0;
  std::uint64_t restored_process = 0;
  std::uint64_t restored_symbol_table = 0;
  std::uint64_t restored_offset_base = 0;
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
  std::uint64_t entry_process = 0;
  std::uint64_t entry_symbol_table = 0;
  std::uint64_t entry_offset_base = 0;
  std::uint64_t entry_arg0 = 0;
  std::uint64_t entry_arg1 = 0;
  std::uint64_t entry_arg2 = 0;
  std::uint64_t result = 0;
  std::uint64_t exit_process = 0;
  std::uint64_t exit_symbol_table = 0;
  std::uint64_t exit_offset_base = 0;
  std::uint64_t restored_process = 0;
  std::uint64_t restored_symbol_table = 0;
  std::uint64_t restored_offset_base = 0;
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
    std::uint64_t process,
    std::uint64_t symbol_table,
    std::uint64_t offset_base,
    goalpad::AOTEntry0 entry,
    GoalCallProbe* probe);

extern "C" std::uint64_t goalpad_probe_call_aot1_with_state(
    std::uint64_t process,
    std::uint64_t symbol_table,
    std::uint64_t offset_base,
    goalpad::AOTEntry1 entry,
    std::uint64_t arg0,
    GoalCallProbe1* probe);

extern "C" std::uint64_t goalpad_probe_call_aot2_with_state(
    std::uint64_t process,
    std::uint64_t symbol_table,
    std::uint64_t offset_base,
    goalpad::AOTEntry2 entry,
    std::uint64_t arg0,
    std::uint64_t arg1,
    GoalCallProbe2* probe);

extern "C" std::uint64_t goalpad_probe_call_aot3_with_state(
    std::uint64_t process,
    std::uint64_t symbol_table,
    std::uint64_t offset_base,
    goalpad::AOTEntry3 entry,
    std::uint64_t arg0,
    std::uint64_t arg1,
    std::uint64_t arg2,
    GoalCallProbe3* probe);

bool has_expected_jak1_false_func_arm64_code(goalpad::AOTEntry0 entry) {
#if defined(__arm64__)
  constexpr std::array<unsigned char, 8> expected = {
      0xe0, 0x03, 0x15, 0xaa, 0xc0, 0x03, 0x5f, 0xd6,
  };
  std::array<unsigned char, expected.size()> actual{};
  std::memcpy(actual.data(), reinterpret_cast<const void*>(entry), actual.size());
  return actual == expected;
#else
  return false;
#endif
}

bool has_expected_jak1_true_func_arm64_code(goalpad::AOTEntry0 entry) {
#if defined(__arm64__)
  constexpr std::array<unsigned char, 12> expected = {
      0xe0, 0x03, 0x15, 0xaa, 0x00, 0x20,
      0x00, 0x91, 0xc0, 0x03, 0x5f, 0xd6,
  };
  std::array<unsigned char, expected.size()> actual{};
  std::memcpy(actual.data(), reinterpret_cast<const void*>(entry), actual.size());
  return actual == expected;
#else
  return false;
#endif
}

bool has_expected_jak1_identity_arm64_code(goalpad::AOTEntry1 entry) {
#if defined(__arm64__)
  constexpr std::array<unsigned char, 4> expected = {
      0xc0, 0x03, 0x5f, 0xd6,
  };
  std::array<unsigned char, expected.size()> actual{};
  std::memcpy(actual.data(), reinterpret_cast<const void*>(entry), actual.size());
  return actual == expected;
#else
  return false;
#endif
}

bool has_expected_jak1_lognot_arm64_code(goalpad::AOTEntry1 entry) {
#if defined(__arm64__)
  constexpr std::array<unsigned char, 8> expected = {
      0xe0, 0x03, 0x20, 0xaa, 0xc0, 0x03, 0x5f, 0xd6,
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

bool has_expected_goal_state(const GoalCallProbe& probe,
                             std::uint64_t process,
                             std::uint64_t symbol_table,
                             std::uint64_t offset_base,
                             std::uint64_t result) {
  return probe.entry_process == process && probe.entry_symbol_table == symbol_table &&
         probe.entry_offset_base == offset_base && probe.result == result &&
         probe.exit_process == process && probe.exit_symbol_table == symbol_table &&
         probe.exit_offset_base == offset_base && probe.restored_process == 0x14 &&
         probe.restored_symbol_table == 0x15 && probe.restored_offset_base == 0x16;
}

bool has_expected_goal_state(const GoalCallProbe1& probe,
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

bool has_expected_goal_state(const GoalCallProbe2& probe,
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

bool has_expected_goal_state(const GoalCallProbe3& probe,
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

bool verifies_level_group_load_commands_set(goalpad::AOTEntry2 entry,
                                            std::uint64_t process,
                                            std::uint64_t symbol_table) {
  constexpr std::uint64_t first_value = 0x0123456789abcdefULL;
  constexpr std::uint64_t second_value = 0xfedcba9876543210ULL;
  SyntheticGoalArena arena;
  arena.bytes.fill(kSyntheticArenaGuard);
  SyntheticGoalArena expected = arena;
  GoalCallProbe2 first_probe;
  GoalCallProbe2 second_probe;

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
      !has_expected_goal_state(first_probe, process, symbol_table, first_offset_base,
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
         has_expected_goal_state(second_probe, process, symbol_table, second_offset_base,
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
  GoalCallProbe2 first_probe;
  GoalCallProbe2 second_probe;

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
      !has_expected_goal_state(first_probe, process, symbol_table, first_offset_base,
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
         has_expected_goal_state(second_probe, process, symbol_table, second_offset_base,
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
    GoalCallProbe3 probe;
    const auto result = goalpad_probe_call_aot3_with_state(
        process, kFalse, offset_base, entry, kThis, test_case.argument0,
        test_case.argument1, &probe);
    if (result != 0 ||
        !has_expected_goal_state(probe, process, kFalse, offset_base, kThis,
                                 test_case.argument0, test_case.argument1, result) ||
        !has_guard_bytes(arena, 0, kFirstWriteOffset) ||
        !has_guard_bytes(arena, kEndWriteOffset, arena.bytes.size()) ||
        arena.bytes != expected.bytes) {
      return false;
    }
  }
  return true;
}

void write_data_arena_word(std::byte* storage, std::uint32_t offset, std::uint32_t value) {
  std::memcpy(storage + offset, &value, sizeof(value));
}

void write_data_arena_halfword(std::byte* storage,
                               std::uint32_t offset,
                               std::uint16_t value) {
  std::memcpy(storage + offset, &value, sizeof(value));
}

std::uint32_t read_data_arena_word(const std::byte* storage, std::uint32_t offset) {
  std::uint32_t value = 0;
  std::memcpy(&value, storage + offset, sizeof(value));
  return value;
}

struct NativeMethodInvocationCounter {
  std::size_t calls = 0;
};

std::uint64_t count_native_method_invocation(const jak1::DataArenaNativeMethodCall1&,
                                             void* user_context) {
  auto* counter = static_cast<NativeMethodInvocationCounter*>(user_context);
  ++counter->calls;
  return 0;
}

bool verifies_load_state_reset(goalpad::AOTEntry1 entry, std::uint64_t process) {
  constexpr std::size_t kGuardSize = 16;
  constexpr std::byte kCanary = std::byte{0xa5};
  constexpr std::byte kSeed = std::byte{0x3c};
  constexpr std::uint32_t kSymbolTableEntrySize = 8;
  constexpr std::uint32_t kSymbolTable = 0x1000;
  constexpr std::uint32_t kSymbolTableEnd = kSymbolTable + jak1::SYM_TABLE_MEM_SIZE;
  constexpr std::uint32_t kS7 =
      kSymbolTable + (jak1::GOAL_MAX_SYMBOLS / 2) * kSymbolTableEntrySize + BASIC_OFFSET;
  constexpr std::uint32_t kLastSymbol =
      kSymbolTable + jak1::SYM_TABLE_END * kSymbolTableEntrySize;
  constexpr std::size_t kArenaSize = kSymbolTableEnd + 0x2000;
  constexpr std::size_t kLaneSize = kGuardSize + kArenaSize + kGuardSize;
  constexpr std::uint32_t kTypeType = 0x42004;
  constexpr std::uint32_t kFunctionType = 0x42044;
  constexpr std::uint32_t kLoadStateType = 0x42084;
  constexpr std::uint32_t kObject = 0x42104;
  constexpr std::uint32_t kObjectRaw = kObject - BASIC_OFFSET;
  constexpr std::uint32_t kFunction = 0x42a04;
  constexpr std::uint16_t kLoadStateAllocatedSize = 0x82c;
  constexpr std::uint16_t kLoadStatePaddedSize = 0x830;
  constexpr std::uint16_t kLoadStateMethodCount = 21;
  constexpr std::uint32_t kResetMethodId = 9;
  constexpr std::uint32_t kWantWordCount = 8;
  constexpr std::uint32_t kVisNickOffset = 0x20;
  constexpr std::uint32_t kCommandListOffset = 0x24;
  constexpr std::uint32_t kObjectNameOffset = 0x28;
  constexpr std::uint32_t kObjectStatusOffset = 0x428;
  constexpr std::uint32_t kObjectCount = 256;
  constexpr std::uint32_t kVisNickSentinel = 0xdecafbad;
  constexpr std::uint32_t kObjectEnd =
      kObject + kLoadStateAllocatedSize - BASIC_OFFSET;
  constexpr std::uint32_t kObjectGuardBegin = kObjectRaw - kGuardSize;
  constexpr std::uint32_t kObjectGuardEnd = kObjectEnd + kGuardSize;

  static_assert(std::is_same_v<goalpad::AOTEntry1, jak1::DataArenaNativeMethodEntry1>);
  static_assert(offsetof(jak1::Type, allocated_size) == 0x8);
  static_assert(offsetof(jak1::Type, padded_size) == 0xa);
  static_assert(offsetof(jak1::Type, num_methods) == 0xe);
  static_assert(offsetof(jak1::Type, new_method) == 0x10);
  static_assert(offsetof(jak1::Type, new_method) +
                    kResetMethodId * sizeof(std::uint32_t) ==
                0x34);
  static_assert(kSymbolTableEnd == 0x41000);
  static_assert(kArenaSize == 0x43000);
  static_assert(kObjectStatusOffset + kObjectCount * sizeof(std::uint32_t) == 0x828);
  static_assert(kFunction - BASIC_OFFSET >= kObjectGuardEnd);

  if (!entry) {
    return false;
  }

  const jak1::DataArenaHeader header{
      .global_heap_info = 0x100,
      .global_heap_base = kSymbolTable,
      .global_heap_current = kSymbolTableEnd,
      .global_heap_end = static_cast<std::uint32_t>(kArenaSize),
      .symbol_table = kSymbolTable,
      .symbol_table_end = kSymbolTableEnd,
      .symbol_table2 = kSymbolTable + BASIC_OFFSET,
      .last_symbol = kLastSymbol,
      .s7 = kS7,
      .empty_pair = kS7 + jak1_symbols::FIX_SYM_EMPTY_PAIR,
      .false_value = kS7,
      .true_value = kS7 + jak1_symbols::FIX_SYM_TRUE,
  };
  const std::array bindings{
      jak1::DataArenaNativeMethodBinding1{
          .object_type = kLoadStateType,
          .method_id = kResetMethodId,
          .method_value = kFunction,
          .allocated_size = kLoadStateAllocatedSize,
          .padded_size = kLoadStatePaddedSize,
          .arity = 1,
          .entry = entry,
      },
  };
  jak1::DataArenaNativeMethodArm64Context context{.process = process};

  std::vector<std::byte> backing(2 * kLaneSize, kCanary);
  auto* first_arena = backing.data() + kGuardSize;
  auto* second_arena = backing.data() + kLaneSize + kGuardSize;

  const auto stage_arena = [&](std::byte* storage) {
    std::fill(storage, storage + kArenaSize, std::byte{0});
    write_data_arena_word(storage, header.global_heap_info + offsetof(kheapinfo, base),
                          header.global_heap_base);
    write_data_arena_word(storage, header.global_heap_info + offsetof(kheapinfo, top),
                          header.global_heap_end);
    write_data_arena_word(storage, header.global_heap_info + offsetof(kheapinfo, current),
                          header.global_heap_current);
    write_data_arena_word(storage, header.global_heap_info + offsetof(kheapinfo, top_base),
                          header.global_heap_end);
    write_data_arena_word(storage, header.s7 + jak1_symbols::FIX_SYM_EMPTY_CAR,
                          header.empty_pair);
    write_data_arena_word(storage, header.s7 + jak1_symbols::FIX_SYM_EMPTY_CDR,
                          header.empty_pair);
    write_data_arena_word(storage, header.s7 + jak1_symbols::FIX_SYM_FALSE,
                          header.false_value);
    write_data_arena_word(storage, header.s7 + jak1_symbols::FIX_SYM_TRUE,
                          header.true_value);
    write_data_arena_word(storage, header.s7 + jak1_symbols::FIX_SYM_TYPE_TYPE, kTypeType);
    write_data_arena_word(storage, header.s7 + jak1_symbols::FIX_SYM_FUNCTION_TYPE,
                          kFunctionType);

    write_data_arena_word(storage, kTypeType - BASIC_OFFSET, kTypeType);
    write_data_arena_word(storage, kFunctionType - BASIC_OFFSET, kTypeType);
    write_data_arena_word(storage, kLoadStateType - BASIC_OFFSET, kTypeType);
    write_data_arena_halfword(storage, kLoadStateType + offsetof(jak1::Type, allocated_size),
                              kLoadStateAllocatedSize);
    write_data_arena_halfword(storage, kLoadStateType + offsetof(jak1::Type, padded_size),
                              kLoadStatePaddedSize);
    write_data_arena_halfword(storage, kLoadStateType + offsetof(jak1::Type, num_methods),
                              kLoadStateMethodCount);
    write_data_arena_word(
        storage,
        kLoadStateType + offsetof(jak1::Type, new_method) +
            kResetMethodId * sizeof(std::uint32_t),
        kFunction);
    write_data_arena_word(storage, kObjectRaw, kLoadStateType);
    write_data_arena_word(storage, kFunction - BASIC_OFFSET, kFunctionType);

    std::fill(storage + kObject, storage + kObjectEnd, kSeed);
    write_data_arena_word(storage, kObjectRaw, kLoadStateType);
    write_data_arena_word(storage, kObject + kVisNickOffset, kVisNickSentinel);
    std::fill(storage + kObjectGuardBegin, storage + kObjectRaw, kCanary);
    std::fill(storage + kObjectEnd, storage + kObjectGuardEnd, kCanary);

    return read_data_arena_word(storage,
                                header.global_heap_info + offsetof(kheapinfo, base)) ==
               header.global_heap_base &&
           read_data_arena_word(storage,
                                header.global_heap_info + offsetof(kheapinfo, top)) ==
               header.global_heap_end &&
           read_data_arena_word(storage,
                                header.global_heap_info + offsetof(kheapinfo, current)) ==
               header.global_heap_current &&
           read_data_arena_word(storage,
                                header.global_heap_info + offsetof(kheapinfo, top_base)) ==
               header.global_heap_end &&
           read_data_arena_word(storage,
                                header.s7 + jak1_symbols::FIX_SYM_EMPTY_CAR) ==
               header.empty_pair &&
           read_data_arena_word(storage,
                                header.s7 + jak1_symbols::FIX_SYM_EMPTY_CDR) ==
               header.empty_pair;
  };

  const auto invoke_and_verify = [&](std::byte* storage) {
    std::vector<std::byte> expected(storage, storage + kArenaSize);
    const auto write_expected = [&](std::uint32_t object_offset, std::uint32_t value) {
      write_data_arena_word(expected.data(), kObject + object_offset, value);
    };
    for (std::uint32_t index = 0; index < kWantWordCount; ++index) {
      write_expected(index * sizeof(std::uint32_t), header.false_value);
    }
    write_expected(kCommandListOffset, header.empty_pair);
    for (std::uint32_t index = 0; index < kObjectCount; ++index) {
      write_expected(kObjectNameOffset + index * sizeof(std::uint32_t), header.false_value);
      write_expected(kObjectStatusOffset + index * sizeof(std::uint32_t), 0);
    }

    const auto result = jak1::invoke_data_arena_native_basic_method1(
        storage, kArenaSize, header, kObject, kResetMethodId, bindings,
        &jak1::invoke_data_arena_native_method1_arm64, &context);
    return result.invoked() && result.value == kObject &&
           result.basic_method.object_type == kLoadStateType &&
           result.basic_method.allocated_size == kLoadStateAllocatedSize &&
           result.basic_method.padded_size == kLoadStatePaddedSize &&
           result.basic_method.method_value == kFunction &&
           read_data_arena_word(storage, kObjectRaw) == kLoadStateType &&
           read_data_arena_word(storage,
                                kLoadStateType + offsetof(jak1::Type, new_method) +
                                    kResetMethodId * sizeof(std::uint32_t)) == kFunction &&
           read_data_arena_word(storage, kFunction - BASIC_OFFSET) == kFunctionType &&
           read_data_arena_word(storage, kObject + kVisNickOffset) == kVisNickSentinel &&
           std::equal(storage, storage + kArenaSize, expected.begin());
  };

  if (!stage_arena(first_arena) || !invoke_and_verify(first_arena)) {
    return false;
  }
  if (!stage_arena(second_arena) || !invoke_and_verify(second_arena)) {
    return false;
  }

  if (!stage_arena(first_arena)) {
    return false;
  }
  const auto before_unbound = backing;
  auto unbound_binding = bindings[0];
  unbound_binding.method_value += BASIC_OFFSET;
  const std::array unbound_bindings{unbound_binding};
  NativeMethodInvocationCounter counter;
  const auto unbound = jak1::invoke_data_arena_native_basic_method1(
      first_arena, kArenaSize, header, kObject, kResetMethodId, unbound_bindings,
      &count_native_method_invocation, &counter);
  const auto is_canary = [](std::byte value) { return value == kCanary; };
  return unbound.error == jak1::DataArenaNativeMethodInvokeError::UnboundMethod &&
         unbound.lookup_error == jak1::DataArenaBasicMethodValueLookupError::None &&
         unbound.basic_method.method_value == kFunction && counter.calls == 0 &&
         backing == before_unbound &&
         std::all_of(backing.begin(), backing.begin() + kGuardSize, is_canary) &&
         std::all_of(backing.begin() + kLaneSize - kGuardSize,
                     backing.begin() + kLaneSize, is_canary) &&
         std::all_of(backing.begin() + kLaneSize,
                     backing.begin() + kLaneSize + kGuardSize, is_canary) &&
         std::all_of(backing.end() - kGuardSize, backing.end(), is_canary);
}

class SymbolValueOffsetRestore {
 public:
  explicit SymbolValueOffsetRestore(std::int32_t* offset) : m_offset(offset), m_saved(*offset) {}

  ~SymbolValueOffsetRestore() { *m_offset = m_saved; }

 private:
  std::int32_t* m_offset;
  std::int32_t m_saved;
};

bool verifies_load_state_value(goalpad::AOTEntry0 entry,
                               const goalpad::AOTSymbolValueBinding32& binding,
                               std::uint64_t process) {
  constexpr std::uint64_t kJak1S7 = 0x14fd24;
  constexpr std::size_t kJak1FixedSymbolEndOffset = 0x1d0;
  constexpr std::int32_t kPositiveSymbolOffset = 0x400;
  constexpr std::int32_t kNegativeSymbolOffset = -0x400;
  constexpr std::uint32_t kFirstValue = 0x00012345;
  constexpr std::uint32_t kSecondValue = 0x81234567;
  constexpr std::byte kArenaGuard = static_cast<std::byte>(0xa5);
  constexpr std::size_t kGuardSize = 16;
  constexpr auto kFirstSlot = kJak1S7 + static_cast<std::size_t>(kPositiveSymbolOffset);
  constexpr auto kSecondSlot = kJak1S7 - static_cast<std::size_t>(-kNegativeSymbolOffset);
  constexpr auto kArenaSize = kFirstSlot + sizeof(std::uint32_t);

  static_assert(kPositiveSymbolOffset >= kJak1FixedSymbolEndOffset);
  static_assert(-kNegativeSymbolOffset >= kJak1FixedSymbolEndOffset);
  static_assert(kJak1S7 >= static_cast<std::uint64_t>(-kNegativeSymbolOffset));
  static_assert(kSecondSlot + sizeof(std::uint32_t) <= kArenaSize);

  struct alignas(16) GuardedJak1SymbolArena {
    std::array<std::byte, kGuardSize> leading_guard;
    std::array<std::byte, kArenaSize> storage;
    std::array<std::byte, kGuardSize> trailing_guard;
  };
  static_assert(alignof(GuardedJak1SymbolArena) >= 16);
  static_assert(offsetof(GuardedJak1SymbolArena, storage) == kGuardSize);

  if (!entry || !binding.offset ||
      (reinterpret_cast<std::uintptr_t>(binding.offset) % alignof(std::int32_t)) != 0) {
    return false;
  }

  SymbolValueOffsetRestore restore(binding.offset);
  auto actual = std::make_unique<GuardedJak1SymbolArena>();
  actual->leading_guard.fill(kArenaGuard);
  actual->storage.fill(kArenaGuard);
  actual->trailing_guard.fill(kArenaGuard);
  auto expected = std::make_unique<GuardedJak1SymbolArena>();
  auto* arena = actual->storage.data();
  const auto offset_base = static_cast<std::uint64_t>(
      reinterpret_cast<std::uintptr_t>(arena));
  if ((offset_base & 0xf) != 0) {
    return false;
  }

  const auto write_value = [arena](std::size_t offset, std::uint32_t value) {
    std::memcpy(arena + offset, &value, sizeof(value));
  };
  const auto read_value = [arena](std::size_t offset) {
    std::uint32_t value = 0;
    std::memcpy(&value, arena + offset, sizeof(value));
    return value;
  };
  const auto matches_expected = [&actual, &expected] {
    return actual->leading_guard == expected->leading_guard &&
           actual->storage == expected->storage &&
           actual->trailing_guard == expected->trailing_guard;
  };
  const auto invoke = [&](std::int32_t symbol_offset, std::uint32_t expected_value) {
    *binding.offset = symbol_offset;
    GoalCallProbe probe{};
    const auto result = goalpad_probe_call_aot_with_state(
        process, kJak1S7, offset_base, entry, &probe);
    return result == expected_value && (result >> 32) == 0 &&
           has_expected_goal_state(probe, process, kJak1S7, offset_base, result);
  };

  write_value(kFirstSlot, 0);
  write_value(kSecondSlot, 0);
  if (read_value(kFirstSlot) != 0 || read_value(kSecondSlot) != 0) {
    return false;
  }
  *expected = *actual;
  if (!invoke(kPositiveSymbolOffset, 0) || !matches_expected()) {
    return false;
  }

  write_value(kFirstSlot, kFirstValue);
  *expected = *actual;
  if (!invoke(kPositiveSymbolOffset, kFirstValue) || !matches_expected()) {
    return false;
  }

  write_value(kSecondSlot, kSecondValue);
  *expected = *actual;
  return invoke(kNegativeSymbolOffset, kSecondValue) && matches_expected() &&
         read_value(kFirstSlot) == kFirstValue && read_value(kSecondSlot) == kSecondValue;
}

std::string architecture_name() {
#if defined(__arm64__)
  return "arm64";
#elif defined(__x86_64__)
  return "x86_64";
#else
  return "unsupported";
#endif
}

}  // namespace

namespace goalpad {

RuntimeStatus initialize_runtime(std::string storage_path) {
  constexpr std::uint64_t process = 0x1001;
  constexpr std::uint64_t symbol_table = 0x2002;
  constexpr std::uint64_t offset_base = 0x3003;
  constexpr std::uint64_t true_symbol_offset = 0x8;
  constexpr std::uint64_t identity_arg0 = 0x4a5b6c7d8e9fa0b1;
  constexpr std::uint64_t lognot_arg0 = 0x0123456789abcdefULL;
  constexpr std::uint64_t lognot_expected_result = 0xfedcba9876543210ULL;

  GoalCallProbe false_func_probe;
  GoalCallProbe true_func_probe;
  GoalCallProbe1 identity_probe;
  GoalCallProbe1 lognot_probe;
  RuntimeStatus status;
  status.architecture = architecture_name();
  status.storage_path = std::move(storage_path);
  const auto* false_func = find_aot_export0("false-func");
  if (!false_func || !false_func->entry) {
    status.message = "Required signed ARM64 AOT export unavailable: false-func";
    return status;
  }
  const auto* true_func = find_aot_export0("true-func");
  if (!true_func || !true_func->entry) {
    status.message = "Required signed ARM64 AOT export unavailable: true-func";
    return status;
  }
  const auto* load_state_value = find_aot_export0("load-state-value");
  if (!load_state_value || !load_state_value->entry) {
    status.message = "Required signed ARM64 AOT export unavailable: load-state-value";
    return status;
  }
  const auto* load_state_binding =
      find_aot_symbol_value_binding32("jak1", "*load-state*", "load-state");
  if (!load_state_binding || !load_state_binding->offset) {
    status.message = "Required signed ARM64 AOT symbol-value binding unavailable: *load-state*";
    return status;
  }
  const auto* identity = find_aot_export1("identity");
  if (!identity || !identity->entry) {
    status.message = "Required signed ARM64 AOT export unavailable: identity";
    return status;
  }
  const auto* lognot = find_aot_export1("lognot");
  if (!lognot || !lognot->entry) {
    status.message = "Required signed ARM64 AOT export unavailable: lognot";
    return status;
  }
  const auto* load_state_reset = find_aot_export1("reset!");
  if (!load_state_reset || !load_state_reset->entry) {
    status.message = "Required signed ARM64 AOT export unavailable: reset!";
    return status;
  }
  const auto* level_group_load_commands_set =
      find_aot_export2("level-group-load-commands-set!");
  if (!level_group_load_commands_set || !level_group_load_commands_set->entry) {
    status.message = "Required signed ARM64 AOT export unavailable: level-group-load-commands-set!";
    return status;
  }
  const auto* want_vis = find_aot_export2("want-vis");
  if (!want_vis || !want_vis->entry) {
    status.message = "Required signed ARM64 AOT export unavailable: want-vis";
    return status;
  }
  const auto* want_levels = find_aot_export3("want-levels");
  if (!want_levels || !want_levels->entry) {
    status.message = "Required signed ARM64 AOT export unavailable: want-levels";
    return status;
  }

  status.workload_result = goalpad_probe_call_aot_with_state(
      process, symbol_table, offset_base, false_func->entry, &false_func_probe);
  const auto true_func_result = goalpad_probe_call_aot_with_state(
      process, symbol_table, offset_base, true_func->entry, &true_func_probe);
  const auto identity_result = goalpad_probe_call_aot1_with_state(
      process, symbol_table, offset_base, identity->entry, identity_arg0, &identity_probe);
  const auto lognot_result = goalpad_probe_call_aot1_with_state(
      process, symbol_table, offset_base, lognot->entry, lognot_arg0, &lognot_probe);
  status.workload_verified = status.workload_result == symbol_table &&
                             has_expected_jak1_false_func_arm64_code(false_func->entry) &&
                             has_expected_goal_state(false_func_probe, process, symbol_table,
                                                     offset_base, status.workload_result) &&
                             true_func_result == symbol_table + true_symbol_offset &&
                             has_expected_jak1_true_func_arm64_code(true_func->entry) &&
                             has_expected_goal_state(true_func_probe, process, symbol_table,
                                                     offset_base, true_func_result) &&
                             identity_result == identity_arg0 &&
                             has_expected_jak1_identity_arm64_code(identity->entry) &&
                             has_expected_goal_state(identity_probe, process, symbol_table,
                                                     offset_base, identity_arg0, identity_result) &&
                             lognot_result == lognot_expected_result &&
                             has_expected_jak1_lognot_arm64_code(lognot->entry) &&
                             has_expected_goal_state(lognot_probe, process, symbol_table,
                                                     offset_base, lognot_arg0, lognot_result) &&
                             verifies_load_state_value(load_state_value->entry,
                                                      *load_state_binding, process) &&
                             has_expected_jak1_load_state_reset_arm64_code(
                                 load_state_reset->entry) &&
                             verifies_load_state_reset(load_state_reset->entry, process) &&
                             has_expected_jak1_level_group_load_commands_set_arm64_code(
                                 level_group_load_commands_set->entry) &&
                             verifies_level_group_load_commands_set(
                                 level_group_load_commands_set->entry, process, symbol_table) &&
                             has_expected_jak1_want_vis_arm64_code(want_vis->entry) &&
                             verifies_want_vis(want_vis->entry, process, symbol_table) &&
                             verifies_want_levels(want_levels->entry, process);
  status.message = status.workload_verified
                       ? "Signed ARM64 Jak 1 false-func, true-func, identity, lognot, and direct "
                         "level-group-load-commands-set!, want-vis, want-levels, and "
                         "data-arena-bound load-state reset plus load-state symbol-value AOT proof "
                         "verified"
                       : "Signed ARM64 Jak 1 false-func, true-func, identity, lognot, and direct "
                         "level-group-load-commands-set!, want-vis, want-levels, and "
                         "data-arena-bound load-state reset plus load-state symbol-value AOT proof "
                         "failed";
  return status;
}

}  // namespace goalpad
