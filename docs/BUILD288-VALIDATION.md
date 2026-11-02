# Private Build 288 — Jak II runtime corrections

Status: **private signed iOS Build 288 is ready for later device testing; physical acceptance is pending.**
Source and public IPA publication are held until Zach tests and accepts on a device.

## Scope

- Restore the existing upstream Jak II texture-remapping function in the portable Apple machine layer. Its previous no-op allowed different textures to share a destination, including the taillight texture and another texture with a white border. No shader, blend or retail asset changes.
- Correct short streamed-audio natural completion, including delayed game updates and payload loop-start flags. A silent terminal block and the existing locked loop-address setter keep completion observable. The reported slide and hideout scene freezes remain unconfirmed; this is not a blanket cutscene fix.
- Destroy Jak 1 renderer buckets before their texture pool on normal shutdown and render-stack allocation failure. This removes a source-proven dangling pool reference during cleanup.
- Refresh three stale lifecycle source-check patterns to match already-existing Build 287 behavior. No game-loop behavior changes in that refresh.
- Carry forward private 287's app-folder import alternative, Jak II internal resolution wiring and bounded opt-in freeze diagnostics.

The texture seam regression fails three checks before the change and passes all five with the new binding. Offline local numeric metadata independently shows the taillight destination collision and the differing edge colors. No retail fixtures or images are added to this repository. Physical taillight appearance remains pending.

## Verification boundary

Canonical native compilation and all five focused CTest targets passed: texture remap, sound RPC, PC random, controller and handler seams. The final audio fixture fails ten assertions against the baseline and passes all legacy and new checks with the correction. Release iOS, visionOS, macOS and iOS Simulator builds all passed sequentially from app `28ab90b63ebeac108bc399fe800a1669da69214e` and engine `95cc8bf069655a5663547fedbe1bd1f39489f32c`. Simulator compilation did not launch or test a simulator. Full logs and exact invocation receipts remain in the workspace artifact directory `.agent-builds/jak2-continue-20261102`.

No physical devices or simulator gameplay are used for this phase. Water corruption (#13), reported scene freezes (#8/#23), ProMotion (#6), importer recipient acceptance (#19), and Jak 1 immersive appearance (#3) remain open. New Jak II immersion remains gated on ordinary playability. Build and package checks do not establish complete-game acceptance.

## Commands completed before Apple builds

```sh
cmake --build <workspace>/.agent-builds/opengoal-host-current --target jak2-tex-remap-seam-test jak2-sound-rpc-test jak2-pc-rand-test jak2-pad-seam-test jak2-handler-seam-test -j2
ctest --test-dir <workspace>/.agent-builds/opengoal-host-current -R "^(jak2-tex-remap-seam-test|jak2-sound-rpc-test|jak2-pc-rand-test|jak2-pad-seam-test|jak2-handler-seam-test)$" --output-on-failure
sh Scripts/run-game-lifecycle-check.sh
git diff --check
```

All passed. Exact absolute invocations and durations are in `core-validation.json` in the artifact directory. The audio test uses only original synthetic fixtures. No new source pack or GOAL workload was generated.

## Apple builds and private package

All builds used the existing project/scheme, Release configuration, ARM64 and the single canonical DerivedData directory, with two build jobs. Exact invocations are in `VALIDATION.json` in the private artifact directory. Reproduction uses `run-platform-build.py ios`, then `vision`, `mac`, and `simulator`; the retained script records the full xcodebuild command and asserts clean, unchanged source for every build.

The generic iOS build is signed. `package-private-ios.py` passed strict signature checks before and after staging, provisioning expiry/application identity checks, both source-pack verifiers, archive CRC and embedded executable/framework hash comparisons. The unchanged source packs are Jak1 518 objects / `c1e79fbb50f33437` and Jak2 840 objects / `52a48a48ebb03e70`.

Private IPA: `DarkEco-iOS-2.0-build288-private-test.ipa` (35,962,596 bytes).
SHA-256: `41b507ff702fe8b2e6bcd51a977b3a643935c1e6ecb51b00b19a2c1b39ae92bd`.
No physical installation, gameplay, source push or public release occurred.

## Remaining acceptance and limitations

- Compare real near/far taillights, headlights and other remapped textures; the source/data evidence is strong, but pixels have not been accepted on device.
- Reproduce the pre-Haven slide and hideout scenes. The new short-stream regression does not establish that either reported freeze is solved. Large-stream refill behavior is unchanged; the inherited opt-in diagnostics remain available.
- Water corruption remains unresolved after a bounded source review. Do not make arbitrary depth/projection changes without symptom-aligned evidence.
- Confirm Jak1 return-to-Library and re-entry. The pool lifetime fix has source review and compile coverage, not a new runtime teardown reproduction.
- Inherited importer alternative and resolution changes still require recipient/device acceptance. ProMotion and Jak1 immersive visual acceptance remain open. Do not begin new Jak II immersion or call the game complete on this evidence.
