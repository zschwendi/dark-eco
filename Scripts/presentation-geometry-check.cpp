#include <cstdint>
#include <cstdio>
#include <limits>

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

bool is_unpresented(const goalpad::PresentationGeometry& geometry, int internal_scale) {
  return geometry.internal_width == 640 * internal_scale &&
         geometry.internal_height == 480 * internal_scale && geometry.draw_region_width == 0 &&
         geometry.draw_region_height == 0 && geometry.game_display_width == 640 &&
         geometry.game_display_height == 480;
}
}  // namespace

int main() {
  constexpr std::int32_t kInt32Max = std::numeric_limits<std::int32_t>::max();
  constexpr std::int32_t kInt32Min = std::numeric_limits<std::int32_t>::min();

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

  std::puts("Fit to Screen on a portrait drawable extends the target vertically");
  const auto portrait = goalpad::presentation_geometry(1668, 2388, 2, true);
  check(portrait.internal_width == 1280 && portrait.internal_height == 1833,
        "a portrait drawable keeps the Classic width and grows the target height");
  check(portrait.draw_region_width == 1668 && portrait.draw_region_height == 2388,
        "a portrait drawable fills the whole drawable");
  check(portrait.game_display_width == 1668 && portrait.game_display_height == 2388,
        "a portrait drawable reports its own aspect to GOAL for the Vert+ camera");

  const auto exact_portrait = goalpad::presentation_geometry(2064, 2752, 1, true);
  check(exact_portrait.internal_width == 640 && exact_portrait.internal_height == 854,
        "an exact 3:4 drawable at 1x rounds 853.33 target lines up to 854");
  check(exact_portrait.draw_region_width == 2064 && exact_portrait.draw_region_height == 2752,
        "an exact 3:4 drawable fills the whole drawable");
  check(exact_portrait.game_display_width == 2064 && exact_portrait.game_display_height == 2752,
        "an exact 3:4 drawable reports 3:4 to GOAL");
  const auto exact_portrait_2x = goalpad::presentation_geometry(2064, 2752, 2, true);
  check(exact_portrait_2x.internal_width == 1280 && exact_portrait_2x.internal_height == 1707,
        "an exact 3:4 drawable at 2x is 1280x1707");
  const auto exact_portrait_4x = goalpad::presentation_geometry(2064, 2752, 4, true);
  check(exact_portrait_4x.internal_width == 2560 && exact_portrait_4x.internal_height == 3414,
        "an exact 3:4 drawable at 4x is 2560x3414");

  std::puts("Fit to Screen off still letterboxes a portrait drawable exactly as before");
  const auto portrait_off = goalpad::presentation_geometry(1668, 2388, 2, false);
  check(portrait_off.internal_width == 1280 && portrait_off.internal_height == 960,
        "Fit to Screen off keeps the Classic 1280x960 target on a portrait drawable");
  check(portrait_off.draw_region_width == 1668 && portrait_off.draw_region_height == 1251,
        "Fit to Screen off keeps the existing width-filling 4:3 draw region");
  check(portrait_off.game_display_width == 640 && portrait_off.game_display_height == 480,
        "Fit to Screen off keeps reporting 640x480 to GOAL");

  std::puts("An exact 4:3 drawable is unchanged by Fit to Screen");
  for (const bool fit : {false, true}) {
    const auto square = goalpad::presentation_geometry(2752, 2064, 2, fit);
    check(square.internal_width == 1280 && square.internal_height == 960 &&
              square.draw_region_width == 2752 && square.draw_region_height == 2064 &&
              square.game_display_width == 640 && square.game_display_height == 480,
          fit ? "Fit to Screen on keeps an exact 4:3 drawable Classic"
              : "Fit to Screen off keeps an exact 4:3 drawable Classic");
  }

  const auto clamped = goalpad::presentation_geometry(1920, 1080, 99, false);
  check(clamped.internal_width == 2560 && clamped.internal_height == 1920,
        "the existing 4x internal-scale ceiling remains");
  const auto zero_scale = goalpad::presentation_geometry(1668, 2388, 0, true);
  check(zero_scale.internal_width == 640 && zero_scale.internal_height == 917,
        "a zero internal scale clamps to 1x before the portrait target is computed");
  const auto negative_scale = goalpad::presentation_geometry(1668, 2388, kInt32Min, true);
  check(negative_scale.internal_width == 640 && negative_scale.internal_height == 917,
        "a negative internal scale clamps to 1x before the portrait target is computed");
  const auto huge_scale = goalpad::presentation_geometry(1668, 2388, kInt32Max, true);
  check(huge_scale.internal_width == 2560 && huge_scale.internal_height == 3666,
        "an oversized internal scale clamps to 4x before the portrait target is computed");

  std::puts("Unpresentable drawables keep the early return");
  check(is_unpresented(goalpad::presentation_geometry(0, 2388, 2, true), 2),
        "a zero width returns the unpresented Classic geometry");
  check(is_unpresented(goalpad::presentation_geometry(1668, 0, 2, true), 2),
        "a zero height returns the unpresented Classic geometry");
  check(is_unpresented(goalpad::presentation_geometry(-1668, 2388, 2, true), 2),
        "a negative width returns the unpresented Classic geometry");
  check(is_unpresented(goalpad::presentation_geometry(1668, -2388, 2, true), 2),
        "a negative height returns the unpresented Classic geometry");
  check(is_unpresented(goalpad::presentation_geometry(kInt32Min, kInt32Min, 99, true), 4),
        "minimum integer dimensions return the unpresented Classic geometry");
  const auto negative = goalpad::presentation_geometry(-1, -1, 1, false);
  check(negative.drawable_width == 0 && negative.drawable_height == 0,
        "negative dimensions are reported as zero");

  std::puts("Extreme dimensions stay within the 32-bit result");
  const auto tallest = goalpad::presentation_geometry(1, kInt32Max, 4, true);
  check(tallest.internal_width == 2560 && tallest.internal_height == kInt32Max,
        "an extremely tall drawable saturates the target height");
  check(tallest.draw_region_width == 1 && tallest.draw_region_height == kInt32Max,
        "an extremely tall drawable still fills the drawable");
  const auto widest = goalpad::presentation_geometry(kInt32Max, 1, 4, true);
  check(widest.internal_width == kInt32Max && widest.internal_height == 1920,
        "an extremely wide drawable saturates the target width");
  const auto largest = goalpad::presentation_geometry(kInt32Max, kInt32Max, 4, true);
  check(largest.internal_width == 2560 && largest.internal_height == 2560 &&
            largest.draw_region_width == kInt32Max && largest.draw_region_height == kInt32Max &&
            largest.game_display_width == kInt32Max && largest.game_display_height == kInt32Max,
        "a square maximum drawable is narrower than 4:3 and fits without overflow");
  const auto largest_off = goalpad::presentation_geometry(kInt32Max, kInt32Max, 4, false);
  check(largest_off.internal_width == 2560 && largest_off.internal_height == 1920 &&
            largest_off.draw_region_width == kInt32Max &&
            largest_off.draw_region_height == static_cast<std::int32_t>(kInt32Max * 3LL / 4),
        "a square maximum drawable letterboxes without overflow when Fit to Screen is off");
  const auto tall_maximum = goalpad::presentation_geometry(kInt32Max - 1, kInt32Max, 4, true);
  check(tall_maximum.internal_width == 2560 && tall_maximum.internal_height == 2561 &&
            tall_maximum.draw_region_width == kInt32Max - 1 &&
            tall_maximum.draw_region_height == kInt32Max,
        "a near-square maximum drawable rounds its target height up without overflow");

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
      {1125, 1800}, {1024, 768},  {768, 1024},  {640, 480},   {480, 640},
  };
  bool classic_is_exact = true;
  bool widened_keeps_height = true;
  bool widened_within_one_column = true;
  bool heightened_keeps_width = true;
  bool heightened_within_one_row = true;
  bool fills_drawable = true;
  bool reports_drawable = true;
  for (const int scale : {1, 2, 4}) {
    for (const bool fit : {false, true}) {
      for (const auto& drawable : drawables) {
        const auto geometry =
            goalpad::presentation_geometry(drawable.width, drawable.height, scale, fit);
        const long long base_width = 640LL * scale;
        const long long base_height = 480LL * scale;
        const bool wider = drawable.width * 3LL > drawable.height * 4LL;
        const bool narrower = drawable.width * 3LL < drawable.height * 4LL;
        if (!fit || (!wider && !narrower)) {
          classic_is_exact &= geometry.internal_width == base_width &&
                              geometry.internal_height == base_height &&
                              geometry.game_display_width == 640 &&
                              geometry.game_display_height == 480;
          continue;
        }
        if (wider) {
          widened_keeps_height &= geometry.internal_height == base_height;
          // internal_width - 1 < base_height * aspect <= internal_width
          const long long exact = base_height * drawable.width;
          const long long target =
              static_cast<long long>(geometry.internal_width) * drawable.height;
          widened_within_one_column &= target >= exact && target - exact < drawable.height;
        } else {
          heightened_keeps_width &= geometry.internal_width == base_width;
          // internal_height - 1 < base_width / aspect <= internal_height
          const long long exact = base_width * drawable.height;
          const long long target =
              static_cast<long long>(geometry.internal_height) * drawable.width;
          heightened_within_one_row &= target >= exact && target - exact < drawable.width;
        }
        fills_drawable &= geometry.draw_region_width == drawable.width &&
                          geometry.draw_region_height == drawable.height;
        reports_drawable &= geometry.game_display_width == drawable.width &&
                            geometry.game_display_height == drawable.height;
      }
    }
  }
  check(classic_is_exact, "Fit to Screen off and exact 4:3 drawables keep an exact 4:3 target");
  check(widened_keeps_height, "a widened target keeps a 480-line multiple height");
  check(widened_within_one_column,
        "a widened target matches the drawable aspect to within one target column");
  check(heightened_keeps_width, "a heightened target keeps a 640-column multiple width");
  check(heightened_within_one_row,
        "a heightened target matches the drawable aspect to within one target row");
  check(fills_drawable, "a fitted target fills the whole drawable");
  check(reports_drawable, "a fitted target reports the drawable size to GOAL");

  const auto active = goalpad::presentation_geometry(2388, 1668, 1, true);
  check(active.internal_width == 688 && active.internal_height == 480,
        "the active Jak II 1x Fit to Screen target on a 2388x1668 drawable is 688x480");
  check(active.game_display_width != active.internal_width,
        "the drawable-sized Jak 1 display size is not the Jak II snapshot size");
  const auto active_portrait = goalpad::presentation_geometry(1668, 2388, 1, true);
  check(active_portrait.internal_width == 640 && active_portrait.internal_height == 917,
        "the active Jak II 1x Fit to Screen target on a 1668x2388 drawable is 640x917");
  const auto active_exact_portrait = goalpad::presentation_geometry(1536, 2048, 1, true);
  check(active_exact_portrait.internal_width == 640 &&
            active_exact_portrait.internal_height == 854,
        "the active Jak II 1x Fit to Screen target on an exact 3:4 drawable is 640x854");
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
