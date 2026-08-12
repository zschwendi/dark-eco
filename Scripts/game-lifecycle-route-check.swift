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
let bridge = source(at: root + "/GOALPad/Native/GOALPadRuntimeBridge.h")
let bridgeImplementation = source(at: root + "/GOALPad/Native/GOALPadRuntimeBridge.mm")
let surfaceView = source(at: root + "/GOALPad/Game/GameSurfaceView.swift")
let renderSurface = source(at: root + "/GOALPad/Native/GOALPadRenderSurface.mm")
let metalHost = source(at: root + "/GOALPad/Native/GOALPadMetalHost.mm")

let audioSession = section(audio,
                           from: "private func activateSession() throws",
                           to: "private func deactivateSession()")
check(audioSession.contains("setCategory(.playback, mode: .default, options: [.mixWithOthers])")
        && !audioSession.contains(".duckOthers")
        && !audioSession.contains(".interruptSpokenAudioAndMixWithOthers"),
      "game audio mixes with external media without ducking or interrupting speech")
check(audio.contains("setActive(false, options: .notifyOthersOnDeactivation)"),
      "audio shutdown still notifies other active media sessions")

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
check(session.contains("GOALPadRenderSurface.shared.setDetailedFrameStatsEnabled(\n            presentationSettings.developerLogsEnabled)"),
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
check(occursInOrder([
    "let developerLogsEnabled = presentationSettings.developerLogsEnabled",
    "input.pushFrame",
    "GOALPadRuntimeBridge.runFrame(at: targetPresentationTime)",
    "let nativeState = GOALPadRuntimeBridge.gameFrameStateSnapshot",
    "nativeState.exitToLibraryRequested.boolValue",
    "returnToLibraryRequestID &+= 1",
    "framesRun = nativeState.framesRun",
    "let currentMode = nativeState.gameMode",
    "NativeProgressMenuSnapshot(nativeState.progressMenu)",
    "let currentTitleStartState = nativeState.titleStartState",
    "NativeWarpGateTouchSnapshot(\n                nativeState.warpGateTouch)",
    "NativeCutsceneSkipTouchSnapshot(\n                nativeState.cutsceneSkipTouch)",
    "NativeFacePromptTouchSnapshot(\n                nativeState.facePromptTouch)",
    "let currentLookAroundState = nativeState.lookAroundState",
    "let currentSpeederState = nativeState.speederState",
    "let framePresented = endFrame()",
], in: armedTick),
      "the shared frame body preserves input, state-publication, and presentation ordering")
check(occurrenceCount("GOALPadRuntimeBridge.gameFrameStateSnapshot", in: armedTick) == 1
        && !armedTick.contains("GOALPadRuntimeBridge.exitToLibraryRequested")
        && !armedTick.contains("GOALPadRuntimeBridge.framesRun")
        && !armedTick.contains("GOALPadRuntimeBridge.gameMode")
        && !armedTick.contains("GOALPadRuntimeBridge.progressMenuSnapshot")
        && !armedTick.contains("GOALPadRuntimeBridge.titleStartState")
        && !armedTick.contains("GOALPadRuntimeBridge.warpGateTouchSnapshot")
        && !armedTick.contains("GOALPadRuntimeBridge.cutsceneSkipTouchSnapshot")
        && !armedTick.contains("GOALPadRuntimeBridge.facePromptTouchSnapshot")
        && !armedTick.contains("GOALPadRuntimeBridge.lookAroundState")
        && !armedTick.contains("GOALPadRuntimeBridge.speederState"),
      "each successful frame crosses the Objective-C++ bridge for native state exactly once")
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
    "const auto current_mode = game_mode();",
    "snapshot.game_mode = current_mode;",
    "snapshot.progress_menu = progress_menu_snapshot_for_mode(current_mode);",
    "snapshot.title_start_state = title_start_state();",
    "snapshot.warp_gate_touch = warp_gate_touch_snapshot();",
    "snapshot.cutscene_skip_touch = cutscene_skip_touch_snapshot_for_mode(current_mode);",
    "snapshot.face_prompt_touch = face_prompt_touch_snapshot_for_mode(current_mode);",
    "snapshot.look_around_state = look_around_state();",
    "snapshot.speeder_state = speeder_state();",
], in: nativeFrameState) && occurrenceCount("game_mode();", in: nativeFrameState) == 1,
      "the native aggregate preserves read order and reuses one master-mode classification")

let frameStateMapping = section(bridgeImplementation,
                                from: "+ (GOALPadGameFrameStateSnapshot)gameFrameStateSnapshot",
                                to: "+ (GOALPadFrameChainStats)frameChainStats")
check(bridge.contains("typedef struct GOALPadGameFrameStateSnapshot")
        && bridge.contains("@property(class, nonatomic, readonly) GOALPadGameFrameStateSnapshot gameFrameStateSnapshot;")
        && occursInOrder([
            "snapshot.exitToLibraryRequested = core.exit_to_library_requested ? YES : NO;",
            "snapshot.framesRun = core.frames_run;",
            "snapshot.gameMode = GOALPadGameModeFromCore(core.game_mode);",
            "snapshot.progressMenu = GOALPadProgressMenuSnapshotFromCore(core.progress_menu);",
            "snapshot.titleStartState = GOALPadTitleStartStateFromCore(core.title_start_state);",
            "snapshot.warpGateTouch = GOALPadWarpGateTouchSnapshotFromCore(core.warp_gate_touch);",
            "snapshot.cutsceneSkipTouch = GOALPadCutsceneSkipTouchSnapshotFromCore(core.cutscene_skip_touch);",
            "snapshot.facePromptTouch = GOALPadFacePromptTouchSnapshotFromCore(core.face_prompt_touch);",
            "snapshot.lookAroundState = GOALPadLookAroundStateFromCore(core.look_around_state);",
            "snapshot.speederState = GOALPadSpeederStateFromCore(core.speeder_state);",
        ], in: frameStateMapping),
      "the fixed C bridge maps every native frame field without object ownership")

let bootFinished = section(session,
                           from: "private func bootFinished",
                           to: "func shutdown")
check(occursInOrder([
    "if presentationSettings.developerLogsEnabled",
    "startCameraDiagnostics()",
    "cameraDiagnosticsURL = nil",
], in: bootFinished),
      "camera diagnostics start only when developer logs are enabled")

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
