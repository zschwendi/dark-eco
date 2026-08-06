import Foundation
import simd

@main
struct VisionStereoFramePlanCheck {
    private static let viewport = VisionStereoViewport(
        originX: 0,
        originY: 0,
        width: 1_024,
        height: 768,
        nearDepth: 0,
        farDepth: 1
    )

    static func main() {
        checkValidSharedTextureSlices()
        checkSingleViewIsNotStereoProof()
        checkInvalidInputsFailClosed()
        print("vision stereo frame-plan checks passed")
    }

    private static func checkValidSharedTextureSlices() {
        var snapshotFactoryCalls = 0
        let left = makeView(viewIndex: 0, sliceIndex: 0, eyeX: -0.032)
        let right = makeView(viewIndex: 1, sliceIndex: 1, eyeX: 0.032)
        let input = makeDrawable(views: [left, right])

        let plan = VisionStereoFramePlanner.makePlan(
            snapshotFactory: {
                snapshotFactoryCalls += 1
                return VisionStereoProofSnapshot(
                    frameID: 42,
                    modelTransform: translation(x: 0, y: 0.1, z: -2)
                )
            },
            drawables: [input]
        )

        check(snapshotFactoryCalls == 1, "one compositor frame must create one snapshot")
        guard let plan else { fail("valid stereo input did not produce a frame plan") }
        check(plan.provesStereo, "two distinct planned views must prove stereo")
        check(plan.maximumViewCount == 2, "planned stereo view count was not retained")
        check(plan.snapshot.frameID == 42, "snapshot identity changed during planning")
        check(plan.drawables.count == 1, "drawable count changed during planning")
        let plannedViews = plan.drawables[0].views
        check(plannedViews.map(\.viewIndex) == [0, 1], "view order changed during planning")
        check(plannedViews.map(\.snapshotID) == [42, 42], "views did not share one snapshot")
        check(plannedViews.map(\.targetIndex) == [0, 0],
              "dedicated layout must allow one texture index with distinct slices")
        check(plannedViews.map(\.sliceIndex) == [0, 1], "texture slices were not retained")
        check(plannedViews.allSatisfy { $0.viewport == viewport },
              "per-view viewport mapping changed during planning")
        check(!matrixEqual(plannedViews[0].viewProjection, plannedViews[1].viewProjection),
              "distinct eye transforms collapsed to one view-projection")
    }

    private static func checkSingleViewIsNotStereoProof() {
        let plan = VisionStereoFramePlanner.makePlan(
            snapshotFactory: {
                VisionStereoProofSnapshot(frameID: 1, modelTransform: matrix_identity_float4x4)
            },
            drawables: [makeDrawable(views: [makeView(viewIndex: 0, sliceIndex: 0)])]
        )
        guard let plan else { fail("one valid compositor view should remain renderable") }
        check(!plan.provesStereo, "one view must never be reported as stereo proof")
        check(plan.maximumViewCount == 1, "one-view count was not retained")
    }

    private static func checkInvalidInputsFailClosed() {
        checkInvalid([], "empty drawable set")
        checkInvalid([makeDrawable(views: [])], "empty view set")
        checkInvalid([
            makeDrawable(views: [
                makeView(viewIndex: 0, sliceIndex: 0, eyeX: -0.032),
                makeView(viewIndex: 1, sliceIndex: 0, eyeX: 0.032),
            ])
        ], "duplicate target, slice, and viewport mapping")
        checkInvalid([
            makeDrawable(views: [
                makeView(viewIndex: 0, sliceIndex: 0),
                makeView(viewIndex: 1, sliceIndex: 1),
            ])
        ], "two identical view-projections")
        checkInvalid([
            makeDrawable(views: [makeView(viewIndex: 0, targetIndex: 1, sliceIndex: 0)])
        ], "out-of-bounds texture index")
        checkInvalid([
            makeDrawable(views: [makeView(viewIndex: 0, sliceIndex: 2)])
        ], "out-of-bounds texture slice")
        checkInvalid([
            makeDrawable(views: [makeView(
                viewIndex: 0,
                sliceIndex: 0,
                viewport: VisionStereoViewport(
                    originX: 0,
                    originY: 0,
                    width: .infinity,
                    height: 768,
                    nearDepth: 0,
                    farDepth: 1
                )
            )])
        ], "non-finite viewport")
        checkInvalid([
            makeDrawable(views: [makeView(
                viewIndex: 0,
                sliceIndex: 0,
                depthRange: SIMD2<Float>(0.1, 100)
            )])
        ], "forward depth range")

        var nonfinite = matrix_identity_float4x4
        nonfinite.columns.0.x = .nan
        checkInvalid([
            makeDrawable(views: [makeView(
                viewIndex: 0,
                sliceIndex: 0,
                worldFromView: nonfinite
            )])
        ], "non-finite view transform")

        var snapshotCalls = 0
        let invalidSnapshot = VisionStereoFramePlanner.makePlan(
            snapshotFactory: {
                snapshotCalls += 1
                return VisionStereoProofSnapshot(frameID: 0, modelTransform: matrix_identity_float4x4)
            },
            drawables: [makeDrawable(views: [makeView(viewIndex: 0, sliceIndex: 0)])]
        )
        check(invalidSnapshot == nil, "zero snapshot identity must fail closed")
        check(snapshotCalls == 1, "snapshot factory must not be retried")
    }

    private static func checkInvalid(_ drawables: [VisionStereoDrawableInput],
                                     _ description: String) {
        let plan = VisionStereoFramePlanner.makePlan(
            snapshotFactory: {
                VisionStereoProofSnapshot(frameID: 7, modelTransform: matrix_identity_float4x4)
            },
            drawables: drawables
        )
        check(plan == nil, "planner accepted \(description)")
    }

    private static func makeDrawable(views: [VisionStereoViewInput])
        -> VisionStereoDrawableInput {
        VisionStereoDrawableInput(
            drawableIndex: 0,
            colorTargetCount: 1,
            depthTargetCount: 1,
            views: views
        )
    }

    private static func makeView(viewIndex: Int,
                                 targetIndex: Int = 0,
                                 sliceIndex: Int,
                                 eyeX: Float = 0,
                                 viewport: VisionStereoViewport = viewport,
                                 depthRange: SIMD2<Float> = SIMD2<Float>(100, 0.1),
                                 worldFromView: simd_float4x4? = nil)
        -> VisionStereoViewInput {
        VisionStereoViewInput(
            viewIndex: viewIndex,
            targetIndex: targetIndex,
            sliceIndex: sliceIndex,
            viewport: viewport,
            colorWidth: 1_024,
            colorHeight: 768,
            colorSliceCount: 2,
            depthWidth: 1_024,
            depthHeight: 768,
            depthSliceCount: 2,
            depthRange: depthRange,
            worldFromView: worldFromView ?? translation(x: eyeX, y: 0, z: 0),
            projection: matrix_identity_float4x4
        )
    }

    private static func translation(x: Float, y: Float, z: Float) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(x, y, z, 1)
        ))
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
        fatalError("vision stereo frame-plan check failed: \(message)")
    }
}
