#if os(visionOS) && GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE
import Foundation

@MainActor
final class VisionImmersiveProofCoordinator {
    static let shared = VisionImmersiveProofCoordinator()

    func tickGame(attempt _: UInt64,
                  request _: VisionImmersiveFrameRequest) -> VisionImmersivePresentedFrame? {
        nil
    }

    func setImmersiveSceneActive(_: Bool, attempt _: UInt64) {}
    func presenterFailed(attempt _: UInt64, message _: String) {}
    func presentedFirstGameFrame(attempt _: UInt64) {}
    func presenterStopped(attempt _: UInt64, reason _: VisionImmersiveCloseReason) {}
}
#endif
