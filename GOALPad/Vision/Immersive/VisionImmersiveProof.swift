#if os(visionOS) && GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE
import CompositorServices
import Metal
import Observation
import OSLog
import SwiftUI
import simd

private let immersiveLayerConfigurationLog = Logger(
    subsystem: "com.zephyrstudiosllc.eco", category: "ImmersiveProofConfiguration")

#if GOALPAD_EXPERIMENTAL_VISION_STEREO
// The window stereo surface ticks the game on its own schedule and would double-advance it.
#error("The immersive proof cannot be combined with the dormant window stereo experiment.")
#endif

/// The host-owned target one immersive game tick renders into.
struct VisionImmersiveGameTarget {
    let viewIDs: [UInt64]
    let colorTextures: [any MTLTexture]
    let depthTextures: [any MTLTexture]
}

/// The opt-in immersive renderer replays one Jak 1 game update into two physical eye cameras.
/// Head motion is relative to the existing third-person game camera, so Jak remains in the world.
@MainActor
@Observable
final class VisionImmersiveProofCoordinator {
    typealias Phase = VisionImmersiveProofLifecycle.Phase

    private final class GameTargetState {
        let target: VisionImmersiveGameTarget
        let width: Int
        let height: Int

        init(target: VisionImmersiveGameTarget, width: Int, height: Int) {
            self.target = target
            self.width = width
            self.height = height
        }
    }

    private struct MenuTargetState {
        let viewID: UInt64
        let colorTexture: any MTLTexture
        let depthTexture: any MTLTexture
    }

    static let shared = VisionImmersiveProofCoordinator()
    static let spaceID = "dark-eco-immersive-proof"
    private static let firstFrameTimeout = Duration.seconds(3)

    private(set) var lifecycle = VisionImmersiveProofLifecycle()

    @ObservationIgnored private weak var session: GameSession?
    /// Kept here, not in a window, so closing the window that opened the space still dismisses it.
    @ObservationIgnored private var dismissImmersiveSpace: DismissImmersiveSpaceAction?
    @ObservationIgnored private var dismissalTask: Task<Void, Never>?
    @ObservationIgnored private var cadence = VisionImmersiveTickCadence()
    @ObservationIgnored private var gameTarget: GameTargetState?
    @ObservationIgnored private var menuTarget: MenuTargetState?
    /// The newest valid frame. Entering a menu discards per-eye pixels whose reusable targets were
    /// already overwritten by that tick.
    @ObservationIgnored private var lastFrame: VisionImmersivePresentedFrame?
    @ObservationIgnored private var lastViewID: UInt64 = 0
    @ObservationIgnored private var lastRenderSerial: UInt64 = 0
    @ObservationIgnored private var firstFrameTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private let sessionStatus = VisionImmersiveSessionStatusRecorder()

    var phase: Phase {
        lifecycle.phase
    }

    var isActive: Bool {
        lifecycle.isActive
    }

    var suppressesWindowRendering: Bool {
        switch phase {
        case .opening, .presenting, .closing: true
        case .closed, .failed: false
        }
    }

    /// A paused game stays in the window; immersion opens only after the player resumes there.
    func canOpen(for session: GameSession) -> Bool {
        lifecycle.canBeginOpen && session.isRunning && session.title == .jak1
            && session.runReadiness == .active && Self.route(for: session) != .exitForPause
    }

    private static func route(for session: GameSession) -> VisionImmersiveTickRoute {
        VisionImmersiveTickRoute(isNativePaused: isNativePause(session),
                                 usesControllerMenuNavigation: session.usesControllerMenuNavigation)
    }

    /// Normal Start enters `progress` at the fuel-cell origin (screen 0); legacy `pause` remains.
    /// Title, autosave, speedrun and unknown origins keep their existing routes.
    static func isNativePause(_ session: GameSession) -> Bool {
        VisionImmersiveNativePausePolicy.isNativePause(
            modeIsPause: session.gameMode == .pause,
            modeIsProgress: session.gameMode == .progress,
            isJak1: session.title == .jak1,
            runIsActive: session.runReadiness == .active,
            progressAvailable: session.progressMenuSnapshot.available,
            startingScreenRawValue: session.progressMenuSnapshot.startingScreenRawValue)
    }

