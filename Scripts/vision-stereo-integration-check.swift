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

private func source(_ root: String, _ path: String) -> String {
    do {
        return try String(contentsOfFile: root + "/" + path, encoding: .utf8)
    } catch {
        print("  FAIL could not read \(path): \(error.localizedDescription)")
        Foundation.exit(1)
    }
}

private func section(_ source: String, from start: String, to end: String) -> String {
    guard let lower = source.range(of: start),
          let upper = source.range(of: end, range: lower.upperBound..<source.endIndex) else {
        print("  FAIL could not isolate \(start)")
        failures += 1
        return ""
    }
    return String(source[lower.lowerBound..<upper.lowerBound])
}

private func occursInOrder(_ values: [String], in source: String) -> Bool {
    var lower = source.startIndex
    for value in values {
        guard let range = source.range(of: value, range: lower..<source.endIndex) else {
            return false
        }
        lower = range.upperBound
    }
    return true
}

guard CommandLine.arguments.count == 2 else {
    print("usage: vision-stereo-integration-check <repository-root>")
    Foundation.exit(2)
}

let root = CommandLine.arguments[1]
let app = source(root, "GOALPad/GOALPadApp.swift")
let content = source(root, "GOALPad/ContentView.swift")
let session = source(root, "GOALPad/Game/GameSession.swift")
let gameSurfaceView = source(root, "GOALPad/Game/GameSurfaceView.swift")
let controllerInput = source(root, "GOALPad/Input/ControllerInput.swift")
let touchView = source(root, "GOALPad/Game/TouchControlsView.swift")
let touchGuide = source(root, "GOALPad/Game/TouchControlsGuideView.swift")
let settingsUI = source(root, "GOALPad/Saves/SaveSyncController.swift")
let libraryUI = source(root, "GOALPad/Library/GameLibraryView.swift")
let surface = source(root, "GOALPad/Vision/VisionWindowStereoSurface.swift")
let clipPlan = source(root, "GOALPad/Vision/VisionWindowStereoClipPlan.swift")
let host = source(root, "GOALPad/Native/GOALPadMetalHost.mm")
let renderSurface = source(root, "GOALPad/Native/GOALPadRenderSurface.mm")
let bridge = source(root, "GOALPad/Native/GOALPadRuntimeBridge.h")
let ornament = source(root, "GOALPad/Vision/VisionControllerStatusOrnament.swift")
let pausedEcoOrnament = source(root, "GOALPad/Vision/VisionPausedEcoOrnament.swift")

let gameplaySurface = section(content,
                              from: "private struct GameplaySurface: View",
                              to: "/// The game's own startup")
check(gameplaySurface.components(separatedBy: "gameSurface").count - 1 == 3,
      "both GameplaySurface layouts use the shared mono/stereo surface")
check(gameplaySurface.contains("onFrame: { session.tick(targetPresentationTime: $0) }")
        && gameplaySurface.contains("isStereoRendererReady: session.isRunning")
        && gameplaySurface.contains("onStereoFrame: { session.tickStereo(frame: $0) }")
        && !gameplaySurface.contains("stereoMaximumWidthPixels")
        && !gameplaySurface.contains("stereoMaximumHeightPixels"),
      "the shared surface wires both callbacks without the rejected per-eye render-budget cap")
check(gameSurfaceView.contains(".onChange(of: isStereoRendererReady, initial: true)")
        && gameSurfaceView.contains(
            "setStereoRendererAvailable(isReady && onStereoFrame != nil)"
        )
        && !gameSurfaceView.contains(
            "setStereoRendererAvailable(onStereoFrame != nil)"
        ),
      "stereo remains unavailable through boot and follows running-session readiness changes")
let gamepadRouting = section(gameSurfaceView,
                             from: "private final class VisionGamepadEventRoutingAnchor",
                             to: "/// Xcode's generated iPad scene manifest")
