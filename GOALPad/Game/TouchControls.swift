import Foundation
import OSLog

nonisolated private let touchLog = Logger(subsystem: "com.zephyrstudiosllc.eco",
                                          category: "Touch")

/// The PS2 buttons the on-screen controls drive.
enum TouchButton: CaseIterable, Hashable, Sendable {
    case cross, square, circle, crouch, start, select
    case up, down, left, right
    case triangle, leftShoulder, rightShoulder

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
        case .triangle: .triangle
        case .leftShoulder: .L1
        case .rightShoulder: .R1
        }
    }

    var glyph: String {
        switch self {
        case .cross: "✕"
        case .square: "□"
        case .circle: "○"
        case .crouch: "↓"
        case .start: "START"
        case .select: "SELECT"
        case .up: "↑"
        case .down: "↓"
        case .left: "←"
        case .right: "→"
        case .triangle: "△"
        case .leftShoulder: "L1"
        case .rightShoulder: "R1"
        }
    }
}

enum TouchControlStyle: String, CaseIterable, Sendable {
    case modern
    case classic
}

/// Touch-friendly actions whose meanings are authoritative for the current native game mode.
/// Progress is deliberately absent: Jak reuses its face buttons for both stat tabs and nested
/// option confirmation, and GameSession does not expose that internal display state.
enum NativeMenuTouchAction: CaseIterable, Hashable, Sendable {
    case up, down, left, right
    case confirm, back, resume

    var button: TouchButton {
        switch self {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .confirm: .cross
        case .back: .square
        case .resume: .start
        }
    }

    var label: String {
        switch self {
        case .up: "Up"
        case .down: "Down"
        case .left: "Left"
        case .right: "Right"
        case .confirm: "Confirm"
        case .back: "Back"
        case .resume: "Resume"
        }
    }

    var systemImage: String {
        switch self {
        case .up: "chevron.up"
        case .down: "chevron.down"
        case .left: "chevron.left"
        case .right: "chevron.right"
        case .confirm: "checkmark"
        case .back: "arrow.uturn.backward"
        case .resume: "play.fill"
        }
    }

    nonisolated static func available(in mode: GOALPadGameMode) -> [Self] {
        switch mode {
        case .pause:
            [.resume]
        case .menu:
            [.up, .down, .left, .right, .back, .confirm, .resume]
        case .unknown, .gameplay, .progress:
            []
        @unknown default:
            []
        }
    }
}

/// A discrete, app-owned touch action that may receive device feedback.
/// These are intentionally separate from native game/controller rumble.
enum TouchHapticEvent: Equatable {
    case button(TouchButton)
    case gesture(TouchButton)
    case stickEngaged
}

struct TouchSafeAreaInsets: Equatable, Sendable {
    var top: CGFloat = 0
    var leading: CGFloat = 0
    var bottom: CGFloat = 0
    var trailing: CGFloat = 0

    static let zero = TouchSafeAreaInsets()
}

/// Deterministic Modern artwork geometry. Input radii remain owned by TouchControls.
struct ModernTouchLayout: Sendable {
    static let movementKnobSize: CGFloat = 66
    static let movementVisualRadius: CGFloat = 54
    static let rightStickHitSlop: CGFloat = 16
    static let rightStickSpacerCap: CGFloat = 200

    private static let pillSize = CGSize(width: 82, height: 42)
    private static let pillSpacing: CGFloat = 20
    private static let pillHitInsets = CGSize(width: 10, height: 12)
    private static let controlGap: CGFloat = 8

    let safeBounds: CGRect
    let rightStickSpacer: CGFloat
    let rightStickArtworkFrame: CGRect
    let rightStickHitFrame: CGRect
    let selectPillFrame: CGRect
    let startPillFrame: CGRect

