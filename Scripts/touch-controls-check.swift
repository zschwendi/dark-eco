// Deterministic host check for the multitouch state machine.
//
// The simulator can only be driven with one mouse. This instead drives TouchControls directly,
// one game frame at a time, without linking the engine.
//
//   Scripts/run-touch-controls-check.sh

import Foundation

private final class Finger {}

private var failures = 0

private func check(_ condition: Bool, _ what: String) {
    if condition {
        print("  ok   \(what)")
    } else {
        print("  FAIL \(what)")
        failures += 1
    }
}

@MainActor
private struct Runner {
    static let screen = CGSize(width: 1210, height: 834)
    static let movement = CGRect(x: 82, y: 578, width: 216, height: 216)
    static let select = CGRect(x: 410, y: 690, width: 102, height: 66)
    static let start = CGRect(x: 610, y: 690, width: 102, height: 66)
    static let rightStick = CGRect(x: 790, y: 668, width: 108, height: 108)
    static let roll = CGRect(x: 1010, y: 666, width: 132, height: 88)

    let controls: TouchControls
    var clock: TimeInterval = 0

    init() {
        controls = TouchControls()
        controls.setMovementFrame(Self.movement)
        controls.setPillFrame(.select, Self.select)
        controls.setPillFrame(.start, Self.start)
        controls.setRightStickFrame(Self.rightStick)
        controls.setRollFrame(Self.roll)
    }

    mutating func frame() -> TouchPadState {
        clock += 1.0 / 60
        return controls.frameState()
    }

    mutating func frames(_ count: Int) -> [TouchPadState] {
        (0..<count).map { _ in frame() }
    }

    func down(_ finger: Finger, _ point: CGPoint) {
        controls.began(ObjectIdentifier(finger), at: point, in: Self.screen, at: clock)
    }

    func move(_ finger: Finger, _ point: CGPoint) {
        controls.moved(ObjectIdentifier(finger), to: point)
    }

    func up(_ finger: Finger) {
        controls.ended(ObjectIdentifier(finger), at: clock)
    }
}

private let neutral = UInt8(GOALPadAnalogNeutral)

@MainActor
private func movementOriginIsStationary() {
    print("the movement stick has one stationary centre")
    var run = Runner()
    let centre = CGPoint(x: Runner.movement.midX, y: Runner.movement.midY)
    let thumb = Finger()
    run.down(thumb, centre)

    check(run.controls.stick?.origin == centre, "the touch uses the laid-out centre, not its own")
    check(run.frame().leftX == neutral, "the centre is neutral")

    run.move(thumb, CGPoint(x: centre.x + TouchControls.movementRadius, y: centre.y))
    var state = run.frame()
    check(state.leftX == 254 && state.leftY == neutral, "one radius right is hard right")
    check(run.controls.stick?.origin == centre, "dragging does not move the origin")

    for _ in 0..<10 { state = run.frame() }
    check(state.leftX == 254, "the held deflection does not recenter under the finger")

    run.move(thumb, CGPoint(x: centre.x + 45, y: centre.y + 45))
    state = run.frame()
    check(state.leftX == 191 && state.leftY == 191, "a half-radius diagonal stays analog")

    run.move(thumb, CGPoint(x: centre.x, y: centre.y - 300))
    check(run.frame().leftY == 0, "travel beyond the ring clamps to hard up")

    run.up(thumb)
    check(run.frame().leftX == neutral, "lifting immediately centres movement")

    let offCentre = Finger()
    run.down(offCentre, CGPoint(x: centre.x + 30, y: centre.y))
    check(run.controls.stick?.origin == centre, "a new landing point does not relocate the base")
    check(run.frame().leftX > neutral, "an off-centre landing deflects from the fixed base")
}

@MainActor
private func freeCameraSwipeIsGone() {
    print("dragging outside the explicit controls cannot move the camera")
    var run = Runner()
    let oldCameraArea = Finger()
    run.down(oldCameraArea, CGPoint(x: 220, y: 420))
    run.move(oldCameraArea, CGPoint(x: 500, y: 250))
    var state = run.frame()
    check(run.controls.touches.isEmpty, "the old above-stick camera area tracks no touch")
    check(state.rightX == neutral && state.rightY == neutral,
          "the old camera drag leaves the right stick centred")

    let faceGesture = Finger()
    run.down(faceGesture, CGPoint(x: 900, y: 360))
    run.move(faceGesture, CGPoint(x: 900, y: 290))
    state = run.frame()
    check(state.buttons.contains(.cross), "the independent face-button swipe remains available")
    check(!state.isRightDeflected, "a face-button swipe never emits camera axes")
}