check(gameSurfaceView.contains("import GameController")
        && gameSurfaceView.contains("VisionGamepadEventRoutingAnchorView()")
        && gameSurfaceView.contains(".frame(width: 0, height: 0)")
        && gameSurfaceView.contains(".allowsHitTesting(false)")
        && gameSurfaceView.contains(".accessibilityHidden(true)")
        && gamepadRouting.contains("GCEventInteraction()")
        && gamepadRouting.contains("interaction.handledEventTypes = .gamepad")
        && gamepadRouting.contains("host?.addInteraction(gamepadInteraction)")
        && gamepadRouting.contains("interactionHost?.removeInteraction(gamepadInteraction)")
        && gamepadRouting.contains("isUserInteractionEnabled = false")
        && !gamepadRouting.contains("receivesEventsInView = true"),
      "the gameplay window routes face-button events exclusively through Game Controller without a touch target")

let stereoTick = section(session,
                         from: "func tickStereo(frame:",
                         to: "private func runArmedTick")
check(occursInOrder([
    "else { return .skipped }",
    "GOALPadStereoRenderTarget(",
    "GOALPadStereoRenderTarget(",
    "surface.beginStereoFrame(",
    "else { return .failed }",
    "var completion = GOALPadStereoFrameCompletion.skipped",
    "runArmedTick(targetPresentationTime:",
    "completion = surface.endStereoFrame()",
    "return completion == .completed",
    "if completion == .failed { return .failed }",
    "framePresented ? .rendered : .skipped",
], in: stereoTick), "one stereo callback arms, runs, waits, and ends one shared game tick")

let sharedTick = section(session,
                         from: "private func runArmedTick",
                         to: "private func updateNativeMenuState")
check(sharedTick.components(separatedBy: "GOALPadRuntimeBridge.runFrame(").count - 1 == 1,
      "the shared tick advances the GOAL kernel exactly once")
check(sharedTick.components(separatedBy: "saveSync.gameplayFrameCompleted()").count - 1 == 1
        && sharedTick.components(separatedBy: "input.applyRumble()").count - 1 == 1,
      "frame completion and rumble side effects remain single-shot")
check(sharedTick.contains("#if os(iOS)")
        && sharedTick.contains("input.pushFrame(merging: touch.frameState())")
        && sharedTick.contains("#elseif os(visionOS)\n        input.pushControllerFrame()")
        && controllerInput.contains("controllerOnly: true")
        && controllerInput.contains("keyboardMouseConnected: false"),
      "visionOS accepts only an ordinary gamepad while iOS retains its touch merge")
let startWatching = section(controllerInput,
                            from: "func startWatching()",
                            to: "func stopWatching()")
let stopWatching = section(controllerInput,
                           from: "func stopWatching()",
                           to: "/// Read the physical inputs")
check(startWatching.contains(".GCControllerDidConnect")
        && startWatching.contains(".GCControllerDidDisconnect")
        && startWatching.contains("adoptController(Self.preferredController())")
        && startWatching.contains("#if !os(visionOS)\n        GCController.startWirelessControllerDiscovery()\n        #endif")
        && stopWatching.contains("#if !os(visionOS)\n        GCController.stopWirelessControllerDiscovery()\n        #endif"),
      "visionOS observes system-connected gamepads without wireless discovery")
let controlsSettings = section(settingsUI,
                               from: "private var controlsSection: some View",
                               to: "@ViewBuilder\n    private func profileSection")
check(controlsSettings.contains("ControllerBindingsSettingsView")
        && controlsSettings.contains("#if !os(visionOS)\n            Picker(\"Primary Controller\"")
        && controlsSettings.contains("#if !os(visionOS)\n            NavigationLink {\n                KeyboardMouseBindingsSettingsView"),
      "visionOS exposes ordinary gamepad bindings without alternate input selection")

check(bridge.contains("GOALPadStereoRenderTarget")
        && bridge.contains("simd_float4x4 clipFromGameClip")
        && bridge.contains("beginStereoFrameAtTime")
        && bridge.contains("endStereoFrame"),
      "the Objective-C bridge carries borrowed textures and column-major per-eye matrices")
