import SwiftUI

#if os(iOS)
struct TouchStickSettingsView: View {
    @Bindable var settings: PresentationSettings

    var body: some View {
        Form {
            Section("Movement Stick") {
                Toggle("Dynamic Left Stick", isOn: Binding(
                    get: { settings.dynamicLeftStick },
                    set: { settings.setDynamicLeftStick($0) }
                ))
                stickSizePicker("Size", control: .modernMovement)
                Text(settings.dynamicLeftStick
                     ? "Stick moves to wherever your finger is placed."
                     : "Uses the chosen fixed position.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Camera Stick") {
                stickSizePicker("Size", control: .modernCamera)
                Text("The camera stick uses a fixed position and the shared three-second control visibility.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Fixed Positions") {
                TouchStickPlacementEditor(settings: settings)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                Text(settings.dynamicLeftStick
                     ? "Drag the camera stick. Turn off Dynamic Left Stick to place the movement stick."
                     : "Drag either stick to choose its fixed starting position.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Restore Default Positions") {
                    settings.setTouchControlPosition(nil, for: .modernMovement)
                    settings.setTouchControlPosition(nil, for: .modernCamera)
                }
            }
        }
        .navigationTitle("Touch Sticks")
    }

    private func stickSizePicker(_ title: String,
                                 control: TouchLayoutControlID) -> some View {
        Picker(title, selection: Binding(
            get: { settings.jak1TouchLayout.stickSize(for: control) },
            set: { settings.setTouchStickSize($0, for: control) }
        )) {
            ForEach(TouchStickSize.allCases) { size in
                Text(size.title).tag(size)
            }
        }
        .pickerStyle(.segmented)
    }
}

private struct TouchStickPlacementEditor: View {
    @Bindable var settings: PresentationSettings
    @State private var draftLayout: TouchLayoutCustomization?

    private static let coordinateSpace = "TouchStickPlacementEditor"

    var body: some View {
        GeometryReader { proxy in
            let customization = draftLayout ?? settings.jak1TouchLayout
            let layout = ModernTouchLayout(size: proxy.size, customization: customization)

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.82))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)

                placementStick(label: "L", radius: layout.movementRadius,
                               knobSize: layout.movementKnobSize,
                               isEnabled: !settings.dynamicLeftStick)
                    .position(x: layout.movementArtworkFrame.midX,
                              y: layout.movementArtworkFrame.midY)
                    .gesture(placementGesture(for: .modernMovement,
                                              visualDiameter: layout.movementRadius * 2,
                                              safeBounds: layout.safeBounds))
                    .allowsHitTesting(!settings.dynamicLeftStick)
                    .opacity(settings.dynamicLeftStick ? 0.35 : 1)

                placementStick(label: "R", radius: layout.rightStickRadius,
                               knobSize: layout.rightStickKnobSize,
                               isEnabled: true)
                    .position(x: layout.rightStickArtworkFrame.midX,
                              y: layout.rightStickArtworkFrame.midY)
                    .gesture(placementGesture(for: .modernCamera,
                                              visualDiameter: layout.rightStickRadius * 2,
                                              safeBounds: layout.safeBounds))
            }
            .coordinateSpace(.named(Self.coordinateSpace))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Touch stick position preview")
    }

    private func placementStick(label: String, radius: CGFloat,
                                knobSize: CGFloat, isEnabled: Bool) -> some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.55))
                .overlay(Circle().strokeBorder(.white.opacity(isEnabled ? 0.55 : 0.28),
                                               lineWidth: 2))
            Circle()
                .fill(.white.opacity(isEnabled ? 0.78 : 0.38))
                .frame(width: knobSize, height: knobSize)
                .overlay {
                    Text(label)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.78))
                }
        }
        .frame(width: radius * 2, height: radius * 2)
        .contentShape(Circle())
        .accessibilityLabel(label == "L" ? "Movement stick position" : "Camera stick position")
    }

    private func placementGesture(for control: TouchLayoutControlID,
                                  visualDiameter: CGFloat,
                                  safeBounds: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpace))
            .onChanged { value in
                var layout = draftLayout ?? settings.jak1TouchLayout
                let position = TouchLayoutGeometry.normalizedPosition(
                    for: value.location,
                    visualSize: CGSize(width: visualDiameter, height: visualDiameter),
                    in: safeBounds)
                layout.setPosition(position, for: control)
                draftLayout = layout
            }
            .onEnded { _ in
                guard let position = draftLayout?.position(for: control) else {
                    draftLayout = nil
                    return
                }
                settings.setTouchControlPosition(position, for: control)
                draftLayout = nil
            }
    }
}
#endif
