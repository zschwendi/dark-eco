#if os(visionOS)
import SwiftUI

struct VisionPausedEcoOrnament: View {
    let openSettings: () -> Void

    var body: some View {
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
    }
}
#endif
