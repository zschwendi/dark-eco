#include <cstdio>

#include "GOALPad/Native/GOALPadPresentationGeometry.hpp"

namespace {
int failures = 0;

void check(bool condition, const char* description) {
  if (condition) {
    std::printf("  ok   %s\n", description);
  } else {
    std::printf("  FAIL %s\n", description);
    ++failures;
  }
}
}  // namespace

int main() {
  std::puts("Classic keeps the exact 4:3 target and letterbox");
  const auto classic = goalpad::presentation_geometry(2388, 1668, 2, false);
  check(classic.internal_width == 1280 && classic.internal_height == 960,
        "Classic remains 1280x960 at 2x");
  check(classic.draw_region_width == 2224 && classic.draw_region_height == 1668,
        "Classic uses the existing centred 4:3 draw region");
  check(classic.game_display_width == 640 && classic.game_display_height == 480,
        "Classic reports 640x480 to GOAL");

  std::puts("Modern Hor+ widens without reducing vertical resolution");
  const auto modern = goalpad::presentation_geometry(2388, 1668, 2, true);
  check(modern.internal_width == 1375 && modern.internal_height == 960,
        "Hor+ widens the internal target and retains its height");
  check(modern.draw_region_width == 2388 && modern.draw_region_height == 1668,
        "Hor+ fills the drawable");
  check(modern.game_display_width == 2388 && modern.game_display_height == 1668,
        "Hor+ reports the drawable aspect to GOAL");

  std::puts("Hor+ never narrows the Classic field of view");
  const auto portrait = goalpad::presentation_geometry(1668, 2388, 2, true);
  check(portrait.internal_width == 1280 && portrait.internal_height == 960,
        "a portrait drawable keeps the Classic target");
  check(portrait.draw_region_width == 1668 && portrait.draw_region_height == 1251,
        "a portrait drawable still fills width without vertical-FOV loss");
  check(portrait.game_display_width == 640 && portrait.game_display_height == 480,
        "a narrow drawable keeps the Classic GOAL aspect");

  const auto clamped = goalpad::presentation_geometry(1920, 1080, 99, false);
  check(clamped.internal_width == 2560 && clamped.internal_height == 1920,
        "the existing 4x internal-scale ceiling remains");

  if (failures) {
    std::printf("\n%d presentation geometry check(s) failed\n", failures);
    return 1;
  }
  std::puts("\nall presentation geometry checks passed");
  return 0;
}
