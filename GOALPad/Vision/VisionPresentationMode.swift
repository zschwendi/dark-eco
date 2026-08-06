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
    case playableWindow
    case syntheticCompositorProof
    case unavailable

    var isPlayable: Bool {
        self == .playableWindow
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
            readiness: .playableWindow,
            explanation: "Uses the existing monoscopic WindowGroup and game CAMetalLayer."
        ),
        .init(
            mode: .stereoscopic3D,
            readiness: .syntheticCompositorProof,
            explanation: "The compositor proof renders one synthetic geometry snapshot through "
                + "tracked per-view transforms and target mappings; the game renderer is not "
                + "attached."
        ),
        .init(
            mode: .tabletopVolume,
            readiness: .unavailable,
            explanation: "The game renderer does not yet export bounded world geometry or a "
                + "viewer camera to RealityKit."
        ),
        .init(
            mode: .roomScaleWorld,
            readiness: .unavailable,
            explanation: "The renderer lacks a simulation-once/render-many snapshot, external "
                + "views, world anchoring, and spatial culling coverage."
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
    static func mode(for graphicsProfile: SettingsProfile) -> VisionPresentationMode {
        graphicsProfile == .modern ? .stereoscopic3D : .comfortNormal
    }
}

@MainActor
@Observable
final class VisionPresentationCoordinator {
    enum SessionState: Equatable {
        case conventionalWindow
        case openingStereoProof
        case syntheticStereoProof(viewCount: Int)
        case closingStereoProof
        case unavailable(mode: VisionPresentationMode, reason: String)
        case failed(String)
    }

    struct SceneRequest: Equatable, Identifiable {
        enum Action: Equatable {
            case openStereoProof
            case dismissStereoProof
        }

        let id: UInt64
        let action: Action
    }

    private(set) var selectedMode: VisionPresentationMode
    private(set) var activeGameMode: VisionPresentationMode = .comfortNormal
    private(set) var sessionState: SessionState = .conventionalWindow
    private(set) var sceneRequest: SceneRequest?

    private var nextRequestID: UInt64 = 0
    private var stereoProofIsOpen = false

    init(graphicsProfile: SettingsProfile = .modern) {
        selectedMode = VisionPresentationDefaults.mode(for: graphicsProfile)
    }

    var selectedCapability: VisionPresentationCapability {
        VisionPresentationCapabilities.capability(for: selectedMode)
    }

    var isUsingConventionalWindowFallback: Bool {
        activeGameMode == .comfortNormal && selectedMode != .comfortNormal
    }

    func select(_ mode: VisionPresentationMode) {
        selectedMode = mode
    }

    /// Called by future visionOS UI after the user explicitly asks to enter the selected mode.
    /// Unavailable game modes remain in the conventional window; only the isolated compositor
    /// proof can currently open an immersive scene.
    func requestSelectedPresentation() {
        let capability = selectedCapability
        switch capability.readiness {
        case .playableWindow:
            if isStereoProofSessionActive {
                sessionState = .closingStereoProof
                enqueue(.dismissStereoProof)
            } else {
                activeGameMode = .comfortNormal
                sessionState = .conventionalWindow
            }
        case .syntheticCompositorProof:
            guard !isStereoProofSessionActive else { return }
            sessionState = .openingStereoProof
            enqueue(.openStereoProof)
        case .unavailable:
            activeGameMode = .comfortNormal
            if isStereoProofSessionActive {
                sessionState = .closingStereoProof
                enqueue(.dismissStereoProof)
            } else {
                sessionState = .unavailable(mode: selectedMode, reason: capability.explanation)
            }
        }
    }

    func sceneRequestFinished(_ request: SceneRequest, opened: Bool, error: String? = nil) {
        guard sceneRequest == request else { return }
        sceneRequest = nil
        if let error {
            activeGameMode = .comfortNormal
            sessionState = .failed(error)
        } else if request.action == .openStereoProof && opened {
            stereoProofIsOpen = true
        } else if request.action == .dismissStereoProof || !opened {
            stereoProofIsOpen = false
            activeGameMode = .comfortNormal
            sessionState = .conventionalWindow
        }
    }

    func stereoProofSubmitted(viewCount: Int) {
        guard viewCount > 1 else { return }
        activeGameMode = .comfortNormal
        sessionState = .syntheticStereoProof(viewCount: viewCount)
    }

    func stereoProofStopped() {
        stereoProofIsOpen = false
        activeGameMode = .comfortNormal
        sceneRequest = nil
        sessionState = .conventionalWindow
    }

    func stereoProofFailed(_ message: String) {
        activeGameMode = .comfortNormal
        sceneRequest = nil
        sessionState = .failed(message)
    }

    private func enqueue(_ action: SceneRequest.Action) {
        nextRequestID &+= 1
        sceneRequest = SceneRequest(id: nextRequestID, action: action)
    }

    private var isStereoProofSessionActive: Bool {
        if stereoProofIsOpen { return true }
        switch sessionState {
        case .openingStereoProof, .syntheticStereoProof, .closingStereoProof:
            return true
        case .conventionalWindow, .unavailable, .failed:
            return false
        }
    }
}
#endif
