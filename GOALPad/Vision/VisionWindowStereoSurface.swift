#if os(visionOS)
import Metal
import QuartzCore
import RealityKit
import SwiftUI

@MainActor
struct VisionWindowStereoRenderTarget {
    let viewID: UInt64
    let colorTexture: any MTLTexture
    let depthTexture: any MTLTexture
    let clipFromGameClip: simd_float4x4
}

@MainActor
struct VisionWindowStereoRenderFrame {
    let targetPresentationTime: CFTimeInterval
    let width: Int
    let height: Int
    let commandBuffer: any MTLCommandBuffer
    let left: VisionWindowStereoRenderTarget
    let right: VisionWindowStereoRenderTarget
}

@MainActor
struct VisionWindowStereoRenderRequest {
    let targetPresentationTime: CFTimeInterval
    let width: Int
    let height: Int

    private let frameFactory: @MainActor () -> VisionWindowStereoRenderFrame?

    init(targetPresentationTime: CFTimeInterval,
         width: Int,
         height: Int,
         frameFactory: @escaping @MainActor () -> VisionWindowStereoRenderFrame?) {
        self.targetPresentationTime = targetPresentationTime
        self.width = width
        self.height = height
        self.frameFactory = frameFactory
    }

    func makeFrame() -> VisionWindowStereoRenderFrame? {
        frameFactory()
    }
}

typealias VisionWindowStereoFrameHandler = @Sendable @MainActor (
    VisionWindowStereoRenderRequest
) -> VisionStereoSubmissionDisposition

@MainActor
struct VisionWindowStereoSurfaceView: View {
    fileprivate struct PixelSize: Hashable {
        let width: Int
        let height: Int
    }

    fileprivate struct Configuration {
        let pixelSize: PixelSize
        let widthMeters: Float
        let heightMeters: Float
    }

    @Environment(\.displayScale) private var displayScale
    @Environment(\.physicalMetrics) private var physicalMetrics

    let renderFrame: VisionWindowStereoFrameHandler

    var body: some View {
        GeometryReader3D { proxy in
            let configuration = Configuration(
                pixelSize: .init(
                    width: pixelDimension(proxy.size.width),
                    height: pixelDimension(proxy.size.height)
                ),
                widthMeters: meterDimension(proxy.size.width),
                heightMeters: meterDimension(proxy.size.height)
            )

            VisionWindowStereoRealitySurface(
                configuration: configuration,
                renderFrame: renderFrame
            )
            .id(configuration.pixelSize)
        }
        .ignoresSafeArea()
        .background(.black)
    }

    private func pixelDimension(_ points: CGFloat) -> Int {
        min(max(Int((points * displayScale).rounded(.up)), 1), 4_096)
    }

    private func meterDimension(_ points: CGFloat) -> Float {
        max(Float(physicalMetrics.convert(points, to: .meters)), 0.001)
    }
}

@MainActor
private struct VisionWindowStereoRealitySurface: View {
    let configuration: VisionWindowStereoSurfaceView.Configuration
    let renderFrame: VisionWindowStereoFrameHandler

    @Environment(VisionPresentationCoordinator.self) private var coordinator
    @Environment(\.scenePhase) private var scenePhase
    @State private var resources: VisionWindowStereoResources?

    var body: some View {
        RealityView { content in
            do {
                VisionWindowStereoRenderSystem.registerSystem()
                let resources = try await VisionWindowStereoResources.make(
                    widthPixels: configuration.pixelSize.width,
                    heightPixels: configuration.pixelSize.height,
                    widthMeters: configuration.widthMeters,
                    heightMeters: configuration.heightMeters,
                    renderFrame: renderFrame,
                    failClosed: failClosed
                )
                content.add(resources.presentationEntity)
                resources.setSceneActive(scenePhase == .active)
                self.resources = resources
            } catch {
                failClosed(
                    "The stereoscopic window could not start, so Eco returned to Comfort mode: "
                        + error.localizedDescription
                )
            }
        } update: { _ in
            resources?.updateSurfaceSize(
                widthMeters: configuration.widthMeters,
                heightMeters: configuration.heightMeters
            )
        }
        .frame(depth: 0)
        .onChange(of: scenePhase, initial: true) { _, phase in
            resources?.setSceneActive(phase == .active)
        }
        .onDisappear {
            resources?.invalidate()
            resources = nil
        }
    }

    private func failClosed(_ message: String) {
        Task { @MainActor in
            await Task.yield()
            coordinator.stereoSurfaceFailed(message)
        }
    }
}

private struct VisionWindowStereoRenderComponent: TransientComponent {}

@MainActor
private final class VisionWindowStereoRenderEntity: Entity {
    weak var resources: VisionWindowStereoResources?

    required init() {
        super.init()
        components.set(VisionWindowStereoRenderComponent())
    }

    func renderNextFrame() {
        resources?.renderNextFrame()
    }
}

private final class VisionWindowStereoRenderSystem: System {
    private static let renderEntities = EntityQuery(
        where: .has(VisionWindowStereoRenderComponent.self)
    )

