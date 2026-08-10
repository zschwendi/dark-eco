#if os(visionOS)
import SwiftUI

struct VisionPausedEcoOrnament: View {
    let openSettings: () -> Void

    var body: some View {
        Button(action: openSettings) {
            HStack(spacing: 6) {
                Image(systemName: "gearshape")
                Text("ECO")
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassBackgroundEffect(in: Capsule())
        .accessibilityLabel("Eco Settings")
    }
}
#endif
