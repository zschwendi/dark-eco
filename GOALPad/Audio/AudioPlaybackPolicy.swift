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
        interruptionAllowsPlayback = false
    }

    mutating func interruptionEnded(shouldResume: Bool) {
        if shouldResume {
            interruptionAllowsPlayback = true
        }
    }

    mutating func setRouteAvailable(_ available: Bool) {
        routeAllowsPlayback = available
    }
}
