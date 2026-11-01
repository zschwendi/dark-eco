// Compiled together with GOALPad/Vision/Immersive/VisionImmersiveProofLifecycle.swift and
// -D GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE by Scripts/run-vision-immersive-proof-check.sh.

private typealias Lifecycle = VisionImmersiveProofLifecycle

private var failures = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("  ok   \(message)")
    } else {
        print("  FAIL \(message)")
        failures += 1
    }
}

/// An attempt whose renderer is presenting, as after a successful open.
private func presenting() -> (Lifecycle, UInt64) {
    var lifecycle = Lifecycle()
    let attempt = lifecycle.beginOpen()!
    _ = lifecycle.rendererArrived(attempt: attempt)
    _ = lifecycle.openFinished(attempt: attempt, result: .opened)
    _ = lifecycle.firstFramePresented(attempt: attempt)
    return (lifecycle, attempt)
}

private func checkReopenWaitsForClosing() {
    print("Close and reopen")
    let (presentingLifecycle, first) = presenting()
    var lifecycle = presentingLifecycle
    let close = lifecycle.close()
    check(close.releaseFrameLoop && close.cancelFirstFrameTimeout && close.dismissalRequest != nil
            && lifecycle.phase == .closing(failure: nil),
          "closing returns frames to the window at once and requests a dismissal")
    check(!lifecycle.canBeginOpen && lifecycle.beginOpen() == nil,
          "a new attempt cannot begin while the previous space is still closing")
    lifecycle.dismissalFinished(request: close.dismissalRequest ?? 0)
    check(lifecycle.phase == .closing(failure: nil) && lifecycle.beginOpen() == nil,
          "a finished dismissal still waits for the old layer renderer to stop")
    _ = lifecycle.presenterStopped(attempt: first)
    check(lifecycle.phase == .closed, "the proof closes once the space and renderer are gone")
    let second = lifecycle.beginOpen()
    check(second == first + 1 && lifecycle.phase == .opening,
          "only then does a new attempt begin")

    let late = lifecycle.rendererArrived(attempt: first)
    check(late == Lifecycle.Effects() && lifecycle.phase == .opening,
          "a late renderer from the earlier attempt neither presents nor dismisses the new space")
    let accepted = lifecycle.rendererArrived(attempt: second ?? 0)
    let duplicate = lifecycle.rendererArrived(attempt: second ?? 0)
    check(accepted.startPresenter && !duplicate.startPresenter
            && duplicate.dismissalRequest == nil,
          "only the first renderer opened for the current attempt presents")
    check(lifecycle.openFinished(attempt: first, result: .failed("stale")) == Lifecycle.Effects()
            && lifecycle.fail(attempt: first, message: "stale") == Lifecycle.Effects()
            && lifecycle.firstFramePresented(attempt: first) == Lifecycle.Effects()
            && lifecycle.phase == .opening,
          "results reported for an earlier attempt are ignored")
}

private func checkCloseWhileOpening() {
    print("Close while visionOS is opening the space")
    var lifecycle = Lifecycle()
    let attempt = lifecycle.beginOpen()!
    let close = lifecycle.close()
    check(close.dismissalRequest == nil && lifecycle.phase == .closing(failure: nil)
            && !lifecycle.canBeginOpen,
          "closing before anything opened waits for the open result")
    let lateRenderer = lifecycle.rendererArrived(attempt: attempt)
    check(!lateRenderer.startPresenter && lateRenderer.dismissalRequest != nil,
          "a renderer arriving after its attempt closed is dismissed instead of presenting")
    let opened = lifecycle.openFinished(attempt: attempt, result: .opened)
    check(opened.dismissalRequest != nil && opened.dismissalRequest != lateRenderer.dismissalRequest
            && !opened.armFirstFrameTimeout,
          "a space that finishes opening after the close is dismissed again")
    lifecycle.dismissalFinished(request: lateRenderer.dismissalRequest ?? 0)
    check(lifecycle.phase == .closing(failure: nil),
          "an earlier dismissal does not end closing while a later one is outstanding")
    lifecycle.dismissalFinished(request: opened.dismissalRequest ?? 0)
    check(lifecycle.phase == .closed && lifecycle.canBeginOpen,
          "closing ends after the latest dismissal")
}

