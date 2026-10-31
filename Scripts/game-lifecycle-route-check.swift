import Foundation

private var failures = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("  ok   \(message)")
    } else {
        print("  FAIL \(message)")
        failures += 1
    }
}

private func source(at path: String) -> String {
    do {
        return try String(contentsOfFile: path, encoding: .utf8)
    } catch {
        print("  FAIL could not read \(path): \(error.localizedDescription)")
        Foundation.exit(1)
    }
}

private func section(_ source: String, from start: String, to end: String) -> String {
    guard let lower = source.range(of: start),
          let upper = source.range(of: end, range: lower.upperBound..<source.endIndex) else {
        print("  FAIL could not isolate source section from \(start) to \(end)")
        failures += 1
        return ""
    }
    return String(source[lower.lowerBound..<upper.lowerBound])
}

private func occursInOrder(_ needles: [String], in source: String) -> Bool {
    var lower = source.startIndex
    for needle in needles {
        guard let match = source.range(of: needle, range: lower..<source.endIndex) else {
            return false
        }
        lower = match.upperBound
    }
    return true
}

private func occurrenceCount(_ needle: String, in source: String) -> Int {
    source.components(separatedBy: needle).count - 1
}

guard CommandLine.arguments.count == 2 else {
    print("usage: swift Scripts/game-lifecycle-route-check.swift <repository-root>")
    Foundation.exit(2)
}

let root = CommandLine.arguments[1]
let session = source(at: root + "/GOALPad/Game/GameSession.swift")
let content = source(at: root + "/GOALPad/ContentView.swift")
let audio = source(at: root + "/GOALPad/Audio/AudioOutput.swift")
let gameBoot = source(at: root + "/GOALPad/Native/GOALPadGameBoot.cpp")
let gameBootHeader = source(at: root + "/GOALPad/Native/GOALPadGameBoot.hpp")
let gameplaySaveGeneration = source(
    at: root + "/GOALPad/Game/GameplaySaveGenerationState.swift")
let bridge = source(at: root + "/GOALPad/Native/GOALPadRuntimeBridge.h")
let bridgeImplementation = source(at: root + "/GOALPad/Native/GOALPadRuntimeBridge.mm")
let surfaceView = source(at: root + "/GOALPad/Game/GameSurfaceView.swift")
let renderSurface = source(at: root + "/GOALPad/Native/GOALPadRenderSurface.mm")
let metalHost = source(at: root + "/GOALPad/Native/GOALPadMetalHost.mm")
let kmemcardHeader = source(at: root + "/OpenGOAL/game/kernel/common/kmemcard.h")
let kmemcard = source(at: root + "/OpenGOAL/game/kernel/common/kmemcard.cpp")

let audioSession = section(audio,
                           from: "private func activateSession() throws",
                           to: "private func deactivateSession()")
check(audioSession.contains("setCategory(.playback, mode: .default, options: [.mixWithOthers])")
        && !audioSession.contains(".duckOthers")
        && !audioSession.contains(".interruptSpokenAudioAndMixWithOthers"),
      "game audio mixes with external media without ducking or interrupting speech")
check(audio.contains("setActive(false, options: .notifyOthersOnDeactivation)"),
      "audio shutdown still notifies other active media sessions")
let audioPull = section(audio,
                        from: "func render(frameCount: AVAudioFrameCount",
                        to: "return noErr\n    }\n}")
check(audioPull.contains("let leftSample = scratch[frame * 2]")
        && audioPull.contains("let rightSample = scratch[frame * 2 + 1]")
        && audioPull.contains("loudest = max(loudest, max(abs(Int(leftSample)), abs(Int(rightSample))))")
        && !audioPull.contains("for sample in 0..<(written * 2)"),
      "the real-time audio callback measures peak amplitude during mandatory deinterleaving")

let uiLifecycle = section(surfaceView,
                          from: "private final class MetalHostView: UIView",
                          to: "private struct SurfaceRepresentable: UIViewRepresentable")
