#include "GOALPad/Native/GOALPadGameBoot.hpp"

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <vector>

namespace {

constexpr std::size_t kMemoryBytes = 2048;
constexpr std::size_t kLowProtectBytes = 64;
constexpr std::uint32_t kGoalFalse = 68;
constexpr std::uint32_t kGoalTrue = 76;
constexpr std::uint32_t kProgressType = 100;
constexpr std::uint32_t kProgressPpointer = 200;
constexpr std::uint32_t kProgressObject = 324;
constexpr std::uint16_t kProgressAllocatedBytes = 192;
constexpr std::uint32_t kProgressStateType = 124;
constexpr std::uint32_t kStateType = 140;
constexpr std::uint32_t kProgressNormal = 160;
constexpr std::uint32_t kOtherState = 164;
constexpr std::uint32_t kNextStateObject = 604;
constexpr std::uint32_t kProgressStateObject = 700;

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
    write(memory, kStateType + 8, std::uint16_t{36});
    write(memory, kProgressStateType + 8, std::uint16_t{72});
    write(memory, kNextStateObject - 4, kStateType);
    write(memory, kNextStateObject + goalpad::progress_layout::kStateNameOffset,
          kProgressNormal);
    write(memory, kProgressObject + goalpad::progress_layout::kNextStateOffset,
          kNextStateObject);
    write(memory, kProgressStateObject - 4, kProgressStateType);
    set_screen(3);
    set_starting_screen(0);
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

  void set_starting_screen(std::int64_t value) {
    write(memory, kProgressStateObject + goalpad::progress_layout::kStartingStateOffset, value);
  }

  void set_next_state_name(std::uint32_t value) {
    write(memory, kNextStateObject + goalpad::progress_layout::kStateNameOffset, value);
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
        expected_type, kProgressStateObject, kProgressStateType, kStateType, kProgressNormal);
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
  expect(ordinary.navigation_available && ordinary.starting_screen == ProgressScreen::FuelCells,
         "the checked starting screen is published with the progress snapshot");
  expect(ordinary.can_exit_with_start && ordinary.can_go_back,
         "gameplay-origin settings expose exact Start-exit and Back eligibility");

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
  expect(!selected_snapshot.can_exit_with_start && !selected_snapshot.can_go_back,
         "selection and transition state disable navigation without hiding the snapshot");

  Fixture title;
  title.set_screen(27);
  title.set_starting_screen(27);
  const auto title_snapshot = title.read();
  expect(title_snapshot.can_exit_with_start && title_snapshot.can_go_back,
         "title-origin progress exposes physical Start and Back exit truth");

  Fixture files;
  files.set_screen(16);
  files.set_starting_screen(16);
  const auto file_snapshot = files.read();
  expect(!file_snapshot.can_exit_with_start && file_snapshot.can_go_back,
         "file lists retain source-proven Back without inventing Start exit");

  Fixture wrong_state;
  wrong_state.set_next_state_name(kOtherState);
  const auto wrong_state_snapshot = wrong_state.read();
  expect(wrong_state_snapshot.navigation_available && !wrong_state_snapshot.can_go_back &&
             !wrong_state_snapshot.can_exit_with_start,
         "a non-normal progress process disables both exit paths");

  Fixture pc_only;
  pc_only.set_screen(65);
  expect(pc_only.read().available, "valid PC-only progress states remain readable but unclassified");
  Fixture auto_save_disabled;
  auto_save_disabled.set_screen(61);
  expect(!auto_save_disabled.read().can_exit_with_start,
         "PC auto-save-disabled does not invent can-go-back eligibility");
  Fixture monitor;
  monitor.set_screen(62);
  expect(monitor.read().can_exit_with_start,
         "PC monitor retains its exact can-go-back eligibility");
  Fixture speedrun_category;
  speedrun_category.set_screen(66);
  speedrun_category.set_starting_screen(64);
  const auto speedrun_category_snapshot = speedrun_category.read();
  expect(speedrun_category_snapshot.available &&
             speedrun_category_snapshot.can_exit_with_start,
         "speedrun category options are readable and Start-exitable from speedrun options");
  speedrun_category.set_screen(67);
  expect(!speedrun_category.read().available,
         "the PC max sentinel is rejected as a display state");

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
