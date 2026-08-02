#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>

NS_ASSUME_NONNULL_BEGIN

/// One GOAL type read out of the live kernel heap.
@interface GOALPadKernelType : NSObject

@property(nonatomic, readonly) NSString *symbolName;
@property(nonatomic, readonly) NSString *typeName;
@property(nonatomic, readonly) NSString *parentName;
@property(nonatomic, readonly) uint32_t typeOffset;
@property(nonatomic, readonly) uint32_t allocatedSize;
@property(nonatomic, readonly) uint32_t methodCount;

@end

/// A snapshot of the GOAL kernel session. Every `*Offset` is a GOAL pointer: a byte offset from
/// `mainMemoryAddress`.
@interface GOALPadKernelStatus : NSObject

@property(nonatomic, readonly, getter=isRunning) BOOL running;
@property(nonatomic, readonly) NSString *message;
@property(nonatomic, readonly) NSString *architecture;

/// The directory holding the player's own prepared `iso/` and `fr3/` data, as the kernel was told
/// it. Empty when no directory was supplied or when this build cannot accept one.
@property(nonatomic, readonly) NSString *dataDirectory;
/// NO when a data directory was supplied but this build has no entry point to hand it to.
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

@property(nonatomic, readonly) NSArray<GOALPadKernelType *> *types;

@end

/// What booting the game did, read out of the live kernel.
@interface GOALPadGameBootStatus : NSObject

@property(nonatomic, readonly, getter=isBooted) BOOL booted;
@property(nonatomic, readonly) NSString *message;

/// Object files loaded out of each archive, and the code/data split of GAME.CGO's. Code comes from
/// the ahead-of-time C this app was built with; data comes off the player's own disc image.
@property(nonatomic, readonly) int32_t kernelObjects;
@property(nonatomic, readonly) int32_t gameObjects;
@property(nonatomic, readonly) int32_t codeObjects;
@property(nonatomic, readonly) int32_t dataObjects;

@property(nonatomic, readonly) uint32_t kernelVersion;
@property(nonatomic, readonly) uint32_t globalHeapUsedBytes;
@property(nonatomic, readonly) int32_t symbolCount;

/// Whether 989snd started and is answering the sound RPC, and the rate it mixes at.
@property(nonatomic, readonly, getter=isSoundInstalled) BOOL soundInstalled;
@property(nonatomic, readonly) int32_t soundSampleRate;

/// Whether the Metal renderer answered the machine layer's graphics functions. NO means the
/// frame's DMA chain was only measured and nothing was drawn.
@property(nonatomic, readonly, getter=isRendererInstalled) BOOL rendererInstalled;

/// Whether the engine's own `play` ran: the level heaps and the title level's load.
@property(nonatomic, readonly, getter=didPlay) BOOL played;
@property(nonatomic, readonly) NSTimeInterval duration;

@end

/// What the frames' DMA chains carried. Only measured when the Metal renderer did not start: the
/// renderer answers `__send-gfx-dma-chain` itself and reports through `GOALPadRenderSurface`.
typedef struct GOALPadFrameChainStats {
  int32_t chains;
  uint32_t lastPayloadBytes;
  uint32_t largestPayloadBytes;
  int32_t lastTextureUploads;
} GOALPadFrameChainStats;

/// The whole Swift-facing surface of the native runtime. The GOAL kernel is a process-wide
/// singleton, so this is a class API rather than an instantiable object.
@interface GOALPadRuntimeBridge : NSObject

/// Bring the kernel up, pointed at the player's own prepared data. All-or-nothing: if the returned
/// status is not `running`, nothing is live and `message` says why. `dataDirectory` is the
/// directory that holds `iso/` and `fr3/`; pass nil to start without game data.
+ (GOALPadKernelStatus *)startKernelWithDataDirectory:(nullable NSString *)dataDirectory;

/// Tear the kernel down. Safe to call when no session is live.
+ (void)stopKernel;

+ (BOOL)isKernelRunning;

/// Boot Jak 1: KERNEL.CGO, the machine layer, GAME.CGO, then the engine's own `play`. The kernel
/// must already be up. This takes seconds and runs the game's own startup code, so call it off the
/// main thread; nothing else may touch the kernel while it runs.
+ (GOALPadGameBootStatus *)bootGame;

