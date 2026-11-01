#if GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE
nonisolated(unsafe) private var failures = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("  ok   \(message)")
    } else {
        print("  FAIL \(message)")
        failures += 1
    }
}

private func checkOrdinaryWindowPhases() {
    print("Ordinary window lifecycle")
    var activity = VisionImmersiveActivity()
    check(activity.effectivePhase == .active,
          "a new session preserves the active window phase")
    activity.setWindowPhase(.inactive)
    check(activity.effectivePhase == .inactive,
          "an inactive window suspends when there is no immersive owner")
    activity.setWindowPhase(.background)
    check(activity.effectivePhase == .background,
          "a background window stays background when there is no immersive owner")
    activity.setRunning(true, owner: 90)
    check(activity.effectivePhase == .background,
          "a renderer report without an owner cannot change ordinary behavior")
    activity.setWindowPhase(.active)
    check(activity.effectivePhase == .active,
          "an ordinary window returns to active")
}

private func checkOpeningHandoff() {
    print("Opening handoff")
    var activity = VisionImmersiveActivity()
    activity.begin(owner: 1)
    activity.setWindowPhase(.inactive)
    check(activity.effectivePhase == .active,
          "the tentative opening lease prevents a hidden window false-suspend")
    activity.setRunning(true, owner: 1)
    check(activity.effectivePhase == .active,
          "the current running renderer confirms active")

    var reverseOrder = VisionImmersiveActivity()
    reverseOrder.begin(owner: 2)
    reverseOrder.setRunning(true, owner: 2)
    reverseOrder.setWindowPhase(.inactive)
    check(reverseOrder.effectivePhase == .active,
          "renderer-first and window-first handoffs converge to active")

    var pausedAtFirstReport = VisionImmersiveActivity()
    pausedAtFirstReport.begin(owner: 6)
    pausedAtFirstReport.setWindowPhase(.inactive)
    pausedAtFirstReport.setRunning(false, owner: 6)
    check(pausedAtFirstReport.effectivePhase == .inactive,
          "the first matching paused report overrides the tentative opening lease")
}

private func checkRunningAndPaused() {
    print("Running and paused immersive scene")
    var activity = VisionImmersiveActivity()
    activity.begin(owner: 3)
    activity.setRunning(true, owner: 3)
    activity.setWindowPhase(.inactive)
    check(activity.effectivePhase == .active,
          "a current running immersive scene overrides an inactive window")
    activity.setWindowPhase(.background)
    check(activity.effectivePhase == .active,
          "a current running immersive scene overrides the raw background window")
    activity.setRunning(false, owner: 3)
    check(activity.effectivePhase == .background,
          "a renderer pause reveals the raw background phase")
    activity.setWindowPhase(.inactive)
    check(activity.effectivePhase == .inactive,
          "a paused renderer plus inactive window remains suspended")
    activity.setRunning(true, owner: 3)
    check(activity.effectivePhase == .active,
          "the current renderer can resume after a pause")
}

private func checkCancellationAndFailure() {
    print("Cancellation and open failure")
    var inactiveWindow = VisionImmersiveActivity()
    inactiveWindow.begin(owner: 4)
    inactiveWindow.setWindowPhase(.inactive)
    inactiveWindow.end(owner: 4)
    check(inactiveWindow.effectivePhase == .inactive,
          "ending a failed open restores the inactive raw window")

    var activeWindow = VisionImmersiveActivity()
    activeWindow.begin(owner: 5)
    activeWindow.end(owner: 5)
    check(activeWindow.effectivePhase == .active,
          "cancelling an open restores the active raw window")
}

private func checkStaleOwners() {
    print("Owner replacement and stale callbacks")
    var activity = VisionImmersiveActivity()
    activity.begin(owner: 10)
    activity.setRunning(true, owner: 10)
    activity.setWindowPhase(.inactive)
    activity.begin(owner: 11)
    activity.setRunning(false, owner: 10)
    check(activity.effectivePhase == .active,
          "an old renderer pause cannot suspend a newer tentative owner")
    activity.end(owner: 10)
    check(activity.effectivePhase == .active,
          "an old owner end cannot clear a newer opening lease")
    activity.setRunning(false, owner: 11)
    check(activity.effectivePhase == .inactive,
          "the current owner pause still suspends")
    activity.setRunning(true, owner: 10)
    check(activity.effectivePhase == .inactive,
          "an old running callback cannot reactivate the current paused owner")
}

private func checkCloseOrdering() {
    print("Close ordering")
    var windowFirst = VisionImmersiveActivity()
    windowFirst.begin(owner: 20)
    windowFirst.setRunning(true, owner: 20)
    windowFirst.setWindowPhase(.inactive)
    windowFirst.setWindowPhase(.active)
    check(windowFirst.effectivePhase == .active,
          "window restoration keeps the session active before renderer stop")
    windowFirst.setRunning(false, owner: 20)
    check(windowFirst.effectivePhase == .active,
          "renderer stop after window restoration keeps the session active")
    windowFirst.end(owner: 20)
    check(windowFirst.effectivePhase == .active,
          "ending after window-first close preserves the active window")

    var rendererFirst = VisionImmersiveActivity()
    rendererFirst.begin(owner: 21)
    rendererFirst.setRunning(true, owner: 21)
    rendererFirst.setWindowPhase(.inactive)
    rendererFirst.setRunning(false, owner: 21)
    check(rendererFirst.effectivePhase == .inactive,
          "renderer stop first reveals the still-inactive window")
    rendererFirst.setWindowPhase(.active)
    check(rendererFirst.effectivePhase == .active,
          "window restoration reactivates a stopped immersive owner")
    rendererFirst.end(owner: 21)
    check(rendererFirst.effectivePhase == .active,
          "later window restoration and owner end converge to active")

    var ownerEndsFirst = VisionImmersiveActivity()
    ownerEndsFirst.begin(owner: 22)
    ownerEndsFirst.setRunning(true, owner: 22)
    ownerEndsFirst.setWindowPhase(.background)
    ownerEndsFirst.end(owner: 22)
    check(ownerEndsFirst.effectivePhase == .background,
          "ending the current owner immediately restores a background window")
    ownerEndsFirst.setRunning(true, owner: 22)
    check(ownerEndsFirst.effectivePhase == .background,
          "a late callback after close cannot revive the ended owner")
}

@main
private enum VisionImmersiveActivityCheck {
    static func main() {
        checkOrdinaryWindowPhases()
        checkOpeningHandoff()
        checkRunningAndPaused()
        checkCancellationAndFailure()
        checkStaleOwners()
        checkCloseOrdering()

        guard failures == 0 else {
            print("vision immersive activity checks failed: \(failures)")
            fatalError("vision immersive activity checks failed")
        }
        print("vision immersive activity checks passed")
    }
}
#endif
