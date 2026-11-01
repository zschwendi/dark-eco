#if GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE
/// The immersive proof's open and close lifecycle, free of SwiftUI and CompositorServices so its
/// ordering is testable on the host. A new attempt may begin only after the previous space is
/// dismissed and its layer renderer has stopped, and only the renderer opened for the current
/// attempt may present.
nonisolated struct VisionImmersiveProofLifecycle: Sendable {
    enum Phase: Equatable, Sendable {
        case closed
        case opening
        case presenting
        /// Dismissal or layer invalidation is still outstanding. Holds the failure to report once
        /// the space is gone.
        case closing(failure: String?)
        case failed(String)
    }

    enum OpenResult: Equatable, Sendable {
        case opened
        case cancelled
        case failed(String)
    }

    /// Work the coordinator performs after an event.
    struct Effects: Equatable, Sendable {
        var cancelFirstFrameTimeout = false
        var releaseFrameLoop = false
        var startPresenter = false
        var armFirstFrameTimeout = false
        /// Dismiss the space, then report `dismissalFinished(request:)` with this value.
        var dismissalRequest: UInt64?
    }

    private(set) var phase = Phase.closed
    private(set) var attempt: UInt64 = 0
    private var openInFlight = false
    private var rendererAccepted = false
    private var presenterRunning = false
    private var spaceMayBeOpen = false
    private var latestDismissal: UInt64 = 0
    private var dismissalInFlight = false

    var isActive: Bool {
        phase == .opening || phase == .presenting
    }

    var canBeginOpen: Bool {
        switch phase {
        case .closed, .failed: true
        case .opening, .presenting, .closing: false
        }
    }

    /// Starts a new attempt and returns its identity, or nil while another is open or closing.
    mutating func beginOpen() -> UInt64? {
        guard canBeginOpen else { return nil }
        attempt &+= 1
        phase = .opening
        openInFlight = true
        rendererAccepted = false
        return attempt
    }

    mutating func openFinished(attempt: UInt64, result: OpenResult) -> Effects {
        guard attempt == self.attempt, openInFlight else { return Effects() }
        openInFlight = false
        if result == .opened {
            spaceMayBeOpen = true
        }
        var effects = Effects()
        switch (phase, result) {
        case (.opening, .opened):
            effects.armFirstFrameTimeout = true
        case (.closing, .opened):
            // visionOS finished opening a space this attempt no longer wants.
            requestDismissal(&effects)
        case (.opening, .cancelled), (.presenting, .cancelled):
            return end(failure: nil)
        case (.opening, .failed(let message)), (.presenting, .failed(let message)):
            return end(failure: message)
        default:
            break
        }
        finishClosingIfComplete()
        return effects
    }

    /// Decides whether a layer renderer opened for `attempt` may present. A renderer from an
    /// earlier attempt, whose space was dismissed before this attempt began, or a second renderer
    /// never presents; a space that opened after its attempt ended is dismissed.
    mutating func rendererArrived(attempt: UInt64) -> Effects {
        guard attempt == self.attempt else { return Effects() }
        spaceMayBeOpen = true
        var effects = Effects()
        switch phase {
        case .opening where !rendererAccepted:
            rendererAccepted = true
            presenterRunning = true
            effects.startPresenter = true
        case .opening, .presenting:
            break
        case .closing:
            requestDismissal(&effects)
        case .closed:
            phase = .closing(failure: nil)
            requestDismissal(&effects)
        case .failed(let message):
            phase = .closing(failure: message)
            requestDismissal(&effects)
        }
        return effects
    }

    mutating func firstFramePresented(attempt: UInt64) -> Effects {
        guard attempt == self.attempt, phase == .opening else { return Effects() }
        phase = .presenting
        return Effects(cancelFirstFrameTimeout: true)
    }

    mutating func fail(attempt: UInt64, message: String) -> Effects {
        guard attempt == self.attempt, isActive else { return Effects() }
        return end(failure: message)
    }

    mutating func firstFrameTimedOut(attempt: UInt64, message: String) -> Effects {
        guard attempt == self.attempt, phase == .opening else { return Effects() }
        return end(failure: message)
    }

    /// The presenter for `attempt` stopped after its layer was invalidated, or never started.
    mutating func presenterStopped(attempt: UInt64) -> Effects {
        guard attempt == self.attempt, presenterRunning else { return Effects() }
        presenterRunning = false
        if isActive {
            // visionOS invalidated the layer itself, for example when the person left the space.
            return end(failure: nil)
        }
        finishClosingIfComplete()
        return Effects()
    }

    mutating func close() -> Effects {
        guard isActive else { return Effects() }
        return end(failure: nil)
    }

    mutating func dismissalFinished(request: UInt64) {
        guard request == latestDismissal else { return }
        dismissalInFlight = false
        spaceMayBeOpen = false
        finishClosingIfComplete()
    }

    private mutating func end(failure: String?) -> Effects {
        var effects = Effects(cancelFirstFrameTimeout: true, releaseFrameLoop: true)
        phase = .closing(failure: failure)
        if spaceMayBeOpen {
            requestDismissal(&effects)
        }
        finishClosingIfComplete()
        return effects
    }

    private mutating func requestDismissal(_ effects: inout Effects) {
        latestDismissal &+= 1
        dismissalInFlight = true
        effects.dismissalRequest = latestDismissal
    }

    private mutating func finishClosingIfComplete() {
        guard case .closing(let failure) = phase, !openInFlight, !presenterRunning,
              !spaceMayBeOpen, !dismissalInFlight else { return }
        phase = failure.map(Phase.failed) ?? .closed
    }
}

/// The path one immersive compositor frame takes for the game's native state. Native pause is
/// also a menu, so it is decided first: it returns the still-paused game to the conventional
/// window instead of drawing the pause menu on the immersive plane.
nonisolated enum VisionImmersiveTickRoute: Equatable, Sendable {
    case perEye
    case menuPlane
    case exitForPause

    init(isNativePaused: Bool, usesControllerMenuNavigation: Bool) {
        if isNativePaused {
            self = .exitForPause
        } else if usesControllerMenuNavigation {
            self = .menuPlane
        } else {
            self = .perEye
        }
    }
}
/// Normal Start enters `progress` at the fuel-cell origin (starting screen 0); select/debug paths
/// use legacy `pause`. Title (27), autosave (29), speedrun (64) and unknown origins are not pause.
nonisolated enum VisionImmersiveNativePausePolicy {
    static let fuelCellsStartingScreen = 0

    static func isNativePause(modeIsPause: Bool, modeIsProgress: Bool, isJak1: Bool,
                              runIsActive: Bool, progressAvailable: Bool,
                              startingScreenRawValue: Int) -> Bool {
        if modeIsPause { return true }
        return isJak1 && runIsActive && modeIsProgress && progressAvailable
            && startingScreenRawValue == fuelCellsStartingScreen
    }
}
#endif
