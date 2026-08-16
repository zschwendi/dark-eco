#import "GOALPadRuntimeBridge.h"

int main(void) {
  @autoreleasepool {
    GOALPadGameFrameStateSnapshot snapshot = {};
    GOALPadInputSetRumbleEnabled(0, YES);
    [GOALPadRenderSurface.shared setDetailedFrameStatsEnabled:NO];
    (void)[GOALPadRuntimeBridge bootGameWithTargetFrameRate:60];
    (void)[GOALPadRuntimeBridge setTargetFrameRate:60];
    (void)[GOALPadRuntimeBridge runFrameAtPresentationTime:0 stateSnapshot:&snapshot];
    (void)GOALPadRuntimeBridge.exitToLibraryRequested;
    (void)GOALPadRuntimeBridge.gameFrameStateSnapshot;
    (void)GOALPadRuntimeBridge.jak2ProgressMenuSemanticSnapshot;
    return GOALPadRuntimeBridge.isGameCodeLinked ? 0 : 1;
  }
}
