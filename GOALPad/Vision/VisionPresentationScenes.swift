#if os(visionOS)
import CompositorServices
import SwiftUI

struct VisionPresentationSessionBridge<Content: View>: View {
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    let coordinator: VisionPresentationCoordinator
    private let content: Content

    init(coordinator: VisionPresentationCoordinator,
         @ViewBuilder content: () -> Content) {
        self.coordinator = coordinator
        self.content = content()
    }

    var body: some View {
        content
            .environment(coordinator)
            .task(id: coordinator.sceneRequest?.id) {
                guard let request = coordinator.sceneRequest else { return }
                switch request.action {
                case .openHeadTracking:
                    let result = await openImmersiveSpace(
                        id: VisionPresentationMode.stereoscopic3D.sceneID
                    )
                    switch result {
                    case .opened:
                        coordinator.sceneRequestFinished(request, opened: true)
                    case .userCancelled:
                        coordinator.sceneRequestFinished(request, opened: false)
                    case .error:
                        coordinator.sceneRequestFinished(
                            request,
                            opened: false,
                            error: "visionOS could not open the head-tracking support space."
                        )
                    @unknown default:
                        coordinator.sceneRequestFinished(
                            request,
                            opened: false,
                            error: "visionOS returned an unknown immersive-space result."
                        )
                    }
                case .dismissHeadTracking:
                    await dismissImmersiveSpace()
                    coordinator.sceneRequestFinished(request, opened: false)
                }
            }
    }
}

struct GOALPadVisionSpatialScenes: Scene {
    let coordinator: VisionPresentationCoordinator

    var body: some Scene {
        // The mixed space exists only so the bounded window can query head pose relative to the
        // window. It never hosts game geometry or replaces the app's ordinary WindowGroup.
        ImmersiveSpace(id: VisionPresentationMode.stereoscopic3D.sceneID) {
            EmptyView()
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}

// Retained for deterministic renderer diagnostics only. GOALPadVisionSpatialScenes never declares
// this content, so the product cannot replace its bounded window with the synthetic compositor.
struct VisionStereoCompositorProofContent: CompositorContent {
    let coordinator: VisionPresentationCoordinator

    var body: some CompositorContent {
        CompositorLayer(configuration: self) { @MainActor layerRenderer in
            VisionStereoCompositorProofRenderer.start(layerRenderer, coordinator: coordinator)
        }
    }
}

extension VisionStereoCompositorProofContent: CompositorLayerConfiguration {
    func makeConfiguration(capabilities: LayerRenderer.Capabilities,
                           configuration: inout LayerRenderer.Configuration) {
        configuration.isFoveationEnabled = false
        configuration.colorUsage = [.renderTarget]
        configuration.depthUsage = [.renderTarget]
        let nearPlane = max(0.1, capabilities.supportedMinimumNearPlaneDistance)
        configuration.defaultDepthRange = SIMD2(max(100, nearPlane * 1_000), nearPlane)
        let supportedLayouts = capabilities.supportedLayouts(options: [])
        configuration.layout = supportedLayouts.contains(.dedicated)
            ? .dedicated
            : supportedLayouts.first ?? .dedicated
    }
}
#endif
