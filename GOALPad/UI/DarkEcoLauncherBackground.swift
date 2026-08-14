import SwiftUI

struct DarkEcoLauncherBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animationStart = Date.now

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
                Rectangle()
                    .fill(DarkEcoTheme.background)
                    .colorEffect(
                        ShaderLibrary.default.darkEcoLauncherBackground(
                            .float2(proxy.size),
                            .float(elapsedTime(at: timeline.date))
                        )
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func elapsedTime(at date: Date) -> Float {
        guard !reduceMotion else { return 0 }
        return Float(max(date.timeIntervalSince(animationStart), 0))
    }
}
