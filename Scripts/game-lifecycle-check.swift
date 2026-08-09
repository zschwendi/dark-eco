import Foundation

private var failures = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("  ok   \(message)")
    } else {
        print("  FAIL \(message)")
        failures += 1
    }
}

private func generation(from action: GameplayLifecycleState.Action) -> UInt64? {
    guard case .prepareForeground(let generation) = action else { return nil }
    return generation
}

private func normalLifecycleRoundTrip() {
    print("a normal background round trip resumes only after its save gate")
    var state = GameplayLifecycleState()
    check(state.frameLoopEnabled, "a newly active scene can run")
    check(state.transition(to: .active, prepareOnActivation: true) == .none,
          "a repeated active callback is idempotent")
    check(state.generation == 0, "a repeated active callback does not create a generation")

    check(state.transition(to: .inactive, prepareOnActivation: false) == .none,
          "inactive closes synchronously")
    check(!state.frameLoopEnabled, "inactive suspends the frame loop")
    _ = state.transition(to: .background, prepareOnActivation: false)
    let action = state.transition(to: .active, prepareOnActivation: true)
    let activeGeneration = generation(from: action)
    check(activeGeneration != nil, "foreground begins one save preparation")
    check(!state.frameLoopEnabled, "foreground stays suspended before save preparation completes")
    check(state.transition(to: .active, prepareOnActivation: true) == .none,
          "repeated active does not duplicate preparation")
    check(state.completePreparation(generation: activeGeneration!, succeeded: true) == .resumed,
          "the current successful generation resumes")
    check(state.frameLoopEnabled, "the successful generation reopens the frame loop")
}

private func staleCompletionCannotResume() {
    print("a stale preparation cannot reopen a later active generation")
    var state = GameplayLifecycleState()
    _ = state.transition(to: .inactive, prepareOnActivation: false)
    let firstGeneration = generation(from:
        state.transition(to: .active, prepareOnActivation: true))!
    _ = state.transition(to: .inactive, prepareOnActivation: false)
    _ = state.transition(to: .background, prepareOnActivation: false)
    check(state.transition(to: .active, prepareOnActivation: true) == .none,
          "the in-flight task remains the only task")

    let staleCompletion = state.completePreparation(
        generation: firstGeneration,
        succeeded: true
    )
    let currentGeneration = generation(from: staleCompletion)
    check(currentGeneration == state.generation,
          "stale success hands ownership to the latest active generation")
    check(!state.frameLoopEnabled, "stale success cannot resume gameplay")
    check(state.completePreparation(generation: currentGeneration!, succeeded: true) == .resumed,
          "the latest generation may resume")
}

private func suspensionAndFailureAreRetryable() {
    print("completion while suspended and a save failure remain safely retryable")
    var state = GameplayLifecycleState()
    _ = state.transition(to: .inactive, prepareOnActivation: false)
    let suspendedGeneration = generation(from:
        state.transition(to: .active, prepareOnActivation: true))!
    _ = state.transition(to: .background, prepareOnActivation: false)
    check(state.completePreparation(generation: suspendedGeneration, succeeded: true) == .suspended,
          "completion in background cannot resume")
    check(!state.frameLoopEnabled, "background completion keeps the frame loop closed")

    let retryGeneration = generation(from:
        state.transition(to: .active, prepareOnActivation: true))!
    check(state.completePreparation(generation: retryGeneration, succeeded: false) == .failed,
          "unsafe save recovery remains a hard gate")
    check(!state.frameLoopEnabled, "failed save recovery keeps gameplay suspended")
    check(generation(from: state.requestPreparationIfNeeded()) == retryGeneration,
          "a save-readiness callback can retry without a fake scene activation")
    check(state.completePreparation(generation: retryGeneration, succeeded: true) == .resumed,
          "the retry can safely resume")
}

private func presentationOwnershipTransfersDeterministically() {
    print("one shared presentation surface has one deterministic active owner")
    var state = PresentationOwnershipState<String>()
    state.register("first")
    state.activate("first")
    state.deactivate("first")
    check(state.owner == nil, "backgrounding the only active host releases surface ownership")
    state.activate("first")
    check(state.owner == "first", "the same host can reacquire ownership after activation")
    state.register("second")
    state.activate("second")
    check(state.owner == "first", "another active window cannot steal the live surface")
    state.deactivate("second")
    check(state.owner == "first", "a non-owner cannot detach the live surface")
    state.activate("second")
    state.deactivate("first")
    check(state.owner == "second",
          "owner deactivation transfers to an already-active window without another activation")
    state.activate("first")
    check(state.owner == "second", "reactivation leaves the current active owner stable")
    state.unregister("second")
    check(state.owner == "first", "removing the owner transfers to the remaining active window")
    state.unregister("first")
    check(state.owner == nil, "removing the final owner detaches the shared surface")
}

