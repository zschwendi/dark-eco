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

enum Jak1InputAction: String, CaseIterable, Codable, Hashable, Sendable {
    case moveForward
    case moveBackward
    case moveLeft
    case moveRight
    case cross
    case circle
    case square
    case triangle
    case dpadUp
    case dpadDown
    case dpadLeft
    case dpadRight
    case L1
    case R1
    case L2
    case R2
    case L3
    case R3
    case start
    case select
    case shoulderChord
    case stats

    var title: String {
        switch self {
        case .moveForward: "Move Forward"
        case .moveBackward: "Move Backward"
        case .moveLeft: "Move Left"
        case .moveRight: "Move Right"
        case .cross: "Cross"
        case .circle: "Circle"
        case .square: "Square"
        case .triangle: "Triangle"
        case .dpadUp: "D-Pad Up"
        case .dpadDown: "D-Pad Down"
        case .dpadLeft: "D-Pad Left"
        case .dpadRight: "D-Pad Right"
        case .L1: "L1"
        case .R1: "R1"
        case .L2: "L2"
        case .R2: "R2"
        case .L3: "L3"
        case .R3: "R3"
        case .start: "Start / Pause"
        case .select: "Select"
        case .shoulderChord: "L1 + R1"
        case .stats: "Stats"
        }
    }

    var buttons: GOALPadButton {
        switch self {
        case .moveForward, .moveBackward, .moveLeft, .moveRight: []
        case .cross: .cross
        case .circle: .circle
        case .square: .square
        case .triangle: .triangle
        case .dpadUp: .up
        case .dpadDown: .down
        case .dpadLeft: .left
        case .dpadRight: .right
        case .L1: .L1
        case .R1: .R1
        case .L2: .L2
        case .R2: .R2
        case .L3: .L3
        case .R3: .R3
        case .start: .start
        case .select: .select
        case .shoulderChord: [.L1, .R1]
        case .stats: [.L2, .R2]
        }
    }

    var isControllerBindable: Bool {
        switch self {
        case .moveForward, .moveBackward, .moveLeft, .moveRight: false
        default: true
        }
    }

    static var controllerChoices: [Self] {
        allCases.filter(\.isControllerBindable)
    }
}

enum Jak1ControllerControl: String, CaseIterable, Codable, Hashable, Sendable {
    case buttonA
    case buttonB
    case buttonX
    case buttonY
    case dpadUp
    case dpadDown
    case dpadLeft
    case dpadRight
    case leftShoulder
    case rightShoulder
    case leftTrigger
    case rightTrigger
    case leftThumbstickButton
    case rightThumbstickButton
    case menu
    case options

    var title: String {
        switch self {
        case .buttonA: "Bottom Face (A / Cross)"
        case .buttonB: "Right Face (B / Circle)"
        case .buttonX: "Left Face (X / Square)"
        case .buttonY: "Top Face (Y / Triangle)"
        case .dpadUp: "D-Pad Up"
        case .dpadDown: "D-Pad Down"
        case .dpadLeft: "D-Pad Left"
        case .dpadRight: "D-Pad Right"
        case .leftShoulder: "Left Shoulder"
        case .rightShoulder: "Right Shoulder"
        case .leftTrigger: "Left Trigger"
        case .rightTrigger: "Right Trigger"
        case .leftThumbstickButton: "Left Stick Click"
        case .rightThumbstickButton: "Right Stick Click"
        case .menu: "Menu / Options"
        case .options: "Options / Create"
        }
    }
}

/// Only these named keyboard and mouse controls can become gameplay input. In particular, ordinary
/// typing never falls through to a gameplay action merely because bindings are customizable.
enum KeyboardMouseKey: String, CaseIterable, Codable, Hashable, Sendable {
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
    case spacebar
    case returnOrEnter
    case mouseLeft
    case mouseRight
    case mouseMiddle

    static var keyboardCases: [Self] { allCases.filter(\.isKeyboard) }
    static var mouseCases: [Self] { allCases.filter { !$0.isKeyboard } }

    var isKeyboard: Bool {
        switch self {
        case .mouseLeft, .mouseRight, .mouseMiddle: false
        default: true
        }
    }

    var title: String {
        switch self {
        case .w: "W"
        case .a: "A"
        case .s: "S"
        case .d: "D"
        case .leftArrow: "Left Arrow"
        case .rightArrow: "Right Arrow"
        case .upArrow: "Up Arrow"
        case .downArrow: "Down Arrow"
        case .escape: "Escape"
        case .tab: "Tab"
        case .spacebar: "Space"
        case .returnOrEnter: "Return / Enter"
        case .mouseLeft: "Left Mouse Button"
        case .mouseRight: "Right Mouse Button"
        case .mouseMiddle: "Middle Mouse Button"
        }
    }
}

