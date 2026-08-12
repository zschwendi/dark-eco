// Deterministic host check for the hardware-independent keyboard/mouse mappings and activity
// policy. Game Controller adoption and callback signatures are checked separately by compiling
// ControllerInput.swift against the Apple SDK.

import Foundation

private var failures = 0

private func check(_ condition: Bool, _ what: String) {
    if condition {
        print("  ok   \(what)")
    } else {
        print("  FAIL \(what)")
        failures += 1
    }
}

private let neutral = UInt8(GOALPadAnalogNeutral)

private func keyboardMovement() {
    print("WASD produces a deterministic full-range left stick")
    var state = KeyboardMouseInputState()

    state.setKey(.w, pressed: true)
    state.setKey(.d, pressed: true)
    var frame = state.consumeFrame()
    check(frame.leftX == 254 && frame.leftY == 0, "W+D is full up-right")
    check(frame.hasKeyboardInput, "held movement counts as keyboard activity")

    state.setKey(.s, pressed: true)
    state.setKey(.a, pressed: true)
    frame = state.consumeFrame()
    check(frame.leftX == neutral && frame.leftY == neutral,
          "opposite directions cancel on both axes")

    for key in [KeyboardMouseKey.w, .a, .s, .d] { state.setKey(key, pressed: false) }
    frame = state.consumeFrame()
    check(frame.leftX == neutral && frame.leftY == neutral,
          "releasing WASD returns the left stick to neutral")
    check(!frame.hasKeyboardInput, "released keys no longer count as active")
}

private func configurableKeyboardMovement() {
    print("keyboard movement directions use the same deterministic remapping surface")
    var bindings = Jak1InputBindings.standard
    bindings.setKeyboardMouseAction(.moveLeft, for: .leftArrow)
    bindings.setKeyboardMouseAction(.moveRight, for: .rightArrow)
    bindings.setKeyboardMouseAction(.moveForward, for: .upArrow)
    bindings.setKeyboardMouseAction(.moveBackward, for: .downArrow)

    check(bindings.action(for: .leftArrow) == .moveLeft
          && bindings.action(for: .rightArrow) == .moveRight
          && bindings.action(for: .upArrow) == .moveForward
          && bindings.action(for: .downArrow) == .moveBackward,
          "all four movement directions can move away from their WASD defaults")
    check(bindings.action(for: .a) == .square
          && bindings.action(for: .d) == .circle
          && bindings.action(for: .w) == .triangle
          && bindings.action(for: .s) == .shoulderChord,
          "occupied arrow actions swap back to WASD without duplicate owners")

    var state = KeyboardMouseInputState()
    state.setKey(.upArrow, pressed: true)
    state.setKey(.rightArrow, pressed: true)
    let frame = state.consumeFrame(bindings: bindings)
    check(frame.leftX == 254 && frame.leftY == 0 && frame.buttons.isEmpty,
          "remapped Up+Right arrows emit only the exact full-range movement vector")
}

