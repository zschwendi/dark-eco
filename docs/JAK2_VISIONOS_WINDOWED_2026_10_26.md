# Jak II native visionOS windowed test — Build 254

Status: **Experimental. Signed Build 254 was installed in place on the maintainer's Vision Pro on October 26, 2026. Headset disc import and gameplay acceptance remain pending.** Jak II immersive work remains deferred until ordinary playability is near-perfect.

## Summary

Jak II's ISO and ZIP files were dimmed because its preparation adapter, runtime router, embedded framework and resource staging were restricted to iOS. With preparation unavailable, the setup picker accepted only prepared folders. Downloading the same file again could not enable that path.

The native visionOS app now includes the isolated Jak II runtime framework, composer and public preparation resources. The existing picker can offer ISO, supported archived ISO and prepared-folder sources. In the II card's setup screen, use **Choose game data…** and then **Play Now** after preparation. Jak 1's existing immersive entry remains restricted to Jak 1.

## Files changed

- `GOALPad.xcodeproj/project.pbxproj`: build, embed and stage the Jak II framework/resources on visionOS as well as iOS.
- `Scripts/build-jak2-native-apple.sh`, `Configuration/Jak2Packaging.xcconfig`: select matching SDK and deployment settings.
- `GOALPad/Native/GOALPadRuntimeRouterPrivate.h`, `GOALPad/Data/Jak2NativePreparationBackend.swift`: enable the existing runtime and importer on visionOS when the framework is present.
- `OpenGOAL/CMakeLists.txt`, `OpenGOAL/game/graphics/pipelines/metal/metal_product.cmake`: allow the visionOS runtime closure and compile its embedded shaders for the correct SDK. These changes belong in the shared native build graph; the application cannot correct an already embedded macOS metallib.
- Two existing source-check scripts now require the iOS/visionOS gates while retaining the unavailable-framework and macOS exclusions.

The game kernels remain isolated. No Jak II immersive renderer, game data, new dependency or runtime-generated code requirement was added.

## Validation

- Complete native visionOS Release app build: PASS, 390.186 seconds. Both executable and embedded Jak II framework report native `VISIONOS` load commands. Both games' preparation resource directories are present.
- Signing: PASS, including the nested framework, strict recursive verification and the existing provisioning entitlements. Installed version was independently read back as **2.0 (254)**. No uninstall or data clearing occurred.
- Existing preparation-backend and native-router checks: PASS. Bounded worker checks also covered header present/absent on xros and iOS, visionOS simulator Swift typechecking, and the unavailable Mac path.
- Generic iOS Release regression build: PASS, 56.737 seconds, signing disabled; no physical iPad was accessed.
- Current native `metal-proof --stereo-pixels-only`: PASS on the Mac GPU, including the original Jak 1 Sprite2d/HUD oracle. This is a regression proof, not headset acceptance.
- The source-bounded Lightning fix is included. A normal, unskipped New Game introduction in iPad simulator Build 253 traversed all four introductory scenes and reached prison with zero failed rendering chains. Build 252 had reproduced the exact `transfer-budget`, `256/256` rejection. Focused capture/plan tests passed 2/2, including the 2312-transfer maximum and rejection/mutation cases.

Exact command arrays, source base/diff hashes, signed package identities, installation receipt and private captures remain in the workspace artifacts under `.agent-builds/jak2-playability-20261026/vision-windowed254/`. No artifacts or user game data were committed.

## Not validated / follow-up

The maintainer still needs to select a disc image and complete import and ordinary play on Vision Pro. Complete mission progression, physical saving/loading, performance, audio and controller acceptance are separate gates. Normal iPad simulator save creation and cold reload were verified earlier, but no ordinary mission completion is claimed.

The settled Jak II pause submenu background still flips vertically. A source-shaped GPU test passes with an experimental consumer correction, but the stable live menu does not; that correction remains uncommitted in the separate iPad investigation and is absent from Vision Pro Build 254. Continue with a bounded live packet/snapshot diagnostic, not further speculative visual edits.
