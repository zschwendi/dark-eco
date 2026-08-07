# visionOS Presentation Modes Implementation Manual

Maintainer guide for turning Eco's Build 134 visionOS scene foundation into five honest, playable presentation modes without creating a second game engine.

## Scope and audited baseline

This guide was written against:

- GOALPad parent commit `d2d077b9bf4c06e390de2f2ad7166aafbed2c227` (Build 134).
- OpenGOAL submodule commit `597270b0901a9ee19a675efb744e35133a5568d7`.
- The native `GOALPad` Xcode target, including its `xros` and `xrsimulator` destinations.

It covers implementation planning only. It does not claim that stereoscopic game rendering, tabletop rendering, room-scale play, first-person VR, or room-mesh gameplay works today.

### What exists now

| Mode | Build 134 state | Honest product status |
| --- | --- | --- |
| Comfort / Normal | The real game renders through one `CAMetalLayer` in the conventional `WindowGroup`. | Implemented. Preserve this as the reliable fallback. |
| Stereoscopic 3D | A synthetic tetrahedron renders through distinct Compositor Services views, tracked transforms, projections, targets, slices, and reverse depth. The game renderer is not attached. | Experimental renderer proof, not playable stereo. |
| Tabletop / Volume | A volumetric `WindowGroup` displays an unavailable message. | Planned. |
| Room-scale World | A progressive `ImmersiveSpace` displays an unavailable message. | Planned; renderer and anchoring architecture unresolved. |
| First-person VR | A full `ImmersiveSpace` displays an unavailable message. | Investigating; explicit comfort behavior is unresolved. |

The five-mode enum, capability descriptions, coordinator, and scene declarations exist. Modern selects Stereoscopic 3D as its desired mode, but active gameplay correctly remains in Comfort. There is no shipped user-facing mode picker or playable scene transition for modes 2 through 5.

### Important API correction before implementation

The current stereo proof is declared with `.immersionStyle(... .mixed)`, but that modifier alone is not evidence of a mixed passthrough experience. Apple's current [fully immersive Metal guidance](https://developer.apple.com/documentation/compositorservices/drawing-fully-immersive-content-using-metal) says a default space containing `CompositorLayer` is automatically fully immersive and ignores style modifiers. Apple also documents a newer, explicit [progressive Metal immersion path](https://developer.apple.com/documentation/compositorservices/controlling-metal-rendering-immersion-level) that requires layered layout, a drawable render context, and a stencil mask.

Before relying on mixed or progressive custom-Metal behavior, reconcile these documents against the exact Xcode and visionOS deployment SDK in use. Treat Build 134's proof as a full-space synthetic stereo proof until a physical-device run demonstrates otherwise.

## Non-negotiable architecture decisions

1. OpenGOAL remains the only game simulation and authoritative world. SwiftUI and RealityKit own presentation, system UI, gestures, spatial anchoring, and permission flow; they do not become a replacement game engine.
2. Advance the GOAL simulation exactly once per game tick. Two eyes, mirrors, portals, and additional views render the same immutable state; they never call `GOALPadRuntimeBridge.runFrame` independently.
3. Separate the authored gameplay camera from each final viewer camera. Gameplay, streaming, cutscenes, and targeting may continue to use the authored camera while the renderer uses system-provided eye views.
4. Never synthesize eye separation with a guessed interpupillary distance. Use the per-view transform and projection supplied by RealityKit or Compositor Services.
5. Keep Comfort playable throughout the work. Any unavailable mode, denied permission, tracking failure, or scene-opening failure returns to Comfort without losing the loaded game or save state.
6. Use user-supplied, locally prepared game data only. Tests and checked-in fixtures remain synthetic and original.
7. A simulator build is not physical Vision Pro proof. Apple's own [windowed stereo game sample](https://developer.apple.com/documentation/realitykit/rendering-a-windowed-game-in-stereo) requires Apple Vision Pro and does not run in the simulator.

## Repository map

### Existing files to extend deliberately

| File | Current responsibility | Intended change |
| --- | --- | --- |
| `GOALPad/GOALPadApp.swift` | Declares the normal window and visionOS scenes. | Keep one coordinator and one runtime owner across window, volume, and immersive scenes. |
| `GOALPad/Vision/VisionPresentationMode.swift` | Five-mode model, readiness, selection, fallback, scene requests. | Add explicit transition states, per-mode settings, availability reasons, and user-requested entry/exit. Do not mark a mode playable until its gate passes. |
| `GOALPad/Vision/VisionPresentationScenes.swift` | Volumetric and immersive scene declarations; synthetic compositor configuration. | Replace unavailable views one mode at a time. Keep scene presentation separate from game simulation ownership. |
| `GOALPad/Vision/VisionStereoFramePlan.swift` | Validates a simulation-once, multiview plan for synthetic data. | Generalize only after the native renderer has an external-view contract. Preserve fail-closed matrix, target, slice, and depth validation. |
| `GOALPad/Vision/VisionStereoCompositorProofRenderer.swift` | Dedicated Compositor Services loop and predicted tracking for a tetrahedron. | Reuse its frame timing and drawable discipline for immersive modes. Do not splice `GameSession.tick` into its per-eye loop. |
| `GOALPad/Vision/VisionStereoProof.metal` | Synthetic proof shader. | Keep as a permanent no-retail-data smoke test; do not evolve it into the game renderer. |
| `GOALPad/Game/GameSession.swift` | Owns session lifecycle and performs input → one GOAL frame → render → save hooks → rumble. | Split simulation cadence from presentation cadence while retaining one authoritative session. |
| `GOALPad/Game/GameSurfaceView.swift` | Owns one `CAMetalLayer` and a main-thread `CADisplayLink`. | Leave as the Comfort adapter. Move shared clock/ownership policy below this adapter instead of adding spatial cases throughout it. |
| `GOALPad/Native/GOALPadRenderSurface.mm` | Bridges one Swift-facing surface to one `CAMetalLayer` frame. | Add a narrow presentation-neutral native surface/session API; keep Objective-C++ ownership explicit. |
| `GOALPad/Native/GOALPadMetalHost.mm` and `.hpp` | Receives DMA chains, consumes live Merc bones synchronously, and drives the OpenGOAL Metal renderer. | Establish immutable frame provenance and render-once/render-many entry points before attaching any real spatial mode. |
| `OpenGOAL/game/graphics/opengl_renderer/MetalRenderer.*` and its Metal bucket renderers | Decode and render real Jak DMA into one offscreen color/depth pair, then present once. | Accept external views and targets across every 3D bucket. Keep upstream-shaped changes narrow and tested. |
| `GOALPad-Info.plist` | Controller and document settings. | Add privacy usage strings only when a mode actually requests the corresponding ARKit data. |
| `GOALPad/GOALPad.entitlements` and target Signing & Capabilities | Game Center and iCloud only. | Add World Sensing only for the room-play implementation, not for ordinary stereo or head pose. |
| `Scripts/run-vision-scene-foundation-check.sh` and `Scripts/vision-stereo-frame-plan-check.swift` | Compile/static contracts and deterministic synthetic multiview validation. | Extend focused contracts per milestone; retain the synthetic proof independently of game-data tests. |