check(uiLifecycle.contains("UIScene.willDeactivateNotification")
        && uiLifecycle.contains("UIScene.didActivateNotification"),
      "the UIKit presentation host observes both scene suspension and activation")

let suspendPresentation = section(uiLifecycle,
                                  from: "private func suspendPresentation()",
                                  to: "override func layoutSubviews()")
check(occursInOrder([
    "stopDisplayLink()",
    "PresentationSurfaceCoordinator.shared.deactivate(self)",
], in: suspendPresentation),
      "scene suspension stops callbacks before releasing surface ownership")

let resumePresentation = section(uiLifecycle,
                                 from: "private func resumePresentation()",
                                 to: "private func suspendPresentation()")
check(occursInOrder([
    "PresentationSurfaceCoordinator.shared.activate(self, layer: metalLayer)",
    "updateDrawableSize()",
    "startDisplayLink()",
], in: resumePresentation),
      "scene activation reattaches and sizes the layer before recreating its display link")

let displayStep = section(uiLifecycle,
                          from: "@objc private func step(_ link: CADisplayLink)",
                          to: "}\n}")
check(occursInOrder([
    "PresentationSurfaceCoordinator.shared.isOwner(self)",
    "onFrame?(link.targetTimestamp)",
], in: displayStep), "only the attached presentation owner can drive a native frame")

let attachLayer = section(renderSurface,
                          from: "- (void)attachLayer:(CAMetalLayer *)layer",
                          to: "- (void)setDrawableSize")
check(occursInOrder([
    "if (layer == nil)",
    "goalpad::metal_host_end_frame();",
    "_layer = nil;",
], in: attachLayer), "detaching closes a stale armed frame before releasing its layer")

let tick = section(session,
                   from: "func tick(targetPresentationTime",
                   to: "#if os(visionOS)\n    func tickStereo")
check(session.contains("detailedFrameStatsEnabled = presentationSettings.developerLogsEnabled\n"
                       + "        GOALPadRenderSurface.shared.setDetailedFrameStatsEnabled(detailedFrameStatsEnabled)"),
      "rich renderer frame evidence follows the opt-in Developer Logs setting")
check(bridge.contains("- (void)setDetailedFrameStatsEnabled:(BOOL)enabled;")
        && renderSurface.contains("goalpad::metal_host_set_detailed_frame_stats_enabled(enabled);")
        && metalHost.contains("jak1_bones_provenance_trace::registry().set_enabled(enabled);")
        && metalHost.contains("if (g_host.detailed_frame_stats_enabled) {\n    camera.emplace(goalpad::current_camera_frame_identity(true));")
        && metalHost.contains("opts.engine_frame_id = goalpad::frames_run() + 1;")
        && metalHost.contains("retain_current_frame_target_post_flag(opts.engine_frame_id")
        && metalHost.contains("if (!g_host.detailed_frame_stats_enabled) {\n    return;\n  }\n  const auto stats = g_host.renderer->chain_stats();")
        && metalHost.contains("if (g_host.renderer && g_host.detailed_frame_stats_enabled)"),
      "shipping frames avoid camera snapshots, detailed Metal stats copies, and host evidence processing")
check(occursInOrder([
    "lifecycle.frameLoopEnabled",
    "!controlsGuideSuspension.blocksGameplay",
    "surface.beginFrame(at: targetPresentationTime)",
    "runArmedTick(targetPresentationTime: targetPresentationTime)",
    "surface.endFrame()",
], in: tick), "an eligible conventional display tick arms and delegates one frame")

let armedTick = section(session,
                        from: "private func runArmedTick",
                        to: "private func updateNativeMenuState")
check(session.contains("@ObservationIgnored private(set) var framesRun: UInt64 = 0")
        && session.contains("@ObservationIgnored private(set) var framesPresented: UInt64 = 0"),
      "per-frame diagnostic counters do not publish Swift Observation invalidations")
