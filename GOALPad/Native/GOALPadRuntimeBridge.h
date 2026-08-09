#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <simd/simd.h>

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

typedef NS_ENUM(NSInteger, GOALPadStereoFrameCompletion) {
  GOALPadStereoFrameCompletionSkipped = 0,
  GOALPadStereoFrameCompletionCompleted = 1,
  GOALPadStereoFrameCompletionFailed = 2,
};

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

typedef NS_ENUM(NSInteger, GOALPadGameMode) {
  GOALPadGameModeUnknown,
  GOALPadGameModeGameplay,
  GOALPadGameModePause,
  GOALPadGameModeProgress,
  GOALPadGameModeMenu,
};

typedef NS_ENUM(NSInteger, GOALPadTitleStartState) {
  GOALPadTitleStartStateUnknown,
  GOALPadTitleStartStateNotAwaiting,
  GOALPadTitleStartStateAwaiting,
  GOALPadTitleStartStateTitleSequence,
};

typedef NS_ENUM(NSInteger, GOALPadLookAroundState) {
  GOALPadLookAroundStateUnknown,
  GOALPadLookAroundStateNormal,
  GOALPadLookAroundStateFirstPerson,
};

typedef NS_ENUM(NSInteger, GOALPadSpeederState) {
  GOALPadSpeederStateUnknown,
  GOALPadSpeederStateNotRiding,
  GOALPadSpeederStateRiding,
};

typedef NS_ENUM(NSInteger, GOALPadProgressScreen) {
  GOALPadProgressScreenUnknown = -2,
  GOALPadProgressScreenInvalid = -1,
  GOALPadProgressScreenFuelCells = 0,
  GOALPadProgressScreenPrecursorOrbs = 1,
  GOALPadProgressScreenScoutFlies = 2,
  GOALPadProgressScreenSettings = 3,
  GOALPadProgressScreenGameSettings = 4,
  GOALPadProgressScreenGraphicSettings = 5,
  GOALPadProgressScreenSoundSettings = 6,
  GOALPadProgressScreenMemoryCardNoSpace = 7,
  GOALPadProgressScreenMemoryCardNotInserted = 8,
  GOALPadProgressScreenMemoryCardNotFormatted = 9,
  GOALPadProgressScreenMemoryCardFormat = 10,
  GOALPadProgressScreenMemoryCardDataExists = 11,
  GOALPadProgressScreenLoading = 12,
  GOALPadProgressScreenSaving = 13,
  GOALPadProgressScreenFormatting = 14,
  GOALPadProgressScreenCreating = 15,
  GOALPadProgressScreenLoadGame = 16,
  GOALPadProgressScreenSaveGame = 17,
  GOALPadProgressScreenSaveGameTitle = 18,
  GOALPadProgressScreenInsert = 19,
  GOALPadProgressScreenErrorLoading = 20,
  GOALPadProgressScreenErrorSaving = 21,
  GOALPadProgressScreenRemoved = 22,
  GOALPadProgressScreenNoData = 23,
  GOALPadProgressScreenErrorFormatting = 24,
  GOALPadProgressScreenErrorCreating = 25,
  GOALPadProgressScreenAutoSaveError = 26,
  GOALPadProgressScreenTitle = 27,
  GOALPadProgressScreenSettingsTitle = 28,
  GOALPadProgressScreenAutoSave = 29,
  GOALPadProgressScreenPalChange = 30,
  GOALPadProgressScreenPalNow = 31,
  GOALPadProgressScreenNoDisc = 32,
  GOALPadProgressScreenBadDisc = 33,
  GOALPadProgressScreenQuit = 34,
};

typedef struct GOALPadProgressMenuSnapshot {
  BOOL available;
  GOALPadProgressScreen screen;
  int32_t optionIndex;
  BOOL selectedOption;
  BOOL inTransition;
  BOOL navigationAvailable;
  GOALPadProgressScreen startingScreen;
  BOOL canExitWithStart;
  BOOL canGoBack;
} GOALPadProgressMenuSnapshot;

