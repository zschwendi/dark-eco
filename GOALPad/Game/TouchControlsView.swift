import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// The selected Modern gesture layer or Classic DualShock-like overlay over the game surface.
struct TouchControlsView: View {
    let controls: TouchControls
    /// Active physical input hides the artwork until the screen is touched again.
    let isSuppressed: Bool
    let isNativeMenuOpen: Bool

    fileprivate static let space = "GOALPadTouchControls"
    private static let pillWidth: CGFloat = 82

    private var isVisible: Bool {
        TouchControls.artworkIsVisible(isEngaged: controls.isEngaged,
                                       isSuppressed: isSuppressed,
                                       hasTouches: !controls.touches.isEmpty,
                                       isNativeMenuOpen: isNativeMenuOpen)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                #if canImport(UIKit)
                TouchSurface(controls: controls)
                #endif

                artwork(in: proxy)
                    .allowsHitTesting(false)
                    .opacity(isVisible ? 1 : 0)
                    .animation(.easeOut(duration: 0.16), value: isVisible)
            }
        }
        .coordinateSpace(.named(Self.space))
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func artwork(in proxy: GeometryProxy) -> some View {
        switch controls.style {
        case .modern:
            modernArtwork(in: proxy)
        case .classic:
            classicArtwork(in: proxy)
        }
    }

    private func modernArtwork(in proxy: GeometryProxy) -> some View {
        let proxyInsets = TouchSafeAreaInsets(top: proxy.safeAreaInsets.top,
                                              leading: proxy.safeAreaInsets.leading,
                                              bottom: proxy.safeAreaInsets.bottom,
                                              trailing: proxy.safeAreaInsets.trailing)
        let insets = controls.surfaceSafeAreaInsets == .zero
            ? proxyInsets
            : controls.surfaceSafeAreaInsets
        let layout = ModernTouchLayout(
            size: proxy.size,
            safeAreaInsets: insets)

        return ZStack {
            if let stick = controls.stick {
                MovementStickArtwork(touch: stick)
            }

            ForEach(controls.gestures) { gesture in
                GestureRose(gesture: gesture)
            }

            HStack(spacing: 20) {
                pill(.select)
                pill(.start)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 30)

            RightStickControl(controls: controls)
                .position(x: layout.rightStickArtworkFrame.midX,
                          y: layout.rightStickArtworkFrame.midY)
        }
        .frame(width: proxy.size.width, height: proxy.size.height)
    }

    private func classicArtwork(in proxy: GeometryProxy) -> some View {
        let proxyInsets = TouchSafeAreaInsets(top: proxy.safeAreaInsets.top,
                                              leading: proxy.safeAreaInsets.leading,
                                              bottom: proxy.safeAreaInsets.bottom,
                                              trailing: proxy.safeAreaInsets.trailing)
        let insets = controls.surfaceSafeAreaInsets == .zero
            ? proxyInsets
            : controls.surfaceSafeAreaInsets
        let layout = ClassicTouchLayout(size: proxy.size, safeAreaInsets: insets)

        return ZStack {
            ClassicStickControl(controls: controls, side: .left,
                                frame: layout.leftStickFrame, radius: layout.stickRadius)
            ClassicStickControl(controls: controls, side: .right,
                                frame: layout.rightStickFrame, radius: layout.stickRadius)

            ForEach(ClassicTouchLayout.buttons, id: \.self) { button in
                if let frame = layout.frame(for: button) {
                    ClassicButtonControl(button: button,
                                         label: TouchControls.artworkLabel(
                                            for: button,
                                            isNativeMenuOpen: isNativeMenuOpen),
                                         isDown: controls.isPillDown(button), frame: frame)
                }
            }
        }
    }

    private func pill(_ button: TouchButton) -> some View {
        let isDown = controls.isPillDown(button)
        return Text(TouchControls.artworkLabel(for: button,
                                               isNativeMenuOpen: isNativeMenuOpen))
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(.white.opacity(isDown ? 1 : 0.8))
            .frame(width: Self.pillWidth, height: 42)
            .background(Capsule().fill(.black.opacity(isDown ? 0.72 : 0.42)))
            .overlay(Capsule().strokeBorder(.white.opacity(isDown ? 0.9 : 0.35), lineWidth: 1))
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(Self.space)).insetBy(dx: -10, dy: -12)
            } action: {
                controls.setPillFrame(button, $0)
            }
    }
}