check(armedTick.contains("if developerLogsEnabled, framesRun % 60 == 0")
        && armedTick.contains("diagnosticsRevision &+= 1")
        && content.contains("let _ = session.diagnosticsRevision"),
      "the opt-in diagnostics overlay refreshes at a bounded cadence")
check(occursInOrder([
    "let developerLogsEnabled = presentationSettings.developerLogsEnabled",
    "input.pushFrame",
    "var nativeState = GOALPadGameFrameStateSnapshot()",
    "GOALPadRuntimeBridge.runFrame(at: targetPresentationTime,",
    "stateSnapshot: &nativeState)",
    "gameplaySaveGeneration.observe(nativeState.successfulSaveGeneration)",
    "saveSync.gameplaySaveCompleted()",
    "nativeState.exitToLibraryRequested.boolValue",
    "returnToLibraryRequestID &+= 1",
    "framesRun = nativeState.framesRun",
    "let currentMode = nativeState.gameMode",
    "NativeProgressMenuSnapshot(\n                nativeState.progressMenu,",
    "let currentTitleStartState = nativeState.titleStartState",
    "NativeWarpGateTouchSnapshot(\n                nativeState.warpGateTouch)",
    "NativeCutsceneSkipTouchSnapshot(\n                nativeState.cutsceneSkipTouch)",
    "NativeFacePromptTouchSnapshot(\n                nativeState.facePromptTouch)",
    "let currentLookAroundState = nativeState.lookAroundState",
    "let currentJak2TraversalState = nativeState.jak2TraversalState",
    "let currentSpeederState = nativeState.speederState",
    "let framePresented = endFrame()",
], in: armedTick),
      "the shared frame body preserves input, state-publication, and presentation ordering")
check(occurrenceCount("GOALPadRuntimeBridge.runFrame", in: armedTick) == 1
        && !armedTick.contains("GOALPadRuntimeBridge.gameFrameStateSnapshot")
        && !armedTick.contains("GOALPadRuntimeBridge.exitToLibraryRequested")
        && !armedTick.contains("GOALPadRuntimeBridge.framesRun")
        && !armedTick.contains("GOALPadRuntimeBridge.gameMode")
        && !armedTick.contains("GOALPadRuntimeBridge.progressMenuSnapshot")
        && !armedTick.contains("GOALPadRuntimeBridge.titleStartState")
        && !armedTick.contains("GOALPadRuntimeBridge.warpGateTouchSnapshot")
        && !armedTick.contains("GOALPadRuntimeBridge.cutsceneSkipTouchSnapshot")
        && !armedTick.contains("GOALPadRuntimeBridge.facePromptTouchSnapshot")
        && !armedTick.contains("GOALPadRuntimeBridge.lookAroundState")
        && !armedTick.contains("GOALPadRuntimeBridge.jak2TraversalState")
        && !armedTick.contains("GOALPadRuntimeBridge.speederState")
        && !armedTick.contains("gameplayFrameCompleted")
        && occurrenceCount("saveSync.gameplaySaveCompleted()", in: armedTick) == 1,
      "each eligible frame uses one fused Objective-C++ tick and native-state crossing")
check(gameplaySaveGeneration.contains("guard generation != observed else { return false }")
        && gameplaySaveGeneration.contains("observed = generation")
        && gameplaySaveGeneration.contains("observed = 0"),
      "the session save tracker emits only changed generations and treats wrap as a change")
check(armedTick.contains("if developerLogsEnabled {\n            recordDisplayCallback()\n        }")
        && armedTick.contains("shouldLog = developerLogsEnabled && framesRun % 600 == 0")
        && armedTick.contains("if shouldLog { logRunningState(renderer: GOALPadRenderSurface.shared.stats) }"),
      "display cadence samples and renderer logging remain opt-in developer diagnostics")

let nativeFrameState = section(gameBoot,
                               from: "GameFrameStateSnapshot game_frame_state_snapshot() noexcept",
                               to: "#else  // GOALPAD_HAVE_GAME_BOOT")
