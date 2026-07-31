#pragma once

#include <cstdint>
#include <string_view>

namespace goalpad {

using AOTEntry0 = std::uint64_t (*)();

struct AOTExport0 {
  std::string_view goal_name;
  AOTEntry0 entry;
};

const AOTExport0* find_aot_export0(std::string_view goal_name) noexcept;

}  // namespace goalpad