@MainActor
private func faceButtonGesturesRemain() {
    print("open-screen gestures retain the three face buttons and tap repeat")
    for (dx, dy, expected, name) in [(CGFloat(0), CGFloat(-70), GOALPadButton.cross, "up"),
                                     (-70, 0, .square, "left"),
                                     (70, 0, .circle, "right")] {
        var run = Runner()
        let finger = Finger()
        run.down(finger, CGPoint(x: 900, y: 360))
        run.move(finger, CGPoint(x: 900 + dx, y: 360 + dy))
        run.up(finger)
        check(run.frames(3).allSatisfy { $0.buttons == expected },
              "swipe \(name) maps to its original face button")
    }

    var repeatRun = Runner()
    let swipe = Finger()
    repeatRun.down(swipe, CGPoint(x: 900, y: 360))
    repeatRun.move(swipe, CGPoint(x: 830, y: 360))
    repeatRun.up(swipe)
    _ = repeatRun.frames(TouchControls.holdFrames + TouchControls.releaseFrames)

    let tap = Finger()
    repeatRun.down(tap, CGPoint(x: 900, y: 360))
    repeatRun.up(tap)
    check(repeatRun.frames(3).allSatisfy { $0.buttons.contains(.square) },
          "a tap repeats the last face-button swipe")
}

@MainActor
private func rightStickIsAnOctantControl() {
    print("the small right stick has a deadzone and snaps to octants")
    var run = Runner()
    let centre = CGPoint(x: Runner.rightStick.midX, y: Runner.rightStick.midY)
    let thumb = Finger()
    run.down(thumb, centre)
    check(run.frame().rightX == neutral, "the C-stick centre is neutral")

    run.move(thumb, CGPoint(x: centre.x + TouchControls.rightStickDeadzone, y: centre.y))
    var state = run.frame()
    check(!state.isRightDeflected, "travel through the deadzone stays neutral")

    run.move(thumb, CGPoint(x: centre.x + 20, y: centre.y))
    state = run.frame()
    check(state.rightX == 254 && state.rightY == neutral,
          "crossing the deadzone snaps to hard right")

    run.move(thumb, CGPoint(x: centre.x + 30, y: centre.y - 30))
    state = run.frame()
    check(state.rightX == 217 && state.rightY == 37,
          "a diagonal snaps to the fixed up-right octant")

    run.move(thumb, CGPoint(x: centre.x + 30, y: centre.y + 10))
    state = run.frame()
    check(state.rightX == 254 && state.rightY == neutral,
          "small angle changes do not become one-to-one displacement")

    run.up(thumb)
    state = run.frame()
    check(state.rightX == neutral && state.rightY == neutral,
          "releasing immediately centres the C-stick")
}

@MainActor
private func heldRollCanAddAJump() {
    print("roll is held while an upward drag adds one jump press")
    var run = Runner()
    let centre = CGPoint(x: Runner.roll.midX, y: Runner.roll.midY)
    let finger = Finger()
    run.down(finger, centre)

    let crouching = run.frames(20)
    check(crouching.allSatisfy { $0.buttons.contains(.L1) }, "press and hold keeps L1 down")
    check(crouching.allSatisfy { !$0.buttons.contains(.cross) }, "holding alone does not jump")

    run.move(finger, CGPoint(x: centre.x, y: centre.y - TouchControls.rollJumpDistance - 8))
    let jumping = run.frames(TouchControls.holdFrames)
    check(jumping.allSatisfy { $0.buttons.contains(.L1) },
          "crouch remains held throughout the jump edge")
    check(jumping.allSatisfy { $0.buttons.contains(.cross) },
          "the upward drag emits a full Cross pulse")

    let stillHeld = run.frame()
    check(stillHeld.buttons.contains(.L1) && !stillHeld.buttons.contains(.cross),
          "the one-shot jump ends while crouch remains held")

    run.move(finger, CGPoint(x: centre.x, y: centre.y - 100))
    check(run.frames(10).allSatisfy { !$0.buttons.contains(.cross) },
          "continuing the same drag does not retrigger jump")

    run.up(finger)
    let released = run.frame()
    check(!released.buttons.contains(.L1), "lifting immediately releases crouch")
}

@MainActor
private func controlsWorkTogether() {
    print("movement, look, and roll jump can share one frame")
    var run = Runner()
    let movement = Finger()
    let look = Finger()
    let roll = Finger()
    let movementCentre = CGPoint(x: Runner.movement.midX, y: Runner.movement.midY)
    let lookCentre = CGPoint(x: Runner.rightStick.midX, y: Runner.rightStick.midY)
    let rollCentre = CGPoint(x: Runner.roll.midX, y: Runner.roll.midY)

    run.down(movement, movementCentre)
    run.move(movement, CGPoint(x: movementCentre.x + 90, y: movementCentre.y))
    run.down(look, lookCentre)
    run.move(look, CGPoint(x: lookCentre.x, y: lookCentre.y - 30))
    run.down(roll, rollCentre)
    run.move(roll, CGPoint(x: rollCentre.x, y: rollCentre.y - 60))

    let state = run.frame()
    check(state.leftX == 254 && state.rightY == 0,
          "movement and the C-stick both reach the controller seam")
    check(state.buttons.contains(.L1) && state.buttons.contains(.cross),
          "roll and its jump edge are present in that same frame")
}