check(occursInOrder([
    "snapshot.exit_to_library_requested = exit_to_library_requested();",
    "snapshot.frames_run = frames_run();",
    "snapshot.successful_save_generation = kmemcard_successful_save_generation();",
    "const auto current_mode = game_mode();",
    "snapshot.game_mode = current_mode;",
    "snapshot.progress_menu = progress_menu_snapshot_for_mode(current_mode);",
    "const auto target_state = capture_target_frame_state();",
    "snapshot.title_start_state = title_start_state_from_capture(target_state);",
    "snapshot.warp_gate_touch = warp_gate_touch_snapshot();",
    "snapshot.cutscene_skip_touch = cutscene_skip_touch_snapshot_for_mode(current_mode);",
    "snapshot.face_prompt_touch = face_prompt_touch_snapshot_for_mode(current_mode);",
    "snapshot.look_around_state = look_around_state_from_capture(target_state);",
    "snapshot.speeder_state = speeder_state_from_capture(target_state);",
], in: nativeFrameState)
        && occurrenceCount("game_mode();", in: nativeFrameState) == 1
        && occurrenceCount("capture_target_frame_state();", in: nativeFrameState) == 1,
      "the native aggregate preserves read order and reuses one mode and target capture")

let fusedNativeFrame = section(
    gameBoot,
    from: "bool run_frame(double target_presentation_time,\n               GameFrameStateSnapshot* state_snapshot) noexcept",
    to: "bool run_frame(double target_presentation_time) noexcept")
check(occursInOrder([
    "*state_snapshot = {};",
    "if (!g_booted)",
    "call_goal_on_stack",
    "goal_sound_frame();",
    "g_frames++;",
    "*state_snapshot = game_frame_state_snapshot();",
    "return true;",
], in: fusedNativeFrame)
        && gameBoot.contains("bool run_frame(double target_presentation_time) noexcept {\n  return run_frame(target_presentation_time, nullptr);\n}"),
      "the fused native entry publishes only fail-closed or completed post-tick state")
let unavailableNativeFrame = section(
    gameBoot,
    from: "#else  // GOALPAD_HAVE_GAME_BOOT",
    to: "#endif  // GOALPAD_HAVE_GAME_BOOT")
check(occursInOrder([
    "bool run_frame(double target_presentation_time,",
    "GameFrameStateSnapshot* state_snapshot) noexcept",
    "*state_snapshot = {};",
    "return false;",
], in: unavailableNativeFrame),
      "the unavailable native frame entry returns false with fail-closed output")

let targetFrameCapture = section(gameBootHeader,
                                 from: "inline TargetFrameStateCapture read_target_frame_state_capture(",
                                 to: "template <std::size_t StateCount>")
check(occurrenceCount("camera_correction_trace::checked_goal_object(", in: targetFrameCapture) == 1
        && targetFrameCapture.contains("live_state_layout::kProcessRequiredObjectBytes")
        && targetFrameCapture.contains("target_bytes < target_frame_layout::kLookAroundRequiredObjectBytes")
        && occurrenceCount("read_checked_state_name(", in: targetFrameCapture) == 2,
      "one checked target read preserves independent current, next, and look bounds")

let frameStateMapping = section(
    bridgeImplementation,
    from: "static GOALPadGameFrameStateSnapshot GOALPadGameFrameStateSnapshotFromCore",
    to: "@implementation GOALPadRuntimeBridge")
let fusedFrameBridge = section(
    bridgeImplementation,
    from: "+ (BOOL)runFrameAtPresentationTime:(CFTimeInterval)targetPresentationTime\n                     stateSnapshot:",
    to: "+ (void)resetFrameTiming")