typedef NS_ENUM(NSInteger, GOALPadWarpGateTouchState) {
  GOALPadWarpGateTouchStateUnavailable = 0,
  GOALPadWarpGateTouchStateCircleUseAvailable = 1,
  GOALPadWarpGateTouchStateDestinationListActive = 2,
  GOALPadWarpGateTouchStateTransitioning = 3,
};

typedef struct GOALPadWarpGateTouchSnapshot {
  /// YES means the GOAL object and its seqlock-protected payload passed every contract check.
  BOOL valid;
  /// Stable even generation; changes for every semantic publication.
  uint32_t sequence;
  GOALPadWarpGateTouchState state;
  int32_t selectedSlot;
  uint32_t permittedMask;
  BOOL selectionMoving;
} GOALPadWarpGateTouchSnapshot;

typedef NS_ENUM(NSInteger, GOALPadCutsceneSkipTouchState) {
  GOALPadCutsceneSkipTouchStateUnavailable = 0,
  GOALPadCutsceneSkipTouchStateTriangleQueryAvailable = 1,
  GOALPadCutsceneSkipTouchStateCreditsTriangleAvailable = 2,
};

typedef struct GOALPadCutsceneSkipTouchSnapshot {
  /// YES means the GOAL object, revision, seqlock, owner, state, and heartbeat are current.
  BOOL valid;
  /// Stable even owner/state generation. Heartbeats do not change this value.
  uint32_t sequence;
  GOALPadCutsceneSkipTouchState state;
} GOALPadCutsceneSkipTouchSnapshot;

typedef struct GOALPadFacePromptTouchSnapshot {
  /// YES only after the same GOAL owner and requested mask publish a fresh later-frame heartbeat.
  BOOL valid;
  /// Ordinary Jak 1 pad bits: Triangle 12, Circle 13, Cross 14, and Square 15.
  uint32_t requestedButtons;
  /// Stable even semantic generation. Heartbeats do not change this value.
  uint32_t sequence;
} GOALPadFacePromptTouchSnapshot;

/// The whole Swift-facing surface of the native runtime. The GOAL kernel is a process-wide
/// singleton, so this is a class API rather than an instantiable object.
@interface GOALPadRuntimeBridge : NSObject

/// Bring the kernel up, pointed at the player's own prepared data. All-or-nothing: if the returned
/// status is not `running`, nothing is live and `message` says why. `dataDirectory` is the
/// directory that holds `iso/` and `fr3/`; pass nil to start without game data. `savesDirectory`
/// is the canonical local OpenGOAL save root and must not be empty.
+ (GOALPadKernelStatus *)startKernelWithDataDirectory:(nullable NSString *)dataDirectory
                                      savesDirectory:(NSString *)savesDirectory;

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
/// Jak's own `*master-mode*`; reading it never advances or mutates gameplay.
@property(class, nonatomic, readonly) GOALPadGameMode gameMode;
/// Exact read of whether Jak's live target is waiting at, traversing, or outside the title flow.
@property(class, nonatomic, readonly) GOALPadTitleStartState titleStartState;
/// Jak's live directional look-around state. Unavailable and other first-person modes are unknown.
@property(class, nonatomic, readonly) GOALPadLookAroundState lookAroundState;
/// Exact checked target-state classification; unresolved level-bundled racer states stay unknown.
@property(class, nonatomic, readonly) GOALPadSpeederState speederState;
/// A fail-closed read of Jak's live progress process; reading it never advances or mutates GOAL.
@property(class, nonatomic, readonly) GOALPadProgressMenuSnapshot progressMenuSnapshot;
/// GOAL-owned warp-gate touch semantics. Invalid and valid-unavailable snapshots are distinct.
@property(class, nonatomic, readonly) GOALPadWarpGateTouchSnapshot warpGateTouchSnapshot;
/// GOAL-owned, fail-closed Triangle-query availability for explicitly skippable animations only.
@property(class, nonatomic, readonly) GOALPadCutsceneSkipTouchSnapshot cutsceneSkipTouchSnapshot;
/// GOAL-owned contextual face-button requests; first, malformed, and stale reads fail closed.
@property(class, nonatomic, readonly) GOALPadFacePromptTouchSnapshot facePromptTouchSnapshot;
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

/// One borrowed RealityKit-owned view target for the synchronous visionOS stereo tick.
@interface GOALPadStereoRenderTarget : NSObject

