#if os(visionOS)
import SwiftUI

struct VisionControllerStatusOrnament: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerOffset: CGFloat = -180

    var body: some View {
        label
            .foregroundStyle(.purple)
            .overlay {
                LinearGradient(
                    colors: [.clear, .white.opacity(0.9), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: 64)
                .rotationEffect(.degrees(18))
                .offset(x: reduceMotion ? 0 : shimmerOffset)
                .mask { label }
            }
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

    private func updateShimmer() {
        shimmerOffset = -180
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
            shimmerOffset = 180
        }
    }
}
#endif
