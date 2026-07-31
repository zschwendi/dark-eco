#include "GOALPadAOTExportRegistry.hpp"

#include <cstddef>
#include <cstdint>

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

extern "C" std::uint64_t goalpad_probe_call_aot_with_state(
    std::uint64_t process, std::uint64_t symbol_table,
    std::uint64_t offset_base, goalpad::AOTEntry0 entry, GoalCallProbe* probe);

extern "C" std::uint64_t goalpad_probe_call_aot1_with_state(
    std::uint64_t process, std::uint64_t symbol_table,
    std::uint64_t offset_base, goalpad::AOTEntry1 entry, std::uint64_t arg0,
    GoalCallProbe1* probe);

int main() {
  const auto* false_func = goalpad::find_aot_export0("false-func");
  const auto* true_func = goalpad::find_aot_export0("true-func");
  const auto* identity = goalpad::find_aot_export1("identity");
  if (!false_func || false_func->goal_name != "false-func" ||
      !false_func->entry || !true_func || true_func->goal_name != "true-func" ||
      !true_func->entry || goalpad::find_aot_export0("identity") ||
      goalpad::find_aot_export0("") || !identity ||
      identity->goal_name != "identity" || !identity->entry ||
      goalpad::find_aot_export1("false-func") ||
      goalpad::find_aot_export1("true-func") || goalpad::find_aot_export1("")) {
    return 1;
  }

  constexpr std::uint64_t process = 0x1001;
  constexpr std::uint64_t symbol_table = 0x2002;
  constexpr std::uint64_t offset_base = 0x3003;
  constexpr std::uint64_t true_symbol_offset = 0x8;
  constexpr std::uint64_t identity_arg0 = 0x4a5b6c7d8e9fa0b1;
  GoalCallProbe false_func_probe{};
  GoalCallProbe true_func_probe{};
  GoalCallProbe1 identity_probe{};
  const auto false_func_result = goalpad_probe_call_aot_with_state(
      process, symbol_table, offset_base, false_func->entry, &false_func_probe);
  const auto true_func_result = goalpad_probe_call_aot_with_state(
      process, symbol_table, offset_base, true_func->entry, &true_func_probe);
  const auto identity_result = goalpad_probe_call_aot1_with_state(
      process, symbol_table, offset_base, identity->entry, identity_arg0, &identity_probe);

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
                 identity_probe.restored_offset_base == 0x16
             ? 0
             : 1;
}
