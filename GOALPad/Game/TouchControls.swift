import Foundation
import OSLog

nonisolated private let touchLog = Logger(subsystem: "com.zephyrstudiosllc.GOALPad",
                                          category: "Touch")

/// The PS2 buttons the on-screen controls drive.
enum TouchButton: CaseIterable {
    case cross, square, circle, start, select
    case up, down, left, right

    var bit: GOALPadButton {
        switch self {
        case .cross: .cross
        case .square: .square
        case .circle: .circle
        case .start: .start
        case .select: .select
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        }
    }

    var glyph: String {
        switch self {
        case .cross: "✕"
        case .square: "□"
        case .circle: "○"
        case .start: "START"
        case .select: "SELECT"
        case .up: "↑"
        case .down: "↓"
        case .left: "←"
        case .right: "→"
        }
    }
}

/// One frame of the on-screen pad, in the shape the engine reads: a button mask and a left stick
/// byte per axis, 127 at rest and growing right and down.
struct TouchPadState {
    var buttons: GOALPadButton = []
    var leftX = UInt8(GOALPadAnalogNeutral)
    var leftY = UInt8(GOALPadAnalogNeutral)
    var rightX = UInt8(GOALPadAnalogNeutral)
    var rightY = UInt8(GOALPadAnalogNeutral)

    static let neutral = TouchPadState()

    var isLeftDeflected: Bool {
        leftX != UInt8(GOALPadAnalogNeutral) || leftY != UInt8(GOALPadAnalogNeutral)
    }

    var isRightDeflected: Bool {
        rightX != UInt8(GOALPadAnalogNeutral) || rightY != UInt8(GOALPadAnalogNeutral)
    }
}

/// The on-screen controls: a stick on the left half of the screen, a camera drag above it, swipe
/// gestures on the right half, and the two pills, turned into one frame of pad state.
///
/// The engine reads the pad once per frame and GOAL edge-detects with `cpad-pressed?`, so a swipe -
/// which is over the moment it is recognised - cannot be reported as one frame's press and
/// forgotten. Every button here is a small state machine instead: pressed for `holdFrames`, held
/// for as long as the finger stays down beyond that, then released for a guaranteed
/// `releaseFrames` before the next press, so two taps are two presses rather than one long one.
@MainActor
@Observable
final class TouchControls {
    /// How far from its origin the stick is dragged for full deflection, in points.
    nonisolated static let deflectionRadius: CGFloat = 90
    /// The same, for the camera drag. Longer, because the camera is a rate: the finger stays where
    /// it was dragged to and the camera keeps turning, so the travel is worth spending on control.
    nonisolated static let cameraRadius: CGFloat = 130
    /// Camera travel that reports nothing, so a resting finger cannot creep the camera. The game
    /// has a much larger one of its own - `analog-input` in `engine/ps2/pad.gc` ignores everything
    /// within 32 counts of centre - and this only has to cover a finger that is not moving.
    nonisolated static let cameraDeadzone: CGFloat = 4
    /// How far a right-half touch travels before it is a swipe rather than a tap.
    nonisolated static let swipeDistance: CGFloat = 44
    /// A touch that stays inside `swipeDistance` for longer than this is neither a tap nor a swipe.
    nonisolated static let tapDuration: TimeInterval = 0.4
    /// Frames a recognised gesture holds its button down for: long enough for GOAL to see the edge,
    /// and long enough that a flick jumps.
    nonisolated static let holdFrames = 6
    /// Frames a button is guaranteed to be released for before it can be pressed again.
    nonisolated static let releaseFrames = 2
    /// How long the controls stay on screen after the last finger leaves.
    nonisolated static let fadeOutDelay: TimeInterval = 0.9

    /// How far the stick is pushed before it also counts as a D-pad direction, and how far it has
    /// to come back before another push counts. The gap is what keeps a wavering thumb from
    /// stepping a menu twice.
    nonisolated static let dpadPress: CGFloat = 0.55
    nonisolated static let dpadRelease: CGFloat = 0.35
    /// Frames a held direction waits before it starts repeating, and the frames between repeats.
    nonisolated static let dpadRepeatDelay = 26
    nonisolated static let dpadRepeatInterval = 10

    /// What a finger is doing. Decided when it lands and never revisited, so a finger that started
    /// on a pill cannot become a swipe and the stick cannot become a jump.
    enum Role: Equatable {
        case stick
        case camera
        case gesture
        case pill(TouchButton)
    }

    /// One finger. `origin` is where it landed and never changes: the stick is placed by the touch
    /// that created it and then stays exactly where it was put, so a heading can be held.
    struct Tracked: Identifiable {
        let id: ObjectIdentifier
        let role: Role
        let origin: CGPoint
        var point: CGPoint
        let startedAt: TimeInterval
        var travelled: CGFloat = 0
        /// The button a recognised swipe is holding down. Nil until one is recognised.
        var swiped: TouchButton?
    }

