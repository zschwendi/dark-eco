#if os(visionOS)
import CoreGraphics
import Metal
import QuartzCore
import RealityKit
import SwiftUI
import UIKit

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
    let left: VisionWindowStereoRenderTarget
    let right: VisionWindowStereoRenderTarget
}

/// The handler owns one synchronous game tick and its fixed two-view render. Only `rendered` means
/// both renderer command buffers completed and the borrowed textures are ready for paired
/// RealityKit presentation. A skipped tick is expected while the game is not ready or produces no
/// render chain; Swift never retains or copies the native DMA chain.
nonisolated enum VisionWindowStereoFrameDisposition: Equatable, Sendable {
    case skipped
    case rendered
    case failed
}

typealias VisionWindowStereoFrameHandler = @Sendable @MainActor (
    VisionWindowStereoRenderFrame
) -> VisionWindowStereoFrameDisposition

@MainActor
struct VisionWindowStereoSurfaceView: View {
    fileprivate struct Configuration: Hashable {
        let widthPixels: Int
        let heightPixels: Int
        let widthMeters: Float
        let heightMeters: Float
    }

    @Environment(\.displayScale) private var displayScale
    @Environment(\.physicalMetrics) private var physicalMetrics

    let renderFrame: VisionWindowStereoFrameHandler

    var body: some View {
        GeometryReader3D { proxy in
            let configuration = Configuration(
                widthPixels: pixelDimension(proxy.size.width),
                heightPixels: pixelDimension(proxy.size.height),
                widthMeters: meterDimension(proxy.size.width),
                heightMeters: meterDimension(proxy.size.height)
            )

            VisionWindowStereoRealitySurface(
                configuration: configuration,
                renderFrame: renderFrame
            )
            .id(configuration)
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
    @State private var resources: VisionWindowStereoResources?

    var body: some View {
        ZStack {
            RealityView { content in
                do {
                    let resources = try await VisionWindowStereoResources.make(
                        widthPixels: configuration.widthPixels,
                        heightPixels: configuration.heightPixels,
                        widthMeters: configuration.widthMeters,
                        heightMeters: configuration.heightMeters
                    )
                    content.add(resources.surfaceEntity)
                    self.resources = resources
                } catch {
                    deferStereoSurfaceFailure(
                        "The stereoscopic window could not start, so Eco returned to Comfort "
                            + "mode: \(error.localizedDescription)"
                    )
                }
            }
            .frame(depth: 0)

            VisionWindowStereoFrameClock { presentationTime in
                drawFrame(at: presentationTime)
            }
        }
        .onDisappear {
            resources = nil
        }
    }

    private func drawFrame(at presentationTime: CFTimeInterval) {
        let disposition = renderNextFrame(at: presentationTime)
        guard disposition == .failed else { return }
        deferStereoSurfaceFailure(
            "The native two-view renderer stopped, so Eco returned to Comfort mode."
        )
    }

    private func renderNextFrame(
        at presentationTime: CFTimeInterval
    ) -> VisionWindowStereoFrameDisposition {
        guard let resources,
              let clipPlan = VisionWindowStereoClipPlanner.makePlan(),
              let drawablePair = resources.nextDrawablePair() else {
            return .skipped
        }

        let frame = VisionWindowStereoRenderFrame(
            targetPresentationTime: presentationTime,
            width: configuration.widthPixels,
            height: configuration.heightPixels,
            left: .init(
                viewID: clipPlan.left.viewID,
                colorTexture: drawablePair.left.texture,
                depthTexture: resources.leftDepth,
                clipFromGameClip: clipPlan.left.clipFromGameClip
            ),
            right: .init(
                viewID: clipPlan.right.viewID,
                colorTexture: drawablePair.right.texture,
                depthTexture: resources.rightDepth,
                clipFromGameClip: clipPlan.right.clipFromGameClip
            )
        )

        let disposition = renderFrame(frame)
        guard disposition == .rendered else { return disposition }
        drawablePair.left.presentOnSceneUpdate()
        drawablePair.right.presentOnSceneUpdate()
        return .rendered
    }

    private func deferStereoSurfaceFailure(_ message: String) {
        Task { @MainActor in
            await Task.yield()
            coordinator.stereoSurfaceFailed(message)
        }
    }
}

@MainActor
private final class VisionWindowStereoResources {
    struct DrawablePair {
        let left: TextureResource.Drawable
        let right: TextureResource.Drawable
    }

    let surfaceEntity: ModelEntity
    let leftDepth: any MTLTexture
    let rightDepth: any MTLTexture

    private let leftQueue: TextureResource.DrawableQueue
    private let rightQueue: TextureResource.DrawableQueue
    private let leftResource: TextureResource
    private let rightResource: TextureResource

    private init(surfaceEntity: ModelEntity,
                 leftDepth: any MTLTexture,
                 rightDepth: any MTLTexture,
                 leftQueue: TextureResource.DrawableQueue,
                 rightQueue: TextureResource.DrawableQueue,
                 leftResource: TextureResource,
                 rightResource: TextureResource) {
        self.surfaceEntity = surfaceEntity
        self.leftDepth = leftDepth
        self.rightDepth = rightDepth
        self.leftQueue = leftQueue
        self.rightQueue = rightQueue
        self.leftResource = leftResource
        self.rightResource = rightResource
    }

    static func make(widthPixels: Int,
                     heightPixels: Int,
                     widthMeters: Float,
                     heightMeters: Float) async throws -> VisionWindowStereoResources {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw VisionWindowStereoSurfaceError.metalUnavailable
        }

        let leftQueue = try makeQueue(width: widthPixels, height: heightPixels)
        let rightQueue = try makeQueue(width: widthPixels, height: heightPixels)
        let placeholder = try makePlaceholderImage()
        let options = TextureResource.CreateOptions(semantic: .color, mipmapsMode: .none)
        let leftResource = try await TextureResource(
            image: placeholder,
            withName: "EcoStereoLeft",
            options: options
        )
        let rightResource = try await TextureResource(
            image: placeholder,
            withName: "EcoStereoRight",
            options: options
        )
        leftResource.replace(withDrawables: leftQueue)
        rightResource.replace(withDrawables: rightQueue)

        var material = try await ShaderGraphMaterial(
            named: "/Root/Material",
            from: "VisionStereoWindowMaterial",
            in: .main
        )
        try material.setParameter(name: "leftEye", value: .textureResource(leftResource))
        try material.setParameter(name: "rightEye", value: .textureResource(rightResource))

        let surface = ModelEntity(
            mesh: .generatePlane(width: widthMeters, height: heightMeters),
            materials: [material]
        )
        surface.name = "Eco stereoscopic game surface"

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

        return VisionWindowStereoResources(
            surfaceEntity: surface,
            leftDepth: leftDepth,
            rightDepth: rightDepth,
            leftQueue: leftQueue,
            rightQueue: rightQueue,
            leftResource: leftResource,
            rightResource: rightResource
        )
    }

    func nextDrawablePair() -> DrawablePair? {
        guard let left = try? leftQueue.nextDrawable(),
              let right = try? rightQueue.nextDrawable() else {
            return nil
        }
        return DrawablePair(left: left, right: right)
    }

    private static func makeQueue(width: Int,
                                  height: Int) throws -> TextureResource.DrawableQueue {
        let descriptor = TextureResource.DrawableQueue.Descriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            usage: [.renderTarget, .shaderRead],
            mipmapsMode: .none
        )
        let queue = try TextureResource.DrawableQueue(descriptor)
        queue.allowsNextDrawableTimeout = true
        return queue
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

    private static func makePlaceholderImage() throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw VisionWindowStereoSurfaceError.placeholderCreationFailed
        }
        return image
    }
}