private func keyboardButtons() {
    print("default keyboard bytes remain exact while the remapping surface stays explicit")
    check(KeyboardMouseKey.keyboardCases.count == 13
          && KeyboardMouseKey.mouseCases == [.mouseLeft, .mouseRight, .mouseMiddle],
          "only the named keyboard keys and three mouse buttons can be bound")
    check(Jak1InputBindings.standard.keyboardMouseBindings.count == 12,
          "the default mapping assigns movement, action, Shift, and Space keys")
    check(Jak1InputBindings.standard.action(for: .spacebar) == .cross
          && Jak1InputBindings.standard.action(for: .shift) == .L1
          && Jak1InputBindings.standard.action(for: .returnOrEnter) == nil
          && KeyboardMouseKey(rawValue: "q") == nil,
          "additional named keys begin unused and arbitrary typing has no control value")
    var unused = KeyboardMouseInputState()
    unused.setControl(.returnOrEnter, pressed: true)
    unused.setControl(.mouseLeft, pressed: true)
    let unusedFrame = unused.consumeFrame()
    check(unusedFrame.buttons.isEmpty && !unusedFrame.hasKeyboardInput && !unusedFrame.hasMouseInput,
          "Not Used candidates emit no bytes and do not report gameplay activity")

    let expected: [(KeyboardMouseKey, GOALPadButton, String)] = [
        (.leftArrow, .square, "Left Arrow is Square"),
        (.rightArrow, .circle, "Right Arrow is Circle"),
        (.upArrow, .triangle, "Up Arrow is Triangle"),
        (.shift, .L1, "Shift is L1"),
        (.spacebar, .cross, "Space is Cross / jump"),
        (.escape, .start, "Escape is Start/Pause"),
    ]
    for (key, button, label) in expected {
        var state = KeyboardMouseInputState()
        state.setKey(key, pressed: true)
        check(state.consumeFrame().buttons == button, label)
    }

    var shoulders = KeyboardMouseInputState()
    shoulders.setKey(.downArrow, pressed: true)
    let shoulderButtons = shoulders.consumeFrame().buttons
    check(shoulderButtons == [.L1, .R1], "Down Arrow is exactly the L1+R1 shoulder chord")
    check(shoulderButtons.rawValue == (1 << 10) | (1 << 11),
          "the shoulder chord emits only pad bits 10 and 11")
    check(!shoulderButtons.contains(.start),
          "the shoulder chord is distinct from ordinary Start pause/progress")

    var stats = KeyboardMouseInputState()
    stats.setKey(.tab, pressed: true)
    check(stats.consumeFrame().buttons == [.L2, .R2],
          "Tab is the explicit native progress/stats shoulder chord")
}

private func defaultControllerBytes() {
    print("the standard physical controller mapping emits the preserved pad bytes")
    let allPressed = Set(Jak1ControllerControl.allCases)
    let frame = Jak1InputBindings.standard.controllerFrame(
        pressed: allPressed,
        values: [.leftTrigger: 0.25, .rightTrigger: 0.75])
    check(frame.buttons.rawValue == 0xffff,
          "the sixteen standard controls still cover exactly every PS2 pad button bit")
    check(frame.leftTrigger == 64 && frame.rightTrigger == 191,
          "default physical trigger pressure keeps the existing rounded byte conversion")
    check(Jak1InputBindings.standard.action(for: .buttonA) == .cross
          && Jak1InputBindings.standard.action(for: .buttonB) == .circle
          && Jak1InputBindings.standard.action(for: .buttonX) == .square
          && Jak1InputBindings.standard.action(for: .buttonY) == .triangle,
          "face-button position defaults remain Cross, Circle, Square, Triangle")
}

private func controllerStickRoleMapping() {
    print("controller stick roles preserve normalized vectors and apply before source merge")
    check(Jak1ControllerStickRoles.allCases == [.standard, .swapped]
          && Jak1ControllerStickRoles.standard.title == "Standard"
          && Jak1ControllerStickRoles.swapped.title == "Swapped Sticks",
          "the role surface exposes only Standard and Swapped Sticks")
    let standard = Jak1MappedControllerSticks(
        roles: .standard,
        physicalLeftX: 1,
        physicalLeftY: 1,
        physicalRightX: -1,
        physicalRightY: -1)
    check(standard.leftX == 254 && standard.leftY == 0
          && standard.rightX == 0 && standard.rightY == 254,
          "Standard emits the exact established bytes, including GameController Y normalization")

    var bindings = Jak1InputBindings.standard
    bindings.setControllerStickRoles(.swapped)
    let swapped = Jak1MappedControllerSticks(
        roles: bindings.controllerStickRoles,
        physicalLeftX: -0.5,
        physicalLeftY: 0.25,
        physicalRightX: 1,
        physicalRightY: -1)
    check(swapped.leftX == 254 && swapped.leftY == 254
          && swapped.rightX == 64 && swapped.rightY == 95,
          "Swapped Sticks exchanges complete normalized X/Y vectors without changing their bytes")

    let cameraOnly = Jak1MappedControllerSticks(
        roles: .swapped,
        physicalLeftX: 1,
        physicalLeftY: 0,
        physicalRightX: 0,
        physicalRightY: 0)
    let movement = PadStickMerge.preferred(
        primaryX: cameraOnly.leftX,
        primaryY: cameraOnly.leftY,
        fallbackX: 254,
        fallbackY: 0,
        fallbackActive: true)
    let camera = PadStickMerge.preferred(
        primaryX: cameraOnly.rightX,
        primaryY: cameraOnly.rightY,
        fallbackX: 0,
        fallbackY: 254,
        fallbackActive: true)
    check(movement.x == 254 && movement.y == 0,
          "a neutral mapped controller movement role yields to keyboard movement")
    check(camera.x == 254 && camera.y == neutral,
          "a mapped controller camera role keeps controller-first precedence over mouse")
}