    private(set) var touches: [ObjectIdentifier: Tracked] = [:]
    /// What a tap on the right half fires. Jump, until the player swipes something else.
    private(set) var repeatButton: TouchButton = .cross
    /// True while anything is being touched, and for a moment afterwards. The controls are only
    /// drawn while it is true.
    private(set) var isEngaged = false

    var stick: Tracked? { touches.values.first { $0.role == .stick } }
    var camera: Tracked? { touches.values.first { $0.role == .camera } }
    var gestures: [Tracked] { touches.values.filter { $0.role == .gesture } }

    func isPillDown(_ button: TouchButton) -> Bool {
        touches.values.contains { $0.role == .pill(button) }
    }

    /// Where the view laid the pills out, in the same space the touches arrive in. The pills are
    /// hit-tested here, before anything else, so the swipe recogniser can never swallow them.
    @ObservationIgnored private var pillFrames: [TouchButton: CGRect] = [:]
    @ObservationIgnored private var pulses: [TouchButton: Pulse] = [:]
    @ObservationIgnored private var fadeToken = 0
    @ObservationIgnored private var dpad = DirectionRepeat()

    func setPillFrame(_ button: TouchButton, _ frame: CGRect) {
        pillFrames[button] = frame
    }

    // MARK: - Touches

    func began(_ id: ObjectIdentifier, at point: CGPoint, in size: CGSize, at time: TimeInterval) {
        guard let role = self.role(for: point, in: size) else { return }
        touches[id] = Tracked(id: id, role: role, origin: point, point: point, startedAt: time)
        if case .pill(let button) = role { press(button) }
        engage()
    }

    func moved(_ id: ObjectIdentifier, to point: CGPoint) {
        guard var touch = touches[id] else { return }
        touch.point = point
        touch.travelled = max(touch.travelled, distance(touch.origin, point))
        if touch.role == .gesture, touch.swiped == nil, touch.travelled >= Self.swipeDistance,
           let button = Self.swipe(from: touch.origin, to: point) {
            touch.swiped = button
            repeatButton = button
            press(button)
            touchLog.debug("swipe -> \(String(describing: button), privacy: .public)")
        }
        touches[id] = touch
    }

    func ended(_ id: ObjectIdentifier, at time: TimeInterval) {
        guard let touch = touches.removeValue(forKey: id) else { return }
        if touch.role == .gesture, touch.swiped == nil, touch.travelled < Self.swipeDistance,
           time - touch.startedAt <= Self.tapDuration {
            press(repeatButton)
            touchLog.debug("tap -> \(String(describing: self.repeatButton), privacy: .public)")
        }
        fadeWhenIdle()
    }

    func cancelled(_ id: ObjectIdentifier) {
        touches.removeValue(forKey: id)
        fadeWhenIdle()
    }

    /// What a finger that just landed here is for, or nil if it is nothing.
    ///
    /// The pills are hit-tested first, so nothing else can swallow them. The left half is the
    /// stick, until one has been placed: after that the area above its ring is the camera, and the
    /// rest of the left half is a hand resting on the glass. A finger that is already the stick is
    /// never reconsidered, so dragging the stick upward cannot turn into a camera drag.
    private func role(for point: CGPoint, in size: CGSize) -> Role? {
        for (button, frame) in pillFrames where frame.contains(point) { return .pill(button) }
        guard point.x < size.width / 2 else { return .gesture }
        guard let stick else { return .stick }
        guard camera == nil, point.y <= stick.origin.y - Self.deflectionRadius else { return nil }
        return .camera
    }

    // MARK: - The frame

    /// This frame's pad state. It advances every button's state machine, so it is called exactly
    /// once per frame, from the frame loop.
    func frameState() -> TouchPadState {
        for touch in touches.values {
            switch touch.role {
            case .pill(let button):
                pulses[button, default: Pulse()].sustain()
            case .gesture:
                if let button = touch.swiped { pulses[button, default: Pulse()].sustain() }
            case .stick, .camera:
                break
            }
        }

        let push = stick.map {
            Self.deflection(from: $0.origin, to: $0.point, radius: Self.deflectionRadius)
        } ?? .zero
        if let direction = dpad.advance(push: push) { press(direction) }

        var state = TouchPadState()
        for button in TouchButton.allCases {
            var pulse = pulses[button] ?? Pulse()
            if pulse.advance() { state.buttons.insert(button.bit) }
            pulses[button] = pulse
        }
        (state.leftX, state.leftY) = Self.axes(push)
        if let camera {
            let look = Self.deflection(from: camera.origin, to: camera.point,
                                       radius: Self.cameraRadius, deadzone: Self.cameraDeadzone)
            (state.rightX, state.rightY) = Self.axes(look)
        }
        return state
    }

    // MARK: - Mapping

