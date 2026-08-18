# Jak II `v2.0` divergence audit

Date: 2026-08-17

## Decision

Dark Eco on outer branch `v2.0` is the only shipping application. Nested
OpenGOAL `v2.0` is the only shipping native-runtime line. The removed
standalone Jak II app, `jak2-best`, and historical agent branches are read-only
comparison history.

This audit compares the final old product checkpoints with the current unified
product. It does not treat every diagnostic experiment or superseded packaging
commit as a feature that should ship.

## Repository boundaries

| Repository | Old checkpoint | Current checkpoint | Result |
| --- | --- | --- | --- |
| Outer GOALPad | `30068e88` (`jak2-best`) | `ee8a8c7f` (`v2.0`) | Histories diverge after `0a625cc3`; shipping behavior was ported into the unified shell. |
| Nested OpenGOAL | `8e914809` (`jak2-best`) | `c8666f88` (`v2.0`) | The old tip is an ancestor of current `v2.0`; no old runtime commit is missing. |

Nested `v2.0` incorporated the complete old runtime through merge `34eda4d14`
and then added importer error handling, bounded generated-input memory, Merc
compatibility, player-context and prompt snapshots, Hor+, warp compatibility,
ocean rendering, eye-source fixes, high-refresh timing, and PC save/menu
repairs. No nested cherry-pick from `jak2-best` remains.

## Outer old-line audit

The outer histories have 219 old-only commits because `jak2-best` was developed
as a separate product line. Their final net change touches 68 paths:

| Path class | Count | Disposition |
| --- | ---: | --- |
| App source | 20 | Ported to runtime-selected title profiles and the unified runtime router. |
| Jak II bridge | 3 | Copied exactly at `a0648786`, then extended on `v2.0`. |
| Scripts and checks | 36 | Copied or generalized for the embedded framework and unified app. |
| Standalone packaging | 4 | Deliberately retired; must not be restored. |
| Documentation | 4 | Historical evidence retained; current authority corrected on `v2.0`. |
| Nested gitlink | 1 | Superseded by nested `v2.0`, which contains the old tip. |

The following old-tip blobs were byte-identical in outer integration checkpoint
`a0648786` before further unified work:

- `TargetSupport/Jak2/EcoJak2RuntimeBridge.mm`
- `TargetSupport/Jak2/EcoJak2RuntimeBridgeLinkCheck.mm`
- `TargetSupport/Jak2/EcoJak2RuntimeBridgeTest.mm`
- `Scripts/build-jak2-native-apple.sh`
- `Scripts/jak2-scene-sweep.py`
- `Scripts/run-jak2-scene-sweep.sh`
- `Scripts/run-jak2-import-target-config-check.sh`

This establishes that the final old bridge and test harness were not recreated
from an earlier snapshot. Later `v2.0` changes extend those files for runtime
selection, high refresh, player context, prompts, renderer diagnostics, Hor+,
and the embedded framework.

## Behavior mapping

| Old Jak II behavior | Unified Dark Eco implementation |
| --- | --- |
| Prepared data and raw ISO import | Per-title `GameDataProfile`, title-routed install safety, and `Jak2NativePreparationBackend` through the embedded runtime framework. |
| Foreground import protection | `DeviceIdleTimerAssertions` owned by `GameDataImporter`; this supersedes the standalone `GameDataImportLifecyclePolicy` file without dropping the behavior. |
| Local Jak II save isolation | `SaveSyncProfile.jak2`, separate local/conflict/state paths, title-specific format validation, manual transfer, and a separate Dark Eco iCloud namespace. |
| Standalone 4x Jak II render default | `RenderSettingsConfiguration.jak2` with its own defaults key and 4x default, selected by the active title instead of bundle ID. |
| Title, pause, overwrite, save, and load touch controls | Title-aware progress snapshots and native pause/progress actions in the shared touch system, plus later pause/save-menu regression repairs. |
| Runtime and renderer bridge | `GOALPadJak2Runtime` embedded in Dark Eco and selected through `GOALPadRuntimeBridge`; no compile-time standalone app switch remains. |
| Scene and cutscene sweep | Current sweep retains the old scenes and adds reliable live-log capture plus explicit ocean, TFRAG, and eye renderer requirements. |
| Import and runtime diagnostics | Retained where still actionable; one-off proof logging is not treated as required player behavior. |

## Post-merge Jak II lanes

The later feature branches were also compared with current `v2.0`. Their
shipping outcomes are present at these checkpoints:

| Work | Outer checkpoint | Nested checkpoint or basis |
| --- | --- | --- |
| Colored weapon D-pad and title-aware touch | `a1f9100c`, `2997f9d6` | Native PS2 direction bits; no nested feature fork required. |
| Title-safe save sync and transfer | `decd953d`, `15b3c186` | Per-title bank formats and namespaces. |
| Player traversal/look context | `24c992d0` | `acfec2a98`. |
| Fit to Screen / Hor+ | `b6657295` | `476cba196`. |
| Contextual Triangle prompts | `4bb91916`, `313100e7` | `c15ca237d`, `d0d0b9305`. |
| High-refresh timing | `f87cc599` | `09be637fd`, `5884f6a14`, `48cd2df77`. |
| Ocean repair | `a4457fd0` | `5cf83fc0b`. |
| Eye diagnostics and final source fix | `3ac229c7`, `706458f3`, `9655aab8`, `0a7947ff` | `f5c3b84e4`, `b71c9e646`, `455332263`, `663970d60`, `1e37725af`, `7ebdce615`. |
| Memory-card bypass and pause/save controls | `5277cf29`, `b4232d55`, `63914578`, `260ac92b`, `2bba0c19` | `c3ae11504`, `c44cf6ee2`, `01efd38b3`, `a81645346`. |
| Holdable traversal controls and vehicle exit | `b5a000a9`, `a0e63a52` | Uses native Jak II input/state contracts. |
| Unified settings and touch guide | `8b6d1ba2`, `c28d6855` | Runtime title ownership in the shared app. |

The dedicated-eye-buffer and other A/B branches were diagnostic. Their useful
evidence and the resulting source-identity fix are already in `v2.0`; reviving
the alternative buffer experiment would not add player behavior. Likewise,
standalone framework-embed and default-to-Jak-II branches became obsolete when
Dark Eco became the sole application at `5be3d5ed`.

## Conclusion

No shipping Jak II behavior from the final `jak2-best` checkpoints is missing
from the current unified source tree. The remaining direct tree differences are
newer unified work, deliberately retired standalone packaging, generalized
checks, or obsolete diagnostics. Future regressions must be fixed on `v2.0`;
they are not evidence that the old application branch should be resumed.

Physical visual and gameplay acceptance remains separate from this source
history result. A successful ancestry or focused-contract audit does not prove
every retail scene, cutscene, save, vehicle, or touch interaction on iPad.

## Focused validation

The unified source contracts passed after the audit:

```text
Scripts/run-jak2-import-target-config-check.sh
swift Scripts/selected-session-routing-check.swift "$PWD"
Scripts/run-raw-iso-profile-routing-check.sh
Scripts/run-save-sync-check.sh
Scripts/run-touch-controls-check.sh
Scripts/run-native-runtime-router-check.sh
python3 Scripts/jak2-scene-sweep.py --self-test
git diff --check
```

These are focused source and synthetic checks, not a new Xcode build or physical
iPad acceptance run.