private func controllerAnalogTuning() throws {
    print("controller analog tuning is role-based, bounded, radial, and compatibility-safe")
    check(Jak1InputBindings.standard.controllerAnalog == .standard
          && Jak1InputBindings.standard.controllerAnalog.movement == .standard
          && Jak1InputBindings.standard.controllerAnalog.camera == .standard,
          "the established controller bytes begin with no host-side analog tuning")

    var bindings = Jak1InputBindings.standard
    bindings.setControllerSensitivityPercent(200, for: .movement)
    bindings.setControllerInvertHorizontal(true, for: .movement)
    bindings.setControllerSensitivityPercent(50, for: .camera)
    bindings.setControllerInvertVertical(true, for: .camera)
    var tuned = Jak1MappedControllerSticks(
        roles: bindings.controllerStickRoles,
        analog: bindings.controllerAnalog,
        physicalLeftX: 0.25,
        physicalLeftY: 0.5,
        physicalRightX: 0.5,
        physicalRightY: 0.25)
    check(tuned.leftX == 64 && tuned.leftY == 0,
          "movement sensitivity and horizontal inversion transform only the movement vector")
    check(tuned.rightX == 159 && tuned.rightY == 143,
          "camera sensitivity and vertical inversion transform only the camera vector")

    bindings.setControllerDeadZonePercent(25, for: .movement)
    bindings.setControllerSensitivityPercent(100, for: .movement)
    bindings.setControllerInvertHorizontal(false, for: .movement)
    tuned = Jak1MappedControllerSticks(
        roles: .standard,
        analog: bindings.controllerAnalog,
        physicalLeftX: 0.25,
        physicalLeftY: 0,
        physicalRightX: 0,
        physicalRightY: 0)
    check(tuned.leftX == neutral && tuned.leftY == neutral,
          "the additional radial dead zone is inclusive at its configured boundary")
    tuned = Jak1MappedControllerSticks(
        roles: .standard,
        analog: bindings.controllerAnalog,
        physicalLeftX: 0.5,
        physicalLeftY: 0,
        physicalRightX: 0,
        physicalRightY: 0)
    check(tuned.leftX == 169 && tuned.leftY == neutral,
          "the range beyond the additional radial dead zone is deterministically rescaled")

    bindings.setControllerDeadZonePercent(0, for: .camera)
    bindings.setControllerSensitivityPercent(200, for: .camera)
    bindings.setControllerInvertVertical(false, for: .camera)
    tuned = Jak1MappedControllerSticks(
        roles: .standard,
        analog: bindings.controllerAnalog,
        physicalLeftX: 0,
        physicalLeftY: 0,
        physicalRightX: 1,
        physicalRightY: -0.5)
    check(tuned.rightX == 254 && tuned.rightY == 191,
          "whole-vector saturation preserves a two-to-one direction instead of clipping Y")

    bindings.setControllerStickRoles(.swapped)
    bindings.setControllerDeadZonePercent(0, for: .movement)
    bindings.setControllerSensitivityPercent(200, for: .movement)
    bindings.setControllerInvertHorizontal(true, for: .movement)
    tuned = Jak1MappedControllerSticks(
        roles: bindings.controllerStickRoles,
        analog: bindings.controllerAnalog,
        physicalLeftX: 0.25,
        physicalLeftY: -0.5,
        physicalRightX: 0.5,
        physicalRightY: 0)
    check(tuned.leftX == 0 && tuned.leftY == neutral,
          "Swapped Sticks assigns the whole right vector to movement before movement tuning")
    check(tuned.rightX == 191 && tuned.rightY == 254,
          "Swapped Sticks assigns the whole left vector to camera before camera tuning")

    bindings.setControllerSensitivityPercent(999, for: .movement)
    bindings.setControllerDeadZonePercent(999, for: .movement)
    bindings.setControllerSensitivityPercent(-1, for: .camera)
    bindings.setControllerDeadZonePercent(-1, for: .camera)
    check(bindings.controllerAnalog.movement.sensitivityPercent
            == Jak1ControllerStickSettings.maximumSensitivityPercent
          && bindings.controllerAnalog.movement.deadZonePercent
            == Jak1ControllerStickSettings.maximumDeadZonePercent
          && bindings.controllerAnalog.camera.sensitivityPercent
            == Jak1ControllerStickSettings.minimumSensitivityPercent
          && bindings.controllerAnalog.camera.deadZonePercent
            == Jak1ControllerStickSettings.minimumDeadZonePercent,
          "controller analog setters clamp every bounded value")

    let encoded = try JSONEncoder().encode(bindings)
    let decoded = try JSONDecoder().decode(Jak1InputBindings.self, from: encoded)
    check(decoded == bindings,
          "custom whole-role controller analog settings round-trip with the binding payload")
    let standardJSON = String(decoding: try JSONEncoder().encode(Jak1InputBindings.standard),
                              as: UTF8.self)
    check(!standardJSON.contains("controllerAnalog"),
          "the exact default omits the optional controller-analog compatibility field")

    let outOfRange = Data(
        #"{"controller":[],"keyboardMouse":[],"controllerAnalog":{"movement":{"sensitivityPercent":999,"deadZonePercent":999},"camera":{"sensitivityPercent":-1,"deadZonePercent":-1}}}"#.utf8)
    let clamped = try JSONDecoder().decode(Jak1InputBindings.self, from: outOfRange)
    check(clamped.controllerAnalog.movement.sensitivityPercent
            == Jak1ControllerStickSettings.maximumSensitivityPercent
          && clamped.controllerAnalog.movement.deadZonePercent
            == Jak1ControllerStickSettings.maximumDeadZonePercent
          && clamped.controllerAnalog.camera.sensitivityPercent
            == Jak1ControllerStickSettings.minimumSensitivityPercent
          && clamped.controllerAnalog.camera.deadZonePercent
            == Jak1ControllerStickSettings.minimumDeadZonePercent,
          "decoded controller tuning is bounded before it can reach input emission")

    let invalid = Jak1MappedControllerSticks(
        roles: .standard,
        analog: bindings.controllerAnalog,
        physicalLeftX: .nan,
        physicalLeftY: 0,
        physicalRightX: .infinity,
        physicalRightY: 0)
    check(invalid.leftX == neutral && invalid.leftY == neutral
          && invalid.rightX == neutral && invalid.rightY == neutral,
          "non-finite controller vectors fail neutral instead of producing invalid bytes")

    var mouse = KeyboardMouseInputState()
    mouse.addMouseMovement(deltaX: 12, deltaY: 0, camera: bindings.mouseCamera)
    let mouseFrame = mouse.consumeFrame(bindings: bindings)
    check(mouseFrame.leftX == neutral && mouseFrame.leftY == neutral
          && mouseFrame.rightX == 254 && mouseFrame.rightY == neutral,
          "controller role tuning cannot reroute relative mouse motion away from camera")
}

private func legacyControllerBindingsDefaultToStandardSticks() {
    print("legacy remapping data defaults absent stick-role, analog, and mouse-camera fields")
    let legacy = Data(
        #"{"controller":[{"control":"buttonA","action":"square"}],"keyboardMouse":[{"control":"w","action":"moveForward"}]}"#.utf8)
    let decoded = try? JSONDecoder().decode(Jak1InputBindings.self, from: legacy)
    check(decoded?.controllerStickRoles == .standard
          && decoded?.controllerAnalog == .standard
          && decoded?.mouseCamera == .standard
          && decoded?.action(for: .buttonA) == .square
          && decoded?.action(for: .w) == .moveForward,
          "a legacy customized document preserves mappings and exact analog defaults")
}

private func remappingAndCollisions() {
    print("remapping is deterministic and never leaves duplicate action owners")
    var bindings = Jak1InputBindings.standard
    bindings.setControllerAction(.square, for: .buttonA)
    check(bindings.action(for: .buttonA) == .square
          && bindings.action(for: .buttonX) == .cross,
          "assigning an occupied controller action swaps its prior and new controls")
    check(bindings.controllerFrame(pressed: [.buttonA]).buttons == .square
          && bindings.controllerFrame(pressed: [.buttonX]).buttons == .cross,
          "the controller remap reaches emitted GOALPad button bytes")

    bindings.setKeyboardMouseAction(.stats, for: .spacebar)
    check(bindings.action(for: .spacebar) == .stats && bindings.action(for: .tab) == .cross,
          "remapping Space swaps its occupied action without a duplicate")
    var keyboard = KeyboardMouseInputState()
    keyboard.setControl(.spacebar, pressed: true)
    check(keyboard.consumeFrame(bindings: bindings).buttons == [.L2, .R2],
          "an explicitly remapped key emits the Stats chord")

    bindings.setKeyboardMouseAction(.square, for: .spacebar)
    check(bindings.action(for: .spacebar) == .square
          && bindings.action(for: .leftArrow) == .stats,
          "a second occupied assignment swaps the two keyboard actions deterministically")

    bindings.setKeyboardMouseAction(.cross, for: .mouseLeft)
    var mouse = KeyboardMouseInputState()
    mouse.setControl(.mouseLeft, pressed: true)
    let mouseFrame = mouse.consumeFrame(bindings: bindings)
    check(mouseFrame.buttons == .cross && mouseFrame.hasMouseInput,
          "an explicitly bound mouse button emits its remapped pad bit and activity")

    let duplicate = Jak1InputBindings(
        controllerBindings: [
            .init(control: .buttonB, action: .cross),
            .init(control: .buttonA, action: .cross),
        ],
        keyboardMouseBindings: [
            .init(control: .d, action: .moveForward),
            .init(control: .w, action: .moveForward),
        ])
    check(duplicate.action(for: .buttonA) == .cross
          && duplicate.action(for: .buttonB) == nil,
          "duplicate controller actions normalize by declared control order")
    check(duplicate.action(for: .w) == .moveForward && duplicate.action(for: .d) == nil,
          "duplicate keyboard actions use the same stable first-control policy")
}

private func primaryInputSourcePolicy() {
    print("Primary Controller preferences preserve always-on touch input")
    let automatic = InputSourcePolicy(preference: .automatic, touchAvailable: true,
                                      controllerConnected: true, keyboardMouseConnected: true)
    check(automatic.allowsTouch && automatic.allowsController && automatic.allowsKeyboardMouse,
          "Automatic preserves the accepted merged-source behavior")
    check(automatic.suppressesTouchChrome(recentPhysicalActivity: true)
          && !automatic.suppressesTouchChrome(recentPhysicalActivity: false),
          "Automatic keeps activity-driven touch suppression")
    check(automatic.allowsTouchRecovery,
          "Automatic permits a screen touch to reclaim the touch UI")

    let touch = InputSourcePolicy(preference: .touch, touchAvailable: true,
                                  controllerConnected: true, keyboardMouseConnected: true)
    check(touch.effectiveSource == .touch && touch.allowsTouch
          && touch.allowsController && !touch.allowsKeyboardMouse,
          "a connected controller immediately joins explicit Touch")
    check(!touch.suppressesTouchChrome(recentPhysicalActivity: true),
          "ignored physical activity cannot hide explicit Touch controls")
    check(touch.allowsTouchRecovery,
          "explicit Touch may clear stale physical ownership")

    let controller = InputSourcePolicy(preference: .controller, touchAvailable: true,
                                       controllerConnected: true, keyboardMouseConnected: true)
    check(controller.allowsController && controller.allowsTouch
          && !controller.allowsKeyboardMouse,
          "Controller remains primary while touch stays additive")
    check(controller.suppressesTouchChrome(recentPhysicalActivity: true)
          && !controller.suppressesTouchChrome(recentPhysicalActivity: false),
          "Controller hides touch chrome only while it has recent activity")
    check(controller.allowsTouchRecovery,
          "a screen touch can reclaim controls from an explicitly selected Controller")

    let keyboardMouse = InputSourcePolicy(preference: .keyboardMouse, touchAvailable: true,
                                          controllerConnected: true,
                                          keyboardMouseConnected: true)
    check(keyboardMouse.allowsKeyboardMouse && keyboardMouse.allowsTouch
          && keyboardMouse.allowsController,
          "Keyboard/Mouse keeps both controller and touch additive")
    check(keyboardMouse.allowsTouchRecovery,
          "a screen touch can reclaim controls from explicit Keyboard/Mouse")

    let unavailable = InputSourcePolicy(preference: .controller, touchAvailable: true,
                                        controllerConnected: false,
                                        keyboardMouseConnected: false)
    check(unavailable.effectiveSource == .automatic && unavailable.allowsTouch,
          "an unavailable cloud-synced preference falls back without stranding input")

    for preference in PrimaryInputSource.allCases {
        let coexistence = InputSourcePolicy(preference: preference, touchAvailable: true,
                                            controllerConnected: true,
                                            keyboardMouseConnected: false)
        check(coexistence.allowsController && coexistence.allowsTouch,
              "\(preference.title) cannot disable controller-plus-touch coexistence")
    }
}

private func relativeMouse() {
    print("relative mouse movement is bounded and consumed once")
    var state = KeyboardMouseInputState()

    state.addMouseMovement(deltaX: 12, deltaY: 12)
    var frame = state.consumeFrame()
    check(frame.rightX == 254 && frame.rightY == 0,
          "the stronger default reaches full right-stick deflection")
    check(frame.hasMouseInput, "nonzero relative motion counts as mouse activity")

    state.addMouseMovement(deltaX: 1, deltaY: 0)
    frame = state.consumeFrame()
    check(frame.rightX == neutral + 33,
          "the smallest nonzero delta clears Jak 1's 32-unit analog deadzone")

    frame = state.consumeFrame()
    check(frame.rightX == neutral && frame.rightY == neutral,
          "the next frame is neutral without another mouse event")
    check(!frame.hasMouseInput, "a stopped mouse is not reported active")

    state.addMouseMovement(deltaX: 18, deltaY: 0)
    state.addMouseMovement(deltaX: 18, deltaY: 0)
    frame = state.consumeFrame()
    check(frame.rightX == 254, "accumulated positive movement clamps at full deflection")

    state.addMouseMovement(deltaX: -1000, deltaY: -1000)
    frame = state.consumeFrame()
    check(frame.rightX == 0 && frame.rightY == 254,
          "large movement stays inside the PS2 stick byte range")

    state.addMouseMovement(deltaX: 100, deltaY: 0)
    state.addMouseMovement(deltaX: -90, deltaY: 0)
    frame = state.consumeFrame()
    check(frame.rightX == 0,
          "100% preserves the established per-event clamp for alternating same-frame deltas")

    check(!state.addMouseMovement(deltaX: .nan, deltaY: 2),
          "non-finite movement is rejected")
    frame = state.consumeFrame()
    check(frame.rightX == neutral && frame.rightY == neutral,
          "rejected movement cannot leave sticky state")
}

private func mouseCameraTuning() throws {
    print("mouse camera sensitivity and directions preserve exact defaults and tune independently")
    check(Jak1InputBindings.standard.mouseCamera == .standard
          && Jak1InputBindings.standard.mouseCamera.sensitivityPercent == 250
          && !Jak1InputBindings.standard.mouseCamera.invertHorizontal
          && !Jak1InputBindings.standard.mouseCamera.invertVertical,
          "the persisted mouse camera defaults are exactly 250% with neither direction inverted")

    var bindings = Jak1InputBindings.standard
    bindings.setMouseCameraInvertHorizontal(true)
    var state = KeyboardMouseInputState()
    state.addMouseMovement(deltaX: 12, deltaY: 12, camera: bindings.mouseCamera)
    var frame = state.consumeFrame(bindings: bindings)
    check(frame.rightX == 0 && frame.rightY == 0,
          "horizontal inversion flips only X while default vertical conversion stays exact")

    bindings.setMouseCameraInvertHorizontal(false)
    bindings.setMouseCameraInvertVertical(true)
    state.addMouseMovement(deltaX: 12, deltaY: 12, camera: bindings.mouseCamera)
    frame = state.consumeFrame(bindings: bindings)
    check(frame.rightX == 254 && frame.rightY == 254,
          "vertical inversion flips only Y while default horizontal conversion stays exact")

    bindings.setMouseCameraInvertVertical(false)
    bindings.setMouseCameraSensitivityPercent(200)
    state.addMouseMovement(deltaX: 6, deltaY: 0, camera: bindings.mouseCamera)
    frame = state.consumeFrame(bindings: bindings)
    check(frame.rightX == 191,
          "200% sensitivity reaches the established half-scale byte with half the raw delta")

    bindings.setMouseCameraSensitivityPercent(400)
    state.addMouseMovement(deltaX: -1000, deltaY: 0, camera: bindings.mouseCamera)
    frame = state.consumeFrame(bindings: bindings)
    check(frame.rightX == 0,
          "maximum sensitivity remains clamped to the PS2 stick byte range")

    bindings.setMouseCameraSensitivityPercent(25)
    state.addMouseMovement(deltaX: 96, deltaY: 0, camera: bindings.mouseCamera)
    frame = state.consumeFrame(bindings: bindings)
    check(frame.rightX == 254,
          "25% sensitivity can still reach full deflection through bounded accumulated motion")
    state.addMouseMovement(deltaX: 1, deltaY: 0, camera: bindings.mouseCamera)
    frame = state.consumeFrame(bindings: bindings)
    check(frame.rightX == neutral + PadStickMerge.deadzone + 1,
          "custom sensitivity preserves the exact one-unit-beyond-deadzone minimum")

    bindings.setMouseCameraSensitivityPercent(999)
    check(bindings.mouseCamera.sensitivityPercent
          == Jak1MouseCameraSettings.maximumSensitivityPercent,
          "sensitivity setters clamp to the supported maximum")
    bindings.setMouseCameraSensitivityPercent(-1)
    check(bindings.mouseCamera.sensitivityPercent
          == Jak1MouseCameraSettings.minimumSensitivityPercent,
          "sensitivity setters clamp to the supported minimum")

    bindings.setMouseCameraSensitivityPercent(175)
    bindings.setMouseCameraInvertHorizontal(true)
    let encoded = try JSONEncoder().encode(bindings)
    let decoded = try JSONDecoder().decode(Jak1InputBindings.self, from: encoded)
    check(decoded == bindings,
          "custom mouse camera tuning round-trips with the complete binding payload")

    let standardJSON = String(decoding: try JSONEncoder().encode(Jak1InputBindings.standard),
                              as: UTF8.self)
    check(!standardJSON.contains("mouseCamera"),
          "the exact default omits the optional mouse-camera compatibility field")

    let outOfRange = Data(
        #"{"controller":[],"keyboardMouse":[],"mouseCamera":{"sensitivityPercent":999}}"#.utf8)
    let clamped = try JSONDecoder().decode(Jak1InputBindings.self, from: outOfRange)
    check(clamped.mouseCamera.sensitivityPercent
          == Jak1MouseCameraSettings.maximumSensitivityPercent,
          "decoded sensitivity is bounded before it can reach input emission")
}

private func drivingArbitration() {
    print("connectivity alone never suppresses touch chrome")
    var activity = InputActivityTracker()

    check(!activity.isDriving(at: 100,
                              controllerConnected: true,
                              keyboardConnected: true,
                              mouseConnected: true),
          "three connected idle devices are not driving")

    activity.noteKeyboard(at: 100)
    check(activity.isDriving(at: 101.999,
                             controllerConnected: false,
                             keyboardConnected: true,
                             mouseConnected: false),
          "keyboard activity suppresses touch for just under two seconds")
    check(!activity.isDriving(at: 102,
                              controllerConnected: false,
                              keyboardConnected: true,
                              mouseConnected: false),
          "keyboard suppression expires at exactly two seconds")

    activity.noteMouse(at: 200)
    check(activity.isDriving(at: 201,
                             controllerConnected: false,
                             keyboardConnected: false,
                             mouseConnected: true),
          "recent mouse motion is driving")
    activity.disconnectMouse()
    check(!activity.isDriving(at: 201,
                              controllerConnected: false,
                              keyboardConnected: false,
                              mouseConnected: true),
          "mouse disconnect clears its activity immediately")

    activity.noteController(at: 300)
    check(activity.isDriving(at: 301,
                             controllerConnected: true,
                             keyboardConnected: false,
                             mouseConnected: false),
          "the existing controller activity path retains the same interval")
    check(!activity.isDriving(at: 301,
                              controllerConnected: false,
                              keyboardConnected: false,
                              mouseConnected: false),
          "recent activity from a disconnected controller cannot suppress touch")

    let explicitController = InputSourcePolicy(
        preference: .controller, touchAvailable: true,
        controllerConnected: true, keyboardMouseConnected: false)
    check(activity.reclaimTouch(using: explicitController)
          && !activity.isDriving(at: 301,
                                 controllerConnected: true,
                                 keyboardConnected: false,
                                 mouseConnected: false),
          "touch reclaim clears recent explicit Controller activity")

    let automatic = InputSourcePolicy(
        preference: .automatic, touchAvailable: true,
        controllerConnected: true, keyboardMouseConnected: true)
    activity.noteKeyboard(at: 300)
    activity.noteMouse(at: 300)
    check(activity.reclaimTouch(using: automatic)
          && !activity.isDriving(at: 301,
                                 controllerConnected: true,
                                 keyboardConnected: true,
                                 mouseConnected: true),
          "Automatic touch reclaim immediately clears every recent physical owner")

    activity.noteKeyboard(at: 400)
    let explicitKeyboardMouse = InputSourcePolicy(
        preference: .keyboardMouse, touchAvailable: true,
        controllerConnected: false, keyboardMouseConnected: true)
    check(activity.reclaimTouch(using: explicitKeyboardMouse)
          && !activity.isDriving(at: 401,
                                 controllerConnected: false,
                                 keyboardConnected: true,
                                 mouseConnected: false),
          "touch reclaim clears recent explicit Keyboard/Mouse activity")

    let explicitTouch = InputSourcePolicy(
        preference: .touch, touchAvailable: true,
        controllerConnected: true, keyboardMouseConnected: true)
    check(activity.reclaimTouch(using: explicitTouch)
          && !activity.isDriving(at: 401,
                                 controllerConnected: true,
                                 keyboardConnected: true,
                                 mouseConnected: true),
          "explicit Touch may clear stale physical activity deterministically")
}

private func stickSourcePrecedence() {
    print("physical stick precedence and fallback preserve the existing merge")
    let controller = PadStickMerge.preferred(primaryX: 200,
                                             primaryY: neutral,
                                             fallbackX: 0,
                                             fallbackY: 254,
                                             fallbackActive: true)
    check(controller.x == 200 && controller.y == neutral,
          "a controller outside the deadzone keeps the whole stick")

    let touch = PadStickMerge.preferred(primaryX: neutral + PadStickMerge.deadzone,
                                        primaryY: neutral,
                                        fallbackX: 254,
                                        fallbackY: 0,
                                        fallbackActive: true)
    check(touch.x == 254 && touch.y == 0,
          "controller drift at the deadzone yields to an active fallback")

    let idleFallback = PadStickMerge.preferred(primaryX: neutral,
                                               primaryY: neutral,
                                               fallbackX: 254,
                                               fallbackY: 0,
                                               fallbackActive: false)
    check(idleFallback.x == neutral && idleFallback.y == neutral,
          "an idle connected fallback cannot take over the stick")
}

@main
struct KeyboardMouseInputCheck {
    static func main() {
        keyboardMovement()
        configurableKeyboardMovement()
        keyboardButtons()
        defaultControllerBytes()
        controllerStickRoleMapping()
        do {
            try controllerAnalogTuning()
        } catch {
            print("  FAIL controller analog tuning threw: \(error)")
            failures += 1
        }
        legacyControllerBindingsDefaultToStandardSticks()
        remappingAndCollisions()
        relativeMouse()
        do {
            try mouseCameraTuning()
        } catch {
            print("  FAIL mouse camera tuning threw: \(error)")
            failures += 1
        }
        drivingArbitration()
        stickSourcePrecedence()
        primaryInputSourcePolicy()

        if failures > 0 {
            print("\nkeyboard/mouse input check failed: \(failures) assertion(s)")
            exit(1)
        }
        print("\nkeyboard/mouse input check passed")
    }
}