private struct ClassicButtonControl: View {
    let button: TouchButton
    let label: String
    let isDown: Bool
    let frame: CGRect

    private var isWide: Bool {
        switch button {
        case .select, .start, .leftShoulder, .rightShoulder:
            true
        default:
            false
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: min(16, frame.height * 0.42), weight: .semibold,
                          design: .rounded))
            .tracking(isWide ? 0.8 : 0)
            .foregroundStyle(.white.opacity(isDown ? 1 : 0.82))
            .frame(width: frame.width, height: frame.height)
            .background {
                if isWide {
                    Capsule().fill(.black.opacity(isDown ? 0.74 : 0.42))
                } else {
                    Circle().fill(.black.opacity(isDown ? 0.74 : 0.42))
                }
            }
            .overlay {
                if isWide {
                    Capsule().strokeBorder(.white.opacity(isDown ? 0.92 : 0.38), lineWidth: 1.5)
                } else {
                    Circle().strokeBorder(.white.opacity(isDown ? 0.92 : 0.38), lineWidth: 1.5)
                }
            }
            .position(x: frame.midX, y: frame.midY)
    }
}

private struct ClassicStickControl: View {
    enum Side {
        case left
        case right
    }

    let controls: TouchControls
    let side: Side
    let frame: CGRect
    let radius: CGFloat

    private var touch: TouchControls.Tracked? {
        side == .left ? controls.stick : controls.rightStick
    }

    private var label: String {
        side == .left ? "L" : "R"
    }

    private var knobSize: CGFloat {
        frame.width * 0.48
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.25))
                .overlay(Circle().strokeBorder(.white.opacity(0.38), lineWidth: 2))
            Circle()
                .fill(.white.opacity(touch == nil ? 0.48 : 0.68))
                .overlay(Circle().strokeBorder(.white.opacity(0.86), lineWidth: 1.5))
                .frame(width: knobSize, height: knobSize)
                .overlay {
                    Text(label)
                        .font(.system(size: max(10, knobSize * 0.28), weight: .bold,
                                      design: .rounded))
                        .foregroundStyle(.black.opacity(0.7))
                }
                .offset(knobOffset)
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
    }

    private var knobOffset: CGSize {
        guard let touch else { return .zero }
        let push = TouchControls.classicStickDeflection(from: touch.origin, to: touch.point,
                                                        radius: radius)
        let travel = radius - knobSize / 2
        return CGSize(width: push.x * travel, height: push.y * travel)
    }
}

/// Face-button gestures remain available in open space without producing camera axes.
private struct GestureRose: View {
    let gesture: TouchControls.Tracked

    private static let reach = TouchControls.swipeDistance + 24

    var body: some View {
        ZStack {
            chip(.cross, isLit: gesture.swiped == .cross || gesture.jumpTriggered)
                .position(x: gesture.origin.x, y: gesture.origin.y - Self.reach)
            chip(.square, isLit: gesture.swiped == .square || gesture.punchTriggered)
                .position(x: gesture.origin.x - Self.reach, y: gesture.origin.y)
            chip(.circle, isLit: gesture.swiped == .circle)
                .position(x: gesture.origin.x + Self.reach, y: gesture.origin.y)
            chip(.crouch, isLit: gesture.swiped == .crouch)
                .position(x: gesture.origin.x, y: gesture.origin.y + Self.reach)
        }
    }

