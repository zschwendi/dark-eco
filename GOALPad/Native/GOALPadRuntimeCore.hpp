#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace goalpad {

/*! One GOAL type, read back out of the live kernel heap. */
struct KernelType {
  std::string symbol_name;
  std::string type_name;
  std::string parent_name;
  std::uint32_t type_offset = 0;
  std::uint32_t allocated_size = 0;
  std::uint32_t method_count = 0;
};

/*! A snapshot of the kernel session. GOAL pointers are byte offsets into EE main memory. */
struct KernelStatus {
  bool running = false;
  std::string message;
  std::string architecture;

  /*! The directory holding the player's own `iso/` and `fr3/` data, as the kernel was told it. */
  std::string data_directory;
  /*! False when a data directory was supplied but this build has no entry point to hand it to. */
  bool data_directory_accepted = false;

  std::uint64_t main_memory_address = 0;
  std::uint32_t main_memory_size = 0;
  bool main_memory_executable = false;

  std::uint32_t global_heap_base = 0;
  std::uint32_t global_heap_current = 0;
  std::uint32_t global_heap_top_base = 0;
  std::uint32_t global_heap_used_bytes = 0;
  std::uint32_t debug_heap_base = 0;

  std::uint32_t symbol_table = 0;
  std::uint32_t s7 = 0;
  std::uint32_t last_symbol = 0;
  std::int32_t symbol_count = 0;

  std::vector<KernelType> types;
};

/*!
 * Bring up the real OpenGOAL Jak 1 kernel: EE main memory, the kernel heaps, the GOAL symbol
 * table, and the fundamental types. All-or-nothing: on any failure the kernel is torn back down
 * and the returned status has `running == false` and a message naming the failure.
 *
 * `data_directory` is the directory holding the player's own prepared `iso/` and `fr3/` data, or
 * empty to start without game data. No game data ships with this application and none is ever
 * written into it.
 *
 * Never throws. The kernel is a process-wide singleton, so a second call while a session is live
 * fails instead of starting a second one.
 */
KernelStatus start_kernel(std::string data_directory) noexcept;

/*! Tear the kernel down. Safe to call when no session is live. Never throws. */
void stop_kernel() noexcept;

bool kernel_is_running() noexcept;

}  // namespace goalpad
