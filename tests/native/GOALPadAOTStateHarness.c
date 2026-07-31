#include <stdint.h>

extern uint64_t goalpad_aot_false_func(void);
extern uint64_t goalpad_aot_true_func(void);

struct goal_call_probe {
  uint64_t entry_process;
  uint64_t entry_symbol_table;
  uint64_t entry_offset_base;
  uint64_t result;
  uint64_t exit_process;
  uint64_t exit_symbol_table;
  uint64_t exit_offset_base;
  uint64_t restored_process;
  uint64_t restored_symbol_table;
  uint64_t restored_offset_base;
};

extern uint64_t goalpad_probe_call_aot_with_state(
    uint64_t process,
    uint64_t symbol_table,
    uint64_t offset_base,
    uint64_t (*entry)(void),
    struct goal_call_probe* probe);

int main(void) {
  const uint64_t process = 0x1001;
  const uint64_t symbol_table = 0x2002;
  const uint64_t offset_base = 0x3003;
  const uint64_t true_symbol_offset = 0x8;
  struct goal_call_probe false_func_probe = {0};
  struct goal_call_probe true_func_probe = {0};
  const uint64_t false_func_result = goalpad_probe_call_aot_with_state(
      process, symbol_table, offset_base, goalpad_aot_false_func, &false_func_probe);
  const uint64_t true_func_result = goalpad_probe_call_aot_with_state(
      process, symbol_table, offset_base, goalpad_aot_true_func, &true_func_probe);

  return false_func_result == symbol_table && false_func_probe.entry_process == process &&
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
                 true_func_probe.restored_offset_base == 0x16
             ? 0
             : 1;
}
