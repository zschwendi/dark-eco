import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// A dynamic movement stick, bottom-right R stick, and swipe gestures over the game surface.
struct TouchControlsView: View {
    let controls: TouchControls
    /// Physical-controller activity hides the artwork until the screen is touched again.
    let isSuppressed: Bool

    fileprivate static let space = "GOALPadTouchControls"
    private static let pillWidth: CGFloat = 82

    private var isVisible: Bool {
        controls.isEngaged && (!isSuppressed || !controls.touches.isEmpty)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                #if canImport(UIKit)
                TouchSurface(controls: controls)
                #endif

                artwork(in: proxy.size)
                    .allowsHitTesting(false)
                    .opacity(isVisible ? 1 : 0)
                    .animation(.easeOut(duration: 0.16), value: isVisible)
            }
        }
        .coordinateSpace(.named(Self.space))
        .ignoresSafeArea()
    }

    private func artwork(in size: CGSize) -> some View {
        let edge = max(28, min(size.width, size.height) * 0.06)

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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, edge)
                .padding(.bottom, edge)
        }
    }

    private func pill(_ button: TouchButton) -> some View {
        let isDown = controls.isPillDown(button)
        return Text(button.glyph)
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

/// Face-button gestures remain available in open space without producing camera axes.
private struct GestureRose: View {
    let gesture: TouchControls.Tracked

    private static let reach = TouchControls.swipeDistance + 24

    var body: some View {
        ZStack {
            chip(.cross, isLit: gesture.swiped == .cross || gesture.jumpTriggered)
                .position(x: gesture.origin.x, y: gesture.origin.y - Self.reach)
            chip(.square, isLit: gesture.swiped == .square)
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
    private let knobSize: CGFloat = 66

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
        .frame(width: TouchControls.movementRadius * 2,
               height: TouchControls.movementRadius * 2)
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
    }
}

private final class TouchSurfaceView: UIView {
    var controls: TouchControls?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            controls?.began(ObjectIdentifier(touch), at: touch.location(in: self),
                            in: bounds.size, at: touch.timestamp)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            controls?.moved(ObjectIdentifier(touch), to: touch.location(in: self))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            controls?.ended(ObjectIdentifier(touch), at: touch.timestamp)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            controls?.cancelled(ObjectIdentifier(touch))
        }
    }
}

#endif
