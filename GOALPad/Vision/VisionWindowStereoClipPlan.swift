import simd

nonisolated struct VisionWindowStereoClipPlan: Sendable {
    struct View: Sendable {
        let viewID: UInt64
        let clipFromGameClip: simd_float4x4
    }

    let left: View
    let right: View
}

/// Converts the tracked eye positions relative to the game surface into post-projection shears.
/// The game projection's Metal depth-zero plane is treated as the window convergence plane, so
/// the resulting parallax is zero at the glass and increases only into the scene.
nonisolated enum VisionWindowStereoClipPlanner {
    static let leftViewID: UInt64 = 1
    static let rightViewID: UInt64 = 2

    static func makePlan(windowSizeMeters: SIMD2<Float>,
                         windowFromHead: simd_float4x4,
                         headFromEyes: [simd_float4x4] = nominalHeadFromEyes)
        -> VisionWindowStereoClipPlan? {
        guard windowSizeMeters.x.isFinite,
              windowSizeMeters.y.isFinite,
              windowSizeMeters.x > 0,
              windowSizeMeters.y > 0,
              matrixIsFinite(windowFromHead),
              headFromEyes.count == 2,
              headFromEyes.allSatisfy(matrixIsFinite) else {
            return nil
        }

        let leftEye = (windowFromHead * headFromEyes[0]).columns.3
        let rightEye = (windowFromHead * headFromEyes[1]).columns.3
        guard leftEye.x.isFinite, leftEye.y.isFinite, leftEye.z.isFinite,
              rightEye.x.isFinite, rightEye.y.isFinite, rightEye.z.isFinite,
              leftEye.z != 0, rightEye.z != 0 else {
            return nil
        }

        let leftTransform = clipTransform(
            eyePosition: leftEye,
            windowSizeMeters: windowSizeMeters
        )
        let rightTransform = clipTransform(
            eyePosition: rightEye,
            windowSizeMeters: windowSizeMeters
        )
        guard !matrixEqual(leftTransform, rightTransform) else { return nil }

        return VisionWindowStereoClipPlan(
            left: .init(viewID: leftViewID, clipFromGameClip: leftTransform),
            right: .init(viewID: rightViewID, clipFromGameClip: rightTransform)
        )
    }

    static let nominalHeadFromEyes: [simd_float4x4] = [
        translation(x: -0.0315, y: -0.0265, z: -0.034),
        translation(x: 0.0315, y: -0.0265, z: -0.034),
    ]

    private static func clipTransform(eyePosition: SIMD4<Float>,
                                      windowSizeMeters: SIMD2<Float>) -> simd_float4x4 {
        var transform = matrix_identity_float4x4
        transform.columns.2.x = 2 * eyePosition.x / windowSizeMeters.x
        transform.columns.2.y = 2 * eyePosition.y / windowSizeMeters.y
        return transform
    }

    private static func translation(x: Float, y: Float, z: Float) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(x, y, z, 1)
        ))
    }

    private static func matrixIsFinite(_ matrix: simd_float4x4) -> Bool {
        for column in 0..<4 {
            for row in 0..<4 where !matrix[column][row].isFinite {
                return false
            }
        }
        return true
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
}