    required init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        for entity in context.entities(
            matching: Self.renderEntities,
            updatingSystemWhen: .rendering
        ) {
            (entity as? VisionWindowStereoRenderEntity)?.renderNextFrame()
        }
    }
}

@MainActor
private final class VisionWindowStereoResources {
    let presentationEntity: VisionWindowStereoRenderEntity

    private let widthPixels: Int
    private let heightPixels: Int
    private let commandQueue: any MTLCommandQueue
    private let leftTexture: LowLevelTexture
    private let rightTexture: LowLevelTexture
    private let leftResource: TextureResource
    private let rightResource: TextureResource
    private let leftDepth: any MTLTexture
    private let rightDepth: any MTLTexture
    private let surfaceEntity: ModelEntity
    private let renderFrame: VisionWindowStereoFrameHandler
    private let failClosed: @MainActor (String) -> Void

    private var watchdog = VisionStereoSubmissionWatchdog()
    private var cadence = VisionStereoCadenceGate()
    private var liveness = VisionStereoLivenessWatchdog()
    private var livenessTask: Task<Void, Never>?
    private var isActive = true
    private var failureScheduled = false

    private init(widthPixels: Int,
                 heightPixels: Int,
                 commandQueue: any MTLCommandQueue,
                 leftTexture: LowLevelTexture,
                 rightTexture: LowLevelTexture,
                 leftResource: TextureResource,
                 rightResource: TextureResource,
                 leftDepth: any MTLTexture,
                 rightDepth: any MTLTexture,
                 surfaceEntity: ModelEntity,
                 presentationEntity: VisionWindowStereoRenderEntity,
                 renderFrame: @escaping VisionWindowStereoFrameHandler,
                 failClosed: @escaping @MainActor (String) -> Void) {
        self.widthPixels = widthPixels
        self.heightPixels = heightPixels
        self.commandQueue = commandQueue
        self.leftTexture = leftTexture
        self.rightTexture = rightTexture
        self.leftResource = leftResource
        self.rightResource = rightResource
        self.leftDepth = leftDepth
        self.rightDepth = rightDepth
        self.surfaceEntity = surfaceEntity
        self.presentationEntity = presentationEntity
        self.renderFrame = renderFrame
        self.failClosed = failClosed
    }

    static func make(widthPixels: Int,
                     heightPixels: Int,
                     widthMeters: Float,
                     heightMeters: Float,
                     renderFrame: @escaping VisionWindowStereoFrameHandler,
                     failClosed: @escaping @MainActor (String) -> Void) async throws
        -> VisionWindowStereoResources {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            throw VisionWindowStereoSurfaceError.metalUnavailable
        }

        let descriptor = LowLevelTexture.Descriptor(
            pixelFormat: .bgra8Unorm,
            width: widthPixels,
            height: heightPixels,
            depth: 1,
            mipmapLevelCount: 1,
            textureUsage: [.shaderRead, .renderTarget]
        )
        let leftTexture = try LowLevelTexture(descriptor: descriptor)
        let rightTexture = try LowLevelTexture(descriptor: descriptor)
        let leftResource = try await TextureResource(from: leftTexture)
        let rightResource = try await TextureResource(from: rightTexture)

        var material = try await ShaderGraphMaterial(
            named: "/Root/Material",
            from: "VisionStereoWindowMaterial",
            in: .main
        )
        try material.setParameter(name: "leftEye", value: .textureResource(leftResource))
        try material.setParameter(name: "rightEye", value: .textureResource(rightResource))

        let surfaceEntity = ModelEntity(
            mesh: .generatePlane(width: widthMeters, height: heightMeters),
            materials: [material]
        )
        surfaceEntity.name = "Eco stereoscopic game surface"

        guard let leftDepth = makeDepthTexture(
            device: device,
            width: widthPixels,
            height: heightPixels,
            label: "Eco stereo left depth"
        ), let rightDepth = makeDepthTexture(
            device: device,
            width: widthPixels,
            height: heightPixels,
            label: "Eco stereo right depth"
        ) else {
            throw VisionWindowStereoSurfaceError.depthTextureCreationFailed
        }

