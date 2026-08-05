#pragma once

#include <algorithm>
#include <cstdint>
#include <limits>

namespace goalpad {

struct PresentationGeometry {
  std::int32_t drawable_width = 0;
  std::int32_t drawable_height = 0;
  std::int32_t internal_width = 640;
  std::int32_t internal_height = 480;
  std::int32_t draw_region_width = 0;
  std::int32_t draw_region_height = 0;
  std::int32_t game_display_width = 640;
  std::int32_t game_display_height = 480;
};

inline PresentationGeometry presentation_geometry(std::int32_t drawable_width,
                                                   std::int32_t drawable_height,
                                                   std::int32_t internal_scale,
                                                   bool horizontal_plus) {
  constexpr std::int32_t kBaseWidth = 640;
  constexpr std::int32_t kBaseHeight = 480;
  constexpr std::int32_t kMaximumScale = 4;

  PresentationGeometry result;
  result.drawable_width = std::max(drawable_width, 0);
  result.drawable_height = std::max(drawable_height, 0);
  const auto scale = std::clamp(internal_scale, std::int32_t{1}, kMaximumScale);
  result.internal_width = kBaseWidth * scale;
  result.internal_height = kBaseHeight * scale;

  if (result.drawable_width <= 0 || result.drawable_height <= 0) {
    return result;
  }

  const std::int64_t drawable_at_base_height =
      std::int64_t{result.drawable_width} * kBaseHeight;
  const std::int64_t base_at_drawable_height =
      std::int64_t{result.drawable_height} * kBaseWidth;
  const bool drawable_is_wider_than_classic =
      drawable_at_base_height > base_at_drawable_height;

  if (horizontal_plus && drawable_is_wider_than_classic) {
    const std::int64_t numerator =
        std::int64_t{result.internal_height} * result.drawable_width;
    const std::int64_t widened =
        (numerator + result.drawable_height - 1) / result.drawable_height;
    result.internal_width = static_cast<std::int32_t>(std::min<std::int64_t>(
        widened, std::numeric_limits<std::int32_t>::max()));
    result.draw_region_width = result.drawable_width;
    result.draw_region_height = result.drawable_height;
    result.game_display_width = result.drawable_width;
    result.game_display_height = result.drawable_height;
    return result;
  }

  const std::int64_t by_width =
      std::int64_t{result.drawable_width} * result.internal_height;
  const std::int64_t by_height =
      std::int64_t{result.drawable_height} * result.internal_width;
  if (by_width <= by_height) {
    result.draw_region_width = result.drawable_width;
    result.draw_region_height = static_cast<std::int32_t>(by_width / result.internal_width);
  } else {
    result.draw_region_height = result.drawable_height;
    result.draw_region_width = static_cast<std::int32_t>(by_height / result.internal_height);
  }
  return result;
}

}  // namespace goalpad
