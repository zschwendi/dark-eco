# Jak 1 mod inventory for Dark Eco Modern

**Status: Investigating.** This is a source and distribution inventory, not an iPad compatibility list or a promise to support a mod. It is limited to primary project/mod sources available on 2026-08-06.

## Pinned-source caveat

GOALPad's OpenGOAL submodule is pinned independently of the desktop launcher and community mod repositories. The catalogues below generally identify a release date, but do not state compatibility with GOALPad's exact pinned source or its signed ARM64 AOT object pack. Treat every candidate as incompatible until it is rebased, built, and tested against the current pin.

## Upstream settings are not mods

The pinned Jak 1 source already contains upstream PC-setting paths for display fit/aspect, frame-rate choices, MSAA, level of detail, subtitles/text languages, camera options, accessibility options, speedrunner mode, and mirrored world. Describe these as **upstream-native settings** when and only when their iPad implementation is validated. Do not call existing presentation or quality controls "Dark Eco Modern mods."

The official OpenGOAL launcher documentation says third-party mods are not vetted by the OpenGOAL team and can execute arbitrary code. It also says the project does not promote HD texture packs because scaled or cleaned original textures are derivative game assets. See [OpenGOAL FAQ](https://opengoal.dev/docs/faq/).

## Third-party candidates

Dates are the last verifiable public catalog/release signal, not a confirmed current release. `AOT review` means: obtain an authorized source revision, audit its license and non-retail asset provenance, rebase it to the pin, regenerate the signed source/AOT pack, then validate on physical iPad. None is currently an approved GOALPad bundle.

| Candidate | Primary source and last verifiable date | Observed form / license status | Classification |
| --- | --- | --- | --- |
| Speedrun Practice | [OpenGOAL-Mods repo](https://github.com/OpenGOAL-Mods/OG-Speedrun-Practice), Jak 1 catalog date 2022-10-23 | GOAL/gameplay source in a full mod-base tree; ISC repository license | **AOT review** |
| Checkpoint Randomizer | [OpenGOAL-Mods repo](https://github.com/OpenGOAL-Mods/OG-Randomizer), 2022-08-28 | GOAL/gameplay source in a full mod-base tree; ISC repository license | **AOT review** |
| Orb Hunt | [dallmeyer repo](https://github.com/dallmeyer/OG-OrbHunt), Jak 1 catalog date 2023-01-05 | Gameplay/source mod; asset and exact-pin compatibility not audited | **AOT review** |
| Gordon and Daxter | [MFO repo](https://github.com/mfOliveira19/GordonAndDaxter-Mod), 2026-02-05 | GOAL movement/gameplay modification; license not verified here | **Uncertain, then AOT review** |
| JET-Board Legacy | [Hat-Kid repo](https://github.com/Hat-Kid/og-j1-board), 2026-05-27 | GOAL gameplay modification; license/provenance not verified here | **Uncertain, then AOT review** |
| J1 Guy's Chaos | [this-guy-git repo](https://github.com/this-guy-git/JGChaos), 2025-12-21 | GOAL random-effect gameplay modification; license not verified here | **Uncertain, then AOT review** |
| Spec Ops Jak | [Ruh repo](https://github.com/ruhphorte/spec-ops-jak), 2024-07-23 | Gameplay plus visual/outfit/weapon changes; asset provenance and license not verified | **Blocked on provenance; not data-only** |
| ArchipelaGOAL | [ArchipelaGOAL repo](https://github.com/ArchipelaGOAL/ArchipelaGOAL), 2024-05-22 | Randomizer integration with external-service/runtime concerns | **Not MVP; requires separate network and AOT review** |
| TeamRuns | [TeamRuns site](https://teamruns.web.app/), 2024-06-05 | External multiplayer listing; standard catalogue exposes it as an external link | **Not MVP / unverified runtime** |
| The Forgotten Lands | [Kuitar5 repo](https://github.com/Kuitar5/the-forgotten-lands), 2023-01-08 | Custom levels plus gameplay/source changes | **AOT review** |
| Jak Up | [dallmeyer repo](https://github.com/dallmeyer/jak-up), 2023-08-10 | Multi-level custom-content/gameplay package | **AOT review; not an initial app-size candidate** |
| River to Water | [Cuttlefish repo](https://github.com/Cuttlefishthesage/OG-Mod-Base), 2024-06-04 | Custom-level source in a full mod-base tree; ISC repository license | **AOT review** |
| Rockpool | [Cuttlefish repo](https://github.com/Cuttlefishthesage/Og-ModBase-Rockpool), 2024-07-23 | Custom-level source in a full mod-base tree; ISC repository license | **AOT review** |
| Overgrown | [Cuttlefish repo](https://github.com/Cuttlefishthesage/LL-OpenGOAL-ModBase), 2024-09-26; visible release `v4.3.4` on 2024-09-28 | Custom-level source/full mod base; ISC repository license | **AOT review** |
| Glacier | [Cuttlefish repo](https://github.com/Cuttlefishthesage/OG-Mod-Base-Glacier), 2024-12-22 | Custom-level source in a full mod-base tree | **AOT review** |
| Yosemite | [OpenGOAL-Mods repo](https://github.com/OpenGOAL-Mods/OG-Yosemite), no reliable package date | Special build whose instructions require a `YOS.DGO`; required data provenance not verified | **Do not distribute; uncertain** |
| Snowy Legacy | [source repository](https://github.com/kekdeveloper/opengoal-mod-snowy-legacy), no end-to-end release in the catalogue | Texture/weather replacement; original-versus-retail-derived texture provenance not verified | **Blocked by provenance and texture policy** |

The discoverable JakMods source configuration is [OpenGOAL-Mods/jakmods.dev](https://github.com/OpenGOAL-Mods/jakmods.dev/blob/main/scripts/update-mod-source-data/config.yaml). It is a catalogue, not proof of quality, permissions, source-pin compatibility, or iPad support.

## Data-only and custom-level reality

No candidate above is presently verified as a user-importable, data-only FR3 package. The documented custom-level workflow starts from a mod base, edits GOAL and level definitions, and builds a DGO; it is not an established runtime-only iPad package format. See [Making Your First Level](https://opengoal.dev/docs/developing/custom_levels/your_first_level/) and the [custom-level introduction](https://opengoal.dev/docs/developing/custom_levels/intro/).

Custom geometry, textures, models, music, and levels need independent origin and license review. A source repository or an ISC notice for software does not by itself establish permission to redistribute every artifact in a release. This document makes no legal conclusion.

## Current MVP boundary

**Implemented/validated separately:** signed base-game AOT work and user-supplied base-game data are the only relevant content boundary.

**Planned:** expose validated upstream-native presentation and accessibility settings in the iPad experience.

**Investigating:** a fail-closed local manifest for original, data-only content that the runtime can load without executable GOAL objects. Do not add a remote catalogue, downloader, executable ZIP importer, REPL/hook path, or JIT path.

**Blocked:** executable GOAL mods need a maintainer-approved source revision, license/dependency review, non-retail asset provenance review, source-pack/AOT regeneration, normal Apple signing, and physical-iPad validation. Data-only mods need a defined extension format, compatibility validator, loader, and asset-provenance policy before any package can be supported.