- (instancetype)initWithViewID:(uint64_t)viewID
                  colorTexture:(id<MTLTexture>)colorTexture
                  depthTexture:(id<MTLTexture>)depthTexture
              clipFromGameClip:(simd_float4x4)clipFromGameClip
    NS_SWIFT_NAME(init(viewID:colorTexture:depthTexture:clipFromGameClip:));

@property(nonatomic, readonly) uint64_t viewID;
@property(nonatomic, readonly) id<MTLTexture> colorTexture;
@property(nonatomic, readonly) id<MTLTexture> depthTexture;
/// Column-major transform from the game's final Metal clip coordinates into this view.
@property(nonatomic, readonly) simd_float4x4 clipFromGameClip;

@end

/// Numeric evidence retained for one consecutive-frame eichar-lod0 transform discontinuity.
/// Issue bits identify: 0 uniform-scale jump, 1 per-axis shape jump, 2 input-root A/B/A,
/// 3 output-only A/B/A, 4 camera-driven A/B/A, 5 changed input with stale output, and
/// 6 a source mapping or producer-to-renderer output identity mismatch, and
/// 7 an expected-output mismatch.
typedef struct GOALPadMercTransformEvent {
  uint64_t hostTickID;
  uint64_t chainOrdinal;
  uint8_t issueMask;
  int32_t boneSlot;
  uint64_t modelNameHash;
  uint64_t olderFrameID;
  uint64_t previousFrameID;
  uint64_t currentFrameID;
  uint64_t olderMatrixHash;
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
  uint64_t olderSourceBase;
  uint64_t previousSourceBase;
  uint64_t currentSourceBase;
  int32_t inputRootBone;
  uint64_t olderProducerSerial;
  uint64_t previousProducerSerial;
  uint64_t currentProducerSerial;
  uint64_t previousProducerOutputHash;
  uint64_t currentProducerOutputHash;
  uint64_t previousRendererOutputHash;
  uint64_t currentRendererOutputHash;
  uint64_t olderInputRootHash;
  uint64_t previousInputRootHash;
  uint64_t currentInputRootHash;
  uint64_t olderCameraHash;
  uint64_t previousCameraHash;
  uint64_t currentCameraHash;
  uint64_t previousBindPoseHash;
  uint64_t currentBindPoseHash;
  double inputOlderToPreviousDistance;
  double inputPreviousToCurrentDistance;
  double inputOlderToCurrentDistance;
  double outputOlderToPreviousDistance;
  double outputPreviousToCurrentDistance;
  double outputOlderToCurrentDistance;
  double previousOutputExpectedDistance;
  double currentOutputExpectedDistance;
  double cameraOlderToPreviousDistance;
  double cameraPreviousToCurrentDistance;
  double cameraOlderToCurrentDistance;
  double previousInputTranslationX;
  double previousInputTranslationY;
  double previousInputTranslationZ;
  double currentInputTranslationX;
  double currentInputTranslationY;
  double currentInputTranslationZ;
} GOALPadMercTransformEvent;

/// Numeric evidence retained for one unhealthy eichar-lod0 palette matrix.
typedef struct GOALPadMercPaletteHealthEvent {
  uint64_t engineFrameID;
  uint64_t hostTickID;
  uint64_t chainOrdinal;
  uint8_t issueMask;
  uint32_t nonfiniteLaneMask;
  int32_t boneSlot;
  uint64_t modelNameHash;
  uint64_t matrixHash;
  double axisNormX;
  double axisNormY;
  double axisNormZ;
  double normalizedAbsDeterminant;
  uint32_t sourceAddress;
  uint64_t sourceBase;
  uint64_t expectedSourceBase;
} GOALPadMercPaletteHealthEvent;

/// One copied GOAL vector in a constrained-camera event. These are numeric values, never live
/// pointers into the GOAL heap.
typedef struct GOALPadCameraCorrectionVector {
  double x;
  double y;
  double z;
  double w;
} GOALPadCameraCorrectionVector;

