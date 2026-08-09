#if os(visionOS)
import SwiftUI

struct VisionControllerStatusOrnament: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var highlightLocation: CGFloat = -1

    var body: some View {
        label
            .foregroundStyle(labelForegroundStyle)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .glassBackgroundEffect()
            .allowsHitTesting(false)
            .accessibilityLabel("No controller detected.")
            .onAppear { updateShimmer() }
            .onChange(of: reduceMotion) { _, _ in updateShimmer() }
    }

    private var label: some View {
        Text("No controller detected.")
            .font(.headline.weight(.semibold))
    }

    private var labelForegroundStyle: LinearGradient {
        guard !reduceMotion else {
            return LinearGradient(
                colors: [.purple, .purple],
                startPoint: .leading,
                endPoint: .trailing
            )
        }

        return LinearGradient(
            colors: [.purple, .purple, .white.opacity(0.85), .purple, .purple],
            startPoint: UnitPoint(x: highlightLocation - 1, y: 0.5),
            endPoint: UnitPoint(x: highlightLocation + 1, y: 0.5)
        )
    }

    private func updateShimmer() {
        highlightLocation = -1
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
            highlightLocation = 1
        }
    }
}
#endif