    init(size: CGSize, safeAreaInsets: TouchSafeAreaInsets = .zero) {
        let bounds = CGRect(origin: .zero,
                            size: CGSize(width: max(0, size.width), height: max(0, size.height)))
        let leading = min(max(0, safeAreaInsets.leading), bounds.width)
        let trailing = min(max(0, safeAreaInsets.trailing), bounds.width - leading)
        let top = min(max(0, safeAreaInsets.top), bounds.height)
        let bottom = min(max(0, safeAreaInsets.bottom), bounds.height - top)
        let safe = CGRect(x: leading, y: top,
                          width: bounds.width - leading - trailing,
                          height: bounds.height - top - bottom)
        safeBounds = safe

        let legacyEdge = Self.legacyRightStickEdge(for: bounds.size)
        let targetSpacer = min(Self.rightStickSpacerCap,
                               max(legacyEdge, safe.width * 0.24))
        rightStickSpacer = min(targetSpacer,
                                max(0, safe.width - TouchControls.rightStickRadius * 2))

        let pillOffset = (Self.pillSize.width + Self.pillSpacing) / 2
        let pillY = bounds.maxY - 30 - Self.pillSize.height / 2
        selectPillFrame = Self.frame(centre: CGPoint(x: bounds.midX - pillOffset, y: pillY),
                                     size: Self.pillSize)
        startPillFrame = Self.frame(centre: CGPoint(x: bounds.midX + pillOffset, y: pillY),
                                    size: Self.pillSize)

        let radius = TouchControls.rightStickRadius
        let centreX = max(safe.minX + radius, safe.maxX - radius - rightStickSpacer)
        let lowestCentreY = safe.maxY - radius - legacyEdge
        let candidateHitFrame = Self.frame(centre: CGPoint(x: centreX, y: lowestCentreY),
                                           diameter: radius * 2)
            .insetBy(dx: -Self.rightStickHitSlop, dy: -Self.rightStickHitSlop)
        let pillHitFrames = [selectPillFrame, startPillFrame].map {
            $0.insetBy(dx: -Self.pillHitInsets.width, dy: -Self.pillHitInsets.height)
        }
        let overlapsPillHorizontally = pillHitFrames.contains {
            $0.minX < candidateHitFrame.maxX && candidateHitFrame.minX < $0.maxX
        }
        let clearCentreY = pillHitFrames.map(\.minY).min()
            .map { $0 - radius - Self.rightStickHitSlop - Self.controlGap }
            ?? lowestCentreY
        let centreY = max(safe.minY + radius,
                          overlapsPillHorizontally ? min(lowestCentreY, clearCentreY) : lowestCentreY)
        rightStickArtworkFrame = Self.frame(centre: CGPoint(x: centreX, y: centreY),
                                            diameter: radius * 2)
        rightStickHitFrame = rightStickArtworkFrame.insetBy(dx: -Self.rightStickHitSlop,
                                                             dy: -Self.rightStickHitSlop)
    }

    static func legacyRightStickEdge(for size: CGSize) -> CGFloat {
        max(28, min(max(0, size.width), max(0, size.height)) * 0.06)
    }

    private static func frame(centre: CGPoint, diameter: CGFloat) -> CGRect {
        frame(centre: centre, size: CGSize(width: diameter, height: diameter))
    }

    private static func frame(centre: CGPoint, size: CGSize) -> CGRect {
        CGRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2,
               width: size.width, height: size.height)
    }
}

/// Deterministic hit targets shared by the Classic artwork and raw touch surface.
struct ClassicTouchLayout {
    static let buttons: [TouchButton] = [
        .up, .down, .left, .right,
        .select, .start,
        .leftShoulder, .rightShoulder,
        .triangle, .square, .circle, .cross,
    ]

    let safeBounds: CGRect
    let stickRadius: CGFloat
    let leftStickFrame: CGRect
    let rightStickFrame: CGRect
    let buttonFrames: [TouchButton: CGRect]

