# visionOS Bounded Stereo Implementation Manual

Maintainer guide for Dark Eco's deferred bounded-stereo implementation. This contract is narrower
than the earlier five-mode exploration and takes priority over those retired experiments.

## Shipping boundary

Dark Eco ships Jak 1 in the conventional Comfort/2D window inside Shared Space. Other apps and
windows remain available. The product declares one `WindowGroup`; it does not create an immersive
scene, request world data, query viewer pose, or drive Jak's camera from device motion.

The rejected bounded-stereo experiment remains in source for later development, but every normal
build compiles its UI and launch wiring out. Only an explicit
`GOALPAD_EXPERIMENTAL_VISION_STEREO` development build can reconnect the dormant coordinator and
RealityKit surface.

| Mode | Behavior | Status |
| --- | --- | --- |
| Comfort / Normal | Existing monoscopic `CAMetalLayer` window. | Implemented shipping path. |
| Stereoscopic 3D | Retained two-view RealityKit experiment. | Deferred; development-only opt-in. |

Tabletop, volume, room-scale, and first-person presentation are separate future projects. Do not
add their scene types, permissions, tracking providers, controller profiles, or placeholder UI to
this target.

## Dormant stereo frame contract

The synchronous bounded stereo path is:

```text
ordinary extended gamepad
        |
        v
one GameSession tick
        |
        v
one GOAL simulation frame
        |
        v
one call-scoped live DMA chain while Merc side data remains valid
        |
        +-------------------------+
        |                         |
        v                         v
borrowed left color/depth    borrowed right color/depth
fixed left clip transform    fixed right clip transform
        |                         |
        +------------+------------+
                     v
       encode both eyes in one command buffer
                     |
                     v
       publish both LowLevelTextures together
```

The two views must never call `GOALPadRuntimeBridge.runFrame` independently. Texture uploads,
callbacks, stats, save hooks, rumble, and runtime state remain single-shot. Borrowed targets must
remain alive until both native submissions complete.

If target validation, encoding, or completion fails, present neither eye and return immediately to
Comfort without destroying the loaded session.

## Existing fixed game-camera stereo pair

Jak's authored third-person camera remains the only camera. The bounded-window adapter applies a
small symmetric post-projection shear to that one game-camera clip transform:

```text
left  = game clip with -separation / 2 at Metal far depth
right = game clip with +separation / 2 at Metal far depth
```

The Metal depth-zero plane is the convergence plane. The pair has no vertical disparity and is
deterministic for identical game-camera input. Keep the initial separation conservative; changing
it requires a deliberate physical comfort review.

The retained experiment does not depend on window position, physical size, or viewer pose. Do not
change that implementation while stereo is deferred.

## Planned dynamic stereo continuation

**Planned:** a later stereo project should replace the fixed strength with a physical-window-width
calculation. Let `B = 0.063 m` be the assumed interpupillary baseline, `W` the physical window width,
and `P` its pixel width. Infer a nominal viewer distance `V` from the current nominal field of view
and `W`, then clamp `V` to `1.0 ... 1.5 m`. For Jak's reversed-Z projection, choose convergence
`c = d(V)` and begin physical comfort testing with:

```text
S = 2B / W
delta NDC      = S * (d - c)
delta physical = W * delta NDC / 2 = B * (d - c)
delta pixels   = P * delta NDC / 2 = P * B * (d - c) / W
```

At `W = 0.20 m`, `S` is approximately `0.63`; the proposed comfort target was described as roughly
`0.63` to `0.65`. These values are starting points, not implemented or accepted calibration.
Physically confirm which diagnostic marker reaches each eye before changing or locking the
eye-transform sign.

A true near-disparity cap is piecewise and cannot be expressed by the current single projection
matrix alone. It requires one shared clamp in every world-space shader path so geometry cannot
disagree between renderers. The cap must be no greater than one assumed IPD on the physical window,
must be physically comfort-tested, and should start fractionally below that maximum. Windowed
stereo remains based on Jak's authored camera and physical window dimensions; it must not add head
tracking, viewer-pose camera motion, world tracking, or an immersive scene.

## Renderer coverage

The native renderer validates two distinct color/depth targets and two distinct finite transforms
before mutating frame state. TFRAG, TIE, ETIE, shrub, and Merc currently consume the per-view clip
transform.

Direct, sprite/HUD, sky, ocean, generic, and shadow alpha paths remain monoscopic until separately
classified and implemented. Keep that limitation explicit. A successful build is not proof that
all effects have correct stereo depth.

## Input and app-owned UI

visionOS gameplay accepts ordinary `GCExtendedGamepad` input through Dark Eco's existing Game
Controller path. It does not merge touch, keyboard, mouse, spatial accessory, or tracked-controller
state.

Do not create touch sticks, swipe regions, Pause/Stats/Zoom pills, face buttons, touch-guide sheets,
contextual touch prompts, or invisible touch hit regions on visionOS. Preserve the iOS touch path
exactly behind `#if os(iOS)`.

The noninteractive controller-status ornament retains the exact text:

```text
No controller detected.
```

It uses one readable full-label purple gradient with a moving highlight. Reduce Motion keeps the
full label static purple. It hides when a supported gamepad connects and returns when the gamepad
disconnects. A separate accessible Dark Eco Settings ornament is available at all times. It is
top-center only when a controller is connected and the existing native settings gate is active;
otherwise it is top-leading, including gameplay, launcher, boot, and every no-controller state.
Neither ornament adds a gameplay touch region. Developer diagnostics must not appear over visionOS
gameplay. Jak-authored HUD and menus are game content, not app-owned overlays.

## Shared Space surface

When explicitly compiled in, `VisionWindowStereoSurfaceView` owns a bounded `RealityView` plane and
two stable `LowLevelTexture` resources. Each frame replaces both BGRA8 color textures through one
command buffer and uses one private `depth32Float_stencil8` texture per view. The ShaderGraph
material selects the appropriate left or right texture using RealityKit's camera index.

The surface remains inside the normal `WindowGroup`. It must not declare a second scene or require
a privacy usage string, special entitlement, full-space transition, or surroundings access.

## Validation gates

Before any later stereo integration:

1. Run the fixed-pair deterministic check.
2. Run the source contract that rejects spatial-scene and tracking APIs, touch UI, and visionOS
   gameplay diagnostics.
3. Typecheck the Swift window/coordinator/surface sources against the xros SDK.
4. Syntax-check the Objective-C++ bridge against the xros SDK.
5. Compile the RealityKit ShaderGraph material and current OpenGOAL Metal shaders.
6. Build the real Xcode target for a generic visionOS destination.

Normal release validation must first prove that only Comfort/2D is reachable. Experimental
simulator and generic-device builds are build evidence only. Any later physical Vision Pro stereo
candidate must separately prove stable presentation, visible depth, correct eye assignment,
near-disparity safety, ordinary gamepad connect/disconnect behavior, and sustained frame pacing.

Do not install, launch, log, or capture a physical headset without request-specific maintainer
authorization.
