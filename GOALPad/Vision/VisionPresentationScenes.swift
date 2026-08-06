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
                case .openStereoProof:
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
                            error: "visionOS could not open the synthetic stereo compositor proof."
                        )
                    @unknown default:
                        coordinator.sceneRequestFinished(
                            request,
                            opened: false,
                            error: "visionOS returned an unknown immersive-space result."
                        )
                    }
                case .dismissStereoProof:
                    await dismissImmersiveSpace()
                    coordinator.sceneRequestFinished(request, opened: false)
                }
            }
    }
}

struct GOALPadVisionSpatialScenes: Scene {
    let coordinator: VisionPresentationCoordinator

    var body: some Scene {
        WindowGroup(id: VisionPresentationMode.tabletopVolume.sceneID) {
            VisionUnavailablePresentationView(mode: .tabletopVolume)
                .environment(coordinator)
        }
        .windowStyle(.volumetric)

        ImmersiveSpace(id: VisionPresentationMode.stereoscopic3D.sceneID) {
            VisionStereoCompositorProofContent(coordinator: coordinator)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)

        ImmersiveSpace(id: VisionPresentationMode.roomScaleWorld.sceneID) {
            VisionUnavailablePresentationView(mode: .roomScaleWorld)
                .environment(coordinator)
        }
        .immersionStyle(selection: .constant(.progressive), in: .progressive)

        ImmersiveSpace(id: VisionPresentationMode.firstPersonVR.sceneID) {
            VisionUnavailablePresentationView(mode: .firstPersonVR)
                .environment(coordinator)
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }
}

private struct VisionUnavailablePresentationView: View {
    let mode: VisionPresentationMode

    private var capability: VisionPresentationCapability {
        VisionPresentationCapabilities.capability(for: mode)
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(mode.title)
                .font(.title2.weight(.semibold))
            Text("Unavailable")
                .font(.headline)
            Text(capability.explanation)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: 520)
        .glassBackgroundEffect()
    }
}

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
        let supportedLayouts = capabilities.supportedLayouts(options: [])
        configuration.layout = supportedLayouts.contains(.dedicated)
            ? .dedicated
            : supportedLayouts.first ?? .dedicated
    }
}
#endif
