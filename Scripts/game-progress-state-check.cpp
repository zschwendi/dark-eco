#include "GOALPad/Native/GOALPadGameBoot.hpp"

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <vector>

namespace {

constexpr std::size_t kMemoryBytes = 1024;
constexpr std::size_t kLowProtectBytes = 64;
constexpr std::uint32_t kGoalFalse = 68;
constexpr std::uint32_t kGoalTrue = 76;
constexpr std::uint32_t kProgressType = 100;
constexpr std::uint32_t kProgressPpointer = 200;
constexpr std::uint32_t kProgressObject = 324;
constexpr std::uint16_t kProgressAllocatedBytes = 192;

[[noreturn]] void fail(const char* message) {
  std::cerr << "FAIL: " << message << '\n';
  std::exit(1);
}

void expect(bool condition, const char* message) {
  if (!condition) {
    fail(message);
  }
}

template <typename T>
void write(std::vector<std::uint8_t>& memory, std::size_t offset, T value) {
  std::memcpy(memory.data() + offset, &value, sizeof(value));
}

struct Fixture {
  std::vector<std::uint8_t> memory = std::vector<std::uint8_t>(kMemoryBytes);

  Fixture() {
    write(memory, kProgressPpointer, kProgressObject);
    write(memory, kProgressObject - 4, kProgressType);
    write(memory, kProgressType + 8, kProgressAllocatedBytes);
    set_screen(3);
    set_option(2);
    set_selected(kGoalFalse);
    set_transition(kGoalFalse);
  }

  void set_screen(std::int64_t value) {
    write(memory, kProgressObject + goalpad::progress_layout::kDisplayStateOffset, value);
  }

  void set_option(std::int32_t value) {
    write(memory, kProgressObject + goalpad::progress_layout::kOptionIndexOffset, value);
  }

  void set_selected(std::uint32_t value) {
    write(memory, kProgressObject + goalpad::progress_layout::kSelectedOptionOffset, value);
  }

  void set_transition(std::uint32_t value) {
    write(memory, kProgressObject + goalpad::progress_layout::kInTransitionOffset, value);
  }

  goalpad::ProgressMenuSnapshot read(std::size_t memory_bytes = kMemoryBytes,
                                     std::uint32_t ppointer = kProgressPpointer,
                                     std::uint32_t expected_type = kProgressType) const {
    return goalpad::read_progress_menu_snapshot(
        memory.data(), memory_bytes, kLowProtectBytes, kGoalFalse, kGoalTrue, ppointer,
        expected_type);
  }
};

}  // namespace

int main() {
  using goalpad::ProgressScreen;

  Fixture valid;
  const auto ordinary = valid.read();
  expect(ordinary.available, "valid progress object is available");
  expect(ordinary.screen == ProgressScreen::Settings, "display-state is decoded as signed 64-bit");
  expect(ordinary.option_index == 2, "option-index is decoded");
  expect(!ordinary.selected_option && !ordinary.in_transition,
         "GOAL false values decode without mutation");

  Fixture selected;
  selected.set_screen(18);
  selected.set_option(5);
  selected.set_selected(kGoalTrue);
  selected.set_transition(kGoalTrue);
  const auto selected_snapshot = selected.read();
  expect(selected_snapshot.available && selected_snapshot.screen == ProgressScreen::SaveGameTitle,
         "known file screen is decoded");
  expect(selected_snapshot.selected_option && selected_snapshot.in_transition,
         "GOAL true values decode exactly");

  Fixture pc_only;
  pc_only.set_screen(35);
  expect(pc_only.read().available, "valid PC-only progress states remain readable but unclassified");

  Fixture absent;
  expect(!absent.read(kMemoryBytes, kGoalFalse).available,
         "GOAL false progress-process fails closed");
  write(absent.memory, kProgressPpointer, std::uint32_t{0});
  expect(!absent.read().available, "empty ppointer target fails closed");

  Fixture wrong_type;
  write(wrong_type.memory, kProgressObject - 4, std::uint32_t{108});
  expect(!wrong_type.read().available, "wrong GOAL object type fails closed");

  Fixture too_small;
  write(too_small.memory, kProgressType + 8, std::uint16_t{172});
  expect(!too_small.read().available, "undersized progress allocation fails closed");

  Fixture truncated;
  expect(!truncated.read(500).available, "truncated allocated object span fails closed");

  Fixture invalid_screen;
  invalid_screen.set_screen(67);
  expect(!invalid_screen.read().available, "out-of-range display-state fails closed");
  invalid_screen.set_screen(-2);
  expect(!invalid_screen.read().available, "display-state below invalid fails closed");

  Fixture invalid_option;
  invalid_option.set_option(-1);
  expect(!invalid_option.read().available, "negative option-index fails closed");

  Fixture invalid_boolean;
  invalid_boolean.set_selected(80);
  expect(!invalid_boolean.read().available, "non-boolean selected-option fails closed");
  invalid_boolean.set_selected(kGoalFalse);
  invalid_boolean.set_transition(80);
  expect(!invalid_boolean.read().available, "non-boolean transition fails closed");

  std::cout << "game progress state check passed\n";
  return 0;
}
