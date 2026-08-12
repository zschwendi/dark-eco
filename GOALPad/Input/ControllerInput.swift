import CoreHaptics
import GameController
import OSLog
import QuartzCore

#if canImport(UIKit)
import UIKit
#endif

nonisolated private let inputLog = Logger(subsystem: "com.zephyrstudiosllc.eco",
                                          category: "Input")

/// Reads physical controller, keyboard, and mouse input through GameController, merges it with the
/// on-screen controls, and pushes the result at the engine once per frame, then reads the engine's
/// vibration request back out and drives the controller's haptics.
///
/// The engine has no input library of its own: `game/kernel/core/pad.h` is a state the host pushes
/// in, shaped like the PS2 pad `engine/ps2/pad.gc` expects. Everything Apple-specific stops here.
@MainActor
@Observable
final class ControllerInput {
    /// The port the engine reads first, and the only one GOALPad drives.
    static let primaryPort: Int32 = 0

    private(set) var controllerName: String?
    private(set) var isDualSense = false
    private(set) var buttons: GOALPadButton = []
    private(set) var leftStick: (x: UInt8, y: UInt8) = (UInt8(GOALPadAnalogNeutral),
                                                        UInt8(GOALPadAnalogNeutral))
    private(set) var rightStick: (x: UInt8, y: UInt8) = (UInt8(GOALPadAnalogNeutral),
                                                         UInt8(GOALPadAnalogNeutral))
    private(set) var rumble = GOALPadRumble(large: 0, small: 0)
    private(set) var isRumbleEnabled = true
    private(set) var primarySource: PrimaryInputSource = .automatic
    private(set) var bindings = Jak1InputBindings.standard

    var isConnected: Bool { controller != nil }
    var isKeyboardConnected: Bool { keyboard != nil }
    var isMouseConnected: Bool { mouse != nil }
    var isKeyboardMouseConnected: Bool { keyboard != nil || mouse != nil }
    var effectivePrimarySource: PrimaryInputSource { sourcePolicy.effectiveSource }

    var availablePrimarySources: [PrimaryInputSource] {
        PrimaryInputSource.allCases.filter {
            switch $0 {
            case .automatic: true
            case .touch: Self.touchAvailable
            case .controller: controller != nil
            case .keyboardMouse: isKeyboardMouseConnected
            }
        }
    }

    func isSourceAvailable(_ source: PrimaryInputSource) -> Bool {
        availablePrimarySources.contains(source)
    }

    /// True while a physical controller, keyboard, or mouse is the thing being played with.
    private(set) var isDriving = false

    private var controller: GCController?
    private var keyboard: GCKeyboard?
    private var mouse: GCMouse?
    private var motors: ControllerRumble?
    private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var keyboardMouseState = KeyboardMouseInputState()
    @ObservationIgnored private var heldShiftCodes: Set<GCKeyCode> = []
    @ObservationIgnored private var activity = InputActivityTracker()
    @ObservationIgnored private var controllerButtonSnapshots: [GOALPadButton] = []
    @ObservationIgnored private var lastObservedControllerButtons: GOALPadButton = []
    #if os(iOS)
    @ObservationIgnored private let deviceRumbleHaptics = DeviceRumbleHaptics()
    #endif

    func setPrimarySource(_ source: PrimaryInputSource) {
        guard source != primarySource else { return }
        primarySource = source
        noteDriving()
    }

    func setBindings(_ bindings: Jak1InputBindings) {
        guard bindings != self.bindings else { return }
        self.bindings = bindings
        resetControllerButtonSnapshots()
    }

    func setRumbleEnabled(_ enabled: Bool) {
        isRumbleEnabled = enabled
        GOALPadInputSetRumbleEnabled(Self.primaryPort, enabled)
        if !enabled { stopRumble() }
    }

