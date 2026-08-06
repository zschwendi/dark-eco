# Jak 1 authored touch-prompt inventory

Status: **Implemented and signed in Build 127; physical interaction coverage pending**
Scope: authored Jak 1 on-screen face-button prompts outside native title/progress menus

This inventory distinguishes an authored prompt from an ordinary gameplay control.
Eco may add a semantic touch target only while the game itself owns and accepts that
prompt. It must not infer a prompt from proximity, display ownership, a screenshot,
or an unprompted controller read.

## Existing accepted paths

- **Warp gate:** `Circle - Use Warp Gate`, destination actions, full-screen list
  capture, and horizontal swipes are implemented and maintainer-accepted. This path
  is frozen and must not be generalized, relabelled, or replaced.
- **Cutscene SKIP:** the native authored Triangle query has a separate checked
  owner/sequence/heartbeat snapshot. Keep it separate so Triangle is not duplicated.
- **Title/progress/pause:** app-owned touch actions use their existing checked native
  state and are not part of the gameplay prompt snapshot.

## Build 127 authored prompts

| Interaction | Requested input | Authoritative owner |
| --- | --- | --- |
| NPC talk or trade, including Oracle | Circle | Common `process-taskable` idle responder after its task, proximity, gameplay, HUD, and display-owner gates |
| Zoomer / speederbike | Circle | `racer` prompt branch while explicit input is required; condition 4 auto-entry is excluded |
| Fisherman's boat | Circle | Boat dock prompt branch after task, distance, debounce, animation, HUD, display-owner, and boot-mode gates |
| Flut Flut mount | Circle | `flutflut` prompt branch while explicit input is required |
| Misty cannon mount | Circle | Cannon grip-touch prompt branch |
| Jungle mirror / periscope mount | Circle | Mirror grip-touch prompt branch |
| Gondola ride | Circle | Gondola prompt branch after task/cell, distance, height, HUD, and display-owner gates |
| Billy/Fisher confirmation and replay query | Cross and Triangle, or Triangle only | Explicit non-cutscene `gui-query` owner; Cross is yes and Triangle is no/cancel |
| First-intro subtitle notice | Square | First `sage-intro-sequence-a` notice while the five-second subtitle prompt is actually drawn and accepted |

Primary sources:

- `OpenGOAL/goal_src/jak1/engine/common-obs/process-taskable.gc`
- `OpenGOAL/goal_src/jak1/levels/racer_common/racer.gc`
- `OpenGOAL/goal_src/jak1/levels/village1/fishermans-boat.gc`
- `OpenGOAL/goal_src/jak1/levels/flut_common/flutflut.gc`
- `OpenGOAL/goal_src/jak1/levels/misty/mistycannon.gc`
- `OpenGOAL/goal_src/jak1/levels/jungle/jungle-mirrors.gc`
- `OpenGOAL/goal_src/jak1/levels/village3/village3-obs.gc`
- `OpenGOAL/goal_src/jak1/levels/swamp/billy.gc`
- `OpenGOAL/goal_src/jak1/levels/jungle/fisher.gc`
- `OpenGOAL/goal_src/jak1/pc/subtitle.gc`

## Explicit exclusions

- Fire Canyon and Lava Tube cell-requirement notices have no face-button responder.
- `can-grab-display?` is an ownership/throttling gate, not a button identity.
- Cannon exit/charge, mounted steering, combat, and other ordinary gameplay reads
  are not contextual prompts merely because they consume face buttons.
- Debug and demo controls are outside the shipping interaction surface.

## Build 127 contract

GOAL owns a read-only prompt snapshot containing revision, even seqlock sequence,
requested face-button mask, owner handle, and heartbeat. Publication occurs only
inside the exact authored branch above and clears immediately when that branch loses
authority. Native validation rejects torn, stale, ownerless, empty, or non-face
publications.

Swift presents requested symbols in stable `Cross, Square, Triangle, Circle` order
and emits only the matching ordinary pad bit. Visible labels are not inferred. The
new targets do not capture the gameplay surface, remain touchable while controller
artwork is visually suppressed, and yield completely to the frozen warp path.

Physical acceptance still requires Oracle, Zoomer, boat, Flut Flut, cannon,
periscope, gondola, Fisher/Billy queries, and the first-intro Square notice. Static,
host, AOT, and signed-build evidence cannot replace those gameplay checks.
