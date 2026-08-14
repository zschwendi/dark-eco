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
let experimentalStereoGate = "#if os(visionOS) && GOALPAD_EXPERIMENTAL_VISION_STEREO"
let project = source(root, "GOALPad.xcodeproj/project.pbxproj")
let app = source(root, "GOALPad/GOALPadApp.swift")
let content = source(root, "GOALPad/ContentView.swift")
let session = source(root, "GOALPad/Game/GameSession.swift")
let gameSurfaceView = source(root, "GOALPad/Game/GameSurfaceView.swift")
let controllerInput = source(root, "GOALPad/Input/ControllerInput.swift")
let touchView = source(root, "GOALPad/Game/TouchControlsView.swift")
let touchGuide = source(root, "GOALPad/Game/TouchControlsGuideView.swift")
let settingsUI = source(root, "GOALPad/Saves/SaveSyncController.swift")
let libraryUI = source(root, "GOALPad/Library/GameLibraryView.swift")
let visionCardActivation = section(libraryUI,
                                   from: "#if os(visionOS)\n        tileSurface",
                                   to: "#else")
let surface = source(root, "GOALPad/Vision/VisionWindowStereoSurface.swift")
let submissionWatchdog = source(root, "GOALPad/Vision/VisionStereoSubmissionWatchdog.swift")
let clipPlan = source(root, "GOALPad/Vision/VisionWindowStereoClipPlan.swift")
let host = source(root, "GOALPad/Native/GOALPadMetalHost.mm")
let renderSurface = source(root, "GOALPad/Native/GOALPadRenderSurface.mm")
let bridge = source(root, "GOALPad/Native/GOALPadRuntimeBridge.h")
let ornament = source(root, "GOALPad/Vision/VisionControllerStatusOrnament.swift")
let pausedEcoOrnament = source(root, "GOALPad/Vision/VisionPausedEcoOrnament.swift")
let metalRenderer = source(root, "OpenGOAL/game/graphics/pipelines/metal/metal_renderer.mm")
let eyeMarker = source(
    root,
    "OpenGOAL/game/graphics/pipelines/metal/metal_stereo_eye_marker.h"
)

let gameplaySurface = section(content,
                              from: "private struct GameplaySurface: View",
                              to: "/// The game's own startup")
check(gameplaySurface.components(separatedBy: "gameSurface").count - 1 == 3,
      "both GameplaySurface layouts use the shared presentation surface")
check(gameplaySurface.contains("onFrame: { session.tick(targetPresentationTime: $0) }")
        && gameplaySurface.contains(experimentalStereoGate)
        && gameplaySurface.contains("isStereoRendererReady: session.isRunning")
        && gameplaySurface.contains("onStereoFrame: { session.tickStereo(request: $0) }")
        && !gameplaySurface.contains("stereoMaximumWidthPixels")
        && !gameplaySurface.contains("stereoMaximumHeightPixels"),
      "only the opt-in branch wires stereo while the shared 2D callback remains available")
check(gameSurfaceView.contains(".onChange(of: isStereoRendererReady, initial: true)")
        && gameSurfaceView.contains(
            "setStereoRendererAvailable(isReady && onStereoFrame != nil)"
        )
        && !gameSurfaceView.contains(
            "setStereoRendererAvailable(onStereoFrame != nil)"
        ),
      "stereo remains unavailable through boot and follows running-session readiness changes")
check(gameSurfaceView.contains("import GameController")
        && gameSurfaceView.components(
            separatedBy: ".handlesGameControllerEvents(matching: .gamepad)"
        ).count - 1 == 3
        && occursInOrder([
            experimentalStereoGate,
            "VisionWindowStereoSurfaceView { frame in",
            ".handlesGameControllerEvents(matching: .gamepad)",
            "} else {",
            "conventionalSurface",
            ".handlesGameControllerEvents(matching: .gamepad)",
            "#elseif os(visionOS)",
            "conventionalSurface",
            ".handlesGameControllerEvents(matching: .gamepad)",
        ], in: gameSurfaceView)
        && !gameSurfaceView.contains("VisionGamepadEventRoutingAnchor")
        && !gameSurfaceView.contains("GCEventInteraction()")
        && !gameSurfaceView.contains("addInteraction("),
      "the shipping 2D root and both dormant stereo roots route gamepad events directly")