    /// End recent physical-input suppression as soon as the player touches the screen.
    @discardableResult
    func reclaimTouchInput() -> Bool {
        guard activity.reclaimTouch(using: sourcePolicy) else { return false }
        noteDriving()
        return true
    }

    func startWatching() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) {
                [weak self] note in
                MainActor.assumeIsolated {
                    self?.controllerDidConnect(note.object as? GCController)
                }
            },
            center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) {
                [weak self] note in
                MainActor.assumeIsolated { self?.dropController(note.object as? GCController) }
            },
            center.addObserver(forName: .GCControllerDidBecomeCurrent,
                               object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    self?.adoptController(note.object as? GCController)
                }
            },
            center.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) {
                [weak self] note in
                MainActor.assumeIsolated { self?.adoptKeyboard(note.object as? GCKeyboard) }
            },
            center.addObserver(forName: .GCKeyboardDidDisconnect, object: nil, queue: .main) {
                [weak self] note in
                MainActor.assumeIsolated { self?.dropKeyboard(note.object as? GCKeyboard) }
            },
            center.addObserver(forName: .GCMouseDidConnect, object: nil, queue: .main) {
                [weak self] note in
                MainActor.assumeIsolated { self?.adoptMouse(note.object as? GCMouse) }
            },
            center.addObserver(forName: .GCMouseDidDisconnect, object: nil, queue: .main) {
                [weak self] note in
                MainActor.assumeIsolated { self?.dropMouse(note.object as? GCMouse) }
            },
            center.addObserver(forName: .GCMouseDidBecomeCurrent, object: nil, queue: .main) {
                [weak self] note in
                MainActor.assumeIsolated {
                    self?.mouseBecameCurrent(note.object as? GCMouse)
                }
            },
        ]
        adoptController(Self.preferredController())
        adoptKeyboard(GCKeyboard.coalesced)
        adoptMouse(GCMouse.current ?? GCMouse.mice().first)
        #if !os(visionOS)
        GCController.startWirelessControllerDiscovery()
        #endif
    }

    func stopWatching() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        #if !os(visionOS)
        GCController.stopWirelessControllerDiscovery()
        #endif
        releaseAll()
    }

    /// Read the physical inputs and hand the engine this frame's pad state. Non-iOS hosts use this
    /// path so an attached keyboard or mouse can provide the otherwise-disconnected port.
    func pushFrame() {
        pushFrame(merging: nil)
    }

    /// Push only an ordinary extended gamepad. The bounded visionOS game window deliberately does
    /// not expose touch, keyboard, mouse, or spatial-controller gameplay paths.
    func pushControllerFrame() {
        pushFrame(merging: nil, controllerOnly: true)
    }

    /// Read the physical inputs, merge the on-screen controls into them, and hand the engine this
    /// frame's pad state. Call before the frame runs.
    ///
    /// The sources are one pad: buttons are the union. A deflected controller stick wins first,
    /// then keyboard/mouse, then touch, so a stray finger cannot fight physical input. The port is
    /// reported as connected either way - on an iPad the on-screen controls are always present.
    func pushFrame(merging touch: TouchPadState) {
        pushFrame(merging: Optional(touch))
    }

    private func pushFrame(merging touch: TouchPadState?, controllerOnly: Bool = false) {
        var state = Self.neutralState()
        let now = CACurrentMediaTime()
        let policy = controllerOnly
            ? InputSourcePolicy(
                preference: .controller,
                touchAvailable: false,
                controllerConnected: controller != nil,
                keyboardMouseConnected: false
            )
            : sourcePolicy
        if policy.allowsController, let gamepad = controller?.extendedGamepad {
            let controllerFrame = bindings.controllerFrame(
                pressed: Self.pressedControls(of: gamepad),
                values: Self.controlValues(of: gamepad))
            let controllerSticks = Jak1MappedControllerSticks(
                roles: bindings.controllerStickRoles,
                analog: bindings.controllerAnalog,
                physicalLeftX: gamepad.leftThumbstick.xAxis.value,
                physicalLeftY: gamepad.leftThumbstick.yAxis.value,
                physicalRightX: gamepad.rightThumbstick.xAxis.value,
                physicalRightY: gamepad.rightThumbstick.yAxis.value)
            var polledButtons = controllerFrame.buttons
            if Self.touchpadIsPressed(on: gamepad) { polledButtons.insert(.select) }
            state.buttons = nextControllerButtons(polled: polledButtons)
            state.leftX = controllerSticks.leftX
            state.leftY = controllerSticks.leftY
            state.rightX = controllerSticks.rightX
            state.rightY = controllerSticks.rightY
            state.leftTrigger = controllerFrame.leftTrigger
            state.rightTrigger = controllerFrame.rightTrigger
            if Self.isActive(state) { activity.noteController(at: now) }
        }

        var preferred = (x: state.leftX, y: state.leftY)
        if !controllerOnly {
            let keyboardMouse = keyboardMouseState.consumeFrame(bindings: bindings)
            if keyboardMouse.hasKeyboardInput { activity.noteKeyboard(at: now) }
            if keyboardMouse.hasMouseInput { activity.noteMouse(at: now) }
            if policy.allowsKeyboardMouse {
                state.buttons.formUnion(keyboardMouse.buttons)
                preferred = PadStickMerge.preferred(
                    primaryX: state.leftX,
                    primaryY: state.leftY,
                    fallbackX: keyboardMouse.leftX,
                    fallbackY: keyboardMouse.leftY,
                    fallbackActive: PadStickMerge.isDeflected(x: keyboardMouse.leftX,
                                                              y: keyboardMouse.leftY))
                state.leftX = preferred.x
                state.leftY = preferred.y
                preferred = PadStickMerge.preferred(primaryX: state.rightX,
                                                    primaryY: state.rightY,
                                                    fallbackX: keyboardMouse.rightX,
                                                    fallbackY: keyboardMouse.rightY,
                                                    fallbackActive: keyboardMouse.hasMouseInput)
                state.rightX = preferred.x
                state.rightY = preferred.y
            }
        }
        noteDriving(at: now)

        if let touch, policy.allowsTouch {
            preferred = PadStickMerge.preferred(primaryX: state.leftX,
                                                primaryY: state.leftY,
                                                fallbackX: touch.leftX,
                                                fallbackY: touch.leftY,
                                                fallbackActive: touch.isLeftDeflected)
            state.leftX = preferred.x
            state.leftY = preferred.y
            preferred = PadStickMerge.preferred(primaryX: state.rightX,
                                                primaryY: state.rightY,
                                                fallbackX: touch.rightX,
                                                fallbackY: touch.rightY,
                                                fallbackActive: touch.isRightDeflected)
            state.rightX = preferred.x
            state.rightY = preferred.y
            state.buttons.formUnion(touch.buttons)
        }

        buttons = state.buttons
        leftStick = (state.leftX, state.leftY)
        rightStick = (state.rightX, state.rightY)
        if policy.allowsController || policy.allowsKeyboardMouse
            || (touch != nil && policy.allowsTouch) {
            GOALPadInputSetState(Self.primaryPort, state)
        } else {
            GOALPadInputSetDisconnected(Self.primaryPort)
        }
    }

    /// Read what GOAL asked the two motors to do and drive them.
    func applyRumble() {
        rumble = isRumbleEnabled
            ? GOALPadInputRumble(Self.primaryPort)
            : GOALPadRumble(large: 0, small: 0)
        motors?.set(large: rumble.large, small: rumble.small)
        #if os(iOS)
        deviceRumbleHaptics.update(rumble)
        #endif
    }

    func stopRumble() {
        rumble = GOALPadRumble(large: 0, small: 0)
        motors?.set(large: 0, small: 0)
        #if os(iOS)
        deviceRumbleHaptics.reset()
        #endif
    }

    // MARK: - Mapping

    private static func neutralState() -> GOALPadControllerState {
        GOALPadControllerState(buttons: [],
                               leftX: UInt8(GOALPadAnalogNeutral),
                               leftY: UInt8(GOALPadAnalogNeutral),
                               rightX: UInt8(GOALPadAnalogNeutral),
                               rightY: UInt8(GOALPadAnalogNeutral),
                               leftTrigger: 0,
                               rightTrigger: 0)
    }

    private static func isActive(_ state: GOALPadControllerState) -> Bool {
        !state.buttons.isEmpty || PadStickMerge.isDeflected(x: state.leftX, y: state.leftY)
            || PadStickMerge.isDeflected(x: state.rightX, y: state.rightY)
    }

    /// Only assigned when it changes: this runs every frame and every assignment to an observed
    /// property redraws whatever is watching it.
    private func noteDriving(at time: TimeInterval = CACurrentMediaTime()) {
        let recentPhysicalActivity = activity.isDriving(
            at: time,
            controllerConnected: controller != nil,
            keyboardConnected: keyboard != nil,
            mouseConnected: mouse != nil)
        let driving = sourcePolicy.suppressesTouchChrome(
            recentPhysicalActivity: recentPhysicalActivity)
        if driving != isDriving { isDriving = driving }
    }

    private static var touchAvailable: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    private var sourcePolicy: InputSourcePolicy {
        InputSourcePolicy(preference: primarySource,
                          touchAvailable: Self.touchAvailable,
                          controllerConnected: controller != nil,
                          keyboardMouseConnected: isKeyboardMouseConnected)
    }

    nonisolated private static func keyboardKey(for code: GCKeyCode) -> KeyboardMouseKey? {
        switch code {
        case .keyW: .w
        case .keyA: .a
        case .keyS: .s
        case .keyD: .d
        case .leftArrow: .leftArrow
        case .rightArrow: .rightArrow
        case .upArrow: .upArrow
        case .downArrow: .downArrow
        case .escape: .escape
        case .tab: .tab
        case .leftShift, .rightShift: .shift
        case .spacebar: .spacebar
        case .returnOrEnter: .returnOrEnter
        default: nil
        }
    }

    nonisolated private static func keyboardCode(for control: KeyboardMouseKey) -> GCKeyCode? {
        switch control {
        case .w: .keyW
        case .a: .keyA
        case .s: .keyS
        case .d: .keyD
        case .leftArrow: .leftArrow
        case .rightArrow: .rightArrow
        case .upArrow: .upArrow
        case .downArrow: .downArrow
        case .escape: .escape
        case .tab: .tab
        case .shift: nil
        case .spacebar: .spacebar
        case .returnOrEnter: .returnOrEnter
        case .mouseLeft, .mouseRight, .mouseMiddle: nil
        }
    }

    /// Keep Apple's positional controls distinct here so the persisted mapping, rather than a
    /// controller-brand special case, decides which PS2 pad action each one emits.
    nonisolated private static func pressedControls(
        of pad: GCExtendedGamepad
    ) -> Set<Jak1ControllerControl> {
        var pressed: Set<Jak1ControllerControl> = []
        func add(_ button: GCControllerButtonInput?, _ control: Jak1ControllerControl) {
            if button?.isPressed == true { pressed.insert(control) }
        }
        add(pad.buttonA, .buttonA)
        add(pad.buttonB, .buttonB)
        add(pad.buttonX, .buttonX)
        add(pad.buttonY, .buttonY)
        add(pad.dpad.up, .dpadUp)
        add(pad.dpad.down, .dpadDown)
        add(pad.dpad.left, .dpadLeft)
        add(pad.dpad.right, .dpadRight)
        add(pad.leftShoulder, .leftShoulder)
        add(pad.rightShoulder, .rightShoulder)
        add(pad.leftTrigger, .leftTrigger)
        add(pad.rightTrigger, .rightTrigger)
        add(pad.leftThumbstickButton, .leftThumbstickButton)
        add(pad.rightThumbstickButton, .rightThumbstickButton)
        add(pad.buttonMenu, .menu)
        add(pad.buttonOptions, .options)
        return pressed
    }

    nonisolated private static func touchpadIsPressed(on pad: GCExtendedGamepad) -> Bool {
        if let dualSense = pad as? GCDualSenseGamepad {
            return dualSense.touchpadButton.isPressed
        }
        if let dualShock = pad as? GCDualShockGamepad {
            return dualShock.touchpadButton.isPressed
        }
        return false
    }

    private static func controlValues(
        of pad: GCExtendedGamepad
    ) -> [Jak1ControllerControl: Float] {
        [
            .buttonA: pad.buttonA.value,
            .buttonB: pad.buttonB.value,
            .buttonX: pad.buttonX.value,
            .buttonY: pad.buttonY.value,
            .dpadUp: pad.dpad.up.value,
            .dpadDown: pad.dpad.down.value,
            .dpadLeft: pad.dpad.left.value,
            .dpadRight: pad.dpad.right.value,
            .leftShoulder: pad.leftShoulder.value,
            .rightShoulder: pad.rightShoulder.value,
            .leftTrigger: pad.leftTrigger.value,
            .rightTrigger: pad.rightTrigger.value,
            .leftThumbstickButton: pad.leftThumbstickButton?.value ?? 0,
            .rightThumbstickButton: pad.rightThumbstickButton?.value ?? 0,
            .menu: pad.buttonMenu.value,
            .options: pad.buttonOptions?.value ?? 0,
        ]
    }

    // MARK: - Connection

    private static func preferredController(excluding excluded: GCController? = nil) -> GCController? {
        if let current = GCController.current,
           current !== excluded,
           current.extendedGamepad != nil { return current }
        return GCController.controllers().first {
            $0 !== excluded && $0.extendedGamepad != nil
        }
    }

    private func controllerDidConnect(_ candidate: GCController?) {
        guard let candidate, candidate.extendedGamepad != nil else { return }
        guard controller == nil else { return }
        adoptController(Self.preferredController() ?? candidate)
    }

    private func adoptController(_ candidate: GCController?) {
        guard let candidate, candidate.extendedGamepad != nil else { return }
        guard controller !== candidate else { return }

        releaseController()
        controller = candidate
        controllerName = candidate.vendorName ?? candidate.productCategory
        isDualSense = candidate.extendedGamepad is GCDualSenseGamepad
        resetControllerButtonSnapshots()
        candidate.extendedGamepad?.valueChangedHandler = { [weak self, weak candidate] pad, _ in
            let pressed = Self.pressedControls(of: pad)
            let touchpadPressed = Self.touchpadIsPressed(on: pad)
            DispatchQueue.main.async { [weak self, weak candidate] in
                MainActor.assumeIsolated {
                    self?.recordControllerButtonSnapshot(
                        pressed: pressed,
                        touchpadPressed: touchpadPressed,
                        from: candidate)
                }
            }
        }
        motors = ControllerRumble(controller: candidate)
        if motors == nil {
            inputLog.error("Controller haptics are unavailable for \(self.controllerName ?? "unnamed", privacy: .public)")
        } else {
            inputLog.notice("Controller haptics ready for \(self.controllerName ?? "unnamed", privacy: .public)")
        }
        inputLog.notice("Controller connected: \(self.controllerName ?? "unnamed", privacy: .public) (DualSense: \(self.isDualSense))")
    }

    /// One controller went away. Another that is still attached takes over the port.
    private func dropController(_ leaving: GCController?) {
        guard leaving === controller else { return }
        releaseController()
        inputLog.notice("Controller disconnected")

        if let next = Self.preferredController(excluding: leaving) {
            adoptController(next)
        }
        noteDriving()
    }

    private func releaseController() {
        controller?.extendedGamepad?.valueChangedHandler = nil
        motors?.stop()
        motors = nil
        controller = nil
        controllerName = nil
        isDualSense = false
        controllerButtonSnapshots.removeAll()
        lastObservedControllerButtons = []
        activity.disconnectController()
    }

    private func resetControllerButtonSnapshots() {
        controllerButtonSnapshots.removeAll()
        guard let gamepad = controller?.extendedGamepad else {
            lastObservedControllerButtons = []
            return
        }
        let pressed = Self.pressedControls(of: gamepad)
        var buttons = bindings.controllerFrame(pressed: pressed).buttons
        if Self.touchpadIsPressed(on: gamepad) { buttons.insert(.select) }
        lastObservedControllerButtons = buttons
    }

    private func recordControllerButtonSnapshot(
        pressed: Set<Jak1ControllerControl>,
        touchpadPressed: Bool,
        from candidate: GCController?
    ) {
        guard controller === candidate else { return }
        var buttons = bindings.controllerFrame(pressed: pressed).buttons
        if touchpadPressed { buttons.insert(.select) }
        guard buttons != lastObservedControllerButtons else { return }
        lastObservedControllerButtons = buttons
        if controllerButtonSnapshots.last != buttons {
            controllerButtonSnapshots.append(buttons)
        }
        if controllerButtonSnapshots.count > 32 {
            controllerButtonSnapshots.removeFirst(controllerButtonSnapshots.count - 32)
        }
    }

    private func nextControllerButtons(polled: GOALPadButton) -> GOALPadButton {
        guard !controllerButtonSnapshots.isEmpty else {
            lastObservedControllerButtons = polled
            return polled
        }
        return controllerButtonSnapshots.removeFirst()
    }

    private func adoptKeyboard(_ candidate: GCKeyboard?) {
        guard let candidate, let input = candidate.keyboardInput else { return }
        guard keyboard !== candidate else { return }

        releaseKeyboard()
        keyboard = candidate
        input.keyChangedHandler = { [weak self, weak candidate] _, _, code, pressed in
            guard let key = Self.keyboardKey(for: code) else { return }
            DispatchQueue.main.async { [weak self, weak candidate] in
                guard let self, self.keyboard === candidate else { return }
                let changed: Bool
                if key == .shift {
                    if pressed {
                        self.heldShiftCodes.insert(code)
                    } else {
                        self.heldShiftCodes.remove(code)
                    }
                    changed = self.keyboardMouseState.setKey(
                        .shift, pressed: !self.heldShiftCodes.isEmpty)
                } else {
                    changed = self.keyboardMouseState.setKey(key, pressed: pressed)
                }
                if changed {
                    if self.bindings.action(for: key) != nil {
                        self.activity.noteKeyboard(at: CACurrentMediaTime())
                        self.noteDriving()
                    }
                }
            }
        }
        let mappedCodes = KeyboardMouseKey.keyboardCases.compactMap(Self.keyboardCode(for:))
            + [GCKeyCode.leftShift, .rightShift]
        var adoptedHeldInput = false
        for code in mappedCodes where input.button(forKeyCode: code)?.isPressed == true {
            if let key = Self.keyboardKey(for: code) {
                if key == .shift { heldShiftCodes.insert(code) }
                let adoptedMappedKey = keyboardMouseState.setKey(key, pressed: true)
                    && bindings.action(for: key) != nil
                adoptedHeldInput = adoptedMappedKey || adoptedHeldInput
            }
        }
        if adoptedHeldInput {
            activity.noteKeyboard(at: CACurrentMediaTime())
            noteDriving()
        }
        inputLog.notice("Keyboard connected: \(candidate.vendorName ?? "unnamed", privacy: .public)")
    }

    private func dropKeyboard(_ leaving: GCKeyboard?) {
        guard leaving === keyboard else { return }
        releaseKeyboard()
        noteDriving()
        inputLog.notice("Keyboard disconnected")

        if let next = GCKeyboard.coalesced { adoptKeyboard(next) }
    }

    private func releaseKeyboard() {
        keyboard?.keyboardInput?.keyChangedHandler = nil
        keyboard = nil
        heldShiftCodes.removeAll()
        keyboardMouseState.clearKeyboard()
        activity.disconnectKeyboard()
    }

    private func adoptMouse(_ candidate: GCMouse?) {
        guard let candidate, let input = candidate.mouseInput else { return }
        guard mouse !== candidate else { return }

        releaseMouse()
        mouse = candidate
        input.mouseMovedHandler = { [weak self, weak candidate] _, deltaX, deltaY in
            DispatchQueue.main.async { [weak self, weak candidate] in
                guard let self, self.mouse === candidate else { return }
                if self.keyboardMouseState.addMouseMovement(
                    deltaX: deltaX,
                    deltaY: deltaY,
                    camera: self.bindings.mouseCamera) {
                    self.activity.noteMouse(at: CACurrentMediaTime())
                    self.noteDriving()
                }
            }
        }
        observeMouseButton(input.leftButton, as: .mouseLeft, from: candidate)
        observeMouseButton(input.rightButton, as: .mouseRight, from: candidate)
        observeMouseButton(input.middleButton, as: .mouseMiddle, from: candidate)
        inputLog.notice("Mouse connected: \(candidate.vendorName ?? "unnamed", privacy: .public)")
    }

    private func observeMouseButton(_ button: GCDeviceButtonInput?,
                                    as control: KeyboardMouseKey,
                                    from candidate: GCMouse) {
        guard let button else { return }
        button.pressedChangedHandler = { [weak self, weak candidate] _, _, pressed in
            DispatchQueue.main.async { [weak self, weak candidate] in
                guard let self, self.mouse === candidate else { return }
                if self.keyboardMouseState.setControl(control, pressed: pressed) {
                    if self.bindings.action(for: control) != nil {
                        self.activity.noteMouse(at: CACurrentMediaTime())
                        self.noteDriving()
                    }
                }
            }
        }
        if button.isPressed {
            _ = keyboardMouseState.setControl(control, pressed: true)
        }
    }

    private func dropMouse(_ leaving: GCMouse?) {
        guard leaving === mouse else { return }
        releaseMouse()
        noteDriving()
        inputLog.notice("Mouse disconnected")

        if let next = GCMouse.current ?? GCMouse.mice().first { adoptMouse(next) }
    }

    private func mouseBecameCurrent(_ candidate: GCMouse?) {
        adoptMouse(candidate)
        guard mouse === candidate else { return }
        activity.noteMouse(at: CACurrentMediaTime())
        noteDriving()
    }

    private func releaseMouse() {
        mouse?.mouseInput?.mouseMovedHandler = nil
        mouse?.mouseInput?.leftButton.pressedChangedHandler = nil
        mouse?.mouseInput?.rightButton?.pressedChangedHandler = nil
        mouse?.mouseInput?.middleButton?.pressedChangedHandler = nil
        mouse = nil
        keyboardMouseState.clearMouse()
        activity.disconnectMouse()
    }

    private func releaseAll() {
        releaseController()
        releaseKeyboard()
        releaseMouse()
        keyboardMouseState.reset()
        activity.reset()
        isDriving = false
        GOALPadInputSetDisconnected(Self.primaryPort)
    }
}

