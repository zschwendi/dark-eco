#import "GOALPadRuntimeBridge.h"

int main(void) {
  @autoreleasepool {
    GOALPadGameFrameStateSnapshot snapshot = {};
    if (![GOALPadRuntimeBridge selectGame:GOALPadGameIdentifierJak2] ||
        [GOALPadRuntimeBridge selectGame:GOALPadGameIdentifierJak1] ||
        GOALPadRuntimeBridge.activeGameIdentifier != GOALPadGameIdentifierJak2 ||
        ![GOALPadRuntimeBridge isGameCodeLinkedForGame:GOALPadGameIdentifierJak2] ||
        [GOALPadRuntimeBridge isGameCodeLinkedForGame:GOALPadGameIdentifierJak1]) {
      return 1;
    }
    GOALPadInputSetRumbleEnabled(0, YES);
    [GOALPadRenderSurface.shared setDetailedFrameStatsEnabled:NO];
    (void)[GOALPadRuntimeBridge bootGameWithTargetFrameRate:60];
    (void)[GOALPadRuntimeBridge setTargetFrameRate:60];
    (void)[GOALPadRuntimeBridge runFrameAtPresentationTime:0 stateSnapshot:&snapshot];
    (void)GOALPadRuntimeBridge.exitToLibraryRequested;
    (void)GOALPadRuntimeBridge.gameFrameStateSnapshot;
    (void)GOALPadRuntimeBridge.jak2TraversalState;
    (void)GOALPadRuntimeBridge.jak2ProgressMenuSemanticSnapshot;
    return GOALPadRuntimeBridge.isGameCodeLinked ? 0 : 1;
  }
}
