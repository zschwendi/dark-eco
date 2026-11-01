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
        exit(1)
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

private func count(_ value: String, in source: String) -> Int {
    source.components(separatedBy: value).count - 1
}

guard CommandLine.arguments.count == 2 else {
    print("usage: vision-immersive-proof-integration-check <repository-root>")
    exit(2)
}

let root = CommandLine.arguments[1]
let gate = "#if os(visionOS) && GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE"
let session = source(root, "GOALPad/Game/GameSession.swift")
let content = source(root, "GOALPad/ContentView.swift")
let surfaceView = source(root, "GOALPad/Game/GameSurfaceView.swift")
let proof = source(root, "GOALPad/Vision/Immersive/VisionImmersiveProof.swift")
let sessionStatus = source(root,
    "GOALPad/Vision/Immersive/VisionImmersiveSessionStatus.swift")
let modeControl = source(root, "GOALPad/Vision/Immersive/VisionImmersiveModeControl.swift")
let presenter = source(root, "GOALPad/Vision/Immersive/VisionImmersiveFramePresenter.swift")
let host = source(root, "GOALPad/Native/GOALPadMetalHost.mm")
let renderSurface = source(root, "GOALPad/Native/GOALPadRenderSurface.mm")
let bridge = source(root, "GOALPad/Native/GOALPadRuntimeBridge.h")

print("Frame-loop ownership")
let conventionalTick = section(session, from: "func tick(targetPresentationTime",
                               to: "#if os(visionOS)\n    func tickStereo")
check(occursInOrder([
    "guard wantsFrameCallbacks else { return }",
    "guard immersiveFrameLoopOwner == nil else { return }",
    "guard !VisionImmersiveProofCoordinator.shared.suppressesWindowRendering else { return }",
    "surface.beginFrame(at: targetPresentationTime)",
], in: conventionalTick),
      "the window's display link yields throughout exclusive immersive presentation")
let immersiveTick = section(session, from: "func tickImmersive(", to: "    #endif")
check(occursInOrder([
    "guard wantsFrameCallbacks",
    "immersiveFrameLoopOwner != nil",
    "switch surface.reserveStereoFrame()",
    "var reservationNeedsCancellation = true",
    "surface.rendererCommandQueue?.makeCommandBuffer()",
    "let eyes = (0..<2).map { index in",
    "clipFromEye: camera.clipFromEye",
    "eyeFromGameCameraMeters: camera.eyeFromGameCameraMeters",
    "binocularCullFromGameCameraMeters: camera.binocularCullFromGameCameraMeters",
    "surface.beginReservedStereoFrame(",
    "commandBuffer: commandBuffer, left: eyes[0], right: eyes[1]",
    "runArmedTick(targetPresentationTime: targetPresentationTime)",
    "completion = surface.endStereoFrame()",
], in: immersiveTick)
        && count("GOALPadStereoRenderTarget(", in: immersiveTick) == 2
        && immersiveTick.contains("if let hud = camera.hudClipFromScreenClip")
        && immersiveTick.contains("hudClipFromScreenClip: hud)")
        && !immersiveTick.contains("beginMonoscopicFrame")
        && !immersiveTick.contains("GOALPadRuntimeBridge.runFrame"),
      "one shared game tick constructs and submits two physical native eye targets")
check(session.contains(gate + "\n    func claimImmersiveFrameLoop(")
        && session.contains(gate + "\n    /// While set, the experimental immersive presenter")
        && session.contains("func releaseImmersiveFrameLoop(_ owner: UInt64)")
        && session.contains("GOALPadRenderSurface.shared.prepareStereoFallback()")
        && session.contains("immersiveFrameLoopOwner = nil\n        applyImmersiveActivity()"),
      "ownership is opt-in, owner-scoped, and fallback returns rendering to the window")

