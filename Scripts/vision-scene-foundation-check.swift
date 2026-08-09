import QuartzCore
import SwiftUI

nonisolated enum SettingsProfile: Equatable, Sendable {
    case modern
    case classic
}

@MainActor
final class GOALPadRenderSurface {
    static let shared = GOALPadRenderSurface()

    func attach(_ layer: CAMetalLayer?) {}
    func setDrawableSize(_ size: CGSize) {}
}

struct ContentView: View {
    var body: some View { Color.clear }
}

nonisolated enum EcoTipTransactionObserver {
    static func run() async {}
}

@MainActor
struct GameCenterRootView<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View { content }
}

#if os(visionOS)
@MainActor
private func exerciseVisionPresentationFoundation() {
    let modes = VisionPresentationMode.allCases
    precondition(modes.count == 5)
    precondition(modes.map(\.title) == [
        "Comfort / Normal",
        "Stereoscopic 3D",
        "Tabletop / Volume",
        "Room-scale World",
        "First-person VR",
    ])

    let modern = VisionPresentationCoordinator(graphicsProfile: .modern)
    precondition(modern.selectedMode == .stereoscopic3D)
    precondition(modern.activeGameMode == .comfortNormal)
    precondition(modern.isUsingConventionalWindowFallback)
    precondition(modern.selectedCapability.readiness.isPlayable)
    precondition(modern.sessionState == .conventionalWindow)

    modern.configure(
        graphicsProfile: .modern,
        stereoscopic3DEnabled: true,
        rendererAvailable: true
    )
    precondition(modern.sessionState == .openingHeadTracking)
    guard let openRequest = modern.sceneRequest else {
        preconditionFailure("Modern stereo should request its head-tracking support space")
    }
    precondition(openRequest.action == .openHeadTracking)
    modern.sceneRequestFinished(openRequest, opened: true)
    precondition(modern.activeGameMode == .stereoscopic3D)
    precondition(modern.sessionState == .stereoscopicWindow)

    modern.stereoProofSubmitted(viewCount: 2)
    precondition(modern.diagnosticProofState == .submitted(viewCount: 2))
    precondition(modern.activeGameMode == .stereoscopic3D)

    modern.configure(graphicsProfile: .modern, stereoscopic3DEnabled: false)
    precondition(modern.activeGameMode == .comfortNormal)
    precondition(modern.sessionState == .closingHeadTracking)
    guard let dismissRequest = modern.sceneRequest else {
        preconditionFailure("Comfort should dismiss its head-tracking support space")
    }
    precondition(dismissRequest.action == .dismissHeadTracking)
    modern.sceneRequestFinished(dismissRequest, opened: false)
    precondition(modern.sessionState == .conventionalWindow)

    let toggledDuringOpen = VisionPresentationCoordinator(graphicsProfile: .modern)
    toggledDuringOpen.setStereoRendererAvailable(true)
    guard let pendingOpen = toggledDuringOpen.sceneRequest else {
        preconditionFailure("renderer readiness should request tracking")
    }
    toggledDuringOpen.configure(graphicsProfile: .modern, stereoscopic3DEnabled: false)
    precondition(toggledDuringOpen.sceneRequest == pendingOpen)
    toggledDuringOpen.sceneRequestFinished(pendingOpen, opened: true)
    precondition(toggledDuringOpen.sceneRequest?.action == .dismissHeadTracking)

    let classic = VisionPresentationCoordinator(graphicsProfile: .classic)
    precondition(classic.selectedMode == .comfortNormal)
    precondition(classic.selectedCapability.readiness.isPlayable)

    for mode in modes {
        precondition(VisionPresentationCapabilities.capability(for: mode).mode == mode)
    }
}
#endif