### Suggested new files

Names may be adjusted to match the implementation, but keep these responsibilities separate:

- `GOALPad/Vision/VisionPresentationSettings.swift`: Codable, validated user choices such as world scale, rotation, immersion, locomotion, vignette, and automatic comfort fallback.
- `GOALPad/Vision/VisionPresentationRuntime.swift`: main-actor state machine that grants exactly one presentation adapter ownership of the native session.
- `GOALPad/Vision/VisionWindowedStereoView.swift`: RealityKit bridge based on Apple's windowed-game pattern.
- `GOALPad/Vision/VisionTabletopView.swift`: bounded volume, RealityKit content root, manipulation gestures, and mode chrome.
- `GOALPad/Vision/VisionImmersiveRenderer.swift`: product Compositor Services loop for modes that actually use custom immersive Metal; keep the synthetic proof separate.
- `GOALPad/Vision/VisionWorldAnchorController.swift`: session-local origin, recentering, tracking-loss policy, and optional `WorldAnchor` ownership.
- `GOALPad/Vision/VisionRoomPlayController.swift`: opt-in authorization and room/scene-reconstruction providers. Do not create this until the room-play milestone starts.
- `GOALPad/Native/GOALPadSpatialPresentation.h` and `.mm`: small Swift-facing API for selecting a presentation adapter and submitting validated view descriptors.
- A portable OpenGOAL renderer header for `RenderFrameSnapshot` and `RenderView`, located beside `MetalRenderer` rather than in Swift-facing code.

Do not create all of these as empty scaffolding. Add each file in the milestone that first needs it.

## Shared frame architecture

### Current constraint

`GameSession.tick` currently opens one `CAMetalLayer` frame, pushes input, calls one GOAL frame, and ends that surface frame. During the GOAL frame, `host_send_chain` copies the DMA chain and renders synchronously. That synchronous consumption is required because Merc bone matrices referenced outside the copied DMA chain are live only for that send. The Metal renderer also has one game color texture, one depth texture, one present destination, and reusable streaming buffers guarded by completion waits.

A naïve second call for the other eye would either advance simulation twice, reuse mutable buffers unsafely, or consume camera-dependent state with the wrong lifetime.

### Target frame flow

```text
GameController / touch state
          |
          v
one fixed GOAL simulation tick
          |
          v
capture one render-complete immutable snapshot
  - copied DMA and stable side data
  - authored gameplay camera and frame identity
  - texture/upload generation references
  - HUD/2D classification
          |
          +---------------------+
          |                     |
          v                     v
presentation frame N        presentation frame N+1
  view 0 + view 1            view 0 + view 1
  same snapshot ID           latest snapshot ID
          |
          v
one command-buffer submission policy, then present
```

The presentation loop may run at a system-selected cadence different from the 60 Hz game tick. It reads the latest complete snapshot; it never calls game processes, save hooks, or input twice.

### Snapshot milestone

Define a C++-owned `RenderFrameSnapshot` with an explicit monotonically increasing frame ID and immutable lifetime through GPU completion. It must own or safely pin every item a bucket reads after `host_send_chain` returns. At minimum audit:

- DMA bytes and chain address provenance.
- Merc bone palettes and every other out-of-chain EE pointer.
- Texture uploads, relocations, texture-pool generation, and level load/unload boundaries.
- Renderer options and game version.
- Authored camera packets and culling data used by every bucket.
- Any stream-buffer memory mutated in place.
- HUD, subtitles, menus, sprites, and other screen-space content.

There are two acceptable first implementations:

1. Render all required eyes synchronously inside `host_send_chain` while live side pointers remain valid. This is the smallest proof, but it still needs isolated per-view stream state and must finish both eye encodes before returning.
2. Deep-copy or pin a render-complete snapshot, return from `host_send_chain`, and let a presentation thread render it later. This is the durable architecture and is required if compositor cadence decouples from simulation.

Do not choose option 2 until an ownership audit proves that every live side pointer has been captured. Do not describe option 1 as a reusable immutable snapshot.

### Render-view contract

The renderer should consume a span of validated view records instead of a `CAMetalLayer`:

```text
RenderView
  stable view ID / eye role
  color texture + optional array slice
  depth texture + optional array slice
  viewport
  world-from-view transform from the platform
  projection matrix from the platform
  near/far and reverse-depth convention
  game-world-to-presentation-world transform
  culling policy
  HUD policy
```

The existing `CAMetalLayer` present pass becomes the one-view Comfort adapter. RealityKit-backed window/volume adapters and Compositor Services adapters provide their own targets and view records.

### Coordinate and stereo math

Pick and document one notation. For a game-space point `p_game`:

```text
p_clip_i = P_i * inverse(T_presentationFromEye_i) * T_presentationFromGame * M_game * p_game
```

Where:

