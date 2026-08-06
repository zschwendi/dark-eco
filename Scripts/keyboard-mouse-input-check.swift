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

private func keyboardButtons() {
    print("only the ten chosen gameplay keys have mappings")
    check(KeyboardMouseKey.allCases.count == 10, "the explicit keyboard surface stays bounded")

    let expected: [(KeyboardMouseKey, GOALPadButton, String)] = [
        (.leftArrow, .square, "Left Arrow is Square"),
        (.rightArrow, .circle, "Right Arrow is Circle"),
        (.upArrow, .triangle, "Up Arrow is Triangle"),
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

private func primaryInputSourcePolicy() {
    print("Primary Controller preferences are exclusive when available and safe when unavailable")
    let automatic = InputSourcePolicy(preference: .automatic, touchAvailable: true,
                                      controllerConnected: true, keyboardMouseConnected: true)
    check(automatic.allowsTouch && automatic.allowsController && automatic.allowsKeyboardMouse,
          "Automatic preserves the accepted merged-source behavior")
    check(automatic.suppressesTouchChrome(recentPhysicalActivity: true)
          && !automatic.suppressesTouchChrome(recentPhysicalActivity: false),
          "Automatic keeps activity-driven touch suppression")

    let touch = InputSourcePolicy(preference: .touch, touchAvailable: true,
                                  controllerConnected: true, keyboardMouseConnected: true)
    check(touch.effectiveSource == .touch && touch.allowsTouch
          && !touch.allowsController && !touch.allowsKeyboardMouse,
          "Touch explicitly excludes connected physical input")
    check(!touch.suppressesTouchChrome(recentPhysicalActivity: true),
          "ignored physical activity cannot hide explicit Touch controls")

    let controller = InputSourcePolicy(preference: .controller, touchAvailable: true,
                                       controllerConnected: true, keyboardMouseConnected: true)
    check(controller.allowsController && !controller.allowsTouch
          && !controller.allowsKeyboardMouse,
          "Controller explicitly owns the pad while connected")
    check(controller.suppressesTouchChrome(recentPhysicalActivity: false),
          "an explicitly selected connected Controller hides idle touch chrome")

    let unavailable = InputSourcePolicy(preference: .controller, touchAvailable: true,
                                        controllerConnected: false,
                                        keyboardMouseConnected: false)
    check(unavailable.effectiveSource == .automatic && unavailable.allowsTouch,
          "an unavailable cloud-synced preference falls back without stranding input")
}

private func relativeMouse() {
    print("relative mouse movement is bounded and consumed once")
    var state = KeyboardMouseInputState()

    state.addMouseMovement(deltaX: 12, deltaY: 12)
    var frame = state.consumeFrame()
    check(frame.rightX == 191 && frame.rightY == 64,
          "half-scale movement produces proportional right-stick bytes")
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

    check(!state.addMouseMovement(deltaX: .nan, deltaY: 2),
          "non-finite movement is rejected")
    frame = state.consumeFrame()
    check(frame.rightX == neutral && frame.rightY == neutral,
          "rejected movement cannot leave sticky state")
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
        keyboardButtons()
        relativeMouse()
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