private func checkFailures() {
    print("Failures and system invalidation")
    var (lifecycle, attempt) = presenting()
    let failure = lifecycle.fail(attempt: attempt, message: "GPU work failed")
    check(failure.releaseFrameLoop && failure.dismissalRequest != nil
            && lifecycle.phase == .closing(failure: "GPU work failed"),
          "a failure returns frames to the window and keeps its reason while closing")
    lifecycle.dismissalFinished(request: failure.dismissalRequest ?? 0)
    _ = lifecycle.presenterStopped(attempt: attempt)
    check(lifecycle.phase == .failed("GPU work failed") && lifecycle.canBeginOpen,
          "the reason is reported once the space is gone, and a retry may begin")

    (lifecycle, attempt) = presenting()
    let invalidated = lifecycle.presenterStopped(attempt: attempt)
    check(invalidated.releaseFrameLoop && invalidated.dismissalRequest != nil
            && lifecycle.phase == .closing(failure: nil),
          "visionOS invalidating the layer returns frames to the window")
    lifecycle.dismissalFinished(request: invalidated.dismissalRequest ?? 0)
    check(lifecycle.phase == .closed, "and the proof closes after the dismissal")

    (lifecycle, attempt) = presenting()
    check(lifecycle.firstFrameTimedOut(attempt: attempt, message: "late") == Lifecycle.Effects()
            && lifecycle.phase == .presenting,
          "the first-frame timeout cannot end a proof that is already presenting")

    lifecycle = Lifecycle()
    attempt = lifecycle.beginOpen()!
    _ = lifecycle.rendererArrived(attempt: attempt)
    _ = lifecycle.openFinished(attempt: attempt, result: .opened)
    let timeout = lifecycle.firstFrameTimedOut(attempt: attempt, message: "no frame")
    check(timeout.releaseFrameLoop && timeout.dismissalRequest != nil
            && lifecycle.phase == .closing(failure: "no frame"),
          "an opening proof without a frame times out and dismisses its space")

    lifecycle = Lifecycle()
    attempt = lifecycle.beginOpen()!
    let cancelled = lifecycle.openFinished(attempt: attempt, result: .cancelled)
    check(cancelled.releaseFrameLoop && cancelled.dismissalRequest == nil
            && lifecycle.phase == .closed,
          "a cancelled open closes without dismissing anything")
    attempt = lifecycle.beginOpen()!
    _ = lifecycle.openFinished(attempt: attempt, result: .failed("could not open"))
    check(lifecycle.phase == .failed("could not open"), "a failed open reports its reason")

    lifecycle = Lifecycle()
    attempt = lifecycle.beginOpen()!
    _ = lifecycle.rendererArrived(attempt: attempt)
    let startFailure = lifecycle.fail(attempt: attempt, message: "no renderer")
    _ = lifecycle.presenterStopped(attempt: attempt)
    let opened = lifecycle.openFinished(attempt: attempt, result: .opened)
    lifecycle.dismissalFinished(request: startFailure.dismissalRequest ?? 0)
    check(lifecycle.phase == .closing(failure: "no renderer"),
          "a presenter that cannot start still waits for the space it opened")
    lifecycle.dismissalFinished(request: opened.dismissalRequest ?? 0)
    check(lifecycle.phase == .failed("no renderer"),
          "and reports why once that space is dismissed")
}

private func checkPauseRoute() {
    print("Native pause route")
    check(VisionImmersiveTickRoute(isNativePaused: false, usesControllerMenuNavigation: false)
            == .perEye,
          "active gameplay renders both eyes")
    check(VisionImmersiveTickRoute(isNativePaused: false, usesControllerMenuNavigation: true)
            == .menuPlane,
          "progress, menu, not-ready, and warp destination lists keep the menu plane")
    check(VisionImmersiveTickRoute(isNativePaused: true, usesControllerMenuNavigation: true)
            == .exitForPause,
          "native pause, itself a menu, leaves immersion instead of drawing the menu plane")
    check(VisionImmersiveTickRoute(isNativePaused: true, usesControllerMenuNavigation: false)
            == .exitForPause,
          "pause leaves immersion regardless of the broader menu-navigation state")
}

