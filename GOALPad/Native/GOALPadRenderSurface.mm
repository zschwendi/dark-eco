#import "GOALPadRuntimeBridge.h"

#include "GOALPadMetalHost.hpp"

#import <Metal/Metal.h>

#include <algorithm>

/*!
 * @file GOALPadRenderSurface.mm
 * The presentation surface: the CAMetalLayer the game is drawn into, and the geometry its present
 * pass works in.
 *
 * The game renders into an offscreen target at its own internal resolution and a PCRTC-style
 * present pass draws that target into a centred, letterboxed region of the drawable. That is what
 * `MetalRenderer::encode_present_pass` in the OpenGOAL fork does, and it is the contract this
 * surface satisfies: a layer with a known drawable size and pixel format, an internal resolution,
 * and a draw region that keeps the game's 4:3 aspect.
 *
 * The renderer itself is `goalpad::metal_host_render` in GOALPadMetalHost.mm. This file decides
 * only where the game frame goes on the screen.
 */

/*! The PS2's internal resolution, which the game's own render target is a multiple of. */
static const int32_t kGameBaseWidth = 640;
static const int32_t kGameBaseHeight = 480;
static const int32_t kMaxInternalScale = 4;

@interface GOALPadRenderSurface ()
@property(nonatomic, readwrite) uint64_t framesPresented;
@property(nonatomic, readwrite) NSString *lastError;
@end

@implementation GOALPadRenderSurface {
  CAMetalLayer *_layer;
  CGSize _drawableSize;
  int32_t _internalScale;
}

+ (GOALPadRenderSurface *)shared {
  static GOALPadRenderSurface *shared = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    shared = [[GOALPadRenderSurface alloc] init];
  });
  return shared;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _drawableSize = CGSizeZero;
    _internalScale = 2;
    self.lastError = @"";
  }
  return self;
}

- (BOOL)isRendererLinked {
  return goalpad::metal_host_is_running();
}

- (void)attachLayer:(CAMetalLayer *)layer {
  if (layer == nil) {
    _layer = nil;
    return;
  }
  layer.framebufferOnly = NO;
  goalpad::metal_host_attach_layer(layer);
  _layer = layer;
  self.lastError = @"";
}

- (void)setDrawableSize:(CGSize)size {
  if (size.width < 1 || size.height < 1) {
    return;
  }
  _drawableSize = size;
  _layer.drawableSize = size;
}

- (void)setInternalResolutionScale:(int32_t)scale {
  _internalScale = std::clamp(scale, (int32_t)1, kMaxInternalScale);
}

- (GOALPadSurfaceGeometry)geometry {
  GOALPadSurfaceGeometry geometry = {};
  geometry.drawableWidth = (int32_t)_drawableSize.width;
  geometry.drawableHeight = (int32_t)_drawableSize.height;
  geometry.internalWidth = kGameBaseWidth * _internalScale;
  geometry.internalHeight = kGameBaseHeight * _internalScale;

  // The largest rectangle of the game's own aspect that fits in the drawable. The present pass
  // centres this and clears the rest to black.
  if (geometry.drawableWidth > 0 && geometry.drawableHeight > 0) {
    const int64_t byWidth = (int64_t)geometry.drawableWidth * geometry.internalHeight;
    const int64_t byHeight = (int64_t)geometry.drawableHeight * geometry.internalWidth;
    if (byWidth <= byHeight) {
      geometry.drawRegionWidth = geometry.drawableWidth;
      geometry.drawRegionHeight =
          (int32_t)(byWidth / std::max(geometry.internalWidth, (int32_t)1));
    } else {
      geometry.drawRegionHeight = geometry.drawableHeight;
      geometry.drawRegionWidth =
          (int32_t)(byHeight / std::max(geometry.internalHeight, (int32_t)1));
    }
  }
  return geometry;
}

- (GOALPadRendererStats)stats {
  const auto core = goalpad::metal_host_stats();
  GOALPadRendererStats stats = {core.chains_sent,   core.chains_rendered,  core.chains_dropped,
                                core.texture_uploads, (int32_t)core.levels_loaded,
                                (int32_t)core.level_failures, (int32_t)core.last_draw_calls,
                                (int32_t)core.last_triangles};
  return stats;
}

- (NSString *)levelsWanted {
  return @(goalpad::metal_host_stats().levels_wanted.c_str());
}

- (NSString *)levelsLoaded {
  return @(goalpad::metal_host_stats().levels_loaded_names.c_str());
}

- (BOOL)renderFrame {
  if (_layer == nil) {
    return NO;
  }
  const GOALPadSurfaceGeometry geometry = [self geometry];
  if (geometry.drawRegionWidth <= 0 || geometry.drawRegionHeight <= 0) {
    return NO;
  }

  goalpad::MetalHostFrame frame;
  frame.game_res_w = geometry.internalWidth;
  frame.game_res_h = geometry.internalHeight;
  frame.draw_region_w = geometry.drawRegionWidth;
  frame.draw_region_h = geometry.drawRegionHeight;
  if (!goalpad::metal_host_render(_layer, frame)) {
    return NO;
  }

  self.framesPresented = self.framesPresented + 1;
  return YES;
}

@end
