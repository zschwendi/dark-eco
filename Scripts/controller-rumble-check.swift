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
private struct ControllerRumbleCheck {
    static func main() {
        let standard = ControllerRumblePolicy.standard
        let dualSense = ControllerRumblePolicy.dualSenseHandles
        check(standard.largeIntensity(0) == 0 && standard.largeIntensity(1) == 1
                && dualSense.largeIntensity(255) == 1,
              "the PS2 large motor remains an on/off channel")
        check(standard.smallIntensity(127) == Float(127) / 255
                && standard.smallIntensity(255) == 1,
              "ordinary controllers retain their existing analog-motor scale")
        check(dualSense.smallIntensity(0) == 0
                && dualSense.smallIntensity(1) == Float(2) / 255
                && dualSense.smallIntensity(127) == Float(254) / 255
                && dualSense.smallIntensity(128) == 1
                && dualSense.smallIntensity(255) == 1,
              "DualSense analog rumble is amplified twofold and clamped")
        check(dualSense.largeMotorSharpness == 0 && dualSense.smallMotorSharpness == 1,
              "DualSense left and right handles use distinct low and sharp responses")
        check(dualSense.preservesFinitePulseTail && !standard.preservesFinitePulseTail,
              "finite-pulse tail preservation is scoped to DualSense handles")

        func decision(_ previous: (UInt8, UInt8), _ next: (UInt8, UInt8))
            -> ControllerRumbleFrameDecision {
            ControllerRumbleFrameDecision(
                previousLarge: previous.0, previousSmall: previous.1,
                nextLarge: next.0, nextSmall: next.1)
        }
        check(decision((0, 0), (0, 0)) == .init(
                previousLarge: 0, previousSmall: 0, nextLarge: 0, nextSmall: 0)
                && !decision((0, 0), (0, 0)).publishesChange
                && !decision((0, 0), (0, 0)).refreshesController,
              "repeated silence performs no observable or haptic work")
        check(decision((0, 0), (1, 127)).publishesChange
                && decision((0, 0), (1, 127)).refreshesController
                && !decision((1, 127), (1, 127)).publishesChange
                && decision((1, 127), (1, 127)).refreshesController,
              "rumble starts publish once while sustained finite pulses still refresh")
        check(decision((1, 127), (0, 0)).publishesChange
                && decision((1, 127), (0, 0)).refreshesController,
              "the first zero transition still silences ordinary controllers")

        guard CommandLine.arguments.count == 2,
              let source = try? String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        else {
            print("usage: controller-rumble-check <ControllerInput.swift>")
            Foundation.exit(2)
        }
        check(source.contains("ControllerRumble(controller: candidate, isDualSense: isDualSense)"),
              "the public DualSense profile selects the tuned policy")
        check(source.components(separatedBy: "preservesFinitePulseTail: isDualSense").count - 1 == 2
                && source.contains("policy = isDualSense ? .dualSenseHandles : .standard")
                && source.contains("preservesFinitePulseTail: false"),
              "DualSense tuning requires two handle localities and fallback stays standard")
        check(source.contains("motors?.silence()")
                && source.contains("if preservesFinitePulseTail")
                && source.contains("func silence()"),
              "explicit cancellation remains immediate while DualSense event tails may finish")
        check(source.contains("let intensityChanged = playerIntensity.map")
                && source.contains("if intensityChanged {")
                && source.contains("try player?.start(atTime: CHHapticTimeImmediate)"),
              "unchanged finite rumble refreshes reuse their standard haptic player")
        check(source.contains("func applyRumble() {\n        guard isRumbleEnabled else { return }")
                && source.contains("let next = GOALPadInputRumble(Self.primaryPort)")
                && source.contains("if decision.publishesChange {")
                && source.contains("if decision.refreshesController {"),
              "disabled rumble skips all per-frame native and haptic bookkeeping")

        if failures == 0 {
            print("controller rumble checks passed")
        } else {
            print("controller rumble checks failed: \(failures)")
            Foundation.exit(1)
        }
    }
}