print("Conventional window")
check(content.contains("isPresentationEnabled: isConventionalGameplayPresentationEnabled")
        && content.contains(
            "!VisionImmersiveProofCoordinator.shared.suppressesWindowRendering")
        && content.contains(".opacity(isConventionalGameplayPresentationEnabled ? 1 : 0)")
        && content.contains(".allowsHitTesting(isConventionalGameplayPresentationEnabled)")
        && content.contains(".accessibilityHidden(!isConventionalGameplayPresentationEnabled)"),
      "the coordinator's exclusive phase hides and disables conventional window content")
let uiHost = section(surfaceView, from: "private final class MetalHostView: UIView",
                     to: "private struct SurfaceRepresentable: UIViewRepresentable")
check(surfaceView.contains(".opacity(isPresentationEnabled ? 1 : 0)")
        && uiHost.contains("var isPresentationEnabled = true")
        && occursInOrder([
            "if isPresentationEnabled, window != nil, isHostActive {",
            "resumePresentation()",
            "} else {",
            "suspendPresentation()",
        ], in: section(uiHost, from: "var isPresentationEnabled = true",
                      to: "private var frameLink:"))
        && section(uiHost, from: "private var isHostActive:",
                   to: "private func suspendPresentation()")
            .contains("window?.windowScene?.activationState == .foregroundActive")
        && section(uiHost, from: "private func resumePresentation()",
                   to: "private var isHostActive:")
            .contains("guard isPresentationEnabled else {")
        && uiHost.contains("if isPresenting && framesRequested {"),
      "the mounted host hides, detaches, and resumes only in an active conventional scene")
let detachWindowLayer = section(renderSurface, from: "- (void)attachLayer:",
                                to: "- (void)setDrawableSize:")
check(occursInOrder([
    "if (layer == nil)",
    "goalpad::metal_host_end_frame();",
    "_layer = nil;",
    "return;",
], in: detachWindowLayer)
        && !detachWindowLayer.contains("metal_host_stop")
        && !detachWindowLayer.contains("_drawableSize ="),
      "detaching the window closes only an armed frame and preserves renderer geometry")
check(renderSurface.contains("return goalpad::metal_host_device();")
        && renderSurface.contains("return goalpad::metal_host_command_queue();"),
      "the retained renderer device and command queue remain available to the compositor")

print("Coordinator")
let pauseAfterTick = "if disposition != .failed, Self.route(for: session) == .exitForPause {\n"
    + "                return exitForNativePause()\n            }\n            switch disposition {"
let gameTick = section(proof, from: "func tickGame(", to: "private func tickMenuPlane(")
check(occursInOrder([
    "attempt == lifecycle.attempt, lifecycle.isActive, request.isValid",
    "guard let session, session.isRunning, session.title == .jak1 else {",
    "close(reason: .sessionInvalidForTick)",
    "let route = Self.route(for: session)",
    "guard route != .exitForPause else { return exitForNativePause() }",
    "session.input.updateSpatialGestureReference(originFromDevice: request.originFromDevice",
    "if route == .menuPlane {",
    "return tickMenuPlane(",
    "let compatible = lastPerEyeFrame?.request.isOpticallyCompatible(with: request)",
    "cadence.scheduledTime(",
    "scheduledTime ?? (compatible ? nil : request.presentationTime)",
    "let disposition = session.tickImmersive(targetPresentationTime: tickTime,",
    "request: request, target: state.target)",
    pauseAfterTick,
    "if session.usesControllerMenuNavigation {",
    "lastFrame = nil",
    "} else {",
    "lastFrame = .perEye(VisionImmersiveGameFrame(",
    "fade: 1,",
    "request: request))",
    "return presentableLastFrame(for: request)",
], in: gameTick)
        && count("session.tickImmersive(", in: gameTick) == 1
        && occursInOrder([
            "case .perEye(let frame):",
            "frame.request.isOpticallyCompatible(with: request) ? lastFrame : nil",
        ], in: section(proof, from: "private func presentableLastFrame(",
                       to: "func setImmersiveSceneActive(")),
      "the current Jak 1 attempt caches only pose-bound, optically compatible paired frames")
