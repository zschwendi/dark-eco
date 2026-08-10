nonisolated enum VisionStereoSubmissionDisposition: Equatable, Sendable {
    case skipped
    case submitted
    case busy
    case failed
}

nonisolated struct VisionStereoSubmissionWatchdog: Sendable {
    enum Action: Equatable, Sendable {
        case continueStereo
        case failClosed
    }

    static let defaultMaximumConsecutiveBusyUpdates = 6
    static let defaultMaximumConsecutiveFailures = 1

    let maximumConsecutiveBusyUpdates: Int
    let maximumConsecutiveFailures: Int

    private(set) var consecutiveBusyUpdates = 0
    private(set) var consecutiveFailures = 0

    init(
        maximumConsecutiveBusyUpdates: Int = defaultMaximumConsecutiveBusyUpdates,
        maximumConsecutiveFailures: Int = defaultMaximumConsecutiveFailures
    ) {
        precondition(maximumConsecutiveBusyUpdates > 0)
        precondition(maximumConsecutiveFailures > 0)
        self.maximumConsecutiveBusyUpdates = maximumConsecutiveBusyUpdates
        self.maximumConsecutiveFailures = maximumConsecutiveFailures
    }

    mutating func observe(_ disposition: VisionStereoSubmissionDisposition) -> Action {
        switch disposition {
        case .skipped, .submitted:
            consecutiveBusyUpdates = 0
            consecutiveFailures = 0
        case .busy:
            consecutiveBusyUpdates += 1
            consecutiveFailures = 0
            if consecutiveBusyUpdates >= maximumConsecutiveBusyUpdates {
                return .failClosed
            }
        case .failed:
            consecutiveBusyUpdates = 0
            consecutiveFailures += 1
            if consecutiveFailures >= maximumConsecutiveFailures {
                return .failClosed
            }
        }
        return .continueStereo
    }
}

nonisolated struct VisionStereoCadenceGate: Sendable {
    static let framesPerSecond = 60.0
    static let discontinuitySeconds = 0.25

    private let interval = 1.0 / framesPerSecond
    private var lastUpdateTime: Double?
    private var nextScheduledTime: Double?

    mutating func scheduledTime(for updateTime: Double) -> Double? {
        guard updateTime.isFinite else { return nil }
        if let lastUpdateTime,
           updateTime >= lastUpdateTime,
           updateTime - lastUpdateTime <= Self.discontinuitySeconds,
           let nextScheduledTime {
            self.lastUpdateTime = updateTime
            let tolerance = interval * 0.001
            guard updateTime + tolerance >= nextScheduledTime else { return nil }
            let elapsedIntervals = max(
                Int(((updateTime - nextScheduledTime) / interval).rounded(.down)),
                0
            )
            self.nextScheduledTime = nextScheduledTime
                + Double(elapsedIntervals + 1) * interval
            return nextScheduledTime
        }

        lastUpdateTime = updateTime
        nextScheduledTime = updateTime + interval
        return updateTime
    }

    mutating func reset() {
        lastUpdateTime = nil
        nextScheduledTime = nil
    }
}

nonisolated struct VisionStereoLivenessWatchdog: Sendable {
    static let defaultTimeoutSeconds = 0.25

    let timeoutSeconds: Double

    private(set) var isActive = false
    private(set) var lastHeartbeat: Double?

    init(timeoutSeconds: Double = defaultTimeoutSeconds) {
        precondition(timeoutSeconds.isFinite && timeoutSeconds > 0)
        self.timeoutSeconds = timeoutSeconds
    }

    mutating func setActive(_ active: Bool, at time: Double) {
        guard time.isFinite else { return }
        isActive = active
        lastHeartbeat = active ? time : nil
    }

    mutating func heartbeat(at time: Double) {
        guard isActive, time.isFinite else { return }
        lastHeartbeat = time
    }

    mutating func hasTimedOut(at time: Double) -> Bool {
        guard isActive, time.isFinite, let lastHeartbeat else { return false }
        guard time >= lastHeartbeat else {
            self.lastHeartbeat = time
            return false
        }
        return time - lastHeartbeat >= timeoutSeconds
    }
}
