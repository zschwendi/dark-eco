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

extern "C" std::uint64_t goalpad_probe_call_aot_with_state(
    std::uint64_t process, std::uint64_t symbol_table,
    std::uint64_t offset_base, goalpad::AOTEntry0 entry, GoalCallProbe* probe);

int main() {
  const auto* false_func = goalpad::find_aot_export0("false-func");
  if (!false_func || false_func->goal_name != "false-func" ||
      !false_func->entry || goalpad::find_aot_export0("identity") ||
      goalpad::find_aot_export0("")) {
    return 1;
  }

  constexpr std::uint64_t process = 0x1001;
  constexpr std::uint64_t symbol_table = 0x2002;
  constexpr std::uint64_t offset_base = 0x3003;
  GoalCallProbe probe{};
  const auto result = goalpad_probe_call_aot_with_state(
      process, symbol_table, offset_base, false_func->entry, &probe);

  return result == symbol_table && probe.entry_process == process &&
                 probe.entry_symbol_table == symbol_table &&
                 probe.entry_offset_base == offset_base &&
                 probe.result == result && probe.exit_process == process &&
                 probe.exit_symbol_table == symbol_table &&
                 probe.exit_offset_base == offset_base &&
                 probe.restored_process == 0x14 &&
                 probe.restored_symbol_table == 0x15 &&
                 probe.restored_offset_base == 0x16
             ? 0
             : 1;
}