let menuTick = section(proof, from: "private func tickMenuPlane(",
                       to: "private var lastPerEyeFrame")
check(occursInOrder([
    "menuTargetState(width: Int(geometry.internalWidth),",
    "height: Int(geometry.internalHeight),",
    "cadence.scheduledTime(for: request.presentationTime,",
    "let disposition = session.tickImmersiveMenuFrame(",
    "targetPresentationTime: tickTime,",
    pauseAfterTick,
    "lastFrame = .menuPlane(VisionImmersiveMenuFrame(",
    "fade: surface.monoscopicFrameFade,",
    "fail(attempt: attempt, reason: .nativeFailure, message: reason)",
    "return presentableLastFrame(for: request)",
], in: menuTick)
        && !menuTick.contains("tickImmersive(targetPresentationTime"),
      "a native menu renders one conventional frame at window size on the shared game cadence")
let pauseExit = section(proof, from: "private func exitForNativePause()",
                        to: "private var lastPerEyeFrame")
check(proof.contains("VisionImmersiveTickRoute(isNativePaused: isNativePause(session),")
        && proof.contains("VisionImmersiveNativePausePolicy.isNativePause(")
        && proof.contains(
            "usesControllerMenuNavigation: session.usesControllerMenuNavigation)")
        && section(proof, from: "func canOpen(for session: GameSession)",
                   to: "private static func route(")
            .contains("Self.route(for: session) != .exitForPause")
        && occursInOrder([
            "lastFrame = nil",
            "close(reason: .pauseEntered)",
            "return nil",
        ], in: pauseExit)
        && !pauseExit.contains("session") && !pauseExit.contains("fail(")
        && !pauseExit.contains("lifecycle.") && !pauseExit.contains("dismiss")
        && count("close(reason: .pauseEntered)", in: proof) == 1
        && count("exitForNativePause()", in: proof) == 4
        && sessionStatus.contains("case pauseEntered"),
      "native pause, already open or entered by either update, closes through the ordinary "
        + "lifecycle without a failure, never touches the session, and blocks reopening")
let failedAfterTick: (String) -> Bool = { tick in
    let failed = section(section(tick, from: "switch disposition {",
                                 to: "return presentableLastFrame(for: request)"),
                         from: "case .failed", to: "return nil")
    return occursInOrder([
        "let reason = surface.lastError.isEmpty",
        "fail(attempt: attempt, reason: .nativeFailure, message: reason)",
    ], in: failed)
        && !failed.contains("exitForNativePause") && !failed.contains("close(")
}
check(count(pauseAfterTick, in: gameTick) == 1 && count(pauseAfterTick, in: menuTick) == 1
        && count("Self.route(for: session) == .exitForPause", in: proof) == 2
        && count("disposition != .failed, Self.route(for: session) == .exitForPause", in: proof) == 2
        && failedAfterTick(gameTick) && failedAfterTick(menuTick)
        && count("session.tickImmersive(", in: proof) == 1
        && count("session.tickImmersiveMenuFrame(", in: proof) == 1
        && !gameTick.contains("tickImmersiveMenuFrame")
        && !menuTick.contains("session.tickImmersive("),
      "a failed native update reports nativeFailure even if it paused; only a non-failed update "
        + "that paused closes normally, after exactly one native tick")
check(occursInOrder([
    "gameTarget = nil",
    "menuTarget = nil",
    "lastFrame = nil",
], in: section(proof, from: "func presenterStopped(", to: "/// Return frame ownership")),
      "presenter stop releases both targets and the cached frame of either kind")
let menuFrameTick = section(session, from: "func tickImmersiveMenuFrame(",
                            to: "func tickImmersive(")
