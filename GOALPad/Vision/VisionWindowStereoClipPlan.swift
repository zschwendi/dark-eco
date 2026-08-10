import simd

nonisolated struct VisionWindowStereoClipPlan: Sendable {
    struct View: Sendable {
        let viewID: UInt64
        let clipFromGameClip: simd_float4x4
    }

    let left: View
    let right: View
}

/// Builds a fixed stereo pair from the one clip-space projection authored by Jak's existing
/// third-person camera. The transform is an explicit post-projection off-axis shift:
/// `x' = x + eyeSlope * (z - convergenceDepth * w)`. The defaults are the bounded physical
/// candidate; physical comfort and depth ordering still require acceptance on Vision Pro.
nonisolated enum VisionWindowStereoClipPlanner {
    static let leftViewID: UInt64 = 1
    static let rightViewID: UInt64 = 2
    static let defaultNormalizedDepthDisparitySlope: Float = 0.05
    static let maximumNormalizedDepthDisparitySlope: Float = 0.05
    static let defaultConvergenceDepth: Float = 0.05

    static func makePlan(
        normalizedDepthDisparitySlope: Float = defaultNormalizedDepthDisparitySlope,
        convergenceDepth: Float = defaultConvergenceDepth
    ) -> VisionWindowStereoClipPlan? {
        guard normalizedDepthDisparitySlope.isFinite,
              normalizedDepthDisparitySlope > 0,
              normalizedDepthDisparitySlope <= maximumNormalizedDepthDisparitySlope,
              convergenceDepth.isFinite,
              (0...1).contains(convergenceDepth) else {
            return nil
        }

        let halfSlope = normalizedDepthDisparitySlope * 0.5
        let leftTransform = clipTransform(eyeSlope: -halfSlope,
                                          convergenceDepth: convergenceDepth)
        let rightTransform = clipTransform(eyeSlope: halfSlope,
                                           convergenceDepth: convergenceDepth)

        return VisionWindowStereoClipPlan(
            left: .init(viewID: leftViewID, clipFromGameClip: leftTransform),
            right: .init(viewID: rightViewID, clipFromGameClip: rightTransform)
        )
    }

    private static func clipTransform(eyeSlope: Float,
                                      convergenceDepth: Float) -> simd_float4x4 {
        var transform = matrix_identity_float4x4
        transform.columns.2.x = eyeSlope
        transform.columns.3.x = -eyeSlope * convergenceDepth
        return transform
    }
}
