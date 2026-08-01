import CoreHaptics
import GameController
import OSLog

nonisolated private let inputLog = Logger(subsystem: "com.zephyrstudiosllc.GOALPad",
                                          category: "Input")

/// Reads a physical controller through GameController and pushes it at the engine once per frame,
/// then reads the engine's vibration request back out and drives the controller's haptics.
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

    var isConnected: Bool { controller != nil }

    private var controller: GCController?
    private var motors: ControllerRumble?
    private var observers: [NSObjectProtocol] = []

    func startWatching() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) {
                [weak self] note in
                MainActor.assumeIsolated { self?.adopt(note.object as? GCController) }
            },
            center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) {
                [weak self] note in
                MainActor.assumeIsolated { self?.drop(note.object as? GCController) }
            },
        ]
        adopt(GCController.current ?? GCController.controllers().first)
        GCController.startWirelessControllerDiscovery()
    }

    func stopWatching() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        GCController.stopWirelessControllerDiscovery()
        release()
    }

    /// Read the controller and hand the engine this frame's pad state. Call before the frame runs.
    func pushFrame() {
        guard let gamepad = controller?.extendedGamepad else {
            buttons = []
            leftStick = (UInt8(GOALPadAnalogNeutral), UInt8(GOALPadAnalogNeutral))
            rightStick = (UInt8(GOALPadAnalogNeutral), UInt8(GOALPadAnalogNeutral))
            GOALPadInputSetDisconnected(Self.primaryPort)
            return
        }

        buttons = Self.buttons(of: gamepad)
        leftStick = (Self.axisByte(gamepad.leftThumbstick.xAxis.value),
                     Self.axisByte(-gamepad.leftThumbstick.yAxis.value))
        rightStick = (Self.axisByte(gamepad.rightThumbstick.xAxis.value),
                      Self.axisByte(-gamepad.rightThumbstick.yAxis.value))

        var state = GOALPadControllerState()
        state.buttons = buttons
        state.leftX = leftStick.x
        state.leftY = leftStick.y
        state.rightX = rightStick.x
        state.rightY = rightStick.y
        state.leftTrigger = Self.triggerByte(gamepad.leftTrigger.value)
        state.rightTrigger = Self.triggerByte(gamepad.rightTrigger.value)
        GOALPadInputSetState(Self.primaryPort, state)
    }

    /// Read what GOAL asked the two motors to do and drive them.
    func applyRumble() {
        rumble = GOALPadInputRumble(Self.primaryPort)
        motors?.set(large: rumble.large, small: rumble.small)
    }

    func stopRumble() {
        rumble = GOALPadRumble(large: 0, small: 0)
        motors?.set(large: 0, small: 0)
    }

    // MARK: - Mapping

    /// The DualSense face buttons sit exactly where the PS2 ones did, and GameController names its
    /// face buttons by position, so A/B/X/Y are cross/circle/square/triangle without a special
    /// case. `buttonMenu` is Options and `buttonOptions` is Create, which are Start and Select.
    private static func buttons(of pad: GCExtendedGamepad) -> GOALPadButton {
        var pressed: GOALPadButton = []
        func add(_ button: GCControllerButtonInput?, _ bit: GOALPadButton) {
            if button?.isPressed == true { pressed.insert(bit) }
        }
        add(pad.buttonA, .cross)
        add(pad.buttonB, .circle)
        add(pad.buttonX, .square)
        add(pad.buttonY, .triangle)
        add(pad.dpad.up, .up)
        add(pad.dpad.down, .down)
        add(pad.dpad.left, .left)
        add(pad.dpad.right, .right)
        add(pad.leftShoulder, .L1)
        add(pad.rightShoulder, .R1)
        add(pad.leftTrigger, .L2)
        add(pad.rightTrigger, .R2)
        add(pad.leftThumbstickButton, .L3)
        add(pad.rightThumbstickButton, .R3)
        add(pad.buttonMenu, .start)
        add(pad.buttonOptions, .select)
        return pressed
    }

    /// GameController reports an axis as -1...1. The pad reports a byte per axis with 127 at rest,
    /// growing right and down, so the caller negates the Y axis before calling this.
    private static func axisByte(_ value: Float) -> UInt8 {
        let scaled = Float(GOALPadAnalogNeutral) + value * 127
        return UInt8(max(0, min(255, scaled.rounded())))
    }

    private static func triggerByte(_ value: Float) -> UInt8 {
        UInt8(max(0, min(255, (value * 255).rounded())))
    }

    // MARK: - Connection

    private func adopt(_ candidate: GCController?) {
        guard let candidate, candidate.extendedGamepad != nil else { return }
        guard controller !== candidate else { return }

        controller = candidate
        controllerName = candidate.vendorName ?? candidate.productCategory
        isDualSense = candidate.extendedGamepad is GCDualSenseGamepad
        motors = ControllerRumble(controller: candidate)
        inputLog.notice("Controller connected: \(self.controllerName ?? "unnamed", privacy: .public) (DualSense: \(self.isDualSense))")
    }

    /// One controller went away. Another that is still attached takes over the port.
    private func drop(_ leaving: GCController?) {
        guard leaving === controller else { return }
        release()
        inputLog.notice("Controller disconnected")

        if let next = GCController.controllers().first(where: { $0.extendedGamepad != nil }) {
            adopt(next)
        }
    }

    private func release() {
        motors?.stop()
        motors = nil
        controller = nil
        controllerName = nil
        isDualSense = false
        GOALPadInputSetDisconnected(Self.primaryPort)
    }
}

/// The two vibration motors, driven by Core Haptics. The engine's `large` motor is the on/off one
/// the PS2 pulsed to fake an intensity and `small` is the analog one; the two controller handles
/// are the closest thing a DualSense offers.
///
/// The DualSense's adaptive triggers are deliberately not driven: the PS2 pad had no such thing,
/// so there is nothing in the game asking for it.
@MainActor
private final class ControllerRumble {
    private var large: Motor?
    private var small: Motor?

    init?(controller: GCController) {
        guard let haptics = controller.haptics else { return nil }
        large = Motor(haptics: haptics, locality: .leftHandle)
        small = Motor(haptics: haptics, locality: .rightHandle)
        if large == nil && small == nil { return nil }
    }

    func set(large largeValue: UInt8, small smallValue: UInt8) {
        large?.set(intensity: Float(largeValue) / 255)
        small?.set(intensity: Float(smallValue) / 255)
    }

    func stop() {
        large?.stop()
        small?.stop()
        large = nil
        small = nil
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
            engine.isAutoShutdownEnabled = true
            do {
                try engine.start()
                let event = CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
                    ],
                    relativeTime: 0,
                    duration: TimeInterval(GCHapticDurationInfinite))
                player = try engine.makeAdvancedPlayer(with: CHHapticPattern(events: [event],
                                                                            parameters: []))
            } catch {
                inputLog.error("Haptics unavailable for \(locality.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }

        func set(intensity: Float) {
            guard let player else { return }
            do {
                if intensity > 0 {
                    if !running {
                        try player.start(atTime: CHHapticTimeImmediate)
                        running = true
                    }
                    try player.sendParameters(
                        [CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                                  value: intensity,
                                                  relativeTime: 0)],
                        atTime: CHHapticTimeImmediate)
                } else if running {
                    try player.stop(atTime: CHHapticTimeImmediate)
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
    }
}
