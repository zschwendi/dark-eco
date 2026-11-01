nonisolated(unsafe) private var failures = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("  ok   \(message)")
    } else {
        print("  FAIL \(message)")
        failures += 1
    }
}

private func stick(_ x: Float, _ y: Float) -> ControllerMenuStickSample {
    .init(x: x, y: y)
}

@main
private struct ControllerMenuNavigationCheck {
    static func main() {
        var navigation = ControllerMenuNavigation()
        check(navigation.update(primary: stick(0.54, 0), fallback: nil, enabled: true) == nil,
              "the press deadzone ignores a near-threshold stick")
        check(navigation.update(primary: stick(0.70, 0), fallback: nil, enabled: true) == .right,
              "a strong right push engages right")
        check(navigation.update(primary: stick(0.40, 0), fallback: nil, enabled: true) == .right,
              "release hysteresis retains a partially relaxed direction")
        check(navigation.update(primary: stick(0.34, 0), fallback: nil, enabled: true) == nil,
              "returning through the release threshold centers the D-pad")
        check(navigation.update(primary: stick(0.40, 0), fallback: nil, enabled: true) == nil,
              "a centered direction must cross the press threshold to reengage")
        check(navigation.update(primary: stick(.nan, 0), fallback: nil, enabled: true) == nil,
              "a non-finite stick fails centered")

        check(navigation.update(primary: stick(-0.80, 0), fallback: nil, enabled: true) == .left,
              "left engages after centering")
        check(navigation.update(primary: stick(0.80, 0), fallback: nil, enabled: true) == .right,
              "crossing directly to the opposite side resets to right immediately")

        navigation.reset()
        check(navigation.update(primary: stick(0.80, 0.80), fallback: nil, enabled: true) == .up,
              "an exact diagonal deterministically chooses the vertical axis")
        check(navigation.update(primary: stick(0.40, 0.41), fallback: nil, enabled: true) == .up,
              "axis hysteresis holds the chosen diagonal direction below press strength")
        check(navigation.update(primary: stick(0.70, 0.40), fallback: nil, enabled: true) == .right,
              "a newly strong dominant axis deliberately changes direction")

        navigation.reset()
        var heldEveryPoll = true
        for _ in 0..<120 {
            heldEveryPoll = heldEveryPoll
                && navigation.update(primary: stick(0, -0.75), fallback: nil,
                                     enabled: true) == .down
        }
        check(heldEveryPoll,
              "a held stick remains held for native PS2 menu repeat without queued pulses")
        check(navigation.update(primary: stick(0, -0.75), fallback: nil,
                                enabled: false) == nil,
              "leaving menu context clears the synthetic direction")
        check(navigation.update(primary: stick(0, -0.40), fallback: nil,
                                enabled: true) == nil,
              "re-entering a menu does not preserve stale hysteresis")

        navigation.reset()
        check(navigation.update(primary: stick(0.05, 0), fallback: stick(-0.72, 0),
                                enabled: true) == .left,
              "a deflected Sense fallback wins over a centered conventional controller")
        check(navigation.update(primary: stick(0.82, 0), fallback: stick(-0.72, 0),
                                enabled: true) == .right,
              "the stronger conventional-controller stick wins deterministically")

        if failures == 0 {
            print("controller menu navigation checks passed")
        } else {
            print("controller menu navigation checks failed: \(failures)")
            fatalError("controller menu navigation checks failed")
        }
    }
}
