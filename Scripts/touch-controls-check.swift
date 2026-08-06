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
    static let safeAreaInsets = TouchSafeAreaInsets(top: 24, leading: 18,
                                                     bottom: 20, trailing: 18)
    static let select = CGRect(x: 500, y: 690, width: 102, height: 66)
    static let start = CGRect(x: 610, y: 690, width: 102, height: 66)
    static let rightStick = CGRect(x: 1040, y: 668, width: 108, height: 108)

    let controls: TouchControls
    var clock: TimeInterval = 0

    init(style: TouchControlStyle = .modern) {
        self.init(style: style, rightStickFrame: Self.rightStick)
    }

    init(style: TouchControlStyle = .modern, rightStickFrame: CGRect) {
        controls = TouchControls(style: style)
        controls.setPillFrame(.select, Self.select)
        controls.setPillFrame(.start, Self.start)
        controls.setRightStickFrame(rightStickFrame)
    }

    mutating func frame() -> TouchPadState {
        clock += 1.0 / 60
        return controls.frameState()
    }

    mutating func frames(_ count: Int) -> [TouchPadState] {
        (0..<count).map { _ in frame() }
    }

    func down(_ finger: Finger, _ point: CGPoint) {
        controls.began(ObjectIdentifier(finger), at: point, in: Self.screen,
                       safeAreaInsets: Self.safeAreaInsets, at: clock)
    }

    func move(_ finger: Finger, _ point: CGPoint) {
        controls.moved(ObjectIdentifier(finger), to: point)
    }

    func up(_ finger: Finger) {
        controls.ended(ObjectIdentifier(finger), at: clock)
    }

    func cancel(_ finger: Finger) {
        controls.cancelled(ObjectIdentifier(finger))
    }
}

private let neutral = UInt8(GOALPadAnalogNeutral)

private func close(_ lhs: CGFloat, _ rhs: CGFloat, tolerance: CGFloat = 0.001) -> Bool {
    abs(lhs - rhs) <= tolerance
}

@MainActor
private func modernLayoutIsCompactAndSafe() {
    print("Modern artwork geometry keeps input semantics and clears the centre controls")
    check(ModernTouchLayout.movementKnobSize == 66,
          "the Modern movement knob remains 66 points")
    check(ModernTouchLayout.movementVisualRadius < TouchControls.movementRadius * 0.7,
          "the Modern movement ring is substantially smaller than its input radius")
    check(TouchControls.movementRadius == 90,
          "the Modern movement input radius remains byte-compatible")

    let roomyIPad = ModernTouchLayout(size: Runner.screen, safeAreaInsets: Runner.safeAreaInsets)
    check(roomyIPad.rightStickSpacer <= ModernTouchLayout.rightStickSpacerCap,
          "the right-stick spacer never exceeds 200 points")
    check(roomyIPad.rightStickSpacer > ModernTouchLayout.legacyRightStickEdge(for: Runner.screen),
          "a roomy iPad moves the right stick inward from its former edge")

    let layouts = [
        roomyIPad,
        ModernTouchLayout(size: CGSize(width: 834, height: 1210),
                          safeAreaInsets: TouchSafeAreaInsets(top: 28, leading: 12,
                                                              bottom: 24, trailing: 12)),
        ModernTouchLayout(size: CGSize(width: 852, height: 393),
                          safeAreaInsets: TouchSafeAreaInsets(top: 0, leading: 59,
                                                              bottom: 21, trailing: 59)),
        ModernTouchLayout(size: CGSize(width: 393, height: 852),
                          safeAreaInsets: TouchSafeAreaInsets(top: 59, leading: 0,
                                                              bottom: 34, trailing: 0)),
    ]
    for (index, layout) in layouts.enumerated() {
        check(layout.safeBounds.contains(layout.rightStickArtworkFrame),
              "Modern layout \(index + 1) keeps the R artwork inside the safe area")
        check(layout.rightStickArtworkFrame.width == TouchControls.rightStickRadius * 2
              && layout.rightStickArtworkFrame.height == TouchControls.rightStickRadius * 2,
              "Modern layout \(index + 1) retains the R-stick visual radius")
        check(layout.rightStickHitFrame == layout.rightStickArtworkFrame.insetBy(
            dx: -ModernTouchLayout.rightStickHitSlop, dy: -ModernTouchLayout.rightStickHitSlop),
              "Modern layout \(index + 1) derives the raw R hit frame from its artwork")
        let pillHits = [layout.selectPillFrame, layout.startPillFrame].map {
            $0.insetBy(dx: -10, dy: -12)
        }
        check(pillHits.allSatisfy {
            let intersection = $0.intersection(layout.rightStickHitFrame)
            return intersection.isNull || intersection.width <= 0.001 || intersection.height <= 0.001
        }, "Modern layout \(index + 1) avoids Pause/Select hit-target overlap")
    }

    var former = Runner()
    var moved = Runner(rightStickFrame: roomyIPad.rightStickHitFrame)
    let formerFinger = Finger()
    let movedFinger = Finger()
    former.down(formerFinger, CGPoint(x: Runner.rightStick.midX, y: Runner.rightStick.midY))
    moved.down(movedFinger, CGPoint(x: roomyIPad.rightStickHitFrame.midX,
                                    y: roomyIPad.rightStickHitFrame.midY))
    former.move(formerFinger, CGPoint(x: Runner.rightStick.midX + 30,
                                      y: Runner.rightStick.midY - 10))
    moved.move(movedFinger, CGPoint(x: roomyIPad.rightStickHitFrame.midX + 30,
                                    y: roomyIPad.rightStickHitFrame.midY - 10))
    check(former.frame() == moved.frame(),
          "moving the R artwork preserves the existing Modern controller bytes")
}

