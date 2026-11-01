#if os(visionOS) && GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE
import SwiftUI

/// A compact entry and exit control for the opt-in immersive presentation.
/// Opening remains attempt-bound so a stale result cannot affect a newer space.
struct VisionImmersiveModeControl: View {
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    let session: GameSession
    private let coordinator = VisionImmersiveProofCoordinator.shared
    @State private var failureMessage: String?

    var body: some View {
        Button(action: toggle) {
            Image(systemName: isReturningToWindow
                  ? "arrow.down.right.and.arrow.up.left"
                  : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 42, height: 42)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassBackgroundEffect(in: Circle())
        .disabled(!isEnabled)
        .accessibilityLabel(isReturningToWindow ? "Return to Window" : "Enter Immersive")
        .accessibilityHint(accessibilityHint)
        .onChange(of: coordinator.phase, initial: true) { _, phase in
            if case .failed(let message) = phase { failureMessage = message }
        }
        .alert("Immersive Mode", isPresented: Binding(
            get: { failureMessage != nil },
            set: { if !$0 { failureMessage = nil } }
        )) {
            Button("OK") { failureMessage = nil }
        } message: {
            Text(failureMessage ?? "")
        }
    }

    private var isReturningToWindow: Bool {
        switch coordinator.phase {
        case .opening, .presenting, .closing:
            true
        case .closed, .failed:
            false
        }
    }

    private var isEnabled: Bool {
        switch coordinator.phase {
        case .opening, .presenting:
            true
        case .closed, .failed:
            coordinator.canOpen(for: session)
        case .closing:
            false
        }
    }

    private var accessibilityHint: String {
        switch coordinator.phase {
        case .opening, .presenting:
            "Returns gameplay to the Dark Eco window."
        case .closing:
            "Dark Eco is returning gameplay to the window."
        case .closed, .failed:
            "Opens the running Jak 1 game in full immersion."
        }
    }

    private func toggle() {
        switch coordinator.phase {
        case .opening, .presenting:
            coordinator.close(reason: .userToggle)
        case .closed, .failed:
            open()
        case .closing:
            break
        }
    }

    private func open() {
        guard session.isRunning, session.title == .jak1,
              coordinator.canOpen(for: session),
              let attempt = coordinator.prepareToOpen(session: session) else { return }
        Task {
            let result: VisionImmersiveProofLifecycle.OpenResult =
                switch await openImmersiveSpace(
                    id: VisionImmersiveProofCoordinator.spaceID,
                    value: attempt
                ) {
                case .opened:
                    .opened
                case .userCancelled:
                    .cancelled
                case .error:
                    .failed("visionOS could not open the immersive space.")
                @unknown default:
                    .failed("visionOS returned an unknown immersive space result.")
                }
            coordinator.openFinished(attempt: attempt, result: result)
        }
    }
}
#endif
