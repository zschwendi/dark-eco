import simd

nonisolated struct VisionWindowStereoClipPlan: Sendable {
    struct View: Sendable {
        let viewID: UInt64
        let clipFromGameClip: simd_float4x4
    }

    let left: View
    let right: View
}

/// Builds a conservative fixed stereo pair from the one clip-space projection authored by Jak's
/// existing third-person camera. The Metal depth-zero plane remains the convergence plane, so the
/// game camera is never replaced or driven by the device, window, or viewer pose.
nonisolated enum VisionWindowStereoClipPlanner {
    static let leftViewID: UInt64 = 1
    static let rightViewID: UInt64 = 2
    static let defaultNormalizedFarPlaneSeparation: Float = 0.025
    static let maximumNormalizedFarPlaneSeparation: Float = 0.05

    static func makePlan(
        normalizedFarPlaneSeparation: Float = defaultNormalizedFarPlaneSeparation
    ) -> VisionWindowStereoClipPlan? {
        guard normalizedFarPlaneSeparation.isFinite,
              normalizedFarPlaneSeparation > 0,
              normalizedFarPlaneSeparation <= maximumNormalizedFarPlaneSeparation else {
            return nil
        }

        let halfSeparation = normalizedFarPlaneSeparation * 0.5
        let leftTransform = clipTransform(horizontalParallax: -halfSeparation)
        let rightTransform = clipTransform(horizontalParallax: halfSeparation)

        return VisionWindowStereoClipPlan(
            left: .init(viewID: leftViewID, clipFromGameClip: leftTransform),
            right: .init(viewID: rightViewID, clipFromGameClip: rightTransform)
        )
    }

    private static func clipTransform(horizontalParallax: Float) -> simd_float4x4 {
        var transform = matrix_identity_float4x4
        transform.columns.2.x = horizontalParallax
        return transform
    }
}
