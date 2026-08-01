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

/// Whether the engine's own `play` ran: the level heaps and the title level's load.
@property(nonatomic, readonly, getter=didPlay) BOOL played;
@property(nonatomic, readonly) NSTimeInterval duration;

@end

/// What the frames' DMA chains carried. Nothing is drawn until the Metal renderer is linked; this
/// measures what a frame handed `__send-gfx-dma-chain`, which is what says whether it drew.
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

/// Run one frame of the game: `kernel-dispatcher`, then the overlord's vblank work. NO when the
/// game is not booted. Call from one thread only.
+ (BOOL)runFrame;

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

/// Render and present one frame. NO when there is no layer, no device, or no drawable.
- (BOOL)renderFrame;

@property(nonatomic, readonly) uint64_t framesPresented;
/// NO while the real Metal renderer is not part of this build, in which case `renderFrame`
/// presents a placeholder that exercises the surface and the letterbox geometry only.
@property(nonatomic, readonly, getter=isRendererLinked) BOOL rendererLinked;
/// The last Metal failure, or "" if there has been none.
@property(nonatomic, readonly) NSString *lastError;

@end

NS_ASSUME_NONNULL_END
