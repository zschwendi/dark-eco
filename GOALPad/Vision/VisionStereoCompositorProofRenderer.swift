#if os(visionOS)
import CompositorServices
import Foundation
import Metal

/// An isolated compositor contract proof. It clears separate compositor-provided textures for
/// each view; it never consumes or duplicates the game's completed window framebuffer.
final class VisionStereoCompositorProofRenderer: @unchecked Sendable {
    private let layerRenderer: LayerRenderer
    private let commandQueue: MTLCommandQueue
    private let coordinator: VisionPresentationCoordinator
    private var reportedStereoFrame = false

    private init?(_ layerRenderer: LayerRenderer,
                  coordinator: VisionPresentationCoordinator) {
        guard let commandQueue = layerRenderer.device.makeCommandQueue() else { return nil }
        self.layerRenderer = layerRenderer
        self.commandQueue = commandQueue
        self.coordinator = coordinator
    }

    @MainActor
    static func start(_ layerRenderer: LayerRenderer,
                      coordinator: VisionPresentationCoordinator) {
        guard let renderer = VisionStereoCompositorProofRenderer(
            layerRenderer,
            coordinator: coordinator
        ) else {
            coordinator.stereoProofFailed("Metal could not create a compositor command queue.")
            return
        }
        Task.detached(priority: .userInitiated) {
            renderer.renderLoop()
        }
    }

    private func renderLoop() {
        guard layerRenderer.configuration.layout == .dedicated else {
            reportFailure(
                "The compositor does not support the separate per-view textures required "
                    + "by this proof."
            )
            return
        }

        while true {
            switch layerRenderer.state {
            case .invalidated:
                Task { @MainActor in coordinator.stereoProofStopped() }
                return
            case .paused:
                layerRenderer.waitUntilRunning()
            default:
                autoreleasepool {
                    renderFrame()
                }
            }
        }
    }

    private func renderFrame() {
        guard let frame = layerRenderer.queryNextFrame() else { return }
        frame.startUpdate()
        frame.endUpdate()

        guard let timing = frame.predictTiming() else { return }
        LayerRenderer.Clock().wait(until: timing.optimalInputTime)

        let drawables = frame.queryDrawables()
        guard !drawables.isEmpty,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        frame.startSubmission()
        var maximumViewCount = 0
        for drawable in drawables {
            guard encode(drawable: drawable, commandBuffer: commandBuffer) else { continue }
            maximumViewCount = max(maximumViewCount, drawable.views.count)
        }
        commandBuffer.commit()
        frame.endSubmission()

        guard !reportedStereoFrame, maximumViewCount > 1 else { return }
        reportedStereoFrame = true
        Task { @MainActor in
            coordinator.stereoProofSubmitted(viewCount: maximumViewCount)
        }
    }

    private func encode(drawable: LayerRenderer.Drawable,
                        commandBuffer: MTLCommandBuffer) -> Bool {
        let textureIndices = drawable.views.map { $0.textureMap.textureIndex }
        guard textureIndices.count == Set(textureIndices).count else {
            reportFailure("The compositor did not provide a distinct texture for every view.")
            return false
        }

        for (viewIndex, textureIndex) in textureIndices.enumerated() {
            guard textureIndex < drawable.colorTextures.count,
                  textureIndex < drawable.depthTextures.count else {
                reportFailure("A compositor view referenced a missing color or depth texture.")
                return false
            }

            let descriptor = MTLRenderPassDescriptor()
            descriptor.colorAttachments[0].texture = drawable.colorTextures[textureIndex]
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].storeAction = .store
            descriptor.colorAttachments[0].clearColor = Self.clearColor(for: viewIndex)
            descriptor.depthAttachment.texture = drawable.depthTextures[textureIndex]
            descriptor.depthAttachment.loadAction = .clear
            descriptor.depthAttachment.storeAction = .store
            descriptor.depthAttachment.clearDepth = 0

            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
                reportFailure("Metal could not encode a compositor proof pass.")
                return false
            }
            encoder.label = "Eco Synthetic Stereo View \(viewIndex)"
            encoder.endEncoding()
        }

        drawable.encodePresent(commandBuffer: commandBuffer)
        return true
    }

    private static func clearColor(for viewIndex: Int) -> MTLClearColor {
        if viewIndex.isMultiple(of: 2) {
            return MTLClearColor(red: 0.03, green: 0.16, blue: 0.22, alpha: 1)
        }
        return MTLClearColor(red: 0.18, green: 0.04, blue: 0.16, alpha: 1)
    }

    private func reportFailure(_ message: String) {
        Task { @MainActor in coordinator.stereoProofFailed(message) }
    }
}
#endif
