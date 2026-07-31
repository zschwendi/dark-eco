#include "GOALPadRuntimeCore.hpp"

#include "game/kernel/core/kernel_core.h"
#include "game/kernel/jak1/kscheme.h"

#include <array>
#include <exception>
#include <string_view>

namespace {

/*! The types the fundamental-type bootstrap builds first. Reading them back proves the heap holds
 *  real, linked GOAL type objects rather than staged bytes. */
constexpr std::array<std::string_view, 8> kBootstrapTypes = {
    "object", "structure", "basic", "symbol", "type", "string", "function", "pair"};

std::string architecture_name() {
#if defined(__arm64__)
  return "arm64";
#elif defined(__x86_64__)
  return "x86_64";
#else
  return "unsupported";
#endif
}

std::string type_name_of(Ptr<jak1::Type> type) {
  if (!type.offset || !type->symbol.offset) {
    return {};
  }
  return jak1::info(type->symbol)->str->data();
}

/*! Read one bootstrapped type out of the live heap. Returns false if the kernel did not produce a
 *  usable type object for `symbol_name`. */
bool read_bootstrap_type(std::string_view symbol_name, goalpad::KernelType* out) {
  const std::string name(symbol_name);
  std::uint32_t symbol_offset = 0;
  std::uint32_t type_offset = 0;
  if (goal_kernel_core_lookup(name.c_str(), &symbol_offset, &type_offset) != GOAL_KERNEL_CORE_OK) {
    return false;
  }

  char buffer[64] = {};
  if (goal_kernel_core_type_name_of_symbol(name.c_str(), buffer, sizeof(buffer)) !=
      GOAL_KERNEL_CORE_OK) {
    return false;
  }

  auto type = Ptr<jak1::Type>(type_offset);
  const std::string parent = type_name_of(type->parent);

  out->symbol_name = name;
  out->type_name = buffer;
  out->parent_name = parent.empty() ? "<none>" : parent;
  out->type_offset = type_offset;
  out->allocated_size = type->allocated_size;
  out->method_count = type->num_methods;
  return true;
}

/*! Leave nothing live: any failure after mapping memory tears the whole session back down. */
goalpad::KernelStatus failure(std::string message, std::string architecture) {
  goal_kernel_core_shutdown();
  goalpad::KernelStatus status;
  status.running = false;
  status.architecture = std::move(architecture);
  status.message = std::move(message);
  return status;
}

}  // namespace

namespace goalpad {

KernelStatus start_kernel(std::string storage_path) noexcept {
  try {
    std::string architecture = architecture_name();

    if (goal_kernel_core_is_initialized()) {
      KernelStatus status;
      status.architecture = std::move(architecture);
      status.message = "A GOAL kernel session is already live; shut it down first.";
      return status;
    }

    if (goal_kernel_core_initialize() != GOAL_KERNEL_CORE_OK) {
      return failure(
          std::string("goal_kernel_core_initialize failed: ") + goal_kernel_core_last_error(),
          std::move(architecture));
    }

    goal_kernel_core_state state = {};
    if (goal_kernel_core_get_state(&state) != GOAL_KERNEL_CORE_OK) {
      return failure(
          std::string("goal_kernel_core_get_state failed: ") + goal_kernel_core_last_error(),
          std::move(architecture));
    }

    KernelStatus status;
    status.architecture = std::move(architecture);
    status.storage_path = std::move(storage_path);
    status.main_memory_address = state.main_memory_address;
    status.main_memory_size = state.main_memory_size;
    status.main_memory_executable = state.main_memory_executable != 0;
    status.global_heap_base = state.global_heap_base_offset;
    status.global_heap_current = state.global_heap_current_offset;
    status.global_heap_top_base = state.global_heap_top_base_offset;
    status.global_heap_used_bytes = state.global_heap_used_bytes;
    status.debug_heap_base = state.debug_heap_base_offset;
    status.symbol_table = state.symbol_table_offset;
    status.s7 = state.s7_offset;
    status.last_symbol = state.last_symbol_offset;
    status.symbol_count = state.symbol_count;

    status.types.reserve(kBootstrapTypes.size());
    for (const auto& name : kBootstrapTypes) {
      KernelType type;
      if (!read_bootstrap_type(name, &type)) {
        return failure("The kernel did not bootstrap the GOAL type '" + std::string(name) +
                           "': " + goal_kernel_core_last_error(),
                       status.architecture);
      }
      status.types.push_back(std::move(type));
    }

    status.running = true;
    status.message = "Real OpenGOAL Jak 1 kernel initialized: heaps, symbol table, and " +
                     std::to_string(status.types.size()) + " fundamental types are live.";
    return status;
  } catch (const std::exception& e) {
    return failure(std::string("kernel startup threw: ") + e.what(), architecture_name());
  } catch (...) {
    return failure("kernel startup threw an unknown exception", architecture_name());
  }
}

void stop_kernel() noexcept {
  goal_kernel_core_shutdown();
}

bool kernel_is_running() noexcept {
  return goal_kernel_core_is_initialized() != 0;
}

}  // namespace goalpad