@MainActor
private func movementAlsoStepsTheDpad() {
    print("strong movement still steps the D-pad for menus")
    var run = Runner()
    let thumb = Finger()
    let centre = CGPoint(x: Runner.movement.midX, y: Runner.movement.midY)
    run.down(thumb, centre)
    run.move(thumb, CGPoint(x: centre.x + 0.6 * TouchControls.movementRadius, y: centre.y))

    let states = run.frames(48)
    let right = states.map { $0.buttons.contains(.right) }
    let hold = TouchControls.holdFrames
    let delay = TouchControls.dpadRepeatDelay
    let interval = TouchControls.dpadRepeatInterval

    check(right.prefix(hold).allSatisfy { $0 }, "crossing the threshold is one press")
    check(right[hold..<delay].allSatisfy { !$0 }, "the initial press has a real release")
    check(right[delay..<(delay + hold)].allSatisfy { $0 }, "it repeats after the delay")
    check(right[(delay + hold)..<(delay + interval)].allSatisfy { !$0 },
          "repeats remain separated")
    check(states.allSatisfy { $0.leftX > 160 }, "analog movement remains present")

    run.move(thumb, CGPoint(x: centre.x + 0.2 * TouchControls.movementRadius, y: centre.y))
    check(run.frames(20).dropFirst(hold).allSatisfy { !$0.buttons.contains(.right) },
          "returning below the release threshold stops repeat")
}

@MainActor
private func pillsRemainExplicitControls() {
    print("Start and Select remain explicit held controls")
    var run = Runner()
    let finger = Finger()
    let centre = CGPoint(x: Runner.start.midX, y: Runner.start.midY)
    run.down(finger, centre)
    check(run.controls.isPillDown(.start), "the Start hit area owns the finger")
    check(run.frames(3).allSatisfy { $0.buttons.contains(.start) }, "Start is held")

    run.move(finger, CGPoint(x: centre.x, y: centre.y - 140))
    let dragged = run.frames(3)
    check(dragged.allSatisfy { $0.buttons.contains(.start) }, "dragging off keeps Start held")
    check(dragged.allSatisfy { !$0.buttons.contains(.cross) },
          "dragging Start never becomes a jump")

    run.up(finger)
    check(!run.frames(TouchControls.holdFrames + 2).last!.buttons.contains(.start),
          "Start releases after the finger lifts")
}

@MainActor
private func visibilityFollowsRecognisedTouch() {
    print("visibility follows recognised controls")
    let run = Runner()
    check(!run.controls.isEngaged, "artwork starts hidden")
    let finger = Finger()
    run.down(finger, CGPoint(x: Runner.movement.midX, y: Runner.movement.midY))
    check(run.controls.isEngaged, "touching a control shows the artwork")
}

@MainActor
private func resetClearsInterruptedInput() {
    print("reset clears every interrupted input")
    var run = Runner()
    let movement = Finger()
    let look = Finger()
    let roll = Finger()
    let movementCentre = CGPoint(x: Runner.movement.midX, y: Runner.movement.midY)
    let lookCentre = CGPoint(x: Runner.rightStick.midX, y: Runner.rightStick.midY)
    let rollCentre = CGPoint(x: Runner.roll.midX, y: Runner.roll.midY)

    run.down(movement, movementCentre)
    run.move(movement, CGPoint(x: movementCentre.x + 90, y: movementCentre.y))
    run.down(look, lookCentre)
    run.move(look, CGPoint(x: lookCentre.x + 30, y: lookCentre.y))
    run.down(roll, rollCentre)
    run.move(roll, CGPoint(x: rollCentre.x, y: rollCentre.y - 60))
    _ = run.frame()

    run.controls.reset()
    let state = run.frame()
    check(state.buttons.isEmpty, "no held or queued button survives reset")
    check(!state.isLeftDeflected, "movement is centred")
    check(!state.isRightDeflected, "the C-stick is centred")
    check(run.controls.touches.isEmpty, "all tracked fingers are discarded")
    check(!run.controls.isEngaged, "the artwork is hidden")
    check(run.controls.repeatButton == .cross, "face-button tap repeat resets to Cross")
}

@main
@MainActor
struct TouchControlsCheck {
    static func main() {
        movementOriginIsStationary()
        freeCameraSwipeIsGone()
        faceButtonGesturesRemain()
        rightStickIsAnOctantControl()
        heldRollCanAddAJump()
        controlsWorkTogether()
        movementAlsoStepsTheDpad()
        pillsRemainExplicitControls()
        visibilityFollowsRecognisedTouch()
        resetClearsInterruptedInput()

        print(failures == 0 ? "\nall checks passed" : "\n\(failures) checks FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
