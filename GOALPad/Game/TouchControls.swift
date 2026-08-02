import Foundation
import OSLog

nonisolated private let touchLog = Logger(subsystem: "com.zephyrstudiosllc.GOALPad",
                                          category: "Touch")

/// The PS2 buttons the on-screen controls drive.
enum TouchButton: CaseIterable {
    case cross, square, circle, crouch, start, select
    case up, down, left, right

    var bit: GOALPadButton {
        switch self {
        case .cross: .cross
        case .square: .square
        case .circle: .circle
        case .crouch: .L1
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
        case .crouch: "ROLL"
        case .start: "START"
        case .select: "SELECT"
        case .up: "↑"
        case .down: "↓"
        case .left: "←"
        case .right: "→"
        }
    }
}

/// One frame of the on-screen pad, in the shape the engine reads: a button mask and one byte per
/// stick axis, 127 at rest and growing right and down.
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

/// Stationary on-screen controls translated into the same state as a physical PS2-style pad.
///
/// Movement remains analog. The small right stick is intentionally button-like: after its
/// deadzone it snaps to one of eight directions at a fixed magnitude. The roll control is a held
/// L1 button; dragging that same finger upward adds one Cross press without releasing L1.
@MainActor
@Observable
final class TouchControls {
    nonisolated static let movementRadius: CGFloat = 90
    nonisolated static let rightStickRadius: CGFloat = 38
    nonisolated static let rightStickDeadzone: CGFloat = 12
    nonisolated static let rollJumpDistance: CGFloat = 44
    nonisolated static let swipeDistance: CGFloat = 44
    nonisolated static let tapDuration: TimeInterval = 0.4

    /// Frames a recognised one-shot press remains down, followed by a guaranteed release gap.
    nonisolated static let holdFrames = 6
    nonisolated static let releaseFrames = 2
    nonisolated static let fadeOutDelay: TimeInterval = 0.9

    /// Strong movement pushes also step list-style menus through the D-pad.
    nonisolated static let dpadPress: CGFloat = 0.55
    nonisolated static let dpadRelease: CGFloat = 0.35
    nonisolated static let dpadRepeatDelay = 26
    nonisolated static let dpadRepeatInterval = 10

    enum Role: Equatable {
        case movement
        case rightStick
        case roll
        case gesture
        case pill(TouchButton)
    }

    struct Tracked: Identifiable {
        let id: ObjectIdentifier
        let role: Role
        /// Fixed stick centre, or the finger's landing point for gestures, roll, and pills.
        let origin: CGPoint
        var point: CGPoint
        let startedAt: TimeInterval
        var travelled: CGFloat = 0
        var swiped: TouchButton? = nil
        var jumpTriggered = false
    }

    private(set) var touches: [ObjectIdentifier: Tracked] = [:]
    private(set) var isEngaged = false

    var stick: Tracked? { touches.values.first { $0.role == .movement } }
    var rightStick: Tracked? { touches.values.first { $0.role == .rightStick } }
    var gestures: [Tracked] { touches.values.filter { $0.role == .gesture } }
    var isRollDown: Bool { touches.values.contains { $0.role == .roll } }
    private(set) var repeatButton: TouchButton = .cross

    func isPillDown(_ button: TouchButton) -> Bool {
        touches.values.contains { $0.role == .pill(button) }
    }

    @ObservationIgnored private var movementFrame = CGRect.zero
    @ObservationIgnored private var rightStickFrame = CGRect.zero
    @ObservationIgnored private var rollFrame = CGRect.zero
    @ObservationIgnored private var pillFrames: [TouchButton: CGRect] = [:]
    @ObservationIgnored private var pulses: [TouchButton: Pulse] = [:]
    @ObservationIgnored private var fadeToken = 0
    @ObservationIgnored private var dpad = DirectionRepeat()

    func setMovementFrame(_ frame: CGRect) {
        movementFrame = frame
    }

    func setRightStickFrame(_ frame: CGRect) {
        rightStickFrame = frame
    }

    func setRollFrame(_ frame: CGRect) {
        rollFrame = frame
    }

    func setPillFrame(_ button: TouchButton, _ frame: CGRect) {
        pillFrames[button] = frame
    }

    // MARK: - Touches

    func began(_ id: ObjectIdentifier, at point: CGPoint, in size: CGSize, at time: TimeInterval) {
        guard let role = role(for: point, in: size) else { return }
        let origin: CGPoint
        switch role {
        case .movement:
            origin = movementFrame.centre
        case .rightStick:
            origin = rightStickFrame.centre
        case .roll, .gesture, .pill:
            origin = point
        }
        touches[id] = Tracked(id: id, role: role, origin: origin, point: point, startedAt: time)
        if case .pill(let button) = role { press(button) }
        engage()
    }

    func moved(_ id: ObjectIdentifier, to point: CGPoint) {
        guard var touch = touches[id] else { return }
        touch.point = point
        touch.travelled = max(touch.travelled, Self.distance(touch.origin, point))
        if touch.role == .gesture, touch.swiped == nil, touch.travelled >= Self.swipeDistance,
           let button = Self.swipe(from: touch.origin, to: point) {
            touch.swiped = button
            repeatButton = button
            press(button)
        }
        if touch.role == .roll, !touch.jumpTriggered {
            let dx = point.x - touch.origin.x
            let dy = point.y - touch.origin.y
            if dy <= -Self.rollJumpDistance, abs(dy) >= abs(dx) {
                touch.jumpTriggered = true
                press(.cross)
                touchLog.debug("roll jump")
            }
        }
        touches[id] = touch
    }

