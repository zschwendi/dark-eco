#if os(visionOS)
import Foundation
import Observation

nonisolated enum VisionPresentationMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case comfortNormal
    case stereoscopic3D

    var id: String { rawValue }

    var title: String {
        switch self {
        case .comfortNormal: "Comfort / Normal"
        case .stereoscopic3D: "Stereoscopic 3D"
        }
    }
}

nonisolated enum VisionPresentationReadiness: Equatable, Sendable {
    case comfortWindow
    case stereoscopicWindow

    var isPlayable: Bool {
        true
    }
}

nonisolated struct VisionPresentationCapability: Equatable, Sendable {
    let mode: VisionPresentationMode
    let readiness: VisionPresentationReadiness
    let explanation: String
}

nonisolated enum VisionPresentationCapabilities {
    static let all: [VisionPresentationCapability] = [
        .init(
            mode: .comfortNormal,
            readiness: .comfortWindow,
            explanation: "Uses the existing monoscopic WindowGroup and game CAMetalLayer."
        ),
        .init(
            mode: .stereoscopic3D,
            readiness: .stereoscopicWindow,
            explanation: "Uses a RealityKit surface in the normal window with a fixed left/right "
                + "pair derived from Jak's existing game camera."
        ),
    ]

    static func capability(for mode: VisionPresentationMode) -> VisionPresentationCapability {
        all.first { $0.mode == mode }!
    }
}

nonisolated enum VisionPresentationDefaults {
    static func mode(for graphicsProfile: SettingsProfile,
                     stereoscopic3DEnabled: Bool = true) -> VisionPresentationMode {
        graphicsProfile == .modern && stereoscopic3DEnabled
            ? .stereoscopic3D
            : .comfortNormal
    }
}

@MainActor
@Observable
final class VisionPresentationCoordinator {
    enum SessionState: Equatable {
        case conventionalWindow
        case stereoscopicWindow
        case unavailable(mode: VisionPresentationMode, reason: String)
        case failed(String)
    }

    private(set) var selectedMode: VisionPresentationMode
    private(set) var activeGameMode: VisionPresentationMode = .comfortNormal
    private(set) var sessionState: SessionState = .conventionalWindow

    private var graphicsProfile: SettingsProfile
    private var stereoscopic3DEnabled: Bool
    private var stereoRendererAvailable = false
    private var stereoFailure: String?

    init(graphicsProfile: SettingsProfile = .modern,
         stereoscopic3DEnabled: Bool = true) {
        self.graphicsProfile = graphicsProfile
        self.stereoscopic3DEnabled = stereoscopic3DEnabled
        selectedMode = VisionPresentationDefaults.mode(
            for: graphicsProfile,
            stereoscopic3DEnabled: stereoscopic3DEnabled
        )
    }

    var selectedCapability: VisionPresentationCapability {
        VisionPresentationCapabilities.capability(for: selectedMode)
    }

    var isUsingConventionalWindowFallback: Bool {
        activeGameMode == .comfortNormal && selectedMode == .stereoscopic3D
    }

    var isStereoWindowActive: Bool {
        activeGameMode == .stereoscopic3D
    }

    func configure(graphicsProfile: SettingsProfile,
                   stereoscopic3DEnabled: Bool,
                   rendererAvailable: Bool) {
        let previousMode = selectedMode
        let rendererBecameAvailable = !stereoRendererAvailable && rendererAvailable
        self.graphicsProfile = graphicsProfile
        self.stereoscopic3DEnabled = stereoscopic3DEnabled
        stereoRendererAvailable = rendererAvailable
        selectedMode = VisionPresentationDefaults.mode(
            for: graphicsProfile,
            stereoscopic3DEnabled: stereoscopic3DEnabled
        )
        if selectedMode != previousMode || rendererBecameAvailable {
            stereoFailure = nil
        }
        reconcilePresentation()
    }

    func configure(graphicsProfile: SettingsProfile,
                   stereoscopic3DEnabled: Bool) {
        configure(
            graphicsProfile: graphicsProfile,
            stereoscopic3DEnabled: stereoscopic3DEnabled,
            rendererAvailable: stereoRendererAvailable
        )
    }

    func setStereoRendererAvailable(_ available: Bool) {
        configure(
            graphicsProfile: graphicsProfile,
            stereoscopic3DEnabled: stereoscopic3DEnabled,
            rendererAvailable: available
        )
    }

    func stereoSurfaceFailed(_ message: String) {
        failStereoWindow(message)
    }

    private func reconcilePresentation() {
        guard selectedMode == .stereoscopic3D else {
            activeGameMode = .comfortNormal
            sessionState = .conventionalWindow
            return
        }

        guard stereoRendererAvailable else {
            activeGameMode = .comfortNormal
            sessionState = .unavailable(
                mode: .stereoscopic3D,
                reason: "The native two-view game renderer is unavailable."
            )
            return
        }

        if let stereoFailure {
            activeGameMode = .comfortNormal
            sessionState = .failed(stereoFailure)
            return
        }

        activeGameMode = .stereoscopic3D
        sessionState = .stereoscopicWindow
    }

    private func failStereoWindow(_ message: String) {
        stereoFailure = message
        activeGameMode = .comfortNormal
        sessionState = .failed(message)
    }
}
#endif
