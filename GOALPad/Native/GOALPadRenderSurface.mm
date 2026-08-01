#import "GOALPadRuntimeBridge.h"

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
 * surface has to satisfy: a layer with a known drawable size and pixel format, an internal
 * resolution, and a draw region that keeps the game's 4:3 aspect.
 *
 * Until the Metal renderer is part of this build, `presentPlaceholder` below stands in for it. It
 * is the single function the fused renderer replaces, and it deliberately does the same two things
 * the real one does - render an offscreen target at the internal resolution, then present it into
 * the draw region - so the surface, the drawable, and the letterbox arithmetic are all exercised
 * for real.
 */

static NSString *const kPresentShaderSource =
    @"#include <metal_stdlib>\n"
    @"using namespace metal;\n"
    @"struct VOut { float4 pos [[position]]; float2 uv; };\n"
    @"vertex VOut goalpad_present_vertex(uint vid [[vertex_id]]) {\n"
    @"  const float2 corner[4] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1) };\n"
    @"  VOut out;\n"
    @"  out.pos = float4(corner[vid], 0.0, 1.0);\n"
    @"  out.uv = corner[vid] * float2(0.5, -0.5) + 0.5;\n"
    @"  return out;\n"
    @"}\n"
    @"fragment float4 goalpad_present_fragment(VOut in [[stage_in]],\n"
    @"                                         texture2d<float> src [[texture(0)]]) {\n"
    @"  constexpr sampler samp(filter::linear, address::clamp_to_edge);\n"
    @"  return src.sample(samp, in.uv);\n"
    @"}\n";

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
  id<MTLDevice> _device;
  id<MTLCommandQueue> _queue;
  id<MTLRenderPipelineState> _presentPipeline;
  id<MTLTexture> _gameTarget;
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
  return NO;
}

- (void)attachLayer:(CAMetalLayer *)layer {
  if (layer == nil) {
    _layer = nil;
    _gameTarget = nil;
    _presentPipeline = nil;
    _queue = nil;
    _device = nil;
    return;
  }

  _device = layer.device ?: MTLCreateSystemDefaultDevice();
  if (_device == nil) {
    self.lastError = @"No Metal device is available.";
    return;
  }

  layer.device = _device;
  layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
  layer.framebufferOnly = YES;
  _layer = layer;

  _queue = [_device newCommandQueue];
  if (_queue == nil) {
    self.lastError = @"Could not create a Metal command queue.";
    return;
  }

  NSError *error = nil;
  id<MTLLibrary> library = [_device newLibraryWithSource:kPresentShaderSource
                                                 options:nil
                                                   error:&error];
  if (library == nil) {
    self.lastError = [NSString stringWithFormat:@"Present shader failed to compile: %@",
                                                error.localizedDescription];
    return;
  }

  MTLRenderPipelineDescriptor *descriptor = [[MTLRenderPipelineDescriptor alloc] init];
  descriptor.vertexFunction = [library newFunctionWithName:@"goalpad_present_vertex"];
  descriptor.fragmentFunction = [library newFunctionWithName:@"goalpad_present_fragment"];
  descriptor.colorAttachments[0].pixelFormat = layer.pixelFormat;
  _presentPipeline = [_device newRenderPipelineStateWithDescriptor:descriptor error:&error];
  if (_presentPipeline == nil) {
    self.lastError = [NSString stringWithFormat:@"Present pipeline failed: %@",
                                                error.localizedDescription];
    return;
  }

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
  const int32_t clamped = std::clamp(scale, (int32_t)1, kMaxInternalScale);
  if (clamped == _internalScale) {
    return;
  }
  _internalScale = clamped;
  _gameTarget = nil;
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

/*!
 * Stand-in for `MetalRenderer::render_frame`. Renders the offscreen game target and presents it
 * into the draw region, in one command buffer, exactly where the fused renderer will.
 */
- (void)presentPlaceholder:(id<MTLCommandBuffer>)commands
                  drawable:(id<CAMetalDrawable>)drawable
                  geometry:(GOALPadSurfaceGeometry)geometry {
  MTLRenderPassDescriptor *gamePass = [MTLRenderPassDescriptor renderPassDescriptor];
  gamePass.colorAttachments[0].texture = _gameTarget;
  gamePass.colorAttachments[0].loadAction = MTLLoadActionClear;
  gamePass.colorAttachments[0].storeAction = MTLStoreActionStore;
  gamePass.colorAttachments[0].clearColor = MTLClearColorMake(0.06, 0.13, 0.20, 1.0);
  [[commands renderCommandEncoderWithDescriptor:gamePass] endEncoding];

  MTLRenderPassDescriptor *presentPass = [MTLRenderPassDescriptor renderPassDescriptor];
  presentPass.colorAttachments[0].texture = drawable.texture;
  presentPass.colorAttachments[0].loadAction = MTLLoadActionClear;
  presentPass.colorAttachments[0].storeAction = MTLStoreActionStore;
  presentPass.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);

  id<MTLRenderCommandEncoder> encoder =
      [commands renderCommandEncoderWithDescriptor:presentPass];
  const double offsetX = (geometry.drawableWidth - geometry.drawRegionWidth) / 2.0;
  const double offsetY = (geometry.drawableHeight - geometry.drawRegionHeight) / 2.0;
  [encoder setViewport:{offsetX, offsetY, (double)geometry.drawRegionWidth,
                        (double)geometry.drawRegionHeight, 0.0, 1.0}];
  [encoder setRenderPipelineState:_presentPipeline];
  [encoder setFragmentTexture:_gameTarget atIndex:0];
  [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
  [encoder endEncoding];
}

- (BOOL)renderFrame {
  if (_layer == nil || _queue == nil || _presentPipeline == nil) {
    return NO;
  }

  const GOALPadSurfaceGeometry geometry = [self geometry];
  if (geometry.drawRegionWidth <= 0 || geometry.drawRegionHeight <= 0) {
    return NO;
  }

  if (_gameTarget == nil || (int32_t)_gameTarget.width != geometry.internalWidth ||
      (int32_t)_gameTarget.height != geometry.internalHeight) {
    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:_layer.pixelFormat
                                     width:(NSUInteger)geometry.internalWidth
                                    height:(NSUInteger)geometry.internalHeight
                                 mipmapped:NO];
    descriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    descriptor.storageMode = MTLStorageModePrivate;
    _gameTarget = [_device newTextureWithDescriptor:descriptor];
    if (_gameTarget == nil) {
      self.lastError = @"Could not allocate the game render target.";
      return NO;
    }
  }

  @autoreleasepool {
    id<CAMetalDrawable> drawable = [_layer nextDrawable];
    if (drawable == nil) {
      return NO;
    }
    id<MTLCommandBuffer> commands = [_queue commandBuffer];
    [self presentPlaceholder:commands drawable:drawable geometry:geometry];
    [commands presentDrawable:drawable];
    [commands commit];
  }

  self.framesPresented = self.framesPresented + 1;
  return YES;
}

@end