    init(size: CGSize, safeAreaInsets: TouchSafeAreaInsets = .zero) {
        let bounds = CGRect(origin: .zero,
                            size: CGSize(width: max(0, size.width), height: max(0, size.height)))
        let leading = min(max(0, safeAreaInsets.leading), bounds.width)
        let trailing = min(max(0, safeAreaInsets.trailing), bounds.width - leading)
        let top = min(max(0, safeAreaInsets.top), bounds.height)
        let bottom = min(max(0, safeAreaInsets.bottom), bounds.height - top)
        let safe = CGRect(x: leading, y: top,
                          width: bounds.width - leading - trailing,
                          height: bounds.height - top - bottom)
        let padding = min(18, max(0, min(safe.width, safe.height) * 0.025))
        safeBounds = safe.insetBy(dx: padding, dy: padding)

        let scale = min(1, max(0.5, min(safeBounds.width / 560, safeBounds.height / 240)))
        let buttonDiameter = 44 * scale
        let buttonRadius = buttonDiameter / 2
        let buttonGap = 12 * scale
        let clusterStep = buttonDiameter + buttonGap
        stickRadius = 56 * scale

        let clusterInset = clusterStep + buttonRadius
        let leftCluster = CGPoint(x: safeBounds.minX + clusterInset,
                                  y: safeBounds.maxY - clusterInset - 8 * scale)
        let rightCluster = CGPoint(x: safeBounds.maxX - clusterInset,
                                   y: leftCluster.y)
        let stickInset = clusterInset + clusterStep + buttonRadius + buttonGap + stickRadius
        let stickY = safeBounds.maxY - stickRadius - 8 * scale
        let leftStickCentre = CGPoint(x: safeBounds.minX + stickInset, y: stickY)
        let rightStickCentre = CGPoint(x: safeBounds.maxX - stickInset, y: stickY)

        leftStickFrame = Self.frame(centre: leftStickCentre, diameter: stickRadius * 2)
        rightStickFrame = Self.frame(centre: rightStickCentre, diameter: stickRadius * 2)

        var frames: [TouchButton: CGRect] = [:]
        frames[.up] = Self.frame(centre: CGPoint(x: leftCluster.x,
                                                 y: leftCluster.y - clusterStep),
                                         diameter: buttonDiameter)
        frames[.down] = Self.frame(centre: CGPoint(x: leftCluster.x,
                                                   y: leftCluster.y + clusterStep),
                                           diameter: buttonDiameter)
        frames[.left] = Self.frame(centre: CGPoint(x: leftCluster.x - clusterStep,
                                                   y: leftCluster.y),
                                           diameter: buttonDiameter)
        frames[.right] = Self.frame(centre: CGPoint(x: leftCluster.x + clusterStep,
                                                    y: leftCluster.y),
                                            diameter: buttonDiameter)
        frames[.triangle] = Self.frame(centre: CGPoint(x: rightCluster.x,
                                                       y: rightCluster.y - clusterStep),
                                               diameter: buttonDiameter)
        frames[.cross] = Self.frame(centre: CGPoint(x: rightCluster.x,
                                                    y: rightCluster.y + clusterStep),
                                            diameter: buttonDiameter)
        frames[.square] = Self.frame(centre: CGPoint(x: rightCluster.x - clusterStep,
                                                     y: rightCluster.y),
                                             diameter: buttonDiameter)
        frames[.circle] = Self.frame(centre: CGPoint(x: rightCluster.x + clusterStep,
                                                     y: rightCluster.y),
                                             diameter: buttonDiameter)

        let shoulderSize = CGSize(width: 82 * scale, height: 34 * scale)
        let shoulderY = leftCluster.y - clusterStep - buttonRadius - buttonGap
            - shoulderSize.height / 2
        frames[.leftShoulder] = Self.frame(
            centre: CGPoint(x: (leftCluster.x + leftStickCentre.x) / 2, y: shoulderY),
            size: shoulderSize)
        frames[.rightShoulder] = Self.frame(
            centre: CGPoint(x: (rightCluster.x + rightStickCentre.x) / 2, y: shoulderY),
            size: shoulderSize)

        let pillSize = CGSize(width: 68 * scale, height: 30 * scale)
        let centreGap = rightStickFrame.minX - leftStickFrame.maxX
        if centreGap >= pillSize.width * 2 + buttonGap {
            let offset = pillSize.width / 2 + buttonGap / 2
            frames[.select] = Self.frame(centre: CGPoint(x: safeBounds.midX - offset, y: stickY),
                                         size: pillSize)
            frames[.start] = Self.frame(centre: CGPoint(x: safeBounds.midX + offset, y: stickY),
                                        size: pillSize)
        } else {
            frames[.start] = Self.frame(centre: CGPoint(x: safeBounds.midX, y: shoulderY),
                                        size: pillSize)
            frames[.select] = Self.frame(
                centre: CGPoint(x: safeBounds.midX,
                                y: shoulderY - pillSize.height - buttonGap),
                size: pillSize)
        }
        buttonFrames = frames
    }

