import simd

@main
struct VisionWindowStereoClipPlanCheck {
    static func main() {
        checkFixedGameCameraPair()
        checkExplicitConvergenceMath()
        checkJakProjectionDisparityDiagnostic()
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

        checkDisparity(plan: plan, depth: 0,
                       expected: -VisionWindowStereoClipPlanner
                           .defaultNormalizedDepthDisparitySlope
                           * VisionWindowStereoClipPlanner.defaultConvergenceDepth,
                       "the default reversed-Z far plane disparity is incorrect")
        checkDisparity(plan: plan,
                       depth: VisionWindowStereoClipPlanner.defaultConvergenceDepth,
                       expected: 0,
                       "the default convergence depth did not converge")
        checkDisparity(plan: plan, depth: 1,
                       expected: VisionWindowStereoClipPlanner
                           .defaultNormalizedDepthDisparitySlope
                           * (1 - VisionWindowStereoClipPlanner.defaultConvergenceDepth),
                       "the default reversed-Z near plane disparity is incorrect")
    }

    private static func checkExplicitConvergenceMath() {
        let slope: Float = 0.04
        let convergenceDepth: Float = 0.25
        guard let plan = VisionWindowStereoClipPlanner.makePlan(
            normalizedDepthDisparitySlope: slope,
            convergenceDepth: convergenceDepth
        ) else {
            fail("the explicit convergence plan was rejected")
        }

        checkDisparity(plan: plan, depth: 0,
                       expected: -slope * convergenceDepth,
                       "the far endpoint did not use z - convergenceDepth * w")
        checkDisparity(plan: plan, depth: convergenceDepth, expected: 0,
                       "the explicit convergence depth did not converge")
        checkDisparity(plan: plan, depth: 1,
                       expected: slope * (1 - convergenceDepth),
                       "the near endpoint did not use z - convergenceDepth * w")
    }

    private static func checkJakProjectionDisparityDiagnostic() {
        // Jak 1's default math-camera maps 0.25 m to 10,000 m into the 24-bit reversed depth
        // interval [100, 16_760_631]. This one-meter sample is representative projection evidence,
        // not a physical stereo calibration.
        let near: Float = 1_024
        let far: Float = 40_960_000
        let oneMeter: Float = 4_096
        let depthMinimum: Float = 100
        let depthMaximum: Float = 16_760_631
        let metalDepthScale: Float = 16_777_216
        let oneMeterDepth = (
            depthMinimum
                + (depthMaximum - depthMinimum) * near
                    * (far / oneMeter - 1) / (far - near)
        ) / metalDepthScale

        check(close(oneMeterDepth, 0.2497386),
              "the one-meter Jak projection depth oracle drifted")
        let pixelDisparity = VisionWindowStereoClipPlanner
            .defaultNormalizedDepthDisparitySlope
            * (oneMeterDepth - VisionWindowStereoClipPlanner.defaultConvergenceDepth)
            * 640 / 2
        check(close(pixelDisparity, 3.1958177),
              "the 640-pixel default disparity diagnostic drifted")
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
            normalizedDepthDisparitySlope: 0
        ) == nil, "zero separation was accepted")
        check(VisionWindowStereoClipPlanner.makePlan(
            normalizedDepthDisparitySlope: -.infinity
        ) == nil, "non-finite separation was accepted")
        check(VisionWindowStereoClipPlanner.makePlan(
            normalizedDepthDisparitySlope:
                VisionWindowStereoClipPlanner.maximumNormalizedDepthDisparitySlope.nextUp
        ) == nil, "an excessive separation was accepted")
        check(VisionWindowStereoClipPlanner.makePlan(
            convergenceDepth: -Float.leastNonzeroMagnitude
        ) == nil, "a convergence depth below Metal's range was accepted")
        check(VisionWindowStereoClipPlanner.makePlan(
            convergenceDepth: Float(1).nextUp
        ) == nil, "a convergence depth above Metal's range was accepted")
        check(VisionWindowStereoClipPlanner.makePlan(
            convergenceDepth: .nan
        ) == nil, "a non-finite convergence depth was accepted")
    }

    private static func checkDisparity(plan: VisionWindowStereoClipPlan,
                                       depth: Float,
                                       expected: Float,
                                       _ message: String) {
        let point = SIMD4<Float>(0.2, -0.3, depth, 1)
        let left = plan.left.clipFromGameClip * point
        let right = plan.right.clipFromGameClip * point
        check(close(right.x / right.w - left.x / left.w, expected), message)
        check(left.y == point.y && right.y == point.y
                && left.z == point.z && right.z == point.z
                && left.w == point.w && right.w == point.w,
              "the stereo transform changed y, z, or w")
    }

    private static func close(_ lhs: Float, _ rhs: Float) -> Bool {
        abs(lhs - rhs) < 0.000001
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