/// Run one frame of the game: `kernel-dispatcher`, then the overlord's vblank work. The target
/// presentation time supplies the same 60 Hz cadence that schedules the frame. NO when the game
/// is not booted. Call from one thread only.
+ (BOOL)runFrameAtPresentationTime:(CFTimeInterval)targetPresentationTime
    NS_SWIFT_NAME(runFrame(at:));

/// Forget display-link cadence across an app lifecycle pause.
+ (void)resetFrameTiming;

@property(class, nonatomic, readonly) uint64_t framesRun;
@property(class, nonatomic, readonly, getter=isGameBooted) BOOL gameBooted;
@property(class, nonatomic, readonly) GOALPadFrameChainStats frameChainStats;

/// Whether this build carries each engine host seam. A seam that is not linked reports its absence
/// instead of pretending to work; see `GOALPadEngineSeams.h`.
@property(class, nonatomic, readonly, getter=isDataSeamLinked) BOOL dataSeamLinked;
@property(class, nonatomic, readonly, getter=isInputSeamLinked) BOOL inputSeamLinked;
@property(class, nonatomic, readonly, getter=isAudioSeamLinked) BOOL audioSeamLinked;
/// NO when this build has no ahead-of-time Jak 1 code, in which case the game cannot boot at all.
@property(class, nonatomic, readonly, getter=isGameCodeLinked) BOOL gameCodeLinked;

@end

#pragma mark - Controller input

#ifdef __cplusplus
extern "C" {
#endif

/// The held-button bits GOAL reads, which are the bit numbers of the `pad-buttons` enum in
/// `goal_src/jak1/engine/ps2/pad.gc`. The implementation static-asserts these against the engine's
/// own `goal_pad_button` whenever that seam is linked.
typedef NS_OPTIONS(uint32_t, GOALPadButton) {
  GOALPadButtonSelect = 1u << 0,
  GOALPadButtonL3 = 1u << 1,
  GOALPadButtonR3 = 1u << 2,
  GOALPadButtonStart = 1u << 3,
  GOALPadButtonUp = 1u << 4,
  GOALPadButtonRight = 1u << 5,
  GOALPadButtonDown = 1u << 6,
  GOALPadButtonLeft = 1u << 7,
  GOALPadButtonL2 = 1u << 8,
  GOALPadButtonR2 = 1u << 9,
  GOALPadButtonL1 = 1u << 10,
  GOALPadButtonR1 = 1u << 11,
  GOALPadButtonTriangle = 1u << 12,
  GOALPadButtonCircle = 1u << 13,
  GOALPadButtonCross = 1u << 14,
  GOALPadButtonSquare = 1u << 15,
};

/// Sticks are a byte per axis. X grows to the right and Y grows downward, which is what the PS2
/// pad reported and what `engine/ps2/pad.gc` expects.
#define GOALPadAnalogNeutral 127

/// One controller as the app read it, ready to be pushed at the engine.
typedef struct GOALPadControllerState {
  GOALPadButton buttons;
  uint8_t leftX;
  uint8_t leftY;
  uint8_t rightX;
  uint8_t rightY;
  uint8_t leftTrigger;
  uint8_t rightTrigger;
} GOALPadControllerState;

/// What GOAL last asked a port's two vibration motors to do. `large` is the on/off motor GOAL
/// pulses to fake an intensity; `small` is the analog one.
typedef struct GOALPadRumble {
  uint8_t large;
  uint8_t small;
} GOALPadRumble;

/// How many controller ports the game reads.
#define GOALPadPortCount 4

/// Push what `port` is holding right now. Call once per frame, before the frame runs. A port the
/// app never sets, or sets disconnected, is reported to GOAL as empty rather than as a pad with
/// nothing pressed.
void GOALPadInputSetState(int32_t port, GOALPadControllerState state);
void GOALPadInputSetDisconnected(int32_t port);

/// Read the motors back out. All zero when nothing is buzzing or the seam is not linked.
GOALPadRumble GOALPadInputRumble(int32_t port);

/// How many times GOAL has read `port`. 0 when the seam is not linked, which is how the app can
/// tell "no engine" from "engine is ignoring the pad".
int32_t GOALPadInputReadCount(int32_t port);

#pragma mark - Audio output

/// The rate the engine's mixer runs at. Its sequencer timing is derived from this, so a host that
/// cannot open a device at this rate has to resample rather than ask for another rate.
int32_t GOALPadAudioSampleRate(void);

/// Render `frames` interleaved stereo 16-bit frames into `out` and return how many were written:
/// `frames` when the engine is producing sound, 0 when it is not, in which case `out` is untouched
/// and the caller is expected to output silence.
///
/// Safe to call from the audio device's render thread: it takes no Objective-C path and allocates
/// nothing.
int32_t GOALPadAudioPull(int16_t *out, int32_t frames);

#ifdef __cplusplus
}  // extern "C"
#endif

