nonisolated struct AudioPlaybackPolicy: Equatable, Sendable {
    private(set) var playbackRequested = false
    private(set) var lifecycleAllowsPlayback = true
    private(set) var interruptionAllowsPlayback = true
    private(set) var routeAllowsPlayback = true

    var shouldRun: Bool {
        playbackRequested && lifecycleAllowsPlayback
            && interruptionAllowsPlayback && routeAllowsPlayback
    }

    mutating func requestStart() {
        playbackRequested = true
    }

    mutating func requestStop() {
        playbackRequested = false
        interruptionAllowsPlayback = true
        routeAllowsPlayback = true
    }

    mutating func setLifecycleActive(_ active: Bool) {
        lifecycleAllowsPlayback = active
    }

    mutating func interruptionBegan() {
        guard playbackRequested else { return }
        interruptionAllowsPlayback = false
    }

    mutating func interruptionEnded(shouldResume: Bool) {
        guard playbackRequested else { return }
        if shouldResume {
            interruptionAllowsPlayback = true
        }
    }

    mutating func setRouteAvailable(_ available: Bool) {
        guard playbackRequested else { return }
        routeAllowsPlayback = available
    }
}
