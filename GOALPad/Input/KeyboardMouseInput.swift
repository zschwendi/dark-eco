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

    var snapshotIndex: Int {
        switch self {
        case .buttonA: 0
        case .buttonB: 1
        case .buttonX: 2
        case .buttonY: 3
        case .dpadUp: 4
        case .dpadDown: 5
        case .dpadLeft: 6
        case .dpadRight: 7
        case .leftShoulder: 8
        case .rightShoulder: 9
        case .leftTrigger: 10
        case .rightTrigger: 11
        case .leftThumbstickButton: 12
        case .rightThumbstickButton: 13
        case .menu: 14
        case .options: 15
        }
    }

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

struct Jak1ControllerSnapshot: Equatable, Sendable {
    private(set) var pressedMask: UInt16
    private(set) var values: SIMD16<Float>

    init(pressedMask: UInt16 = 0, values: SIMD16<Float> = .zero) {
        self.pressedMask = pressedMask
        self.values = values
    }

    init(pressed: Set<Jak1ControllerControl>,
         values: [Jak1ControllerControl: Float] = [:]) {
        self.init()
        for control in Jak1ControllerControl.allCases {
            set(control, pressed: pressed.contains(control), value: values[control] ?? 0)
        }
    }

    mutating func set(_ control: Jak1ControllerControl, pressed: Bool, value: Float) {
        let bit = UInt16(1) << control.snapshotIndex
        if pressed {
            pressedMask |= bit
        } else {
            pressedMask &= ~bit
        }
        values[control.snapshotIndex] = value
    }

    func isPressed(_ control: Jak1ControllerControl) -> Bool {
        pressedMask & (UInt16(1) << control.snapshotIndex) != 0
    }

    func value(for control: Jak1ControllerControl) -> Float {
        values[control.snapshotIndex]
    }
}

enum Jak1ControllerStickRoles: String, CaseIterable, Codable, Sendable {
    case standard
    case swapped

    var title: String {
        switch self {
        case .standard: "Standard"
        case .swapped: "Swapped Sticks"
        }
    }
}

enum Jak1ControllerAnalogRole: CaseIterable, Hashable, Sendable {
    case movement
    case camera

    var title: String {
        switch self {
        case .movement: "Movement"
        case .camera: "Camera"
        }
    }
}

struct Jak1ControllerStickSettings: Codable, Equatable, Sendable {
    static let minimumSensitivityPercent = 50
    static let maximumSensitivityPercent = 200
    static let minimumDeadZonePercent = 0
    static let maximumDeadZonePercent = 50
    static let standard = Jak1ControllerStickSettings()

    private(set) var sensitivityPercent: Int
    private(set) var deadZonePercent: Int
    private(set) var invertHorizontal: Bool
    private(set) var invertVertical: Bool

    init(sensitivityPercent: Int = 100,
         deadZonePercent: Int = 0,
         invertHorizontal: Bool = false,
         invertVertical: Bool = false) {
        self.sensitivityPercent = Self.clampedSensitivity(sensitivityPercent)
        self.deadZonePercent = Self.clampedDeadZone(deadZonePercent)
        self.invertHorizontal = invertHorizontal
        self.invertVertical = invertVertical
    }

    mutating func setSensitivityPercent(_ percent: Int) {
        sensitivityPercent = Self.clampedSensitivity(percent)
    }

    mutating func setDeadZonePercent(_ percent: Int) {
        deadZonePercent = Self.clampedDeadZone(percent)
    }

    mutating func setInvertHorizontal(_ inverted: Bool) {
        invertHorizontal = inverted
    }

    mutating func setInvertVertical(_ inverted: Bool) {
        invertVertical = inverted
    }

    private static func clampedSensitivity(_ percent: Int) -> Int {
        max(minimumSensitivityPercent, min(maximumSensitivityPercent, percent))
    }

    private static func clampedDeadZone(_ percent: Int) -> Int {
        max(minimumDeadZonePercent, min(maximumDeadZonePercent, percent))
    }

