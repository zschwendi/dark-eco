#import "GOALPadRuntimeBridge.h"

#import <TargetConditionals.h>

#if (TARGET_OS_IOS || TARGET_OS_VISION) && __has_include(<GOALPadJak2Runtime/GOALPadJak2Runtime.h>)
#import <GOALPadJak2Runtime/GOALPadJak2Runtime.h>
#define GOALPAD_HAS_JAK2_RUNTIME 1
#else
#define GOALPAD_HAS_JAK2_RUNTIME 0
#endif

/// Lock-free selection read shared by the frame, controller, and audio paths.
FOUNDATION_EXPORT GOALPadGameIdentifier GOALPadActiveGameIdentifier(void);

@interface GOALPadRenderSurface (GOALPadRuntimeRouting)
- (void)goalpadDetachActiveBackendPreservingConfiguration;
- (void)goalpadReplayConfigurationForActiveGame;
@end