typedef struct GOALPadCameraCorrectionRotationAxes {
  GOALPadCameraCorrectionVector axis0;
  GOALPadCameraCorrectionVector axis1;
  GOALPadCameraCorrectionVector axis2;
} GOALPadCameraCorrectionRotationAxes;

typedef struct GOALPadCameraCorrectionSlaveFrame {
  BOOL valid;
  uint32_t options;
  uint32_t losState;
  uint32_t stringVelocityDirection;
  BOOL lineOfSightEnabled;
  BOOL movementBlocked;
  double minimumDistanceOverride;
  double maxAngleOffset;
  double maxAngleCurrent;
  GOALPadCameraCorrectionVector transform;
  GOALPadCameraCorrectionRotationAxes trackingInverseMatrix;
  GOALPadCameraCorrectionVector viewFlat;
  GOALPadCameraCorrectionVector stringTransform;
  GOALPadCameraCorrectionVector desiredPosition;
} GOALPadCameraCorrectionSlaveFrame;

typedef struct GOALPadCameraCorrectionFrame {
  BOOL valid;
  uint64_t engineFrameID;
  uint32_t mathCameraObjectOffset;
  uint32_t mathCameraTypeOffset;
  uint32_t masterObjectOffset;
  uint32_t masterTypeOffset;
  uint32_t combinerObjectOffset;
  uint32_t combinerTypeOffset;
  uint32_t slave0PpointerOffset;
  uint32_t slave0ObjectOffset;
  uint32_t slave0TypeOffset;
  uint32_t slave1PpointerOffset;
  uint32_t slave1ObjectOffset;
  uint32_t slave1TypeOffset;
  double displayTimeRatio;
  int32_t numSlaves;
  BOOL beingAttacked;
  GOALPadCameraCorrectionVector targetPosition;
  GOALPadCameraCorrectionVector adjustedTargetPosition;
  GOALPadCameraCorrectionSlaveFrame slave0;
  GOALPadCameraCorrectionSlaveFrame slave1;
  BOOL combinerValid;
  double combinerInterpolation;
  uint64_t combinerTrackingStatus;
  GOALPadCameraCorrectionVector combinerTransform;
  GOALPadCameraCorrectionRotationAxes combinerInverseCameraRotation;
} GOALPadCameraCorrectionFrame;

/// A bounded three-frame constrained-camera sample. Reason bit 0 is a LOS state transition; bit
/// 1 is the existing producer A/B/A observation; bit 2 is a combined-camera orientation delta
/// over thirty degrees between consecutive engine frames; bit 3 is a full render-camera A/B/A.
typedef struct GOALPadCameraCorrectionEvent {
  BOOL valid;
  uint8_t reasonMask;
  uint64_t hostTickID;
  uint64_t chainOrdinal;
  GOALPadCameraCorrectionFrame older;
  GOALPadCameraCorrectionFrame previous;
  GOALPadCameraCorrectionFrame current;
} GOALPadCameraCorrectionEvent;

/// Summary for a compact temporal sample beginning one frame before a validated camera-rotation
/// delta of at least five degrees. A complete sample includes sixteen post-trigger frames.
typedef struct GOALPadCameraCorrectionTailInfo {
  BOOL valid;
  BOOL complete;
  uint32_t frameCount;
  uint64_t triggerEngineFrameID;
  double triggerOrientationDegrees;
} GOALPadCameraCorrectionTailInfo;

typedef struct GOALPadCameraCorrectionTailFrame {
  BOOL valid;
  uint64_t hostTickID;
  uint64_t chainOrdinal;
  uint64_t renderCameraFingerprint;
  GOALPadCameraCorrectionFrame camera;
} GOALPadCameraCorrectionTailFrame;

/// One coherent native camera-tail copy. Reading its frames never re-copies or races a newer tail.
@interface GOALPadCameraCorrectionTailSnapshot : NSObject {
 @private
  void *_nativeTail;
}
@property(nonatomic, readonly) GOALPadCameraCorrectionTailInfo info;
- (GOALPadCameraCorrectionTailFrame)frameAtIndex:(uint32_t)index
    NS_SWIFT_NAME(frame(at:));
@end