    /// Up is jump, left and right are the two other face buttons. Down is unmapped: it is the
    /// clumsiest of the four to reach and nothing needs it yet.
    private static func swipe(from origin: CGPoint, to point: CGPoint) -> TouchButton? {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        if abs(dy) > abs(dx) { return dy < 0 ? .cross : nil }
        return dx < 0 ? .square : .circle
    }

    /// How far a finger has been dragged from where it landed, as -1...1 per axis, clamped to the
    /// radius. The origin never moves, so this is the deflection of a stick that stays where it was
    /// put.
    private static func deflection(from origin: CGPoint, to point: CGPoint, radius: CGFloat,
                                   deadzone: CGFloat = 0) -> CGPoint {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > deadzone else { return .zero }
        let scale = (min(length, radius) - deadzone) / (radius - deadzone) / length
        return CGPoint(x: dx * scale, y: dy * scale)
    }

    /// A deflection as the pad's two bytes: 127 at rest, growing right and down, which is the
    /// direction screen coordinates already grow in.
    private static func axes(_ deflection: CGPoint) -> (x: UInt8, y: UInt8) {
        (byte(deflection.x), byte(deflection.y))
    }

    private static func byte(_ deflection: CGFloat) -> UInt8 {
        let scaled = CGFloat(GOALPadAnalogNeutral) + deflection * 127
        return UInt8(max(0, min(255, scaled.rounded())))
    }

    private func distance(_ from: CGPoint, _ to: CGPoint) -> CGFloat {
        ((to.x - from.x) * (to.x - from.x) + (to.y - from.y) * (to.y - from.y)).squareRoot()
    }

    // MARK: - Presses

    private func press(_ button: TouchButton) {
        pulses[button, default: Pulse()].press()
    }

    /// Turns the stick's deflection into D-pad presses.
    ///
    /// The menus - the progress menu, the save and load screens - read the D-pad, not the analog
    /// stick, so a stick alone cannot move through them. The stick is reported as itself as well;
    /// Jak 1's gameplay movement is analog and ignores these bits, so nothing here has to know
    /// whether a menu is open, and no game code changes.
    ///
    /// A held direction is a press, a wait, and then a slow repeat - never a bit held down, which
    /// would run a menu off its end in a fraction of a second. Coming back near the centre re-arms
    /// it, so the next push is a fresh press.
    private struct DirectionRepeat {
        private var direction: TouchButton?
        private var frames = 0
        private var nextRepeat = 0

        /// The direction to press this frame, if any.
        mutating func advance(push: CGPoint) -> TouchButton? {
            let threshold = direction == nil ? TouchControls.dpadPress : TouchControls.dpadRelease
            let pushed = Self.direction(of: push, beyond: threshold)
            guard pushed == direction else {
                direction = pushed
                frames = 0
                nextRepeat = TouchControls.dpadRepeatDelay
                return pushed
            }
            guard direction != nil else { return nil }
            frames += 1
            guard frames >= nextRepeat else { return nil }
            nextRepeat = frames + TouchControls.dpadRepeatInterval
            return direction
        }

        /// The dominant axis only: a diagonal push is one direction, not two, because the menus it
        /// drives are lists.
        private static func direction(of push: CGPoint, beyond threshold: CGFloat) -> TouchButton? {
            let horizontal = abs(push.x) > abs(push.y)
            let along = horizontal ? push.x : push.y
            guard abs(along) >= threshold else { return nil }
            if horizontal { return along < 0 ? .left : .right }
            return along < 0 ? .up : .down
        }
    }

    /// One button's press across frames. `press` starts one, `sustain` keeps it down while the
    /// finger is still there, and `advance` reports whether it is down this frame.
    private struct Pulse {
        var holdRemaining = 0
        var gapRemaining = 0
        var queued = 0

        mutating func press() {
            if holdRemaining == 0 && gapRemaining == 0 {
                holdRemaining = TouchControls.holdFrames
            } else {
                queued += 1
            }
        }

        mutating func sustain() {
            if holdRemaining > 0 { holdRemaining = max(holdRemaining, 2) }
        }

        mutating func advance() -> Bool {
            if holdRemaining == 0, gapRemaining == 0, queued > 0 {
                queued -= 1
                holdRemaining = TouchControls.holdFrames
            }
            if holdRemaining > 0 {
                holdRemaining -= 1
                if holdRemaining == 0 { gapRemaining = TouchControls.releaseFrames }
                return true
            }
            if gapRemaining > 0 { gapRemaining -= 1 }
            return false
        }
    }

    // MARK: - Visibility

    private func engage() {
        fadeToken += 1
        isEngaged = true
    }

    private func fadeWhenIdle() {
        guard touches.isEmpty else { return }
        fadeToken += 1
        let token = fadeToken
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.fadeOutDelay))
            guard let self, token == fadeToken, touches.isEmpty else { return }
            isEngaged = false
        }
    }
}
