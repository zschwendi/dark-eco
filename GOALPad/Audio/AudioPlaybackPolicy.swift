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

/// How many frames a manually rendered (simulator-only) engine owes at a wake. The target comes
/// from total monotonic elapsed time, so fractional frames never accumulate drift; a late wake
/// renders at most `maxFramesPerWake` and drops the rest instead of catching up in a burst.
nonisolated struct ManualAudioClock: Equatable, Sendable {
    let sampleRate: Int
    let maxFramesPerWake: Int
    private(set) var renderedFrames: Int64 = 0
    private(set) var droppedFrames: Int64 = 0

    init(sampleRate: Int, maxFramesPerWake: Int) {
        self.sampleRate = sampleRate
        self.maxFramesPerWake = maxFramesPerWake
    }

    mutating func framesDue(elapsed: Duration) -> Int {
        let parts = elapsed.components
        guard parts.seconds >= 0, parts.attoseconds >= 0 else { return 0 }
        let rate = Int64(sampleRate)
        let nanoseconds = parts.attoseconds / 1_000_000_000
        let target = parts.seconds * rate + nanoseconds * rate / 1_000_000_000
        let owed = target - renderedFrames - droppedFrames
        guard owed > 0 else { return 0 }
        let frames = min(owed, Int64(maxFramesPerWake))
        droppedFrames += owed - frames
        renderedFrames += frames
        return Int(frames)
    }
}
