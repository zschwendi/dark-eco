#if os(iOS)
import SwiftUI

struct TouchControlsGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    let gameTitle: TouchGameTitle

    var body: some View {
        NavigationStack {
            TouchControlsGuideView(gameTitle: gameTitle)
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
    let gameTitle: TouchGameTitle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                TouchControlsInfographic(gameTitle: gameTitle)

                VStack(spacing: 14) {
                    if gameTitle == .jak2 {
                        jak2GuideRows
                    } else {
                        jak1GuideRows
                    }
                    guideRow(symbol: .text("L"), title: "Movement")
                    guideRow(symbol: .text("R"), title: "Camera")
                }

                Text("Dark Eco also supports wireless gamepads for controller input.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(DarkEcoTheme.background)
        .navigationTitle(gameTitle == .jak2 ? "Jak II Touch Controls" : "Jak 1 Touch Controls")
    }

    @ViewBuilder
    private var jak1GuideRows: some View {
        guideRow(symbol: .systemImage("hand.draw"), title: "Swipe Actions",
                 detail: "Swipe anywhere on the right side\n- Up: Jump\n- Down: Crouch\n- Left: Punch\n- Right: Spin Kick")
        guideRow(symbol: .systemImage("flag.pattern.checkered.2.crossed"),
                 title: "Speeder Controls",
                 detail: "Swipe up and hold to accelerate. Swipe down to hop brake.")
    }

    @ViewBuilder
    private var jak2GuideRows: some View {
        guideRow(symbol: .systemImage("hand.draw"), title: "Action Swipes",
                 detail: "Swipe and hold on the right side\n- Up: Jump or accelerate\n- Down: Crouch or jetboard trick\n- Left: Attack or vehicle brake\n- Right: Attack or vehicle action")
        guideRow(symbol: .text("R1"), title: "Fire & Jetboard",
                 detail: "Tap the camera area to fire. Hold R1 for sustained fire or a jetboard spin.")
        guideRow(symbol: .text("R2"), title: "Jetboard & Vehicles",
                 detail: "Hold R2 to mount or dismount the jetboard and switch vehicle flight height.")
        guideRow(symbol: .text("R3"), title: "Look Around",
                 detail: "Tap Zoom to enter or leave first-person look-around.")
        guideRow(symbol: .text("↑↓←→"), title: "Weapons",
                 detail: "Use the colored wheel: red up, dark right, yellow down, blue left.")
        guideRow(symbol: .text("△"), title: "Game Prompts",
                 detail: "Tap the visible action for Talk, Use, Play, or vehicle entry. Triangle stays available while riding so you can exit.")
        guideRow(symbol: .systemImage("pause.fill"), title: "Menus",
                 detail: "Pause and save screens provide D-pad, Back, Confirm, Settings, and Resume controls.")
    }

    private enum GuideSymbol {
        case text(String)
        case systemImage(String)
    }

    private func guideRow(symbol: GuideSymbol, title: String, detail: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                switch symbol {
                case .text(let text):
                    Text(text)
                case .systemImage(let name):
                    Image(systemName: name)
                        .accessibilityHidden(true)
                }
            }
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(DarkEcoTheme.accent.opacity(0.38), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                if let detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TouchControlsInfographic: View {
    let gameTitle: TouchGameTitle

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
                    capsule(gameTitle == .jak2 ? "R2" : "STATS")
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
#endif