check(bridge.contains("typedef struct GOALPadGameFrameStateSnapshot")
        && bridge.contains("uint64_t successfulSaveGeneration;")
        && bridge.contains("NS_SWIFT_NAME(runFrame(at:));")
        && bridge.contains("NS_SWIFT_NAME(runFrame(at:stateSnapshot:));")
        && bridge.contains("@property(class, nonatomic, readonly) GOALPadGameFrameStateSnapshot gameFrameStateSnapshot;")
        && occursInOrder([
            "snapshot.exitToLibraryRequested = core.exit_to_library_requested ? YES : NO;",
            "snapshot.framesRun = core.frames_run;",
            "snapshot.successfulSaveGeneration = core.successful_save_generation;",
            "snapshot.gameMode = GOALPadGameModeFromCore(core.game_mode);",
            "snapshot.progressMenu = GOALPadProgressMenuSnapshotFromCore(core.progress_menu);",
            "snapshot.titleStartState = GOALPadTitleStartStateFromCore(core.title_start_state);",
            "snapshot.warpGateTouch = GOALPadWarpGateTouchSnapshotFromCore(core.warp_gate_touch);",
            "snapshot.cutsceneSkipTouch = GOALPadCutsceneSkipTouchSnapshotFromCore(core.cutscene_skip_touch);",
            "snapshot.facePromptTouch = GOALPadFacePromptTouchSnapshotFromCore(core.face_prompt_touch);",
            "snapshot.lookAroundState = GOALPadLookAroundStateFromCore(core.look_around_state);",
            "snapshot.jak2TraversalState = GOALPadJak2TraversalStateUnknown;",
            "snapshot.speederState = GOALPadSpeederStateFromCore(core.speeder_state);",
        ], in: frameStateMapping),
      "the fixed C bridge maps every native frame field without object ownership")
check(occursInOrder([
    "goalpad::GameFrameStateSnapshot core;",
    "goalpad::run_frame(targetPresentationTime, &core);",
    "*stateSnapshot = GOALPadGameFrameStateSnapshotFromCore(core);",
    "return ran ? YES : NO;",
], in: fusedFrameBridge)
        && bridgeImplementation.contains("return goalpad::run_frame(targetPresentationTime) ? YES : NO;")
        && bridgeImplementation.contains("return GOALPadGameFrameStateSnapshotFromCore(goalpad::game_frame_state_snapshot());"),
      "the fused bridge returns one POD snapshot while preserving both compatibility entry points")

let memcardInitialization = section(kmemcard,
                                    from: "void kmemcard_init_globals()",
                                    to: "u64 kmemcard_successful_save_generation()")
let memcardSave = section(kmemcard,
                          from: "void pc_game_save_synch()",
                          to: "void pc_game_load_open_file")
check(kmemcardHeader.contains("class KmemcardSuccessfulSaveGeneration")
        && kmemcardHeader.contains("if (close_result == 0) {")
        && kmemcardHeader.contains("value_++;")
        && kmemcardHeader.contains("u64 kmemcard_successful_save_generation();")
        && memcardInitialization.contains("successful_save_generation.reset();")
        && occursInOrder([
            "const int close_result = fclose(fd);",
            "successful_save_generation.record_close_result(close_result);",
            "if (close_result == 0) {",
            "op.result = McStatusCode::OK;",
        ], in: memcardSave)
        && occurrenceCount("record_close_result", in: kmemcard) == 1,
      "kmemcard resets its host counter and advances it only from the successful save close")

let start = section(session, from: "func start() async", to: "private func bootFinished")
check(occursInOrder([
    "let status = GOALPadRuntimeBridge.startKernel(",
    "guard status.isRunning else",
    "gameplaySaveGeneration.reset()",
    "bootQueue.async",
], in: start), "a successful kernel start resets the save baseline before asynchronous boot")
check(start.contains("startupGeneration: startupGeneration"),
      "asynchronous boot completion carries the startup generation it belongs to")

let bootFinished = section(session,
                           from: "private func bootFinished",
                           to: "func shutdown")
check(occursInOrder([
    "startupGeneration: UInt64",
    "guard isBooting, startupState.owns(generation: startupGeneration) else { return }",
    "boot = status",
    "isBooting = false",
    "startupState.reset()",
], in: bootFinished),
      "boot completion rejects callbacks invalidated by shutdown or session replacement")
