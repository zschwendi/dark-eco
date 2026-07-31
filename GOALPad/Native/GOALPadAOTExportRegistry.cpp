#include "GOALPadAOTExportRegistry.hpp"

#define OPENGOAL_AOT_EXPORT0(goal_name, c_symbol)                              \
  extern "C" std::uint64_t c_symbol();
#include "Generated/OpenGOALJak1FalseFunc.exports.h"
#include "Generated/OpenGOALJak1TrueFunc.exports.h"
#undef OPENGOAL_AOT_EXPORT0

#define OPENGOAL_AOT_EXPORT1(goal_name, c_symbol)                              \
  extern "C" std::uint64_t c_symbol(std::uint64_t);
#include "Generated/OpenGOALJak1Identity.exports.h"
#undef OPENGOAL_AOT_EXPORT1

namespace {

constexpr goalpad::AOTExport0 kAOTExports0[] = {
#define OPENGOAL_AOT_EXPORT0(goal_name, c_symbol) {goal_name, &c_symbol},
#include "Generated/OpenGOALJak1FalseFunc.exports.h"
#include "Generated/OpenGOALJak1TrueFunc.exports.h"
#undef OPENGOAL_AOT_EXPORT0
};

constexpr goalpad::AOTExport1 kAOTExports1[] = {
#define OPENGOAL_AOT_EXPORT1(goal_name, c_symbol) {goal_name, &c_symbol},
#include "Generated/OpenGOALJak1Identity.exports.h"
#undef OPENGOAL_AOT_EXPORT1
};

}  // namespace

namespace goalpad {

const AOTExport0* find_aot_export0(std::string_view goal_name) noexcept {
  for (const auto& native_export : kAOTExports0) {
    if (native_export.goal_name == goal_name) {
      return &native_export;
    }
  }
  return nullptr;
}

const AOTExport1* find_aot_export1(std::string_view goal_name) noexcept {
  for (const auto& native_export : kAOTExports1) {
    if (native_export.goal_name == goal_name) {
      return &native_export;
    }
  }
  return nullptr;
}

}  // namespace goalpad