#pragma mark - Presentation surface

/// The geometry the renderer's present pass works in. `internal*` is the offscreen target the game
/// draws into; `drawRegion*` is the letterboxed rectangle that target is drawn into, centred in
/// the drawable.
typedef struct GOALPadSurfaceGeometry {
  int32_t drawableWidth;
  int32_t drawableHeight;
  int32_t internalWidth;
  int32_t internalHeight;
  int32_t drawRegionWidth;
  int32_t drawRegionHeight;
} GOALPadSurfaceGeometry;

/// Numeric evidence retained for one consecutive-frame eichar-lod0 transform discontinuity.
/// Issue bit 0 is a uniform-scale jump; bit 1 is an aspect/per-axis-shape jump.
typedef struct GOALPadMercTransformEvent {
  uint64_t hostTickID;
  uint64_t chainOrdinal;
  uint8_t issueMask;
  int32_t boneSlot;
  uint64_t modelNameHash;
  uint64_t previousFrameID;
  uint64_t currentFrameID;
  uint64_t previousMatrixHash;
  uint64_t currentMatrixHash;
  double previousAxisNormX;
  double previousAxisNormY;
  double previousAxisNormZ;
  double currentAxisNormX;
  double currentAxisNormY;
  double currentAxisNormZ;
  double previousScale;
  double currentScale;
  double previousAspect;
  double currentAspect;
  uint64_t previousSourceBase;
  uint64_t currentSourceBase;
} GOALPadMercTransformEvent;

