#include "GOALPadRuntimeCore.hpp"

#include "GOALPadAOTExportRegistry.hpp"

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>

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
  const auto* level_group_load_commands_set =
      find_aot_export2("level-group-load-commands-set!");
  if (!level_group_load_commands_set || !level_group_load_commands_set->entry) {
    status.message = "Required signed ARM64 AOT export unavailable: level-group-load-commands-set!";
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
                             has_expected_jak1_level_group_load_commands_set_arm64_code(
                                 level_group_load_commands_set->entry) &&
                             verifies_level_group_load_commands_set(
                                 level_group_load_commands_set->entry, process, symbol_table);
  status.message = status.workload_verified
                       ? "Signed ARM64 Jak 1 false-func, true-func, identity, lognot, and direct "
                         "level-group-load-commands-set! AOT proof verified"
                       : "Signed ARM64 Jak 1 false-func, true-func, identity, lognot, and direct "
                         "level-group-load-commands-set! AOT proof failed";
  return status;
}

}  // namespace goalpad
