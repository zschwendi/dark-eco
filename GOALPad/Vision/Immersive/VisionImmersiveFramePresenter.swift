#if os(visionOS) && GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE
import ARKit
import CompositorServices
import Foundation
import Metal
import OSLog
import os
import simd

nonisolated private let immersivePresenterLog = Logger(
    subsystem: "com.zephyrstudiosllc.eco", category: "ImmersivePresenter")

/// Owns CompositorServices submission and resolves paired native game views into the matching
/// left/right compositor views. Game images retain the tracked render pose that produced them, so
/// a cadence-reused image is never falsely labelled with the newest head pose.
nonisolated final class VisionImmersiveFramePresenter: @unchecked Sendable {
    private struct ResolveUniforms {
        var clipFromQuad: simd_float4x4
        var fade: Float
    }

    private struct RetainedPose {
        let identity: UInt64
        let anchor: DeviceAnchor
    }

    private struct PreparedDrawable {
        let drawable: LayerRenderer.Drawable
        let passes: [VisionImmersivePass]
    }

    private struct EncodedDrawable {
        let drawnViews: Int
        let evidenceTicket: VisionImmersiveRenderEvidenceSampler.Ticket?
    }

    private struct RequestContext {
        let request: VisionImmersiveFrameRequest
        let binocularCullClipFromDevice: simd_float4x4
        let cullIncreaseTangents: SIMD4<Float>
        let configurationDefaultDepthRange: SIMD2<Float>
    }

    private static let unpresentableMapping =
        "The compositor supplied an unsupported two-eye texture mapping."

    private let layerRenderer: LayerRenderer
    private let attempt: UInt64
    private let commandQueue: any MTLCommandQueue
    private let pipelineState: any MTLRenderPipelineState
    private let menuPipelineState: any MTLRenderPipelineState
    private let depthState: any MTLDepthStencilState
    private let depthHasStencil: Bool
    private let evidenceSampler: VisionImmersiveRenderEvidenceSampler
    private let arSession = ARKitSession()
    private let worldTracking = WorldTrackingProvider()
    private let firstGameFrameReported = OSAllocatedUnfairLock(initialState: false)
    private let failureReported = OSAllocatedUnfairLock(initialState: false)
    private let mappingRejectionRecorded = OSAllocatedUnfairLock(initialState: false)
    private let stopReported = OSAllocatedUnfairLock(initialState: false)
    private let trackingReady = OSAllocatedUnfairLock(initialState: false)

    // Render-thread state.
    private var trackingPolicy = VisionImmersiveTrackingPolicy()
    private var nextPoseIdentity: UInt64 = 0
    private var latestRequestPose: RetainedPose?
    private var latestRenderedPose: RetainedPose?
    private var latestRenderedSerial: UInt64?
    private var entryOriginFromGameCameraMeters: simd_float4x4?
    /// Fixed in the room when a menu frame first appears; cleared when gameplay frames return.
    private var menuOriginFromPlane: simd_float4x4?
    private var reportedSceneActive: Bool?
    private var cameraContractCaptureScheduled = false

    private init(layerRenderer: LayerRenderer,
                 attempt: UInt64,
                 commandQueue: any MTLCommandQueue,
                 pipelineState: any MTLRenderPipelineState,
                 menuPipelineState: any MTLRenderPipelineState,
                 depthState: any MTLDepthStencilState,
                 depthHasStencil: Bool,
                 evidenceSampler: VisionImmersiveRenderEvidenceSampler) {
        self.layerRenderer = layerRenderer
        self.attempt = attempt
        self.commandQueue = commandQueue
        self.pipelineState = pipelineState
        self.menuPipelineState = menuPipelineState
        self.depthState = depthState
        self.depthHasStencil = depthHasStencil
        self.evidenceSampler = evidenceSampler
    }

    /// Validates the layer against the game renderer and starts required world tracking before the
    /// render thread. Tracking is not optional: native per-eye cameras and cached-frame reprojection
    /// would be incorrect without the actual presentation-time DeviceAnchor.
    @MainActor
    static func start(_ layerRenderer: LayerRenderer,
                      attempt: UInt64,
                      device: any MTLDevice,
                      commandQueue: any MTLCommandQueue) -> String? {
        guard layerRenderer.device === device else {
            return "The compositor and the game renderer use different Metal devices."
        }
        guard WorldTrackingProvider.isSupported else {
            return "Head tracking is unavailable, so per-eye immersive rendering cannot start."
        }
        let configuration = layerRenderer.configuration
        guard [.bgra8Unorm_srgb, .rgba16Float].contains(configuration.colorFormat) else {
            return "The compositor color format \(configuration.colorFormat.rawValue) cannot "
                + "preserve Dark Eco's colors."
        }
        guard configuration.depthFormat != .invalid else {
            return "The compositor did not provide a depth format."
        }
        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "vision_immersive_screen_vertex"),
              let fragmentFunction = library.makeFunction(
                  name: "vision_immersive_screen_fragment"),
              let menuFragmentFunction = library.makeFunction(
                  name: "vision_immersive_menu_plane_fragment") else {
            return "This build lacks the immersive per-eye resolve shader."
        }

        let depthHasStencil = configuration.depthFormat == .depth32Float_stencil8
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "Dark Eco immersive per-eye color/depth resolve"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = configuration.colorFormat
        pipelineDescriptor.depthAttachmentPixelFormat = configuration.depthFormat
        if depthHasStencil {
            pipelineDescriptor.stencilAttachmentPixelFormat = configuration.depthFormat
        }
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .always
        depthDescriptor.isDepthWriteEnabled = true
        let menuPipelineDescriptor = pipelineDescriptor.copy() as! MTLRenderPipelineDescriptor
        menuPipelineDescriptor.label = "Dark Eco immersive menu plane"
        menuPipelineDescriptor.fragmentFunction = menuFragmentFunction
        guard let pipelineState = try? device.makeRenderPipelineState(
                  descriptor: pipelineDescriptor),
              let menuPipelineState = try? device.makeRenderPipelineState(
                  descriptor: menuPipelineDescriptor),
              let depthState = device.makeDepthStencilState(descriptor: depthDescriptor) else {
            return "Metal could not build the immersive per-eye resolve pipeline."
        }
        let evidenceSampler: VisionImmersiveRenderEvidenceSampler
        do {
            evidenceSampler = try VisionImmersiveRenderEvidenceSampler(
                device: device, library: library, attempt: attempt)
        } catch {
            return "Immersive render evidence could not start: \(error.localizedDescription)"
        }

        let presenter = VisionImmersiveFramePresenter(
            layerRenderer: layerRenderer,
            attempt: attempt,
            commandQueue: commandQueue,
            pipelineState: pipelineState,
            menuPipelineState: menuPipelineState,
            depthState: depthState,
            depthHasStencil: depthHasStencil,
            evidenceSampler: evidenceSampler
        )
        presenter.startRenderThread()
        Task {
            do {
                try await presenter.arSession.run([presenter.worldTracking])
                presenter.trackingReady.withLock { $0 = true }
            } catch {
                presenter.fail("World tracking could not start: \(error.localizedDescription)")
            }
        }
        return nil
    }

    private func startRenderThread() {
        let thread = Thread { self.renderLoop() }
        thread.name = "Dark Eco immersive per-eye presenter"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    private func renderLoop() {
        while true {
            switch layerRenderer.state {
            case .invalidated:
                reportSceneActive(false)
                stop()
                return
            case .paused:
                reportSceneActive(false)
                trackingPolicy.suspend()
                layerRenderer.waitUntilRunning()
            case .running:
                reportSceneActive(true)
                autoreleasepool { renderFrame() }
            @unknown default:
                reportSceneActive(false)
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
    }

    private func renderFrame() {
        guard !failureReported.withLock({ $0 }) else {
            // The coordinator is dismissing the space; wait for invalidation without drawing.
            Thread.sleep(forTimeInterval: 0.02)
            return
        }
        guard trackingReady.withLock({ $0 }) else {
            Thread.sleep(forTimeInterval: 0.005)
            return
        }
        guard let layerFrame = layerRenderer.queryNextFrame() else {
            Thread.sleep(forTimeInterval: 0.001)
            return
        }
        guard layerFrame.predictTiming() != nil else { return }
        layerFrame.startUpdate()
        layerFrame.endUpdate()

        guard let timing = layerFrame.predictTiming() else { return }
        LayerRenderer.Clock().wait(until: timing.optimalInputTime)
        let drawables = layerFrame.queryDrawables()
        // CompositorServices frame.h: an empty drawable array means the frame was cancelled and is
        // invalid to access, so discard it before any further frame or drawable access.
        guard !drawables.isEmpty else { return }
        guard let preparedDrawables = prepare(drawables, layerFrameIndex: layerFrame.frameIndex),
              let builtIn = preparedDrawables.first(where: {
                  $0.drawable.target == .builtIn
              }) else { return }
        let presentationTime = builtIn.drawable.frameTiming.presentationTime.timeInterval
        guard let anchor = trackedDeviceAnchor(at: presentationTime) else {
            presentWithoutPose(preparedDrawables, layerFrame: layerFrame)
            return
        }
        guard let requestContext = makeRequest(
            layerFrame: layerFrame,
            drawable: builtIn.drawable,
            anchor: anchor,
            presentationTime: presentationTime) else { return }

        // Native eye rendering depends on this pose too; include its CPU encoding and queued GPU
        // work in the compositor's submission interval, not only the final texture resolve.
        layerFrame.startSubmission()
        defer { layerFrame.endSubmission() }
        let presentedFrame = tickGame(request: requestContext.request)
        let renderAnchor: DeviceAnchor
        switch presentedFrame {
        case .perEye(let gameFrame):
            guard gameFrame.isPresentable(on: layerRenderer.device) else {
                fail("The native renderer returned an incomplete per-eye color/depth frame.")
                return
            }
            guard gameFrame.request.isOpticallyCompatible(with: requestContext.request) else {
                fail("The native renderer returned a frame for different eye optics.")
                return
            }
            if let latestRenderedSerial {
                guard gameFrame.renderSerial >= latestRenderedSerial,
                      gameFrame.renderSerial != latestRenderedSerial
                        || gameFrame.request.poseIdentity == latestRenderedPose?.identity else {
                    fail("The native renderer changed or reordered a completed stereo frame.")
                    return
                }
            }
            guard let retained = retainedPose(for: gameFrame.request.poseIdentity) else {
                fail("The native renderer returned a frame whose tracked render pose was lost.")
                return
            }
            renderAnchor = retained.anchor
            latestRenderedPose = retained
            latestRenderedSerial = gameFrame.renderSerial
            menuOriginFromPlane = nil
        case .menuPlane(let menuFrame):
            guard menuFrame.isPresentable(on: layerRenderer.device) else {
                fail("The native renderer returned an incomplete menu frame.")
                return
            }
            if let latestRenderedSerial, menuFrame.renderSerial < latestRenderedSerial {
                fail("The native renderer reordered a completed menu frame.")
                return
            }
            if menuOriginFromPlane == nil {
                menuOriginFromPlane = VisionImmersiveMenuPlane.originFromPlane(
                    originFromDevice: anchor.originFromAnchorTransform)
            }
            guard menuOriginFromPlane != nil else {
                fail("Dark Eco could not place the immersive menu in front of the head pose.")
                return
            }
            // Menu pixels do not depend on head pose, so the plane always uses this frame's pose.
            renderAnchor = anchor
            latestRenderedSerial = menuFrame.renderSerial
        case nil:
            renderAnchor = anchor
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            fail("Metal could not create the immersive per-eye command buffer.")
            return
        }
        commandBuffer.label = "Dark Eco immersive per-eye frame \(layerFrame.frameIndex)"
        var evidenceTicket: VisionImmersiveRenderEvidenceSampler.Ticket?
        for (drawableIndex, prepared) in preparedDrawables.enumerated() {
            guard let encoded = encode(
                prepared: prepared,
                presentedFrame: presentedFrame,
                renderAnchor: renderAnchor,
                requestContext: requestContext,
                layerFrameIndex: layerFrame.frameIndex,
                frameDrawableCount: preparedDrawables.count,
                drawableIndex: drawableIndex,
                into: commandBuffer) else { return }
            if encoded.drawnViews != prepared.drawable.views.count && presentedFrame != nil {
                fail("Metal did not encode both immersive eye views.")
                return
            }
            if let ticket = encoded.evidenceTicket {
                guard evidenceTicket == nil else {
                    fail("Metal encoded more than one built-in immersive evidence sample.")
                    return
                }
                evidenceTicket = ticket
            }
            prepared.drawable.encodePresent(commandBuffer: commandBuffer)
        }

        let attempt = attempt
        let firstGameFrameReported = firstGameFrameReported
        let evidenceSampler = evidenceSampler
        commandBuffer.addCompletedHandler { completed in
            if completed.status != .completed {
                let message = "Immersive per-eye GPU work failed (status "
                    + "\(completed.status.rawValue)), so Dark Eco returned to the window."
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        VisionImmersiveProofCoordinator.shared.presenterFailed(
                            attempt: attempt, message: message)
                    }
                }
            } else if let evidenceTicket {
                let evidence = evidenceSampler.complete(evidenceTicket)
                if evidence.becameVisible,
                   firstGameFrameReported.withLock({ reported in
                       defer { reported = true }
                       return !reported
                   }) {
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            VisionImmersiveProofCoordinator.shared.presentedFirstGameFrame(
                                attempt: attempt)
                        }
                    }
                }
            }
        }
        commandBuffer.commit()
    }

    /// The caller discards cancelled (empty) frames before preparing drawables.
    private func prepare(_ drawables: [LayerRenderer.Drawable],
                         layerFrameIndex: UInt64) -> [PreparedDrawable]? {
        guard drawables.filter({ $0.target == .builtIn }).count == 1 else {
            recordMappingRejection(.builtInCount, drawables: drawables,
                                   failingDrawableIndex: nil, layerFrameIndex: layerFrameIndex)
            fail(Self.unpresentableMapping)
            return nil
        }
        var prepared: [PreparedDrawable] = []
        prepared.reserveCapacity(drawables.count)
        for (drawableIndex, drawable) in drawables.enumerated() {
            guard drawable.rasterizationRateMaps.isEmpty else {
                recordMappingRejection(.rateMaps, drawables: drawables,
                                       failingDrawableIndex: drawableIndex,
                                       layerFrameIndex: layerFrameIndex)
                fail(Self.unpresentableMapping)
                return nil
            }
            guard drawable.views.count == VisionImmersiveFrameRequest.viewCount else {
                recordMappingRejection(.viewCount, drawables: drawables,
                                       failingDrawableIndex: drawableIndex,
                                       layerFrameIndex: layerFrameIndex)
                fail(Self.unpresentableMapping)
                return nil
            }
            let mappings = drawable.views.map(Self.mapping)
            guard let passes = VisionImmersivePassPlanner.passes(
                views: mappings,
                colorTargets: drawable.colorTextures.map(Self.shape),
                depthTargets: drawable.depthTextures.map(Self.shape)
            ) else {
                recordMappingRejection(.passPlan, drawables: drawables,
                                       failingDrawableIndex: drawableIndex,
                                       layerFrameIndex: layerFrameIndex)
                fail(Self.unpresentableMapping)
                return nil
            }
            prepared.append(PreparedDrawable(drawable: drawable, passes: passes))
        }
        return prepared
    }

    /// While no tracked pose exists, presents opaque black at far depth with no device anchor, so
    /// the compositor keeps its cadence without content placed from an untracked pose.
    private func presentWithoutPose(_ preparedDrawables: [PreparedDrawable],
                                    layerFrame: LayerRenderer.Frame) {
        layerFrame.startSubmission()
        defer { layerFrame.endSubmission() }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            fail("Metal could not create the immersive per-eye command buffer.")
            return
        }
        commandBuffer.label = "Dark Eco immersive pose-free frame \(layerFrame.frameIndex)"
        for prepared in preparedDrawables {
            for pass in prepared.passes {
                guard let encoder = commandBuffer.makeRenderCommandEncoder(
                    descriptor: clearingPassDescriptor(drawable: prepared.drawable, pass: pass))
                else {
                    fail("Metal could not encode the immersive per-eye resolve.")
                    return
                }
                encoder.label = "Dark Eco immersive pose-free clear"
                encoder.endEncoding()
            }
            prepared.drawable.encodePresent(commandBuffer: commandBuffer)
        }
        commandBuffer.commit()
    }

    private func makeRequest(layerFrame: LayerRenderer.Frame,
                             drawable: LayerRenderer.Drawable,
                             anchor: DeviceAnchor,
                             presentationTime: TimeInterval) -> RequestContext? {
        let views = drawable.views
        guard views.count == VisionImmersiveFrameRequest.viewCount else {
            recordMappingRejection(.requestViewCount, drawables: [drawable],
                                   failingDrawableIndex: nil, layerFrameIndex: layerFrame.frameIndex)
            fail(Self.unpresentableMapping)
            return nil
        }
        let originFromDevice = anchor.originFromAnchorTransform
        if entryOriginFromGameCameraMeters == nil {
            entryOriginFromGameCameraMeters = originFromDevice
        }
        guard let entryOriginFromGameCameraMeters else {
            fail("Dark Eco could not establish the immersive entry pose.")
            return nil
        }

        let cullIncreaseTangents = VisionImmersiveBinocularCullPolicy.increaseTangents
        let configurationDefaultDepthRange = layerRenderer.configuration.defaultDepthRange
        let cullDepthRange = VisionImmersiveBinocularCullPolicy.broaderDepthRange(
            than: configurationDefaultDepthRange)
        let binocularCullClipFromDevice = layerFrame.binocularFrustumMatrixForDrawableTarget(
            drawableTarget: .builtIn,
            convention: .rightUpBack,
            increaseTangents: cullIncreaseTangents,
            depthRange: cullDepthRange
        )
        let clipFromEyes = views.indices.map {
            drawable.computeProjection(convention: .rightUpBack, viewIndex: $0)
        }
        let aspects = views.map { view -> Float in
            let viewport = view.textureMap.viewport
            return Float(viewport.width / viewport.height)
        }
        guard let cameras = VisionImmersiveCameraMath.makeCameras(
            originFromDevice: originFromDevice,
            deviceFromEyes: views.map(\.transform),
            clipFromEyes: clipFromEyes,
            aspectRatios: aspects,
            entryOriginFromGameCameraMeters: entryOriginFromGameCameraMeters,
            binocularCullClipFromDevice: binocularCullClipFromDevice,
            skyGeneration: true) else {
            fail("The compositor returned a non-invertible per-eye camera transform or an improper head rotation.")
            return nil
        }

        nextPoseIdentity &+= 1
        if nextPoseIdentity == 0 { nextPoseIdentity = 1 }
        let request = VisionImmersiveFrameRequest(
            presentationTime: presentationTime,
            originFromDevice: originFromDevice,
            cameras: cameras,
            poseIdentity: nextPoseIdentity
        )
        guard request.isValid else {
            fail("The compositor returned an invalid per-eye camera request.")
            return nil
        }
        latestRequestPose = RetainedPose(identity: request.poseIdentity, anchor: anchor)
        return RequestContext(
            request: request,
            binocularCullClipFromDevice: binocularCullClipFromDevice,
            cullIncreaseTangents: cullIncreaseTangents,
            configurationDefaultDepthRange: configurationDefaultDepthRange
        )
    }

    private func tickGame(request: VisionImmersiveFrameRequest) -> VisionImmersivePresentedFrame? {
        let attempt = attempt
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                VisionImmersiveProofCoordinator.shared.tickGame(
                    attempt: attempt, request: request)
            }
        }
    }

    /// Clears every mapped target to opaque black and reverse-Z far, then resolves each native eye
    /// into only the corresponding compositor view. The fragment shader writes native physical
    /// depth as well as color. A menu frame is instead drawn once per view on its finite plane,
    /// leaving black at far depth around it.
    private func encode(prepared: PreparedDrawable,
                        presentedFrame: VisionImmersivePresentedFrame?,
                        renderAnchor: DeviceAnchor,
                        requestContext: RequestContext,
                        layerFrameIndex: UInt64,
                        frameDrawableCount: Int,
                        drawableIndex: Int,
                        into commandBuffer: any MTLCommandBuffer) -> EncodedDrawable? {
        let drawable = prepared.drawable
        let views = drawable.views
        drawable.deviceAnchor = renderAnchor
        var gameFrame: VisionImmersiveGameFrame?
        var menuFrame: VisionImmersiveMenuFrame?
        switch presentedFrame {
        case .perEye(let frame): gameFrame = frame
        case .menuPlane(let frame): menuFrame = frame
        case nil: break
        }
        captureCameraContractIfNeeded(
            drawable: drawable,
            gameFrame: gameFrame,
            requestContext: requestContext,
            layerFrameIndex: layerFrameIndex,
            frameDrawableCount: frameDrawableCount,
            drawableIndex: drawableIndex,
            commandBuffer: commandBuffer
        )
        // Every view's plane transform is formed before any encoder opens, so a failure leaves no
        // partially encoded pass.
        var menuClipFromQuads: [simd_float4x4] = []
        if let menuFrame {
            guard let menuOriginFromPlane,
                  let size = VisionImmersiveMenuPlane.size(
                      aspectRatio: menuFrame.aspectRatio) else {
                fail("Dark Eco could not size the immersive menu plane.")
                return nil
            }
            for viewIndex in views.indices {
                guard let clipFromQuad = VisionImmersiveMenuPlane.clipFromQuad(
                    originFromPlane: menuOriginFromPlane,
                    size: size,
                    originFromDevice: renderAnchor.originFromAnchorTransform,
                    deviceFromEye: views[viewIndex].transform,
                    clipFromEye: drawable.computeProjection(
                        convention: .rightUpBack, viewIndex: viewIndex)) else {
                    fail("The compositor returned a non-invertible menu-plane eye transform.")
                    return nil
                }
                menuClipFromQuads.append(clipFromQuad)
            }
        }

        var drawnViews = 0
        for pass in prepared.passes {
            guard let encoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: clearingPassDescriptor(drawable: drawable, pass: pass)) else {
                fail("Metal could not encode the immersive per-eye resolve.")
                return nil
            }
            encoder.label = "Dark Eco immersive texture \(pass.textureIndex) "
                + "slice \(pass.sliceIndex)"
            if let gameFrame {
                encoder.setRenderPipelineState(pipelineState)
                encoder.setDepthStencilState(depthState)
                encoder.setCullMode(.none)
                for viewIndex in pass.viewIndices {
                    var uniforms = ResolveUniforms(
                        clipFromQuad: VisionImmersiveResolve.clipFromQuad,
                        fade: gameFrame.fade)
                    encoder.setViewport(views[viewIndex].textureMap.viewport)
                    encoder.setVertexBytes(&uniforms,
                                           length: MemoryLayout<ResolveUniforms>.stride,
                                           index: 0)
                    encoder.setFragmentBytes(&uniforms,
                                             length: MemoryLayout<ResolveUniforms>.stride,
                                             index: 0)
                    encoder.setFragmentTexture(gameFrame.colorTextures[viewIndex], index: 0)
                    encoder.setFragmentTexture(gameFrame.depthTextures[viewIndex], index: 1)
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                    drawnViews += 1
                }
            } else if let menuFrame {
                encoder.setRenderPipelineState(menuPipelineState)
                encoder.setDepthStencilState(depthState)
                encoder.setCullMode(.none)
                for viewIndex in pass.viewIndices {
                    var uniforms = ResolveUniforms(
                        clipFromQuad: menuClipFromQuads[viewIndex],
                        fade: menuFrame.fade)
                    encoder.setViewport(views[viewIndex].textureMap.viewport)
                    encoder.setVertexBytes(&uniforms,
                                           length: MemoryLayout<ResolveUniforms>.stride,
                                           index: 0)
                    encoder.setFragmentBytes(&uniforms,
                                             length: MemoryLayout<ResolveUniforms>.stride,
                                             index: 0)
                    encoder.setFragmentTexture(menuFrame.colorTexture, index: 0)
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                    drawnViews += 1
                }
            }
            encoder.endEncoding()
        }
        var evidenceTicket: VisionImmersiveRenderEvidenceSampler.Ticket?
        if let presentedFrame, drawable.target == .builtIn {
            let resolvedEyes = views.map { view in
                let map = view.textureMap
                let viewport = map.viewport
                return VisionImmersiveRenderEvidenceSampler.ResolvedEye(
                    colorTexture: drawable.colorTextures[map.textureIndex],
                    depthTexture: drawable.depthTextures[map.textureIndex],
                    originX: viewport.originX,
                    originY: viewport.originY,
                    width: viewport.width,
                    height: viewport.height,
                    sliceIndex: map.sliceIndex
                )
            }
            let nativeColorTextures: [any MTLTexture]
            let nativeDepthTextures: [any MTLTexture]
            let fade: Float
            let request: VisionImmersiveFrameRequest
            switch presentedFrame {
            case .perEye(let frame):
                nativeColorTextures = frame.colorTextures
                nativeDepthTextures = frame.depthTextures
                fade = frame.fade
                request = frame.request
            case .menuPlane(let frame):
                // Both eyes see the same conventional source image.
                nativeColorTextures = [frame.colorTexture, frame.colorTexture]
                nativeDepthTextures = [frame.depthTexture, frame.depthTexture]
                fade = frame.fade
                request = requestContext.request
            }
            do {
                evidenceTicket = try evidenceSampler.encodeIfNeeded(
                    nativeColorTextures: nativeColorTextures,
                    nativeDepthTextures: nativeDepthTextures,
                    resolvedEyes: resolvedEyes,
                    fade: fade,
                    nativeRenderSerial: presentedFrame.renderSerial,
                    poseIdentity: request.poseIdentity,
                    compositorFrameIndex: layerFrameIndex,
                    presentationTime: request.presentationTime,
                    commandBuffer: commandBuffer
                )
            } catch {
                fail("Immersive render evidence sampling failed: \(error.localizedDescription)")
                return nil
            }
        }
        return EncodedDrawable(drawnViews: drawnViews, evidenceTicket: evidenceTicket)
    }

    private func clearingPassDescriptor(drawable: LayerRenderer.Drawable,
                                        pass: VisionImmersivePass) -> MTLRenderPassDescriptor {
        let color = drawable.colorTextures[pass.textureIndex]
        let depth = drawable.depthTextures[pass.textureIndex]
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = color
        descriptor.colorAttachments[0].slice = pass.sliceIndex
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: 0, green: 0, blue: 0, alpha: 1)
        descriptor.depthAttachment.texture = depth
        descriptor.depthAttachment.slice = pass.sliceIndex
        descriptor.depthAttachment.loadAction = .clear
        descriptor.depthAttachment.storeAction = .store
        descriptor.depthAttachment.clearDepth = 0
        if depthHasStencil {
            descriptor.stencilAttachment.texture = depth
            descriptor.stencilAttachment.slice = pass.sliceIndex
            descriptor.stencilAttachment.loadAction = .clear
            descriptor.stencilAttachment.storeAction = .dontCare
        }
        return descriptor
    }

    private func captureCameraContractIfNeeded(
        drawable: LayerRenderer.Drawable,
        gameFrame: VisionImmersiveGameFrame?,
        requestContext: RequestContext,
        layerFrameIndex: UInt64,
        frameDrawableCount: Int,
        drawableIndex: Int,
        commandBuffer: any MTLCommandBuffer
    ) {
        guard let gameFrame,
              let entryOriginFromGameCameraMeters,
              gameFrame.request.poseIdentity == requestContext.request.poseIdentity,
              drawable.target == .builtIn,
              !cameraContractCaptureScheduled else { return }
        cameraContractCaptureScheduled = true
        let views = drawable.views
        let contractViews = views.indices.map { viewIndex in
            let view = views[viewIndex]
            let viewport = view.textureMap.viewport
            return VisionImmersiveCameraContract.View(
                index: viewIndex,
                projectionRightUpBackColumnMajor: Self.columnMajor(
                    gameFrame.request.cameras[viewIndex].clipFromEye),
                deviceFromViewColumnMajor: Self.columnMajor(view.transform),
                textureIndex: view.textureMap.textureIndex,
                sliceIndex: view.textureMap.sliceIndex,
                viewport: .init(
                    originX: viewport.originX,
                    originY: viewport.originY,
                    width: viewport.width,
                    height: viewport.height,
                    nearDepth: viewport.znear,
                    farDepth: viewport.zfar
                )
            )
        }
        let contract = VisionImmersiveCameraContract(
            schemaVersion: 3,
            captureScope: "firstNativePerEyeFrameWithTrackedRenderPose",
            coordinateConvention: "rightUpBack",
            attempt: attempt,
            layerFrameIndex: layerFrameIndex,
            frameDrawableCount: frameDrawableCount,
            capturedDrawableIndex: drawableIndex,
            drawableTarget: "builtIn",
            drawablePresentationFrameIndex: drawable.presentationFrameIndex,
            drawablePresentationTimestamp: gameFrame.request.presentationTime,
            gameFrameAvailable: true,
            gameRenderWidth: gameFrame.colorTextures[0].width,
            gameRenderHeight: gameFrame.colorTextures[0].height,
            deviceAnchorWasAssigned: true,
            originFromDeviceColumnMajor: Self.columnMajor(gameFrame.request.originFromDevice),
            entryOriginFromGameCameraMetersColumnMajor:
                Self.columnMajor(entryOriginFromGameCameraMeters),
            configurationDefaultDepthRange: [
                requestContext.configurationDefaultDepthRange.x,
                requestContext.configurationDefaultDepthRange.y,
            ],
            binocularCullClipFromDeviceColumnMajor: Self.columnMajor(
                requestContext.binocularCullClipFromDevice),
            binocularCullIncreaseTangents: [
                requestContext.cullIncreaseTangents.x,
                requestContext.cullIncreaseTangents.y,
                requestContext.cullIncreaseTangents.z,
                requestContext.cullIncreaseTangents.w,
            ],
            views: contractViews
        )
        commandBuffer.addCompletedHandler { completed in
            guard completed.status == .completed else { return }
            VisionImmersiveCameraContractWriter.write(contract)
        }
    }

    private func retainedPose(for identity: UInt64) -> RetainedPose? {
        if latestRequestPose?.identity == identity { return latestRequestPose }
        if latestRenderedPose?.identity == identity { return latestRenderedPose }
        return nil
    }

    /// This frame's own tracked pose, or nil while tracking starts or briefly drops. The space
    /// fails once the tracking policy's bounded grace expires or the provider stops.
    private func trackedDeviceAnchor(at time: TimeInterval) -> DeviceAnchor? {
        var trackedAnchor: DeviceAnchor?
        if time.isFinite, time > 0,
           let anchor = worldTracking.queryDeviceAnchor(atTimestamp: time),
           anchor.trackingState == .tracked,
           Self.isFinite(anchor.originFromAnchorTransform) {
            trackedAnchor = anchor
        }
        let sample: VisionImmersiveTrackingPolicy.Sample
        if worldTracking.state == .stopped {
            sample = .providerStopped
        } else {
            sample = trackedAnchor == nil ? .untracked : .tracked
        }
        switch trackingPolicy.decide(sample, at: LayerRenderer.Clock().now.timeInterval) {
        case .render:
            return trackedAnchor
        case .wait:
            return nil
        case .fail(.neverAcquired):
            fail("Head tracking did not start within two seconds, so Dark Eco returned to the "
                + "window.")
        case .fail(.lost):
            fail("Head tracking was lost for over a second, so Dark Eco returned to the window.")
        case .fail(.providerStopped):
            fail("World tracking stopped, so Dark Eco returned to the window.")
        }
        return nil
    }

    private func reportSceneActive(_ active: Bool) {
        guard reportedSceneActive != active else { return }
        reportedSceneActive = active
        let attempt = attempt
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                VisionImmersiveProofCoordinator.shared.setImmersiveSceneActive(
                    active, attempt: attempt)
            }
        }
    }

    /// Snapshots bounded mapping metadata for the first genuine rejection of this attempt and hands
    /// it to the async diagnostics writer. It never changes the user-visible failure message.
    private func recordMappingRejection(_ rejectedGuard: VisionImmersiveMappingRejection.Guard,
                                        drawables: [LayerRenderer.Drawable],
                                        failingDrawableIndex: Int?,
                                        layerFrameIndex: UInt64) {
        let shouldRecord = mappingRejectionRecorded.withLock { recorded in
            guard !recorded, !failureReported.withLock({ $0 }) else { return false }
            recorded = true
            return true
        }
        guard shouldRecord else { return }
        let document = VisionImmersiveMappingRejection.document(
            attempt: attempt,
            layerFrameIndex: layerFrameIndex,
            rejectedGuard: rejectedGuard,
            failingDrawableIndex: failingDrawableIndex,
            drawables: drawables,
            accessors: VisionImmersiveMappingRejection.Accessors(
                target: Self.rejectionTarget,
                viewCount: { $0.views.count },
                rasterizationRateMapCount: { $0.rasterizationRateMaps.count },
                colorTextureCount: { $0.colorTextures.count },
                depthTextureCount: { $0.depthTextures.count },
                view: { drawable, index in
                    let textureMap = drawable.views[index].textureMap
                    let viewport = textureMap.viewport
                    return VisionImmersiveMappingRejection.ViewInput(
                        textureIndex: textureMap.textureIndex,
                        sliceIndex: textureMap.sliceIndex,
                        originX: viewport.originX,
                        originY: viewport.originY,
                        width: viewport.width,
                        height: viewport.height,
                        nearDepth: viewport.znear,
                        farDepth: viewport.zfar)
                },
                colorTexture: { Self.rejectionTexture($0.colorTextures[$1]) },
                depthTexture: { Self.rejectionTexture($0.depthTextures[$1]) }))
        VisionImmersiveMappingRejectionRecorder.shared.record(document)
    }

    private static func rejectionTarget(_ drawable: LayerRenderer.Drawable)
        -> VisionImmersiveMappingRejection.Target {
        switch drawable.target {
        case .builtIn: .builtIn
        case .capture: .capture
        @unknown default: .unknown
        }
    }

    private static func rejectionTexture(_ texture: any MTLTexture)
        -> VisionImmersiveMappingRejection.TextureInput {
        VisionImmersiveMappingRejection.TextureInput(
            textureType: texture.textureType.rawValue,
            width: texture.width,
            height: texture.height,
            arrayLength: texture.arrayLength)
    }

    private func fail(_ message: String) {
        let shouldReport = failureReported.withLock { reported in
            guard !reported else { return false }
            reported = true
            return true
        }
        guard shouldReport else { return }
        immersivePresenterLog.error("\(message, privacy: .public)")
        let attempt = attempt
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                VisionImmersiveProofCoordinator.shared.presenterFailed(
                    attempt: attempt, message: message)
            }
        }
    }

    private func stop() {
        let shouldReport = stopReported.withLock { reported in
            guard !reported else { return false }
            reported = true
            return true
        }
        guard shouldReport else { return }
        reportSceneActive(false)
        arSession.stop()
        let attempt = attempt
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                VisionImmersiveProofCoordinator.shared.presenterStopped(
                    attempt: attempt, reason: .compositorInvalidated)
            }
        }
    }

    private static func mapping(_ view: LayerRenderer.Drawable.View)
        -> VisionImmersiveViewMapping {
        let viewport = view.textureMap.viewport
        return VisionImmersiveViewMapping(
            textureIndex: view.textureMap.textureIndex,
            sliceIndex: view.textureMap.sliceIndex,
            viewport: VisionImmersiveViewport(
                originX: viewport.originX,
                originY: viewport.originY,
                width: viewport.width,
                height: viewport.height,
                nearDepth: viewport.znear,
                farDepth: viewport.zfar
            )
        )
    }

    private static func shape(_ texture: any MTLTexture) -> VisionImmersiveTargetShape {
        VisionImmersiveTargetShape(
            width: texture.width,
            height: texture.height,
            sliceCount: texture.textureType == .type2DArray ? texture.arrayLength : 1
        )
    }

    private static func isFinite(_ matrix: simd_float4x4) -> Bool {
        columnMajor(matrix).allSatisfy(\.isFinite)
    }

    private static func columnMajor(_ matrix: simd_float4x4) -> [Float] {
        [
            matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z, matrix.columns.0.w,
            matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z, matrix.columns.1.w,
            matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z, matrix.columns.2.w,
            matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z, matrix.columns.3.w,
        ]
    }
}

private extension LayerRenderer.Clock.Instant {
    /// Seconds in the CACurrentMediaTime domain used by ARKit device-anchor queries.
    nonisolated var timeInterval: TimeInterval {
        let elapsed = LayerRenderer.Clock.Instant.epoch.duration(to: self).components
        return TimeInterval(elapsed.seconds) + TimeInterval(elapsed.attoseconds) * 1e-18
    }
}
#endif