    func frame(for button: TouchButton) -> CGRect? {
        buttonFrames[button]
    }

    private static func frame(centre: CGPoint, diameter: CGFloat) -> CGRect {
        frame(centre: centre, size: CGSize(width: diameter, height: diameter))
    }

    private static func frame(centre: CGPoint, size: CGSize) -> CGRect {
        CGRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2,
               width: size.width, height: size.height)
    }
}

/// One frame of the on-screen pad, in the shape the engine reads: a button mask and one byte per
/// stick axis, 127 at rest and growing right and down.
struct TouchPadState: Equatable {
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

/// On-screen controls translated into the same state as a physical PS2-style pad.
/// Modern retains the dynamic Build 93 gestures; Classic uses fixed DualShock-like hit targets.
@MainActor
@Observable
final class TouchControls {
    nonisolated static let movementRadius: CGFloat = 90
    nonisolated static let rightStickRadius: CGFloat = 38
    nonisolated static let rightStickDeadzone: CGFloat = 12
    nonisolated static let rollJumpDistance: CGFloat = 44
    nonisolated static let swipeDistance: CGFloat = 44
    nonisolated static let pinchScaleDelta: CGFloat = 0.12

    /// Frames a recognised one-shot press remains down, followed by a guaranteed release gap.
    nonisolated static let holdFrames = 6
    nonisolated static let releaseFrames = 2
    nonisolated static let fadeOutDelay: TimeInterval = 0.9

    /// Strong movement pushes also step list-style menus through the D-pad.
    nonisolated static let dpadPress: CGFloat = 0.55
    nonisolated static let dpadRelease: CGFloat = 0.35
    nonisolated static let dpadRepeatDelay = 26
    nonisolated static let dpadRepeatInterval = 10

    private(set) var style: TouchControlStyle
    private(set) var nativeMenuMode: GOALPadGameMode = .unknown

    enum Role: Equatable {
        case movement
        case rightStick
        case gesture
        case pill(TouchButton)
    }

    struct Tracked: Identifiable {
        let id: ObjectIdentifier
        let role: Role
        /// A dynamic movement origin, fixed right-stick centre, or gesture/pill landing point.
        let origin: CGPoint
        var point: CGPoint
        var travelled: CGFloat = 0
        var swiped: TouchButton? = nil
        var crouchPeakY: CGFloat? = nil
        var jumpTriggered = false
        var punchTriggered = false
        var stickHapticTriggered = false
        let radius: CGFloat
        let deadzone: CGFloat
    }

    private(set) var touches: [ObjectIdentifier: Tracked] = [:]
    private(set) var isEngaged = false
    private(set) var surfaceSafeAreaInsets = TouchSafeAreaInsets.zero
    @ObservationIgnored private var hapticEvents: [TouchHapticEvent] = []

    var stick: Tracked? { touches.values.first { $0.role == .movement } }
    var rightStick: Tracked? { touches.values.first { $0.role == .rightStick } }
    var gestures: [Tracked] { touches.values.filter { $0.role == .gesture } }
    var isCrouching: Bool {
        gestures.contains { $0.swiped == .crouch }
    }

    func isPillDown(_ button: TouchButton) -> Bool {
        touches.values.contains { $0.role == .pill(button) }
    }

