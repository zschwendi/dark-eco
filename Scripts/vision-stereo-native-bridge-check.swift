#if os(visionOS)
import CoreGraphics
import Metal

@MainActor
private func checkStereoBridge(
    surface: GOALPadRenderSurface,
    commandBuffer: any MTLCommandBuffer,
    left: GOALPadStereoRenderTarget,
    right: GOALPadStereoRenderTarget
) {
    switch surface.reserveStereoFrame() {
    case .reserved, .busy, .failed:
        break
    @unknown default:
        break
    }

    _ = surface.beginReservedStereoFrame(
        at: 0,
        size: CGSize(width: 16, height: 16),
        commandBuffer: commandBuffer,
        left: left,
        right: right
    )
    surface.cancelReservedStereoFrame()
    surface.prepareStereoFallback()

    switch surface.endStereoFrame() {
    case .skipped, .submitted, .failed:
        break
    @unknown default:
        break
    }
}
#endif
