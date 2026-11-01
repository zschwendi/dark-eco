#if GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE
import simd

/// Where one compositor view draws inside its drawable's textures.
nonisolated struct VisionImmersiveViewport: Equatable, Sendable {
    let originX: Double
    let originY: Double
    let width: Double
    let height: Double
    let nearDepth: Double
    let farDepth: Double
}

nonisolated struct VisionImmersiveViewMapping: Equatable, Sendable {
    let textureIndex: Int
    let sliceIndex: Int
    let viewport: VisionImmersiveViewport
}

nonisolated struct VisionImmersiveTargetShape: Equatable, Sendable {
    let width: Int
    let height: Int
    /// 1 for a 2D texture; the array length for a layered texture.
    let sliceCount: Int
}

/// One render pass over a single texture slice. Every view sharing that slice is drawn inside the
/// same pass, so its clear cannot erase a neighbouring view of a shared layout.
nonisolated struct VisionImmersivePass: Equatable, Sendable {
    let textureIndex: Int
    let sliceIndex: Int
    let viewIndices: [Int]
}

nonisolated enum VisionImmersivePassPlanner {
    /// Nil when any view names a missing texture or slice, leaves its target, overlaps another
    /// view, or when the color and depth textures do not pair up exactly.
    static func passes(views: [VisionImmersiveViewMapping],
                       colorTargets: [VisionImmersiveTargetShape],
                       depthTargets: [VisionImmersiveTargetShape]) -> [VisionImmersivePass]? {
        guard !views.isEmpty, !colorTargets.isEmpty, colorTargets == depthTargets else {
            return nil
        }
        var passes: [VisionImmersivePass] = []
        for (viewIndex, view) in views.enumerated() {
            guard colorTargets.indices.contains(view.textureIndex) else { return nil }
            let target = colorTargets[view.textureIndex]
            guard (0..<target.sliceCount).contains(view.sliceIndex),
                  fits(view.viewport, in: target) else { return nil }

            if let passIndex = passes.firstIndex(where: {
                $0.textureIndex == view.textureIndex && $0.sliceIndex == view.sliceIndex
            }) {
                let pass = passes[passIndex]
                guard pass.viewIndices.allSatisfy({
                    !overlaps(views[$0].viewport, view.viewport)
                }) else { return nil }
                passes[passIndex] = VisionImmersivePass(
                    textureIndex: pass.textureIndex,
                    sliceIndex: pass.sliceIndex,
                    viewIndices: pass.viewIndices + [viewIndex]
                )
            } else {
                passes.append(VisionImmersivePass(
                    textureIndex: view.textureIndex,
                    sliceIndex: view.sliceIndex,
                    viewIndices: [viewIndex]
                ))
            }
        }
        return passes
    }

    private static func fits(_ viewport: VisionImmersiveViewport,
                             in target: VisionImmersiveTargetShape) -> Bool {
        let values = [viewport.originX, viewport.originY, viewport.width, viewport.height,
                      viewport.nearDepth, viewport.farDepth]
        guard values.allSatisfy(\.isFinite), target.width > 0, target.height > 0 else {
            return false
        }
        return viewport.originX >= 0 && viewport.originY >= 0
            && viewport.width > 0 && viewport.height > 0
            && viewport.originX + viewport.width <= Double(target.width)
            && viewport.originY + viewport.height <= Double(target.height)
            && (0...1).contains(viewport.nearDepth) && (0...1).contains(viewport.farDepth)
    }

    private static func overlaps(_ a: VisionImmersiveViewport,
                                 _ b: VisionImmersiveViewport) -> Bool {
        a.originX < b.originX + b.width && b.originX < a.originX + a.width
            && a.originY < b.originY + b.height && b.originY < a.originY + a.height
    }
}

/// Common geometry and depth policy for resolving already-rendered per-eye game targets into the
/// compositor's dedicated, layered, or shared textures.
nonisolated enum VisionImmersiveResolve {
    /// The compositor has historically treated exact zero as both reverse-Z far and empty depth.
    /// Preserve real native depth everywhere else while nudging only an exact far-sky sample to a
    /// tiny positive value so it remains unambiguous to reprojection.
    static let minimumReverseZDepth: Float = 1.0 / 1_048_576.0

    static let clipFromQuad = simd_float4x4(columns: (
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(0, 0, 1, 0),
        SIMD4<Float>(0, 0, 0, 1)
    ))
}

/// Broadens culling slightly beyond the two requested eye frusta. This prevents either eye from
/// losing edge geometry without changing either eye's actual projection.
nonisolated enum VisionImmersiveBinocularCullPolicy {
    static let increaseTangents = SIMD4<Float>(repeating: 0.02)

    static func broaderDepthRange(than defaultRange: SIMD2<Float>) -> SIMD2<Float> {
        guard defaultRange.x.isFinite, defaultRange.y.isFinite,
              defaultRange.x > 0, defaultRange.y > 0 else {
            return SIMD2<Float>(500, 0.05)
        }
        // The compositor configuration uses reverse-Z ordering: far, then near.
        let far = max(defaultRange.x * 4, 500)
        let near = max(min(defaultRange.y * 0.5, 0.05), 0.005)
        return SIMD2<Float>(far, near)
    }
}

/// Kept only so the previous deterministic plan check remains source-compatible while integration
/// transitions to the per-eye resolve. Production presentation uses `VisionImmersiveResolve` and
/// samples each eye's native depth rather than this clear boundary.
nonisolated enum VisionImmersiveFullViewport {
    static let farDepth: Float = 0
    static let clipFromQuad = VisionImmersiveResolve.clipFromQuad
}

/// Schedules game ticks at the session's rate inside a faster compositor cadence. Each scheduled
/// time lies on that rate's grid, so the native display clock sees the steps a display link at
/// the game's rate would deliver, including the catch-up step after a dropped compositor frame.
nonisolated struct VisionImmersiveTickCadence: Sendable {
    static let discontinuitySeconds = 0.25

    private var framesPerSecond = 0
    private var lastPresentationTime: Double?
    private var nextScheduledTime: Double?

    mutating func scheduledTime(for presentationTime: Double, framesPerSecond: Int) -> Double? {
        guard presentationTime.isFinite, framesPerSecond > 0 else {
            reset()
            return nil
        }
        if framesPerSecond != self.framesPerSecond {
            reset()
            self.framesPerSecond = framesPerSecond
        }
        let interval = 1 / Double(framesPerSecond)
        defer { lastPresentationTime = presentationTime }

        guard let lastPresentationTime, let nextScheduledTime,
              presentationTime >= lastPresentationTime,
              presentationTime - lastPresentationTime <= Self.discontinuitySeconds else {
            nextScheduledTime = presentationTime + interval
            return presentationTime
        }
        // A quarter interval absorbs timestamp jitter without ticking a whole frame early.
        let dueTime = presentationTime + interval / 4
        guard dueTime >= nextScheduledTime else { return nil }
        let missed = ((dueTime - nextScheduledTime) / interval).rounded(.down)
        let scheduled = nextScheduledTime + missed * interval
        self.nextScheduledTime = scheduled + interval
        return scheduled
    }

    mutating func reset() {
        lastPresentationTime = nil
        nextScheduledTime = nil
    }
}
#endif
