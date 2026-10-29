# Jak II Kor encounter: build 272 checkpoint

The reported slowdown occurs approaching Kor and the child after the fortress,
and continues while standing nearby. A separate Dark Jak crash was recovered
from the maintainer's iPad Pro. This checkpoint fixes two demonstrated code
problems and adds a diagnostic for a remaining render rejection. It does not
establish that the encounter is fixed on physical devices.

## Code changes

- AOT static/function lookup now indexes owned object tags instead of scanning
  every loaded file. The index preserves load, link, forget and reset behavior.
  Synthetic public-API tests cover registry growth and shifted entries.
- The combo tracker now uses the compiler's boxed-array stack constructor.
  Its previous manual construction reserved 128 bytes for an array whose
  constructor clears 144 bytes. This matches the recovered stack-buffer
  failure in `combo-tracker-method-13`, called from Dark Jak.
- The scene-preview flag has an early declaration in `progress-h.gc`.
  Complete source regeneration otherwise failed because `scene.gc` references
  the flag before `progress.gc` defines it.
- An optional shadow diagnostic records the first failed live preflight,
  including a bounded DMA walk beyond the existing transfer-table limit.
  `GOALPAD_JAK2_DEBUG_DIAGNOSE_SHADOW195=1` enables it for one host lifetime.
  It does not change acceptance, shader behavior or rendering limits.

## Validation

The existing `jak1-aot-execution-test` plus additive public-API checks passed
against both the original and indexed loader. With 400 loaded tags and two
million last-tag queries, the synthetic static lookup changed from 642.78 ns
to 7.25 ns. This is a lookup measurement, not a game frame-rate claim.

An AddressSanitizer fixture executed the actual emitted combo-tracker and
array-constructor bodies. The original body failed with a 144-byte stack
write. The regenerated boxed-array body passed without changing its emitted
storage declaration or function body in the fixture.

All 840 Jak II objects regenerated: 18,493 emitted functions and seven native
implementations. Only `trajectory`, `scene` and `progress` objects changed.
The recorded source-pack aggregate is now `368b12c9d2c123bc`; the verifier and
source-pack tests, including the real generated pack, passed. The Jak 1 pack
is unchanged. Existing prepared game data does not need reimporting for this
code change: the runtime supplies registered native code/statics by object
name while retaining prepared game assets.

The shadow capture, plan and new diagnostic CPU tests passed, 3/3. The complete
Release iPad simulator app compiled as build 272. In-place simulator installation
preserved the original six save banks and the separate copied test banks.

Primary commands, from the application repository:

```sh
cmake --build OpenGOAL/build/Release/bin --target jak1-aot-execution-test --parallel 2
GOALPAD_AOT_LOOKUP_BENCHMARK=1 OpenGOAL/build/Release/bin/game/jak1-aot-execution-test
ctest --test-dir OpenGOAL/build/Release/bin --output-on-failure \
  -R '^(jak2-shadow195-diagnostic-test|jak2-shadow-bucket195-(capture|plan)-test)$'
Scripts/verify-generated-aot.sh Generated/jak2-aot 840
OpenGOAL/build/Release/bin/goalc/jak2-source-object-pack-verify \
  "$PWD/build/jak2-source-object-pack" --expected-aggregate 368b12c9d2c123bc
```

## Remaining

The original simulator encounter dropped 698 render chains during Kor's
cutscene. One observed shadow packet reached the 256-transfer limit before
the next bucket boundary. Its exact plan rejection is still being investigated;
no capacity increase is justified by this checkpoint alone.

Build 272 is a simulator investigation checkpoint. The matched encounter replay,
complete Dark Jak battle, signed device package and physical acceptance remain
pending. Jak II immersion has not been added. The separate Jak 1 sky-fix build
271 remains preserved for its deferred headset trial.
