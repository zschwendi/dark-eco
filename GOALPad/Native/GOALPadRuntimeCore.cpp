#include "GOALPadRuntimeCore.hpp"

#include <array>
#include <cstddef>
#include <cstring>

extern "C" std::uint64_t goalpad_aot_false();

namespace {

using GoalEntry = std::uint64_t (*)();

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

extern "C" std::uint64_t goalpad_probe_call_aot_with_state(
    std::uint64_t process,
    std::uint64_t symbol_table,
    std::uint64_t offset_base,
    GoalEntry entry,
    GoalCallProbe* probe);

bool has_expected_jak1_false_arm64_code() {
#if defined(__arm64__)
  constexpr std::array<unsigned char, 8> expected = {
      0xe0, 0x03, 0x15, 0xaa, 0xc0, 0x03, 0x5f, 0xd6,
  };
  std::array<unsigned char, expected.size()> actual{};
  std::memcpy(actual.data(), reinterpret_cast<const void*>(&goalpad_aot_false), actual.size());
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

  GoalCallProbe probe;
  RuntimeStatus status;
  status.architecture = architecture_name();
  status.storage_path = std::move(storage_path);
  status.workload_result = goalpad_probe_call_aot_with_state(
      process, symbol_table, offset_base, &goalpad_aot_false, &probe);
  status.workload_verified = status.workload_result == symbol_table &&
                             has_expected_jak1_false_arm64_code() &&
                             has_expected_goal_state(probe, process, symbol_table, offset_base,
                                                     status.workload_result);
  status.message = status.workload_verified
                       ? "Signed ARM64 Jak 1 false-form state call verified"
                       : "Signed ARM64 Jak 1 false-form state call verification failed";
  return status;
}

}  // namespace goalpad
