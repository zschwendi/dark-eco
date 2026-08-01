import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// The on-screen controls: it feeds every raw touch to `TouchControls` and draws what the fingers
/// are doing.
///
/// Nothing is drawn while nothing is being touched. The touch surface itself is never faded - a
/// `UIView` with `alpha` at zero stops being touchable - so only the artwork above it fades, and a
/// blind press on a pill still lands.
struct TouchControlsView: View {
    let controls: TouchControls
    /// True while a physical controller is being used, which keeps the artwork off the screen. The
    /// touches still work: putting the controller down and reaching for the screen brings it back.
    let isSuppressed: Bool

    private static let space = "GOALPadTouchControls"

    private var isVisible: Bool { controls.isEngaged && !isSuppressed }

    var body: some View {
        ZStack {
            #if canImport(UIKit)
            TouchSurface(controls: controls)
            #endif

            ZStack {
                if let stick = controls.stick {
                    PadRing(touch: stick, radius: TouchControls.deflectionRadius, isCamera: false)
                }
                if let camera = controls.camera {
                    PadRing(touch: camera, radius: TouchControls.cameraRadius, isCamera: true)
                }
                ForEach(controls.gestures) { gesture in
                    GestureRose(gesture: gesture, tapButton: controls.repeatButton)
                }
                pills
            }
            .allowsHitTesting(false)
            .opacity(isVisible ? 1 : 0)
            .animation(.easeOut(duration: 0.16), value: isVisible)
        }
        .coordinateSpace(.named(Self.space))
        .ignoresSafeArea()
    }

    private var pills: some View {
        HStack(spacing: 20) {
            pill(.select)
            pill(.start)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 30)
    }

    private func pill(_ button: TouchButton) -> some View {
        let isDown = controls.isPillDown(button)
        return Text(button.glyph)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .tracking(1.6)
            .foregroundStyle(.white.opacity(isDown ? 1 : 0.8))
            .padding(.horizontal, 24)
            .padding(.vertical, 11)
            .background(Capsule().fill(.black.opacity(isDown ? 0.7 : 0.4)))
            .overlay(Capsule().strokeBorder(.white.opacity(isDown ? 0.9 : 0.35), lineWidth: 1))
            .onGeometryChange(for: CGRect.self) { proxy in
                // A little wider than it looks, because a thumb is wider than a pill.
                proxy.frame(in: .named(Self.space)).insetBy(dx: -10, dy: -12)
            } action: {
                controls.setPillFrame(button, $0)
            }
    }
}

/// A stick: the ring sits where the finger landed and never moves, and the knob follows the finger
/// out to the ring, which is exactly where full deflection is.
///
/// The camera's is drawn dashed and smaller-knobbed, because it is a rate - leaving the knob out
/// there keeps the camera turning - and should not be mistaken for the movement stick.
private struct PadRing: View {
    let touch: TouchControls.Tracked
    let radius: CGFloat
    let isCamera: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(isCamera ? 0.14 : 0.22))
                .overlay {
                    Circle().strokeBorder(.white.opacity(isCamera ? 0.24 : 0.3),
                                          style: StrokeStyle(lineWidth: 2,
                                                             dash: isCamera ? [10, 9] : []))
                }
                .frame(width: radius * 2, height: radius * 2)
                .position(touch.origin)
            Circle()
                .fill(.white.opacity(isCamera ? 0.32 : 0.55))
                .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5))
                .frame(width: isCamera ? 48 : 66, height: isCamera ? 48 : 66)
                .position(knob)
        }
    }

    private var knob: CGPoint {
        var dx = touch.point.x - touch.origin.x
        var dy = touch.point.y - touch.origin.y
        let length = (dx * dx + dy * dy).squareRoot()
        if length > radius {
            dx *= radius / length
            dy *= radius / length
        }
        return CGPoint(x: touch.origin.x + dx, y: touch.origin.y + dy)
    }
}

/// What a finger on the right half can do, drawn where it landed: the three swipes at the distance
/// they are recognised at, and in the middle the button a tap would repeat.
private struct GestureRose: View {
    let gesture: TouchControls.Tracked
    let tapButton: TouchButton

    private static let reach = TouchControls.swipeDistance + 24

    var body: some View {
        ZStack {
            chip(tapButton, size: 40, isLit: gesture.swiped == nil)
                .position(gesture.origin)
            chip(.cross, size: 46, isLit: gesture.swiped == .cross)
                .position(x: gesture.origin.x, y: gesture.origin.y - Self.reach)
            chip(.square, size: 46, isLit: gesture.swiped == .square)
                .position(x: gesture.origin.x - Self.reach, y: gesture.origin.y)
            chip(.circle, size: 46, isLit: gesture.swiped == .circle)
                .position(x: gesture.origin.x + Self.reach, y: gesture.origin.y)
        }
    }

    private func chip(_ button: TouchButton, size: CGFloat, isLit: Bool) -> some View {
        Text(button.glyph)
            .font(.system(size: size * 0.44, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(isLit ? 1 : 0.7))
            .frame(width: size, height: size)
            .background(Circle().fill(.black.opacity(isLit ? 0.7 : 0.3)))
            .overlay(Circle().strokeBorder(.white.opacity(isLit ? 0.9 : 0.3), lineWidth: 1.5))
    }
}

#if canImport(UIKit)

/// The one thing that sees raw touches. Every finger is tracked by identity, so the stick and a
/// right-half gesture run at the same time - moving and jumping at once is the whole point.
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
