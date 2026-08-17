#include "../GOALPad/Native/GOALPadRuntimeBridge.h"

void GOALPadInputSetState(int32_t port, GOALPadControllerState state) {
  (void)port;
  (void)state;
}

void GOALPadInputSetDisconnected(int32_t port) {
  (void)port;
}

void GOALPadInputSetRumbleEnabled(int32_t port, BOOL enabled) {
  (void)port;
  (void)enabled;
}

GOALPadRumble GOALPadInputRumble(int32_t port) {
  (void)port;
  return (GOALPadRumble){0, 0};
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"
@implementation GOALPadRenderSurface

+ (GOALPadRenderSurface *)shared {
  static GOALPadRenderSurface *surface;
  if (surface == nil) {
    surface = [[GOALPadRenderSurface alloc] init];
  }
  return surface;
}

- (void)setInternalResolutionScale:(int32_t)scale {
  (void)scale;
}

- (void)setHorizontalPlusEnabled:(BOOL)enabled {
  (void)enabled;
}

@end
#pragma clang diagnostic pop
