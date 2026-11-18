# Optional Jak II immersion

Status: **Experimental**, integration validation in progress for Build 291.
Tracked in [#30](https://github.com/zschwendi/dark-eco/issues/30).
The published Build 290 preview does not include this extension.

## Behavior

On Vision Pro, Jak II can use the same optional third-person immersive
presentation as Jak 1. The game's camera remains the base camera, with Jak
visible; headset pose supplies the two eye views. The conventional window
remains available. Entering immersion suspends its renderer, and leaving
restores it. Pausing returns to the window with the game still paused.

A normal gamepad or a pair of PSVR2 Sense controllers can supply buttons and
sticks. With motion gestures enabled, either-hand jabs map to Square,
side-to-side shakes to Circle, and raising both controllers to Cross. A second
lift can trigger the normal double jump. These gestures are optional and also
available during windowed play; original buttons remain available. This is
not first-person play or controller-anchored hands.

## Implementation

- Shared Swift presentation, menu and input gates now admit Jak II. The
  isolated Jak II framework forwards the existing reservation, external-target
  and completion API to its own renderer and Metal queue.
- Both eyes replay the same validated DMA frame. Host uploads and callbacks
  run once, while geometry draws for each eye. Culling uses a conservative
  binocular volume instead of the original single-camera frustum.
- The eye transform accounts for Jak II's projection and vertical scale.
  Sky generation applies the head rotation before the native producer clips
  polygons. Copied sky payloads must map to their validated original EE spans
  and match their bytes before the producer receipt is accepted.
- Shadow volumes and glow positions use their eye transforms. Fullscreen
  shadow resolves retain screen coordinates. Generic warp sampling derives
  its screen position after raster interpolation to preserve perspective.
- Invalid targets, camera data and provenance fail explicitly. Conventional
  rendering and the existing Jak 1 path retain their own camera conventions.

These are native C++/Objective-C++/Metal changes, not a GOAL code-mod pack.
The existing signed AOT libraries and public source-pack identities remain
unchanged: Jak 1 has 518 objects (`c1e79fbb50f33437`), and Jak II has 840
(`4f3e512e091fae63`). No game assets or new runtime-generated code are added.

## Validation boundaries

The synthetic tests exercise camera projection, binocular disparity, head
rotation, sky coverage, copied-DMA provenance, callbacks, shadow coverage and
recovery without retail assets. A separate CPU fixture executes the native
sky polygon producer and clipping functions. Its sun, moon and star callback
paths have source review only.

The canonical Release host build and all 26 scoped CTest cases pass, including
the native external-frame recovery test, actual sky-producer contract, stereo
GPU fixture, and existing Jak 1 sky regressions. The shared Swift/visionOS proof
aggregate also passes. Three fixture corrections were needed: a level name
exceeded the native packet's limit, the synthetic sky depth format was wrong,
and authored fog dimmed the quad below its exact-color detector. Projection
oracles and tolerances were preserved. The host recovery fixture now uses a
valid physical eye pair and a layer-backed host matching the application.

Affected Apple app builds and signing remain pending at this source checkpoint.
Headset acceptance is still required for comfort, real-world effects and sky,
Sense gesture tuning, performance, and repeated enter/pause/resume/exit.
Compilation or synthetic GPU checks do not establish those results. Existing
Jak II renderer, mission and performance issues remain tracked separately;
this feature does not claim a complete story playthrough.
