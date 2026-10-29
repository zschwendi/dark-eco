# Jak II and upstream integration handoff — October 28, 2026

The active app is **Dark Eco** (`zschwendi/dark-eco`). `zschwendi/jak-pad`
is its OpenGOAL engine dependency. Both repositories are public. Existing
engine links route app users and coding agents to Dark Eco. Do not rename them.

## Priority and ownership

Finish ordinary Jak II playability before adding immersion. The immediate
player blocker is sustained slow motion near Kor and the child after the
fortress, including while standing nearby. Verify the separate Dark Jak
crash fix too. Zach wants a notification when a verified test build is ready.
Do not describe physical performance as fixed from simulator evidence.

The handoff branch in both repositories is
`handoff/mac-mini-astra-20261028`. This is a development checkpoint; it is not
a release or a completed Build 274. Read `AGENTS.md`, `docs/PROJECT_OVERVIEW.md`
and `docs/BUILDING.md` before changes. Use one integration/heavy-build owner.
Bounded Claude Code Opus 5.5 workers are preferred when a working Max session
is available. Preserve existing Apple ports, saves and separate Vision work.

## Source identity

- App implementation checkpoint: `b71ac13a8c96f2e80b8e399656507364f9645fd0`.
- Engine: `f391f168e10ab4044d6056d4c2b8f98d2a0703c6`.
- Integrated upstream: `94684e32f60008d3d9617621e7c3a478c9e2af56`.
- Last compiled simulator baseline: Build 273, engine
  `3749f2c5ca60ce1c786eb6a8ab101d60d527c07b`.
- Build 274 is reserved for the upstream integration. Its nested Jak II target
  succeeded, but the outer build was interrupted while compiling Jak 1.
  There is no whole-app Build 274 success or signed device package yet.

## Tracked remaining work

| Issue | Current evidence and next acceptance gate |
| --- | --- |
| [#1: Kor encounter slow motion](https://github.com/zschwendi/dark-eco/issues/1) | Indexed AOT tag lookup and source-derived Shadow195 limit fixes exist. A normal Build 273 copied-save replay held 60 game ticks/submissions per second through the Kor intro, without rejected chains. Replay Build 274, approach and remain nearby, then obtain device confirmation. |
| [#2: Dark Jak crash](https://github.com/zschwendi/dark-eco/issues/2) | Actual combo-tracker stack overwrite reproduced and corrected; regenerated method passes ASan. Ordinary Dark Jak gameplay remains unverified. |
| [#3: Jak 1 immersive effects/HUD/sky](https://github.com/zschwendi/dark-eco/issues/3) | Separate signed Vision Build 271 awaits wearer confirmation. Do not call this solved or overwrite that lane. |
| [#4: Jak 1 renderer teardown](https://github.com/zschwendi/dark-eco/issues/4) | Separate old crash in Metal ocean-renderer destruction; not the Dark Jak failure. Current reproduction pending. |
| [#5: Build 274 validation](https://github.com/zschwendi/dark-eco/issues/5) | Finish app build, ordinary-save replay and generic signed package; record exact identities and remaining device gates. |

## Validated at this checkpoint

- Host compiler, C backend, runtime ABI tools and extractor build.
- 16 focused AOT/ABI/CBackend/source-graph tests.
- 166 synthetic ARM64 emitter, raw trampoline, cache, sky and CodeTester tests.
- Both generated AOT corpora: Jak 1 has 518 objects and 10,632 emitted plus
  seven native functions; Jak II has 840 objects and 18,494 emitted plus seven
  native functions. Both have zero source-generation failures.
- Both source-pack recorded/matching identities and wrong-identity rejection;
  pack fixtures and the real Jak II pack oracle; regenerated Dark Jak ASan case.

Pack identities are Jak 1 `806abc2b2667435a` (10,768,267 object bytes), and
Jak II `f2cdf82e9b913501` (21,217,652 object bytes). Generated user-local inputs
and private saves/crash reports remain outside Git.

The broad desktop JIT `WithMinimalGameTests` run still SIGBUSes after linking
`gcommon`. This is retained evidence, not a passing desktop JIT suite. The
focused synthetic/AOT passes do not resolve it. Full merge whitespace checks
also report 355 files whose blobs exactly match upstream; scoped changed-file
checks pass. Do not suppress failures or mass-format imported upstream code.

The Build 273 Kor snapshots reached 221 shadow transfers; they did not prove
that a packet above the old 256 limit was exercised. No actual Dark Jak
transformation, mission completion or physical performance pass is claimed.

## Next executable steps

1. Inspect live source/process/resource state before starting a build. Preserve
   the stable checkpoints and all existing worktrees. The previous integration
   required absolute per-worktree `core.worktree`; verify the actual Git top.
2. Read the private evidence index supplied through AstraBoard. Reuse the
   verified generated inputs or regenerate them through the existing scripts;
   never reuse machine-specific build caches from another Mac.
3. Finish Release simulator Build 274 and replay the ordinary copied save,
   approaching and standing near Kor, then trigger Dark Jak. Use the approved
   isolated simulator and preserve original banks/settings around testing.
4. Produce and verify a generic signed iOS package, its build number and source
   identity. Physical installation/launch requires the maintainer's current
   authorization; earlier read/copy permission is not installation permission.
5. Report a ready **test build** with exact remaining device gates. Preserve
   the pending Jak 1 Vision lane. Promote stable branches only after their
   affected build/runtime gates pass; do not equate upstream sync with a fix.

The outgoing MacBook simulator's original six banks and exact settings bytes
and modification time have been restored; copied test progress is archived
privately. The simulator is shut down. No physical device was accessed during
handoff preparation.