check(renderSurface.contains("memcpy(leftView.clip_from_game_clip.data(), &leftTransform")
        && renderSurface.contains("memcpy(rightView.clip_from_game_clip.data(), &rightTransform"),
      "Objective-C++ copies both Swift matrices into native column-major storage")
check(occursInOrder([
    "const auto valid_view =",
    "!valid_view(left)",
    "!valid_view(right)",
    "const bool released_stale_art = evict_unwanted_level_art();",
], in: host), "both borrowed target descriptors are rejected before native frame mutation")

let sendChain = section(host, from: "void host_send_chain", to: "uint32_t host_vsync")
check(sendChain.components(separatedBy: "set_input_data").count - 1 == 1
        && sendChain.components(separatedBy: "render_chain_without_goal_stack();").count - 1 == 1,
      "one submitted game chain is copied once before the two-view renderer runs")
check(host.contains("render_chain_frame_to_external_stereo_targets(")
        && occursInOrder([
            "wait_for_last_chain_frame(1.0)",
            "g_host.stereo_left = {};",
            "g_host.stereo_right = {};",
        ], in: host),
      "native completion is awaited before borrowed stereo targets are released")
check(occursInOrder([
    "MetalHostStereoFrameCompletion metal_host_end_stereo_frame()",
    "const bool rendered = g_host.frame_rendered;",
    "const bool completed = close_frame(true);",
    "MetalHostStereoFrameCompletion::skipped",
    "MetalHostStereoFrameCompletion::completed",
    "MetalHostStereoFrameCompletion::failed",
], in: host)
        && bridge.contains("GOALPadStereoFrameCompletion")
        && renderSurface.contains("MetalHostStereoFrameCompletion::failed"),
      "native frame close distinguishes an empty tick from completion failure")

let drawFrame = section(surface,
                        from: "private func drawFrame",
                        to: "private func renderNextFrame")
check(occursInOrder([
    "let disposition = renderNextFrame(at: presentationTime)",
    "guard disposition == .failed else { return }",
    "deferStereoSurfaceFailure(",
], in: drawFrame) && !drawFrame.contains("drawablePair"),
      "only a true render failure schedules fallback after the drawable scope returns")

let renderNextFrame = section(surface,
                              from: "private func renderNextFrame",
                              to: "private func deferStereoSurfaceFailure")
check(occursInOrder([
    "let drawablePair = resources.nextDrawablePair()",
    "return .skipped",
    "let disposition = renderFrame(frame)",
    "case .skipped:",
    "case .rendered:",
    "resources.retainForSceneUpdate(drawablePair)",
    "case .failed:",
    "VisionWindowStereoDrawableQuarantine.shared.retain(drawablePair)",
], in: renderNextFrame) && !renderNextFrame.contains("presentOnSceneUpdate()"),
      "the producer retains one completed pair while failed frames remain quarantined")

let presentationSystem = section(
    surface,
    from: "private final class VisionWindowStereoPresentationSystem",
    to: "/// A timed-out GPU submission"
)
let resourcePresentation = section(
    surface,
    from: "func nextDrawablePair()",
    to: "private static func makeQueue"
)
check(surface.contains("VisionWindowStereoPresentationSystem.registerSystem()")
        && surface.contains("content.add(resources.presentationEntity)")
        && presentationSystem.contains("updatingSystemWhen: .rendering")
        && presentationSystem.contains("presentPendingPair()"),
      "paired publication is driven only by RealityKit rendering scene updates")
check(occursInOrder([
    "guard pendingPresentation == nil",
    "return DrawablePair(left: left, right: right)",
    "func retainForSceneUpdate(_ pair: DrawablePair)",
    "precondition(pendingPresentation == nil)",
    "pendingPresentation = pair",
    "func presentPendingPair()",
    "guard let pair = pendingPresentation else { return }",
    "pair.left.presentOnSceneUpdate()",
    "pair.right.presentOnSceneUpdate()",
    "pendingPresentation = nil",
], in: resourcePresentation)
        && surface.components(separatedBy: "presentOnSceneUpdate()").count - 1 == 2
        && !surface.contains(".present()"),
      "exactly one completed pair is retained and both eyes publish in the same scene update")