let shippingVisionSurface = section(gameSurfaceView,
                                    from: "#elseif os(visionOS)",
                                    to: "#else")
check(shippingVisionSurface.contains("conventionalSurface")
        && shippingVisionSurface.contains(
            ".handlesGameControllerEvents(matching: .gamepad)"
        )
        && !shippingVisionSurface.contains("Stereo")
        && !shippingVisionSurface.contains("Reality"),
      "normal visionOS builds structurally select only the conventional game surface")
check(app.contains(experimentalStereoGate + "\n    @State private var visionPresentation")
        && app.contains(experimentalStereoGate + "\n            ContentView()")
        && !app.contains("GameCenter")
        && content.contains(experimentalStereoGate
            + "\n    @Environment(VisionPresentationCoordinator.self)")
        && settingsUI.contains(experimentalStereoGate
            + "\n            Toggle(\"Stereoscopic 3D\"")
        && !project.contains("GOALPAD_EXPERIMENTAL_VISION_STEREO"),
      "stereo is source-gated and no normal Xcode configuration opts into it")

let stereoTick = section(session,
                         from: "func tickStereo(request:",
                         to: "private func runArmedTick")
check(occursInOrder([
    "else { return .skipped }",
    "switch surface.reserveStereoFrame()",
    "case .busy:",
    "return .busy",
    "var reservationNeedsCancellation = true",
    "guard let frame = request.makeFrame()",
    "GOALPadStereoRenderTarget(",
    "GOALPadStereoRenderTarget(",
    "surface.beginReservedStereoFrame(",
    "commandBuffer: frame.commandBuffer",
    "frame.commandBuffer.commit()",
    "reservationNeedsCancellation = false",
    "var completion = GOALPadStereoFrameCompletion.skipped",
    "runArmedTick(targetPresentationTime:",
    "completion = surface.endStereoFrame()",
    "return completion == .submitted",
    "case .submitted:",
    "case .skipped:",
    "return .skipped",
    "case .failed:",
], in: stereoTick)
        && stereoTick.range(of: "return .busy")!.upperBound
            < stereoTick.range(of: "request.makeFrame()")!.lowerBound
        && stereoTick.range(of: "request.makeFrame()")!.upperBound
            < stereoTick.range(of: "runArmedTick")!.lowerBound,
      "busy exits before LowLevelTexture replacement and one reserved pair owns one game tick")

let sharedTick = section(session,
                         from: "private func runArmedTick",
                         to: "private func updateNativeMenuState")
check(sharedTick.components(separatedBy: "GOALPadRuntimeBridge.runFrame(").count - 1 == 1,
      "the shared tick advances the GOAL kernel exactly once")
check(sharedTick.components(separatedBy: "saveSync.gameplaySaveCompleted()").count - 1 == 1
        && sharedTick.components(separatedBy: "input.applyRumble()").count - 1 == 1,
      "changed-save notification and rumble side effects remain single-shot")
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
                               from: "private var controlsContent: some View",
                               to: "@ViewBuilder\n    private var graphicsContent: some View")
check(controlsSettings.contains("ControllerBindingsSettingsView")
        && controlsSettings.contains("#if !os(visionOS)\n            Picker(\"Primary Controller\"")
        && controlsSettings.contains("#if !os(visionOS)\n            NavigationLink {\n                KeyboardMouseBindingsSettingsView"),
      "visionOS exposes ordinary gamepad bindings without alternate input selection")

check(bridge.contains("GOALPadStereoRenderTarget")
        && bridge.contains("simd_float4x4 clipFromGameClip")
        && bridge.contains("reserveStereoFrame")
        && bridge.contains("beginReservedStereoFrameAtTime")
        && bridge.contains("cancelReservedStereoFrame")
        && bridge.contains("endStereoFrame"),
      "the Objective-C bridge exposes reserve, lazy arm, cancel, and async submission")
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
let liveChainValidation = section(host,
                                  from: "bool valid_live_chain",
                                  to: "// ---------------------------------------------------------------------------------------------\n// the seam")