        let presentationEntity = VisionWindowStereoRenderEntity()
        presentationEntity.addChild(surfaceEntity)
        let resources = VisionWindowStereoResources(
            widthPixels: widthPixels,
            heightPixels: heightPixels,
            commandQueue: commandQueue,
            leftTexture: leftTexture,
            rightTexture: rightTexture,
            leftResource: leftResource,
            rightResource: rightResource,
            leftDepth: leftDepth,
            rightDepth: rightDepth,
            surfaceEntity: surfaceEntity,
            presentationEntity: presentationEntity,
            renderFrame: renderFrame,
            failClosed: failClosed
        )
        presentationEntity.resources = resources
        return resources
    }

    func updateSurfaceSize(widthMeters: Float, heightMeters: Float) {
        guard var model = surfaceEntity.model else { return }
        model.mesh = .generatePlane(width: widthMeters, height: heightMeters)
        surfaceEntity.model = model
    }

    func invalidate() {
        isActive = false
        cadence.reset()
        liveness.setActive(false, at: CACurrentMediaTime())
        livenessTask?.cancel()
        livenessTask = nil
    }

    func setSceneActive(_ active: Bool) {
        guard isActive else { return }
        let now = CACurrentMediaTime()
        liveness.setActive(active, at: now)
        cadence.reset()
        watchdog = VisionStereoSubmissionWatchdog()
        livenessTask?.cancel()
        livenessTask = nil
        if active {
            startLivenessMonitor()
        }
    }

    func renderNextFrame() {
        let updateTime = CACurrentMediaTime()
        liveness.heartbeat(at: updateTime)
        guard isActive, liveness.isActive,
              let presentationTime = cadence.scheduledTime(for: updateTime),
              let clipPlan = VisionWindowStereoClipPlanner.makePlan() else { return }
        let request = VisionWindowStereoRenderRequest(
            targetPresentationTime: presentationTime,
            width: widthPixels,
            height: heightPixels
        ) { [weak self] in
            self?.makeFrame(presentationTime: presentationTime, clipPlan: clipPlan)
        }
        let disposition = renderFrame(request)
        guard watchdog.observe(disposition) == .failClosed else { return }

        switch disposition {
        case .busy:
            scheduleFailure(
                "The stereoscopic renderer stayed busy without submitting frames, so Eco "
                    + "returned to Comfort mode."
            )
        case .failed:
            scheduleFailure(
                "The native two-view renderer stopped, so Eco returned to Comfort mode."
            )
        case .skipped, .submitted:
            break
        }
    }

    private func makeFrame(
        presentationTime: CFTimeInterval,
        clipPlan: VisionWindowStereoClipPlan
    ) -> VisionWindowStereoRenderFrame? {
        guard isActive, let commandBuffer = commandQueue.makeCommandBuffer() else { return nil }
        commandBuffer.label = "Eco paired LowLevelTexture frame"
        let leftReplacement = leftTexture.replace(using: commandBuffer)
        let rightReplacement = rightTexture.replace(using: commandBuffer)
        guard Self.encodePairedClear(
            left: leftReplacement,
            right: rightReplacement,
            commandBuffer: commandBuffer
        ) else {
            commandBuffer.commit()
            return nil
        }
        return VisionWindowStereoRenderFrame(
            targetPresentationTime: presentationTime,
            width: widthPixels,
            height: heightPixels,
            commandBuffer: commandBuffer,
            left: .init(
                viewID: clipPlan.left.viewID,
                colorTexture: leftReplacement,
                depthTexture: leftDepth,
                clipFromGameClip: clipPlan.left.clipFromGameClip
            ),
            right: .init(
                viewID: clipPlan.right.viewID,
                colorTexture: rightReplacement,
                depthTexture: rightDepth,
                clipFromGameClip: clipPlan.right.clipFromGameClip
            )
        )
    }

    private func scheduleFailure(_ message: String) {
        guard !failureScheduled else { return }
        failureScheduled = true
        isActive = false
        liveness.setActive(false, at: CACurrentMediaTime())
        livenessTask?.cancel()
        livenessTask = nil
        GOALPadRenderSurface.shared.prepareStereoFallback()
        failClosed(message)
    }

    private func startLivenessMonitor() {
        livenessTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(50))
                } catch {
                    return
                }
                guard let self, self.isActive else { return }
                if self.liveness.hasTimedOut(at: CACurrentMediaTime()) {
                    self.scheduleFailure(
                        "The stereoscopic window stopped receiving rendering updates, so Eco "
                            + "returned to Comfort mode."
                    )
                    return
                }
            }
        }
    }

    private static func encodePairedClear(
        left: any MTLTexture,
        right: any MTLTexture,
        commandBuffer: any MTLCommandBuffer
    ) -> Bool {
        let pass = MTLRenderPassDescriptor()
        for (index, texture) in [left, right].enumerated() {
            pass.colorAttachments[index].texture = texture
            pass.colorAttachments[index].loadAction = .clear
            pass.colorAttachments[index].storeAction = .store
            pass.colorAttachments[index].clearColor = MTLClearColorMake(0, 0, 0, 1)
        }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            return false
        }
        encoder.label = "Eco stereo replacement initialization"
        encoder.endEncoding()
        return true
    }

    private static func makeDepthTexture(device: any MTLDevice,
                                         width: Int,
                                         height: Int,
                                         label: String) -> (any MTLTexture)? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float_stencil8,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget]
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = label
        return texture
    }
}

private enum VisionWindowStereoSurfaceError: LocalizedError {
    case metalUnavailable
    case depthTextureCreationFailed

    var errorDescription: String? {
        switch self {
        case .metalUnavailable: "Metal is unavailable."
        case .depthTextureCreationFailed: "The per-eye depth targets could not be created."
        }
    }
}
#endif
