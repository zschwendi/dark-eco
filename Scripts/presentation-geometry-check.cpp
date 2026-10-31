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

  // Jak II reports the internal target to GOAL because its pause menu samples the PC-BLIT
  // snapshot of that target in GOAL framebuffer pixels. The bridge currently uses scale 1;
  // 2x and 4x cover the same geometry at the scales the shared helper supports.
  std::puts("The internal target can stand in for the Jak II GOAL framebuffer");
  struct Drawable {
    int width;
    int height;
  };
  const Drawable drawables[] = {
      {2388, 1668}, {1668, 2388}, {2752, 2064}, {2064, 2752}, {2732, 2048},
      {2048, 2732}, {2266, 1488}, {1488, 2266}, {2360, 1640}, {1800, 1125},
      {1125, 1800}, {1024, 768},  {640, 480},
  };
  bool keeps_height = true;
  bool classic_is_exact = true;
  bool widened_within_one_column = true;
  bool fills_drawable = true;
  for (const int scale : {1, 2, 4}) {
    for (const bool fit : {false, true}) {
      for (const auto& drawable : drawables) {
        const auto geometry =
            goalpad::presentation_geometry(drawable.width, drawable.height, scale, fit);
        const long long base_height = 480LL * scale;
        keeps_height &= geometry.internal_height == base_height;
        const bool wider = drawable.width * 3LL > drawable.height * 4LL;
        if (!fit || !wider) {
          classic_is_exact &= geometry.internal_width == 640LL * scale;
          continue;
        }
        // internal_width - 1 < base_height * aspect <= internal_width
        const long long exact = base_height * drawable.width;
        const long long target = static_cast<long long>(geometry.internal_width) * drawable.height;
        widened_within_one_column &= target >= exact && target - exact < drawable.height;
        fills_drawable &= geometry.draw_region_width == drawable.width &&
                          geometry.draw_region_height == drawable.height;
      }
    }
  }
  check(keeps_height, "every scale keeps a 480-line multiple target height");
  check(classic_is_exact, "Fit to Screen off and narrow drawables keep an exact 4:3 target");
  check(widened_within_one_column,
        "a widened target matches the drawable aspect to within one target column");
  check(fills_drawable, "a widened target still fills the whole drawable");

  const auto active = goalpad::presentation_geometry(2388, 1668, 1, true);
  check(active.internal_width == 688 && active.internal_height == 480,
        "the active Jak II 1x Fit to Screen target on a 2388x1668 drawable is 688x480");
  check(active.game_display_width != active.internal_width,
        "the drawable-sized Jak 1 display size is not the Jak II snapshot size");
  const auto active_classic = goalpad::presentation_geometry(2388, 1668, 1, false);
  check(active_classic.internal_width == active_classic.game_display_width &&
            active_classic.internal_height == active_classic.game_display_height,
        "at the active 1x scale Fit to Screen off reports the same 640x480 as before");

  if (failures) {
    std::printf("\n%d presentation geometry check(s) failed\n", failures);
    return 1;
  }
  std::puts("\nall presentation geometry checks passed");
  return 0;
}