let renderChain = section(host,
                          from: "void render_chain(const void* ee_base",
                          to: "#if defined(__aarch64__)")
let hostStackForwarding = section(host,
                                  from: "std::uint64_t render_chain_on_host_stack",
                                  to: "// ---------------------------------------------------------------------------------------------\n// the seam")
check(!host.contains("FixedChunkDmaCopier") && !host.contains("set_input_data")
        && sendChain.components(
            separatedBy: "render_chain_without_goal_stack(ee_base, chain_offset);"
        ).count - 1 == 1,
      "one submitted game chain is rendered synchronously from live EE memory without a frame copy")
check(liveChainValidation.contains("ee_base != nullptr && ee_base == g_ee_main_mem")
        && liveChainValidation.contains("chain_offset >= static_cast<std::uint32_t>(EE_MAIN_MEM_LOW_PROTECT)")
        && liveChainValidation.contains("chain_offset <= static_cast<std::uint32_t>(EE_MAIN_MEM_SIZE) - kDmaTagBytes")
        && liveChainValidation.contains("(chain_offset & (kDmaTagBytes - 1)) == 0")
        && occursInOrder([
            "if (!valid_live_chain(ee_base, chain_offset))",
            "g_host.stats.chains_dropped++",
            "return;",
            "g_host.chains_in_frame++",
            "render_chain_without_goal_stack(ee_base, chain_offset);",
        ], in: sendChain),
      "live DMA rendering fails closed on base, readable range, and tag alignment before dispatch")
check(renderChain.contains("const auto* chain_data = static_cast<const std::uint8_t*>(ee_base);")
        && renderChain.contains("g_host.stereo_command_buffer, chain_data, chain_offset")
        && renderChain.contains("opts, g_host.frame_layer, chain_data, chain_offset")
        && hostStackForwarding.contains("render_chain(reinterpret_cast<const void*>(ee_base)")
        && hostStackForwarding.contains("reinterpret_cast<std::uint64_t>(ee_base),")
        && hostStackForwarding.contains("chain_offset, 0, 0, 0, 0)")
        && hostStackForwarding.contains("render_chain(ee_base, chain_offset);")
        && host.components(
            separatedBy: "chain_data = static_cast<const std::uint8_t*>(ee_base);"
        ).count - 1 == 1
        && !host.contains("get_last_result()"),
      "ordinary, stereo, and alternate-stack paths forward the same call-scoped live chain")
check(host.contains("render_chain_frame_to_external_stereo_targets(")
        && host.contains("g_host.stereo_command_buffer")
        && !host.contains("wait_for_last_chain_frame(1.0)"),
      "both native eye encodes borrow one command buffer without a synchronous GPU wait")
check(occursInOrder([
    "MetalHostStereoFrameCompletion metal_host_end_stereo_frame()",
    "const bool rendered = g_host.frame_rendered;",
    "(void)close_frame(true, &submitted);",
    "if (!submitted)",
    "MetalHostStereoFrameCompletion::skipped",
    "MetalHostStereoFrameCompletion::submitted",
], in: host)
        && bridge.contains("GOALPadStereoFrameCompletion")
        && renderSurface.contains("MetalHostStereoFrameCompletion::failed"),
      "native close distinguishes a submitted empty tick from encode or submit failure")

let rejectedSurfaceAPIs = [
    "TextureResource.DrawableQueue", "nextDrawable()", "presentOnSceneUpdate()",
    "pendingPresentation", "VisionWindowStereoDrawableQuarantine", "CADisplayLink",
]
check(rejectedSurfaceAPIs.allSatisfy { !surface.contains($0) }
        && surface.components(separatedBy: "LowLevelTexture(descriptor: descriptor)").count - 1 == 2
        && surface.components(separatedBy: "TextureResource(from:").count - 1 == 2,
      "the product surface owns two stable LowLevelTextures and none of the rejected APIs")
