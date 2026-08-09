# visionOS Bounded Stereo Implementation Manual

Maintainer guide for Eco's first playable visionOS presentation slice. This contract is narrower
than the earlier five-mode exploration and takes priority over those retired experiments.

## Product boundary

Eco presents Jak 1 as a floating stereoscopic television inside the app's ordinary Shared Space
window. Other apps and windows remain available. The product declares one `WindowGroup`; it does
not create an immersive scene, request world data, query viewer pose, or drive Jak's camera from
device motion.

Only two gameplay presentation modes exist in this slice:

| Mode | Behavior | Status |
| --- | --- | --- |
| Comfort / Normal | Existing monoscopic `CAMetalLayer` window. | Implemented fallback. |
| Stereoscopic 3D | Two RealityKit-backed views derived from Jak's existing third-person camera. | Experimental until physical Vision Pro acceptance. |

Tabletop, volume, room-scale, and first-person presentation are separate future projects. Do not
add their scene types, permissions, tracking providers, controller profiles, or placeholder UI to
this target.

## Frame contract

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
one copied DMA chain while live Merc side data remains valid
        |
        +-------------------------+
        |                         |
        v                         v
borrowed left color/depth    borrowed right color/depth
fixed left clip transform    fixed right clip transform
        |                         |
        +------------+------------+
                     v
       wait for both native submissions
                     |
                     v
       present both RealityKit drawables
```

The two views must never call `GOALPadRuntimeBridge.runFrame` independently. Texture uploads,
callbacks, stats, save hooks, rumble, and runtime state remain single-shot. Borrowed targets must
remain alive until both native submissions complete.

If target validation, encoding, or completion fails, present neither eye and return immediately to
Comfort without destroying the loaded session.

## Fixed game-camera stereo pair

Jak's authored third-person camera remains the only camera. The bounded-window adapter applies a
small symmetric post-projection shear to that one game-camera clip transform:

```text
left  = game clip with -separation / 2 at Metal far depth
right = game clip with +separation / 2 at Metal far depth
```

The Metal depth-zero plane is the convergence plane. The pair has no vertical disparity and is
deterministic for identical game-camera input. Keep the initial separation conservative; changing
it requires a deliberate physical comfort review.

Do not make the pair depend on window position, window size in meters, the wearer's pose, or a
guessed physical eye distance. Those inputs would change this fixed-camera television into a
different spatial product.

## Renderer coverage

The native renderer validates two distinct color/depth targets and two distinct finite transforms
before mutating frame state. TFRAG, TIE, ETIE, shrub, and Merc currently consume the per-view clip
transform.

Direct, sprite/HUD, sky, ocean, generic, and shadow alpha paths remain monoscopic until separately
classified and implemented. Keep that limitation explicit. A successful build is not proof that
all effects have correct stereo depth.

## Input and app-owned UI

visionOS gameplay accepts ordinary `GCExtendedGamepad` input through Eco's existing Game Controller
path. It does not merge touch, keyboard, mouse, spatial accessory, or tracked-controller state.

Do not create touch sticks, swipe regions, Pause/Stats/Zoom pills, face buttons, touch-guide sheets,
contextual touch prompts, or invisible touch hit regions on visionOS. Preserve the iOS touch path
exactly behind `#if os(iOS)`.

The sole app-owned gameplay overlay is a noninteractive top ornament with the exact text:

```text
No controller detected.
```

It uses one readable full-label purple gradient with a moving highlight. Reduce Motion keeps the
full label static purple. It hides when a supported gamepad connects and returns when the gamepad
disconnects. Developer diagnostics must not appear over visionOS gameplay. Jak-authored HUD and
menus are game content, not app-owned overlays.

## Shared Space surface

`VisionWindowStereoSurfaceView` owns a bounded `RealityView` plane and two
`TextureResource.DrawableQueue` instances. Each frame borrows one BGRA8 color drawable and one
private `depth32Float_stencil8` texture per view. The ShaderGraph material selects the appropriate
left or right texture using RealityKit's camera index.

The surface remains inside the normal `WindowGroup`. It must not declare a second scene or require
a privacy usage string, special entitlement, full-space transition, or surroundings access.

## Validation gates

Before integration:

1. Run the fixed-pair deterministic check.
2. Run the source contract that rejects spatial-scene and tracking APIs, touch UI, and visionOS
   gameplay diagnostics.
3. Typecheck the Swift window/coordinator/surface sources against the xros SDK.
4. Syntax-check the Objective-C++ bridge against the xros SDK.
5. Compile the RealityKit ShaderGraph material and current OpenGOAL Metal shaders.
6. Build the real Xcode target for a generic visionOS destination.

Record simulator and generic-device builds as build evidence only. Physical Vision Pro acceptance
must separately prove visible stereo depth, correct eye assignment, Comfort fallback, ordinary
gamepad connect/disconnect behavior, sustained frame pacing, and the still-monoscopic effect policy.

Do not install, launch, log, or capture a physical headset without request-specific maintainer
authorization.
