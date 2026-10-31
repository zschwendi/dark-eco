# Build 280 validation

Build 280 is an experimental iPhone/iPad test package, not a complete-game or
120 Hz acceptance result. It was compiled from app
`75cd02ebc4097bd851a8b18482d789bf5d38f1f1` and engine
`2154f2c3904242a6a41ed56bfaae6556c1497862`.

## Changes

- `GameDataImportSource.swift` and `GameDataSetupView.swift`: broaden Files
  picker selection without relaxing subsequent format/content validation.
- `GameSession.swift`: apply saved Fit to Screen when either title starts.
- `EcoJak2RuntimeBridge.mm`: use internal render dimensions for Jak II's
  pause-background sampling.
- `GameSurfaceView.swift`, `GameplayLifecycleState.swift` and
  `ContentView.swift`: stop unused display callbacks while preserving the
  attached game surface needed for startup.
- Native `jak2_import_composer.cpp`: refresh four stale resource size/hash
  entries. Resource closure, size and XXH64 validation remain required.
  Composer tests cover drift, same-size corruption, size changes and missing
  resources. No retail assets are used in these tests.

## Build and check results

The `GOALPad` Release scheme built successfully for generic iOS, iOS
Simulator, macOS and visionOS, using two jobs. iOS was development-signed;
the other three builds used `CODE_SIGNING_ALLOWED=NO`. macOS and visionOS
were compile/link checks, not runtime tests. The public IPA is an iOS device
build, stripped of maintainer provisioning and transport-signed with empty
entitlements for the recipient to re-sign.

These focused commands passed:

```sh
sh Scripts/run-game-data-import-source-check.sh
sh Scripts/run-game-data-import-lifecycle-check.sh
sh Scripts/run-game-data-import-presentation-check.sh
sh Scripts/run-presentation-geometry-check.sh
sh Scripts/run-native-runtime-router-check.sh
sh Scripts/run-presentation-settings-check.sh
swift Scripts/selected-session-routing-check.swift .
sh Scripts/run-input-frame-delivery-check.sh
```

The native composer test was configured with
`OPENGOAL_BUILD_JAK2_IMPORT_COMPOSER_ONLY=ON`, `BUILD_TESTING=ON`, Release
and Ninja. Building target `jak2-import-composer-test` succeeded;
`ctest --test-dir <build-dir> -R '^jak2-import-composer-test$' --output-on-failure`
passed (1/1). Real-disc oracle environment variables were not enabled.
The actual XXH64 validator also matched all 29 pinned project resources in
both final iOS and simulator bundles.

Two existing check wrappers still return failure; this is **not an all-green
test suite**. They were not disabled or rewritten to hide their results:

- `sh Scripts/run-game-lifecycle-check.sh`: the executable lifecycle checks
  pass, but two baseline source-text assertions fail: bounded diagnostics
  overlay cadence and opt-in display cadence/logging.
- `sh Scripts/run-promotion-frame-rate-check.sh`: the baseline source-text
  assertion about independent iOS/visionOS high-refresh preferences fails.

## iPhone Duo importer test

On an isolated iPhone Duo simulator running iOS 27.1, actual Files UI
selection accepted both an ISO and a ZIP for each title: Jak 1 with the Duo
closed and Jak II with it open. All four cases reached the expected rejection
of deliberately invalid synthetic disc data. No game-data files were activated;
Play Now remained disabled. The simulator was shut down afterward.

The first Jak II replay uncovered a separate stale resource-validation table.
After the native correction and rebuild, both Jak II cases passed that stage
and reached the disc validator. This defect affected the signed iOS bundle
too; it was not specific to Duo hardware.

This verifies selection and negative validation paths with the simulator's
local Files provider. It does not establish a hardware-specific explanation
for the recipient's greyed-out files, test their storage provider, or certify
complete preparation of a valid retail disc. Recipient issue
[#9](https://github.com/zschwendi/dark-eco/issues/9) remains open.

## Package checks

The signed input passed strict signature and source-pack checks (Jak 1: 518
objects; Jak II: 840 objects). Independent readback verified all 1,432 public
bundle files, ZIP integrity, absence of private profiles/entitlements and
unchanged executable/framework code and data sections after transport signing.
The release includes provenance, `SHA256SUMS`, `PACKAGE-MANIFEST.json` and
`INDEPENDENT-PACKAGE-CHECKS.json`.
The anonymous public download matched the local IPA SHA-256 and public
checksum; provenance and the public guide were read back successfully.
[Delivery receipt](BUILD280-DELIVERY.json).

## Still pending

Build 280 has not been installed or tested on physical hardware in this
checkpoint. Fit to Screen in both titles, Jak II's pause background and cold
Library smoothness need physical acceptance. No simulator gameplay or
performance testing was performed.

ProMotion [#6](https://github.com/zschwendi/dark-eco/issues/6) remains
unresolved. The idle-loop change does not change active-game 120 Hz work.
Build 279's accepted Jak II loading-chamber improvement is retained, but that
feedback does not certify all of Jak II or the new package. Water, taillight,
cutscene and internal-resolution issues remain separately tracked.