    func ended(_ id: ObjectIdentifier, at time: TimeInterval) {
        guard let touch = touches.removeValue(forKey: id) else { return }
        if touch.role == .gesture, touch.swiped == nil, touch.travelled < Self.swipeDistance,
           time - touch.startedAt <= Self.tapDuration {
            press(repeatButton)
        }
        fadeWhenIdle()
    }

    func cancelled(_ id: ObjectIdentifier) {
        guard touches.removeValue(forKey: id) != nil else { return }
        fadeWhenIdle()
    }

    /// UIKit may not deliver individual cancellations during a lifecycle transition.
    func reset() {
        touches.removeAll()
        repeatButton = .cross
        pulses.removeAll()
        dpad = DirectionRepeat()
        fadeToken += 1
        isEngaged = false
    }

    private func role(for point: CGPoint, in size: CGSize) -> Role? {
        for (button, frame) in pillFrames where frame.contains(point) { return .pill(button) }
        if rollFrame.contains(point) { return .roll }
        if rightStick == nil, rightStickFrame.contains(point) { return .rightStick }
        if stick == nil, movementFrame.contains(point) { return .movement }
        if point.x >= size.width / 2 { return .gesture }
        return nil
    }

    // MARK: - The frame

    /// Advances every one-shot button state machine exactly once per game frame.
    func frameState() -> TouchPadState {
        for touch in touches.values {
            switch touch.role {
            case .pill(let button):
                pulses[button, default: Pulse()].sustain()
            case .gesture:
                if let button = touch.swiped { pulses[button, default: Pulse()].sustain() }
            case .movement, .rightStick, .roll:
                break
            }
        }

        let movement = stick.map {
            Self.movementDeflection(from: $0.origin, to: $0.point)
        } ?? .zero
        if let direction = dpad.advance(push: movement) { press(direction) }

        var state = TouchPadState()
        for button in TouchButton.allCases {
            var pulse = pulses[button] ?? Pulse()
            if pulse.advance() { state.buttons.insert(button.bit) }
            pulses[button] = pulse
        }
        if isRollDown { state.buttons.insert(TouchButton.crouch.bit) }

        (state.leftX, state.leftY) = Self.axes(movement)
        if let rightStick {
            let look = Self.rightStickDeflection(from: rightStick.origin, to: rightStick.point)
            (state.rightX, state.rightY) = Self.axes(look)
        }
        return state
    }

    // MARK: - Mapping

    /// The three face-button gestures retained outside the explicit controls.
    private static func swipe(from origin: CGPoint, to point: CGPoint) -> TouchButton? {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        if abs(dy) > abs(dx) { return dy < 0 ? .cross : nil }
        return dx < 0 ? .square : .circle
    }

    nonisolated static func movementDeflection(from origin: CGPoint, to point: CGPoint) -> CGPoint {
        radialDeflection(from: origin, to: point, radius: movementRadius)
    }

    /// Returns a unit vector in the nearest of eight directions once outside the deadzone.
    nonisolated static func rightStickDeflection(from origin: CGPoint,
                                                 to point: CGPoint) -> CGPoint {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        guard dx * dx + dy * dy > rightStickDeadzone * rightStickDeadzone else { return .zero }

        let octant = (atan2(Double(dy), Double(dx)) / (.pi / 4)).rounded()
        let angle = octant * (.pi / 4)
        return CGPoint(x: cos(angle), y: sin(angle))
    }

    nonisolated private static func radialDeflection(from origin: CGPoint,
                                                     to point: CGPoint,
                                                     radius: CGFloat) -> CGPoint {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return .zero }
        let scale = min(length, radius) / radius / length
        return CGPoint(x: dx * scale, y: dy * scale)
    }

    private static func axes(_ deflection: CGPoint) -> (x: UInt8, y: UInt8) {
        (byte(deflection.x), byte(deflection.y))
    }

    private static func byte(_ deflection: CGFloat) -> UInt8 {
        let scaled = CGFloat(GOALPadAnalogNeutral) + deflection * 127
        return UInt8(max(0, min(255, scaled.rounded())))
    }

    private static func distance(_ from: CGPoint, _ to: CGPoint) -> CGFloat {
        let dx = to.x - from.x
        let dy = to.y - from.y
        return (dx * dx + dy * dy).squareRoot()
    }

    // MARK: - Presses

    private func press(_ button: TouchButton) {
        pulses[button, default: Pulse()].press()
    }

    /// Converts strong movement into one repeated dominant-axis D-pad direction for menus.
    private struct DirectionRepeat {
        private var direction: TouchButton?
        private var frames = 0
        private var nextRepeat = 0

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

        private static func direction(of push: CGPoint, beyond threshold: CGFloat) -> TouchButton? {
            let horizontal = abs(push.x) > abs(push.y)
            let along = horizontal ? push.x : push.y
            guard abs(along) >= threshold else { return nil }
            if horizontal { return along < 0 ? .left : .right }
            return along < 0 ? .up : .down
        }
    }

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

private extension CGRect {
    var centre: CGPoint { CGPoint(x: midX, y: midY) }
}