    func adoptDismissAction(_ action: DismissImmersiveSpaceAction) {
        dismissImmersiveSpace = action
    }

    /// Called immediately before SwiftUI is asked to open the space. Returns the attempt to open
    /// it with, or nil while the proof is unavailable or a previous space is still closing.
    func prepareToOpen(session: GameSession) -> UInt64? {
        guard canOpen(for: session), let attempt = lifecycle.beginOpen() else { return nil }
        self.session = session
        session.claimImmersiveFrameLoop(attempt)
        cadence.reset()
        recordSessionStatus(attempt: attempt, event: .opening, reason: "enterRequested")
        return attempt
    }

    func openFinished(attempt: UInt64, result: VisionImmersiveProofLifecycle.OpenResult) {
        guard attempt == lifecycle.attempt else { return }
        let effects = lifecycle.openFinished(attempt: attempt, result: result)
        switch result {
        case .opened:
            recordSessionStatus(attempt: attempt, event: .openFinished, reason: "opened")
        case .cancelled:
            recordSessionStatus(attempt: attempt, event: .openFinished,
                                reason: VisionImmersiveCloseReason.openCancelled.rawValue,
                                isTerminal: true)
        case .failed(let message):
            recordSessionStatus(attempt: attempt, event: .openFinished,
                                reason: VisionImmersiveCloseReason.openFailed.rawValue,
                                failure: message, isTerminal: true)
        }
        apply(effects)
    }

    func layerRendererStarted(_ layerRenderer: LayerRenderer, attempt: UInt64?) {
        // Every open passes its attempt, so a space without one was not opened by this proof.
        guard let attempt else { return }
        let effects = lifecycle.rendererArrived(attempt: attempt)
        apply(effects)
        guard effects.startPresenter else { return }
        recordSessionStatus(attempt: attempt, event: .presenterStarted)
        let surface = GOALPadRenderSurface.shared
        let startFailure: String?
        if let device = surface.rendererDevice, let commandQueue = surface.rendererCommandQueue {
            startFailure = VisionImmersiveFramePresenter.start(
                layerRenderer, attempt: attempt, device: device, commandQueue: commandQueue)
        } else {
            startFailure = "The game renderer is not running, so the immersive proof cannot start."
        }
        if let startFailure {
            fail(attempt: attempt, reason: .presenterStartFailed, message: startFailure)
            presenterStopped(attempt: attempt, reason: .presenterStartFailed)
        }
    }