/// Numeric evidence for one eichar-lod0 target/control disagreement or attack edge.
/// Issue bit 0 is a facing divergence and bit 1 is an attack boundary.
typedef struct GOALPadTargetControlEvent {
  uint64_t hostTickID;
  uint64_t chainOrdinal;
  uint8_t issueMask;
  uint64_t engineFrameID;
  uint64_t producerSerial;
  uint32_t sourceBase;
  uint32_t targetStateID;
  uint64_t previousTargetAttackID;
  uint64_t currentTargetAttackID;
  uint32_t button0Abs;
  uint32_t button0Rel;
  uint8_t leftX;
  uint8_t leftY;
  double stickDirection;
  double stickSpeed;
  double padMagnitude;
  double intentForwardX;
  double intentForwardZ;
  double desiredForwardX;
  double desiredForwardZ;
  double controlForwardX;
  double controlForwardZ;
  double renderForwardX;
  double renderForwardZ;
  double rootForwardX;
  double rootForwardZ;
  double intentControlDot;
  double controlRenderDot;
  double renderRootDot;
} GOALPadTargetControlEvent;

typedef struct GOALPadTargetControlVector4 {
  double x;
  double y;
  double z;
  double w;
} GOALPadTargetControlVector4;

typedef struct GOALPadTargetControlFacing {
  BOOL valid;
  double x;
  double z;
} GOALPadTargetControlFacing;

typedef struct GOALPadTargetControlBasis {
  BOOL valid;
  double axis0X;
  double axis0Y;
  double axis0Z;
  double axis1X;
  double axis1Y;
  double axis1Z;
  double axis2X;
  double axis2Y;
  double axis2Z;
} GOALPadTargetControlBasis;

typedef struct GOALPadTargetControlDeformation {
  BOOL valid;
  double axisNormX;
  double axisNormY;
  double axisNormZ;
  double aspect;
  double normalizedAbsDeterminant;
} GOALPadTargetControlDeformation;

typedef struct GOALPadTargetControlRootAnchor {
  BOOL valid;
  GOALPadTargetControlDeformation deformation;
  double scaleX;
  double scaleY;
  double scaleZ;
  uint32_t scaleWBits;
} GOALPadTargetControlRootAnchor;

/// The latest ordinary valid target/control sample, even when no issue event was emitted.
typedef struct GOALPadTargetControlObservation {
  BOOL valid;
  uint64_t hostTickID;
  uint64_t chainOrdinal;
  uint64_t engineFrameID;
  int32_t probeBoneSlot;
  uint64_t producerSerial;
  uint32_t sourceBase;
  uint64_t cameraHash;
  uint32_t targetStateID;
  uint64_t targetAttackID;
  uint32_t button0Abs;
  uint32_t button0Rel;
  uint8_t leftX;
  uint8_t leftY;
  double stickDirection;
  double stickSpeed;
  double padMagnitude;
  GOALPadTargetControlVector4 rawDirTarg;
  GOALPadTargetControlVector4 rawQuatForControl;
  GOALPadTargetControlVector4 rawRenderQuat;
  GOALPadTargetControlVector4 rawTurnToTarget;
  GOALPadTargetControlFacing intentForward;
  GOALPadTargetControlFacing desiredForward;
  GOALPadTargetControlFacing controlForward;
  GOALPadTargetControlFacing renderForward;
  GOALPadTargetControlFacing rootForward;
  GOALPadTargetControlBasis cameraBasis;
  GOALPadTargetControlDeformation inputRootDeformation;
  GOALPadTargetControlDeformation outputDeformation;
  GOALPadTargetControlRootAnchor rootAnchor1;
  GOALPadTargetControlRootAnchor rootAnchor2;
  GOALPadTargetControlRootAnchor rootAnchor3;
  BOOL node3ParentScaleCancellationSelected;
  double inputRootTranslationX;
  double inputRootTranslationY;
  double inputRootTranslationZ;
} GOALPadTargetControlObservation;

typedef struct GOALPadTargetPostFlagObservation {
  BOOL valid;
  uint64_t hostTickID;
  uint64_t chainOrdinal;
  uint64_t engineFrameID;
  uint64_t sampleSerial;
  uint32_t targetAddress;
  uint32_t rawDrawStatus;
  uint64_t targetAttackID;
  BOOL hidden;
} GOALPadTargetPostFlagObservation;

