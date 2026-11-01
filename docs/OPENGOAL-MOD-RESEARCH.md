# OpenGOAL mods and first-person experiments

Research checkpoint: November 1, 2026. Prepared with Claude Code Opus 5.5 and
reviewed against the authors' repositories and official OpenGOAL documentation.
Tracking: [mods and settings #18](https://github.com/zschwendi/dark-eco/issues/18),
[first-person and Sense hands #17](https://github.com/zschwendi/dark-eco/issues/17).

These are candidates, **not installed features or verified Apple ports**. The
ranking balances useful gameplay changes with integration effort. Version and
source details are in [the source ledger](OPENGOAL-MOD-SOURCES.json).
Third-person remains Dark Eco's default. Existing renderer defects take priority.

## Ten candidates

| Rank | Existing mod | Player-facing effect | Apple assessment and next step |
| --- | --- | --- | --- |
| 1 | [Checkpoint Randomizer](https://github.com/OpenGOAL-Mods/OG-Randomizer) | Randomized checkpoint changes make familiar Jak 1 areas unpredictable. | Strong early candidate for iPhone/iPad and third-person Vision play. Audit its GOAL changes and settings-file access, then add a signed optional mode. The [official walkthrough](https://opengoal.dev/docs/developing/modding_examples/checkpoint_randomizer/) documents the approach. |
| 2 | [The Precursor Orb Hunt](https://github.com/dallmeyer/OG-OrbHunt) | Rearranges existing actors and collectibles for fresh exploration. Its [Jak 1 guide](https://github.com/dallmeyer/OG-OrbHunt/blob/f5037c781a1da32e3f9675da2ffad39028a0ffdc/README_JAK1.md) says level models/collision stay unchanged; some collectibles use the goggles. There is also a Jak II variant. | Strong candidate for both flat and immersive play. First identify whether relocations are code or entity data, and keep each game's integration separate. |
| 3 | [Speedrun Practice](https://github.com/OpenGOAL-Mods/OG-Speedrun-Practice/blob/main/README.md) | Custom checkpoints, resets and practice tools, including vehicle toggles. | Useful on all current platforms. Separate new features from tools already upstream, and provide touch/Sense equivalents for controller chords. Jak 3 support in the mod does not make Jak 3 supported by Dark Eco. |
| 4 | [The Zoomer Legacy](https://github.com/OpenGOAL-Mods/OG-Zoomer-Legacy) | Vehicle-focused Jak 1 play. Source adjusts platforms, blockers and collision around traversal obstacles; the catalog describes playing the whole game on a Zoomer. | Promising optional challenge, preferably with a gamepad. Audit racer-state changes and level completion paths; fast vehicle motion needs headset evaluation. |
| 5 | [The FlutFlut Legacy](https://github.com/OpenGOAL-Mods/OG-FlutFlut-Legacy) | FlutFlut-focused Jak 1 play. Source includes bounce tracking and a softlock escape; the catalog describes playing the whole game on FlutFlut. | Promising novelty mode. First verify the forced character states and which bundled mod modules are actually active. Neither full-game claim has been independently tested here. |
| 6 | [First-person-jak](https://github.com/OpenGOAL-Unofficial-Mods/First-person-jak) | An existing Jak 1 first-person camera prototype. | Best camera reference for the requested Vision experiment, but unsuitable for wholesale import: it is a 2022 fork, forces camera states and hides Jak through a gameplay hook. No tracked hands, VR or optional toggle. See the staged plan below. |
| 7 | [Gordon And Daxter](https://github.com/mfOliveira19/GordonAndDaxter-Mod/blob/main/README.md) | Half-Life-style movement and weapons. | Useful reference for a camera-relative mesh pass. Its viewmodel renderer uses desktop OpenGL and would need a Metal implementation. Weapon/model provenance is unresolved; do not copy its assets into Dark Eco. |
| 8 | [Rainy Precursor Legacy](https://github.com/DaMaskV/Rainy-Precursor-Legacy/blob/main/README.md) | Rain, lightning, darker lighting/fog, storm ambience and texture changes in early Jak 1 areas. | Attractive on both flat screens and Vision. Evaluate weather code separately from textures and audio; measure rendering cost. Retail-named replacement textures have not been cleared for redistribution. |
| 9 | [The JET-Board Legacy](https://github.com/Hat-Kid/og-j1-board/blob/main/README.md) | Brings a Jak 3 jetboard into Jak 1 with eco interactions and launchers. | Appealing traversal experiment, with substantial model/animation/audio preparation. Determine whether required assets can be prepared from user-supplied data. The inspected release tag and metadata disagree: v0.0.6 versus 0.0.7. |
| 10 | [ArchipelaGOAL](https://github.com/ArchipelaGOAL/ArchipelaGOAL) | Connects Jak 1 to Archipelago multiworld randomization. | Largest integration cost here. Its [current setup](https://github.com/ArchipelaGOAL/Archipelago/blob/main/worlds/jakanddaxter/docs/setup_en.md) uses an external compiler and memory reader. Dark Eco would need a supported in-app communication path and network client instead. It is not directly compatible with the signed AOT app. |

These feasibility judgments are inferred from source, not device tests. The
repositories declare ISC licensing, but per-file and asset provenance still need
review. No retail assets, mod binaries or game data were downloaded for this
research. A source-tree inventory is not a full dependency or license audit.

## What incorporating a mod means

Dark Eco compiles GOAL/native code ahead of time into its signed app. Code mods
therefore need a reviewed source integration and a new app build. Downloading a
desktop mod bundle is not enough. Each inspected mod is a substantial OpenGOAL
fork; isolate its changes against the correct upstream base before porting it.

Compatible data-only changes can remain user-local data, provided the importer
and runtime support their format. That does not allow bundling retail-derived
textures, models, music or dialogue. Mod-specific save state should be isolated
from ordinary progress before any player-facing mode is released.

## Useful settings to expose next

The [official OpenGOAL settings guide](https://opengoal.dev/docs/usage/settings/)
documents these candidates. Native-menu access in this Dark Eco build still needs
verification; do not add a second conflicting setting store.

- **Subtitles and hint subtitles:** make both easy to find in Dark Eco settings.
- **Play hints:** retain the option for newcomers and let repeat players disable them.
- **Orb glow:** expose the existing visual preference if the current renderer supports it.
- **Original PS2 LOD/culling:** offer the upstream visual choices only after checking their effect on the Metal path.
- **Separate first- and third-person camera inversion:** useful when an optional first-person mode exists; verify how upstream options map to the app's current control settings.

Dark Eco already has frame-rate controls, additional stick dead zones, inversion
and touch cutscene skipping. Those are not new mods. The existing ProMotion
stutter remains a bug to fix, not a reason to add another frame-rate selector.

## First-person Jak with Sense-controlled hands

The existing [first-person camera source](https://github.com/OpenGOAL-Unofficial-Mods/First-person-jak/blob/cdcfea9622/data/goal_src/jak1/engine/camera/cam-states.gc)
and [game hook](https://github.com/OpenGOAL-Unofficial-Mods/First-person-jak/blob/cdcfea9622/data/goal_src/jak1/engine/game/main.gc)
provide a reference, not a ready VR implementation. The prototype hides Jak and
changes camera transitions. Later commits fixed an earlier swimming workaround;
the obsolete workaround should not be mistaken for its current behavior.

The proposed stages are:

1. **Optional first-person camera.** Start with Jak 1. Keep third-person as the default and preserve pause, cutscene, swim, death and vehicle transitions. Reuse Dark Eco's existing late headset-pose composition without applying head motion twice.
2. **Tracked controller markers.** Use original synthetic geometry to prove the coordinate conversion from Sense tracking to game/world/view space. Dark Eco already receives accessory poses for its gesture controls.
3. **Jak's visible hands.** Inspect the user-extracted model, skinning and bone mappings. Whether hands can be separated cleanly or bones overridden per instance is not established yet. A rigid mesh attached to each controller is a smaller experiment than animated arms.
4. **Arms, IK and interactions.** Blend tracking with Jak's animations, then define how punches, ledges, swimming, collision and attacks behave. Visual hand tracking alone does not implement these systems.
5. **Jak II later.** Port the validated approach separately to its camera and character code. Preserve ordinary DualSense play and third-person behavior.

An initial mode should be off by default. Comfort, head movement near geometry,
turning and transition behavior need actual headset evaluation. None of these
stages is implemented by this research, and none is a prerequisite for ordinary
Jak II play.

## Evidence boundaries

Primary code, READMEs, small release metadata and repository licenses were read.
Catalog-only claims are identified in the table and ledger. No mod was compiled,
run, imported or tested on Apple hardware. Missing base-diff, renderer, asset,
save-format and input details are explicit next tasks, not compatibility promises.