- `T_presentationFromEye_i` is the system-supplied pose for view `i` at the predicted presentation time.
- `T_presentationFromGame` places and scales the OpenGOAL world in the window, volume, or immersive origin.
- `M_game` is the object's existing game-world transform.
- `P_i` is the system-supplied asymmetric projection for that eye.

Requirements:

- Convert OpenGOAL and Apple handedness/axis conventions once at the adapter boundary and cover the conversion with deterministic tests.
- Keep Build 134's reverse-depth behavior: use the drawable/capability near and far values, not desktop constants.
- Never derive the second eye from the first with a fixed X offset.
- Use the pose predicted for the drawable's presentation time, not the latest pose sampled during simulation.
- Reject non-finite matrices, mismatched texture/slice/viewport mappings, duplicate eye mappings, and stale snapshots before encoding.
- Recompute visibility per eye or use a conservative union frustum. Culling from only the authored gameplay camera will make stereo geometry disappear.

### Camera separation across OpenGOAL buckets

This is the central renderer task. Camera state is not centralized today. Background packets provide planes, camera transforms, fog, perspective, and other constants; tfrag, tie, shrub, merc, generic, sprite, shadow, ocean, sky, eye, and direct renderers consume camera-dependent data in different forms.

For every 3D bucket:

- Identify which values are true authored/gameplay inputs and which are final-view transforms.
- Preserve authored inputs needed by game logic, streaming, LOD, fog, cutscenes, and effect timing.
- Override only the final render view/projection and the culling derived from it.
- Reset or allocate per-view mutable renderer state before rendering the next eye.
- Prove that eye 0 cannot leak constants, stream offsets, depth state, or texture state into eye 1.

Do not patch only the final present pass. Presenting the same monoscopic offscreen texture twice is not stereo.

### HUD and 2D policy

Classify screen-space draws before shipping stereo:

- App chrome and mode controls stay native SwiftUI/RealityKit UI.
- Game HUD, subtitles, menus, and prompts should initially render onto a comfortable, view-stable plane at a deliberate depth.
- World labels and effects that already belong in 3D render once per eye.
- Avoid placing HUD at the extreme near plane or attaching it rigidly to head motion without a comfort review.
- Decide whether cutscene mattes and full-screen effects remain a view-stable layer or intentionally affect the 3D world. Test both eyes.

## Presentation ownership and lifecycle

Introduce an explicit state machine; do not let each SwiftUI scene infer ownership independently:

```text
Comfort active
  -> requested spatial mode
  -> open target scene while Comfort remains visible and paused for handoff
  -> target adapter reports render-ready
  -> transfer presentation ownership
  -> active spatial mode
  -> dismiss / failure / tracking loss
  -> reacquire Comfort surface
  -> Comfort active
```

Rules:

- One `GameSession` and one OpenGOAL runtime survive the transition.
- Exactly one owner advances simulation. A mirror window may display a texture but must not tick the game.
- Do not dismiss the known-good window before the target scene reports ready.
- Stop accepting drawables before destroying a spatial renderer; wait for its in-flight command buffers and snapshot references.
- On scene backgrounding, stop presentation callbacks, pause input/audio according to the existing lifecycle policy, and preserve the session.
- On transient tracking loss, hold the last stable world anchor briefly and fade. Never snap the world to the user's head.
- On denied authorization or unrecoverable provider failure, explain the limitation and return to Comfort.
- Closing a volume or immersive space must not destroy user saves or prepared game data.

## Mode 1 — Comfort / Normal window

### Product contract

The existing resizable conventional window is the lowest-motion, lowest-permission path. It remains available in every graphics profile and is the automatic recovery destination.

### Implementation checklist

- [ ] Preserve the existing `WindowGroup` → `GameSurfaceView` → `CAMetalLayer` path.
- [ ] Keep it monoscopic unless a user explicitly chooses Stereoscopic 3D.
- [ ] Add a clearly labeled presentation-mode picker and an explicit Enter button; do not open immersive content at launch.
- [ ] Display why unavailable modes cannot start rather than silently changing the selection.
- [ ] Allow an immediate Return to Comfort action from every spatial mode.
- [ ] Preserve controller navigation and existing keyboard/touch behavior where supported.
- [ ] Do not request World Sensing or hand-tracking permission.

### Acceptance gate

- Existing native game, lifecycle, input, save, and renderer checks remain green.
- Switching to a failed or cancelled spatial mode returns to the same running session.
- No extra render loop or second simulation tick remains active after the transition.

## Mode 2 — Stereoscopic 3D, Modern default

### Product contract

This mode is a stereoscopic, head-tracked game presented in a bounded visionOS window. It is the desired default for Modern only after physical-device validation. Until then, Modern may select it but must continue to activate Comfort with an honest status message.

### Recommended presentation path

