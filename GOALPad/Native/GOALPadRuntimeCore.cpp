#include "GOALPadRuntimeCore.hpp"

#include "GOALPadAOTExportRegistry.hpp"

#include <array>
#include <cstddef>
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

  GoalCallProbe false_func_probe;
  GoalCallProbe true_func_probe;
  GoalCallProbe1 identity_probe;
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

  status.workload_result = goalpad_probe_call_aot_with_state(
      process, symbol_table, offset_base, false_func->entry, &false_func_probe);
  const auto true_func_result = goalpad_probe_call_aot_with_state(
      process, symbol_table, offset_base, true_func->entry, &true_func_probe);
  const auto identity_result = goalpad_probe_call_aot1_with_state(
      process, symbol_table, offset_base, identity->entry, identity_arg0, &identity_probe);
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
                                                     offset_base, identity_arg0, identity_result);
  status.message = status.workload_verified
                       ? "Signed ARM64 Jak 1 false-func, true-func, and identity calls verified"
                       : "Signed ARM64 Jak 1 false-func, true-func, and identity call "
                         "verification failed";
  return status;
}

}  // namespace goalpad
