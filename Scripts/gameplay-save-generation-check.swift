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

@main
private struct GameplaySaveGenerationCheck {
    static func main() {
        var state = GameplaySaveGenerationState()
        check(!state.observe(0), "the reset native generation does not synthesize a save event")
        check(state.observe(1), "one changed generation produces one save event")
        check(!state.observe(1), "repeated frames at one generation produce no repeated event")
        check(state.observe(UInt64.max), "a later high generation remains observable")
        check(state.observe(0), "wrapped generation zero is detected by inequality")
        state.reset()
        check(state.observed == 0 && !state.observe(0),
              "session teardown clears the baseline without synthesizing an event")

        if failures == 0 {
            print("gameplay save-generation checks passed")
        } else {
            print("gameplay save-generation checks failed: \(failures)")
            Foundation.exit(1)
        }
    }
}