    private func chip(_ button: TouchButton, isLit: Bool) -> some View {
        Text(button.glyph)
            .font(.system(size: 20, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(isLit ? 1 : 0.7))
            .frame(width: 46, height: 46)
            .background(Circle().fill(.black.opacity(isLit ? 0.7 : 0.3)))
            .overlay(Circle().strokeBorder(.white.opacity(isLit ? 0.9 : 0.3), lineWidth: 1.5))
    }
}

/// The movement ring appears under the first finger that lands on the left half.
private struct MovementStickArtwork: View {
    let touch: TouchControls.Tracked
    private let knobSize = ModernTouchLayout.movementKnobSize

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.22))
                .overlay(Circle().strokeBorder(.white.opacity(0.32), lineWidth: 2))
            Circle()
                .fill(.white.opacity(0.56))
                .overlay(Circle().strokeBorder(.white.opacity(0.86), lineWidth: 1.5))
                .frame(width: knobSize, height: knobSize)
                .offset(knobOffset)
        }
        .frame(width: ModernTouchLayout.movementVisualRadius * 2,
               height: ModernTouchLayout.movementVisualRadius * 2)
        .position(touch.origin)
    }

    private var knobOffset: CGSize {
        let push = TouchControls.movementDeflection(from: touch.origin, to: touch.point)
        let travel = TouchControls.movementRadius - knobSize / 2
        return CGSize(width: push.x * travel, height: push.y * travel)
    }
}

private struct RightStickControl: View {
    let controls: TouchControls

    private let knobSize: CGFloat = 32

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.24))
                .overlay(Circle().strokeBorder(.yellow.opacity(0.55), lineWidth: 2))
            Circle()
                .fill(.yellow.opacity(0.72))
                .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1))
                .frame(width: knobSize, height: knobSize)
                .overlay {
                    Text("R")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.72))
                }
                .offset(knobOffset)
        }
        .frame(width: TouchControls.rightStickRadius * 2,
               height: TouchControls.rightStickRadius * 2)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(TouchControlsView.space)).insetBy(dx: -16, dy: -16)
        } action: {
            controls.setRightStickFrame($0)
        }
    }

    private var knobOffset: CGSize {
        guard let touch = controls.rightStick else { return .zero }
        let push = TouchControls.rightStickDeflection(from: touch.origin, to: touch.point)
        let travel = TouchControls.rightStickRadius - knobSize / 2
        return CGSize(width: push.x * travel, height: push.y * travel)
    }
}

#if canImport(UIKit)

/// The one view that sees raw multitouch and hands each finger to the state machine by identity.
private struct TouchSurface: UIViewRepresentable {
    let controls: TouchControls

    func makeUIView(context: Context) -> TouchSurfaceView {
        let view = TouchSurfaceView()
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        view.controls = controls
        return view
    }

    func updateUIView(_ view: TouchSurfaceView, context: Context) {
        view.controls = controls
        view.updateSafeAreaInsets()
    }
}

private final class TouchSurfaceView: UIView {
    var controls: TouchControls?
    private let haptics = TouchHapticDriver()

    override func layoutSubviews() {
        super.layoutSubviews()
        updateSafeAreaInsets()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        updateSafeAreaInsets()
    }

    func updateSafeAreaInsets() {
        controls?.setSurfaceSafeAreaInsets(
            TouchSafeAreaInsets(top: safeAreaInsets.top,
                                leading: safeAreaInsets.left,
                                bottom: safeAreaInsets.bottom,
                                trailing: safeAreaInsets.right))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let insets = controls?.surfaceSafeAreaInsets ?? .zero
        for touch in touches {
            controls?.began(ObjectIdentifier(touch), at: touch.location(in: self),
                            in: bounds.size, safeAreaInsets: insets, at: touch.timestamp)
        }
        flushHaptics()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            controls?.moved(ObjectIdentifier(touch), to: touch.location(in: self))
        }
        flushHaptics()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            controls?.ended(ObjectIdentifier(touch), at: touch.timestamp)
        }
        flushHaptics()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            controls?.cancelled(ObjectIdentifier(touch))
        }
        flushHaptics()
    }

    private func flushHaptics() {
        haptics.play(controls?.consumeHapticEvents() ?? [])
    }
}

/// Maps touch-owned actions to device feedback; iPhone/iPad feedback has no controller-side locality.
private final class TouchHapticDriver {
    private let button = UIImpactFeedbackGenerator(style: .light)
    private let gesture = UIImpactFeedbackGenerator(style: .medium)
    private let stick = UISelectionFeedbackGenerator()

    func play(_ events: [TouchHapticEvent]) {
        for event in events {
            switch event {
            case .button:
                button.impactOccurred(intensity: 0.75)
                button.prepare()
            case .gesture:
                gesture.impactOccurred(intensity: 0.9)
                gesture.prepare()
            case .stickEngaged:
                stick.selectionChanged()
                stick.prepare()
            }
        }
    }
}

#endif
