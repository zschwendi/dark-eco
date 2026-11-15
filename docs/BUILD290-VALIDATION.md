# Build 290 preview validation

Status: **published experimental Build 290 preview; platform, package and public-download checks passed**. This
record describes source and observed simulator evidence. It does not certify
physical-device compatibility or a complete playthrough.

## Compiled-source target and packages

- App: `76d3663a87686abfe578b924038a127c7956677d`.
- OpenGOAL engine: `d36fe150fc2c009db684e84cab20fa0f674b12b5`.
- Jak II public source pack: 840 objects, aggregate `4f3e512e091fae63`.
- Jak 1 public source pack: 518 objects, aggregate `c1e79fbb50f33437`.
- iOS asset: `DarkEco-iOS-2.0-build290-preview.ipa`.
- visionOS asset: `DarkEco-visionOS-2.0-build290-preview.ipa`.
- Release: `build290-preview`; publication/readback **published; all nine public downloads verified against their SHA-256 hashes**.

Both IPAs are separate platform builds from the shared source. Documentation
may be committed after compilation; provenance must retain the actual compiled
source above. The public Mac download remains Build 270.1. A new macOS compile
check does not replace that package or add its later fixes to it.

## Changes since public Build 286

- From private 287: the iPhone/iPad app-folder import alternative and Jak II
  1×–4× internal-resolution wiring. Jak II defaults to 1×; the obsolete ignored
  value is not reused. The alternative importer still validates the source.
- From private 288: upstream Jak II texture-remap wiring, short streamed-audio
  completion corrections, and safer Jak 1 renderer/texture-pool teardown.
  These are not blanket fixes for taillight appearance or cutscene freezes.
- In 290: exact handling of the authored ocean no-sky prefix and a corrected
  race-manager stack allocation. Authored mission-start smoke tooling and
  bounded numeric upload diagnostics support testing; diagnostics do not
  relax packet validation or silently skip unsupported work.

The race correction was checked with the actual emitted method under ASan:
old emission reproduces the overflow and corrected emission passes. The
focused ocean grammar tests pass. These tests do not establish renderer
appearance, full race completion or physical performance.

## Observed simulator coverage

| Run | Results | Scope |
| --- | --- | --- |
| Build 289b baseline | 48 starts: 33 PASS / 15 FAIL | 48 distinct primary environments |
| Build 290 targeted recheck | 12 starts: 7 PASS / 5 FAIL | Includes failed cases and controls |
| Build 290 remaining starts | 50 starts: 43 PASS / 7 FAIL | Remaining authored playable tasks |
| Latest result for each task | **98 starts: 81 PASS / 17 FAIL** | 36 retained 289b attempts plus 62 Build 290 attempts |

The merged result is **mixed-build evidence**, not 98 fresh Build 290 passes.
A PASS requires the requested authored task/continue, expected active level,
checked live target, a stable dwell, advancing runtime and submitted/completed
render work, no reported errors, three screenshots and unchanged copied save
manifests. These are short developer-mode mission starts, not mission or
campaign completions. They do not judge every effect or screenshot visually.
All 98 latest before/after save manifests match. All 81 latest passing starts
have a recorded review of their sampled stills. The [per-task matrix](BUILD290-MISSION-SMOKE.tsv)
contains the exact task, level, build and result without private captures or saves.

Both sewer starts now pass. Race class 1 and class 2 pass; class 3 survives the
previous stack abort but fails on a separate alpha bucket 157 rejection.
Both nest smoke starts use a recorded test-only correction to a pre-existing invalid
private fixture; original data is preserved and no product reader was relaxed.

The simulator omits the physical presentation callback. Advancing drawables,
submissions and completed commands are observed; zero callback drop counters
are not proof of no dropped frames or physical display performance. Ordinary
audio was used after the host audio service became available, but there was
no audible-output acceptance. The optional simulator manual-audio path mixes
then discards PCM and cannot establish audible or performance acceptance.
1× and 2× observations remain separate; the 98-task aggregate is the 1× run.

## Existing-data update check

Two isolated Build 290 starts, `sewer-enemy` and `stadium-race-class2`, passed
with the unchanged preserved Build 288 prepared data. The original data was
not modified; the current test fixture was restored afterward. No physical
device was used. Users do not need to re-import solely for this update or the
race fix. Keep installed game data, back up saves, and preserve the signing
identity/App ID where possible. This is not a guarantee for every older
import, signing provider, device, or save migration.

## Final release checks