check(occursInOrder([
    "VisionWindowStereoRenderSystem.registerSystem()",
    "content.add(resources.presentationEntity)",
    "updatingSystemWhen: .rendering",
], in: surface)
        && surface.contains("cadence.scheduledTime(for: updateTime)")
        && surface.contains("let disposition = renderFrame(request)"),
      "RealityKit rendering updates are the sole producer behind the 90 Hz cadence gate")
check(occursInOrder([
    "let leftReplacement = leftTexture.replace(using: commandBuffer)",
    "let rightReplacement = rightTexture.replace(using: commandBuffer)",
    "Self.encodePairedClear(",
    "commandBuffer: commandBuffer",
], in: surface),
      "one caller-owned command buffer acquires and initializes both LowLevelTexture replacements")
check(surface.contains("watchdog.observe(disposition) == .failClosed")
        && submissionWatchdog.contains("defaultMaximumConsecutiveBusyUpdates = 6")
        && submissionWatchdog.contains("struct VisionStereoCadenceGate")
        && submissionWatchdog.contains("struct VisionStereoLivenessWatchdog")
        && surface.contains("liveness.heartbeat(at: updateTime)")
        && surface.contains("Task.sleep(for: .milliseconds(50))")
        && surface.contains("liveness.hasTimedOut(at: CACurrentMediaTime())")
        && surface.contains("resources?.setSceneActive(phase == .active)"),
      "busy/error and missing-update watchdogs fail closed behind the deterministic cadence")
check(surface.components(separatedBy: "prepareStereoFallback()").count - 1 == 1
        && bridge.contains("prepareStereoFallback")
        && renderSurface.contains("metal_host_prepare_stereo_fallback()")
        && metalRenderer.contains("m_external_stream.quarantine_in_flight_pages()")
        && metalRenderer.contains("m_external_stereo_disabled = true")
        && metalRenderer.contains("m_external_stream_submission = 0"),
      "fallback quarantines stalled stream pages and removes the Comfort renderer wait")

let rendererStereo = section(
    metalRenderer,
    from: "bool MetalRenderer::render_chain_frame_to_external_stereo_targets(",
    to: "bool MetalRenderer::submit_external_stereo_frame"
)
let rendererSubmit = section(
    metalRenderer,
    from: "bool MetalRenderer::submit_external_stereo_frame",
    to: "bool MetalRenderer::render_chain_frame_impl"
)
let rendererEyeMarker = section(
    metalRenderer,
    from: "void MetalRenderer::encode_stereo_eye_markers",
    to: "bool MetalRenderer::submit_external_stereo_frame"
)
check(rendererStereo.components(separatedBy: "command_buffer, chain_data").count - 1 == 2
        && rendererStereo.contains("m_chain_stats.last_views_rendered = 2"),
      "both eye passes append to the same borrowed command buffer")
check(eyeMarker.contains("#define GOALPAD_VISION_STEREO_EYE_MARKERS 0")
        && eyeMarker.contains("kStereoEyeMarkerInset = 14")
        && eyeMarker.contains("kStereoEyeMarkerLength = 16")
        && metalRenderer.contains("#if GOALPAD_VISION_STEREO_EYE_MARKERS")
        && metalRenderer.contains("encode_stereo_eye_markers(command_buffer, left, right)")
        && metalRenderer.contains("MTLPixelFormatBGRA8Unorm_sRGB")
        && metalRenderer.contains("MTLStorageModeMemoryless")
        && metalRenderer.contains("copyFromBuffer:source")
        && metalRenderer.contains("std::array<u8, 4>{255, 0, 255, 255}")
        && metalRenderer.contains("std::array<u8, 4>{255, 255, 0, 255}")
        && occursInOrder([
            "const bool right_rendered",
            "if (right_rendered)",
            "encode_stereo_eye_markers(command_buffer, left, right)",
            "return right_rendered",
        ], in: rendererStereo)
        && !rendererEyeMarker.contains("waitUntilCompleted")
        && !rendererEyeMarker.contains("wait_for_last_chain_frame"),
      "the opt-in native marker stamps completed eye textures without a frame-loop wait")
check(rendererSubmit.components(separatedBy: "[command_buffer commit]").count - 1 == 1
        && rendererSubmit.contains("addCompletedHandler")
        && !rendererSubmit.contains("waitUntilCompleted"),
      "the paired command buffer commits once and reports completion asynchronously")