/// Capture health and latest ordinary target/control evidence. Stage/result are stable numeric
/// values defined by OpenGOAL's `jak1_target_control_capture.h` diagnostic contract.
typedef struct GOALPadTargetControlTelemetry {
  uint64_t captureAttemptsTotal;
  uint64_t validObservationsTotal;
  uint8_t lastCaptureStage;
  uint8_t lastCaptureResult;
  GOALPadTargetControlObservation lastObservation;
  uint64_t postFlagSamplesTotal;
  uint64_t hiddenSamplesTotal;
  uint64_t hiddenTransitionsTotal;
  uint64_t postFlagSerialGapsTotal;
  uint64_t unframedPostFlagSamplesTotal;
  GOALPadTargetPostFlagObservation lastPostFlagSample;
  GOALPadTargetPostFlagObservation lastHiddenPostFlagSample;
} GOALPadTargetControlTelemetry;

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
  uint64_t renderCameraAlternations;
  uint64_t lastRenderCameraAlternationOlderFrameID;
  uint64_t lastRenderCameraAlternationPreviousFrameID;
  uint64_t lastRenderCameraAlternationCurrentFrameID;
  uint64_t lastRenderCameraAlternationOlderFingerprint;
  uint64_t lastRenderCameraAlternationPreviousFingerprint;
  uint64_t lastRenderCameraAlternationCurrentFingerprint;
  uint64_t lastRenderCameraAlternationHostTickID;
  uint64_t lastRenderCameraAlternationChainOrdinal;
  uint64_t lastRenderCameraAlternationPacketFingerprint;
  uint16_t lastRenderCameraAlternationLiveMismatchQwords;
  uint16_t lastRenderCameraAlternationPacketMismatchQwords;
  double lastRenderCameraOlderToPreviousDistance;
  double lastRenderCameraPreviousToCurrentDistance;
  double lastRenderCameraOlderToCurrentDistance;
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
  uint32_t lastMercPaletteHealthNonfiniteLaneMask;
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
  int32_t mercEicharProvenanceEvents;
  uint64_t mercEicharProvenanceEventsTotal;
  GOALPadMercTransformEvent firstMercEicharProvenanceEvent;
  GOALPadMercTransformEvent lastMercEicharProvenanceEvent;
  int32_t mercEicharOutputCompositionMismatches;
  uint64_t mercEicharOutputCompositionMismatchesTotal;
  GOALPadMercTransformEvent firstMercEicharOutputCompositionMismatch;
  GOALPadMercTransformEvent lastMercEicharOutputCompositionMismatch;
  int32_t mercEicharPaletteHealthIssues;
  uint64_t mercEicharPaletteHealthIssuesTotal;
  GOALPadMercPaletteHealthEvent firstMercEicharPaletteHealthEvent;
  GOALPadMercPaletteHealthEvent lastMercEicharPaletteHealthEvent;
  uint64_t mercBadBonePointers;
  uint64_t mercBadDrawRanges;
  uint64_t cameraCorrectionEventsTotal;
  GOALPadCameraCorrectionEvent lastCameraCorrectionEvent;
  int32_t mercEicharTargetControlEvents;
  uint64_t mercEicharTargetControlEventsTotal;
  int32_t mercEicharTargetControlDivergences;
  uint64_t mercEicharTargetControlDivergencesTotal;
  int32_t mercEicharTargetControlAttackBoundaries;
  uint64_t mercEicharTargetControlAttackBoundariesTotal;
  GOALPadTargetControlEvent firstMercEicharTargetControlEvent;
  GOALPadTargetControlEvent lastMercEicharTargetControlEvent;
  BOOL jak1TieEnvmapSecondPassEnabled;
  int32_t tieEnvmapSecondPassDraws;
  uint64_t tieEnvmapSecondPassDrawsTotal;
  uint64_t mercEicharWeightedProfiledBaseDraws;
  uint64_t mercEicharWeightedProfiledVertices;
  uint64_t mercEicharWeightedMultiBoneVertices;
  uint64_t mercEicharWeightedAffectedVertices;
  uint64_t mercEicharWeightedStaticMultiBoneVertices;
  uint64_t mercEicharWeightedStaticAffectedVertices;
  uint64_t mercEicharWeightedModifiedMultiBoneVertices;
  uint64_t mercEicharWeightedModifiedAffectedVertices;
  uint64_t mercEicharWeightedTupleGroups;
  uint64_t mercEicharWeightedAffectedTupleGroups;
  uint64_t mercEicharWeightedValidBasisGroups;
  uint64_t mercEicharWeightedInvalidBasisGroups;
  uint64_t mercEicharWeightedAffectedDraws;
  uint64_t mercEicharWeightedAffectedEffects;
  uint64_t mercEicharWeightedProfileTupleMismatches;
  uint64_t mercEicharWeightedProfileCapacityDrops;
  double mercEicharWeightedMaximumAxisRatio;
  double mercEicharWeightedMinimumNormalizedAbsDeterminant;
  uint8_t mercEicharWeightedCoverage;
  uint64_t mercEicharPackets;
  uint64_t mercEicharUniqueSourceBases;
  uint64_t mercEicharRepeatedPackets;
  uint64_t mercEicharRepeatedPacketsSamePalette;
  uint64_t mercEicharRepeatedPacketsConflictingPalette;
  uint64_t mercEicharActualBaseDraws;
  uint64_t mercEicharUniqueBaseDraws;
  uint64_t mercEicharRepeatedBaseDraws;
  uint64_t mercEicharRepeatedBaseDrawsSamePalette;
  uint64_t mercEicharRepeatedBaseDrawsConflictingPalette;
  uint64_t mercEicharTraceCapacityDrops;
  uint64_t mercEicharBoundPaletteHashMismatches;
  uint64_t mercEicharWeightedSkinEvidenceTotal;
  uint8_t mercEicharWeightedIssueMask;
  uint64_t lastMercEicharWeightedSkinEngineFrameID;
  uint64_t lastMercEicharWeightedSkinHostTickID;
  uint64_t lastMercEicharWeightedSkinChainOrdinal;
  BOOL jak1ShadowOutputEnabled;
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

