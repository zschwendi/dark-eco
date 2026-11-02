# Private Build 288 — Jak II runtime corrections

Status: **integration in progress; no signed Build 288 package or device acceptance yet.**
Source and public IPA publication are held until Zach tests and accepts on a device.

## Scope

- Restore the existing upstream Jak II texture-remapping function in the portable Apple machine layer. Its previous no-op allowed different textures to share a destination, including the taillight texture and another texture with a white border. No shader, blend or retail asset changes.
- Correct short streamed-audio natural completion, including delayed game updates and payload loop-start flags. A silent terminal block and the existing locked loop-address setter keep completion observable. The reported slide and hideout scene freezes remain unconfirmed; this is not a blanket cutscene fix.
- Destroy Jak 1 renderer buckets before their texture pool on normal shutdown and render-stack allocation failure. This removes a source-proven dangling pool reference during cleanup.
- Refresh three stale lifecycle source-check patterns to match already-existing Build 287 behavior. No game-loop behavior changes in that refresh.
- Carry forward private 287's app-folder import alternative, Jak II internal resolution wiring and bounded opt-in freeze diagnostics.

The texture seam regression fails three checks before the change and passes all five with the new binding. Offline local numeric metadata independently shows the taillight destination collision and the differing edge colors. No retail fixtures or images are added to this repository. Physical taillight appearance remains pending.

## Verification boundary

Canonical native compilation and all five focused CTest targets passed: texture remap, sound RPC, PC random, controller and handler seams. The final audio fixture fails ten assertions against the baseline and passes all legacy and new checks with the correction. Apple platform compilation remains pending. Full logs and exact invocation receipts remain in the workspace artifact directory `.agent-builds/jak2-continue-20261102`.

No physical devices or simulator gameplay are used for this phase. Water corruption (#13), reported scene freezes (#8/#23), ProMotion (#6), importer recipient acceptance (#19), and Jak 1 immersive appearance (#3) remain open. New Jak II immersion remains gated on ordinary playability. Build and package checks do not establish complete-game acceptance.

## Commands completed before Apple builds

```sh
cmake --build <workspace>/.agent-builds/opengoal-host-current --target jak2-tex-remap-seam-test jak2-sound-rpc-test jak2-pc-rand-test jak2-pad-seam-test jak2-handler-seam-test -j2
ctest --test-dir <workspace>/.agent-builds/opengoal-host-current -R "^(jak2-tex-remap-seam-test|jak2-sound-rpc-test|jak2-pc-rand-test|jak2-pad-seam-test|jak2-handler-seam-test)$" --output-on-failure
sh Scripts/run-game-lifecycle-check.sh
git diff --check
```

All passed. Exact absolute invocations and durations are in `core-validation.json` in the artifact directory. The audio test uses only original synthetic fixtures. No new source pack or GOAL workload was generated.
