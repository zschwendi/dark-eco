# Build 281 renderer checkpoint

Compiled app: `23c551c054f056f5d7c70018406fecb38750491a`.
Native engine: `7d513d61d6014e869d974a687318d18ddb5754b3`.

## What changed

`shaders/generic.metal` corrects only Generic WARP framebuffer sampling. The
OpenGL coordinate addresses a bottom-up framebuffer copy; the Metal snapshot
is a plain top-down copy. Converting that coordinate to top-down removes the
vertical mirror while retaining the scissor adjustment. Non-WARP sampling,
geometry, blend, depth and fog behavior are unchanged.

`metal_jak2_gmerc_warp317_renderer_test.mm` now uses distinguishable top and
bottom image bands with expected colors derived from visible source rows.
The previous expectation encoded the mirrored image. The artifact-isolated
matrix gave:

| Test | Old shader | Corrected shader |
| --- | --- | --- |
| Previous test | Pass | Fails 2 image expectations |
| Corrected top/bottom test | Fails 3 image expectations | Pass |

This establishes a sampling defect and correction. It does not establish that
the screenshot's dark water plane or long coloured streaks share that cause.
The physical water issue [#13](https://github.com/zschwendi/dark-eco/issues/13)
remains open.

`metal_jak2_glow_final_flare_proof.mm` adds two adjacent texture indices with
different dimensions and color channels through the production upload planner,
texture pool and glow renderer. Final pixel readback checks distinct colors,
dark edges and absence of cross-texture leakage. It passes: this test does
not reproduce or fix the actual taillight blocks in
[#7](https://github.com/zschwendi/dark-eco/issues/7).

## Integrated checks

The canonical host build ran these commands successfully:

```sh
cmake --build <host-build> --target jak2-metal-gmerc-warp317-renderer-test jak2-metal-glow-final-flare-proof -j 2
ctest --test-dir <host-build> -R '^jak2-metal-(gmerc-warp317-renderer-test|glow-final-flare-proof)$' --output-on-failure
cmake --build <host-build> --target jak2-metal-generic2-renderer-test jak2-gmerc-warp-bucket317-plan-test -j 2
ctest --test-dir <host-build> -R '^(jak2-metal-generic2-renderer-test|jak2-gmerc-warp-bucket317-plan-test)$' --output-on-failure
```

Both CTest invocations passed 2/2. Existing missing-publication, source-order,
coverage/depth, fog, texture-handle reuse and resize/cleanup checks remain.
The focused compile reports existing macOS 27 managed-storage/synchronization
deprecations; they were not suppressed.

The `GOALPad` Release scheme built for generic iOS, iOS Simulator, macOS and
visionOS with two jobs. iOS was development-signed; the other targets were
compile/link checks with signing disabled. No simulator app was launched or
used for gameplay/performance validation in this checkpoint. A visionOS
compile of this ordinary-play source is not a build of the separate immersive
lineage.

The input app passed strict signature verification and both source-pack
verifiers (Jak 1: 518 objects; Jak II: 840). Independent IPA readback verified
1,432 files, ZIP integrity, no private provisioning/entitlements, transport
signatures, and unchanged executable/framework code and data sections.
The recipient must re-sign the public package. Anonymous public download,
checksum and provenance readback passed; the public guide points to this
release. [Delivery receipt](BUILD281-DELIVERY.json).

## Retained work and limits

Build 280 importer and presentation changes are retained. Importer source
paths are unchanged; its Duo picker tests were not repeated or represented as
Build 281 tests. [Build 280's known baseline source-text check failures](BUILD280-VALIDATION.md)
remain documented; this checkpoint does not claim the entire suite is green.

No physical Build 281 installation or gameplay acceptance occurred during
this checkpoint. ProMotion, real taillights, remaining water artifacts and
cutscene video freezing remain open. Fit to Screen and the pause-background
candidate still need physical acceptance.

The cutscene investigation found no source-proven defect. Existing scene,
animation, wait and stream diagnostics are emitted through the device console,
not the Files timing export. A short authorized capture around the affected
scene is the next discriminator; missing records alone do not prove a stall.

Jak 1 immersive effects, HUD and sky remain unconfirmed in
[#3](https://github.com/zschwendi/dark-eco/issues/3). The separate signed Vision
271 candidate and public Vision 264.1 download differ from this iOS source.
[#16](https://github.com/zschwendi/dark-eco/issues/16) records the integration
and public source/delivery gap. No wholesale merge or speculative projection
change was made.