    @ObservationIgnored private var rightStickFrame = CGRect.zero
    @ObservationIgnored private var pillFrames: [TouchButton: CGRect] = [:]
    @ObservationIgnored private var pulses: [TouchButton: Pulse] = [:]
    @ObservationIgnored private var fadeToken = 0
    @ObservationIgnored private var dpad = DirectionRepeat()
    @ObservationIgnored private var pinchZoom = PinchZoom()

    init(style: TouchControlStyle = .modern) {
        self.style = style
    }

    var hasDedicatedNativeMenuControls: Bool {
        !NativeMenuTouchAction.available(in: nativeMenuMode).isEmpty
    }

    func setStyle(_ style: TouchControlStyle) {
        guard style != self.style else { return }
        reset()
        self.style = style
    }

    /// Applies the read-only native master-mode classification. Entering or leaving a dedicated
    /// menu surface cancels carried gameplay touches before another frame reaches the engine.
    func setNativeMenuMode(_ mode: GOALPadGameMode) {
        guard mode != nativeMenuMode else { return }
        let hadDedicatedControls = hasDedicatedNativeMenuControls
        nativeMenuMode = mode
        if hadDedicatedControls || hasDedicatedNativeMenuControls { reset() }
    }

    /// Emits one ordinary pad pulse. Availability is mode-gated so a stale SwiftUI action cannot
    /// send menu input after the game has returned to gameplay or moved into progress.
    func performNativeMenuAction(_ action: NativeMenuTouchAction) {
        guard NativeMenuTouchAction.available(in: nativeMenuMode).contains(action) else { return }
        press(action.button)
        enqueueHaptic(.button(action.button))
    }

    func setRightStickFrame(_ frame: CGRect) {
        rightStickFrame = frame
    }

    func setPillFrame(_ button: TouchButton, _ frame: CGRect) {
        pillFrames[button] = frame
    }

    func setSurfaceSafeAreaInsets(_ insets: TouchSafeAreaInsets) {
        guard insets != surfaceSafeAreaInsets else { return }
        surfaceSafeAreaInsets = insets
    }

    // MARK: - Touches

    func began(_ id: ObjectIdentifier, at point: CGPoint, in size: CGSize,
               safeAreaInsets: TouchSafeAreaInsets = .zero, at _: TimeInterval) {
        guard !hasDedicatedNativeMenuControls else { return }
        let layout = style == .classic
            ? ClassicTouchLayout(size: size, safeAreaInsets: safeAreaInsets)
            : nil
        guard let role = role(for: point, in: size, classicLayout: layout) else { return }
        let origin: CGPoint
        let radius: CGFloat
        let deadzone: CGFloat
        switch role {
        case .movement:
            if let layout {
                origin = layout.leftStickFrame.centre
                radius = layout.stickRadius
                deadzone = layout.stickRadius * 0.16
            } else {
                origin = point
                radius = Self.movementRadius
                deadzone = 0
            }
        case .rightStick:
            if let layout {
                origin = layout.rightStickFrame.centre
                radius = layout.stickRadius
                deadzone = layout.stickRadius * 0.16
            } else {
                origin = rightStickFrame.centre
                radius = Self.rightStickRadius
                deadzone = Self.rightStickDeadzone
            }
        case .gesture, .pill:
            origin = point
            radius = 0
            deadzone = 0
        }
        touches[id] = Tracked(id: id, role: role, origin: origin, point: point,
                              radius: radius, deadzone: deadzone)
        if case .pill(let button) = role {
            press(button)
            enqueueHaptic(.button(button))
        }
        engage()
    }