check(occursInOrder([
    "guard wantsFrameCallbacks",
    "immersiveFrameLoopOwner != nil",
    "switch surface.reserveStereoFrame()",
    "case .busy: return .busy",
    "case .reserved: surface.cancelReservedStereoFrame()",
    "surface.beginMonoscopicFrame(at: targetPresentationTime",
    "runArmedTick(targetPresentationTime: targetPresentationTime)",
    "surface.endFrame()",
], in: menuFrameTick)
        && !menuFrameTick.contains("GOALPadRuntimeBridge.runFrame")
        && !menuFrameTick.contains("GOALPadStereoRenderTarget("),
      "the menu tick is one nonblocking owned game update into the conventional frame path")
check(proof.contains("session.claimImmersiveFrameLoop(attempt)")
        && section(proof, from: "func prepareToOpen(", to: "func openFinished(")
            .contains("cadence.reset()")
        && proof.contains("session.runReadiness == .active"),
      "only active gameplay claims ownership and each opening starts with fresh cadence")
let rendererStart = section(proof, from: "func layerRendererStarted(",
                            to: "/// One game update")
check(occursInOrder([
    "guard let attempt else { return }",
    "lifecycle.rendererArrived(attempt: attempt)",
    "guard effects.startPresenter else { return }",
    "VisionImmersiveFramePresenter.start(",
    "layerRenderer, attempt: attempt, device: device, commandQueue: commandQueue)",
    "fail(attempt: attempt, reason: .presenterStartFailed, message: startFailure)",
    "presenterStopped(attempt: attempt, reason: .presenterStartFailed)",
], in: rendererStart), "only a renderer the lifecycle accepts for the current attempt presents")
check(proof.contains("ImmersiveSpace(id: VisionImmersiveProofCoordinator.spaceID, "
                        + "for: UInt64.self) { attempt in")
        && proof.contains("layerRenderer, attempt: attempt.wrappedValue)")
        && proof.contains("guard canOpen(for: session), let attempt = lifecycle.beginOpen() else {")
        && modeControl.contains("value: attempt")
        && modeControl.contains("coordinator.openFinished(attempt: attempt, result: result)"),
      "each open passes its attempt to the space, so renderers and open results stay bound to it")
