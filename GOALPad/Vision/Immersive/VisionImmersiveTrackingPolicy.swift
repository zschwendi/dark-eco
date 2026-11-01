#if GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE
import Foundation

/// Decides, once per compositor frame, whether that frame's head pose may drive rendering. World
/// tracking needs a moment after `ARKitSession.run` before it can predict a presentation-time
/// pose, and it can drop briefly while immersed; neither ends the space at once. A frame is
/// rendered only from its own tracked pose, tracking must hold for several consecutive frames
/// before rendering starts or resumes, and every wait is bounded.
nonisolated struct VisionImmersiveTrackingPolicy: Sendable {
    enum Sample: Equatable, Sendable {
        /// A fully tracked device anchor for this frame's presentation time.
        case tracked
        /// No anchor, or one without full position and orientation tracking.
        case untracked
        /// The world-tracking provider stopped and will not resume.
        case providerStopped
    }

    enum Failure: Equatable, Sendable {
        case neverAcquired
        case lost
        case providerStopped
    }

    enum Decision: Equatable, Sendable {
        case render
        /// Present a frame without content or a pose, then sample again.
        case wait
        case fail(Failure)
    }

    static let acquisitionBudget: TimeInterval = 2
    static let recoveryBudget: TimeInterval = 1
    static let requiredConsecutiveTrackedFrames = 3

    private(set) var hasAcquired = false
    private var rendering = false
    private var waitingSince: TimeInterval?
    private var consecutiveTracked = 0
    private var failure: Failure?

    mutating func decide(_ sample: Sample, at now: TimeInterval) -> Decision {
        if let failure { return .fail(failure) }
        switch sample {
        case .providerStopped:
            return fail(.providerStopped)
        case .tracked where rendering:
            return .render
        case .tracked:
            consecutiveTracked += 1
            if consecutiveTracked >= Self.requiredConsecutiveTrackedFrames {
                hasAcquired = true
                rendering = true
                waitingSince = nil
                return .render
            }
        case .untracked:
            rendering = false
            consecutiveTracked = 0
        }
        let since = waitingSince ?? now
        waitingSince = since
        let budget = hasAcquired ? Self.recoveryBudget : Self.acquisitionBudget
        guard now - since <= budget else {
            return fail(hasAcquired ? .lost : .neverAcquired)
        }
        return .wait
    }

    /// The layer stopped producing frames. Its next frame starts a new grace window and must
    /// reconfirm tracking, since time spent paused is neither tracking nor loss.
    mutating func suspend() {
        rendering = false
        waitingSince = nil
        consecutiveTracked = 0
    }

    private mutating func fail(_ failure: Failure) -> Decision {
        self.failure = failure
        rendering = false
        return .fail(failure)
    }
}
#endif