    private enum CodingKeys: String, CodingKey {
        case sensitivityPercent
        case deadZonePercent
        case invertHorizontal
        case invertVertical
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sensitivityPercent: try container.decodeIfPresent(Int.self,
                                                               forKey: .sensitivityPercent) ?? 100,
            deadZonePercent: try container.decodeIfPresent(Int.self,
                                                            forKey: .deadZonePercent) ?? 0,
            invertHorizontal: try container.decodeIfPresent(Bool.self,
                                                              forKey: .invertHorizontal) ?? false,
            invertVertical: try container.decodeIfPresent(Bool.self,
                                                            forKey: .invertVertical) ?? false)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if sensitivityPercent != 100 {
            try container.encode(sensitivityPercent, forKey: .sensitivityPercent)
        }
        if deadZonePercent != 0 {
            try container.encode(deadZonePercent, forKey: .deadZonePercent)
        }
        if invertHorizontal {
            try container.encode(true, forKey: .invertHorizontal)
        }
        if invertVertical {
            try container.encode(true, forKey: .invertVertical)
        }
    }
}

struct Jak1ControllerAnalogSettings: Codable, Equatable, Sendable {
    static let standard = Jak1ControllerAnalogSettings()

    private(set) var movement: Jak1ControllerStickSettings
    private(set) var camera: Jak1ControllerStickSettings

    init(movement: Jak1ControllerStickSettings = .standard,
         camera: Jak1ControllerStickSettings = .standard) {
        self.movement = movement
        self.camera = camera
    }

    func settings(for role: Jak1ControllerAnalogRole) -> Jak1ControllerStickSettings {
        switch role {
        case .movement: movement
        case .camera: camera
        }
    }

    mutating func setSensitivityPercent(_ percent: Int, for role: Jak1ControllerAnalogRole) {
        update(role) { $0.setSensitivityPercent(percent) }
    }

    mutating func setDeadZonePercent(_ percent: Int, for role: Jak1ControllerAnalogRole) {
        update(role) { $0.setDeadZonePercent(percent) }
    }

    mutating func setInvertHorizontal(_ inverted: Bool, for role: Jak1ControllerAnalogRole) {
        update(role) { $0.setInvertHorizontal(inverted) }
    }

    mutating func setInvertVertical(_ inverted: Bool, for role: Jak1ControllerAnalogRole) {
        update(role) { $0.setInvertVertical(inverted) }
    }

    private mutating func update(
        _ role: Jak1ControllerAnalogRole,
        _ operation: (inout Jak1ControllerStickSettings) -> Void
    ) {
        switch role {
        case .movement: operation(&movement)
        case .camera: operation(&camera)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case movement
        case camera
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            movement: try container.decodeIfPresent(Jak1ControllerStickSettings.self,
                                                     forKey: .movement) ?? .standard,
            camera: try container.decodeIfPresent(Jak1ControllerStickSettings.self,
                                                   forKey: .camera) ?? .standard)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if movement != .standard {
            try container.encode(movement, forKey: .movement)
        }
        if camera != .standard {
            try container.encode(camera, forKey: .camera)
        }
    }
}

/// Converts Game Controller axes to the PS2 pad byte convention, then assigns each complete
/// physical stick to its Jak 1 role. Tuning is applied to that complete logical-role vector so
/// customization can never send a physical stick's X and Y components to different owners.
struct Jak1MappedControllerSticks: Equatable, Sendable {
    let leftX: UInt8
    let leftY: UInt8
    let rightX: UInt8
    let rightY: UInt8

    init(roles: Jak1ControllerStickRoles,
         analog: Jak1ControllerAnalogSettings = .standard,
         physicalLeftX: Float,
         physicalLeftY: Float,
         physicalRightX: Float,
         physicalRightY: Float) {
        let physicalLeft = (x: physicalLeftX, y: -physicalLeftY)
        let physicalRight = (x: physicalRightX, y: -physicalRightY)
        let movement: (x: Float, y: Float)
        let camera: (x: Float, y: Float)
        switch roles {
        case .standard:
            movement = physicalLeft
            camera = physicalRight
        case .swapped:
            movement = physicalRight
            camera = physicalLeft
        }
        let tunedMovement = Self.tuned(movement, settings: analog.movement)
        let tunedCamera = Self.tuned(camera, settings: analog.camera)
        (leftX, leftY) = (Self.axisByte(tunedMovement.x), Self.axisByte(tunedMovement.y))
        (rightX, rightY) = (Self.axisByte(tunedCamera.x), Self.axisByte(tunedCamera.y))
    }