let deferredFailure = section(surface,
                              from: "private func deferStereoSurfaceFailure",
                              to: "@MainActor\nprivate final class VisionWindowStereoResources")
check(occursInOrder([
    "Task { @MainActor in",
    "await Task.yield()",
    "coordinator.stereoSurfaceFailed(message)",
], in: deferredFailure)
        && deferredFailure.contains("private final class VisionWindowStereoDrawableQuarantine")
        && deferredFailure.contains("pairs.append(pair)")
        && surface.components(separatedBy: "deferStereoSurfaceFailure(").count - 1 == 3,
      "render failures quarantine borrowed drawables before deferred fail-closed mutation")

check(app.components(separatedBy: "WindowGroup").count - 1 == 1
        && app.contains(".environment(visionPresentation)")
        && !app.contains("GOALPadVisionSpatialScenes")
        && !app.contains("VisionPresentationSessionBridge"),
      "the product declares one bounded Shared Space WindowGroup")
check(surface.contains("VisionWindowStereoClipPlanner.makePlan()")
        && clipPlan.contains("defaultNormalizedFarPlaneSeparation")
        && clipPlan.contains("let halfSeparation")
        && !surface.contains("windowFromHead")
        && !clipPlan.contains("headFromEyes"),
      "the fixed pair derives only from Jak's existing game-camera clip projection")
check(surface.contains("private func pixelDimension(_ points: CGFloat)")
        && surface.contains(
            "min(max(Int((points * displayScale).rounded(.up)), 1), 4_096)"
        )
        && !surface.contains("private func fittedPixelDimensions")
        && !gameSurfaceView.contains("stereoMaximumWidthPixels")
        && !gameSurfaceView.contains("stereoMaximumHeightPixels"),
      "stereo restores the native window pixel size while retaining the 4096 safety bound")

let visionDirectory = root + "/GOALPad/Vision"
let visionFiles = FileManager.default.enumerator(atPath: visionDirectory)?.compactMap {
    ($0 as? String).flatMap { $0.hasSuffix(".swift") ? $0 : nil }
} ?? []
let visionProductSource = visionFiles.map { source(root, "GOALPad/Vision/" + $0) }
    .joined(separator: "\n") + app
let forbiddenSpatialAPIs = [
    "ImmersiveSpace", "openImmersiveSpace", "dismissImmersiveSpace", "import ARKit",
    "ARKitSession", "WorldTrackingProvider", "queryDeviceAnchor", "HeadTracker",
    "head tracking", "head-relative", "CompositorLayer",
]
check(forbiddenSpatialAPIs.allSatisfy { !visionProductSource.contains($0) },
      "vision product sources contain no immersive, tracking, or compositor scene path")
check(!FileManager.default.fileExists(
        atPath: root + "/GOALPad/Vision/VisionWindowStereoHeadTracker.swift")
        && !FileManager.default.fileExists(
            atPath: root + "/GOALPad/Vision/VisionPresentationScenes.swift")
        && !FileManager.default.fileExists(
            atPath: root + "/GOALPad/Vision/VisionStereoCompositorProofRenderer.swift"),
      "the obsolete immersive and tracked proof files are absent")

check(content.contains("#if os(iOS)\n                TouchControlsView")
        && content.contains("#if os(iOS)\n    @State private var isShowingTouchControlsGuide")
        && content.contains("#if os(iOS)\n        .sheet(isPresented: $isShowingTouchControlsGuide")
        && !gameplaySurface.contains("TouchControlsView"),
      "visionOS excludes gameplay touch controls and their guide UI")
check(touchView.hasPrefix("#if os(iOS)\n") && touchView.hasSuffix("#endif\n")
        && touchGuide.hasPrefix("#if os(iOS)\n") && touchGuide.hasSuffix("#endif\n"),
      "the visionOS target compiles out touch views and hit regions entirely")