    /// One game update renders both eyes from this exact compositor pose and optical contract.
    /// Cadence reuse retains the old request so presentation never assigns a newer head pose to it.
    /// While a native menu owns input, the update instead renders the conventional frame for the
    /// presenter's finite-depth menu plane. Native pause, whether already open or entered by an
    /// update that did not fail, instead returns the game to the window before any pause frame is
    /// presented.
    func tickGame(attempt: UInt64, request: VisionImmersiveFrameRequest)
        -> VisionImmersivePresentedFrame? {
        guard attempt == lifecycle.attempt, lifecycle.isActive, request.isValid else { return nil }
        guard let session, session.isRunning, session.title == .jak1 else {
            close(reason: .sessionInvalidForTick)
            return nil
        }
        let route = Self.route(for: session)
        guard route != .exitForPause else { return exitForNativePause() }
        let surface = GOALPadRenderSurface.shared
        session.input.updateSpatialGestureReference(originFromDevice: request.originFromDevice,
                                                     timestamp: request.presentationTime)
        let geometry = surface.geometry()
        if route == .menuPlane {
            return tickMenuPlane(attempt: attempt, request: request, session: session,
                                 surface: surface, geometry: geometry)
        }
        guard let device = surface.rendererDevice,
              let aspect = request.cameras.map(\.aspectRatio).max(),
              aspect.isFinite, aspect > 0,
              let eye = RenderSettings.immersiveEyeDimensions(
                  height: session.settings.immersiveEyeHeight, aspects: [aspect]) else { return nil }
        let height = eye.height
        let width = eye.width
        guard let state = gameTargetState(width: width, height: height, device: device) else {
            fail(attempt: attempt, reason: .targetAllocationFailed,
                 message: "Metal could not allocate the immersive eye targets.")
            return nil
        }
        let compatible = lastPerEyeFrame?.request.isOpticallyCompatible(with: request) ?? false
        let scheduledTime = cadence.scheduledTime(for: request.presentationTime,
                                                   framesPerSecond: session.targetFrameRate)
        if let tickTime = scheduledTime ?? (compatible ? nil : request.presentationTime) {
            let disposition = session.tickImmersive(targetPresentationTime: tickTime,
                                                    request: request, target: state.target)
            // A failed submission is always reported as a native failure, even if the same update
            // entered pause; only a non-failed update that paused closes normally.
            if disposition != .failed, Self.route(for: session) == .exitForPause {
                return exitForNativePause()
            }
            switch disposition {
            case .submitted:
                lastRenderSerial &+= 1
                if session.usesControllerMenuNavigation {
                    // The target textures were reused by this tick. Their old frame/pose metadata
                    // no longer describes their pixels; wait for the conventional menu frame.
                    lastFrame = nil
                } else {
                    // The native stereo path applies no PCRTC fade of its own and reports none;
                    // the monoscopic fade describes only menu-plane frames.
                    lastFrame = .perEye(VisionImmersiveGameFrame(
                        colorTextures: state.target.colorTextures,
                        depthTextures: state.target.depthTextures,
                        fade: 1,
                        renderSerial: lastRenderSerial,
                        request: request))
                }
            case .busy, .skipped:
                break
            case .worldCameraPacketAbsent:
                // The rejected frame committed the paired black initialization into the fixed
                // targets, so the cached frame no longer describes their pixels. Keep ticking
                // and present nothing until a fresh validated stereo frame arrives.
                lastFrame = nil
                return nil
            case .failed:
                let reason = surface.lastError.isEmpty
                    ? "The native immersive renderer could not submit both eyes."
                    : surface.lastError
                fail(attempt: attempt, reason: .nativeFailure, message: reason)
                return nil
            }
        }
        return presentableLastFrame(for: request)
    }

    /// Renders the whole conventional frame, HUD and menus included, at the window's own internal
    /// size and aspect on the shared game cadence.
    private func tickMenuPlane(attempt: UInt64,
                               request: VisionImmersiveFrameRequest,
                               session: GameSession,
                               surface: GOALPadRenderSurface,
                               geometry: GOALPadSurfaceGeometry) -> VisionImmersivePresentedFrame? {
        guard let device = surface.rendererDevice,
              geometry.internalWidth > 0, geometry.internalHeight > 0 else { return nil }
        guard let target = menuTargetState(width: Int(geometry.internalWidth),
                                           height: Int(geometry.internalHeight),
                                           device: device) else {
            fail(attempt: attempt, reason: .targetAllocationFailed,
                 message: "Metal could not allocate the immersive menu target.")
            return nil
        }
        if let tickTime = cadence.scheduledTime(for: request.presentationTime,
                                                framesPerSecond: session.targetFrameRate) {
            let disposition = session.tickImmersiveMenuFrame(
                targetPresentationTime: tickTime,
                viewID: target.viewID,
                colorTexture: target.colorTexture,
                depthTexture: target.depthTexture)
            if disposition != .failed, Self.route(for: session) == .exitForPause {
                return exitForNativePause()
            }
            switch disposition {
            case .submitted:
                lastRenderSerial &+= 1
                lastFrame = .menuPlane(VisionImmersiveMenuFrame(
                    colorTexture: target.colorTexture,
                    depthTexture: target.depthTexture,
                    fade: surface.monoscopicFrameFade,
                    renderSerial: lastRenderSerial))
            case .busy, .skipped:
                break
            case .failed, .worldCameraPacketAbsent:
                let reason = surface.lastError.isEmpty
                    ? "The native immersive renderer could not submit the menu frame."
                    : surface.lastError
                fail(attempt: attempt, reason: .nativeFailure, message: reason)
                return nil
            }
        }
        return presentableLastFrame(for: request)
    }

    /// Hands the game back to the window through the ordinary close, which releases this
    /// attempt's frame loop once and dismisses the space. Nothing here resumes the game: the
    /// window's frame loop continues the same paused native state once the space is gone. The
    /// cached frame is dropped because the update that paused may have reused its targets.
    private func exitForNativePause() -> VisionImmersivePresentedFrame? {
        lastFrame = nil
        close(reason: .pauseEntered)
        return nil
    }

