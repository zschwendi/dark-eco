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
    check(generation(from: state.transition(to: .active, prepareOnActivation: true))
            == retryGeneration,
          "an explicit repeated activation can retry the same active generation")
    check(state.completePreparation(generation: retryGeneration, succeeded: true) == .resumed,
          "the retry can safely resume")
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
}

@main
private enum GameLifecycleCheck {
    static func main() {
        normalLifecycleRoundTrip()
        staleCompletionCannotResume()
        suspensionAndFailureAreRetryable()
        bootActivationNeedsNoCompetingPreparation()
        audioLifecycleOwnership()

        if failures == 0 {
            print("game lifecycle checks passed")
        } else {
            print("game lifecycle checks failed: \(failures)")
            Foundation.exit(1)
        }
    }
}
