import Foundation
import simd

nonisolated struct VisionStereoProofSnapshot: Sendable {
    let frameID: UInt64
    let modelTransform: simd_float4x4
}

nonisolated struct VisionStereoViewport: Hashable, Sendable {
    let originX: Double
    let originY: Double
    let width: Double
    let height: Double
    let nearDepth: Double
    let farDepth: Double
}

nonisolated struct VisionStereoViewInput: Sendable {
    let viewIndex: Int
    let targetIndex: Int
    let sliceIndex: Int
    let viewport: VisionStereoViewport
    let colorWidth: Int
    let colorHeight: Int
    let colorSliceCount: Int
    let depthWidth: Int
    let depthHeight: Int
    let depthSliceCount: Int
    let depthRange: SIMD2<Float>
    let worldFromView: simd_float4x4
    let projection: simd_float4x4
}

nonisolated struct VisionStereoDrawableInput: Sendable {
    let drawableIndex: Int
    let colorTargetCount: Int
    let depthTargetCount: Int
    let views: [VisionStereoViewInput]
}

nonisolated struct VisionStereoPlannedView: Sendable {
    let snapshotID: UInt64
    let viewIndex: Int
    let targetIndex: Int
    let sliceIndex: Int
    let viewport: VisionStereoViewport
    let viewMatrix: simd_float4x4
    let projection: simd_float4x4
    let viewProjection: simd_float4x4
}

nonisolated struct VisionStereoDrawablePlan: Sendable {
    let drawableIndex: Int
    let views: [VisionStereoPlannedView]
}

nonisolated struct VisionStereoFramePlan: Sendable {
    let snapshot: VisionStereoProofSnapshot
    let drawables: [VisionStereoDrawablePlan]
    let maximumViewCount: Int

    var provesStereo: Bool { maximumViewCount >= 2 }
}

nonisolated enum VisionStereoFramePlanner {
    static func makePlan(
        snapshotFactory: () -> VisionStereoProofSnapshot?,
        drawables: [VisionStereoDrawableInput]
    ) -> VisionStereoFramePlan? {
        guard !drawables.isEmpty,
              let snapshot = snapshotFactory(),
              snapshot.frameID > 0,
              matrixIsFinite(snapshot.modelTransform) else {
            return nil
        }

        var drawableIDs = Set<Int>()
        var drawablePlans: [VisionStereoDrawablePlan] = []
        var maximumViewCount = 0

        for drawable in drawables {
            guard drawable.drawableIndex >= 0,
                  drawableIDs.insert(drawable.drawableIndex).inserted,
                  drawable.colorTargetCount > 0,
                  drawable.depthTargetCount > 0,
                  !drawable.views.isEmpty else {
                return nil
            }

            var viewIDs = Set<Int>()
            var targetMappings = Set<TargetMapping>()
            var viewProjections = Set<[UInt32]>()
            var plannedViews: [VisionStereoPlannedView] = []

            for view in drawable.views {
                guard view.viewIndex >= 0,
                      viewIDs.insert(view.viewIndex).inserted,
                      view.targetIndex >= 0,
                      view.targetIndex < drawable.colorTargetCount,
                      view.targetIndex < drawable.depthTargetCount,
                      view.sliceIndex >= 0,
                      view.sliceIndex < view.colorSliceCount,
                      view.sliceIndex < view.depthSliceCount,
                      view.colorWidth == view.depthWidth,
                      view.colorHeight == view.depthHeight,
                      valid(viewport: view.viewport,
                            targetWidth: view.colorWidth,
                            targetHeight: view.colorHeight),
                      validReverseDepthRange(view.depthRange),
                      matrixIsFinite(view.worldFromView),
                      matrixIsFinite(view.projection) else {
                    return nil
                }

                let mapping = TargetMapping(
                    targetIndex: view.targetIndex,
                    sliceIndex: view.sliceIndex,
                    viewport: view.viewport
                )
                guard targetMappings.insert(mapping).inserted else { return nil }

                let viewMatrix = simd_inverse(view.worldFromView)
                let viewProjection = view.projection * viewMatrix
                guard matrixIsFinite(viewMatrix), matrixIsFinite(viewProjection) else {
                    return nil
                }
                viewProjections.insert(matrixSignature(viewProjection))
                plannedViews.append(VisionStereoPlannedView(
                    snapshotID: snapshot.frameID,
                    viewIndex: view.viewIndex,
                    targetIndex: view.targetIndex,
                    sliceIndex: view.sliceIndex,
                    viewport: view.viewport,
                    viewMatrix: viewMatrix,
                    projection: view.projection,
                    viewProjection: viewProjection
                ))
            }

            guard plannedViews.count < 2 || viewProjections.count > 1 else { return nil }
            maximumViewCount = max(maximumViewCount, plannedViews.count)
            drawablePlans.append(VisionStereoDrawablePlan(
                drawableIndex: drawable.drawableIndex,
                views: plannedViews
            ))
        }

        return VisionStereoFramePlan(
            snapshot: snapshot,
            drawables: drawablePlans,
            maximumViewCount: maximumViewCount
        )
    }

    private struct TargetMapping: Hashable {
        let targetIndex: Int
        let sliceIndex: Int
        let viewport: VisionStereoViewport
    }

    private static func valid(viewport: VisionStereoViewport,
                              targetWidth: Int,
                              targetHeight: Int) -> Bool {
        guard targetWidth > 0,
              targetHeight > 0,
              viewport.originX.isFinite,
              viewport.originY.isFinite,
              viewport.width.isFinite,
              viewport.height.isFinite,
              viewport.nearDepth.isFinite,
              viewport.farDepth.isFinite,
              viewport.originX >= 0,
              viewport.originY >= 0,
              viewport.width > 0,
              viewport.height > 0,
              viewport.originX + viewport.width <= Double(targetWidth),
              viewport.originY + viewport.height <= Double(targetHeight),
              viewport.nearDepth >= 0,
              viewport.farDepth <= 1,
              viewport.nearDepth <= viewport.farDepth else {
            return false
        }
        return true
    }

    private static func validReverseDepthRange(_ range: SIMD2<Float>) -> Bool {
        range.x.isFinite && range.y.isFinite && range.x > range.y && range.y > 0
    }

    private static func matrixIsFinite(_ matrix: simd_float4x4) -> Bool {
        for column in 0..<4 {
            for row in 0..<4 where !matrix[column][row].isFinite {
                return false
            }
        }
        return true
    }

    private static func matrixSignature(_ matrix: simd_float4x4) -> [UInt32] {
        (0..<4).flatMap { column in
            (0..<4).map { row in matrix[column][row].bitPattern }
        }
    }
}
