import SwiftUI

struct TouchLayoutEditorView: View {
    @Bindable var settings: PresentationSettings
    @State private var profile: TouchLayoutProfile
    @State private var selectedControl: TouchLayoutControlID

    init(settings: PresentationSettings) {
        self.settings = settings
        let initialProfile: TouchLayoutProfile = settings.profile(for: .controls) == .modern
            ? .modern : .classic
        _profile = State(initialValue: initialProfile)
        _selectedControl = State(initialValue: TouchLayoutControlID.controls(
            for: initialProfile).first ?? .modernMovement)
    }

    var body: some View {
        Form {
            Section {
                Picker("Layout", selection: Binding(
                    get: { profile },
                    set: { newProfile in
                        profile = newProfile
                        selectedControl = TouchLayoutControlID.controls(for: newProfile).first
                            ?? .modernMovement
                    }
                )) {
                    ForEach(TouchLayoutProfile.allCases, id: \.self) { profile in
                        Text(profile.title).tag(profile)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Modern and Classic keep separate layouts. Changes apply immediately when "
                     + "that Controls profile is active.")
            }

            Section("Preview") {
                TouchLayoutEditorPreview(settings: settings,
                                         profile: profile,
                                         selectedControl: $selectedControl)
                    .frame(minHeight: 300)
                    .listRowInsets(EdgeInsets())
                Text(profile == .modern
                     ? "Movement and Action Gestures follow your touch by default. Drag either "
                        + "preview control to pin it."
                     : "Drag any active control. Classic intentionally exposes no separate "
                        + "L2 or R2 control.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Selected Control") {
                Picker("Control", selection: $selectedControl) {
                    ForEach(TouchLayoutControlID.controls(for: profile)) { control in
                        Text(control.title).tag(control)
                    }
                }

                if selectedControl == .modernActions {
                    ForEach(TouchGestureDirection.remappableCases, id: \.self) { direction in
                        Picker("Swipe \(direction.title)", selection: Binding(
                            get: { settings.jak1TouchLayout.gestureAction(for: direction) },
                            set: { settings.setTouchGestureAction($0, for: direction) }
                        )) {
                            ForEach(TouchGestureActionMapping.remappableActions, id: \.self) {
                                action in
                                Text(action.title).tag(action)
                            }
                        }
                    }
                    LabeledContent("Swipe Down", value: "Crouch (Fixed)")
                } else if !selectedControl.compatibleActions.isEmpty {
                    Picker("Action", selection: Binding(
                        get: {
                            settings.jak1TouchLayout.action(for: selectedControl)
                                ?? selectedControl.defaultAction ?? .cross
                        },
                        set: { settings.setTouchControlAction($0, for: selectedControl) }
                    )) {
                        ForEach(selectedControl.compatibleActions, id: \.self) { action in
                            Text(action.title).tag(action)
                        }
                    }
                }

                LabeledContent("Opacity", value: "\(opacityPercent)%")
                Slider(value: Binding(
                    get: { Double(opacityPercent) },
                    set: {
                        settings.setTouchControlOpacityPercent(Int($0.rounded()),
                                                               for: selectedControl)
                    }
                ), in: 25...100, step: 5)
                .accessibilityLabel("\(selectedControl.title) Opacity")
                .accessibilityValue("\(opacityPercent) percent")

                LabeledContent("Size", value: "\(sizePercent)%")
                Slider(value: Binding(
                    get: { Double(sizePercent) },
                    set: {
                        settings.setTouchControlSizePercent(Int($0.rounded()),
                                                            for: selectedControl)
                    }
                ), in: 65...160, step: 5)
                .accessibilityLabel("\(selectedControl.title) Size")
                .accessibilityValue("\(sizePercent) percent")

                LabeledContent("Position", value: positionSummary)
                if settings.jak1TouchLayout.position(for: selectedControl) != nil {
                    Button("Use Default Position") {
                        settings.setTouchControlPosition(nil, for: selectedControl)
                    }
                }
                Button("Reset \(selectedControl.title)") {
                    settings.resetTouchControl(selectedControl)
                }
            }

            Section {
                Button("Reset Layout", role: .destructive) {
                    settings.resetTouchLayout()
                }
            } footer: {
                Text("Controls Restore Defaults and Reset Jak 1 Settings also reset both touch "
                     + "layouts.")
            }
        }
        .navigationTitle("Touch Layout")
    }

    private var opacityPercent: Int {
        Int((settings.jak1TouchLayout.opacity(for: selectedControl) * 100).rounded())
    }

    private var sizePercent: Int {
        Int((settings.jak1TouchLayout.scale(for: selectedControl) * 100).rounded())
    }

    private var positionSummary: String {
        guard let position = settings.jak1TouchLayout.position(for: selectedControl) else {
            return "Default"
        }
        return "\(Int((position.x * 100).rounded()))%, "
            + "\(Int((position.y * 100).rounded()))%"
    }
}

private struct TouchLayoutEditorPreview: View {
    @Bindable var settings: PresentationSettings
    let profile: TouchLayoutProfile
    @Binding var selectedControl: TouchLayoutControlID

    private static let space = "TouchLayoutEditorPreview"

    var body: some View {
        GeometryReader { proxy in
            let insets = TouchSafeAreaInsets(top: proxy.safeAreaInsets.top + 12,
                                             leading: proxy.safeAreaInsets.leading + 12,
                                             bottom: proxy.safeAreaInsets.bottom + 12,
                                             trailing: proxy.safeAreaInsets.trailing + 12)
            let modernLayout = ModernTouchLayout(size: proxy.size, safeAreaInsets: insets,
                                                 customization: settings.jak1TouchLayout)
            let classicLayout = ClassicTouchLayout(size: proxy.size, safeAreaInsets: insets,
                                                   customization: settings.jak1TouchLayout)
            let layoutSafeBounds = profile == .modern
                ? modernLayout.safeBounds : classicLayout.safeBounds

            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(.black.opacity(0.86))
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(.secondary.opacity(0.35))
                Rectangle()
                    .stroke(.secondary.opacity(0.14), style: StrokeStyle(dash: [5, 5]))
                    .frame(width: layoutSafeBounds.width, height: layoutSafeBounds.height)
                    .position(x: layoutSafeBounds.midX, y: layoutSafeBounds.midY)

                ForEach(visualOrder) { control in
                    if let visualFrame = frame(for: control,
                                               modern: modernLayout,
                                               classic: classicLayout) {
                        let hitFrame = TouchLayoutGeometry.minimumHitFrame(
                            for: visualFrame, in: layoutSafeBounds)
                        previewControl(control, visualFrame: visualFrame, hitFrame: hitFrame,
                                       safeBounds: layoutSafeBounds)
                    }
                }
            }
            .coordinateSpace(.named(Self.space))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(profile.title) touch layout preview")
    }

    private var visualOrder: [TouchLayoutControlID] {
        TouchLayoutControlID.visualOrder(for: profile)
    }

    private func frame(for control: TouchLayoutControlID,
                       modern: ModernTouchLayout,
                       classic: ClassicTouchLayout) -> CGRect? {
        profile == .modern ? modern.frame(for: control) : classic.frame(for: control)
    }

    private func previewControl(_ control: TouchLayoutControlID,
                                visualFrame: CGRect,
                                hitFrame: CGRect,
                                safeBounds: CGRect) -> some View {
        Button {
            selectedControl = control
        } label: {
            ZStack {
                TouchLayoutPreviewShape(control: control)
                    .fill(.white.opacity(control == selectedControl ? 0.30 : 0.16))
                TouchLayoutPreviewShape(control: control)
                    .strokeBorder(control == selectedControl ? .yellow : .white.opacity(0.55),
                                  lineWidth: control == selectedControl ? 3 : 1.5)
                Text(previewLabel(for: control))
                    .font(.system(size: min(15, max(9, visualFrame.height * 0.25)),
                                  weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(4)
            }
            .frame(width: visualFrame.width, height: visualFrame.height)
            .frame(width: hitFrame.width, height: hitFrame.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(x: hitFrame.midX, y: hitFrame.midY)
        .opacity(settings.jak1TouchLayout.opacity(for: control))
        .simultaneousGesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
                .onChanged { value in
                    selectedControl = control
                    setPosition(value.location, for: control,
                                visualSize: visualFrame.size, safeBounds: safeBounds)
                }
        )
        .accessibilityLabel(control.title)
        .accessibilityValue(accessibilityValue(for: control))
        .accessibilityHint("Drag to reposition. Double tap to select.")
        .accessibilityAction(named: "Move Left") {
            nudge(control, visualFrame: visualFrame, safeBounds: safeBounds,
                  dx: -0.05, dy: 0)
        }
        .accessibilityAction(named: "Move Right") {
            nudge(control, visualFrame: visualFrame, safeBounds: safeBounds,
                  dx: 0.05, dy: 0)
        }
        .accessibilityAction(named: "Move Up") {
            nudge(control, visualFrame: visualFrame, safeBounds: safeBounds,
                  dx: 0, dy: -0.05)
        }
        .accessibilityAction(named: "Move Down") {
            nudge(control, visualFrame: visualFrame, safeBounds: safeBounds,
                  dx: 0, dy: 0.05)
        }
        .accessibilityAction(named: "Use Default Position") {
            settings.setTouchControlPosition(nil, for: control)
        }
    }

    private func setPosition(_ centre: CGPoint,
                             for control: TouchLayoutControlID,
                             visualSize: CGSize,
                             safeBounds: CGRect) {
        let position = TouchLayoutGeometry.normalizedPosition(for: centre,
                                                              visualSize: visualSize,
                                                              in: safeBounds)
        settings.setTouchControlPosition(position, for: control)
    }

    private func nudge(_ control: TouchLayoutControlID,
                       visualFrame: CGRect,
                       safeBounds: CGRect,
                       dx: CGFloat,
                       dy: CGFloat) {
        setPosition(CGPoint(x: visualFrame.midX + dx * safeBounds.width,
                            y: visualFrame.midY + dy * safeBounds.height),
                    for: control, visualSize: visualFrame.size, safeBounds: safeBounds)
    }

    private func previewLabel(for control: TouchLayoutControlID) -> String {
        if control == .modernActions { return "SWIPE" }
        return settings.jak1TouchLayout.action(for: control)?.shortLabel ?? control.title
    }

    private func accessibilityValue(for control: TouchLayoutControlID) -> String {
        let action = control == .modernActions
            ? "four remappable swipe actions"
            : settings.jak1TouchLayout.action(for: control)?.title ?? control.title
        guard let position = settings.jak1TouchLayout.position(for: control) else {
            return "\(action), default position"
        }
        return "\(action), position \(Int((position.x * 100).rounded())) percent horizontal, "
            + "\(Int((position.y * 100).rounded())) percent vertical"
    }
}

private struct TouchLayoutPreviewShape: InsettableShape {
    let control: TouchLayoutControlID
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        switch control {
        case .modernMovement, .modernCamera, .classicMovement, .classicCamera,
             .classicDpadUp, .classicDpadDown, .classicDpadLeft, .classicDpadRight,
             .classicTriangle, .classicSquare, .classicCircle, .classicCross:
            return Circle().path(in: insetRect)
        default:
            return RoundedRectangle(cornerRadius: min(16, insetRect.height / 2))
                .path(in: insetRect)
        }
    }

    func inset(by amount: CGFloat) -> Self {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}
