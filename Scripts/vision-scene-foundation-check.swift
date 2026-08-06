import SwiftUI

struct ContentView: View {
    var body: some View { Color.clear }
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
    precondition(!modern.selectedCapability.readiness.isPlayable)

    let classic = VisionPresentationCoordinator(graphicsProfile: .classic)
    precondition(classic.selectedMode == .comfortNormal)
    precondition(classic.selectedCapability.readiness.isPlayable)

    for mode in modes {
        precondition(VisionPresentationCapabilities.capability(for: mode).mode == mode)
    }
}
#endif
