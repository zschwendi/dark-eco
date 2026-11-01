// Compiled together with GOALPad/Vision/Immersive/VisionImmersiveTrackingPolicy.swift and
// -D GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE by Scripts/run-vision-immersive-proof-check.sh.

import Foundation

private typealias Policy = VisionImmersiveTrackingPolicy

private var failures = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("  ok   \(message)")
    } else {
        print("  FAIL \(message)")
        failures += 1
    }
}

/// Compositor frames at 90 Hz from an arbitrary nonzero clock origin.
private let frameInterval: TimeInterval = 1.0 / 90.0
private let start: TimeInterval = 4_884.9

private struct Run {
    var policy = Policy()
    var now = start

    mutating func frame(_ sample: Policy.Sample) -> Policy.Decision {
        defer { now += frameInterval }
        return policy.decide(sample, at: now)
    }

    mutating func frames(_ sample: Policy.Sample, count: Int) -> [Policy.Decision] {
        (0..<count).map { _ in frame(sample) }
    }

    /// Frames of `sample` until the clock passes `seconds` after `origin`; returns every decision.
    mutating func frames(_ sample: Policy.Sample, until seconds: TimeInterval,
                         after origin: TimeInterval) -> [Policy.Decision] {
        var decisions: [Policy.Decision] = []
        while now - origin <= seconds + frameInterval {
            decisions.append(frame(sample))
        }
        return decisions
    }

    mutating func acquire() {
        _ = frames(.tracked, count: Policy.requiredConsecutiveTrackedFrames)
    }
}

private func checkAcquisition() {
    print("Acquisition")
    var run = Run()
    let misses = run.frames(.untracked, count: 45)
    check(misses.allSatisfy { $0 == .wait } && !run.policy.hasAcquired,
          "half a second without any anchor after the session starts waits instead of failing")
    let confirming = run.frames(.tracked, count: Policy.requiredConsecutiveTrackedFrames - 1)
    check(confirming.allSatisfy { $0 == .wait },
          "the first tracked anchors wait until tracking holds")
    check(run.frame(.tracked) == .render && run.policy.hasAcquired,
          "consecutive tracked anchors start rendering")
    check(run.frame(.tracked) == .render, "steady tracking keeps rendering")

    var immediate = Run()
    check(immediate.frame(.tracked) == .wait && immediate.frame(.tracked) == .wait
            && immediate.frame(.tracked) == .render,
          "tracking available at once still needs only the confirmation frames")

    var spurious = Run()
    let origin = spurious.now
    var pattern: [Policy.Decision] = []
    while spurious.now - origin <= Policy.acquisitionBudget + frameInterval {
        pattern.append(spurious.frame(.untracked))
        pattern.append(spurious.frame(.tracked))
    }
    check(!pattern.contains(.render) && !spurious.policy.hasAcquired,
          "an isolated tracked anchor among misses never renders or acquires")
    check(pattern.last == .fail(.neverAcquired),
          "intermittent anchors do not extend the acquisition deadline")

    var never = Run()
    let neverOrigin = never.now
    let neverDecisions = never.frames(.untracked, until: Policy.acquisitionBudget,
                                      after: neverOrigin)
    let firstFailure = neverDecisions.firstIndex { $0 != .wait }
    check(firstFailure.map { neverDecisions[$0] == .fail(.neverAcquired) } ?? false,
          "persistent absence fails as never acquired, not as a loss")
    check(firstFailure.map {
              TimeInterval($0) * frameInterval > Policy.acquisitionBudget
                  && TimeInterval($0) * frameInterval
                      <= Policy.acquisitionBudget + frameInterval
          } ?? false,
          "acquisition fails on the first frame past its budget")
}

private func checkTransientLoss() {
    print("Transient loss")
    var run = Run()
    run.acquire()
    let lossOrigin = run.now
    let brief = run.frames(.untracked, count: 45)
    check(brief.allSatisfy { $0 == .wait },
          "half a second of lost tracking waits without rendering")
    let reconfirming = run.frames(.tracked, count: Policy.requiredConsecutiveTrackedFrames - 1)
    check(reconfirming.allSatisfy { $0 == .wait } && run.frame(.tracked) == .render,
          "recovered tracking renders again after it holds")
    check(run.now - lossOrigin < Policy.recoveryBudget,
          "the scenario recovered inside the recovery budget")

    let secondOrigin = run.now
    let second = run.frames(.untracked, count: Int(Policy.recoveryBudget / frameInterval) - 1)
    check(second.allSatisfy { $0 == .wait } && run.now - secondOrigin < Policy.recoveryBudget,
          "a later loss gets a fresh budget after a confirmed recovery")

    var flicker = Run()
    flicker.acquire()
    let flickerOrigin = flicker.now
    var decisions: [Policy.Decision] = []
    while flicker.now - flickerOrigin <= Policy.recoveryBudget + frameInterval {
        decisions.append(flicker.frame(.untracked))
        decisions.append(flicker.frame(.tracked))
    }
    check(!decisions.contains(.render) && decisions.last == .fail(.lost),
          "flickering tracking neither renders nor postpones the loss deadline")
}