    private static func tuned(
        _ vector: (x: Float, y: Float),
        settings: Jak1ControllerStickSettings
    ) -> (x: Float, y: Float) {
        guard vector.x.isFinite, vector.y.isFinite else { return (0, 0) }
        var x = max(-1, min(1, vector.x))
        var y = max(-1, min(1, vector.y))
        let magnitude = hypotf(x, y)
        let deadZone = Float(settings.deadZonePercent) / 100
        guard magnitude > deadZone else { return (0, 0) }

        let remainingScale = deadZone == 0
            ? 1
            : (magnitude - deadZone) / ((1 - deadZone) * magnitude)
        let sensitivityScale = Float(settings.sensitivityPercent) / 100
        x *= remainingScale * sensitivityScale
        y *= remainingScale * sensitivityScale

        // Saturate the complete vector against the PS2 byte square instead of clamping each
        // component independently, which would change the requested direction near an edge.
        let largestComponent = max(abs(x), abs(y))
        if largestComponent > 1 {
            x /= largestComponent
            y /= largestComponent
        }
        if settings.invertHorizontal { x = -x }
        if settings.invertVertical { y = -y }
        return (x, y)
    }

    private static func axisByte(_ value: Float) -> UInt8 {
        let scaled = Float(GOALPadAnalogNeutral) + value * 127
        return UInt8(max(0, min(255, scaled.rounded())))
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
    case shift
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
        case .shift: "Shift"
        case .spacebar: "Space"
        case .returnOrEnter: "Return / Enter"
        case .mouseLeft: "Left Mouse Button"
        case .mouseRight: "Right Mouse Button"
        case .mouseMiddle: "Middle Mouse Button"
        }
    }
}

struct Jak1MouseCameraSettings: Codable, Equatable, Sendable {
    static let minimumSensitivityPercent = 25
    static let maximumSensitivityPercent = 400
    static let standard = Jak1MouseCameraSettings()

    private(set) var sensitivityPercent: Int
    private(set) var invertHorizontal: Bool
    private(set) var invertVertical: Bool

    init(sensitivityPercent: Int = 250,
         invertHorizontal: Bool = false,
         invertVertical: Bool = false) {
        self.sensitivityPercent = Self.clampedSensitivity(sensitivityPercent)
        self.invertHorizontal = invertHorizontal
        self.invertVertical = invertVertical
    }

    mutating func setSensitivityPercent(_ percent: Int) {
        sensitivityPercent = Self.clampedSensitivity(percent)
    }

    mutating func setInvertHorizontal(_ inverted: Bool) {
        invertHorizontal = inverted
    }

    mutating func setInvertVertical(_ inverted: Bool) {
        invertVertical = inverted
    }

    private static func clampedSensitivity(_ percent: Int) -> Int {
        max(minimumSensitivityPercent, min(maximumSensitivityPercent, percent))
    }

