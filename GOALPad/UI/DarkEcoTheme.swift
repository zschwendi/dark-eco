import SwiftUI

/// Shared presentation tokens for Eco-owned screens. The rendered game remains untouched.
enum DarkEcoTheme {
    static let background = Color(red: 0.035, green: 0.018, blue: 0.065)
    static let surface = Color(red: 0.105, green: 0.055, blue: 0.16)
    static let raisedSurface = Color(red: 0.16, green: 0.08, blue: 0.24)
    static let accent = Color(red: 0.62, green: 0.43, blue: 1.0)
    static let accentGlow = Color(red: 0.42, green: 0.82, blue: 0.95)
    static let success = Color(red: 0.45, green: 0.9, blue: 0.67)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.35)
    static let danger = Color(red: 1.0, green: 0.48, blue: 0.58)

    static func panelFill(reduceTransparency: Bool) -> Color {
        reduceTransparency ? raisedSurface : raisedSurface.opacity(0.9)
    }

    static func border(reduceTransparency: Bool) -> Color {
        accent.opacity(reduceTransparency ? 0.72 : 0.5)
    }
}

struct DarkEcoPanel<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(DarkEcoTheme.panelFill(reduceTransparency: reduceTransparency),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(DarkEcoTheme.border(reduceTransparency: reduceTransparency),
                            lineWidth: 1)
            }
    }
}
