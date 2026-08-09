import simd

@main
struct VisionWindowStereoClipPlanCheck {
    static func main() {
        checkNominalEyes()
        checkHeadLeanChangesBothViews()
        checkInvalidInputsFailClosed()
        print("vision window stereo clip-plan checks passed")
    }

    private static func checkNominalEyes() {
        guard let plan = VisionWindowStereoClipPlanner.makePlan(
            windowSizeMeters: SIMD2(0.6, 0.45),
            windowFromHead: translation(x: 0, y: 0, z: -0.6)
        ) else {
            fail("nominal head pose did not produce a plan")
        }

        check(plan.left.viewID != 0, "left view ID must be nonzero")
        check(plan.right.viewID != 0, "right view ID must be nonzero")
        check(plan.left.viewID != plan.right.viewID, "view IDs must be distinct")
        check(plan.left.clipFromGameClip.columns.2.x < 0,
              "left eye did not produce left parallax")
        check(plan.right.clipFromGameClip.columns.2.x > 0,
              "right eye did not produce right parallax")
    }

    private static func checkHeadLeanChangesBothViews() {
        let centered = VisionWindowStereoClipPlanner.makePlan(
            windowSizeMeters: SIMD2(0.6, 0.45),
            windowFromHead: translation(x: 0, y: 0, z: -0.6)
        )
        let leaned = VisionWindowStereoClipPlanner.makePlan(
            windowSizeMeters: SIMD2(0.6, 0.45),
            windowFromHead: translation(x: 0.1, y: 0.05, z: -0.6)
        )
        guard let centered, let leaned else { fail("valid lean pose failed") }

        check(leaned.left.clipFromGameClip.columns.2.x
                > centered.left.clipFromGameClip.columns.2.x,
              "lateral lean did not move the left-eye view")
        check(leaned.right.clipFromGameClip.columns.2.x
                > centered.right.clipFromGameClip.columns.2.x,
              "lateral lean did not move the right-eye view")
        check(leaned.left.clipFromGameClip.columns.2.y
                > centered.left.clipFromGameClip.columns.2.y,
              "vertical lean did not move the left-eye view")
        check(leaned.right.clipFromGameClip.columns.2.y
                > centered.right.clipFromGameClip.columns.2.y,
              "vertical lean did not move the right-eye view")
    }

    private static func checkInvalidInputsFailClosed() {
        check(VisionWindowStereoClipPlanner.makePlan(
            windowSizeMeters: SIMD2(0, 0.45),
            windowFromHead: matrix_identity_float4x4
        ) == nil, "zero-width window was accepted")

        var nonfinite = matrix_identity_float4x4
        nonfinite.columns.0.x = .nan
        check(VisionWindowStereoClipPlanner.makePlan(
            windowSizeMeters: SIMD2(0.6, 0.45),
            windowFromHead: nonfinite
        ) == nil, "non-finite head pose was accepted")

        let coincidentEyes = [
            translation(x: 0, y: 0, z: -0.034),
            translation(x: 0, y: 0, z: -0.034),
        ]
        check(VisionWindowStereoClipPlanner.makePlan(
            windowSizeMeters: SIMD2(0.6, 0.45),
            windowFromHead: translation(x: 0, y: 0, z: -0.6),
            headFromEyes: coincidentEyes
        ) == nil, "coincident eye transforms were accepted")
    }

    private static func translation(x: Float, y: Float, z: Float) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(x, y, z, 1)
        ))
    }

    private static func check(_ condition: @autoclosure () -> Bool,
                              _ message: String) {
        if !condition() { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        fatalError("vision window stereo clip-plan check failed: \(message)")
    }
}
