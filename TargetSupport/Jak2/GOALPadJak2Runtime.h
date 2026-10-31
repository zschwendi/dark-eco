#import <Foundation/Foundation.h>

#import "GOALPadGameDataPreparationBridge.h"
#import "GOALPadRuntimeBridge.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT const char* GOALPadJak2RuntimeIdentifier(void);

@interface GOALPadJak2KernelType : NSObject
@property(nonatomic, readonly) NSString *symbolName;
@property(nonatomic, readonly) NSString *typeName;
@property(nonatomic, readonly) NSString *parentName;
@property(nonatomic, readonly) uint32_t typeOffset;
@property(nonatomic, readonly) uint32_t allocatedSize;
@property(nonatomic, readonly) uint32_t methodCount;
@end

@interface GOALPadJak2KernelStatus : NSObject
@property(nonatomic, readonly, getter=isRunning) BOOL running;
@property(nonatomic, readonly) NSString *message;
@property(nonatomic, readonly) NSString *architecture;
@property(nonatomic, readonly) NSString *dataDirectory;
@property(nonatomic, readonly, getter=isDataDirectoryAccepted) BOOL dataDirectoryAccepted;
@property(nonatomic, readonly) uint64_t mainMemoryAddress;
@property(nonatomic, readonly) uint32_t mainMemorySize;
@property(nonatomic, readonly, getter=isMainMemoryExecutable) BOOL mainMemoryExecutable;
@property(nonatomic, readonly) uint32_t globalHeapBaseOffset;
@property(nonatomic, readonly) uint32_t globalHeapCurrentOffset;
@property(nonatomic, readonly) uint32_t globalHeapTopBaseOffset;
@property(nonatomic, readonly) uint32_t globalHeapUsedBytes;
@property(nonatomic, readonly) uint32_t debugHeapBaseOffset;
@property(nonatomic, readonly) uint32_t symbolTableOffset;
@property(nonatomic, readonly) uint32_t s7Offset;
@property(nonatomic, readonly) uint32_t lastSymbolOffset;
@property(nonatomic, readonly) int32_t symbolCount;
@property(nonatomic, readonly) NSArray<GOALPadJak2KernelType *> *types;
@end

@interface GOALPadJak2GameBootStatus : NSObject
@property(nonatomic, readonly, getter=isBooted) BOOL booted;
@property(nonatomic, readonly) NSString *message;
@property(nonatomic, readonly) int32_t kernelObjects;
@property(nonatomic, readonly) int32_t gameObjects;
@property(nonatomic, readonly) int32_t codeObjects;
@property(nonatomic, readonly) int32_t dataObjects;
@property(nonatomic, readonly) uint32_t kernelVersion;
@property(nonatomic, readonly) uint32_t globalHeapUsedBytes;
@property(nonatomic, readonly) int32_t symbolCount;
@property(nonatomic, readonly, getter=isSoundInstalled) BOOL soundInstalled;
@property(nonatomic, readonly) int32_t soundSampleRate;
@property(nonatomic, readonly, getter=isRendererInstalled) BOOL rendererInstalled;
@property(nonatomic, readonly, getter=didPlay) BOOL played;
@property(nonatomic, readonly) NSTimeInterval duration;
@end

@interface GOALPadJak2RuntimeBridge : NSObject
+ (BOOL)selectGame:(GOALPadGameIdentifier)gameIdentifier NS_SWIFT_NAME(selectGame(_:));
@property(class, nonatomic, readonly) GOALPadGameIdentifier activeGameIdentifier;
+ (BOOL)isGameCodeLinkedForGame:(GOALPadGameIdentifier)gameIdentifier
    NS_SWIFT_NAME(isGameCodeLinked(for:));
+ (GOALPadJak2KernelStatus *)startKernelWithDataDirectory:(nullable NSString *)dataDirectory
                                          savesDirectory:(NSString *)savesDirectory;
+ (void)stopKernel;
+ (BOOL)isKernelRunning;
+ (GOALPadJak2GameBootStatus *)bootGame;
+ (GOALPadJak2GameBootStatus *)bootGameWithTargetFrameRate:(NSInteger)targetFrameRate
    NS_SWIFT_NAME(bootGame(targetFrameRate:));
+ (BOOL)setTargetFrameRate:(NSInteger)targetFrameRate;
+ (BOOL)runFrameAtPresentationTime:(CFTimeInterval)targetPresentationTime
    NS_SWIFT_NAME(runFrame(at:));
+ (BOOL)runFrameAtPresentationTime:(CFTimeInterval)targetPresentationTime
                     stateSnapshot:(GOALPadGameFrameStateSnapshot *)stateSnapshot
    NS_SWIFT_NAME(runFrame(at:stateSnapshot:));