    private var lastPerEyeFrame: VisionImmersiveGameFrame? {
        if case .perEye(let frame) = lastFrame { frame } else { nil }
    }

    /// Per-eye pixels remain valid only for compatible optics; a menu plane is projected anew for
    /// every compositor frame.
    private func presentableLastFrame(for request: VisionImmersiveFrameRequest)
        -> VisionImmersivePresentedFrame? {
        switch lastFrame {
        case .perEye(let frame):
            frame.request.isOpticallyCompatible(with: request) ? lastFrame : nil
        case .menuPlane:
            lastFrame
        case nil:
            nil
        }
    }

    func setImmersiveSceneActive(_ active: Bool, attempt: UInt64) {
        guard attempt == lifecycle.attempt else { return }
        session?.setImmersivePresentationActive(active, owner: attempt)
    }

    func presentedFirstGameFrame(attempt: UInt64) {
        let wasOpening = attempt == lifecycle.attempt && phase == .opening
        apply(lifecycle.firstFramePresented(attempt: attempt))
        if wasOpening, phase == .presenting {
            recordSessionStatus(attempt: attempt, event: .presenting, reason: "firstVisibleFrame")
        }
        if attempt == lifecycle.attempt, phase == .presenting {
            session?.enableImmersiveGesturesIfActive()
        }
    }

    func presenterFailed(attempt: UInt64, message: String) {
        fail(attempt: attempt, reason: .presenterFailure, message: message)
    }

    func presenterStopped(attempt: UInt64, reason: VisionImmersiveCloseReason) {
        let wasActive = attempt == lifecycle.attempt && lifecycle.isActive
        if attempt == lifecycle.attempt {
            session?.input.setSpatialGesturesEnabled(false)
        }
        session?.releaseImmersiveFrameLoop(attempt)
        if attempt == lifecycle.attempt {
            gameTarget = nil
            menuTarget = nil
            lastFrame = nil
        }
        let effects = lifecycle.presenterStopped(attempt: attempt)
        recordSessionStatus(attempt: attempt, event: .presenterStopped,
                            reason: reason.rawValue, isTerminal: wasActive)
        apply(effects)
    }

    /// Return frame ownership to the window and dismiss the space.
    func close(reason: VisionImmersiveCloseReason) {
        guard lifecycle.isActive else { return }
        let attempt = lifecycle.attempt
        let effects = lifecycle.close()
        recordSessionStatus(attempt: attempt, event: .closeRequested,
                            reason: reason.rawValue, isTerminal: true)
        apply(effects)
    }

    func sessionEnded(_ endedSession: GameSession) {
        handleSessionLifetime(.sessionStopped, session: endedSession)
    }

    /// Full immersion may hide the window shell without ending the game or its owned frame loop.
    func hostDisappeared(_ hiddenSession: GameSession) {
        handleSessionLifetime(.hostDisappeared, session: hiddenSession)
    }

    private func handleSessionLifetime(_ event: VisionImmersiveSessionLifetimeEvent,
                                       session observedSession: GameSession) {
        guard observedSession === session else { return }
        if event.endsPresentation {
            close(reason: .sessionStopped)
        } else if lifecycle.isActive {
            recordSessionStatus(attempt: lifecycle.attempt, event: .hostDisappeared,
                                reason: event.rawValue)
        }
    }

    private func apply(_ effects: VisionImmersiveProofLifecycle.Effects) {
        if effects.cancelFirstFrameTimeout {
            cancelFirstFrameTimeout()
        }
        if effects.releaseFrameLoop {
            session?.input.setSpatialGesturesEnabled(false)
            session?.releaseImmersiveFrameLoop(lifecycle.attempt)
        }
        if effects.armFirstFrameTimeout {
            armFirstFrameTimeout()
        }
        if let request = effects.dismissalRequest {
            dismissSpace(request: request)
        }
    }

    /// Dismissals run one at a time, after any earlier one finishes.
    private func dismissSpace(request: UInt64) {
        guard let dismissImmersiveSpace else {
            // Only a window's control opens the space, and every window supplies this action.
            dismissalFinished(request: request)
            return
        }
        let previous = dismissalTask
        dismissalTask = Task {
            await previous?.value
            await dismissImmersiveSpace()
            self.dismissalFinished(request: request)
        }
    }

