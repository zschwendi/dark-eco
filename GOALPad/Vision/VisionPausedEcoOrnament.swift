#if os(visionOS)
import SwiftUI

struct VisionPausedEcoOrnament: View {
    #if GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE
    let session: GameSession
    #endif
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassBackgroundEffect(in: Circle())
            .accessibilityLabel("Settings")

            #if GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE
            if session.isRunning && session.title == .jak1 {
                VisionImmersiveModeControl(session: session)
            }
            #endif
        }
    }
}
#endif
