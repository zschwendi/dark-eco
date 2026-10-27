# Jak II pause snapshot orientation — October 26, 2026

Status: **Implemented and validated for the exercised iPad simulator path. Physical acceptance and other scenes/resolutions remain pending.** This is a conventional windowed rendering correction. Jak II immersive work remains deferred.

## Problem and change

The pause ring and its text remained upright while Jak and the world behind them appeared upside down. The source-shaped menu sprite samples PC-BLIT using OpenGL framebuffer coordinates. Metal's snapshot preserves the top-down target row order.

For Jak II's PC-BLIT texture only (TBP `0x3300`), the Direct renderer now reverses the sampled V coordinate against the actual bound texture height. Pixel UV mode uses `16 * height - t`; normalized STQ uses `q - t`. Other textures, placeholder fallback and Jak 1 retain their existing path. This belongs beside Direct's snapshot texture binding because the app shell cannot change these per-batch sampling coordinates.

Native source checkpoint: `28116b31df2309e9431dfa56816f88cde01a77d1` on `v2.0`.

## Evidence

A controlled comparison used the same preserved Game 2 save, unchanged player position and initial camera, and the same Missions menu on the isolated iPad Pro 11-inch M5 simulator running iPadOS 26.5. The two binaries differed only by the presence of the mirror block; both included identical default-off diagnostic additions enabled for observation.

| Simulator build | Mirror | First ring/page | Second ring/page |
| --- | --- | --- | --- |
| 256 | enabled | upright / upright | upright / upright |
| 257, negative control | removed | inverted / inverted | inverted / inverted |

The second entry followed a verified interval of resumed ordinary play. Captures were taken after the initial copy-back frames and after the submenu settled. Jak's head/feet, the overhead red apparatus and floor vents make orientation unambiguous. All five existing savebank hashes stayed unchanged through the updates. Build 256 was restored after the comparison; the negative control is not the intended source state.

Live post-gap metadata confirmed primary `sky-draw`, UV mode, a real 640×480 snapshot lookup and the expected enabled/disabled mirror branch. Those bounded records landed on the strip batch, not the full-screen quad. The full-quad coordinate records were from title menus; they are not presented as later gameplay metadata. The matched visual comparison supplies the causal evidence for the tested pause path.

The earlier report of a later flipped state was not reproduced in this matched comparison. Its precise cause remains unresolved; it does not override the current scoped evidence, and broader acceptance is not claimed.

## Deterministic checks

The authored four-quadrant GPU fixture uses the source's descending-V sprite. It checks every corresponding quadrant and the existing descending-ST lifecycle. Two additional UV cycles cover `SnapshotThenCopyBack → CopyBack → None`, with a different world on the second capture. Steady frames must have no copy-back, and must reject both inversion and a stale earlier snapshot. The pixel comparison assertion was independently checked with a small CPU proof before integration.

From `OpenGOAL`:

```sh
cmake --build build/Release/bin --target jak2-metal-blit-display-spatial-test --parallel 2
ctest --test-dir build/Release/bin -R '^jak2-metal-blit-display-spatial-test$' --output-on-failure
```

Both passed on the Mac GPU. The native application builds for simulator 256 and 257 also passed. A generic iOS Release compile (build 258, signing disabled) passed in 33.16 seconds; it did not access a physical device. Full command arrays, source-diff hashes, executable identities, screenshots and save-preservation receipts remain in the ignored local playability artifacts.

## Remaining work

This proves one ordinary saved-game pause path, including repeat entry. Other levels, resolutions and physical devices remain unvalidated. Mission completion and saving/reloading after progression remain open. The map page showed a collapsed scroll without a map in the tested opening state; its cause is not diagnosed here.

Vision Pro remains on signed Build 254, which does not contain this pause correction. The separate Vision source tree has not yet received this checkpoint. No new headset install or Jak II immersive implementation was performed for this correction.

The temporary UV/copy and player-position diagnostics remain separate uncommitted investigation work. They are default-off and are not part of the native commit above.