#if os(iOS)
/// UIKit cannot sustain the PS2 motors continuously, so translate engine rumble edges and
/// meaningful intensity rises into bounded impacts while preserving the engine's 0...255 scale.
@MainActor
private final class DeviceRumbleHaptics {
    private let impact = UIImpactFeedbackGenerator(style: .rigid)
    private var previousIntensity: CGFloat = 0
    private var previousLarge: UInt8 = 0
    private var lastImpactTime = -Double.infinity

    func update(_ rumble: GOALPadRumble) {
        let largeIntensity: CGFloat = rumble.large == 0 ? 0 : 1
        let intensity = max(largeIntensity, CGFloat(rumble.small) / 255)
        let now = CACurrentMediaTime()
        let startsRumbling = previousIntensity == 0 && intensity > 0
        let largeMotorPulse = previousLarge == 0 && rumble.large > 0
        let meaningfulRise = intensity - previousIntensity >= 0.12
        if intensity > 0, startsRumbling || largeMotorPulse || meaningfulRise,
           now - lastImpactTime >= 0.04 {
            impact.impactOccurred(intensity: max(0.18, intensity))
            impact.prepare()
            lastImpactTime = now
        }
        previousIntensity = intensity
        previousLarge = rumble.large
    }

    func reset() {
        previousIntensity = 0
        previousLarge = 0
    }
}
#endif
/// The two PS2 vibration channels, driven through Core Haptics. The engine's `large` motor is the
/// on/off one the PS2 pulsed to fake an intensity and `small` is the analog one; their strongest
/// requested intensity drives the controller's default haptic locality.
///
/// The DualSense's adaptive triggers are deliberately not driven: the PS2 pad had no such thing,
/// so there is nothing in the game asking for it.
@MainActor
private final class ControllerRumble {
    private var motor: Motor?