+ (void)resetFrameTiming;
@property(class, nonatomic, readonly) uint64_t framesRun;
@property(class, nonatomic, readonly, getter=isGameBooted) BOOL gameBooted;
@property(class, nonatomic, readonly) BOOL exitToLibraryRequested;
@property(class, nonatomic, readonly) GOALPadGameMode gameMode;
@property(class, nonatomic, readonly) GOALPadTitleStartState titleStartState;
@property(class, nonatomic, readonly) GOALPadLookAroundState lookAroundState;
@property(class, nonatomic, readonly) GOALPadJak2TraversalState jak2TraversalState;
@property(class, nonatomic, readonly) GOALPadSpeederState speederState;
@property(class, nonatomic, readonly) GOALPadProgressMenuSnapshot progressMenuSnapshot;
@property(class, nonatomic, readonly) GOALPadJak2ProgressMenuSemanticSnapshot jak2ProgressMenuSemanticSnapshot;
@property(class, nonatomic, readonly) GOALPadJak2GameSpeedSnapshot jak2GameSpeedSnapshot;
@property(class, nonatomic, readonly) GOALPadWarpGateTouchSnapshot warpGateTouchSnapshot;
@property(class, nonatomic, readonly) GOALPadCutsceneSkipTouchSnapshot cutsceneSkipTouchSnapshot;
@property(class, nonatomic, readonly) GOALPadFacePromptTouchSnapshot facePromptTouchSnapshot;
@property(class, nonatomic, readonly) GOALPadGameFrameStateSnapshot gameFrameStateSnapshot;
@property(class, nonatomic, readonly) GOALPadFrameChainStats frameChainStats;
@property(class, nonatomic, readonly, getter=isDataSeamLinked) BOOL dataSeamLinked;
@property(class, nonatomic, readonly, getter=isInputSeamLinked) BOOL inputSeamLinked;
@property(class, nonatomic, readonly, getter=isAudioSeamLinked) BOOL audioSeamLinked;
@property(class, nonatomic, readonly, getter=isGameCodeLinked) BOOL gameCodeLinked;
@end

FOUNDATION_EXPORT void GOALPadJak2InputSetState(int32_t port, GOALPadControllerState state);
FOUNDATION_EXPORT void GOALPadJak2InputSetDisconnected(int32_t port);
FOUNDATION_EXPORT void GOALPadJak2InputSetRumbleEnabled(int32_t port, BOOL enabled);
FOUNDATION_EXPORT GOALPadRumble GOALPadJak2InputRumble(int32_t port);
FOUNDATION_EXPORT int32_t GOALPadJak2InputReadCount(int32_t port);
FOUNDATION_EXPORT int32_t GOALPadJak2AudioSampleRate(void);
FOUNDATION_EXPORT int32_t GOALPadJak2AudioPull(int16_t *out, int32_t frames);

@interface GOALPadJak2CameraCorrectionTailSnapshot : NSObject {
 @private
  void *_nativeTail;
}
@property(nonatomic, readonly) GOALPadCameraCorrectionTailInfo info;
- (GOALPadCameraCorrectionTailFrame)frameAtIndex:(uint32_t)index NS_SWIFT_NAME(frame(at:));
@end

@interface GOALPadJak2RenderSurface : NSObject
@property(class, nonatomic, readonly) GOALPadJak2RenderSurface *shared;
- (void)attachLayer:(nullable CAMetalLayer *)layer;
- (void)setDrawableSize:(CGSize)size;
- (void)setInternalResolutionScale:(int32_t)scale;
- (void)setHorizontalPlusEnabled:(BOOL)enabled;
- (void)setDetailedFrameStatsEnabled:(BOOL)enabled;
- (GOALPadSurfaceGeometry)geometry;
- (BOOL)beginFrameAtTime:(CFTimeInterval)presentationTime NS_SWIFT_NAME(beginFrame(at:));
- (BOOL)endFrame;
@property(nonatomic, readonly, getter=isRendererLinked) BOOL rendererLinked;
@property(nonatomic, readonly) GOALPadRendererStats stats;
@property(nonatomic, readonly) GOALPadCameraCorrectionTailInfo cameraCorrectionTailInfo;
@property(nonatomic, readonly) GOALPadJak2CameraCorrectionTailSnapshot *cameraCorrectionTailSnapshot;
@property(nonatomic, readonly) GOALPadTargetControlTelemetry targetControlTelemetry;
@property(nonatomic, readonly) NSString *levelsWanted;
@property(nonatomic, readonly) NSString *levelsLoaded;
@property(nonatomic, readonly) NSString *lastError;
@end

FOUNDATION_EXPORT NSErrorDomain const GOALPadJak2GameDataPreparationErrorDomain;
FOUNDATION_EXPORT BOOL GOALPadJak2GameDataPreparationIsAvailable(void);

@interface GOALPadJak2GameDataPreparationProgress : NSObject
@property(nonatomic, readonly) GOALPadGameDataPreparationPhase phase;
@property(nonatomic, readonly) NSString *phaseLabel;
@property(nonatomic, readonly) uint64_t completed;
@property(nonatomic, readonly) uint64_t total;
@property(nonatomic, readonly) uint64_t bytesCompleted;
@property(nonatomic, readonly) NSString *currentItem;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

@interface GOALPadJak2GameDataPreparationSummary : NSObject
@property(nonatomic, readonly) uint32_t archivesWritten;
@property(nonatomic, readonly) uint32_t objectsWritten;
@property(nonatomic, readonly) uint32_t flatFilesWritten;
@property(nonatomic, readonly) uint32_t fr3FilesWritten;
@property(nonatomic, readonly) uint64_t outputBytes;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

typedef void (^GOALPadJak2GameDataPreparationProgressHandler)(GOALPadJak2GameDataPreparationProgress *progress);
typedef void (^GOALPadJak2GameDataPreparationCompletionHandler)(
    GOALPadJak2GameDataPreparationSummary *_Nullable summary, NSError *_Nullable error);

@interface GOALPadJak2GameDataPreparationJob : NSObject
- (instancetype)initWithSourceURL:(NSURL *)sourceURL
                     candidateURL:(NSURL *)candidateURL
               projectResourceURL:(NSURL *)projectResourceURL
              sourceObjectPackURL:(NSURL *)sourceObjectPackURL
    NS_SWIFT_NAME(init(sourceURL:candidateURL:projectResourceURL:sourceObjectPackURL:))
        NS_DESIGNATED_INITIALIZER;
- (void)startWithProgressHandler:(GOALPadJak2GameDataPreparationProgressHandler)progressHandler
               completionHandler:(GOALPadJak2GameDataPreparationCompletionHandler)completionHandler
    NS_SWIFT_NAME(start(progress:completion:));
- (void)cancel;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
