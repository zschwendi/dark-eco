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
    func prepareStereoFallback() {}
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
    precondition(modes.count == 2)
    precondition(modes.map(\.title) == [
        "Comfort / Normal",
        "Stereoscopic 3D",
    ])

    let modern = VisionPresentationCoordinator(graphicsProfile: .modern)
    precondition(modern.selectedMode == .stereoscopic3D)
    precondition(modern.activeGameMode == .comfortNormal)
    precondition(modern.isUsingConventionalWindowFallback)
    precondition(modern.selectedCapability.readiness.isPlayable)
    precondition(modern.sessionState == .conventionalWindow)

    // GameSession advertises the renderer only after boot completes.
    modern.setStereoRendererAvailable(false)
    precondition(modern.activeGameMode == .comfortNormal)
    precondition(modern.sessionState != .stereoscopicWindow)

    // The observed readiness transition activates stereo without recreating the view.
    modern.configure(
        graphicsProfile: .modern,
        stereoscopic3DEnabled: true,
        rendererAvailable: true
    )
    precondition(modern.activeGameMode == .stereoscopic3D)
    precondition(modern.sessionState == .stereoscopicWindow)

    modern.stereoSurfaceFailed("fixed-pair renderer failed")
    precondition(modern.activeGameMode == .comfortNormal)
    precondition(modern.sessionState == .failed("fixed-pair renderer failed"))

    modern.configure(graphicsProfile: .modern, stereoscopic3DEnabled: false)
    precondition(modern.activeGameMode == .comfortNormal)
    precondition(modern.sessionState == .conventionalWindow)

    modern.configure(
        graphicsProfile: .modern,
        stereoscopic3DEnabled: true,
        rendererAvailable: true
    )
    precondition(modern.activeGameMode == .stereoscopic3D)
    precondition(modern.sessionState == .stereoscopicWindow)

    modern.setStereoRendererAvailable(false)
    precondition(modern.activeGameMode == .comfortNormal)
    precondition(modern.sessionState == .unavailable(
        mode: .stereoscopic3D,
        reason: "The native two-view game renderer is unavailable."
    ))

    let classic = VisionPresentationCoordinator(graphicsProfile: .classic)
    precondition(classic.selectedMode == .comfortNormal)
    precondition(classic.selectedCapability.readiness.isPlayable)

    for mode in modes {
        precondition(VisionPresentationCapabilities.capability(for: mode).mode == mode)
    }
}
#endif
