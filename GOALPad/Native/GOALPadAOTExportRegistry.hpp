#pragma once

#include <cstdint>
#include <string_view>

namespace goalpad {

using AOTEntry0 = std::uint64_t (*)();
using AOTEntry1 = std::uint64_t (*)(std::uint64_t);
using AOTEntry2 = std::uint64_t (*)(std::uint64_t, std::uint64_t);

struct AOTExport0 {
  std::string_view goal_name;
  AOTEntry0 entry;
};

struct AOTExport1 {
  std::string_view goal_name;
  AOTEntry1 entry;
};

struct AOTExport2 {
  std::string_view goal_name;
  AOTEntry2 entry;
};

const AOTExport0* find_aot_export0(std::string_view goal_name) noexcept;
const AOTExport1* find_aot_export1(std::string_view goal_name) noexcept;
const AOTExport2* find_aot_export2(std::string_view goal_name) noexcept;

}  // namespace goalpad
