import Foundation

enum PrimaryInputSource: String, CaseIterable, Codable, Sendable {
    case automatic
    case touch
    case controller
    case keyboardMouse

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .touch: "Touch"
        case .controller: "Controller"
        case .keyboardMouse: "Mouse & Keyboard"
        }
    }
}

/// Resolves a persisted preference against what this device currently has. An unavailable
/// explicit source falls back to Automatic so a cloud-synced preference cannot strand a player.
struct InputSourcePolicy: Equatable {
    let preference: PrimaryInputSource
    let touchAvailable: Bool
    let controllerConnected: Bool
    let keyboardMouseConnected: Bool

    var effectiveSource: PrimaryInputSource {
        switch preference {
        case .touch where touchAvailable: .touch
        case .controller where controllerConnected: .controller
        case .keyboardMouse where keyboardMouseConnected: .keyboardMouse
        default: .automatic
        }
    }

    var allowsTouch: Bool {
        touchAvailable && (effectiveSource == .automatic || effectiveSource == .touch)
    }

    var allowsController: Bool {
        controllerConnected && (effectiveSource == .automatic || effectiveSource == .controller)
    }

    var allowsKeyboardMouse: Bool {
        keyboardMouseConnected
            && (effectiveSource == .automatic || effectiveSource == .keyboardMouse)
    }

    func suppressesTouchChrome(recentPhysicalActivity: Bool) -> Bool {
        switch effectiveSource {
        case .automatic: recentPhysicalActivity
        case .controller: controllerConnected
        case .keyboardMouse: keyboardMouseConnected
        case .touch: false
        }
    }
}

/// Only the keyboard keys intentionally exposed as Jak 1 controls. Text entry and every other key
/// stay outside the gameplay pad until a later remapping slice chooses them explicitly.
enum KeyboardMouseKey: CaseIterable, Hashable {
    case w
    case a
    case s
    case d
    case leftArrow
    case rightArrow
    case upArrow
    case downArrow
    case escape
    case tab
}

struct KeyboardMouseFrame {
    var buttons: GOALPadButton = []
    var leftX = UInt8(GOALPadAnalogNeutral)
    var leftY = UInt8(GOALPadAnalogNeutral)
    var rightX = UInt8(GOALPadAnalogNeutral)
    var rightY = UInt8(GOALPadAnalogNeutral)
    var hasKeyboardInput = false
    var hasMouseInput = false
}

/// The shared whole-stick precedence rule. A primary physical source keeps both axes whenever it
/// is outside Jak 1's deadzone; otherwise the next active source supplies the whole stick.
enum PadStickMerge {
    static let deadzone: UInt8 = 32

    static func isDeflected(x: UInt8, y: UInt8) -> Bool {
        let neutral = Int(GOALPadAnalogNeutral)
        return abs(Int(x) - neutral) > Int(deadzone) || abs(Int(y) - neutral) > Int(deadzone)
    }

    static func preferred(primaryX: UInt8,
                          primaryY: UInt8,
                          fallbackX: UInt8,
                          fallbackY: UInt8,
                          fallbackActive: Bool) -> (x: UInt8, y: UInt8) {
        if isDeflected(x: primaryX, y: primaryY) || !fallbackActive {
            return (primaryX, primaryY)
        }
        return (fallbackX, fallbackY)
    }
}

/// Pure held-key and relative-mouse state. Mouse movement is consumed exactly once so a stopped
/// mouse produces a neutral right stick on the following game frame.
struct KeyboardMouseInputState {
    /// Raw Game Controller mouse units accumulated during one game frame before the stick clamps.
    static let mouseDeltaForFullDeflection: Float = 24
    /// Any real mouse delta starts one unit beyond Jak 1's deadzone and then scales linearly to the
    /// full byte range.
    static let mouseMinimumStickDeflection = Float(PadStickMerge.deadzone + 1)
    /// Apple's raw-delta contract does not state the vertical sign. This conventional tentative
    /// mapping matches the existing Game Controller stick conversion and needs a physical A/B.
    static let mouseYSign: Float = -1

    private var heldKeys: Set<KeyboardMouseKey> = []
    private var pendingMouseX: Float = 0
    private var pendingMouseY: Float = 0

    @discardableResult
    mutating func setKey(_ key: KeyboardMouseKey, pressed: Bool) -> Bool {
        if pressed {
            return heldKeys.insert(key).inserted
        }
        return heldKeys.remove(key) != nil
    }

    @discardableResult
    mutating func addMouseMovement(deltaX: Float, deltaY: Float) -> Bool {
        guard deltaX.isFinite, deltaY.isFinite, deltaX != 0 || deltaY != 0 else { return false }
        pendingMouseX = Self.clampMouseDelta(pendingMouseX + deltaX)
        pendingMouseY = Self.clampMouseDelta(pendingMouseY + deltaY)
        return true
    }

