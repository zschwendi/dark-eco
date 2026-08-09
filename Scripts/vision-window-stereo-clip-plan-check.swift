import simd

@main
struct VisionWindowStereoClipPlanCheck {
    static func main() {
        checkFixedGameCameraPair()
        checkDeterministicPlan()
        checkInvalidInputsFailClosed()
        print("vision window stereo clip-plan checks passed")
    }

    private static func checkFixedGameCameraPair() {
        guard let plan = VisionWindowStereoClipPlanner.makePlan() else {
            fail("the fixed game-camera pair did not produce a plan")
        }

        check(plan.left.viewID != 0, "left view ID must be nonzero")
        check(plan.right.viewID != 0, "right view ID must be nonzero")
        check(plan.left.viewID != plan.right.viewID, "view IDs must be distinct")
        check(plan.left.clipFromGameClip.columns.2.x < 0,
              "the left game-camera view did not produce left parallax")
        check(plan.right.clipFromGameClip.columns.2.x > 0,
              "the right game-camera view did not produce right parallax")
        check(plan.left.clipFromGameClip.columns.2.x
                == -plan.right.clipFromGameClip.columns.2.x,
              "the fixed stereo pair is not symmetric")
        check(plan.left.clipFromGameClip.columns.2.y == 0
                && plan.right.clipFromGameClip.columns.2.y == 0,
              "the fixed pair introduced unrequested vertical parallax")

        let convergencePoint = SIMD4<Float>(0.2, -0.3, 0, 1)
        check(plan.left.clipFromGameClip * convergencePoint
                == plan.right.clipFromGameClip * convergencePoint,
              "the game camera's Metal depth-zero plane is not the convergence plane")
    }

    private static func checkDeterministicPlan() {
        guard let first = VisionWindowStereoClipPlanner.makePlan(),
              let second = VisionWindowStereoClipPlanner.makePlan() else {
            fail("repeated fixed plans failed")
        }
        check(matrixEqual(first.left.clipFromGameClip, second.left.clipFromGameClip)
                && matrixEqual(first.right.clipFromGameClip, second.right.clipFromGameClip),
              "the stereo pair changed without a game-camera change")
    }

    private static func checkInvalidInputsFailClosed() {
        check(VisionWindowStereoClipPlanner.makePlan(
            normalizedFarPlaneSeparation: 0
        ) == nil, "zero separation was accepted")
        check(VisionWindowStereoClipPlanner.makePlan(
            normalizedFarPlaneSeparation: -.infinity
        ) == nil, "non-finite separation was accepted")
        check(VisionWindowStereoClipPlanner.makePlan(
            normalizedFarPlaneSeparation:
                VisionWindowStereoClipPlanner.maximumNormalizedFarPlaneSeparation.nextUp
        ) == nil, "an excessive separation was accepted")
    }

    private static func matrixEqual(_ lhs: simd_float4x4,
                                    _ rhs: simd_float4x4) -> Bool {
        for column in 0..<4 {
            for row in 0..<4 where lhs[column][row] != rhs[column][row] {
                return false
            }
        }
        return true
    }

    private static func check(_ condition: @autoclosure () -> Bool,
                              _ message: String) {
        if !condition() { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        fatalError("vision window stereo clip-plan check failed: \(message)")
    }
}