check(proof.range(of: #"\bphase\s*=(?!=)"#, options: .regularExpression) == nil
        && !proof.contains("generation"),
      "the coordinator changes phase only through the tested lifecycle")
let applyEffects = section(proof, from: "private func apply(",
                           to: "/// Dismissals run one at a time")
check(occursInOrder([
        "if effects.releaseFrameLoop {",
        "session?.input.setSpatialGesturesEnabled(false)",
        "session?.releaseImmersiveFrameLoop(lifecycle.attempt)",
      ], in: applyEffects)
        && applyEffects.contains("dismissSpace(request: request)")
        && section(proof, from: "func presenterStopped(", to: "/// Return frame ownership")
            .contains("session?.releaseImmersiveFrameLoop(attempt)")
        && proof.contains("Duration.seconds(3)")
        && proof.contains("lifecycle.firstFrameTimedOut("),
      "close, failure, timeout, and invalidation all return frames to the window and dismiss")
let dismissal = section(proof, from: "private func dismissSpace(",
                        to: "private func armFirstFrameTimeout(")
check(occursInOrder([
    "let previous = dismissalTask",
    "await previous?.value",
    "await dismissImmersiveSpace()",
    "self.dismissalFinished(request: request)",
], in: dismissal),
      "the coordinator dismisses one space at a time and reports completion to the lifecycle")
let proofHostEnd = proof.contains("private struct VisionImmersiveProofControl")
    ? "private struct VisionImmersiveProofControl" : "#endif"
let proofHost = section(proof, from: "struct VisionImmersiveProofHost", to: proofHostEnd)
check(proofHost.contains(".onAppear { coordinator.adoptDismissAction(dismissImmersiveSpace) }")
        && proofHost.contains(".onDisappear { coordinator.hostDisappeared(session) }")
        && proofHost.contains("if !isRunning { coordinator.sessionEnded(session) }")
        && !proofHost.contains("await dismissImmersiveSpace()") && !proofHost.contains(".task("),
      "dismissal outlives the window, shell disappearance is observed, and game stop ends the proof")
check(proof.contains("if event.endsPresentation {")
        && proof.contains("close(reason: .sessionStopped)")
        && proof.contains("event: .hostDisappeared,")
        && sessionStatus.contains("case hostDisappeared")
        && sessionStatus.contains("self == .sessionStopped"),
      "window shell visibility never revokes the immersive owner while true session stop does")
check(proof.contains("var suppressesWindowRendering: Bool")
        && proof.contains(".immersionStyle(selection: .constant(.full), in: .full)")
        && proof.contains("configuration.isFoveationEnabled = false")
        && proof.contains("supportedColorFormats(options: [])")
        && proof.contains("pixelFormat: .bgra8Unorm, width: width")
        && proof.contains("pixelFormat: .depth32Float_stencil8, width: width")
        && proof.contains("colorDescriptor.usage = [.renderTarget, .shaderRead]")
        && proof.contains("depthDescriptor.usage = [.renderTarget, .shaderRead]")
        && proof.contains("for eye in 0..<VisionImmersiveFrameRequest.viewCount"),
      "the full space owns two shader-readable BGRA8/D32S8 native eye targets")
check(!proof.contains("DispatchQueue.main.sync") && !proof.contains("waitUntilCompleted")
        && !proof.contains("DispatchSemaphore"),
      "the main actor never waits for the presenter thread or the GPU")

print("Player-facing immersive control")
check(modeControl.hasPrefix(gate + "\n") && modeControl.hasSuffix("#endif\n")
        && modeControl.contains("@Environment(\\.openImmersiveSpace)")
        && modeControl.contains("struct VisionImmersiveModeControl: View"),
      "the shared entry control compiles only in the opt-in visionOS build")
check(occursInOrder([
    "guard session.isRunning, session.title == .jak1,",
    "coordinator.canOpen(for: session)",
    "coordinator.prepareToOpen(session: session)",
    "value: attempt",
    "case .opened:",
    ".opened",
    "case .userCancelled:",
    ".cancelled",
    "case .error:",
    ".failed(\"visionOS could not open the immersive space.\")",
    "@unknown default:",
    "coordinator.openFinished(attempt: attempt, result: result)",
], in: modeControl),
      "entry keeps readiness and every open result bound to the coordinator attempt")
check(modeControl.contains("case .opening, .presenting:\n            coordinator.close(reason: .userToggle)")
        && modeControl.contains("case .closing:\n            false")
        && modeControl.contains(".disabled(!isEnabled)"),
      "the same control exits an active space and cannot reopen while dismissal is outstanding")
check(sessionStatus.contains("immersive-session-status.json")
        && sessionStatus.contains("static let defaultMaximumEventCount = 24")
        && sessionStatus.contains("private let writerQueue = DispatchQueue(")
        && sessionStatus.contains("let acceptsTerminal = isTerminal && terminal == nil")
        && sessionStatus.contains("if acceptsTerminal {")
        && sessionStatus.contains("guard attempt >= currentAttempt else { return }")
        && sessionStatus.contains("write(to: outputURL, options: .atomic)")
        && proof.contains("recordSessionStatus(attempt: attempt, event: .opening")
        && proof.contains("event: .presenting, reason: \"firstVisibleFrame\"")
        && proof.contains("event: .failure,")
        && proof.contains("event: .presenterStopped,"),
      "a serialized bounded status file preserves the first terminal cause and rejects stale attempts")
check(modeControl.contains("\"arrow.up.left.and.arrow.down.right\"")
        && modeControl.contains("\"arrow.down.right.and.arrow.up.left\"")
        && modeControl.contains(".frame(width: 42, height: 42)")
        && modeControl.contains(".glassBackgroundEffect(in: Circle())")
        && modeControl.contains("\"Return to Window\" : \"Enter Immersive\""),
      "matching glass expansion arrows expose clear enter and return accessibility labels")
check(!proof.contains("Open Immersive Proof") && !proof.contains("Close Immersive Proof"),
      "the old proof/debug control is absent from player-facing UI")

print("Compositor frame")
let frame = section(presenter, from: "private func renderFrame()",
                    to: "private func prepare(")
check(occursInOrder([
    "layerRenderer.queryNextFrame()",
    "layerFrame.predictTiming()",
    "layerFrame.startUpdate()",
    "layerFrame.endUpdate()",
    "layerFrame.predictTiming()",
    "LayerRenderer.Clock().wait(until: timing.optimalInputTime)",
    "layerFrame.queryDrawables()",
    "trackedDeviceAnchor(at: presentationTime)",
    "makeRequest(",
    "layerFrame.startSubmission()",
    "defer { layerFrame.endSubmission() }",
    "tickGame(request: requestContext.request)",
    "gameFrame.request.isOpticallyCompatible(with: requestContext.request)",
    "retainedPose(for: gameFrame.request.poseIdentity)",
    "commandQueue.makeCommandBuffer()",
    "var evidenceTicket: VisionImmersiveRenderEvidenceSampler.Ticket?",
    "guard let encoded = encode(",
    "encoded.drawnViews != prepared.drawable.views.count",
    "if let ticket = encoded.evidenceTicket",
    "prepared.drawable.encodePresent(commandBuffer: commandBuffer)",
    "commandBuffer.addCompletedHandler",
    "let evidence = evidenceSampler.complete(evidenceTicket)",
    "if evidence.becameVisible",
    "presentedFirstGameFrame(",
    "commandBuffer.commit()",
], in: frame),
      "pose-bound native rendering is presented before GPU pixel evidence unlocks the first frame")
let request = section(presenter, from: "private func makeRequest(",
                      to: "private func tickGame(")
check(count("DispatchQueue.main.sync", in: presenter) == 1
        && request.contains("entryOriginFromGameCameraMeters = originFromDevice")
        && request.contains("binocularFrustumMatrixForDrawableTarget(")
        && request.contains("drawable.computeProjection(convention: .rightUpBack")
        && request.contains("VisionImmersiveCameraMath.makeCameras(")
        && request.contains("latestRequestPose = RetainedPose(")
        && presenter.contains("latestRenderedPose = retained")
        && presenter.contains("drawable.deviceAnchor = renderAnchor"),
      "one tracked pose and compositor optical request stay attached to rendered or reused pixels")
let anchorQuery = section(presenter, from: "private func trackedDeviceAnchor(",
                          to: "private func reportSceneActive(")
let presenterStart = section(presenter, from: "static func start(",
                             to: "private func renderLoop()")
check(occursInOrder([
    "worldTracking.queryDeviceAnchor(atTimestamp: time)",
    "anchor.trackingState == .tracked",
], in: anchorQuery)
        && anchorQuery.contains("fail(\"Head tracking was lost")
        && presenterStart.contains("guard WorldTrackingProvider.isSupported else")
        && presenterStart.contains("try await presenter.arSession.run([presenter.worldTracking])")
        && !presenter.contains("VisionImmersiveFullViewport")
        && !presenter.contains("fixedShear")
        && !presenter.contains("screenPose"),
      "tracked head pose is required and no monoscopic screen or fixed-shear fallback remains")
let poseFree = section(presenter, from: "private func presentWithoutPose(",
                       to: "private func makeRequest(")
check(occursInOrder([
    "guard let anchor = trackedDeviceAnchor(at: presentationTime) else {",
    "presentWithoutPose(preparedDrawables, layerFrame: layerFrame)",
    "return",
    "guard let requestContext = makeRequest(",
], in: frame)
        && occursInOrder([
            "layerFrame.startSubmission()",
            "defer { layerFrame.endSubmission() }",
            "clearingPassDescriptor(drawable: prepared.drawable, pass: pass)",
            "prepared.drawable.encodePresent(commandBuffer: commandBuffer)",
            "commandBuffer.commit()",
        ], in: poseFree)
        && !poseFree.contains("deviceAnchor")
        && !poseFree.contains("tickGame(")
        && anchorQuery.contains("trackingPolicy.decide(sample, at: LayerRenderer.Clock().now")
        && anchorQuery.contains("worldTracking.state == .stopped")
        && anchorQuery.contains("case .render:\n            return trackedAnchor")
        && presenter.contains("trackingPolicy.suspend()\n                layerRenderer.waitUntilRunning()"),
      "frames without a confirmed tracked pose present pose-free black within a bounded grace")
check(presenter.contains("layerRenderer.device === device")
        && presenter.contains("[.bgra8Unorm_srgb, .rgba16Float].contains(configuration.colorFormat)")
        && presenter.contains("depthDescriptor.depthCompareFunction = .always")
        && presenter.contains("device.makeDefaultLibrary()"),
      "the presenter fails closed on a foreign device or an unproven color format")
check(presenter.contains("case .invalidated:\n                reportSceneActive(false)")
        && presenter.contains("case .paused:\n                reportSceneActive(false)")
        && presenter.contains("case .running:\n                reportSceneActive(true)")
        && presenter.contains("guard reportedSceneActive != active else { return }")
        && proof.contains("session?.setImmersivePresentationActive(active, owner: attempt)"),
      "renderer activity transitions keep the owned session alive without per-frame churn")

print("Build-time resources")
let appSources = FileManager.default.enumerator(atPath: root + "/GOALPad")?.compactMap {
    ($0 as? String).flatMap { $0.hasSuffix(".swift") || $0.hasSuffix(".mm") ? $0 : nil }
} ?? []
check(appSources.allSatisfy {
    let text = source(root, "GOALPad/" + $0)
    return !text.contains("makeLibrary(source") && !text.contains("newLibraryWithSource")
}, "no app source compiles a shader at runtime")

print("Native physical camera bridge")
let renderChain = section(host, from: "void render_chain(const void* ee_base",
                          to: "#if defined(__aarch64__)")
check(occursInOrder([
    "g_host.frame_is_stereo",
    "render_chain_frame_to_external_stereo_targets(",
    "g_host.stereo_left, g_host.stereo_right",
    "g_host.stereo_command_buffer, chain_data, chain_offset, chain_size)",
], in: renderChain), "each live DMA chain is replayed into the paired physical targets")
check(bridge.contains("init(viewID:colorTexture:depthTexture:clipFromEye:")
        && bridge.contains("eyeFromGameCameraMeters:binocularCullFromGameCameraMeters:)")
        && bridge.contains("@property(nonatomic, readonly) BOOL physicalCameraEnabled;")
        && bridge.contains("rendererCommandQueue")
        && bridge.contains("endStereoFrame"),
      "the Objective-C contract exposes typed physical projection, eye, and shared cull matrices")
let physicalCopy = section(renderSurface, from: "const auto copyPhysicalCamera",
                           to: "const BOOL began")
check(occursInOrder([
    "destination.physical_camera.enabled = source.physicalCameraEnabled",
    "destination.binocular_cull.enabled = source.physicalCameraEnabled",
    "source.clipFromEye",
    "source.eyeFromGameCameraMeters",
    "source.binocularCullFromGameCameraMeters",
    "destination.physical_camera.clip_from_eye.data()",
    "destination.physical_camera.eye_from_game_camera_meters.data()",
    "destination.binocular_cull.clip_from_game_camera_meters.data()",
], in: physicalCopy),
      "Objective-C++ mirrors all physical matrices without substituting a legacy clip transform")
let beginStereo = section(host, from: "bool metal_host_begin_reserved_stereo_frame(",
                          to: "bool metal_host_begin_external_frame(")
check(occursInOrder([
    "view.physical_camera.enabled != view.binocular_cull.enabled",
    "finite(view.physical_camera.clip_from_eye)",
    "finite(view.physical_camera.eye_from_game_camera_meters)",
    "finite(view.binocular_cull.clip_from_game_camera_meters)",
    "left.physical_camera.enabled != right.physical_camera.enabled",
    "left.binocular_cull.clip_from_game_camera_meters !=",
    "right.binocular_cull.clip_from_game_camera_meters",
    "target.immersive_camera.view.enabled = view.physical_camera.enabled",
    "target.immersive_camera.view.clip_from_eye = view.physical_camera.clip_from_eye",
    "target.immersive_camera.view.eye_from_game_camera_meters =",
    "target.immersive_camera.binocular_cull.enabled = view.binocular_cull.enabled",
    "target.immersive_camera.binocular_cull.clip_from_game_camera_meters =",
], in: beginStereo)
        && beginStereo.contains("physical-camera-cull-mode-mismatch")
        && beginStereo.contains("physical-camera-target-not-shader-readable")
        && beginStereo.contains("stereo_preflight_error = reason"),
      "native preflight requires finite per-eye cameras and one byte-equal binocular cull contract")
check(renderSurface.contains("const auto detail = goalpad::metal_host_stereo_error();")
        && renderSurface.contains("[@\"Immersive camera: \" stringByAppendingString:")
        && host.contains("immersive_camera_error_name(error)"),
      "native camera rejection names propagate to the coordinator's fail-closed message")

// Typed world-camera-packet absence: host enum -> ObjC -> RenderSurface -> GameSession -> coordinator.
let hostHeader = source(root, "GOALPad/Native/GOALPadMetalHost.hpp")
let stereoWatchdog = source(root, "GOALPad/Vision/VisionStereoSubmissionWatchdog.swift")
check(hostHeader.contains("world_camera_packet_absent,")
        && host.contains("ImmersiveCameraError::WorldPacketUnavailableThisFrame")
        && host.contains("camera_packet_absent && black_initialization_submitted")
        && host.contains("g_host.stereo_preflight_error.empty()")
        && host.components(separatedBy: "g_host.stereo_world_camera_packet_absent = false;").count - 1 >= 4
        && !host.contains("(void)g_host.renderer->submit_external_stereo_frame(g_host.stereo_command_buffer);"),
      "host latches camera absence per frame only as the sole rejection after a submitted black initialization")
check(bridge.contains("GOALPadStereoFrameCompletionWorldCameraPacketAbsent = 3")
        && renderSurface.contains("case goalpad::MetalHostStereoFrameCompletion::world_camera_packet_absent:")
        && renderSurface.contains("return GOALPadStereoFrameCompletionWorldCameraPacketAbsent;")
        && !renderSurface.contains("world-camera-packet-unavailable"),
      "the typed absence crosses the ObjC surface without string matching")
check(stereoWatchdog.contains("case worldCameraPacketAbsent")
        && stereoWatchdog.contains("case .failed, .worldCameraPacketAbsent:"),
      "the conventional stereo watchdog treats camera absence as a failure")
check(session.contains("armedTickNativeUpdateSucceeded = GOALPadRuntimeBridge.runFrame(")
        && session.contains("nativeUpdateSucceeded = armedTickNativeUpdateSucceeded")
        && session.contains("return nativeUpdateSucceeded ? .worldCameraPacketAbsent : .failed")
        && !session.contains("nativeUpdateSucceeded = true")
        && !session.contains("lastStereoWorldCameraPacketAbsent"),
      "only an actually successful native update may report camera absence")
check(proof.contains("""
            case .worldCameraPacketAbsent:
                // The rejected frame committed the paired black initialization into the fixed
                // targets, so the cached frame no longer describes their pixels. Keep ticking
                // and present nothing until a fresh validated stereo frame arrives.
                lastFrame = nil
                return nil
""") && !proof.contains("lastStereoWorldCameraPacketAbsent")
        && proof.contains("case .busy, .skipped:"),
      "camera absence clears the cached frame and returns nil without failing; busy reuse is unchanged")

if failures == 0 {
    print("visionOS immersive proof integration checks passed")
} else {
    print("visionOS immersive proof integration checks failed: \(failures)")
    exit(1)
}
