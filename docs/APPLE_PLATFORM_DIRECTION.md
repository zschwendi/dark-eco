# Apple Platform and Spatial Rendering Direction

## Purpose

The first implementation target is native ARM64 iPadOS. The architecture should, however, remain capable of supporting iPhone, macOS, and visionOS without replacing the OpenGOAL runtime or rebuilding the game port separately for each platform.

This document describes long-term direction. It does not expand the current milestone or authorize speculative refactoring.

## Immediate priority

The current priority is:

Boot and run the existing OpenGOAL implementation of Jak 1 natively on iPadOS using legally supplied local game data.

Future-platform preparation must not delay this milestone.

Do not build visionOS features, stereo rendering, volumetric presentation, room integration, or extensive cross-platform abstractions until the core game is running reliably on iPadOS.

## Intended Apple platform progression

The anticipated progression is:

1. iPadOS native gameplay
2. iPhone support using the shared Apple runtime
3. Apple Silicon macOS support
4. visionOS conventional window support
5. visionOS volumetric diorama presentation
6. visionOS immersive third-person or overhead presentation
7. Optional spatial environment effects driven by current game state

Each stage should reuse the same game simulation, asset pipeline, and OpenGOAL-derived runtime.

## Core architectural principle

The game runtime must not become inseparably coupled to one Apple presentation surface.

The preferred conceptual separation is:

```text
OpenGOAL game simulation
        ↓
Game state and gameplay camera
        ↓
Portable rendering interface
        ↓
Apple graphics backend
        ↓
Platform presentation
  ├─ iPad window
  ├─ iPhone window
  ├─ macOS window
  ├─ visionOS window
  ├─ visionOS volume
  └─ visionOS immersive space
```

This separation may be introduced incrementally. It should not be implemented as a large speculative rewrite.

## Simulation and rendering

Game simulation should not depend directly on:

* a specific UIKit view
* one fixed display size
* one CAMetalLayer
* one platform lifecycle
* a single render target
* one assumed view or projection matrix
* one assumed display refresh rate

Platform-specific code may own these objects, but the game runtime should receive only the information it needs through narrow boundaries.

The long-term rendering interface should be capable of accepting one or more render views.

A conceptual interface might resemble:

```cpp
struct RenderView {
    Matrix4x4 viewMatrix;
    Matrix4x4 projectionMatrix;
    RenderTarget target;
    Viewport viewport;
};
void updateGame(const GameInput& input, double deltaTime);
void renderGame(std::span<const RenderView> views);
```

This example is directional, not a required immediate implementation.

A conventional iPad build may initially submit one render view. A future immersive visionOS build may submit separate left-eye and right-eye views.

## Gameplay camera and viewer camera

The original game camera may affect:

* gameplay
* targeting
* cutscenes
* streaming
* visibility
* LOD selection
* particle behavior
* scripted events

Future spatial modes may require a separate viewer camera based on head pose or a user-controlled tabletop perspective.

The architecture should therefore avoid unnecessarily treating the final display camera as identical to the gameplay camera.

Do not attempt to separate all camera behavior during the initial iPad port. Preserve opportunities for this distinction and document hard dependencies discovered during porting.

## Platform boundaries

Where practical, platform-specific services should remain behind narrow interfaces:

* graphics device and presentation surface
* application lifecycle
* controller, keyboard, touch, and spatial input
* audio output
* filesystem and security-scoped file access
* timing and display refresh
* threading primitives
* logging
* save-data location
* game-data import and verification

Swift and SwiftUI are preferred for Apple application integration. Existing OpenGOAL C++, GOAL, compiler, runtime, and game logic should remain intact unless a replacement has a documented technical justification.

## Renderer direction

The initial iPad implementation should prioritize correct native output and gameplay.

Future visionOS modes may require:

* externally supplied view and projection matrices
* multiple simultaneous views
* stereo rendering
* head-pose-driven presentation
* render targets not backed by a conventional window
* separation of culling from final viewer pose
* spatial HUD and menu presentation
* stable high-refresh-rate frame pacing

Do not implement these prematurely. Avoid new assumptions that would make them impossible without replacing the renderer.

## Envisioned visionOS modes

### Conventional window

The game renders normally into a visionOS window and uses standard controller input.

This is the simplest compatibility target.

### Volumetric diorama

A section of the level appears as a scaled three-dimensional scene inside a visionOS volume. The user may physically lean or move around the scene while gameplay continues.

This likely requires separating gameplay-camera behavior from the final viewer perspective.

### Immersive third-person or overhead mode

The game renders stereoscopically in an immersive space. The user may view Jak from behind, above, or from a configurable world scale.

This requires proper stereo rendering, head tracking, comfort-aware camera behavior, spatial UI, and visionOS frame scheduling.

### Game-driven spatial environment

The surrounding spatial presentation may react to the current game area using:

* lighting
* sky or backdrop treatment
* fog
* ambient particles
* environmental audio
* level palette
* selected world objects

This should initially be driven by known game state rather than requiring unrestricted access to camera imagery or the user’s physical environment.

## Anti-goals

Do not:

* delay the working iPad port for future visionOS features
* rewrite OpenGOAL wholesale to achieve architectural purity
* build a second game simulation for spatial modes
* make UIKit, SwiftUI, RealityKit, or visionOS APIs part of core game logic
* hard-code the entire engine around one display surface
* assume stereo rendering can be added by merely duplicating the final framebuffer
* refactor stable subsystems without a current requirement
* introduce abstract interfaces with no concrete consumer or test

## Decision rule

When implementing the current iPad port:

1. Choose the smallest change that advances real game execution.
2. Preserve upstream OpenGOAL behavior.
3. Avoid obvious permanent coupling to one Apple device when the alternative is equally simple.
4. Record future architectural work instead of implementing it prematurely.
5. Keep every meaningful commit buildable.

The project is iPad-first, but it is not intended to remain iPad-only.

Preserve the direction in `docs/APPLE_PLATFORM_DIRECTION.md`, but never delay the current playable iPadOS milestone for speculative multi-platform or visionOS architecture.