let gameplayOverlay = section(content,
                              from: "if session.isRunning {",
                              to: "} else if session.isBooting")
check(gameplayOverlay.contains("#if !os(visionOS)")
        && gameplayOverlay.contains("DiagnosticsOverlay(session: session)"),
      "visionOS compiles out the gameplay diagnostics overlay")
check(content.contains("visibility: session.input.isConnected ? .hidden : .visible")
        && content.contains("attachmentAnchor: .scene(.top)"),
      "the controller ornament follows supported gamepad connection state at the window top")
check(content.contains("visibility: visionEcoSettingsVisible ? .visible : .hidden")
        && content.contains("attachmentAnchor: .scene(.top)")
        && content.contains("contentAlignment: .bottom")
        && !content.contains("attachmentAnchor: .scene(.topLeading)")
        && content.contains("VisionPausedEcoOrnament { presentSettings(.jak1) }")
        && content.contains("session.isRunning && NativeEcoSettingsPresentation.isVisible(")
        && content.contains("mode: session.gameMode")
        && content.contains("progress: session.progressMenuSnapshot")
        && content.contains("runReadiness: session.runReadiness"),
      "the top-center Eco ornament reuses the paused iPad settings gate and opens Jak 1 settings")
check(pausedEcoOrnament.contains("Button(action: openSettings)")
        && pausedEcoOrnament.contains("Image(systemName: \"gearshape\")")
        && pausedEcoOrnament.contains("Text(\"ECO\")")
        && pausedEcoOrnament.contains(".glassBackgroundEffect(in: Capsule())")
        && pausedEcoOrnament.contains(".accessibilityLabel(\"Eco Settings\")"),
      "the paused Eco ornament is a compact accessible glass settings control")
let controllerMessageOccurrences = ornament.components(separatedBy: "Text(\"No controller detected.\")").count - 1
check(controllerMessageOccurrences == 1
        && ornament.contains(".foregroundStyle(labelForegroundStyle)")
        && ornament.contains("LinearGradient(")
        && ornament.contains("@State private var highlightLocation: CGFloat = -1")
        && ornament.contains("startPoint: UnitPoint(x: highlightLocation - 1, y: 0.5)")
        && ornament.contains("endPoint: UnitPoint(x: highlightLocation + 1, y: 0.5)")
        && ornament.contains("withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false))")
        && ornament.contains("highlightLocation = 1")
        && ornament.contains("guard !reduceMotion else")
        && ornament.contains("colors: [.purple, .purple]")
        && !ornament.contains(".overlay")
        && !ornament.contains(".mask")
        && !ornament.contains(".frame(width:")
        && ornament.contains(".allowsHitTesting(false)")
        && ornament.contains(".accessibilityLabel(\"No controller detected.\")"),
      "the full noninteractive purple controller message shimmers without a duplicate or masked label")
check(content.contains("SettingsTitleListView(\n                openJak1:")
        && content.contains("close: { dismiss() }")
        && content.contains("#if os(visionOS)\n        .toolbar {\n            ToolbarItem(placement: .topBarLeading)")
        && content.contains("Image(systemName: \"xmark\")")
        && content.contains(".accessibilityLabel(\"Close Settings\")")
        && content.contains("#if !os(visionOS)\n        .toolbar {\n            ToolbarItem(placement: .confirmationAction)")
        && content.contains("Button(\"Done\") { dismiss() }"),
      "the visible visionOS title picker owns a top-leading Close action while iOS retains Done")
check(libraryUI.contains("#if os(visionOS)\n            .contentShape([.interaction, .hoverEffect],")
        && libraryUI.contains("RoundedRectangle(cornerRadius: 16, style: .continuous)")
        && libraryUI.contains(".hoverEffect(.highlight)"),
      "visionOS library cards use their full rounded-card shape for interaction and hover")

if failures == 0 {
    print("visionOS stereo integration checks passed")
} else {
    print("visionOS stereo integration checks failed: \(failures)")
    Foundation.exit(1)
}
