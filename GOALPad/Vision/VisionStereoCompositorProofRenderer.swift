#if os(visionOS)
import ARKit
import CompositorServices
import Foundation
import Metal
import simd

/// An isolated compositor contract proof. It renders one immutable synthetic scene snapshot from
/// each compositor view into that view's own color and depth mapping. It never consumes or
/// duplicates the game's completed window framebuffer.
final class VisionStereoCompositorProofRenderer: @unchecked Sendable {
    private struct ProofVertex {
        let position: SIMD3<Float>
        let color: SIMD3<Float>
    }

    private struct ProofUniforms {
        let model: simd_float4x4
        let viewProjection: simd_float4x4
    }

    private enum FrameResult {
        case skipped
        case submitted(viewCount: Int)
        case failed(String)
    }

    private let layerRenderer: LayerRenderer
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let vertexBuffer: MTLBuffer
    private let vertexCount: Int
    private let coordinator: VisionPresentationCoordinator
    private let trackingSession = ARKitSession()
    private let worldTracking = WorldTrackingProvider()

    // The detached render loop below is the only code that touches these values or queries the
    // provider. Keeping one serial owner is required because device-anchor queries are not
    // thread-safe.
    private var nextSnapshotID: UInt64 = 0
    private var reportedStereoFrame = false

    private init?(_ layerRenderer: LayerRenderer,
                  coordinator: VisionPresentationCoordinator) {
        let device = layerRenderer.device
        guard let commandQueue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "vision_stereo_proof_vertex"),
              let fragmentFunction = library.makeFunction(name: "vision_stereo_proof_fragment") else {
            return nil
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "Eco Synthetic Stereo Geometry"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = layerRenderer.configuration.colorFormat
        pipelineDescriptor.depthAttachmentPixelFormat = layerRenderer.configuration.depthFormat
        guard let pipelineState = try? device.makeRenderPipelineState(
            descriptor: pipelineDescriptor
        ) else {
            return nil
        }

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .greater
        depthDescriptor.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: depthDescriptor) else {
            return nil
        }

