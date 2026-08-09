#if os(visionOS)
import Foundation
import Observation

nonisolated enum VisionPresentationMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case comfortNormal
    case stereoscopic3D
    case tabletopVolume
    case roomScaleWorld
    case firstPersonVR

    var id: String { rawValue }

    var title: String {
        switch self {
        case .comfortNormal: "Comfort / Normal"
        case .stereoscopic3D: "Stereoscopic 3D"
        case .tabletopVolume: "Tabletop / Volume"
        case .roomScaleWorld: "Room-scale World"
        case .firstPersonVR: "First-person VR"
        }
    }

    var sceneID: String {
        "eco.vision.\(rawValue)"
    }
}

nonisolated enum VisionPresentationReadiness: Equatable, Sendable {
    case comfortWindow
    case stereoscopicWindow
    case unavailable

    var isPlayable: Bool {
        switch self {
        case .comfortWindow, .stereoscopicWindow: true
        case .unavailable: false
        }
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
            explanation: "Uses a RealityKit surface in the normal window with a separate game "
                + "render target for each eye and head-relative camera transforms."
        ),
        .init(
            mode: .tabletopVolume,
            readiness: .unavailable,
            explanation: "The game renderer does not export a bounded RealityKit world."
        ),
        .init(
            mode: .roomScaleWorld,
            readiness: .unavailable,
            explanation: "Room-scale world anchoring, spatial culling, and room interaction are "
                + "not implemented."
        ),
        .init(
            mode: .firstPersonVR,
            readiness: .unavailable,
            explanation: "Gameplay-camera and head-pose separation plus explicit motion-comfort "
                + "behavior are not implemented."
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
        case openingHeadTracking
        case stereoscopicWindow
        case closingHeadTracking
        case unavailable(mode: VisionPresentationMode, reason: String)
        case failed(String)
    }

    enum DiagnosticProofState: Equatable {
        case idle
        case submitted(viewCount: Int)
        case failed(String)
    }

    struct SceneRequest: Equatable, Identifiable {
        enum Action: Equatable {
            case openHeadTracking
            case dismissHeadTracking
        }

        let id: UInt64
        let action: Action
    }

    private(set) var selectedMode: VisionPresentationMode
    private(set) var activeGameMode: VisionPresentationMode = .comfortNormal
    private(set) var sessionState: SessionState = .conventionalWindow
    private(set) var sceneRequest: SceneRequest?
    private(set) var diagnosticProofState: DiagnosticProofState = .idle

    private var graphicsProfile: SettingsProfile
    private var stereoscopic3DEnabled: Bool
    private var stereoRendererAvailable = false
    private var headTrackingSpaceIsOpen = false
    private var stereoFailure: String?
    private var nextRequestID: UInt64 = 0

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

    func sceneRequestFinished(_ request: SceneRequest, opened: Bool, error: String? = nil) {
        guard sceneRequest == request else { return }
        sceneRequest = nil

        if let error {
            headTrackingSpaceIsOpen = false
            if selectedMode == .stereoscopic3D && stereoRendererAvailable {
                failStereoWindow(error)
            } else {
                reconcilePresentation()
            }
            return
        }

        switch request.action {
        case .openHeadTracking:
            guard opened else {
                headTrackingSpaceIsOpen = false
                if selectedMode == .stereoscopic3D && stereoRendererAvailable {
                    failStereoWindow("visionOS did not open the head-tracking support space.")
                } else {
                    reconcilePresentation()
                }
                return
            }
            headTrackingSpaceIsOpen = true
        case .dismissHeadTracking:
            headTrackingSpaceIsOpen = false
        }
        reconcilePresentation()
    }

    func stereoSurfaceFailed(_ message: String) {
        failStereoWindow(message)
    }

    // The prior synthetic compositor renderer remains available only to focused diagnostics. No
    // product scene opens it, and its state cannot select or replace the bounded game window.
    func stereoProofSubmitted(viewCount: Int) {
        guard viewCount > 1 else { return }
        diagnosticProofState = .submitted(viewCount: viewCount)
    }

    func stereoProofStopped() {
        diagnosticProofState = .idle
    }

    func stereoProofFailed(_ message: String) {
        diagnosticProofState = .failed(message)
    }

    private func reconcilePresentation() {
        guard selectedMode == .stereoscopic3D else {
            activeGameMode = .comfortNormal
            if headTrackingSpaceIsOpen {
                sessionState = .closingHeadTracking
                enqueue(.dismissHeadTracking)
            } else if sceneRequest?.action == .openHeadTracking {
                // An already-issued open cannot be cancelled. Keep its identity so its eventual
                // completion can be followed immediately by a dismiss request.
                sessionState = .closingHeadTracking
            } else {
                sceneRequest = nil
                sessionState = .conventionalWindow
            }
            return
        }

        guard stereoRendererAvailable else {
            activeGameMode = .comfortNormal
            if headTrackingSpaceIsOpen {
                sessionState = .closingHeadTracking
                enqueue(.dismissHeadTracking)
            } else if sceneRequest?.action == .openHeadTracking {
                sessionState = .closingHeadTracking
            } else {
                sceneRequest = nil
                sessionState = .unavailable(
                    mode: .stereoscopic3D,
                    reason: "The native two-view game renderer is unavailable."
                )
            }
            return
        }

        if let stereoFailure {
            activeGameMode = .comfortNormal
            if headTrackingSpaceIsOpen {
                sessionState = .closingHeadTracking
                enqueue(.dismissHeadTracking)
            } else {
                sceneRequest = nil
                sessionState = .failed(stereoFailure)
            }
            return
        }

        if headTrackingSpaceIsOpen {
            sceneRequest = nil
            activeGameMode = .stereoscopic3D
            sessionState = .stereoscopicWindow
        } else if sceneRequest == nil {
            activeGameMode = .comfortNormal
            sessionState = .openingHeadTracking
            enqueue(.openHeadTracking)
        }
    }

    private func failStereoWindow(_ message: String) {
        stereoFailure = message
        activeGameMode = .comfortNormal
        if headTrackingSpaceIsOpen {
            sessionState = .closingHeadTracking
            enqueue(.dismissHeadTracking)
        } else {
            sceneRequest = nil
            sessionState = .failed(message)
        }
    }

    private func enqueue(_ action: SceneRequest.Action) {
        if sceneRequest?.action == action { return }
        nextRequestID &+= 1
        sceneRequest = SceneRequest(id: nextRequestID, action: action)
    }
}
#endif