private func checkPauseExit() {
    print("Native pause exit")
    // Paused after a presented frame: the close releases once, then waits for both the stopped
    // presenter and the dismissal, in either order, and never reports a failure.
    var (lifecycle, attempt) = presenting()
    let exit = lifecycle.close()
    check(exit.releaseFrameLoop && exit.cancelFirstFrameTimeout && exit.dismissalRequest != nil
            && !exit.startPresenter && !exit.armFirstFrameTimeout
            && lifecycle.phase == .closing(failure: nil),
          "a pause exit releases the frame loop and dismisses the space while closing")
    check(lifecycle.close() == Lifecycle.Effects() && !lifecycle.isActive,
          "a later frame's pause check cannot release or dismiss a second time")
    _ = lifecycle.presenterStopped(attempt: attempt)
    check(lifecycle.phase == .closing(failure: nil) && lifecycle.beginOpen() == nil,
          "a stopped presenter still waits for the dismissal")
    lifecycle.dismissalFinished(request: exit.dismissalRequest ?? 0)
    check(lifecycle.phase == .closed && lifecycle.canBeginOpen,
          "the pause exit ends closed, not failed, once the space is gone")

    // Already paused at the first tick: the renderer arrived but visionOS has not yet reported
    // the open result.
    lifecycle = Lifecycle()
    attempt = lifecycle.beginOpen()!
    let accepted = lifecycle.rendererArrived(attempt: attempt)
    let early = lifecycle.close()
    check(accepted.startPresenter && early.releaseFrameLoop && early.dismissalRequest != nil
            && lifecycle.phase == .closing(failure: nil),
          "a pause seen while opening closes through the same release and dismissal")
    let opened = lifecycle.openFinished(attempt: attempt, result: .opened)
    check(!opened.armFirstFrameTimeout && !opened.releaseFrameLoop
            && opened.dismissalRequest != nil,
          "an open completing after the pause exit is dismissed and arms no timeout")
    lifecycle.dismissalFinished(request: early.dismissalRequest ?? 0)
    lifecycle.dismissalFinished(request: opened.dismissalRequest ?? 0)
    check(lifecycle.phase == .closing(failure: nil),
          "dismissals alone do not end closing while the presenter runs")
    check(lifecycle.presenterStopped(attempt: attempt) == Lifecycle.Effects()
            && lifecycle.phase == .closed,
          "the stopped presenter completes the exit without releasing again")
    check(lifecycle.firstFramePresented(attempt: attempt) == Lifecycle.Effects()
            && lifecycle.phase == .closed,
          "a first-frame report arriving after the exit cannot reopen presentation")
}

@main
private enum VisionImmersiveProofLifecycleCheck {
    static func main() {
        checkReopenWaitsForClosing()
        checkCloseWhileOpening()
        checkFailures()
        checkPauseRoute()
        checkPauseExit()
        checkNativePausePolicy()
        guard failures == 0 else {
            print("visionOS immersive proof lifecycle checks failed: \(failures)")
            fatalError("immersive proof lifecycle check failed")
        }
        print("visionOS immersive proof lifecycle checks passed")
    }
}

private func pause(_ pause: Bool = false, progress: Bool = true, jak1: Bool = true,
                   active: Bool = true, available: Bool = true, start: Int = 0) -> Bool {
    VisionImmersiveNativePausePolicy.isNativePause(
        modeIsPause: pause, modeIsProgress: progress, isJak1: jak1, runIsActive: active,
        progressAvailable: available, startingScreenRawValue: start)
}

private func checkNativePausePolicy() {
    check(pause(true, progress: false, jak1: false, active: false, available: false, start: -2),
          "legacy pause is native pause regardless of progress state")
    check(pause(), "active Jak1 progress at fuel-cell origin 0 is native pause")
    for start in [27, 29, 64, -2] {
        check(!pause(start: start), "progress origin \(start) keeps its existing route")
    }
    check(!pause(available: false), "an unavailable progress snapshot is not pause")
    check(!pause(active: false), "an inactive run is not pause")
    check(!pause(jak1: false), "non-Jak1 progress is not pause")
    check(!pause(progress: false), "gameplay at origin 0 is not pause")
}
