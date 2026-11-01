#if os(visionOS) && GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE
import ARKit
import SwiftUI

struct VisionMotionControlsGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    let input: ControllerInput

    var body: some View {
        NavigationStack {
            VisionMotionControlsGuideView(input: input)
        }
        .tint(DarkEcoTheme.accent)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Label("Close", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Close Motion Controls")

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.regularMaterial)
        }
    }
}

struct VisionMotionControlsGuideView: View {
    let input: ControllerInput

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let availabilityMessage {
                    Label(availabilityMessage, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Text("Motion is optional. Default Sense buttons are shown below.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                VStack(spacing: 14) {
                    guideRow(symbol: "□", buttonName: "Square", title: "Punch",
                             detail: "Jab either controller forward.")
                    guideRow(symbol: "○", buttonName: "Circle", title: "Spin Kick",
                             detail: "Move either controller about an inch sideways, then straight back.")
                    guideRow(symbol: "✕", buttonName: "X", title: "Jump",
                             detail: "Lift both controllers together.")
                    guideRow(symbol: "✕", buttonName: "X", title: "Double Jump",
                             detail: "Lower both, then lift them together again while Jak is in the air.")
                }

                Text("Rest your arms and use the buttons whenever you like. When motion is "
                    + "available, you can use it during Jak 1 gameplay in either the game "
                    + "window or Immersive mode.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(DarkEcoTheme.background)
        .navigationTitle("Motion Controls")
    }

    private var availabilityMessage: String? {
        if !input.hasSenseControllers {
            return "Connect your Sense controllers to play with motion."
        }
        if !AccessoryTrackingProvider.isSupported {
            return "Motion isn't available right now. The buttons work as usual."
        }
        return nil
    }

    private func guideRow(symbol: String, buttonName: String, title: String,
                          detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(symbol)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(DarkEcoTheme.accent.opacity(0.38), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Or press \(buttonName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A one-time, non-blocking pointer to the guide shown when Sense controllers first join Jak 1
/// gameplay. It never pauses the game.
struct VisionSenseMotionHint: View {
    let showMoves: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Try Sense motion controls", systemImage: "hand.wave")
                .font(.headline)
            Text("Jab to punch, swing gently to spin, lift both to jump. Buttons always work too.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Show Moves", action: showMoves)
                    .buttonStyle(.borderedProminent)
                Button("Got It", action: dismiss)
                    .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .frame(maxWidth: 440, alignment: .leading)
        .glassBackgroundEffect()
    }
}
#endif