struct Jak1InputBindings: Codable, Equatable, Sendable {
    struct ControllerBinding: Codable, Equatable, Sendable {
        let control: Jak1ControllerControl
        let action: Jak1InputAction
    }

    struct KeyboardMouseBinding: Codable, Equatable, Sendable {
        let control: KeyboardMouseKey
        let action: Jak1InputAction
    }

    static let standard = Jak1InputBindings(
        controllerBindings: [
            .init(control: .buttonA, action: .cross),
            .init(control: .buttonB, action: .circle),
            .init(control: .buttonX, action: .square),
            .init(control: .buttonY, action: .triangle),
            .init(control: .dpadUp, action: .dpadUp),
            .init(control: .dpadDown, action: .dpadDown),
            .init(control: .dpadLeft, action: .dpadLeft),
            .init(control: .dpadRight, action: .dpadRight),
            .init(control: .leftShoulder, action: .L1),
            .init(control: .rightShoulder, action: .R1),
            .init(control: .leftTrigger, action: .L2),
            .init(control: .rightTrigger, action: .R2),
            .init(control: .leftThumbstickButton, action: .L3),
            .init(control: .rightThumbstickButton, action: .R3),
            .init(control: .menu, action: .start),
            .init(control: .options, action: .select),
        ],
        keyboardMouseBindings: [
            .init(control: .w, action: .moveForward),
            .init(control: .a, action: .moveLeft),
            .init(control: .s, action: .moveBackward),
            .init(control: .d, action: .moveRight),
            .init(control: .leftArrow, action: .square),
            .init(control: .rightArrow, action: .circle),
            .init(control: .upArrow, action: .triangle),
            .init(control: .downArrow, action: .shoulderChord),
            .init(control: .escape, action: .start),
            .init(control: .tab, action: .stats),
        ])

    private(set) var controllerBindings: [ControllerBinding]
    private(set) var keyboardMouseBindings: [KeyboardMouseBinding]

    init(controllerBindings: [ControllerBinding],
         keyboardMouseBindings: [KeyboardMouseBinding]) {
        self.controllerBindings = Self.normalized(controllerBindings)
        self.keyboardMouseBindings = Self.normalized(keyboardMouseBindings)
    }

    func action(for control: Jak1ControllerControl) -> Jak1InputAction? {
        controllerBindings.first { $0.control == control }?.action
    }

    func action(for control: KeyboardMouseKey) -> Jak1InputAction? {
        keyboardMouseBindings.first { $0.control == control }?.action
    }

    mutating func setControllerAction(_ action: Jak1InputAction?,
                                      for control: Jak1ControllerControl) {
        guard action?.isControllerBindable != false, action != self.action(for: control) else {
            return
        }
        var mapping = Dictionary(uniqueKeysWithValues: controllerBindings.map {
            ($0.control, $0.action)
        })
        let previous = mapping.removeValue(forKey: control)
        if let action {
            if let owner = Jak1ControllerControl.allCases.first(where: { mapping[$0] == action }) {
                mapping[owner] = previous
            }
            mapping[control] = action
        }
        controllerBindings = Self.normalized(mapping.map {
            ControllerBinding(control: $0.key, action: $0.value)
        })
    }

    mutating func setKeyboardMouseAction(_ action: Jak1InputAction?,
                                         for control: KeyboardMouseKey) {
        guard action != self.action(for: control) else { return }
        var mapping = Dictionary(uniqueKeysWithValues: keyboardMouseBindings.map {
            ($0.control, $0.action)
        })
        let previous = mapping.removeValue(forKey: control)
        if let action {
            if let owner = KeyboardMouseKey.allCases.first(where: { mapping[$0] == action }) {
                mapping[owner] = previous
            }
            mapping[control] = action
        }
        keyboardMouseBindings = Self.normalized(mapping.map {
            KeyboardMouseBinding(control: $0.key, action: $0.value)
        })
    }

    func controllerFrame(pressed: Set<Jak1ControllerControl>,
                         values: [Jak1ControllerControl: Float] = [:]) -> Jak1MappedControllerFrame {
        var buttons: GOALPadButton = []
        for control in pressed {
            if let action = action(for: control) { buttons.formUnion(action.buttons) }
        }
        let leftTrigger = triggerByte(for: .L2, values: values)
        let rightTrigger = triggerByte(for: .R2, values: values)
        return Jak1MappedControllerFrame(buttons: buttons,
                                         leftTrigger: leftTrigger,
                                         rightTrigger: rightTrigger)
    }