private func bootActivationNeedsNoCompetingPreparation() {
    print("boot activation can publish one already-gated runtime without a second save task")
    var state = GameplayLifecycleState()
    _ = state.transition(to: .inactive, prepareOnActivation: false)
    check(state.transition(to: .active, prepareOnActivation: false) == .none,
          "startup owns its existing pregame gate")
    check(state.activateWithoutPreparation(), "boot completion activates while the scene is active")
    _ = state.transition(to: .background, prepareOnActivation: false)
    check(!state.activateWithoutPreparation(), "boot completion in background stays suspended")
}

private func stoppedSessionInvalidatesPreparation() {
    print("stopping a session invalidates foreground work and permits a clean next boot")
    var state = GameplayLifecycleState()
    _ = state.transition(to: .inactive, prepareOnActivation: false)
    let staleGeneration = generation(from:
        state.transition(to: .active, prepareOnActivation: true))!
    state.resetForStoppedSession()
    check(!state.isPreparingForeground, "shutdown clears foreground preparation ownership")
    check(state.completePreparation(generation: staleGeneration, succeeded: true) == .none,
          "a cancelled foreground completion cannot resume a stopped session")
    check(state.activateWithoutPreparation(), "the next active boot can claim the frame loop")
}

private func controlsGuideSuspendsIdempotently() {
    print("the first-run controls guide owns a deterministic gameplay suspension")
    var state = ControlsGuideSuspensionState()
    check(state.present(), "presenting the guide acquires suspension")
    check(state.blocksGameplay, "the guide blocks gameplay while visible")
    check(!state.present(), "duplicate presentation cannot acquire twice")
    check(state.dismiss(), "dismissal releases the guide suspension")
    check(!state.blocksGameplay, "dismissal reopens gameplay eligibility")
    check(!state.dismiss(), "duplicate dismissal cannot resume twice")
    _ = state.present()
    state.reset()
    check(!state.blocksGameplay, "session shutdown clears a visible guide suspension")
}

private func audioLifecycleOwnership() {
    print("audio interruptions and routes cannot override lifecycle suspension")
    var policy = AudioPlaybackPolicy()
    policy.requestStart()
    check(policy.shouldRun, "requested foreground audio may run")
    policy.setLifecycleActive(false)
    check(!policy.shouldRun, "background blocks audio")
    policy.interruptionBegan()
    policy.setLifecycleActive(true)
    check(!policy.shouldRun, "foreground cannot override an active interruption")
    policy.interruptionEnded(shouldResume: false)
    check(!policy.shouldRun, "an interruption without shouldResume remains stopped")
    policy.interruptionEnded(shouldResume: true)
    check(policy.shouldRun, "an authorized interruption end resumes in the foreground")
    policy.setRouteAvailable(false)
    check(!policy.shouldRun, "a lost route blocks audio")
    policy.setLifecycleActive(false)
    policy.setRouteAvailable(true)
    check(!policy.shouldRun, "a new route cannot override background suspension")
    policy.requestStop()
    policy.setLifecycleActive(true)
    check(!policy.shouldRun, "session shutdown clears the playback request")
    policy.interruptionBegan()
    policy.setRouteAvailable(false)
    policy.interruptionEnded(shouldResume: false)
    policy.requestStart()
    check(policy.shouldRun, "notifications after explicit stop cannot poison a fresh start")
}

@main
private enum GameLifecycleCheck {
    static func main() {
        normalLifecycleRoundTrip()
        staleCompletionCannotResume()
        suspensionAndFailureAreRetryable()
        presentationOwnershipTransfersDeterministically()
        bootActivationNeedsNoCompetingPreparation()
        stoppedSessionInvalidatesPreparation()
        controlsGuideSuspendsIdempotently()
        audioLifecycleOwnership()

        if failures == 0 {
            print("game lifecycle checks passed")
        } else {
            print("game lifecycle checks failed: \(failures)")
            Foundation.exit(1)
        }
    }
}