@MainActor
private func defaultStylePreservesModern() {
    print("Modern remains the explicit, byte-compatible default")
    var implicit = Runner()
    var explicit = Runner(style: .modern)
    check(implicit.controls.style == .modern, "TouchControls defaults to Modern")
    check(TouchControlStyle.allCases == [.modern, .classic],
          "the style seam orders Modern before Classic")

    let implicitMovement = Finger()
    let explicitMovement = Finger()
    let implicitLook = Finger()
    let explicitLook = Finger()
    let implicitGesture = Finger()
    let explicitGesture = Finger()
    let implicitStart = Finger()
    let explicitStart = Finger()
    let movementCentre = CGPoint(x: 180, y: 650)
    let lookCentre = CGPoint(x: Runner.rightStick.midX, y: Runner.rightStick.midY)
    let gestureCentre = CGPoint(x: 900, y: 360)
    let startCentre = CGPoint(x: Runner.start.midX, y: Runner.start.midY)

    implicit.down(implicitMovement, movementCentre)
    explicit.down(explicitMovement, movementCentre)
    implicit.move(implicitMovement, CGPoint(x: 240, y: 620))
    explicit.move(explicitMovement, CGPoint(x: 240, y: 620))
    implicit.down(implicitLook, lookCentre)
    explicit.down(explicitLook, lookCentre)
    implicit.move(implicitLook, CGPoint(x: lookCentre.x + 25, y: lookCentre.y - 8))
    explicit.move(explicitLook, CGPoint(x: lookCentre.x + 25, y: lookCentre.y - 8))
    implicit.down(implicitGesture, gestureCentre)
    explicit.down(explicitGesture, gestureCentre)
    implicit.move(implicitGesture, CGPoint(x: gestureCentre.x, y: gestureCentre.y + 60))
    explicit.move(explicitGesture, CGPoint(x: gestureCentre.x, y: gestureCentre.y + 60))
    implicit.down(implicitStart, startCentre)
    explicit.down(explicitStart, startCentre)

    check(implicit.frames(12) == explicit.frames(12),
          "default and explicit Modern emit identical frame bytes")

    implicit.up(implicitGesture)
    explicit.up(explicitGesture)
    implicit.up(implicitStart)
    explicit.up(explicitStart)
    implicit.up(implicitLook)
    explicit.up(explicitLook)
    implicit.up(implicitMovement)
    explicit.up(explicitMovement)
    check(implicit.frames(10) == explicit.frames(10),
          "default and explicit Modern release identically")
}

@MainActor
private func movementOriginFollowsFirstTouch() {
    print("the movement stick appears where the first left-side finger lands")
    var run = Runner()
    let centre = CGPoint(x: 180, y: 650)
    let thumb = Finger()
    run.down(thumb, centre)

    check(run.controls.stick?.origin == centre, "the landing point becomes the stick centre")
    check(run.frame().leftX == neutral, "a new dynamic stick starts neutral")

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

    let newCentre = CGPoint(x: 360, y: 430)
    let relocated = Finger()
    run.down(relocated, newCentre)
    check(run.controls.stick?.origin == newCentre, "the next landing point relocates the base")
    check(run.frame().leftX == neutral, "the relocated stick also starts neutral")
}