/// What the Metal renderer has been asked to do since the game booted.
typedef struct GOALPadRendererStats {
  uint64_t chainsSent;      ///< frames that handed over a DMA chain
  uint64_t chainsRendered;  ///< chains whose game passes were encoded and committed
  uint64_t chainsDropped;   ///< chains replaced before a tick consumed them
  uint64_t framesArmed;     ///< display-link ticks with an attached Metal surface
  uint64_t framesWithoutChain;
  uint64_t framesWithMultipleChains;
  uint64_t maxChainsPerFrame;
  uint64_t drawablesAcquired;
  uint64_t drawableMisses;
  uint64_t latePresentSubmissions;
  uint64_t lastHostTickID;
  uint64_t lastChainOrdinal;
  uint64_t lastEngineFrameID;
  uint64_t lastCameraFingerprint;
  int32_t lastCameraPackets;
  uint64_t producerCameraAlternations;
  uint64_t lastCameraAlternationOlderFrameID;
  uint64_t lastCameraAlternationPreviousFrameID;
  uint64_t lastCameraAlternationCurrentFrameID;
  uint64_t lastCameraAlternationOlderFingerprint;
  uint64_t lastCameraAlternationPreviousFingerprint;
  uint64_t lastCameraAlternationCurrentFingerprint;
  uint64_t lastCameraAlternationHostTickID;
  uint64_t lastCameraAlternationChainOrdinal;
  uint64_t lastCameraAlternationPacketFingerprint;
  uint8_t lastCameraAlternationLiveMismatchQwords;
  uint8_t lastCameraAlternationPacketMismatchQwords;
  uint16_t lastCameraAlternationRenderLiveMismatchQwords;
  uint16_t lastCameraAlternationRenderPacketMismatchQwords;
  double lastCameraOlderToPreviousDistance;
  double lastCameraPreviousToCurrentDistance;
  double lastCameraOlderToCurrentDistance;
  int32_t lastLiveCameraMismatches;
  int32_t lastPacketCameraMismatches;
  uint8_t lastLiveCameraMismatchQwords;
  uint8_t lastPacketCameraMismatchQwords;
  uint64_t liveCameraMismatches;
  uint64_t packetCameraMismatches;
  uint64_t submissions;
  uint64_t presentationsCompleted;
  uint64_t presentationDrops;
  uint64_t presentationOrderMismatches;
  uint64_t lastSubmissionID;
  uint64_t lastPresentedSubmissionID;
  uint64_t lastDroppedSubmissionID;
  uint64_t lastDrawableID;
  uint64_t lastPresentedDrawableID;
  uint64_t lastPresentedEngineFrameID;
  uint64_t lastPresentedHostTickID;
  uint64_t lastPresentedChainOrdinal;
  double lastRequestedPresentationTime;
  double lastActualPresentationTime;
  uint64_t textureUploads;  ///< `__pc-texture-upload-now` calls
  int32_t levelsLoaded;     ///< levels whose `.fr3` art is on the GPU
  int32_t levelFailures;    ///< levels the game asked for that would not load
  int32_t lastDrawCalls;
  int32_t lastTriangles;
  int32_t mercModels;
  int32_t mercDraws;
  int32_t mercBoneVectors;
  int32_t mercMissingBoneSlots;
  int32_t mercModelsWithMissingBoneSlots;
  uint64_t mercMissingBoneSlotsTotal;
  uint64_t mercModelsWithMissingBoneSlotsTotal;
  uint64_t lastMercMissingBoneEngineFrameID;
  uint64_t lastMercMissingBoneHostTickID;
  uint64_t lastMercMissingBoneChainOrdinal;
  int32_t lastMercMissingBoneSlots;
  int32_t lastMercModelsWithMissingBoneSlots;
  int32_t mercNonfiniteBoneMatrices;
  int32_t mercDegenerateBoneMatrices;
  int32_t mercIncoherentBoneSources;
  int32_t mercModelsWithPaletteHealthIssues;
  uint64_t mercNonfiniteBoneMatricesTotal;
  uint64_t mercDegenerateBoneMatricesTotal;
  uint64_t mercIncoherentBoneSourcesTotal;
  uint64_t mercModelsWithPaletteHealthIssuesTotal;
  uint64_t lastMercPaletteHealthEngineFrameID;
  uint64_t lastMercPaletteHealthHostTickID;
  uint64_t lastMercPaletteHealthChainOrdinal;
  uint8_t lastMercPaletteHealthIssueMask;
  int32_t lastMercPaletteHealthBoneSlot;
  uint64_t lastMercPaletteHealthModelNameHash;
  uint64_t lastMercPaletteHealthMatrixHash;
  double lastMercPaletteHealthAxisNormX;
  double lastMercPaletteHealthAxisNormY;
  double lastMercPaletteHealthAxisNormZ;
  double lastMercPaletteHealthNormalizedAbsDeterminant;
  uint32_t lastMercPaletteHealthSourceAddress;
  uint64_t lastMercPaletteHealthSourceBase;
  uint64_t lastMercPaletteHealthExpectedSourceBase;
  int32_t mercEicharTransformDiscontinuities;
  uint64_t mercEicharTransformDiscontinuitiesTotal;
  GOALPadMercTransformEvent firstMercEicharTransformDiscontinuity;
  GOALPadMercTransformEvent lastMercEicharTransformDiscontinuity;
  uint64_t mercBadBonePointers;
  uint64_t mercBadDrawRanges;
} GOALPadRendererStats;

/// The one presentation surface. The app's Metal view owns the layer and hands it here; the native
/// side owns everything drawn into it.
@interface GOALPadRenderSurface : NSObject

@property(class, nonatomic, readonly) GOALPadRenderSurface *shared;

/// Attach or detach the layer the game presents into. Detaching releases the surface's Metal
/// resources, so a backgrounded app holds no drawables.
- (void)attachLayer:(nullable CAMetalLayer *)layer;

/// The size of the layer's drawables, in pixels.
- (void)setDrawableSize:(CGSize)size;

/// The game's internal render target, as a multiple of the PS2's 640x480. Clamped to 1...4.
- (void)setInternalResolutionScale:(int32_t)scale;

- (GOALPadSurfaceGeometry)geometry;

/// Arm the surface immediately before the GOAL frame so its DMA send can render synchronously.
- (BOOL)beginFrameAtTime:(CFTimeInterval)presentationTime NS_SWIFT_NAME(beginFrame(at:));

/// Close the armed frame and report whether its DMA chain scheduled a drawable.
- (BOOL)endFrame;
/// NO until the Metal renderer has been started, in which case frame arming draws nothing.
@property(nonatomic, readonly, getter=isRendererLinked) BOOL rendererLinked;

@property(nonatomic, readonly) GOALPadRendererStats stats;
/// The levels the game last asked for, and every level whose art has been read, joined with '+'.
@property(nonatomic, readonly) NSString *levelsWanted;
@property(nonatomic, readonly) NSString *levelsLoaded;
/// The last Metal failure, or "" if there has been none.
@property(nonatomic, readonly) NSString *lastError;

@end

NS_ASSUME_NONNULL_END