    private func dismissalFinished(request: UInt64) {
        lifecycle.dismissalFinished(request: request)
        recordSessionStatus(attempt: lifecycle.attempt, event: .dismissalFinished,
                            reason: "request:\(request)")
    }

    private func armFirstFrameTimeout() {
        cancelFirstFrameTimeout()
        let attempt = lifecycle.attempt
        firstFrameTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.firstFrameTimeout)
            guard !Task.isCancelled, let self else { return }
            let message = "The immersive proof did not present a game frame within three seconds, "
                + "so Dark Eco returned to the window."
            guard attempt == self.lifecycle.attempt, self.phase == .opening else { return }
            let effects = self.lifecycle.firstFrameTimedOut(attempt: attempt, message: message)
            self.recordSessionStatus(
                attempt: attempt, event: .failure,
                reason: VisionImmersiveCloseReason.firstVisibleTimeout.rawValue,
                failure: message, isTerminal: true)
            self.apply(effects)
        }
    }

    private func cancelFirstFrameTimeout() {
        firstFrameTimeoutTask?.cancel()
        firstFrameTimeoutTask = nil
    }

    private func fail(attempt: UInt64,
                      reason: VisionImmersiveCloseReason,
                      message: String) {
        guard attempt == lifecycle.attempt, lifecycle.isActive else { return }
        let effects = lifecycle.fail(attempt: attempt, message: message)
        recordSessionStatus(attempt: attempt, event: .failure,
                            reason: reason.rawValue, failure: message, isTerminal: true)
        apply(effects)
    }

    private func recordSessionStatus(attempt: UInt64,
                                     event: VisionImmersiveSessionStatusRecorder.EventKind,
                                     reason: String? = nil,
                                     failure: String? = nil,
                                     isTerminal: Bool = false) {
        guard attempt == lifecycle.attempt else { return }
        sessionStatus.record(
            attempt: attempt,
            event: event,
            phase: Self.statusName(for: lifecycle.phase),
            reason: reason,
            failure: failure,
            isTerminal: isTerminal)
    }

    private static func statusName(for phase: Phase) -> String {
        switch phase {
        case .closed: "closed"
        case .opening: "opening"
        case .presenting: "presenting"
        case .closing: "closing"
        case .failed: "failed"
        }
    }

    /// The native stereo seam consumes two independent BGRA8/D32S8 targets. D32S8 is sampled
    /// directly as depth2d<float>; casting it to a Depth32Float view is unsupported by Metal.
    private func gameTargetState(width: Int, height: Int,
                                 device: any MTLDevice) -> GameTargetState? {
        guard width > 0, height > 0 else { return nil }
        if let gameTarget, gameTarget.width == width, gameTarget.height == height {
            return gameTarget
        }
        let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        colorDescriptor.usage = [.renderTarget, .shaderRead]
        colorDescriptor.storageMode = .private
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float_stencil8, width: width, height: height, mipmapped: false)
        depthDescriptor.usage = [.renderTarget, .shaderRead]
        depthDescriptor.storageMode = .private
        var colors: [any MTLTexture] = []
        var depths: [any MTLTexture] = []
        var viewIDs: [UInt64] = []
        for eye in 0..<VisionImmersiveFrameRequest.viewCount {
            guard let color = device.makeTexture(descriptor: colorDescriptor),
                  let depth = device.makeTexture(descriptor: depthDescriptor) else { return nil }
            color.label = "Dark Eco immersive eye \(eye) color"
            depth.label = "Dark Eco immersive eye \(eye) depth"
            lastViewID &+= 1
            colors.append(color)
            depths.append(depth)
            viewIDs.append(lastViewID)
        }
        let state = GameTargetState(target: VisionImmersiveGameTarget(
            viewIDs: viewIDs, colorTextures: colors, depthTextures: depths),
            width: width, height: height)
        gameTarget = state
        return state
    }

    /// The conventional frame's target. Depth is shader-readable only for bounded render evidence.
    private func menuTargetState(width: Int, height: Int,
                                 device: any MTLDevice) -> MenuTargetState? {
        guard width > 0, height > 0 else { return nil }
        if let menuTarget, menuTarget.colorTexture.width == width,
           menuTarget.colorTexture.height == height {
            return menuTarget
        }
        let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        colorDescriptor.usage = [.renderTarget, .shaderRead]
        colorDescriptor.storageMode = .private
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float_stencil8, width: width, height: height, mipmapped: false)
        depthDescriptor.usage = [.renderTarget, .shaderRead]
        depthDescriptor.storageMode = .private
        guard let color = device.makeTexture(descriptor: colorDescriptor),
              let depth = device.makeTexture(descriptor: depthDescriptor) else { return nil }
        color.label = "Dark Eco immersive menu color"
        depth.label = "Dark Eco immersive menu depth"
        lastViewID &+= 1
        let state = MenuTargetState(viewID: lastViewID, colorTexture: color, depthTexture: depth)
        menuTarget = state
        return state
    }

}