/// Widen the game target and its GOAL camera aspect to the drawable while preserving vertical FOV.
/// Disabled is the exact 4:3 Classic presentation path.
- (void)setHorizontalPlusEnabled:(BOOL)enabled;

- (GOALPadSurfaceGeometry)geometry;

/// Arm the surface immediately before the GOAL frame so its DMA send can render synchronously.
- (BOOL)beginFrameAtTime:(CFTimeInterval)presentationTime NS_SWIFT_NAME(beginFrame(at:));

/// Arm one synchronous game tick against two distinct borrowed RealityKit targets.
- (BOOL)beginStereoFrameAtTime:(CFTimeInterval)presentationTime
                          size:(CGSize)size
                          left:(GOALPadStereoRenderTarget *)left
                         right:(GOALPadStereoRenderTarget *)right
    NS_SWIFT_NAME(beginStereoFrame(at:size:left:right:));

/// Close the armed frame and report whether its DMA chain scheduled a drawable.
- (BOOL)endFrame;
/// Wait for both per-eye command buffers and distinguish an empty tick from a GPU failure.
- (GOALPadStereoFrameCompletion)endStereoFrame;
/// NO until the Metal renderer has been started, in which case frame arming draws nothing.
@property(nonatomic, readonly, getter=isRendererLinked) BOOL rendererLinked;

@property(nonatomic, readonly) GOALPadRendererStats stats;
@property(nonatomic, readonly) GOALPadCameraCorrectionTailInfo cameraCorrectionTailInfo;
@property(nonatomic, readonly) GOALPadCameraCorrectionTailSnapshot *cameraCorrectionTailSnapshot;
@property(nonatomic, readonly) GOALPadTargetControlTelemetry targetControlTelemetry;
/// The levels the game last asked for, and every level whose art has been read, joined with '+'.
@property(nonatomic, readonly) NSString *levelsWanted;
@property(nonatomic, readonly) NSString *levelsLoaded;
/// The last Metal failure, or "" if there has been none.
@property(nonatomic, readonly) NSString *lastError;

@end

NS_ASSUME_NONNULL_END
