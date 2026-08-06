#include "GOALPad/Native/GOALPadGameBoot.hpp"

#include <array>
#include <cstdlib>
#include <iostream>

namespace {

void expect(bool condition, const char* description) {
  if (!condition) {
    std::cerr << "FAIL  " << description << '\n';
    std::exit(1);
  }
  std::cout << "  ok   " << description << '\n';
}

}  // namespace

int main() {
  using goalpad::LookAroundState;
  using goalpad::classify_look_around_state;

  constexpr std::uint32_t kNormalMode = 0x100;
  constexpr std::uint32_t kLookAroundMode = 0x200;
  constexpr std::uint32_t kBillyMode = 0x300;
  constexpr auto kFirstPerson = goalpad::kJak1FirstPersonModeFlag;

  expect(classify_look_around_state(false, 0, kNormalMode, kLookAroundMode) ==
             LookAroundState::Unknown,
         "unavailable target state remains unknown");
  expect(classify_look_around_state(true, 0, kNormalMode, kLookAroundMode) ==
             LookAroundState::Normal,
         "a validated target with first-person mode clear is normal");
  expect(classify_look_around_state(true, kFirstPerson, kLookAroundMode, kLookAroundMode) ==
             LookAroundState::FirstPerson,
         "the first-person flag and look-around mode together report first person");
  expect(classify_look_around_state(true, kFirstPerson, kBillyMode, kLookAroundMode) ==
             LookAroundState::Unknown,
         "Billy and other first-person modes fail closed");
  expect(classify_look_around_state(true, kFirstPerson, kLookAroundMode, 0) ==
             LookAroundState::Unknown,
         "a missing look-around symbol fails closed");

  constexpr std::array<LookAroundState, 4> kExpected = {
      LookAroundState::Unknown,
      LookAroundState::Normal,
      LookAroundState::FirstPerson,
      LookAroundState::Normal,
  };
  const std::array<LookAroundState, 4> transition = {
      classify_look_around_state(false, 0, 0, kLookAroundMode),
      classify_look_around_state(true, 0, kNormalMode, kLookAroundMode),
      classify_look_around_state(true, kFirstPerson, kLookAroundMode, kLookAroundMode),
      classify_look_around_state(true, 0, kNormalMode, kLookAroundMode),
  };
  expect(transition == kExpected,
         "unavailable-normal-first-person-normal transitions are stable");

  std::cout << "game look-around state checks passed\n";
}
