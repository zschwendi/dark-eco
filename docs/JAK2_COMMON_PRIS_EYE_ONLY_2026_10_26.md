# Jak II common PRIS eye-only update (AI-assisted)

Status: **Implemented and validated in the isolated iPad simulator; physical confirmation remains pending.** The maintainer handles broad gameplay verification. This change addresses the known ordinary rendering rejection before Jak II immersion work; no immersion is added.

## Reproduction and source evidence

Isolated simulator app265 loaded Game4 in prison, opened the Fortress map, and returned through Resume. Exactly one chain failed at tick19023: bucket220 had57 valid scalar transfer records, no malformed transfers. It contained opening NEXT, two27-record eye chunks, a FLUSHA/DIRECT10 reset and terminal NEXT. The old planner required an ordinary-texture/Dark-Jak prefix and accepted only9/36/63 records. The world recovered on the next frame, explaining the intermittent rather than persistent symptom.

Public source emits eye work independently in `goal_src/jak2/engine/gfx/foreground/eye.gc` (update-eyes and with-dma-buffer-add-bucket). `texture/texture-h.gc` maps default-level PRIS to tex-lcom-pris. The texture prefix is conditional on src-level/texture-enable and a valid tpage in `texture/texture.gc`; animator emission is also conditional. The exact menu predicate that suppressed this prefix was not captured and is not claimed. The observed eye packets still match the existing exact source-shaped eye decoder.

## Change and files

- `metal_jak2_common_tfrag_texture_upload_capture.{h,cpp}`: explicit ordinary/animator-prefix presence, exact57 eye-only grammar, existing eye validation and owned semantic comparison. This variant reads no live texture-page memory; malformed packets and unobserved30/58-record variants stay rejected. Original9/36/63 forms retain their checks.
- `metal_bucket_renderer.mm`: consumes descriptor/animator records only when present, then uses the existing eye renderer and strict reset/boundary checks. Its existing host callback still runs exactly once for every bucket form.
- `metal_jak2_host_bridge.mm`: skips absent ordinary/CLUT preparation and commitment. The separately committed default-off scalar diagnostic remains bounded to two records and64 headers.
- CPU capture and Metal eye renderer tests: positive57, copied/reset/prefix mismatch and malformed controls; existing forms; actual GPU consumption of the eye-only packet. The first GPU run caught manual legacy fixtures missing the new explicit prefix flag. Those fixtures now specify their existing envelope, with every original assertion retained, and a new57-case verifies four eyes,16 draws,32 triangles,two completed command buffers and no missing textures/errors.

This belongs in OpenGOAL because that code owns DMA parsing, texture execution and the renderer cursor. No dependency, generated pack, retail asset or save was changed.

## Validation

From canonical OpenGOAL:

```sh
cmake --build build/Release/bin --target goalpad-jak2-metal-host jak2-common-tfrag-texture-upload-capture-test jak2-pris2-bucket228-plan-test --parallel 2
cmake --build build/Release/bin --target jak2-metal-eye-renderer-test --parallel 2
MTL_DEBUG_LAYER=1 ctest --test-dir build/Release/bin -R '^(jak2-common-tfrag-texture-upload-capture|jak2-pris2-bucket228-plan|jak2-metal-eye-renderer)-test$' --output-on-failure
```

Builds passed; final tests passed3/3 in0.68seconds. The earlier diagnostic/audio checkpoint also passed3/3, including `jak2-sound-rpc-test`; installed user data contains nonempty English dialogue index and493027328-byte English pack. These are bounded sound/data checks, not proof every voice or level was heard.

`git diff --check` passed. Exact commands, first failures, signed/source identities and screenshots are kept outside Git in `.agent-builds/jak2-playability-20261026/`.

Build 266 (outer `9cf41098`, OpenGOAL `0ac5b269`) also built successfully in Release for the approved isolated iPad simulator. The app loaded the preserved Game 4 save, displayed the complete Fortress map and player arrow, and returned through the native Resume control to the upright prison world twice. Runtime samples through tick 27002 reported zero failed chains and no plan-rejection records. Four screenshots and `pris266-map-replay-result.json` preserve the result. The first attempt was interrupted by inaccessible simulator controls while the large diagnostic overlay was enabled; it did not establish an app rendering failure. The successful replay used the ordinary presentation with that overlay disabled.

## Remaining scope

The reproduced map-return gate is closed within this simulator scope. Physical-device confirmation and the maintainer's broader gameplay pass remain separate. No full-game, later-level or physical-device rendering claim follows from the synthetic checks or these two transitions.