        let vertices = Self.proofVertices
        guard let vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<ProofVertex>.stride * vertices.count,
            options: .storageModeShared
        ) else {
            return nil
        }
        vertexBuffer.label = "Eco Synthetic Stereo Geometry"

        self.layerRenderer = layerRenderer
        self.commandQueue = commandQueue
        self.pipelineState = pipelineState
        self.depthState = depthState
        self.vertexBuffer = vertexBuffer
        self.vertexCount = vertices.count
        self.coordinator = coordinator
    }

    @MainActor
    static func start(_ layerRenderer: LayerRenderer,
                      coordinator: VisionPresentationCoordinator) {
        guard let renderer = VisionStereoCompositorProofRenderer(
            layerRenderer,
            coordinator: coordinator
        ) else {
            coordinator.stereoProofFailed(
                "Metal could not initialize the synthetic stereo geometry proof."
            )
            return
        }
        Task.detached(priority: .userInitiated) {
            await renderer.renderLoop()
        }
    }

    private func renderLoop() async {
        guard layerRenderer.configuration.layout == .dedicated else {
            reportFailure(
                "The compositor does not support the dedicated per-view mappings required "
                    + "by this proof."
            )
            return
        }

        do {
            try await trackingSession.run([worldTracking])
        } catch {
            reportFailure("visionOS world tracking could not start for the stereo proof.")
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
                let result = autoreleasepool { renderFrame() }
                switch result {
                case .skipped:
                    continue
                case .submitted(let viewCount):
                    guard !reportedStereoFrame, viewCount > 1 else { continue }
                    reportedStereoFrame = true
                    Task { @MainActor in
                        coordinator.stereoProofSubmitted(viewCount: viewCount)
                    }
                case .failed(let message):
                    reportFailure(message)
                    return
                }
            }
        }
    }

    private func renderFrame() -> FrameResult {
        guard let frame = layerRenderer.queryNextFrame() else { return .skipped }
        frame.startUpdate()
        frame.endUpdate()

        guard let timing = frame.predictTiming() else { return .skipped }
        LayerRenderer.Clock().wait(until: timing.optimalInputTime)

        let drawables = frame.queryDrawables()
        guard !drawables.isEmpty,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return .skipped
        }

        var drawableInputs: [VisionStereoDrawableInput] = []
        for (drawableIndex, drawable) in drawables.enumerated() {
            guard let deviceAnchor = worldTracking.queryDeviceAnchor(
                atTimestamp: drawable.frameTiming.presentationTime.goalpadTimeInterval
            ), deviceAnchor.isTracked else {
                return .skipped
            }
            drawable.deviceAnchor = deviceAnchor

            guard let input = makeInput(
                drawable: drawable,
                drawableIndex: drawableIndex,
                worldFromDevice: deviceAnchor.originFromAnchorTransform
            ) else {
                return .failed("The compositor provided an invalid stereo view or target mapping.")
            }
            drawableInputs.append(input)
        }

        guard let plan = VisionStereoFramePlanner.makePlan(
            snapshotFactory: makeSnapshot,
            drawables: drawableInputs
        ) else {
            return .failed(
                "The compositor stereo frame failed immutable snapshot or per-view validation."
            )
        }

        frame.startSubmission()
        for drawablePlan in plan.drawables {
            guard drawablePlan.drawableIndex < drawables.count else {
                frame.endSubmission()
                return .failed("The validated compositor drawable mapping became stale.")
            }
            let drawable = drawables[drawablePlan.drawableIndex]
            for view in drawablePlan.views {
                guard encode(
                    snapshot: plan.snapshot,
                    view: view,
                    drawable: drawable,
                    commandBuffer: commandBuffer
                ) else {
                    frame.endSubmission()
                    return .failed("Metal could not encode a validated stereo geometry view.")
                }
            }
            drawable.encodePresent(commandBuffer: commandBuffer)
        }
        commandBuffer.commit()
        frame.endSubmission()
        return .submitted(viewCount: plan.maximumViewCount)
    }

    private func makeInput(drawable: LayerRenderer.Drawable,
                           drawableIndex: Int,
                           worldFromDevice: simd_float4x4) -> VisionStereoDrawableInput? {
        var inputs: [VisionStereoViewInput] = []
        for (viewIndex, view) in drawable.views.enumerated() {
            let mapping = view.textureMap
            guard mapping.textureIndex < drawable.colorTextures.count,
                  mapping.textureIndex < drawable.depthTextures.count else {
                return nil
            }
            let color = drawable.colorTextures[mapping.textureIndex]
            let depth = drawable.depthTextures[mapping.textureIndex]
            let viewport = mapping.viewport
            inputs.append(VisionStereoViewInput(
                viewIndex: viewIndex,
                targetIndex: mapping.textureIndex,
                sliceIndex: mapping.sliceIndex,
                viewport: VisionStereoViewport(
                    originX: viewport.originX,
                    originY: viewport.originY,
                    width: viewport.width,
                    height: viewport.height,
                    nearDepth: viewport.znear,
                    farDepth: viewport.zfar
                ),
                colorWidth: color.width,
                colorHeight: color.height,
                colorSliceCount: color.arrayLength,
                depthWidth: depth.width,
                depthHeight: depth.height,
                depthSliceCount: depth.arrayLength,
                depthRange: drawable.depthRange,
                worldFromView: worldFromDevice * view.transform,
                projection: drawable.computeProjection(
                    convention: .rightUpBack,
                    viewIndex: viewIndex
                )
            ))
        }
        return VisionStereoDrawableInput(
            drawableIndex: drawableIndex,
            colorTargetCount: drawable.colorTextures.count,
            depthTargetCount: drawable.depthTextures.count,
            views: inputs
        )
    }

    private func makeSnapshot() -> VisionStereoProofSnapshot? {
        nextSnapshotID &+= 1
        guard nextSnapshotID != 0 else { return nil }
        let angle = Float(nextSnapshotID % 1_800) * (.pi / 900)
        let model = Self.translation(x: 0, y: 0, z: -2)
            * Self.rotationY(angle)
            * Self.rotationX(-0.28)
        return VisionStereoProofSnapshot(frameID: nextSnapshotID, modelTransform: model)
    }

    private func encode(snapshot: VisionStereoProofSnapshot,
                        view: VisionStereoPlannedView,
                        drawable: LayerRenderer.Drawable,
                        commandBuffer: MTLCommandBuffer) -> Bool {
        guard view.targetIndex < drawable.colorTextures.count,
              view.targetIndex < drawable.depthTextures.count else {
            return false
        }
        let color = drawable.colorTextures[view.targetIndex]
        let depth = drawable.depthTextures[view.targetIndex]
        guard color.pixelFormat == layerRenderer.configuration.colorFormat,
              depth.pixelFormat == layerRenderer.configuration.depthFormat else {
            return false
        }

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = color
        descriptor.colorAttachments[0].slice = view.sliceIndex
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: 0.025,
            green: 0.045,
            blue: 0.07,
            alpha: 1
        )
        descriptor.depthAttachment.texture = depth
        descriptor.depthAttachment.slice = view.sliceIndex
        descriptor.depthAttachment.loadAction = .clear
        descriptor.depthAttachment.storeAction = .store
        descriptor.depthAttachment.clearDepth = 0

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return false
        }
        encoder.label = "Eco Synthetic Stereo View \(view.viewIndex), Snapshot \(snapshot.frameID)"
        encoder.setViewport(MTLViewport(
            originX: view.viewport.originX,
            originY: view.viewport.originY,
            width: view.viewport.width,
            height: view.viewport.height,
            znear: view.viewport.nearDepth,
            zfar: view.viewport.farDepth
        ))
        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        var uniforms = ProofUniforms(
            model: snapshot.modelTransform,
            viewProjection: view.viewProjection
        )
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<ProofUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
        encoder.endEncoding()
        return true
    }

    private func reportFailure(_ message: String) {
        Task { @MainActor in coordinator.stereoProofFailed(message) }
    }

    private static let proofVertices: [ProofVertex] = {
        let a = SIMD3<Float>(-0.42, -0.30, 0.28)
        let b = SIMD3<Float>(0.50, -0.26, 0.18)
        let c = SIMD3<Float>(0.02, 0.58, 0.02)
        let d = SIMD3<Float>(-0.08, -0.18, -0.62)
        let red = SIMD3<Float>(0.95, 0.22, 0.18)
        let green = SIMD3<Float>(0.20, 0.85, 0.42)
        let blue = SIMD3<Float>(0.18, 0.48, 0.96)
        let gold = SIMD3<Float>(0.98, 0.70, 0.16)
        return [
            .init(position: a, color: red), .init(position: b, color: red),
            .init(position: c, color: red),
            .init(position: a, color: green), .init(position: d, color: green),
            .init(position: b, color: green),
            .init(position: b, color: blue), .init(position: d, color: blue),
            .init(position: c, color: blue),
            .init(position: c, color: gold), .init(position: d, color: gold),
            .init(position: a, color: gold),
        ]
    }()

    private static func translation(x: Float, y: Float, z: Float) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(x, y, z, 1)
        ))
    }

    private static func rotationX(_ angle: Float) -> simd_float4x4 {
        let cosine = cos(angle)
        let sine = sin(angle)
        return simd_float4x4(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, cosine, sine, 0),
            SIMD4<Float>(0, -sine, cosine, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    private static func rotationY(_ angle: Float) -> simd_float4x4 {
        let cosine = cos(angle)
        let sine = sin(angle)
        return simd_float4x4(columns: (
            SIMD4<Float>(cosine, 0, -sine, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(sine, 0, cosine, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }
}

private extension LayerRenderer.Clock.Instant {
    var goalpadTimeInterval: TimeInterval {
        let components = LayerRenderer.Clock.Instant.epoch.duration(to: self).components
        let nanoseconds = TimeInterval(components.attoseconds / 1_000_000_000)
        return TimeInterval(components.seconds) + nanoseconds / TimeInterval(NSEC_PER_SEC)
    }
}
#endif
