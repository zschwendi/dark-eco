# Jak II map upload and save checkpoint (AI-assisted)

Status: **Experimental; runtime map correction incomplete.** Ordinary Jak II remains the active playability task. No Jak II immersive implementation was added.

## Problem and scoped implementation

Opening the Fortress map rejected bucket 319 at its initial four-qword GS setup. A bounded scalar-only capture identified four indexed map layers interleaved with drawing commands and two ordinary texture uploads. The old planner supported only the ordinary uploads.

Native `62ec96b900777af9a3e0128c3a56b712e8354c18` adds:

- An owned, strict four-layer non-city planner and ordered cursor, retaining the legacy ordinary-only route.
- A copied-chain validator that compares tags, VIF and payloads before reparsing embedded EE pointers.
- A 512×208 CSM1 palette decoder, preserving channels, alpha and row order.
- Four distinct Metal texture publications, with explicit preparation and pool cleanup.
- Synthetic CPU tests and a GPU readback test using four draws in each of two pending frames. Earlier draws retain their own image after the registry is updated.

Image, palette and ordinary-page pointers in the new mixed planner reject the protected EE region before dereferencing. Owned count guards precede array traversal. No retail data or image capture is included in these tests.

Native `e8810955c4f0ec69a46b00160401fb9feac8b6d2` records separately validated, default-off playtest diagnostics. Flags are `GOALPAD_JAK2_DEBUG_LOG_MAP_CHAIN=1`, `GOALPAD_JAK2_DEBUG_LOG_PC_BLIT=1` and `GOALPAD_JAK2_DEBUG_LOG_PLAYER_POSITION=1`. The map capture logs at most 64 scalar transfer records once per process; it does not dereference image payloads or their embedded pointers.

## Validation

Commands ran from `OpenGOAL` with the existing Release cache:

```sh
cmake --build build/Release/bin --target jak2-map-texture-upload-plan-test jak2-map-layer-convert-test --parallel 2
cmake --build build/Release/bin --target jak2-map-layer-executor-readback-test jak2-sprite-texture-upload-plan-test jak2-metal-fog-texture-convert-test --parallel 2
cmake --build build/Release/bin --target jak2-map-copied-plan-test --parallel 2
cmake --build build/Release/bin --target goalpad-jak2-metal-host jak2-map-layer-executor-readback-test --parallel 2
MTL_DEBUG_LAYER=1 ctest --test-dir build/Release/bin -R '^jak2-(map-texture-upload-plan|map-copied-plan|map-layer-convert|map-layer-executor-readback|sprite-texture-upload-plan|metal-fog-texture-convert)-test$' --output-on-failure
```

All builds passed; the final suite passed 6/6 in 0.59 seconds. Existing shared/upstream warnings remain visible. The first broader CTest invocation included two control executables that had not been built; both new CPU tests passed. Building those controls resolved that test setup failure. Worker sanitizer tests also passed after correcting an owned-count overrun found during review.

The subsequent host integration compiled for macOS and as simulator app 261. Its source identity was outer `007c5cc`, native `e8810955c` plus integration diff SHA256 `43199df3bdcbb1ad84c1fbdb0a27dae44c25ec30b6f205bec23195ddda825959`. The simulator Release build used scheme `GOALPad`, two jobs, signing disabled, and the dedicated isolated simulator; Xcode reported success in 64.410 seconds. Exact invocation and receipts are retained in the ignored `jak2-playability-20261026` artifacts.

## Actual simulator observations and limits

App 261 drew the four-layer Fortress map. A later icon-bearing frame introduced three additional DIRECT records, producing a complete 39-transfer capture. The planner deliberately did not support that form and rejected it. **The first map image is not acceptance of a working map or repeat entry.** The icon parser extension is the next bounded implementation task. Host wiring remains an unaccepted integration patch at this checkpoint.

During ordinary app 260 play, the first stacked crates and raised vent passage were traversed with normal controls. A new save was written to the previously empty Game 4 slot. A cold app launch loaded Game 4 and accepted movement. The five original save files remained byte-identical; installing app 261 also preserved all six files. This was an early prison continue at 0% completion, not a completed escape mission or later checkpoint.

No physical iPad was accessed. City maps, additional icon forms, later missions, sustained performance, and physical-device playability remain unvalidated. Jak II immersion stays deferred. The separate Vision Pro build 259 and Jak 1 sky investigation are independent of this simulator checkpoint.
