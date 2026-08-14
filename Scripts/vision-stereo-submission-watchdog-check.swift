private var failures = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("  ok   \(message)")
    } else {
        print("  FAIL \(message)")
        failures += 1
    }
}

@main
private enum VisionStereoSubmissionWatchdogCheck {
    static func main() {
        var watchdog = VisionStereoSubmissionWatchdog(
            maximumConsecutiveBusyUpdates: 3,
            maximumConsecutiveFailures: 2
        )

        check(watchdog.observe(.busy) == .continueStereo,
              "the first busy update does not fail stereo")
        check(watchdog.observe(.busy) == .continueStereo,
              "the bounded busy grace period remains nonblocking")
        check(watchdog.observe(.submitted) == .continueStereo,
              "a submission resets the busy watchdog")
        check(watchdog.consecutiveBusyUpdates == 0,
              "the busy counter resets after submission")
        check(watchdog.observe(.busy) == .continueStereo,
              "busy restarts from zero after submission")
        check(watchdog.observe(.busy) == .continueStereo,
              "the restarted busy grace period remains bounded")
        check(watchdog.observe(.busy) == .failClosed,
              "the configured consecutive-busy limit fails closed")

        watchdog = VisionStereoSubmissionWatchdog(
            maximumConsecutiveBusyUpdates: 3,
            maximumConsecutiveFailures: 2
        )
        check(watchdog.observe(.failed) == .continueStereo,
              "a configured one-error grace period can continue")
        check(watchdog.observe(.failed) == .failClosed,
              "the configured consecutive-error limit fails closed")

        watchdog = VisionStereoSubmissionWatchdog()
        check(watchdog.observe(.failed) == .failClosed,
              "the product default fails closed on the first native error")
        check(watchdog.observe(.skipped) == .continueStereo,
              "an inactive-session skip resets the watchdog")

        var cadence = VisionStereoCadenceGate()
        var scheduledTimes: [Double] = []
        for update in 0..<180 {
            if let scheduled = cadence.scheduledTime(for: Double(update) / 90.0) {
                scheduledTimes.append(scheduled)
            }
        }
        check(scheduledTimes.count == 180,
              "180 RealityKit updates at 90 Hz schedule exactly 180 game frames")
        check(zip(scheduledTimes, scheduledTimes.dropFirst()).allSatisfy {
            abs(($0.1 - $0.0) - (1.0 / 90.0)) < 0.000_001
        }, "scheduled game timestamps retain a deterministic 90 Hz cadence")
        check(cadence.scheduledTime(for: 10.0) == 10.0,
              "a lifecycle-sized discontinuity restarts cadence at the current time")
        cadence.reset()
        check(cadence.scheduledTime(for: 42.0) == 42.0,
              "an explicit lifecycle reset starts a fresh schedule")

        var liveness = VisionStereoLivenessWatchdog(timeoutSeconds: 0.25)
        liveness.setActive(true, at: 1.0)
        check(!liveness.hasTimedOut(at: 1.24),
              "an active scene remains healthy inside the heartbeat deadline")
        liveness.heartbeat(at: 1.2)
        check(!liveness.hasTimedOut(at: 1.44),
              "a RealityKit update refreshes the independent liveness deadline")
        check(liveness.hasTimedOut(at: 1.45),
              "an active scene with no rendering updates fails at the timeout")
        liveness.setActive(false, at: 2.0)
        check(!liveness.hasTimedOut(at: 20.0),
              "an inactive scene suspends the rendering-update timeout")
        liveness.setActive(true, at: 30.0)
        check(!liveness.hasTimedOut(at: 30.24),
              "scene reactivation starts a fresh liveness deadline")
        liveness.heartbeat(at: 29.0)
        check(!liveness.hasTimedOut(at: 29.1),
              "a backward clock discontinuity does not create a false timeout")

        guard failures == 0 else {
            print("Vision stereo submission watchdog check failed: \(failures) assertion(s)")
            fatalError("watchdog check failed")
        }
        print("Vision stereo submission watchdog check passed")
    }
}