check(app.components(separatedBy: "WindowGroup").count - 1 == 1
        && app.contains(experimentalStereoGate)
        && app.contains(".environment(visionPresentation)")
        && !app.contains("GOALPadVisionSpatialScenes")
        && !app.contains("VisionPresentationSessionBridge"),
      "the product declares one Shared Space WindowGroup and gates its stereo environment")
check(surface.contains("VisionWindowStereoClipPlanner.makePlan()")
        && clipPlan.contains("defaultNormalizedDepthDisparitySlope")
        && clipPlan.contains("defaultConvergenceDepth")
        && clipPlan.contains("-eyeSlope * convergenceDepth")
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
check(content.contains(
            "visibility: visionEcoSettingsUsesCenteredPlacement ? .visible : .hidden"
        )
        && content.contains("attachmentAnchor: .scene(.top)")
        && content.components(
            separatedBy: "VisionPausedEcoOrnament { presentSettings() }"
        ).count - 1 == 1
        && !content.contains("attachmentAnchor: .scene(.topLeading)")
        && content.contains("session.input.isConnected && session.isRunning")
        && content.contains("&& NativeEcoSettingsPresentation.isVisible(")
        && content.contains("mode: session.gameMode")
        && content.contains("progress: session.progressMenuSnapshot")
        && content.contains("runReadiness: session.runReadiness"),
      "one Settings ornament centers only for connected native menu state")
check(pausedEcoOrnament.contains("Button(action: openSettings)")
        && pausedEcoOrnament.contains("Image(systemName: \"gearshape\")")
        && !pausedEcoOrnament.contains("Text(\"DARK ECO\")")
        && pausedEcoOrnament.contains(".frame(width: 42, height: 42)")
        && pausedEcoOrnament.contains(".glassBackgroundEffect(in: Circle())")
        && pausedEcoOrnament.contains(".accessibilityLabel(\"Settings\")"),
      "the always-available ornament is an icon-only accessible glass Settings control")
check(libraryUI.contains("ToolbarItem(placement: .principal)")
        && libraryUI.contains("} label: { mainMenuLabel }")
        && libraryUI.contains(".menuStyle(.button)")
        && libraryUI.contains(".buttonStyle(.plain)")
        && !libraryUI.contains("#if os(visionOS)\n            .overlay(alignment: .top)"),
      "the visionOS Library shares the centered toolbar menu without an overlay or outer system pill")
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
check(content.contains("NavigationStack {\n            SaveSettingsView(")
        && !content.contains("SettingsTitleListView")
        && content.contains("#if os(iOS)\n                .toolbar {")
        && content.contains("Button(\"Done\") { dismiss() }")
        && content.contains("#elseif !os(visionOS)\n        .toolbar {\n            ToolbarItem(placement: .confirmationAction)")
        && content.contains("#else\n        .toolbar {\n            ToolbarItem(placement: .topBarLeading)")
        && content.contains("Image(systemName: \"xmark\")")
        && content.contains(".accessibilityLabel(\"Close Settings\")")
        && content.contains("ToolbarItem(placement: .topBarTrailing)")
        && content.contains("Image(systemName: \"power\")"),
      "visionOS Settings owns top-leading Close and top-trailing power actions while iOS retains Done")
check(visionCardActivation.contains(".contentShape([.interaction, .hoverEffect],")
        && visionCardActivation.contains("RoundedRectangle(cornerRadius: 16, style: .continuous)")
        && visionCardActivation.contains(".onTapGesture(perform: activate)")
        && visionCardActivation.contains(".accessibilityAddTraits(.isButton)")
        && visionCardActivation.contains(".hoverEffect { effect, isActive, _ in")
        && visionCardActivation.contains("effect.scaleEffect(isActive ? 1.025 : 1)")
        && !visionCardActivation.contains("Button("),
      "visionOS library cards animate their full rounded-card shape instead of a system oval")

if failures == 0 {
    print("visionOS stereo integration checks passed")
} else {
    print("visionOS stereo integration checks failed: \(failures)")
    Foundation.exit(1)
}