@MainActor
private func freeCameraSwipeIsGone() {
    print("the restored left-side movement zone never emits camera input")
    var run = Runner()
    let oldCameraArea = Finger()
    run.down(oldCameraArea, CGPoint(x: 220, y: 420))
    run.move(oldCameraArea, CGPoint(x: 500, y: 250))
    var state = run.frame()
    check(run.controls.stick?.origin == CGPoint(x: 220, y: 420),
          "a first touch anywhere on the left places movement there")
    check(state.isLeftDeflected, "that drag drives movement")
    check(state.rightX == neutral && state.rightY == neutral,
          "a left-side drag leaves the right stick centred")

    let faceGesture = Finger()
    run.down(faceGesture, CGPoint(x: 900, y: 360))
    run.move(faceGesture, CGPoint(x: 900, y: 290))
    state = run.frame()
    check(state.buttons.contains(.cross), "the independent face-button swipe remains available")
    check(!state.isRightDeflected, "a face-button swipe never emits camera axes")
}

@MainActor
private func faceButtonGesturesAndNoTap() {
    print("open-screen gestures retain three face buttons while taps do nothing")
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

    var tapRun = Runner()
    let swipe = Finger()
    tapRun.down(swipe, CGPoint(x: 900, y: 360))
    tapRun.move(swipe, CGPoint(x: 830, y: 360))
    tapRun.up(swipe)
    _ = tapRun.frames(TouchControls.holdFrames + TouchControls.releaseFrames)

    let tap = Finger()
    tapRun.down(tap, CGPoint(x: 900, y: 360))
    tapRun.up(tap)
    check(tapRun.frames(TouchControls.holdFrames).allSatisfy { $0.buttons.isEmpty },
          "a tap does not repeat Cross or any previous swipe")
}

@MainActor
private func rightStickIsFullyAnalog() {
    print("the bottom-right R stick is continuous rather than snapped")
    var run = Runner()
    let centre = CGPoint(x: Runner.rightStick.midX, y: Runner.rightStick.midY)
    let thumb = Finger()
    run.down(thumb, centre)
    check(run.frame().rightX == neutral, "the R-stick centre is neutral")

    run.move(thumb, CGPoint(x: centre.x + TouchControls.rightStickDeadzone, y: centre.y))
    var state = run.frame()
    check(!state.isRightDeflected, "travel through the deadzone stays neutral")

    run.move(thumb, CGPoint(x: centre.x + 20, y: centre.y))
    let partial = run.frame()
    check(partial.rightX > neutral && partial.rightX < 254 && partial.rightY == neutral,
          "a partial horizontal drag stays partially deflected")

    run.move(thumb, CGPoint(x: centre.x + 30, y: centre.y - 10))
    state = run.frame()
    check(state.rightX > partial.rightX && state.rightX < 254,
          "more travel produces more horizontal output")
    check(state.rightY < neutral && state.rightY > 0,
          "an off-octant diagonal preserves its continuous vertical component")

    run.move(thumb, CGPoint(x: centre.x + TouchControls.rightStickRadius, y: centre.y))
    state = run.frame()
    check(state.rightX == 254 && state.rightY == neutral,
          "one full radius reaches hard right")

    run.up(thumb)
    state = run.frame()
    check(state.rightX == neutral && state.rightY == neutral,
          "releasing immediately centres the R stick")
}

