#include <stdint.h>

extern uint64_t goalpad_aot_false_func(void);

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
  struct goal_call_probe probe = {0};
  const uint64_t result = goalpad_probe_call_aot_with_state(
      process, symbol_table, offset_base, goalpad_aot_false_func, &probe);

  return result == symbol_table && probe.entry_process == process &&
                 probe.entry_symbol_table == symbol_table &&
                 probe.entry_offset_base == offset_base && probe.result == result &&
                 probe.exit_process == process &&
                 probe.exit_symbol_table == symbol_table &&
                 probe.exit_offset_base == offset_base &&
                 probe.restored_process == 0x14 &&
                 probe.restored_symbol_table == 0x15 &&
                 probe.restored_offset_base == 0x16
             ? 0
             : 1;
}