    mutating func clearKeyboard() {
        heldKeys.removeAll(keepingCapacity: true)
    }

    mutating func clearMouse() {
        pendingMouseX = 0
        pendingMouseY = 0
    }

    mutating func reset() {
        clearKeyboard()
        clearMouse()
    }

    mutating func consumeFrame() -> KeyboardMouseFrame {
        var frame = KeyboardMouseFrame()
        frame.hasKeyboardInput = !heldKeys.isEmpty

        let horizontal = Self.digitalAxis(negative: heldKeys.contains(.a),
                                          positive: heldKeys.contains(.d))
        let vertical = Self.digitalAxis(negative: heldKeys.contains(.w),
                                        positive: heldKeys.contains(.s))
        frame.leftX = Self.axisByte(horizontal)
        frame.leftY = Self.axisByte(vertical)

        if heldKeys.contains(.leftArrow) { frame.buttons.insert(.square) }
        if heldKeys.contains(.rightArrow) { frame.buttons.insert(.circle) }
        if heldKeys.contains(.upArrow) { frame.buttons.insert(.triangle) }
        if heldKeys.contains(.downArrow) {
            // Jak 1's PC_PORT speedrunner entry chord checks both shoulders. Ordinary
            // pause/progress is Start, supplied separately by Escape.
            frame.buttons.formUnion([.L1, .R1])
        }
        if heldKeys.contains(.escape) { frame.buttons.insert(.start) }
        if heldKeys.contains(.tab) {
            // Either rear trigger opens Jak 1's native progress/stats readout. Holding the pair
            // keeps the action layout-independent and distinct from Escape's full pause.
            frame.buttons.formUnion([.L2, .R2])
        }

        frame.hasMouseInput = pendingMouseX != 0 || pendingMouseY != 0
        frame.rightX = Self.mouseAxisByte(pendingMouseX)
        frame.rightY = Self.mouseAxisByte(pendingMouseY * Self.mouseYSign)
        clearMouse()
        return frame
    }

    private static func digitalAxis(negative: Bool, positive: Bool) -> Float {
        switch (negative, positive) {
        case (true, false): -1
        case (false, true): 1
        default: 0
        }
    }

    private static func clampMouseDelta(_ delta: Float) -> Float {
        max(-mouseDeltaForFullDeflection, min(mouseDeltaForFullDeflection, delta))
    }

    private static func mouseAxisByte(_ delta: Float) -> UInt8 {
        guard delta != 0 else { return UInt8(GOALPadAnalogNeutral) }
        let scaledMagnitude = abs(clampMouseDelta(delta)) / mouseDeltaForFullDeflection * 127
        let magnitude = max(mouseMinimumStickDeflection, scaledMagnitude)
        let signedMagnitude = delta < 0 ? -magnitude : magnitude
        return UInt8(max(0, min(255, (Float(GOALPadAnalogNeutral) + signedMagnitude).rounded())))
    }

    private static func axisByte(_ value: Float) -> UInt8 {
        let scaled = Float(GOALPadAnalogNeutral) + value * 127
        return UInt8(max(0, min(255, scaled.rounded())))
    }
}

/// Tracks recent activity independently from connectivity. An attached idle device therefore
/// cannot suppress the touch controls, while held input and the short post-input interval can.
struct InputActivityTracker {
    static let drivingTimeout: TimeInterval = 2

    private var lastControllerActivity = -Double.infinity
    private var lastKeyboardActivity = -Double.infinity
    private var lastMouseActivity = -Double.infinity

    mutating func noteController(at time: TimeInterval) {
        lastControllerActivity = time
    }

    mutating func noteKeyboard(at time: TimeInterval) {
        lastKeyboardActivity = time
    }

    mutating func noteMouse(at time: TimeInterval) {
        lastMouseActivity = time
    }

    mutating func disconnectController() {
        lastControllerActivity = -.infinity
    }

    mutating func disconnectKeyboard() {
        lastKeyboardActivity = -.infinity
    }

    mutating func disconnectMouse() {
        lastMouseActivity = -.infinity
    }

    mutating func reset() {
        disconnectController()
        disconnectKeyboard()
        disconnectMouse()
    }

    func isDriving(at time: TimeInterval,
                   controllerConnected: Bool,
                   keyboardConnected: Bool,
                   mouseConnected: Bool) -> Bool {
        (controllerConnected && time - lastControllerActivity < Self.drivingTimeout)
            || (keyboardConnected && time - lastKeyboardActivity < Self.drivingTimeout)
            || (mouseConnected && time - lastMouseActivity < Self.drivingTimeout)
    }
}
