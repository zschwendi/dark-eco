import SwiftUI

struct TouchControlsGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TouchControlsGuideView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .preferredColorScheme(.dark)
        .tint(DarkEcoTheme.accent)
    }
}

struct TouchControlsGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                TouchControlsInfographic()

                VStack(spacing: 14) {
                    guideRow(symbol: "L", title: "Move",
                             detail: "Touch anywhere on the left side and drag.")
                    guideRow(symbol: "R", title: "Camera",
                             detail: "Drag the right stick to look around.")
                    guideRow(symbol: "⌕", title: "Zoom and Fire",
                             detail: "Use the round Zoom button. While zoomed in, tap the open right side or swipe left to fire.")
                    guideRow(symbol: "↑", title: "Jump or Accelerate",
                             detail: "Swipe up on the right side. On a vehicle, pull back down while holding to brake or drift.")
                    guideRow(symbol: "←", title: "Punch",
                             detail: "Swipe left on the right side.")
                    guideRow(symbol: "→", title: "Spin or Interact",
                             detail: "Swipe right on the right side.")
                    guideRow(symbol: "↓", title: "Crouch",
                             detail: "Swipe down and hold. Continue up to jump or left to punch while crouched.")
                    guideRow(symbol: "◇", title: "Contextual Actions",
                             detail: "When the game asks for a specific face button, its touch target appears automatically.")
                }

                Text("The Zoom, Stats, Pause, and contextual controls appear when they are available. A connected controller and touch can be used together.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(DarkEcoTheme.background)
        .navigationTitle("Touch Controls")
    }

    private func guideRow(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(symbol)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(DarkEcoTheme.accent.opacity(0.38), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TouchControlsInfographic: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let movementDiameter = min(108, width * 0.25)
            let cameraDiameter = movementDiameter * 76 / 108

            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(colors: [.black, DarkEcoTheme.surface],
                                       startPoint: .top,
                                       endPoint: .bottom)
                    )
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(DarkEcoTheme.accent.opacity(0.55), lineWidth: 1)

                controlStick(label: "L", diameter: movementDiameter,
                             knobDiameter: movementDiameter * 66 / 108,
                             outerFillOpacity: 0.22, outerStrokeOpacity: 0.32,
                             outerLineWidth: 2, knobFillOpacity: 0.56,
                             knobStrokeOpacity: 0.86, knobLineWidth: 1.5)
                    .position(x: movementDiameter * 0.75,
                              y: proxy.size.height - movementDiameter * 0.72)

                VStack(spacing: 6) {
                    Text("↑")
                    HStack(spacing: 24) {
                        Text("←")
                        Text("→")
                    }
                    Text("↓")
                }
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
                .position(x: width * 0.73, y: proxy.size.height * 0.36)

                controlStick(label: "R", diameter: cameraDiameter,
                             knobDiameter: cameraDiameter * 32 / 76,
                             outerFillOpacity: 0.42, outerStrokeOpacity: 0.35,
                             outerLineWidth: 1, knobFillOpacity: 0.8,
                             knobStrokeOpacity: 0.7, knobLineWidth: 1)
                    .position(x: width - cameraDiameter * 0.75,
                              y: proxy.size.height - cameraDiameter * 0.72)

                HStack(spacing: 12) {
                    capsule("STATS")
                    capsule("PAUSE")
                }
                .position(x: width / 2, y: proxy.size.height - 30)
            }
        }
        .frame(height: 230)
        .accessibilityHidden(true)
    }

    private func controlStick(label: String, diameter: CGFloat, knobDiameter: CGFloat,
                              outerFillOpacity: Double, outerStrokeOpacity: Double,
                              outerLineWidth: CGFloat, knobFillOpacity: Double,
                              knobStrokeOpacity: Double, knobLineWidth: CGFloat) -> some View {
        ZStack {
            Circle().fill(.black.opacity(outerFillOpacity))
            Circle().strokeBorder(.white.opacity(outerStrokeOpacity), lineWidth: outerLineWidth)
            Circle()
                .fill(.white.opacity(knobFillOpacity))
                .overlay(Circle().strokeBorder(.white.opacity(knobStrokeOpacity),
                                                lineWidth: knobLineWidth))
                .frame(width: knobDiameter, height: knobDiameter)
                .overlay {
                    Text(label)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(label == "L" ? 0.82 : 0.68))
                }
        }
        .frame(width: diameter, height: diameter)
    }

    private func capsule(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(1)
            .foregroundStyle(.white.opacity(0.82))
            .frame(width: 68, height: 34)
            .background(.black.opacity(0.5), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
    }
}