check(occursInOrder([
    "if presentationSettings.developerLogsEnabled",
    "startCameraDiagnostics()",
    "cameraDiagnosticsURL = nil",
], in: bootFinished),
      "camera diagnostics start only when developer logs are enabled")
check(bootFinished.contains("GOALPadRuntimeBridge.stopKernel()")
        && bootFinished.contains("gameplaySaveGeneration.reset()"),
      "boot failure clears the session save baseline")

let shutdown = section(session, from: "func shutdown()", to: "func presentTouchControlsGuide()")
check(occursInOrder([
    "isBooting = false",
    "startupState.reset()",
    "GOALPadRuntimeBridge.stopKernel()",
    "gameplaySaveGeneration.reset()",
], in: shutdown),
      "session shutdown invalidates boot completion before stopping native state and save tracking")

let cameraPersistence = section(session,
                                from: "private func persistCameraDiagnosticsForLifecycleEvent()",
                                to: "private func mercPaletteHealthTotal")
check(occursInOrder([
    "guard presentationSettings.developerLogsEnabled else { return }",
    "guard isRunning, surface.isRendererLinked else { return }",
    "persistCameraDiagnosticsIfNeeded(",
], in: cameraPersistence),
      "lifecycle camera diagnostics are inert unless developer logs are enabled")
check(content.contains("session.presentationSettings.developerLogsEnabled")
        && content.contains("DiagnosticsOverlay(session: session)"),
      "the developer diagnostics overlay remains opt-in")

let nativeMachineOverrides = section(gameBoot,
                                     from: "void install_app_machine_functions()",
                                     to: "goalpad::BootStatus failure")
check(gameBoot.contains("u64 app_kernel_shutdown()")
        && nativeMachineOverrides.contains("make_function_symbol_from_c(\"kernel-shutdown\"")
        && gameBoot.contains("g_exit_to_library_requested = true;")
        && gameBoot.contains("MasterExit = RuntimeExitStatus::EXIT;")
        && gameBoot.contains("g_exit_to_library_requested = false;")
        && gameBootHeader.contains("bool exit_to_library_requested() noexcept;")
        && bridge.contains("exitToLibraryRequested")
        && bridgeImplementation.contains("goalpad::exit_to_library_requested()"),
      "title Quit preserves kernel exit semantics and publishes one host navigation request")

let nativeReturnRoute = section(content,
                                from: ".onChange(of: session.returnToLibraryRequestID)",
                                to: "#if os(visionOS)")
check(nativeReturnRoute.contains("newRequest != oldRequest")
        && nativeReturnRoute.contains("returnToLibrary()")
        && content.contains("launcherDestination = .library")
        && content.contains("session.shutdown()"),
      "a native title Quit closes the session through the existing Library route")

let controlsGuide = section(session,
                            from: "func presentTouchControlsGuide()",
                            to: "// MARK: - The frame loop")
check(occursInOrder([
    "controlsGuideSuspension.present()",
    "input.stopRumble()",
    "touch.reset()",
    "audio.suspend()",
    "controlsGuideSuspension.dismiss()",
    "currentScenePhase == .active",
    "lifecycle.frameLoopEnabled",
    "audio.resumeIfSuspended()",
], in: controlsGuide),
      "the controls guide suspends frames, input, and audio until safe dismissal")

let lifecycle = section(session,
                        from: "func scenePhaseChanged",
                        to: "private func resetDisplayTiming")
check(!lifecycle.contains("GOALPadRuntimeBridge.stopKernel")
        && !lifecycle.contains("GOALPadRuntimeBridge.startKernel"),
      "background recovery preserves the active native run instead of faking a restart")
check(lifecycle.contains("touch.restoreGameplayChromeAfterInterruption()"),
      "foreground recovery restores discoverable active-gameplay touch chrome")

if failures == 0 {
    print("game lifecycle route checks passed")
} else {
    print("game lifecycle route checks failed: \(failures)")
    Foundation.exit(1)
}