    private func triggerByte(for action: Jak1InputAction,
                             values: [Jak1ControllerControl: Float]) -> UInt8 {
        let value = controllerBindings.lazy
            .filter { $0.action == action }
            .compactMap { values[$0.control] }
            .max() ?? 0
        return UInt8(max(0, min(255, (value * 255).rounded())))
    }

    private static func normalized(_ bindings: [ControllerBinding]) -> [ControllerBinding] {
        let requested = Dictionary(bindings.map { ($0.control, $0.action) },
                                   uniquingKeysWith: { _, latest in latest })
        var claimed: Set<Jak1InputAction> = []
        return Jak1ControllerControl.allCases.compactMap { control in
            guard let action = requested[control], action.isControllerBindable,
                  claimed.insert(action).inserted else { return nil }
            return ControllerBinding(control: control, action: action)
        }
    }

    private static func normalized(_ bindings: [KeyboardMouseBinding]) -> [KeyboardMouseBinding] {
        let requested = Dictionary(bindings.map { ($0.control, $0.action) },
                                   uniquingKeysWith: { _, latest in latest })
        var claimed: Set<Jak1InputAction> = []
        return KeyboardMouseKey.allCases.compactMap { control in
            guard let action = requested[control], claimed.insert(action).inserted else { return nil }
            return KeyboardMouseBinding(control: control, action: action)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case controller
        case keyboardMouse
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let controller = try container.decodeIfPresent([ControllerBinding].self, forKey: .controller)
            ?? Self.standard.controllerBindings
        let keyboardMouse = try container.decodeIfPresent([KeyboardMouseBinding].self,
                                                           forKey: .keyboardMouse)
            ?? Self.standard.keyboardMouseBindings
        self.init(controllerBindings: controller, keyboardMouseBindings: keyboardMouse)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(controllerBindings, forKey: .controller)
        try container.encode(keyboardMouseBindings, forKey: .keyboardMouse)
    }
}

struct Jak1MappedControllerFrame: Equatable {
    var buttons: GOALPadButton
    var leftTrigger: UInt8
    var rightTrigger: UInt8
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

    private var heldControls: Set<KeyboardMouseKey> = []
    private var pendingMouseX: Float = 0
    private var pendingMouseY: Float = 0

    @discardableResult
    mutating func setKey(_ key: KeyboardMouseKey, pressed: Bool) -> Bool {
        setControl(key, pressed: pressed)
    }

    @discardableResult
    mutating func setControl(_ control: KeyboardMouseKey, pressed: Bool) -> Bool {
        if pressed {
            return heldControls.insert(control).inserted
        }
        return heldControls.remove(control) != nil
    }

    @discardableResult
    mutating func addMouseMovement(deltaX: Float, deltaY: Float) -> Bool {
        guard deltaX.isFinite, deltaY.isFinite, deltaX != 0 || deltaY != 0 else { return false }
        pendingMouseX = Self.clampMouseDelta(pendingMouseX + deltaX)
        pendingMouseY = Self.clampMouseDelta(pendingMouseY + deltaY)
        return true
    }

    mutating func clearKeyboard() {
        heldControls.subtract(KeyboardMouseKey.keyboardCases)
    }

    mutating func clearMouse() {
        heldControls.subtract(KeyboardMouseKey.mouseCases)
        pendingMouseX = 0
        pendingMouseY = 0
    }

    mutating func reset() {
        clearKeyboard()
        clearMouse()
    }

    mutating func consumeFrame(bindings: Jak1InputBindings = .standard) -> KeyboardMouseFrame {
        var frame = KeyboardMouseFrame()
        let activeControls = heldControls.filter { bindings.action(for: $0) != nil }
        frame.hasKeyboardInput = activeControls.contains(where: \.isKeyboard)
        let actions = Set(activeControls.compactMap { bindings.action(for: $0) })

        let horizontal = Self.digitalAxis(negative: actions.contains(.moveLeft),
                                          positive: actions.contains(.moveRight))
        let vertical = Self.digitalAxis(negative: actions.contains(.moveForward),
                                        positive: actions.contains(.moveBackward))
        frame.leftX = Self.axisByte(horizontal)
        frame.leftY = Self.axisByte(vertical)

        for action in actions { frame.buttons.formUnion(action.buttons) }

        frame.hasMouseInput = pendingMouseX != 0 || pendingMouseY != 0
            || activeControls.contains { !$0.isKeyboard }
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