@MainActor
private func downwardSwipeCanRollJump() {
    print("a downward swipe holds crouch and reversing upward adds one jump")
    var run = Runner()
    let centre = CGPoint(x: 900, y: 360)
    let finger = Finger()
    run.down(finger, centre)
    run.move(finger, CGPoint(x: centre.x, y: centre.y + TouchControls.swipeDistance + 8))

    let crouching = run.frames(20)
    check(crouching.allSatisfy { $0.buttons.contains(.L1) }, "swipe down and hold keeps L1 down")
    check(crouching.allSatisfy { !$0.buttons.contains(.cross) }, "holding down alone does not jump")

    let crouchPeak = centre.y + TouchControls.swipeDistance + 24
    run.move(finger, CGPoint(x: centre.x, y: crouchPeak))
    run.move(finger, CGPoint(x: centre.x, y: crouchPeak - TouchControls.rollJumpDistance - 8))
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
private func downwardSwipeCanPunchLeft() {
    print("a held downward swipe can add one leftward punch")
    var run = Runner()
    let centre = CGPoint(x: 900, y: 360)
    let finger = Finger()
    run.down(finger, centre)
    run.move(finger, CGPoint(x: centre.x, y: centre.y + TouchControls.swipeDistance + 12))
    check(run.frames(3).allSatisfy {
        $0.buttons.contains(.L1) && !$0.buttons.contains(.square)
    }, "down first holds crouch without punching")

    run.move(finger, CGPoint(x: centre.x - TouchControls.swipeDistance - 8,
                             y: centre.y + TouchControls.swipeDistance + 12))
    let punching = run.frames(TouchControls.holdFrames)
    check(punching.allSatisfy { $0.buttons.contains(.L1) && $0.buttons.contains(.square) },
          "sliding left while held emits crouch and Square together")

    let after = run.frames(TouchControls.releaseFrames + 2)
    check(after.allSatisfy { $0.buttons.contains(.L1) && !$0.buttons.contains(.square) },
          "the crouch punch is one bounded press while crouch remains held")
    run.move(finger, CGPoint(x: centre.x + 30, y: centre.y + 56))
    run.move(finger, CGPoint(x: centre.x - 80, y: centre.y + 56))
    check(run.frames(TouchControls.holdFrames + TouchControls.releaseFrames).allSatisfy {
        $0.buttons.contains(.L1) && !$0.buttons.contains(.square)
    }, "moving away and left again does not retrigger punch on the same finger")

    run.up(finger)
    check(!run.frame().buttons.contains(.L1), "lifting ends crouch after the punch sequence")

    var leftFirst = Runner()
    let ordinary = Finger()
    leftFirst.down(ordinary, centre)
    leftFirst.move(ordinary, CGPoint(x: centre.x - 70, y: centre.y))
    leftFirst.move(ordinary, CGPoint(x: centre.x - 70, y: centre.y + 80))
    let ordinaryStates = leftFirst.frames(TouchControls.holdFrames)
    check(ordinaryStates.allSatisfy {
        $0.buttons.contains(.square) && !$0.buttons.contains(.L1)
    }, "left-first remains the ordinary Square swipe rather than changing into crouch")

    var fresh = Runner()
    let freshFinger = Finger()
    fresh.down(freshFinger, centre)
    fresh.move(freshFinger, CGPoint(x: centre.x, y: centre.y + 60))
    fresh.move(freshFinger, CGPoint(x: centre.x - 70, y: centre.y + 60))
    check(fresh.frames(TouchControls.holdFrames).allSatisfy {
        $0.buttons.contains(.L1) && $0.buttons.contains(.square)
    }, "a fresh down-then-left gesture can punch once")
}

@MainActor
private func controlsWorkTogether() {
    print("movement, look, and swipe roll-jump can share one frame")
    var run = Runner()
    let movement = Finger()
    let look = Finger()
    let action = Finger()
    let movementCentre = CGPoint(x: 180, y: 650)
    let lookCentre = CGPoint(x: Runner.rightStick.midX, y: Runner.rightStick.midY)
    let actionCentre = CGPoint(x: 900, y: 360)

    run.down(movement, movementCentre)
    run.move(movement, CGPoint(x: movementCentre.x + 90, y: movementCentre.y))
    run.down(look, lookCentre)
    run.move(look, CGPoint(x: lookCentre.x,
                           y: lookCentre.y - TouchControls.rightStickRadius))
    run.down(action, actionCentre)
    run.move(action, CGPoint(x: actionCentre.x, y: actionCentre.y + 70))
    run.move(action, CGPoint(x: actionCentre.x, y: actionCentre.y + 20))

    let state = run.frame()
    check(state.leftX == 254 && state.rightY == 0,
          "movement and the R stick both reach the controller seam")
    check(state.buttons.contains(.L1) && state.buttons.contains(.cross),
          "roll and its jump edge are present in that same frame")
}

@MainActor
private func movementAlsoStepsTheDpad() {
    print("strong movement still steps the D-pad for menus")
    var run = Runner()
    let thumb = Finger()
    let centre = CGPoint(x: 180, y: 650)
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
    run.down(finger, CGPoint(x: 180, y: 650))
    check(run.controls.isEngaged, "touching a control shows the artwork")
}

@MainActor
private func resetClearsInterruptedInput() {
    print("reset clears every interrupted input")
    var run = Runner()
    let movement = Finger()
    let look = Finger()
    let action = Finger()
    let movementCentre = CGPoint(x: 180, y: 650)
    let lookCentre = CGPoint(x: Runner.rightStick.midX, y: Runner.rightStick.midY)
    let actionCentre = CGPoint(x: 900, y: 360)

    run.down(movement, movementCentre)
    run.move(movement, CGPoint(x: movementCentre.x + 90, y: movementCentre.y))
    run.down(look, lookCentre)
    run.move(look, CGPoint(x: lookCentre.x + 30, y: lookCentre.y))
    run.down(action, actionCentre)
    run.move(action, CGPoint(x: actionCentre.x, y: actionCentre.y + 60))
    run.move(action, CGPoint(x: actionCentre.x, y: actionCentre.y + 10))
    _ = run.frame()

    run.controls.reset()
    let state = run.frame()
    check(state.buttons.isEmpty, "no held or queued button survives reset")
    check(!state.isLeftDeflected, "movement is centred")
    check(!state.isRightDeflected, "the R stick is centred")
    check(run.controls.touches.isEmpty, "all tracked fingers are discarded")
    check(!run.controls.isEngaged, "the artwork is hidden")
}

@MainActor
private func touchHapticsAreDiscreteAndRearmSafely() {
    print("touch haptics are discrete, style-aware, and reset-safe")
    var modern = Runner()
    let start = Finger()
    let startCentre = CGPoint(x: Runner.start.midX, y: Runner.start.midY)
    modern.down(start, startCentre)
    check(modern.controls.consumeHapticEvents() == [.button(.start)],
          "Modern Start emits one button event at touch-down")
    _ = modern.frames(20)
    check(modern.controls.consumeHapticEvents().isEmpty,
          "held buttons and frame polling do not emit feedback events")
    modern.up(start)
    check(modern.controls.consumeHapticEvents().isEmpty,
          "lifting a button does not add passive feedback")

    let gesture = Finger()
    let gestureCentre = CGPoint(x: 900, y: 360)
    modern.down(gesture, gestureCentre)
    check(modern.controls.consumeHapticEvents().isEmpty,
          "a pending Modern gesture is silent")
    modern.move(gesture, CGPoint(x: gestureCentre.x, y: gestureCentre.y - 60))
    check(modern.controls.consumeHapticEvents() == [.gesture(.cross)],
          "a recognised Modern gesture emits one event")
    modern.move(gesture, CGPoint(x: gestureCentre.x, y: gestureCentre.y - 120))
    _ = modern.frames(20)
    check(modern.controls.consumeHapticEvents().isEmpty,
          "a held gesture never repeats feedback in the frame loop")
    modern.cancel(gesture)
    check(modern.controls.consumeHapticEvents().isEmpty,
          "cancelling a gesture is silent")

    let stick = Finger()
    let stickCentre = CGPoint(x: 180, y: 650)
    modern.down(stick, stickCentre)
    modern.move(stick, CGPoint(x: stickCentre.x + 30, y: stickCentre.y))
    check(modern.controls.consumeHapticEvents().isEmpty,
          "small Modern stick travel does not count as engagement")
    modern.move(stick, CGPoint(x: stickCentre.x + 55, y: stickCentre.y))
    check(modern.controls.consumeHapticEvents() == [.stickEngaged],
          "meaningful Modern stick engagement emits once")
    modern.move(stick, CGPoint(x: stickCentre.x + 90, y: stickCentre.y))
    _ = modern.frames(20)
    check(modern.controls.consumeHapticEvents().isEmpty,
          "held stick movement does not spam feedback")
    modern.cancel(stick)
    let rearmedStick = Finger()
    modern.down(rearmedStick, stickCentre)
    modern.move(rearmedStick, CGPoint(x: stickCentre.x + 55, y: stickCentre.y))
    check(modern.controls.consumeHapticEvents() == [.stickEngaged],
          "cancelling re-arms a new Modern stick contact")

    modern.controls.reset()
    check(modern.controls.consumeHapticEvents().isEmpty,
          "reset clears pending feedback alongside interrupted input")
    let resetStick = Finger()
    modern.down(resetStick, stickCentre)
    modern.move(resetStick, CGPoint(x: stickCentre.x + 55, y: stickCentre.y))
    check(modern.controls.consumeHapticEvents() == [.stickEngaged],
          "reset re-arms a fresh Modern stick contact")

    var classic = Runner(style: .classic)
    let layout = ClassicTouchLayout(size: Runner.screen, safeAreaInsets: Runner.safeAreaInsets)
    let cross = Finger()
    let crossFrame = layout.frame(for: .cross)!
    classic.down(cross, CGPoint(x: crossFrame.midX, y: crossFrame.midY))
    check(classic.controls.consumeHapticEvents() == [.button(.cross)],
          "Classic face buttons emit one direct button event")
    _ = classic.frames(20)
    check(classic.controls.consumeHapticEvents().isEmpty,
          "Classic held buttons also remain silent between touch events")
}

@MainActor
private func styleSwitchClearsInterruptedInput() {
    print("switching profiles cannot strand input from the prior layout")
    var run = Runner()
    let movement = Finger()
    let action = Finger()
    let centre = CGPoint(x: 180, y: 650)
    run.down(movement, centre)
    run.move(movement, CGPoint(x: centre.x + TouchControls.movementRadius, y: centre.y))
    run.down(action, CGPoint(x: 900, y: 360))
    run.move(action, CGPoint(x: 900, y: 420))
    let modernState = run.frame()
    check(modernState.isLeftDeflected && modernState.buttons.contains(.L1),
          "Modern has live stick and held-button state before switching")

    run.controls.setStyle(.classic)
    var state = run.frame()
    check(run.controls.style == .classic, "the requested Classic style becomes active")
    check(state == .neutral, "switching to Classic clears buttons and both sticks")
    check(run.controls.touches.isEmpty && !run.controls.isEngaged,
          "switching discards tracked fingers and hides stale artwork")

    let layout = ClassicTouchLayout(size: Runner.screen,
                                    safeAreaInsets: Runner.safeAreaInsets)
    let classicButton = Finger()
    run.down(classicButton, CGPoint(x: layout.buttonFrames[.cross]!.midX,
                                    y: layout.buttonFrames[.cross]!.midY))
    check(run.frame().buttons.contains(.cross), "Classic accepts a fresh touch after switching")
    run.controls.setStyle(.modern)
    state = run.frame()
    check(state == .neutral && run.controls.touches.isEmpty,
          "switching back to Modern also clears the Classic touch")
}

@MainActor
private func classicButtonsMapDirectly() {
    print("Classic exposes direct Jak 1 pad controls")
    let layout = ClassicTouchLayout(size: Runner.screen,
                                    safeAreaInsets: Runner.safeAreaInsets)
    for button in ClassicTouchLayout.buttons {
        var run = Runner(style: .classic)
        let finger = Finger()
        guard let frame = layout.frame(for: button) else {
            check(false, "Classic has a frame for \(button)")
            continue
        }
        run.down(finger, CGPoint(x: frame.midX, y: frame.midY))
        check(run.frame().buttons == button.bit, "\(button) maps directly to its PS2 bit")
    }
}

@MainActor
private func classicSticksAreSymmetricalAndAnalog() {
    print("Classic has two equal fixed analog sticks")
    var run = Runner(style: .classic)
    let layout = ClassicTouchLayout(size: Runner.screen,
                                    safeAreaInsets: Runner.safeAreaInsets)
    let left = Finger()
    let right = Finger()
    let leftCentre = CGPoint(x: layout.leftStickFrame.midX, y: layout.leftStickFrame.midY)
    let rightCentre = CGPoint(x: layout.rightStickFrame.midX, y: layout.rightStickFrame.midY)

    run.down(left, leftCentre)
    run.down(right, rightCentre)
    var state = run.frame()
    check(!state.isLeftDeflected && !state.isRightDeflected,
          "both Classic sticks begin neutral at their fixed centres")

    run.move(left, CGPoint(x: leftCentre.x + layout.stickRadius, y: leftCentre.y))
    run.move(right, CGPoint(x: rightCentre.x, y: rightCentre.y - layout.stickRadius))
    state = run.frame()
    check(state.leftX == 254 && state.leftY == neutral, "the left stick reaches hard right")
    check(state.rightX == neutral && state.rightY == 0, "the right stick reaches hard up")

    run.up(left)
    run.up(right)
    state = run.frame()
    check(!state.isLeftDeflected && !state.isRightDeflected,
          "lifting either Classic stick centres it immediately")
}

@MainActor
private func classicGeometryStaysSafeAndBalanced() {
    print("Classic geometry is deterministic, safe-area-aware, and balanced")
    let layouts = [
        ClassicTouchLayout(size: Runner.screen, safeAreaInsets: Runner.safeAreaInsets),
        ClassicTouchLayout(size: CGSize(width: 834, height: 1210),
                           safeAreaInsets: TouchSafeAreaInsets(top: 28, leading: 12,
                                                               bottom: 24, trailing: 12)),
        ClassicTouchLayout(size: CGSize(width: 852, height: 393),
                           safeAreaInsets: TouchSafeAreaInsets(top: 0, leading: 59,
                                                               bottom: 21, trailing: 59)),
    ]

    for (index, layout) in layouts.enumerated() {
        let frames = [layout.leftStickFrame, layout.rightStickFrame]
            + ClassicTouchLayout.buttons.compactMap { layout.frame(for: $0) }
        check(frames.allSatisfy { layout.safeBounds.contains($0) },
              "layout \(index + 1) keeps every control inside its safe bounds")
        check(layout.leftStickFrame.size == layout.rightStickFrame.size,
              "layout \(index + 1) gives both sticks the same size")
        check(close(layout.leftStickFrame.midY, layout.rightStickFrame.midY),
              "layout \(index + 1) aligns both sticks vertically")
        check(close(layout.leftStickFrame.midX - layout.safeBounds.minX,
                    layout.safeBounds.maxX - layout.rightStickFrame.midX),
              "layout \(index + 1) mirrors the sticks across the safe centre")
        check(close(layout.frame(for: .leftShoulder)!.midX - layout.safeBounds.minX,
                    layout.safeBounds.maxX - layout.frame(for: .rightShoulder)!.midX),
              "layout \(index + 1) mirrors L1 and R1")
        for (left, right) in [(TouchButton.up, TouchButton.triangle),
                              (.down, .cross), (.left, .circle), (.right, .square)] {
            check(close(layout.frame(for: left)!.midX - layout.safeBounds.minX,
                        layout.safeBounds.maxX - layout.frame(for: right)!.midX)
                  && close(layout.frame(for: left)!.midY, layout.frame(for: right)!.midY),
                  "layout \(index + 1) mirrors \(left) with \(right)")
        }
        let overlaps = frames.indices.contains { first in
            frames.indices.contains { second in
                guard second > first else { return false }
                let intersection = frames[first].intersection(frames[second])
                return intersection.width > 0.001 && intersection.height > 0.001
            }
        }
        check(!overlaps, "layout \(index + 1) leaves clear space between controls")
    }

    let first = layouts[0]
    let repeated = ClassicTouchLayout(size: Runner.screen,
                                      safeAreaInsets: Runner.safeAreaInsets)
    check(first.leftStickFrame == repeated.leftStickFrame
          && first.rightStickFrame == repeated.rightStickFrame
          && first.buttonFrames == repeated.buttonFrames,
          "identical size and insets reproduce identical geometry")
}

@MainActor
private func classicHasNoTriggerOverlay() {
    print("Classic deliberately omits L2 and R2")
    let layout = ClassicTouchLayout(size: Runner.screen,
                                    safeAreaInsets: Runner.safeAreaInsets)
    check(Set(layout.buttonFrames.keys) == Set(ClassicTouchLayout.buttons),
          "the overlay contains exactly the declared Classic controls")
    check(ClassicTouchLayout.buttons.allSatisfy {
        !$0.bit.contains(.L2) && !$0.bit.contains(.R2)
    }, "no visible Classic control maps to L2 or R2")
}

@MainActor
private func classicMultitouchReachesOneFrame() {
    print("Classic fixed controls support simultaneous gameplay input")
    var run = Runner(style: .classic)
    let layout = ClassicTouchLayout(size: Runner.screen,
                                    safeAreaInsets: Runner.safeAreaInsets)
    let movement = Finger()
    let look = Finger()
    let jump = Finger()
    let shoulder = Finger()
    let start = Finger()
    let leftCentre = CGPoint(x: layout.leftStickFrame.midX, y: layout.leftStickFrame.midY)
    let rightCentre = CGPoint(x: layout.rightStickFrame.midX, y: layout.rightStickFrame.midY)

    run.down(movement, leftCentre)
    run.move(movement, CGPoint(x: leftCentre.x + layout.stickRadius, y: leftCentre.y))
    run.down(look, rightCentre)
    run.move(look, CGPoint(x: rightCentre.x, y: rightCentre.y - layout.stickRadius))
    for (finger, button) in [(jump, TouchButton.cross),
                             (shoulder, .leftShoulder),
                             (start, .start)] {
        let frame = layout.frame(for: button)!
        run.down(finger, CGPoint(x: frame.midX, y: frame.midY))
    }

    let state = run.frame()
    check(state.leftX == 254 && state.rightY == 0,
          "both analog sticks coexist in one Classic frame")
    check(state.buttons.contains(.cross) && state.buttons.contains(.L1)
          && state.buttons.contains(.start),
          "face, shoulder, and Start touches coexist with both sticks")
}

@MainActor
private func pausePresentationFollowsNativeMenuState() {
    print("native menu drives Pause/Resume artwork and visibility")
    check(TouchControls.artworkLabel(for: .start, isNativeMenuOpen: false) == "PAUSE",
          "gameplay Start artwork says PAUSE")
    check(TouchControls.artworkLabel(for: .start, isNativeMenuOpen: true) == "RESUME",
          "native-menu Start artwork says RESUME")
    check(TouchControls.artworkLabel(for: .select, isNativeMenuOpen: false) == "SELECT",
          "Select keeps its existing label")

    check(TouchControls.artworkIsVisible(isEngaged: false, isSuppressed: false,
                                         hasTouches: false, isNativeMenuOpen: true),
          "the native menu keeps idle fallback artwork visible")
    check(!TouchControls.artworkIsVisible(isEngaged: false, isSuppressed: true,
                                          hasTouches: false, isNativeMenuOpen: true),
          "controller suppression hides idle native-menu artwork")
    check(TouchControls.artworkIsVisible(isEngaged: false, isSuppressed: true,
                                         hasTouches: true, isNativeMenuOpen: true),
          "a live touch restores native-menu artwork under suppression")

    var run = Runner()
    let finger = Finger()
    let centre = CGPoint(x: Runner.start.midX, y: Runner.start.midY)
    run.down(finger, centre)
    check(run.frame().buttons.contains(.start),
          "Pause/Resume presentation preserves the Start input bit")
}

private func controllerSuppressionKeepsTouchRecovery() {
    print("controller suppression hides idle artwork but permits touch recovery")
    check(TouchControls.artworkIsVisible(isEngaged: true, isSuppressed: false,
                                         hasTouches: false, isNativeMenuOpen: false),
          "engaged artwork is visible without controller suppression")
    check(!TouchControls.artworkIsVisible(isEngaged: true, isSuppressed: true,
                                          hasTouches: false, isNativeMenuOpen: false),
          "controller suppression hides idle touch artwork")
    check(TouchControls.artworkIsVisible(isEngaged: true, isSuppressed: true,
                                         hasTouches: true, isNativeMenuOpen: false),
          "a live screen touch reveals controls despite prior suppression")
    check(!TouchControls.artworkIsVisible(isEngaged: false, isSuppressed: false,
                                          hasTouches: false, isNativeMenuOpen: false),
          "unengaged artwork remains hidden")
}

@main
@MainActor
struct TouchControlsCheck {
    static func main() {
        modernLayoutIsCompactAndSafe()
        defaultStylePreservesModern()
        movementOriginFollowsFirstTouch()
        freeCameraSwipeIsGone()
        faceButtonGesturesAndNoTap()
        rightStickIsFullyAnalog()
        downwardSwipeCanRollJump()
        downwardSwipeCanPunchLeft()
        controlsWorkTogether()
        movementAlsoStepsTheDpad()
        pillsRemainExplicitControls()
        visibilityFollowsRecognisedTouch()
        resetClearsInterruptedInput()
        touchHapticsAreDiscreteAndRearmSafely()
        styleSwitchClearsInterruptedInput()
        classicButtonsMapDirectly()
        classicSticksAreSymmetricalAndAnalog()
        classicGeometryStaysSafeAndBalanced()
        classicHasNoTriggerOverlay()
        classicMultitouchReachesOneFrame()
        pausePresentationFollowsNativeMenuState()
        controllerSuppressionKeepsTouchRecovery()

        print(failures == 0 ? "\nall checks passed" : "\n\(failures) checks FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
