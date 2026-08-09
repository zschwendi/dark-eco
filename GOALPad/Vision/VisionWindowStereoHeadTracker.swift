#if os(visionOS)
import ARKit
import QuartzCore
import RealityKit
import simd

/// Supplies a predicted head pose in the bounded window surface's coordinate system. The empty
/// mixed ImmersiveSpace exists only because ARKit world tracking is unavailable to a lone window.
@MainActor
final class VisionWindowStereoHeadTracker {
    private let session = ARKitSession()
    private let worldTracking = WorldTrackingProvider()
    private let failureHandler: (String) -> Void
    private var startTask: Task<Void, Never>?
    private var isRunning = false

    init(failureHandler: @escaping (String) -> Void) {
        self.failureHandler = failureHandler
    }

    func start() {
        guard startTask == nil, !isRunning else { return }
        guard WorldTrackingProvider.isSupported else {
            failureHandler("Head tracking is unavailable, so Eco returned to Comfort mode.")
            return
        }

        startTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await session.run([worldTracking])
                guard !Task.isCancelled else {
                    startTask = nil
                    return
                }
                isRunning = true
            } catch {
                if !Task.isCancelled {
                    failureHandler(
                        "Head tracking could not start, so Eco returned to Comfort mode: "
                            + error.localizedDescription
                    )
                }
            }
            startTask = nil
        }
    }

    func stop() {
        startTask?.cancel()
        startTask = nil
        isRunning = false
    }

    func windowFromHead(surfaceEntity: Entity,
                        targetPresentationTime: CFTimeInterval) -> simd_float4x4? {
        guard isRunning,
              let immersiveFromWindow = surfaceEntity.transformMatrix(relativeTo: .immersiveSpace)
        else {
            return nil
        }

        let predictedTime = max(targetPresentationTime, CACurrentMediaTime() + 0.033)
        guard let anchor = worldTracking.queryDeviceAnchor(atTimestamp: predictedTime)
                ?? worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else {
            return nil
        }

        return simd_inverse(immersiveFromWindow) * anchor.originFromAnchorTransform
    }
}
#endif