    init?(controller: GCController) {
        guard let haptics = controller.haptics else { return nil }
        motor = Motor(haptics: haptics, locality: .default)
        guard motor != nil else { return nil }
    }

    func set(large largeValue: UInt8, small smallValue: UInt8) {
        let largeIntensity: Float = largeValue == 0 ? 0 : 1
        let smallIntensity = Float(smallValue) / 255
        motor?.set(intensity: max(largeIntensity, smallIntensity))
    }

    func stop() {
        motor?.stop()
        motor = nil
    }

    /// One handle: a continuous haptic event whose intensity is updated in place, so a frame of
    /// rumble costs a parameter send rather than a new pattern.
    private final class Motor {
        private let engine: CHHapticEngine
        private var player: CHHapticAdvancedPatternPlayer?
        private var running = false

        init?(haptics: GCDeviceHaptics, locality: GCHapticsLocality) {
            guard haptics.supportedLocalities.contains(locality),
                  let engine = haptics.createEngine(withLocality: locality)
            else {
                return nil
            }
            self.engine = engine
            engine.isAutoShutdownEnabled = false
            engine.stoppedHandler = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.player = nil
                    self?.running = false
                }
            }
            engine.resetHandler = { [weak self] in
                Task { @MainActor [weak self] in
                    do {
                        try self?.restartEngine()
                    } catch {
                        inputLog.error("Rumble reset failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
            do {
                try restartEngine()
            } catch {
                inputLog.error("Haptics unavailable for \(locality.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }

        func set(intensity: Float) {
            do {
                if intensity > 0 {
                    if player == nil { try restartEngine() }
                    guard let player else { return }
                    try player.sendParameters(
                        [CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                                  value: intensity,
                                                  relativeTime: 0)],
                        atTime: CHHapticTimeImmediate)
                    if !running {
                        try player.start(atTime: CHHapticTimeImmediate)
                        running = true
                    }
                } else if running {
                    try player?.stop(atTime: CHHapticTimeImmediate)
                    running = false
                }
            } catch {
                inputLog.error("Rumble failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        func stop() {
            try? player?.stop(atTime: CHHapticTimeImmediate)
            running = false
            engine.stop()
        }

        private func restartEngine() throws {
            try engine.start()
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
                ],
                relativeTime: 0,
                duration: TimeInterval(GCHapticDurationInfinite))
            player = try engine.makeAdvancedPlayer(
                with: CHHapticPattern(events: [event], parameters: []))
            running = false
        }
    }
}