Use RealityKit's official [Rendering a windowed game in stereo](https://developer.apple.com/documentation/realitykit/rendering-a-windowed-game-in-stereo) sample as the product integration pattern. It demonstrates a Metal game in a visionOS window with stereoscopy, head tracking, variable refresh behavior, and a spatial frame. Use RealityKit's [`TextureResource.DrawableQueue`](https://developer.apple.com/documentation/realitykit/textureresource/drawablequeue-swift.class) bridge and per-eye camera information to feed the external-view OpenGOAL renderer, following the exact current sample rather than assuming a queue topology.

The Build 134 `CompositorLayer` proof should remain a renderer-contract test and later become a foundation for immersive modes. A default compositor space is not the bounded window promised by this mode.

### Implementation checklist

- [ ] Complete the snapshot and external-view renderer contracts first.
- [ ] Download and audit the current Apple sample with the same Xcode version; record APIs and minimum OS requirements before copying a pattern.
- [ ] Add the RealityKit-backed stereo window without replacing the normal `WindowGroup` fallback.
- [ ] Bind each RealityKit/system view to the correct color target, depth target, slice, viewport, pose, and projection.
- [ ] Render the real 3D bucket set separately for both eyes from one snapshot.
- [ ] Give HUD and full-screen effects an explicit stereoscopic policy.
- [ ] Keep game simulation at its validated cadence; use presentation timing for head pose and rendering only.
- [ ] Support user-controlled 3D strength only by changing world framing/depth placement within safe platform semantics, never by inventing IPD.
- [ ] Do not add ARKit World Sensing. Ordinary device/head pose does not justify room access.
- [ ] Keep the synthetic compositor proof callable from a developer diagnostic, not the consumer mode picker.

### Acceptance gate

- A deterministic test proves one snapshot ID reaches two unique system views and unique render targets.
- Per-eye captures differ as predicted by known synthetic geometry while animation and game state remain identical.
- All 3D bucket classes pass a stereo coverage scene; no one-eye culling, missing eye, or cross-eye state leakage occurs.
- HUD, subtitles, menus, particles, shadows, fog, cutscene effects, and resolution changes are visually reviewed.
- A physical Apple Vision Pro run proves stereoscopy, head tracking, window behavior, controller input, comfort, and sustained frame pacing. Simulator/typecheck evidence is recorded separately.
- Only after that gate should Modern activate this mode by default.

## Mode 3 — Tabletop / volumetric window

### Product contract

The game world appears as a bounded diorama. The person may move their head around it, but manipulating the view rotates, pans, or scales the Jak world root inside the volume—not an invisible user camera. Settings control world scale and how much of the bounded scene fills the volume.

Apple's [volumetric window API](https://developer.apple.com/documentation/swiftui/windowstyle/volumetric/) gives the app a bounded 3D scene. The volume's physical size is fixed after creation, so scale the game content inside it. Use [scene default 3D size](https://developer.apple.com/documentation/SwiftUI/Scene/defaultSize%28width%3Aheight%3Adepth%3Ain%3A%29) for a deliberate initial volume and use [RealityKit coordinate conversion](https://developer.apple.com/documentation/realitykit/transforming-entities-between-realitykit-coordinate-spaces) instead of assuming the volume and immersive origins match.

### Renderer decision gate

`CompositorLayer` is an immersive-space API; it does not by itself render OpenGOAL geometry as true content inside a volumetric window. Decide between these approaches with a small synthetic spike:

1. A RealityKit-facing geometry bridge that exposes OpenGOAL render geometry/material state as entities or low-level resources inside the volume. This can produce true bounded 3D occlusion but is a substantial renderer integration.
2. A RealityKit portal/dynamic stereo-texture surface driven by the external-view Metal renderer. Apple's [portal sample](https://developer.apple.com/documentation/visionos/displaying-a-3d-environment-through-a-portal) and [`PortalMaterial`](https://developer.apple.com/documentation/realitykit/portalmaterial) are relevant references, but a flat stereo card is not a tabletop world.

Reject approach 2 if content cannot maintain correct parallax, clipping, occlusion, and viewing from the supported angles. Do not label a head-tracked rectangle “volumetric.” Do not begin a wholesale conversion of OpenGOAL assets to USDZ or a second RealityKit renderer without an explicit maintainer decision.

### Transform behavior

Maintain a `T_volumeFromGame` root transform:

- Head movement changes `T_volumeFromEye` through the system viewer pose.
- A rotate gesture changes the rotation component of `T_volumeFromGame`.
- A scale gesture changes meters-per-game-unit within validated minimum and maximum bounds.
- A pan/reframe gesture changes the world-root translation, clamped so the useful scene remains recoverable.
- A Reset View action restores a known scale, orientation, and focal point.

The authored gameplay camera may still drive game logic and initial focal selection. It must not be mutated merely because the person circles or rotates the diorama.

### Implementation checklist

- [ ] Prove one original synthetic scene as actual bounded 3D content before attaching retail-derived runtime output.
- [ ] Select and document the geometry-bridge approach at the decision gate.
- [ ] Add a focal-point service that follows Jak or a selected level region without rewriting the game camera.
- [ ] Implement world-root rotate, translate, and scale gestures with SwiftUI/RealityKit standard gestures.
- [ ] Offer presets such as Miniature, Table, and Large plus a bounded fine control; store meters-per-game-unit, not vague “zoom.”
- [ ] Label the second framing control clearly, for example Scene Fill, rather than overloading “immersion.” Volumes do not have progressive/full immersion.
- [ ] Clamp near/far planes and prevent content from clipping through the volume's usable bounds.
- [ ] Decide how out-of-bounds geometry is culled or faded, including Jak crossing a level boundary.
- [ ] Keep gameplay controller input separate from manipulation gestures and provide a lock so an accidental pinch cannot rotate the world during play.
- [ ] Keep native controls accessible outside the densest 3D content.

### Acceptance gate

- Walking the head laterally produces correct stereo parallax; rotating the model does not alter authored gameplay-camera state.
- The world is visibly bounded in depth and remains recoverable after extreme allowed gestures.
- Scale is physically understandable and stable across close/reopen.
- All supported view angles have correct winding, culling, fog, shadows, sprites, and HUD placement.
- Physical-device testing confirms readable controls, no uncomfortable involuntary world motion, and acceptable thermal/GPU behavior.

## Mode 4 — Room-scale third-person / god view

### Product contract

The Jak world is a large third-person scene anchored in the person's space. It is not head-locked. The person can inspect it from nearby while playing with a controller. World Scale controls meters per game unit; immersion controls how much passthrough remains only when the chosen platform presentation path actually supports it.

### Recommended presentation path

Begin with a stationary mixed or progressive immersive experience, not full occlusion. Keep one `T_visionFromGame` rooted at the immersive session origin or a session-local [`WorldAnchor`](https://developer.apple.com/documentation/arkit/worldanchor). The system-provided eye poses then move naturally around that stable world.

Two renderer paths are viable:

- RealityKit presentation is the simplest way to retain passthrough and spatial UI if the tabletop geometry bridge is already capable enough.
- Custom Metal through Compositor Services reuses OpenGOAL rendering more directly. For progressive immersion, implement Apple's explicit [stencil-mask path](https://developer.apple.com/documentation/compositorservices/controlling-metal-rendering-immersion-level); `.immersionStyle` alone is not an implementation.

Choose one path after Mode 2 and the tabletop decision gate. Do not maintain two complete spatial renderers without measured need.

### Implementation checklist

- [ ] Anchor the game root in world/session space; never recompute it from head pose each frame.
- [ ] Add explicit Place, Recenter, Rotate, Scale, and Return to Comfort controls.
- [ ] Separate physical head motion from controller-driven authored camera motion.
- [ ] Use conservative per-eye culling and spatially appropriate LOD/streaming bounds.
- [ ] Decide whether authored-camera streaming is sufficient when the viewer sees outside it. If not, expand visibility/streaming conservatively without altering simulation.
- [ ] Use progressive immersion only with the documented compositor configuration and mask, or use RealityKit's supported progressive scene behavior.
- [ ] Respect the Digital Crown and system transitions; do not trap the person in full immersion.
- [ ] Keep ground, horizon, and stable world references visible whenever possible.
- [ ] Avoid designs that encourage people to walk beyond the system boundary. Apple's [immersive-experience guidance](https://developer.apple.com/design/human-interface-guidelines/immersive-experiences) describes a roughly 1.5 m boundary for progressive and full experiences.
- [ ] Handle world-anchor update/removal, recentering, tracking interruption, scene dismissal, and relaunch.

### Acceptance gate

- The world remains stable while the person turns and translates their head.
- Recenter is deterministic and never moves the world unexpectedly during active play.
- Passthrough/immersion behavior matches the label on physical hardware.
- Streaming and culling cover everything the new viewer can see without simulating a second world.
- Tracking loss fades or falls back safely; it never turns the game head-locked.
- Controller play, system gestures, scene lifecycle, and sustained performance pass on physical Vision Pro.

## Mode 5 — Immersive first-person VR

### Product contract

The person's eyes inhabit the Jak world, but Jak's authored camera is not copied directly onto their head. Physical head pose owns instantaneous view orientation. The game may drive locomotion and a stable body/root transform, while spins, rolls, camera shake, knockback, cutscene edits, and other high-motion authored camera effects are suppressed, transformed, or shown through a safer presentation.

This mode must be opt-in. Follow Apple's [motion guidance](https://developer.apple.com/design/human-interface-guidelines/motion), [immersive-experience guidance](https://developer.apple.com/design/human-interface-guidelines/immersive-experiences), and the user's Reduce Motion preference. Avoid large peripheral motion, rotating the virtual world around the person, oscillation, and abrupt direction changes; use a quick fade or stable frame when a discontinuity is unavoidable.

### Camera ownership model

Maintain three distinct inputs:

```text
authoredGameplayCamera   OpenGOAL's original camera; retained for logic and intent
locomotionState          stable game-world body position plus comfort-filtered yaw
trackedEyePose_i         late, system-predicted physical pose for eye i
```

Locomotion updates the game-to-presentation placement transform; each final view still uses the shared `p_clip_i` equation and the platform's `trackedEyePose_i` and `P_i`. The system eye pose already embodies the correct eye relationship. Do not multiply an extra guessed eye offset or copy authored camera pitch/roll into it.

### Float-through and suppression policy

Implement an explicit camera-event classifier rather than a generic low-pass filter:

| Authored event | Default first-person response |
| --- | --- |
| Normal Jak translation | Move `locomotionRoot` at a comfort-limited rate or use the selected locomotion option. |
| Normal heading change | Apply controller-requested yaw with snap/smooth setting; tracked head yaw remains independent. |
| Jump/fall/bob | Use reduced, tunable vertical coupling; never add artificial head bob by default. |
| Attack spin, roll, flip, pole swing | Keep head horizon stable and let Jak/body/world animation pass around the viewer. This is the “float-through” behavior. |
| Camera shake, hit reaction | Suppress head rotation and translation; substitute haptics, audio, a subtle vignette, or a world-space effect. |
| Teleport, warp, death/reset | Fade out, relocate the root, reacquire a valid pose, then fade in. |
| Cutscene or scripted camera | Switch to a comfortable virtual screen/spectator bubble unless the scene has an approved first-person treatment. |
| Camera collision or geometry crossing the head | Fade/occlude near geometry, adjust a spectator bubble, or fall back; never shove the physical head. |

Provide at least:

- Snap turn angles plus an optional smooth-turn speed.
- Vignette strength for artificial locomotion.
- Reduced vertical motion.
- Dominant heading/recenter control.
- Automatic flat-screen cutscenes.
- Immediate Return to Comfort.

### Implementation checklist

- [ ] Enumerate actual Jak 1 camera modes and high-motion states from OpenGOAL before implementing the classifier.
- [ ] Keep physical head pitch and roll independent of authored camera pitch and roll.
- [ ] Suppress Jak head/face and unsafe near-body geometry when the eye origin is inside the character.
- [ ] Define avatar-body visibility and shadow behavior; do not leave one-eye clipping artifacts.
- [ ] Add collision-safe near fade and a minimum comfort radius.
- [ ] Treat camera cuts, warps, deaths, level loads, pause, and save restore as explicit transitions.
- [ ] Use a full-space custom Metal path only after the external-view renderer passes Modes 2 and 4 gates.
- [ ] Read `UIAccessibility.isReduceMotionEnabled` or the current visionOS equivalent and choose safer defaults; never weaken the user's preference silently.
- [ ] Keep controller gameplay as the first input path. Raw hand-joint tracking is not required for first-person rendering.

### Acceptance gate

- A maintainer-reviewed matrix covers every enumerated camera mode and transition.
- Spins, rolls, shake, warps, cutscenes, and collision cannot rotate or jerk the user's head frame.
- Eye-origin geometry, shadows, particles, HUD, and audio remain coherent.
- First-person movement, snap/smooth turning, vignette, Reduce Motion, pause, recenter, and emergency exit are tested on physical Vision Pro.
- Comfort review includes multiple session lengths and stops immediately on discomfort; “technically rendered” is not acceptance.

## Spatial input and controller policy

### Initial modes

- Keep `GameController` extended-gamepad input as the gameplay authority. It is already declared in `GOALPad-Info.plist` and avoids unnecessary sensor access.
- Use standard SwiftUI and RealityKit gaze-and-pinch, drag, rotate, and scale interactions for mode selection and world placement. The system handles gaze focus without exposing gaze coordinates.
- For custom immersive Metal interactions, use Compositor Services spatial events or tracking areas only where a native control cannot express the interaction. Apple's [Metal hover guidance](https://developer.apple.com/documentation/compositorservices/rendering_hover_effects_in_metal_immersive_apps) preserves gaze privacy.
- Resolve focus explicitly: manipulation mode consumes spatial gestures; gameplay mode sends controller input. Show which one is active.

### Raw hand tracking

Do not request raw hand joints for the first implementation. If a later design genuinely requires them:

- Add `NSHandsTrackingUsageDescription` with a plain-language, feature-specific reason.
- Request authorization at the moment the user enables the feature, not at launch.
- Keep controller and standard-gesture alternatives when permission is denied or revoked.
- Do not store hand traces.

See Apple's [ARKit access setup](https://developer.apple.com/documentation/visionos/setting-up-access-to-arkit-data) and [visionOS privacy guidance](https://developer.apple.com/documentation/visionOS/adopting-best-practices-for-privacy).

## Performance and frame pacing

Do not set a universal millisecond budget in source. Use `LayerRenderer` predicted timing and the actual drawable deadline for the active device/refresh rate.

Use these as initial go/no-go targets, then record any maintainer-approved revision with the physical baseline. A nominal 90 Hz interval is 11.11 ms, but the compositor's predicted timing is authoritative.

| Area | Initial physical-device target |
| --- | --- |
| Game simulation | Maintain the existing validated 60 Hz game cadence; p99 must remain below its 16.67 ms interval outside documented level-load transitions. |
| Presentation CPU | Finish update work and submit before every predicted drawable deadline; p99 encode time below 50% of the observed display interval. |
| GPU | p95 below 80% and p99 below 90% of the observed display interval after warm-up, leaving compositor headroom. |
| Delivery | Fewer than 0.1% missed/repeated presentation snapshots over a representative 10-minute run, with no sustained run of misses. |
| Memory | In-flight snapshot/resource memory reaches a stable plateau; no monotonic growth during 15 minutes of stationary play and repeated mode transitions. |
| Thermal | No `.serious` or `.critical` thermal state during a representative 20-minute run. Record state transitions rather than hiding them with an unreported quality change. |

These are acceptance targets, not claims about Build 134 and not permission to drop visual correctness. If the one-eye physical baseline cannot meet one, stop and diagnose before doubling renderer work.

### Policy

- Keep the proven game simulation cadence independent from display cadence. Start with the latest complete 60 Hz simulation snapshot.
- If physical testing shows judder at another display cadence, add interpolation only for render-safe transforms between two immutable snapshots. Never interpolate game decisions, collision, streaming, save state, or DMA ownership.
- Render head pose as late as the API permits using predicted presentation time.
- Expect stereo to roughly multiply geometry/pixel work, but measure every bucket instead of assuming exactly 2x.
- Start with the proof's clear two-pass dedicated layout for correctness. Consider layered layout, vertex amplification, foveation, rasterization-rate maps, or shared passes only after image equivalence tests pass.
- Add dynamic per-eye internal resolution with conservative bounds and stable hysteresis. Never vary left and right eye quality independently.
- Keep reverse depth and per-drawable near/far values.
- Reuse resources only after GPU completion. Snapshot lifetime must cover the last command buffer that references it.
- Move room-mesh processing, visibility structure builds, and permission/provider updates off the render thread, then atomically publish immutable results.

### Measurements to record

- Simulation time, snapshot capture time, CPU encode time, GPU time, drawable wait, missed deadlines, and dropped/repeated snapshots.
- Per-bucket CPU/GPU cost and per-eye target resolution.
- Memory for snapshots, textures, geometry bridges, room meshes, and in-flight frames.
- Thermal state and sustained behavior, not only a short peak frame rate.
- Head-pose age at submission and visible tracking latency.

Use Metal System Trace, GPU counters, and the appropriate Instruments visionOS templates. Record device model, OS, Xcode, scene mode, resolution, refresh behavior, test duration, and game location with every result.

## Room-play extension — Jak leaves the frame

This is later scope. Start only after real stereo, stationary world anchoring, camera separation, lifecycle recovery, and physical performance are healthy.

### Experience boundary

Jak may cross a visible portal/boundary from the game presentation into a locally reconstructed representation of the user's room. Nearby enemies may spawn only in validated safe regions. The OpenGOAL simulation remains authoritative; room geometry becomes local collision/navigation data, not a second RealityKit game.

### Required Apple APIs and permissions

- Use [`RoomTrackingProvider`](https://developer.apple.com/documentation/arkit/roomtrackingprovider) for room structure and [`SceneReconstructionProvider`](https://developer.apple.com/documentation/arkit/scenereconstructionprovider) for mesh geometry if supported on the running device/OS.
- Use [`RoomAnchor`](https://developer.apple.com/documentation/arkit/roomanchor) relationships and classifications as hints, not exact semantic truth.
- Add the World Sensing capability in Xcode Signing & Capabilities and `NSWorldSensingUsageDescription` only when this feature is implemented. Apple's [object-tracking setup](https://developer.apple.com/documentation/visionos/exploring_object_tracking_with_arkit) documents the capability requirement; [ARKit access setup](https://developer.apple.com/documentation/visionos/setting-up-access-to-arkit-data) documents authorization and usage descriptions.
- Check provider support and [`ARKitSession.AuthorizationType`](https://developer.apple.com/documentation/arkit/arkitsession/authorizationtype) at runtime. Handle denied, restricted, revoked, interrupted, and unsupported states.
- World/device pose alone does not justify World Sensing permission. Request the narrower access only after the person selects Room Play and reads the explanation.

Do not guess or hard-code an entitlement key. Add the capability through the Xcode UI/current project format and inspect the generated entitlement for the target SDK.

### Privacy and data handling

- Explain that room geometry is used locally to place collision and game characters safely.
- Keep raw meshes, classifications, anchors, and derived collision structures in memory for the active session by default.
- Do not upload, log, include in analytics, sync through iCloud, or package room geometry with saves.
- Do not persist a room model unless a later explicit feature has separate consent, retention controls, and deletion UI.
- Never access camera imagery; these APIs provide spatial understanding, not permission to capture the person's environment.
- Stop providers and discard session room data on exit. Verify release on background, crash recovery, and authorization revocation.
- Treat classification as fallible. Never infer private household facts from room labels or meshes.

### Safe world conversion

1. Wait for a stable room anchor and scene mesh; show scanning/progress without gameplay spawns.
2. Transform every mesh anchor into the same session-local vision coordinate system used by `T_visionFromGame`.
3. Build a simplified, immutable collision representation off the render thread.
4. Identify candidate floor or tabletop surfaces by classification, slope, area, height, and continuity.
5. Inset walkable regions from walls, furniture, mesh uncertainty, the user origin, and portal boundary.
6. Reject holes, narrow ledges, low-clearance areas, rapidly changing mesh regions, and locations outside the supported play zone.
7. Convert accepted geometry into an OpenGOAL-facing collision proxy with explicit meters-to-game-units scale. Never feed unbounded raw triangles directly into gameplay.
8. Atomically swap a new collision generation at a safe simulation boundary. Despawn or relocate actors invalidated by a mesh update.

### Portal transition and local enemies

- Require a visible, user-placed transition boundary; do not let Jak unexpectedly enter the room behind the person.
- Blend from game scale to room scale across a controlled threshold while preserving one simulation and stable world transform.
- Keep a reversible path back into the game frame and a Return to Comfort action.
- Spawn enemies only in currently visible or deliberately previewed validated regions, away from the person's head/origin and outside safety insets.
- Cap enemy count, speed, reach, and spawn distance for the first release.
- Never require the person to walk into a wall, furniture, stairs, or outside the system boundary.
- On relocalization, permission loss, mesh invalidation, or tracking degradation, stop new spawns, freeze/despawn room actors safely, fade, and return to the anchored game presentation.

### Room-play acceptance gate

- Permission is requested only from an explicit Room Play action; denial returns to an otherwise fully functional mode.
- A no-network test proves room data remains local and ephemeral.
- Unit tests cover coordinate conversion, scale, mesh-generation replacement, safety insets, spawn rejection, and permission-state transitions using synthetic fixtures.
- Physical tests cover different room sizes, furniture changes, low mesh confidence, relocalization, interruption, and revocation.
- A human safety review signs off on spawn visibility, collision margins, exits, and stationary play boundaries.
- No room mesh, derived room model, screenshot, or proprietary game data enters the repository.

### The unresolved “RIP” reference

Project notes mention possible “RIP” behavior without identifying an API, library, format, license, or maintained source. Do not add a dependency or design around that name. Before use, the maintainer must identify exactly what it means, verify its license and visionOS/ARM64 support, confirm it has no private-entitlement or runtime-code requirement, and compare it with the ARKit/RealityKit implementation above.

## Privacy, entitlements, and accessibility checklist

| Capability/data | Modes | Requirement |
| --- | --- | --- |
| System gaze focus and standard gestures | UI in all modes | No raw gaze access. Prefer system controls. |
| Device/world pose for rendering | 2, 4, 5 | Use the platform rendering/tracking API. Verify exact authorization behavior for the chosen provider; do not broaden access. |
| World Sensing / room and scene reconstruction | Later Room Play only | Xcode World Sensing capability, `NSWorldSensingUsageDescription`, explicit runtime request, denial/revocation fallback. |
| Raw hand joints | None initially | Add `NSHandsTrackingUsageDescription` only if a later approved feature cannot use standard gestures. |
| Room mesh persistence/networking | None | Prohibited by the initial design. Session-local memory only. |

For every release candidate:

- [ ] Usage descriptions say what Eco does with the data and why the selected feature needs it.
- [ ] Permission prompts occur in context, never at first launch without explanation.
- [ ] Denied, restricted, revoked, and unsupported paths are tested.
- [ ] Reduce Motion produces safer first-person defaults and removes nonessential spatial animation.
- [ ] Controls remain usable with VoiceOver/visionOS accessibility features where applicable.
- [ ] Color, depth, scale, and motion are not the only carriers of critical state.
- [ ] No telemetry records gaze, hand pose, device pose, room labels, anchors, or mesh data.

References: Apple's [privacy HIG](https://developer.apple.com/design/human-interface-guidelines/privacy), [visionOS privacy guidance](https://developer.apple.com/documentation/visionOS/adopting-best-practices-for-privacy), and [visionOS accessibility guidance](https://developer.apple.com/documentation/visionos/improving-accessibility-support-in-your-app/).

## Validation ladder

Run heavy builds only after several focused changes have been reviewed. Preserve the first useful failure and exact command in the checkpoint report.

### Gate 0 — unchanged baseline

- Current vision scene foundation check passes.
- Current native renderer, runtime, lifecycle, input, save, AOT, and Xcode matrices documented healthy at the checkpoint remain healthy.
- Comfort still plays real Jak data through the existing path.

### Gate 1 — pure multiview contract

- Synthetic matrix/target/slice tests cover one, two, invalid, stale, and mismatched views.
- Handedness and coordinate-conversion fixtures use known points and poses.
- One immutable synthetic snapshot produces distinct eyes without a second simulation call.

### Gate 2 — real renderer coverage

- The external-view renderer runs every relevant Jak 1 bucket from one snapshot.
- Per-eye culling, constants, streams, textures, depth, and state isolation pass deterministic probes.
- HUD/full-screen policy is tested.
- Comfort uses the same renderer core through its one-view adapter with no visual regression.

### Gate 3 — Mode 2 physical stereo

- xros and xrsimulator builds/typechecks are clean where supported.
- Physical Vision Pro proves windowed stereoscopy, head tracking, controller play, lifecycle, and sustained performance.
- Only then change Stereoscopic 3D readiness to playable and Modern's active default.

### Gate 4 — bounded tabletop

- The renderer decision spike proves true bounded 3D, not a stereo rectangle.
- Physical lean, orbit, world-root rotation, scale, clipping, UI, and recovery pass.

### Gate 5 — stationary room-scale world

- Anchoring, recentering, progressive/mixed presentation, tracking loss, streaming visibility, and lifecycle pass without World Sensing.
- World Sensing is still absent unless Room Play has begun.

### Gate 6 — first-person comfort

- The camera-state matrix, float-through policy, transitions, near clipping, Reduce Motion, locomotion settings, and emergency exit pass physical review.

### Gate 7 — room play

- Authorization, privacy, mesh conversion, safe spawning, relocalization, revocation, and ephemeral cleanup pass synthetic and physical gates.

## Recommended implementation order

Stop at each gate until its behavior and evidence are accepted.

1. Preserve Comfort and add the user-facing mode/status UI without making new modes playable.
2. Add a one-view external-target adapter and prove pixel equivalence with the existing `CAMetalLayer` path.
3. Establish render-complete snapshot ownership, including Merc bones and texture generations.
4. Render one snapshot through two synthetic external views across every 3D bucket.
5. Ship and physically validate bounded windowed Stereoscopic 3D; then make it the active Modern default.
6. Run the tabletop renderer decision spike and implement the selected bounded-volume bridge.
7. Implement a stationary anchored third-person/god-view world with no room mesh.
8. Enumerate camera states and implement first-person comfort behavior.
9. Add Room Play authorization, ephemeral mesh/collision conversion, the portal transition, and conservative local enemy spawning.

## Decisions maintainers must make

These choices materially change the architecture or comfort contract and should not be guessed during implementation:

1. Does Tabletop require geometry that visibly occupies the whole volume and can be viewed from behind, or is a portal/diorama with bounded viewing angles acceptable? The names and acceptance criteria should match the answer.
2. Should Room-scale World use RealityKit mixed presentation, Compositor Services progressive immersion, or full custom Metal? Choose after measuring the geometry bridge and renderer reuse.
3. Which authored camera events count as cutscenes, forced spins, rolls, shake, teleports, and spectator transitions in Jak 1?
4. Which first-person locomotion options ship by default, and which are experimental?
5. May room geometry ever persist? This guide assumes no. Any change needs a separate privacy/product decision and deletion design.
6. What exactly does “RIP” refer to? No integration should begin until its source, license, APIs, and platform constraints are known.

## Official Apple references

- [Drawing fully immersive content using Metal](https://developer.apple.com/documentation/compositorservices/drawing-fully-immersive-content-using-metal)
- [Controlling Metal rendering immersion level](https://developer.apple.com/documentation/compositorservices/controlling-metal-rendering-immersion-level)
- [Rendering a windowed game in stereo](https://developer.apple.com/documentation/realitykit/rendering-a-windowed-game-in-stereo)
- [TextureResource.DrawableQueue](https://developer.apple.com/documentation/realitykit/textureresource/drawablequeue-swift.class)
- [Immersive spaces](https://developer.apple.com/documentation/swiftui/immersive-spaces)
- [Creating a volumetric window](https://developer.apple.com/documentation/visionos/creating-a-volumetric-window-in-visionos)
- [Volumetric window style](https://developer.apple.com/documentation/swiftui/windowstyle/volumetric/)
- [Transforming entities between RealityKit coordinate spaces](https://developer.apple.com/documentation/realitykit/transforming-entities-between-realitykit-coordinate-spaces)
- [Displaying a 3D environment through a portal](https://developer.apple.com/documentation/visionos/displaying-a-3d-environment-through-a-portal)
- [PortalMaterial](https://developer.apple.com/documentation/realitykit/portalmaterial)
- [ARKit in visionOS](https://developer.apple.com/documentation/arkit/arkit-in-visionos)
- [Setting up access to ARKit data](https://developer.apple.com/documentation/visionos/setting-up-access-to-arkit-data)
- [Exploring object tracking with ARKit](https://developer.apple.com/documentation/visionos/exploring_object_tracking_with_arkit)
- [ARKitSession.AuthorizationType](https://developer.apple.com/documentation/arkit/arkitsession/authorizationtype)
- [WorldAnchor](https://developer.apple.com/documentation/arkit/worldanchor)
- [RoomTrackingProvider](https://developer.apple.com/documentation/arkit/roomtrackingprovider)
- [SceneReconstructionProvider](https://developer.apple.com/documentation/arkit/scenereconstructionprovider)
- [RoomAnchor](https://developer.apple.com/documentation/arkit/roomanchor)
- [Adopting best practices for privacy and user preferences](https://developer.apple.com/documentation/visionOS/adopting-best-practices-for-privacy)
- [Human Interface Guidelines: Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy)
- [Human Interface Guidelines: Motion](https://developer.apple.com/design/human-interface-guidelines/motion)
- [Human Interface Guidelines: Immersive experiences](https://developer.apple.com/design/human-interface-guidelines/immersive-experiences)
- [Improving accessibility support in your visionOS app](https://developer.apple.com/documentation/visionos/improving-accessibility-support-in-your-app/)
- [Rendering hover effects in Metal immersive apps](https://developer.apple.com/documentation/compositorservices/rendering_hover_effects_in_metal_immersive_apps)
- [WWDC24: Bring your iOS or iPadOS game to visionOS](https://developer.apple.com/videos/play/wwdc2024/10093/)
- [WWDC24: Design advanced games for Apple platforms](https://developer.apple.com/videos/play/wwdc2024/10094/)

Recheck these references against the deployment SDK when each milestone begins. visionOS APIs and their availability continue to evolve; this manual deliberately avoids treating a compile against one SDK as runtime proof.