    private enum CodingKeys: String, CodingKey {
        case sensitivityPercent
        case invertHorizontal
        case invertVertical
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sensitivityPercent: try container.decodeIfPresent(Int.self,
                                                               forKey: .sensitivityPercent) ?? 250,
            invertHorizontal: try container.decodeIfPresent(Bool.self,
                                                              forKey: .invertHorizontal) ?? false,
            invertVertical: try container.decodeIfPresent(Bool.self,
                                                            forKey: .invertVertical) ?? false)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if sensitivityPercent != 250 {
            try container.encode(sensitivityPercent, forKey: .sensitivityPercent)
        }
        if invertHorizontal {
            try container.encode(true, forKey: .invertHorizontal)
        }
        if invertVertical {
            try container.encode(true, forKey: .invertVertical)
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
            .init(control: .shift, action: .L1),
            .init(control: .spacebar, action: .cross),
        ],
        controllerStickRoles: .standard,
        controllerAnalog: .standard,
        mouseCamera: .standard)

    private(set) var controllerBindings: [ControllerBinding]
    private(set) var keyboardMouseBindings: [KeyboardMouseBinding]
    private(set) var controllerStickRoles: Jak1ControllerStickRoles
    private(set) var controllerAnalog: Jak1ControllerAnalogSettings
    private(set) var mouseCamera: Jak1MouseCameraSettings

    init(controllerBindings: [ControllerBinding],
         keyboardMouseBindings: [KeyboardMouseBinding],
         controllerStickRoles: Jak1ControllerStickRoles = .standard,
         controllerAnalog: Jak1ControllerAnalogSettings = .standard,
         mouseCamera: Jak1MouseCameraSettings = .standard) {
        self.controllerBindings = Self.normalized(controllerBindings)
        self.keyboardMouseBindings = Self.normalized(keyboardMouseBindings)
        self.controllerStickRoles = controllerStickRoles
        self.controllerAnalog = controllerAnalog
        self.mouseCamera = mouseCamera
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

    mutating func setControllerStickRoles(_ roles: Jak1ControllerStickRoles) {
        controllerStickRoles = roles
    }

    mutating func setControllerSensitivityPercent(_ percent: Int,
                                                  for role: Jak1ControllerAnalogRole) {
        controllerAnalog.setSensitivityPercent(percent, for: role)
    }

    mutating func setControllerDeadZonePercent(_ percent: Int,
                                               for role: Jak1ControllerAnalogRole) {
        controllerAnalog.setDeadZonePercent(percent, for: role)
    }

    mutating func setControllerInvertHorizontal(_ inverted: Bool,
                                                for role: Jak1ControllerAnalogRole) {
        controllerAnalog.setInvertHorizontal(inverted, for: role)
    }

    mutating func setControllerInvertVertical(_ inverted: Bool,
                                              for role: Jak1ControllerAnalogRole) {
        controllerAnalog.setInvertVertical(inverted, for: role)
    }

    mutating func setMouseCameraSensitivityPercent(_ percent: Int) {
        mouseCamera.setSensitivityPercent(percent)
    }

    mutating func setMouseCameraInvertHorizontal(_ inverted: Bool) {
        mouseCamera.setInvertHorizontal(inverted)
    }

    mutating func setMouseCameraInvertVertical(_ inverted: Bool) {
        mouseCamera.setInvertVertical(inverted)
    }

    func controllerFrame(pressed: Set<Jak1ControllerControl>,
                         values: [Jak1ControllerControl: Float] = [:]) -> Jak1MappedControllerFrame {
        controllerFrame(snapshot: Jak1ControllerSnapshot(pressed: pressed, values: values))
    }

    func controllerFrame(snapshot: Jak1ControllerSnapshot) -> Jak1MappedControllerFrame {
        var buttons: GOALPadButton = []
        var leftTrigger: Float = 0
        var rightTrigger: Float = 0
        for binding in controllerBindings {
            if snapshot.isPressed(binding.control) {
                buttons.formUnion(binding.action.buttons)
            }
            switch binding.action {
            case .L2:
                leftTrigger = max(leftTrigger, snapshot.value(for: binding.control))
            case .R2:
                rightTrigger = max(rightTrigger, snapshot.value(for: binding.control))
            default:
                break
            }
        }
        return Jak1MappedControllerFrame(buttons: buttons,
                                         leftTrigger: Self.triggerByte(leftTrigger),
                                         rightTrigger: Self.triggerByte(rightTrigger))
    }

    private static func triggerByte(_ value: Float) -> UInt8 {
        UInt8(max(0, min(255, (value * 255).rounded())))
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
        case controllerStickRoles
        case controllerAnalog
        case mouseCamera
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let controller = try container.decodeIfPresent([ControllerBinding].self, forKey: .controller)
            ?? Self.standard.controllerBindings
        let keyboardMouse = try container.decodeIfPresent([KeyboardMouseBinding].self,
                                                           forKey: .keyboardMouse)
            ?? Self.standard.keyboardMouseBindings
        let controllerStickRoles = try container.decodeIfPresent(Jak1ControllerStickRoles.self,
                                                                  forKey: .controllerStickRoles)
            ?? .standard
        let controllerAnalog = try container.decodeIfPresent(Jak1ControllerAnalogSettings.self,
                                                              forKey: .controllerAnalog)
            ?? .standard
        let mouseCamera = try container.decodeIfPresent(Jak1MouseCameraSettings.self,
                                                        forKey: .mouseCamera)
            ?? .standard
        self.init(controllerBindings: controller, keyboardMouseBindings: keyboardMouse,
                  controllerStickRoles: controllerStickRoles, controllerAnalog: controllerAnalog,
                  mouseCamera: mouseCamera)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(controllerBindings, forKey: .controller)
        try container.encode(keyboardMouseBindings, forKey: .keyboardMouse)
        if controllerStickRoles != .standard {
            try container.encode(controllerStickRoles, forKey: .controllerStickRoles)
        }
        if controllerAnalog != .standard {
            try container.encode(controllerAnalog, forKey: .controllerAnalog)
        }
        if mouseCamera != .standard {
            try container.encode(mouseCamera, forKey: .mouseCamera)
        }
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

    /// Touch and a connected controller are always additive. The preference can choose whether a
    /// keyboard/mouse joins them, but it must never strand either of the primary play methods.
    var allowsTouch: Bool { touchAvailable }

    var allowsController: Bool { controllerConnected }

    var allowsKeyboardMouse: Bool {
        keyboardMouseConnected
            && (effectiveSource == .automatic || effectiveSource == .keyboardMouse)
    }

    var allowsTouchRecovery: Bool { touchAvailable }

    func suppressesTouchChrome(recentPhysicalActivity: Bool) -> Bool {
        switch effectiveSource {
        case .automatic, .controller, .keyboardMouse: recentPhysicalActivity
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
    /// Raw Game Controller mouse units needed for full deflection at the default 100% setting.
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
    mutating func addMouseMovement(deltaX: Float,
                                   deltaY: Float,
                                   camera: Jak1MouseCameraSettings = .standard) -> Bool {
        guard deltaX.isFinite, deltaY.isFinite, deltaX != 0 || deltaY != 0 else { return false }
        let sensitivity = Float(camera.sensitivityPercent) / 100
        let horizontalSign: Float = camera.invertHorizontal ? -1 : 1
        let verticalSign = Self.mouseYSign * (camera.invertVertical ? -1 : 1)
        pendingMouseX = Self.clampMouseDelta(
            pendingMouseX + deltaX * sensitivity * horizontalSign)
        pendingMouseY = Self.clampMouseDelta(
            pendingMouseY + deltaY * sensitivity * verticalSign)
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
        guard !heldControls.isEmpty || pendingMouseX != 0 || pendingMouseY != 0 else {
            return KeyboardMouseFrame()
        }

        var frame = KeyboardMouseFrame()
        var movesForward = false
        var movesBackward = false
        var movesLeft = false
        var movesRight = false
        for control in heldControls {
            guard let action = bindings.action(for: control) else { continue }
            if control.isKeyboard {
                frame.hasKeyboardInput = true
            } else {
                frame.hasMouseInput = true
            }
            switch action {
            case .moveForward:
                movesForward = true
            case .moveBackward:
                movesBackward = true
            case .moveLeft:
                movesLeft = true
            case .moveRight:
                movesRight = true
            default:
                frame.buttons.formUnion(action.buttons)
            }
        }

        let horizontal = Self.digitalAxis(negative: movesLeft, positive: movesRight)
        let vertical = Self.digitalAxis(negative: movesForward, positive: movesBackward)
        frame.leftX = Self.axisByte(horizontal)
        frame.leftY = Self.axisByte(vertical)
        frame.hasMouseInput = frame.hasMouseInput || pendingMouseX != 0 || pendingMouseY != 0
        frame.rightX = Self.mouseAxisByte(pendingMouseX)
        frame.rightY = Self.mouseAxisByte(pendingMouseY)
        heldControls.remove(.mouseLeft)
        heldControls.remove(.mouseRight)
        heldControls.remove(.mouseMiddle)
        pendingMouseX = 0
        pendingMouseY = 0
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

    /// A screen touch always ends the short physical-input ownership interval when touch exists.
    @discardableResult
    mutating func reclaimTouch(using policy: InputSourcePolicy) -> Bool {
        guard policy.allowsTouchRecovery else { return false }
        reset()
        return true
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