    func moved(_ id: ObjectIdentifier, to point: CGPoint) {
        guard var touch = touches[id] else { return }
        touch.point = point
        touch.travelled = max(touch.travelled, Self.distance(touch.origin, point))
        if (touch.role == .movement || touch.role == .rightStick), !touch.stickHapticTriggered,
           Self.distance(.zero, Self.radialDeflection(from: touch.origin, to: point,
                                                      radius: touch.radius,
                                                      deadzone: touch.deadzone)) >= 0.5 {
            touch.stickHapticTriggered = true
            enqueueHaptic(.stickEngaged)
        } else if touch.role == .gesture, touch.swiped == nil,
                  touch.travelled >= Self.swipeDistance,
           let button = Self.swipe(from: touch.origin, to: point) {
            touch.swiped = button
            enqueueHaptic(.gesture(button))
            if button == .crouch {
                touch.crouchPeakY = point.y
                touchLog.debug("crouch")
            } else {
                press(button)
            }
        } else if touch.role == .gesture, touch.swiped == .crouch {
            let peak = max(touch.crouchPeakY ?? point.y, point.y)
            touch.crouchPeakY = peak
            let horizontal = point.x - touch.origin.x
            if !touch.punchTriggered, horizontal <= -Self.swipeDistance {
                touch.punchTriggered = true
                press(.square)
                enqueueHaptic(.gesture(.square))
                touchLog.debug("crouch punch")
            }
            if !touch.jumpTriggered, peak - point.y >= Self.rollJumpDistance {
                touch.jumpTriggered = true
                press(.cross)
                enqueueHaptic(.gesture(.cross))
                touchLog.debug("roll jump")
            }
        }
        touches[id] = touch
    }

    func ended(_ id: ObjectIdentifier, at _: TimeInterval) {
        guard touches.removeValue(forKey: id) != nil else { return }
        fadeWhenIdle()
    }

    func cancelled(_ id: ObjectIdentifier) {
        guard touches.removeValue(forKey: id) != nil else { return }
        fadeWhenIdle()
    }

    func pinchBegan() {
        guard style == .modern, !hasDedicatedNativeMenuControls else {
            pinchZoom.reset()
            return
        }
        pinchZoom.begin()
    }

    func pinchChanged(scale: CGFloat, lookAroundState: GOALPadLookAroundState) {
        guard style == .modern, !hasDedicatedNativeMenuControls,
              let direction = pinchZoom.recognize(scale: scale) else { return }
        switch (direction, lookAroundState) {
        case (.zoomIn, .normal), (.zoomOut, .firstPerson):
            press(.triangle)
            enqueueHaptic(.gesture(.triangle))
        default:
            break
        }
    }

    func pinchEnded() {
        pinchZoom.reset()
    }

    func pinchCancelled() {
        pinchZoom.reset()
    }

    /// UIKit may not deliver individual cancellations during a lifecycle transition.
    func reset() {
        touches.removeAll()
        pulses.removeAll()
        dpad = DirectionRepeat()
        pinchZoom.reset()
        hapticEvents.removeAll()
        fadeToken += 1
        isEngaged = false
    }

    /// Returns and clears touch-owned feedback actions without affecting game input state.
    func consumeHapticEvents() -> [TouchHapticEvent] {
        defer { hapticEvents.removeAll() }
        return hapticEvents
    }

    private func role(for point: CGPoint, in size: CGSize,
                      classicLayout: ClassicTouchLayout?) -> Role? {
        if let layout = classicLayout {
            for button in ClassicTouchLayout.buttons
            where layout.frame(for: button)?.contains(point) == true {
                return .pill(button)
            }
            if stick == nil, layout.leftStickFrame.contains(point) { return .movement }
            if rightStick == nil, layout.rightStickFrame.contains(point) { return .rightStick }
            return nil
        }
        for (button, frame) in pillFrames where frame.contains(point) { return .pill(button) }
        if rightStick == nil, rightStickFrame.contains(point) { return .rightStick }
        if stick == nil, point.x < size.width / 2 { return .movement }
        if point.x >= size.width / 2 { return .gesture }
        return nil
    }

    // MARK: - The frame