struct VisionImmersiveProofScene: Scene {
    var body: some Scene {
        // Each open passes its attempt, so a renderer is matched to the attempt that opened it.
        ImmersiveSpace(id: VisionImmersiveProofCoordinator.spaceID, for: UInt64.self) { attempt in
            CompositorLayer(configuration: VisionImmersiveProofLayerConfiguration()) {
                layerRenderer in
                VisionImmersiveProofCoordinator.shared.layerRendererStarted(
                    layerRenderer, attempt: attempt.wrappedValue)
            }
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }
}

struct VisionImmersiveProofLayerConfiguration: CompositorLayerConfiguration {
    func makeConfiguration(capabilities: LayerRenderer.Capabilities,
                           configuration: inout LayerRenderer.Configuration) {
        let systemValues = (
            foveation: configuration.isFoveationEnabled,
            colorFormat: configuration.colorFormat,
            colorUsage: configuration.colorUsage,
            depthUsage: configuration.depthUsage,
            layout: configuration.layout,
            depthRange: configuration.defaultDepthRange)
        configuration.isFoveationEnabled = false
        let colorFormats = capabilities.supportedColorFormats(options: [])
        if colorFormats.contains(.bgra8Unorm_srgb) {
            configuration.colorFormat = .bgra8Unorm_srgb
        } else if colorFormats.contains(.rgba16Float) {
            configuration.colorFormat = .rgba16Float
        }
        configuration.colorUsage = [.renderTarget, .shaderRead]
        configuration.depthUsage = [.renderTarget, .shaderRead]
        let layouts = capabilities.supportedLayouts(options: [])
        if layouts.contains(.dedicated) {
            configuration.layout = .dedicated
        } else if layouts.contains(.layered) {
            configuration.layout = .layered
        }
        let nearPlane = max(0.1, capabilities.supportedMinimumNearPlaneDistance)
        // Reverse-Z: far first, then near.
        configuration.defaultDepthRange = SIMD2(5_000, nearPlane)
        do {
            _ = try LayerRenderer.Properties(configuration: configuration)
        } catch {
            let reason = String(describing: error)
            immersiveLayerConfigurationLog.error(
                "Layer configuration rejected: \(reason, privacy: .public); restored system values")
            configuration.isFoveationEnabled = systemValues.foveation
            configuration.colorFormat = systemValues.colorFormat
            configuration.colorUsage = systemValues.colorUsage
            configuration.depthUsage = systemValues.depthUsage
            configuration.layout = systemValues.layout
            configuration.defaultDepthRange = systemValues.depthRange
        }
    }
}

/// Adds the opt-in build's experimental control to the game window. A stopped game closes the
/// proof; window-shell disappearance is recorded without revoking the immersive owner.
struct VisionImmersiveProofHost: ViewModifier {
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    let session: GameSession
    private let coordinator = VisionImmersiveProofCoordinator.shared

    func body(content: Content) -> some View {
        content
            .opacity(coordinator.suppressesWindowRendering ? 0 : 1)
            .allowsHitTesting(!coordinator.suppressesWindowRendering)
            .persistentSystemOverlays(coordinator.suppressesWindowRendering ? .hidden : .automatic)
            .onAppear { coordinator.adoptDismissAction(dismissImmersiveSpace) }
            .onChange(of: session.isRunning) { _, isRunning in
                if !isRunning { coordinator.sessionEnded(session) }
            }
            .onDisappear { coordinator.hostDisappeared(session) }
    }
}

#endif