private enum VisionWindowStereoSurfaceError: LocalizedError {
    case metalUnavailable
    case depthTextureCreationFailed
    case placeholderCreationFailed

    var errorDescription: String? {
        switch self {
        case .metalUnavailable: "Metal is unavailable."
        case .depthTextureCreationFailed: "The per-eye depth targets could not be created."
        case .placeholderCreationFailed: "The dynamic RealityKit textures could not be created."
        }
    }
}

private struct VisionWindowStereoFrameClock: UIViewRepresentable {
    let onFrame: (CFTimeInterval) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = FrameClockView()
        view.onFrame = onFrame
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        (view as? FrameClockView)?.onFrame = onFrame
    }

    private final class FrameClockView: UIView {
        var onFrame: ((CFTimeInterval) -> Void)?
        private var displayLink: CADisplayLink?
        private var observesSceneLifecycle = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                stopObservingSceneLifecycle()
                stopDisplayLink()
                return
            }
            startObservingSceneLifecycle()
            if window?.windowScene?.activationState == .foregroundActive {
                startDisplayLink()
            }
        }

        private func startDisplayLink() {
            guard displayLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(step(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: 60,
                maximum: 60,
                preferred: 60
            )
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        private func stopDisplayLink() {
            displayLink?.invalidate()
            displayLink = nil
        }

        private func startObservingSceneLifecycle() {
            guard !observesSceneLifecycle else { return }
            let center = NotificationCenter.default
            center.addObserver(
                self,
                selector: #selector(sceneWillDeactivate(_:)),
                name: UIScene.willDeactivateNotification,
                object: nil
            )
            center.addObserver(
                self,
                selector: #selector(sceneDidActivate(_:)),
                name: UIScene.didActivateNotification,
                object: nil
            )
            observesSceneLifecycle = true
        }

        private func stopObservingSceneLifecycle() {
            guard observesSceneLifecycle else { return }
            NotificationCenter.default.removeObserver(self)
            observesSceneLifecycle = false
        }

        private func belongsToCurrentScene(_ notification: Notification) -> Bool {
            guard let scene = notification.object as? UIScene,
                  let windowScene = window?.windowScene else {
                return false
            }
            return scene === windowScene
        }

        @objc private func sceneWillDeactivate(_ notification: Notification) {
            guard belongsToCurrentScene(notification) else { return }
            stopDisplayLink()
        }

        @objc private func sceneDidActivate(_ notification: Notification) {
            guard belongsToCurrentScene(notification), window != nil else { return }
            startDisplayLink()
        }

        @objc private func step(_ link: CADisplayLink) {
            onFrame?(link.targetTimestamp)
        }
    }
}
#endif