private func checkPersistentLoss() {
    print("Persistent loss")
    var run = Run()
    run.acquire()
    let origin = run.now
    let decisions = run.frames(.untracked, until: Policy.recoveryBudget, after: origin)
    let firstFailure = decisions.firstIndex { $0 != .wait }
    check(firstFailure.map { decisions[$0] == .fail(.lost) } ?? false,
          "loss after acquisition fails as lost, not as never acquired")
    check(firstFailure.map {
              TimeInterval($0) * frameInterval > Policy.recoveryBudget
                  && TimeInterval($0) * frameInterval <= Policy.recoveryBudget + frameInterval
          } ?? false,
          "loss fails on the first frame past the recovery budget")
    check(Policy.recoveryBudget < Policy.acquisitionBudget,
          "a loss is tolerated more briefly than startup")
    check(run.frame(.tracked) == .fail(.lost) && run.frame(.tracked) == .fail(.lost),
          "a failure is final; later tracked anchors do not resume rendering")
}

private func checkProviderStop() {
    print("Provider stop")
    var starting = Run()
    check(starting.frame(.providerStopped) == .fail(.providerStopped),
          "a stopped provider fails at once before acquisition")
    var tracking = Run()
    tracking.acquire()
    check(tracking.frame(.providerStopped) == .fail(.providerStopped),
          "a stopped provider fails at once while tracking")
    var losing = Run()
    losing.acquire()
    _ = losing.frames(.untracked, count: 10)
    check(losing.frame(.providerStopped) == .fail(.providerStopped),
          "a stopped provider fails at once during a grace window")
}

private func checkPauseAndReopen() {
    print("Pause and reopen")
    var run = Run()
    run.acquire()
    _ = run.frames(.untracked, count: 45)
    run.policy.suspend()
    run.now += 30
    check(run.frame(.untracked) == .wait,
          "the first miss after a long pause starts a new window instead of failing")
    check(run.frame(.tracked) == .wait && run.frame(.tracked) == .wait
            && run.frame(.tracked) == .render,
          "tracking is reconfirmed after a pause")

    var steady = Run()
    steady.acquire()
    steady.policy.suspend()
    steady.now += 30
    check(steady.frame(.tracked) == .wait && steady.policy.hasAcquired,
          "a pose after a pause is not trusted before it holds again")
    let resumedOrigin = steady.now
    let resumedLoss = steady.frames(.untracked, until: Policy.recoveryBudget,
                                    after: resumedOrigin)
    check(resumedLoss.last == .fail(.lost),
          "an earlier acquisition still distinguishes a loss after the pause")

    var startingPause = Run()
    _ = startingPause.frames(.untracked, count: 90)
    startingPause.policy.suspend()
    startingPause.now += 30
    check(startingPause.frame(.untracked) == .wait,
          "a pause before acquisition restarts the acquisition window")

    var failed = Run()
    _ = failed.frames(.providerStopped, count: 1)
    failed.policy.suspend()
    check(failed.frame(.tracked) == .fail(.providerStopped),
          "a pause does not clear a reported failure")

    var reopened = Run()
    check(!reopened.policy.hasAcquired && reopened.frame(.tracked) == .wait,
          "each new presenter attempt starts unacquired")
    let reopenedOrigin = reopened.now
    let reopenedDecisions = reopened.frames(.untracked, until: Policy.acquisitionBudget,
                                            after: reopenedOrigin)
    check(reopenedDecisions.last == .fail(.neverAcquired),
          "a reopened attempt reports its own acquisition failure")
}

/// Random sample sequences, pauses, and clock gaps never render a frame whose own sample is not
/// tracked, never wait past the larger budget, and never leave a failure.
private func checkInvariants() {
    print("Invariants")
    var state: UInt64 = 0x9E37_79B9_7F4A_7C15
    func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 33
    }
    var renderedUntracked = false
    var waitedTooLong = false
    var resumedAfterFailure = false
    var lostBeforeAcquisition = false
    for _ in 0..<2_000 {
        var policy = Policy()
        var now = start
        var failed = false
        var waitingSince: TimeInterval?
        for _ in 0..<400 {
            let roll = next() % 100
            if roll == 0 {
                policy.suspend()
                waitingSince = nil
                now += TimeInterval(next() % 50)
                continue
            }
            let sample: Policy.Sample = roll < 2 ? .providerStopped
                : roll < 45 ? .untracked : .tracked
            let decision = policy.decide(sample, at: now)
            if decision == .render && sample != .tracked { renderedUntracked = true }
            if failed && decision == .render { resumedAfterFailure = true }
            if case .fail(let failure) = decision {
                failed = true
                if failure == .lost && !policy.hasAcquired { lostBeforeAcquisition = true }
            }
            if decision == .wait {
                let since = waitingSince ?? now
                waitingSince = since
                if now - since > Policy.acquisitionBudget { waitedTooLong = true }
            } else {
                waitingSince = nil
            }
            now += frameInterval * TimeInterval(1 + next() % 3)
        }
    }
    check(!renderedUntracked, "no untracked or stopped sample ever renders")
    check(!waitedTooLong, "no wait outlasts the acquisition budget")
    check(!resumedAfterFailure, "no failure ever returns to rendering")
    check(!lostBeforeAcquisition, "a loss is reported only after tracking was acquired")
}

@main
private enum VisionImmersiveTrackingPolicyCheck {
    static func main() {
        checkAcquisition()
        checkTransientLoss()
        checkPersistentLoss()
        checkProviderStop()
        checkPauseAndReopen()
        checkInvariants()
        guard failures == 0 else {
            print("visionOS immersive tracking policy checks failed: \(failures)")
            fatalError("immersive tracking policy check failed")
        }
        print("visionOS immersive tracking policy checks passed")
    }
}