| Check | Result |
| --- | --- |
| Release arm64 iOS compilation | **PASS (515.36 s)** |
| Release arm64 visionOS compilation | **PASS (500.49 s)** |
| Release arm64 macOS compilation | **PASS (330.20 s)**; no new Mac package |
| Packaged source packs and executable/source identity | **PASS: Jak 1 518 / c1e79fbb50f33437; Jak II 840 / 4f3e512e091fae63** |
| Both IPA archive integrity, transport signatures and entitlement/profile audit | **verified and included in the release** |
| Package sizes, SHA-256, complete manifests and provenance | **recorded and verified** |
| Public assets, hashes and independent download readback | **published; all nine public downloads verified against their SHA-256 hashes** |
| Exact final build/package command receipts | **recorded; see the commands and retained receipt locations below** |
| Physical-device install/gameplay/recipient signing acceptance | Not performed |

Package verification is separate from earlier private build checks. Public
artifacts contain no retail data, maintainer provisioning profile or
credentials; recipients supply their own supported game data and signing
identity. Entitlement/profile verification remains pending in the table above.

## Known limits

- Animated texture uploads: [#25](https://github.com/zschwendi/dark-eco/issues/25).
- Non-finite Merc bone diagnostic in a city challenge: [#29](https://github.com/zschwendi/dark-eco/issues/29).
- Construction-site eye uploads: [#28](https://github.com/zschwendi/dark-eco/issues/28).
- Changing resolution while already paused: [#11](https://github.com/zschwendi/dark-eco/issues/11).
- Water appearance: [#13](https://github.com/zschwendi/dark-eco/issues/13).
- ProMotion slowdown: [#6](https://github.com/zschwendi/dark-eco/issues/6).
- Hideout and pre-Haven cutscene reports: [#8](https://github.com/zschwendi/dark-eco/issues/8), [#23](https://github.com/zschwendi/dark-eco/issues/23).
- Jak 1 immersive appearance and wearer acceptance: [#3](https://github.com/zschwendi/dark-eco/issues/3).

The sewer and race fixes have scoped simulator evidence; they do not resolve
all Jak II issues. Jak II immersion is not included, and Jak 3 remains planned.
No new retail fixtures, private raw logs, screenshots or saves are published
with this validation record.

## Reproduction and delivery

The public release is [Build 290](https://github.com/zschwendi/dark-eco/releases/tag/build290-preview).
[Delivery receipts](BUILD290-DELIVERY.json) record each anonymous download and its hash.
The release tag identifies the compiled app source; this documentation checkpoint follows it.

Executed platform builds used the GOALPad project/scheme, Release, arm64,
`-jobs 2`, `GOALPAD_BUILD_JOBS=2`, and one canonical DerivedData directory.
SDK/destination pairs were `iphoneos` / `generic/platform=iOS`, `xros` /
`generic/platform=visionOS`, and `macosx` / `generic/platform=macOS`.
iOS was signed by Xcode; visionOS was signed after compilation, then both
public packages were stripped of maintainer profiles and given transport
ad-hoc signatures. Recipients re-sign them. The Mac check was compilation only.

Focused checks executed successfully:

```sh
cmake --build <canonical-host-build> --target jak2-source-object-pack-verify jak2-source-object-pack-test jak2-metal-ocean-grammar-test jak2-common-tfrag-texture-upload-capture-test --parallel 2
ctest --test-dir <canonical-host-build> -R '^(jak2-source-object-pack-test|jak2-metal-ocean-grammar-test|jak2-common-tfrag-texture-upload-capture-test)$' --output-on-failure
sh Scripts/verify-generated-aot.sh Generated/jak2-aot 840
```

The AOT check covers 840 objects, 18,495 emitted functions and seven native
functions. Exact local invocations, build results, source hashes, original
ASan comparison and screenshot/save evidence remain in the task artifacts
`jak2-full-regression-20261114`; private captures and game data are not published.
Public package-check receipts verify all members, strict signatures, empty
transport entitlements, absent provisioning profiles and unchanged Mach-O
code/data sections after packaging. Both source packs were verified again
from the extracted IPAs. Public downloads matched those audited IPA bytes.

| IPA | Bytes | SHA-256 |
| --- | ---: | --- |
| iOS | 35,454,337 | `c8cb61b50e32283e3f1e4c72b5eec728551bfdf9e37429d5de10d56600163cf8` |
| visionOS | 35,135,985 | `e29e9f56e3833a68fd9aa1ef537f52f97ff7efeeb5e82411ed77c1eba221f688` |