    /// Advances every one-shot button state machine exactly once per game frame.
    func frameState() -> TouchPadState {
        if hasDedicatedNativeMenuControls {
            var state = TouchPadState()
            for button in TouchButton.allCases {
                var pulse = pulses[button] ?? Pulse()
                if pulse.advance() { state.buttons.insert(button.bit) }
                pulses[button] = pulse
            }
            return state
        }

        for touch in touches.values {
            switch touch.role {
            case .pill(let button):
                pulses[button, default: Pulse()].sustain()
            case .gesture:
                if let button = touch.swiped, button != .crouch {
                    pulses[button, default: Pulse()].sustain()
                }
            case .movement, .rightStick:
                break
            }
        }

        let movement = stick.map {
            Self.radialDeflection(from: $0.origin, to: $0.point,
                                  radius: $0.radius, deadzone: $0.deadzone)
        } ?? .zero
        if let direction = dpad.advance(push: movement) { press(direction) }

        var state = TouchPadState()
        for button in TouchButton.allCases {
            var pulse = pulses[button] ?? Pulse()
            if pulse.advance() { state.buttons.insert(button.bit) }
            pulses[button] = pulse
        }
        if isCrouching { state.buttons.insert(TouchButton.crouch.bit) }

        (state.leftX, state.leftY) = Self.axes(movement)
        if let rightStick {
            let look = Self.radialDeflection(from: rightStick.origin, to: rightStick.point,
                                             radius: rightStick.radius,
                                             deadzone: rightStick.deadzone)
            (state.rightX, state.rightY) = Self.axes(look)
        }
        return state
    }

    // MARK: - Mapping

    /// The three face-button gestures plus held crouch on the downward direction.
    private static func swipe(from origin: CGPoint, to point: CGPoint) -> TouchButton? {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        if abs(dy) > abs(dx) { return dy < 0 ? .cross : .crouch }
        return dx < 0 ? .square : .circle
    }

    nonisolated static func movementDeflection(from origin: CGPoint, to point: CGPoint) -> CGPoint {
        radialDeflection(from: origin, to: point, radius: movementRadius)
    }

    /// Returns a continuous radial deflection after the small resting-finger deadzone.
    nonisolated static func rightStickDeflection(from origin: CGPoint,
                                                 to point: CGPoint) -> CGPoint {
        radialDeflection(from: origin, to: point, radius: rightStickRadius,
                         deadzone: rightStickDeadzone)
    }

    nonisolated static func classicStickDeflection(from origin: CGPoint, to point: CGPoint,
                                                   radius: CGFloat) -> CGPoint {
        radialDeflection(from: origin, to: point, radius: radius, deadzone: radius * 0.16)
    }

    nonisolated static func artworkIsVisible(isEngaged: Bool, isSuppressed: Bool,
                                             hasTouches: Bool,
                                             isNativeMenuOpen: Bool) -> Bool {
        (isEngaged || isNativeMenuOpen) && (!isSuppressed || hasTouches)
    }

    nonisolated static func artworkLabel(for button: TouchButton,
                                         isNativeMenuOpen: Bool) -> String {
        guard button == .start else { return button.glyph }
        return isNativeMenuOpen ? "RESUME" : "PAUSE"
    }

    nonisolated static func nativeMenuControlsAreVisible(mode: GOALPadGameMode,
                                                         isSuppressed: Bool) -> Bool {
        !isSuppressed && !NativeMenuTouchAction.available(in: mode).isEmpty
    }

    nonisolated private static func radialDeflection(from origin: CGPoint,
                                                     to point: CGPoint,
                                                     radius: CGFloat,
                                                     deadzone: CGFloat = 0) -> CGPoint {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > deadzone else { return .zero }
        let scale = (min(length, radius) - deadzone) / (radius - deadzone) / length
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

    private func enqueueHaptic(_ event: TouchHapticEvent) {
        hapticEvents.append(event)
    }

    private struct PinchZoom {
        enum Direction {
            case zoomIn
            case zoomOut
        }

        private var isActive = false
        private var direction: Direction?

        mutating func begin() {
            isActive = true
            direction = nil
        }

        mutating func recognize(scale: CGFloat) -> Direction? {
            guard isActive, direction == nil else { return nil }
            let recognized: Direction
            if scale >= 1 + TouchControls.pinchScaleDelta {
                recognized = .zoomIn
            } else if scale <= 1 - TouchControls.pinchScaleDelta {
                recognized = .zoomOut
            } else {
                return nil
            }
            direction = recognized
            return recognized
        }

        mutating func reset() {
            isActive = false
            direction = nil
        }
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
