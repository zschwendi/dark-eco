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

    let screen: CGSize
    let safeAreaInsets: TouchSafeAreaInsets
    let controls: TouchControls
    var clock: TimeInterval = 0

    init(style: TouchControlStyle = .modern) {
        self.init(style: style, rightStickFrame: Self.rightStick)
    }

    init(style: TouchControlStyle = .modern, rightStickFrame: CGRect) {
        self.init(style: style, size: Self.screen, safeAreaInsets: Self.safeAreaInsets,
                  rightStickFrame: rightStickFrame)
    }

    init(style: TouchControlStyle,
         size: CGSize,
         safeAreaInsets: TouchSafeAreaInsets = .zero,
         rightStickFrame: CGRect) {
        self.screen = size
        self.safeAreaInsets = safeAreaInsets
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
        controls.began(ObjectIdentifier(finger), at: point, in: screen,
                       safeAreaInsets: safeAreaInsets, at: clock)
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

    func beginPinch() {
        controls.pinchBegan()
    }

    func pinch(scale: CGFloat, lookAroundState: GOALPadLookAroundState) {
        controls.pinchChanged(scale: scale, lookAroundState: lookAroundState)
    }

    func endPinch() {
        controls.pinchEnded()
    }

    func cancelPinch() {
        controls.pinchCancelled()
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
private func modernPinchZoomUsesAuthoritativeDirection() {
    print("Modern pinch zoom maps outward/inward scale to one authoritative Triangle pulse")
    var zoomIn = Runner()
    zoomIn.beginPinch()
    zoomIn.pinch(scale: 1 + TouchControls.pinchScaleDelta / 2, lookAroundState: .normal)
    check(!zoomIn.frame().buttons.contains(.triangle),
          "sub-threshold outward movement emits nothing")
    zoomIn.pinch(scale: 1 + TouchControls.pinchScaleDelta, lookAroundState: .normal)
    zoomIn.pinch(scale: 1.8, lookAroundState: .normal)
    check(zoomIn.controls.consumeHapticEvents() == [.gesture(.triangle)],
          "zooming in from normal recognises one Triangle gesture")
    let zoomInFrames = zoomIn.frames(TouchControls.holdFrames
                                     + TouchControls.releaseFrames + 2)
    check(zoomInFrames.prefix(TouchControls.holdFrames).allSatisfy {
        $0.buttons.contains(.triangle)
    }, "zooming in from normal emits one complete Triangle pulse")
    check(zoomInFrames.dropFirst(TouchControls.holdFrames).allSatisfy {
        !$0.buttons.contains(.triangle)
    }, "continued outward movement does not queue another Triangle pulse")

    zoomIn.endPinch()
    zoomIn.beginPinch()
    zoomIn.pinch(scale: 1 - TouchControls.pinchScaleDelta,
                 lookAroundState: .firstPerson)
    let zoomOutFrames = zoomIn.frames(TouchControls.holdFrames
                                      + TouchControls.releaseFrames + 2)
    check(zoomOutFrames.prefix(TouchControls.holdFrames).allSatisfy {
        $0.buttons.contains(.triangle)
    }, "zooming out from first person emits one complete Triangle pulse")
    check(zoomOutFrames.dropFirst(TouchControls.holdFrames).allSatisfy {
        !$0.buttons.contains(.triangle)
    }, "the zoom-out pulse has the required release and stays one-shot")
}

@MainActor
private func modernPinchZoomFailsClosedWithoutARequestedTransition() {
    print("Modern pinch zoom fails closed for current, unknown, and reversed directions")
    var normal = Runner()
    normal.beginPinch()
    normal.pinch(scale: 1 - TouchControls.pinchScaleDelta, lookAroundState: .normal)
    normal.pinch(scale: 1 + TouchControls.pinchScaleDelta, lookAroundState: .normal)
    check(normal.frames(TouchControls.holdFrames + 2).allSatisfy {
        !$0.buttons.contains(.triangle)
    }, "zoom-out from normal stays inert and cannot reverse into zoom-in")

    var firstPerson = Runner()
    firstPerson.beginPinch()
    firstPerson.pinch(scale: 1 + TouchControls.pinchScaleDelta,
                      lookAroundState: .firstPerson)
    firstPerson.pinch(scale: 1 - TouchControls.pinchScaleDelta,
                      lookAroundState: .firstPerson)
    check(firstPerson.frames(TouchControls.holdFrames + 2).allSatisfy {
        !$0.buttons.contains(.triangle)
    }, "zoom-in from first person stays inert and cannot reverse into zoom-out")

    var unknown = Runner()
    unknown.beginPinch()
    unknown.pinch(scale: 1 + TouchControls.pinchScaleDelta, lookAroundState: .unknown)
    unknown.pinch(scale: 1 - TouchControls.pinchScaleDelta, lookAroundState: .unknown)
    check(unknown.frames(TouchControls.holdFrames + 2).allSatisfy {
        !$0.buttons.contains(.triangle)
    }, "unknown, including Billy and other first-person modes, emits nothing")
    check(normal.controls.consumeHapticEvents().isEmpty
          && firstPerson.controls.consumeHapticEvents().isEmpty
          && unknown.controls.consumeHapticEvents().isEmpty,
          "failed-closed pinches emit no gesture haptics")
}

@MainActor
private func pinchZoomIsModernOnlyAndLifecycleSafe() {
    print("pinch zoom is Modern-only and re-arms only after an explicit lifecycle boundary")
    var classic = Runner(style: .classic)
    classic.beginPinch()
    classic.pinch(scale: 1 + TouchControls.pinchScaleDelta, lookAroundState: .normal)
    classic.endPinch()
    classic.beginPinch()
    classic.pinch(scale: 1 - TouchControls.pinchScaleDelta,
                  lookAroundState: .firstPerson)
    check(classic.frames(TouchControls.holdFrames + 2).allSatisfy {
        !$0.buttons.contains(.triangle)
    }, "Classic ignores both pinch directions")

    var cancelled = Runner()
    cancelled.beginPinch()
    cancelled.pinch(scale: 1 + TouchControls.pinchScaleDelta / 2,
                     lookAroundState: .normal)
    cancelled.cancelPinch()
    cancelled.pinch(scale: 1 + TouchControls.pinchScaleDelta, lookAroundState: .normal)
    check(!cancelled.frame().buttons.contains(.triangle),
          "a cancelled recognizer cannot emit until a new pinch begins")
    cancelled.beginPinch()
    cancelled.pinch(scale: 1 + TouchControls.pinchScaleDelta, lookAroundState: .normal)
    check(cancelled.frame().buttons.contains(.triangle),
          "a new pinch can emit after cancellation")

    cancelled.controls.reset()
    check(cancelled.frame() == .neutral,
          "reset clears an emitted pinch pulse and its recognizer state")
    cancelled.beginPinch()
    cancelled.pinch(scale: 1 + TouchControls.pinchScaleDelta, lookAroundState: .normal)
    check(cancelled.frame().buttons.contains(.triangle),
          "reset re-arms a fresh Modern pinch")
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
private func classicHitTargetsLeaveArtworkAndBytesIntact() {
    print("Classic hit targets expand without moving compact artwork or remapping controls")
    let compactSize = CGSize(width: 280, height: 160)
    let layout = ClassicTouchLayout(size: compactSize)
    let expectedVisualFrames: [TouchButton: CGRect] = [
        .up: CGRect(x: 32, y: 74, width: 22, height: 22),
        .down: CGRect(x: 32, y: 130, width: 22, height: 22),
        .left: CGRect(x: 4, y: 102, width: 22, height: 22),
        .right: CGRect(x: 60, y: 102, width: 22, height: 22),
        .triangle: CGRect(x: 226, y: 74, width: 22, height: 22),
        .cross: CGRect(x: 226, y: 130, width: 22, height: 22),
        .square: CGRect(x: 198, y: 102, width: 22, height: 22),
        .circle: CGRect(x: 254, y: 102, width: 22, height: 22),
        .leftShoulder: CGRect(x: 59, y: 51, width: 41, height: 17),
        .rightShoulder: CGRect(x: 180, y: 51, width: 41, height: 17),
        .select: CGRect(x: 123, y: 31, width: 34, height: 15),
        .start: CGRect(x: 123, y: 52, width: 34, height: 15),
    ]
    check(layout.buttonFrames == expectedVisualFrames,
          "the compact Classic artwork retains its existing scaled frames")

    let hitFrames = ClassicTouchLayout.buttons.compactMap { layout.hitFrame(for: $0) }
    check(hitFrames.count == ClassicTouchLayout.buttons.count,
          "every Classic artwork control has an app-owned hit target")
    check(hitFrames.allSatisfy {
        $0.width >= ClassicTouchLayout.minimumButtonHitSize.width
            && $0.height >= ClassicTouchLayout.minimumButtonHitSize.height
    }, "every compact Classic hit target is at least 44 by 44 points")
    check(hitFrames.allSatisfy { layout.safeBounds.contains($0) },
          "every compact Classic hit target stays inside the safe bounds")
    check(ClassicTouchLayout.buttons.allSatisfy {
        guard let visual = layout.frame(for: $0), let hit = layout.hitFrame(for: $0) else {
            return false
        }
        return hit.contains(visual)
    }, "every compact hit target still contains its visible control")

    for button in ClassicTouchLayout.buttons {
        guard let visualFrame = layout.frame(for: button) else {
            check(false, "Classic has compact artwork for \(button)")
            continue
        }
        let visualCentre = CGPoint(x: visualFrame.midX, y: visualFrame.midY)
        let owners = ClassicTouchLayout.buttons.filter {
            layout.hitFrame(for: $0)?.contains(visualCentre) == true
        }
        check(owners == [button],
              "the compact \(button) artwork centre has one deterministic hit owner")

        var run = Runner(style: .classic, size: compactSize, rightStickFrame: .zero)
        let finger = Finger()
        run.down(finger, visualCentre)
        check(run.frame().buttons == button.bit,
              "the compact \(button) hit target preserves its controller byte")
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

    var recoveries = 0
    check(TouchControlsView.requestTouchRecovery(isSuppressed: true) {
        recoveries += 1
        return true
    } && recoveries == 1,
          "the first suppressed screen contact invokes immediate touch recovery")
    check(!TouchControlsView.requestTouchRecovery(isSuppressed: false) {
        recoveries += 1
        return true
    } && recoveries == 1,
          "an already visible touch UI does not repeat recovery work")
    check(!TouchControlsView.requestTouchRecovery(isSuppressed: true) { false },
          "an explicit physical source can reject recovery without exposing an action")
}

private func progressSnapshot(screen: Int, option: Int = 0,
                              selected: Bool = false,
                              transition: Bool = false) -> NativeProgressMenuSnapshot {
    NativeProgressMenuSnapshot(available: true, screenRawValue: screen, optionIndex: option,
                               selectedOption: selected, inTransition: transition)
}

private func warpList(slot: Int32 = 0, mask: UInt32 = 0x1f,
                      moving: Bool = false,
                      sequence: UInt32 = 2) -> NativeWarpGateTouchSnapshot {
    .destinationListActive(selectedSlot: slot, permittedMask: mask,
                           selectionMoving: moving, sequence: sequence)
}

@MainActor
private func nativeMenuActionsAreTruthfullyGatedAndLabelled() {
    print("dedicated native-menu actions use only authoritative mode meanings")
    check(NativeMenuTouchAction.available(in: .pause) == [.resume],
          "pause exposes only the authoritative Start resume action")
    check(NativeMenuTouchAction.available(in: .menu)
          == [.up, .down, .left, .right, .back, .confirm, .resume],
          "debug menu exposes its exact D-pad, Square, X, and Start actions")
    check(NativeMenuTouchAction.available(in: .progress).isEmpty,
          "progress fails closed without an authoritative internal snapshot")
    let stats = progressSnapshot(screen: 0)
    check(NativeMenuTouchAction.available(in: .progress, progress: stats)
          == [.fuelCells, .precursorOrbs, .scoutFlies, .settings],
          "stats expose the exact Square, X, Triangle, and Circle destinations")
    let settings = progressSnapshot(screen: 3, option: 2)
    check(NativeMenuTouchAction.available(in: .progress, progress: settings)
          == [.up, .down, .confirm],
          "unselected settings expose only the PC responder's Up, Down, and Confirm meanings")
    check(NativeMenuTouchAction.available(
        in: .progress, progress: progressSnapshot(screen: 3, option: 2, selected: true))
          == [.left, .right, .cancel, .confirm],
          "selected settings expose the source-proven unconditional Cancel meaning")
    check(NativeMenuTouchAction.available(
        in: .progress, progress: progressSnapshot(screen: 16, option: 4))
          == [.up, .down, .back, .confirm],
          "load files expose the source-proven file-list Back meaning")
    check(NativeMenuTouchAction.available(
        in: .progress, progress: progressSnapshot(screen: 3, option: 7))
          == [.up, .down, .confirm],
          "the eighth shipping main-settings row remains reachable")
    let shippingPCLists = [
        (label: "settings with secrets", screen: 3, optionCount: 9),
        (label: "game settings", screen: 4, optionCount: 10),
        (label: "graphic settings", screen: 5, optionCount: 5),
        (label: "sound settings", screen: 6, optionCount: 4),
        (label: "title", screen: 27, optionCount: 6),
        (label: "title settings", screen: 28, optionCount: 4),
    ]
    for list in shippingPCLists {
        check(NativeMenuTouchAction.available(
            in: .progress,
            progress: progressSnapshot(screen: list.screen, option: list.optionCount - 1))
              == [.up, .down, .confirm],
              "the highest valid \(list.label) shipping row remains reachable")
        check(NativeMenuTouchAction.available(
            in: .progress,
            progress: progressSnapshot(screen: list.screen, option: list.optionCount)).isEmpty,
              "the first invalid \(list.label) row fails closed")
    }
    check(NativeMenuTouchAction.available(
        in: .progress, progress: progressSnapshot(screen: 29)).isEmpty
          && NativeMenuTouchAction.available(
            in: .progress, progress: progressSnapshot(screen: 3, transition: true)).isEmpty
          && NativeMenuTouchAction.available(
            in: .progress, progress: progressSnapshot(screen: 35)).isEmpty,
          "auto-save, transition, and unclassified PC progress states remain inert")
    check(NativeMenuTouchAction.available(in: .gameplay).isEmpty
          && NativeMenuTouchAction.available(in: .unknown).isEmpty,
          "gameplay and unknown modes expose no native-menu actions")

    check(NativeMenuTouchAction.confirm.button.bit == .cross
          && NativeMenuTouchAction.back.button.bit == .square
          && NativeMenuTouchAction.cancel.button.bit == .square
          && NativeMenuTouchAction.resume.button.bit == .start,
          "Confirm, Back, Cancel, and Resume retain Jak's ordinary pad bytes")
    check(NativeMenuTouchAction.fuelCells.button.bit == .square
          && NativeMenuTouchAction.precursorOrbs.button.bit == .cross
          && NativeMenuTouchAction.scoutFlies.button.bit == .triangle
          && NativeMenuTouchAction.settings.button.bit == .circle,
          "stats destinations use Jak's exact face-button mapping")
    check(NativeMenuTouchAction.confirm.label == "Confirm"
          && NativeMenuTouchAction.back.label == "Back"
          && NativeMenuTouchAction.cancel.label == "Cancel"
          && NativeMenuTouchAction.resume.label == "Resume",
          "command targets have explicit accessible labels")
    check(NativeMenuTouchAction.fuelCells.label == "Fuel Cells"
          && NativeMenuTouchAction.precursorOrbs.label == "Precursor Orbs"
          && NativeMenuTouchAction.scoutFlies.label == "Scout Flies"
          && NativeMenuTouchAction.settings.label == "Settings",
          "stats targets use exact user-facing names")
    check(NativeMenuTouchAction.up.label == "Up"
          && NativeMenuTouchAction.down.label == "Down"
          && NativeMenuTouchAction.left.label == "Left"
          && NativeMenuTouchAction.right.label == "Right",
          "direction targets have deterministic navigation labels")
}

@MainActor
private func nativeMenuActionsEmitOnlyExpectedInputBytes() {
    print("dedicated native-menu actions emit ordinary isolated pad pulses")
    var run = Runner()
    run.controls.setNativeMenuMode(.menu)
    run.controls.performNativeMenuAction(.up)
    run.controls.performNativeMenuAction(.confirm)
    run.controls.performNativeMenuAction(.back)
    run.controls.performNativeMenuAction(.resume)
    check(run.controls.consumeHapticEvents() == [
        .button(.up), .button(.cross), .button(.square), .button(.start),
    ], "menu actions emit immediate touch-owned feedback events")
    check(run.controls.consumeHapticEvents().isEmpty,
          "menu feedback events are consumed exactly once")

    let held = run.frames(TouchControls.holdFrames)
    check(held.allSatisfy {
        $0.buttons.contains(.up) && $0.buttons.contains(.cross)
            && $0.buttons.contains(.square) && $0.buttons.contains(.start)
    }, "menu actions hold the expected pad bits for one pulse")
    check(held.allSatisfy {
        !$0.isLeftDeflected && !$0.isRightDeflected
            && !$0.buttons.contains(.L1) && !$0.buttons.contains(.triangle)
    }, "menu actions emit no gameplay axes or unrelated buttons")
    check(run.frames(TouchControls.releaseFrames + 1).allSatisfy { $0.buttons.isEmpty },
          "menu pulses include a deterministic release")

    run.controls.setNativeMenuMode(.progress)
    run.controls.performNativeMenuAction(.confirm)
    check(run.frame() == .neutral,
          "a stale Confirm action is rejected when progress has no authoritative snapshot")

    run.controls.setNativeMenuState(.progress, progress: progressSnapshot(screen: 0))
    run.controls.performNativeMenuAction(.fuelCells)
    run.controls.performNativeMenuAction(.precursorOrbs)
    run.controls.performNativeMenuAction(.scoutFlies)
    run.controls.performNativeMenuAction(.settings)
    check(run.controls.consumeHapticEvents() == [
        .button(.square), .button(.cross), .button(.triangle), .button(.circle),
    ], "progress stats actions emit immediate exact feedback events")
    let statsFrame = run.frame()
    check(statsFrame.buttons.contains(.square) && statsFrame.buttons.contains(.cross)
          && statsFrame.buttons.contains(.triangle) && statsFrame.buttons.contains(.circle),
          "progress stats actions emit exact ordinary pad bits")

    run.controls.setNativeMenuState(.progress,
                                    progress: progressSnapshot(screen: 4, option: 9))
    run.controls.performNativeMenuAction(.left)
    run.controls.performNativeMenuAction(.confirm)
    check(run.controls.consumeHapticEvents() == [.button(.cross)],
          "unselected PC rows reject stale Left and emit only Confirm")

    run.controls.setNativeMenuState(
        .progress, progress: progressSnapshot(screen: 3, option: 1, selected: true))
    run.controls.performNativeMenuAction(.back)
    run.controls.performNativeMenuAction(.cancel)
    check(run.controls.consumeHapticEvents() == [.button(.square)],
          "selected option rejects stale Back and emits only the truthful Cancel pulse")
}

@MainActor
private func nativeProgressListSwipeIsOneShotAndStateGated() {
    print("progress list swipes are one-shot, directional, and fail closed")
    var run = Runner()
    run.controls.setNativeMenuState(.progress,
                                    progress: progressSnapshot(screen: 3, option: 1))
    check(!run.controls.performNativeMenuVerticalSwipe(
        translation: CGSize(width: 0, height: -(TouchControls.nativeMenuSwipeDistance - 1))),
          "subthreshold vertical swipe is inert")
    check(!run.controls.performNativeMenuVerticalSwipe(
        translation: CGSize(width: TouchControls.nativeMenuSwipeDistance + 1,
                            height: TouchControls.nativeMenuSwipeDistance)),
          "horizontal-dominant swipe is inert")
    check(run.controls.performNativeMenuVerticalSwipe(
        translation: CGSize(width: 2, height: -TouchControls.nativeMenuSwipeDistance)),
          "upward settings-list swipe is accepted")
    check(run.controls.consumeHapticEvents() == [.button(.up)],
          "one completed swipe emits one feedback event")
    check(run.frame().buttons.contains(.up), "upward swipe emits one Up pulse")

    run.controls.setNativeMenuState(.progress,
                                    progress: progressSnapshot(screen: 3, option: 2))
    check(run.controls.performNativeMenuVerticalSwipe(
        translation: CGSize(width: 0, height: TouchControls.nativeMenuSwipeDistance)),
          "downward settings-list swipe is accepted")
    check(run.controls.consumeHapticEvents() == [.button(.down)],
          "downward swipe emits one feedback event")
    check(run.frame().buttons.contains(.down), "downward swipe emits one Down pulse")

    run.controls.setNativeMenuState(.progress,
                                    progress: progressSnapshot(screen: 3, option: 2,
                                                               transition: true))
    check(run.frame() == .neutral, "entering transition cancels an unfinished list pulse")
    check(!run.controls.performNativeMenuVerticalSwipe(
        translation: CGSize(width: 0, height: -TouchControls.nativeMenuSwipeDistance)),
          "transitioning progress state rejects a stale list swipe")
    run.controls.setNativeMenuState(.progress, progress: progressSnapshot(screen: 0))
    check(!run.controls.performNativeMenuVerticalSwipe(
        translation: CGSize(width: 0, height: -TouchControls.nativeMenuSwipeDistance)),
          "stats shortcuts do not pretend to be a selectable list")
}

@MainActor
private func nativeMenuTransitionPreventsGameplayLeakage() {
    print("entering dedicated menu controls cancels gameplay gestures")
    var run = Runner()
    let movement = Finger()
    let gesture = Finger()
    let movementCentre = CGPoint(x: 180, y: 650)
    let gestureCentre = CGPoint(x: 900, y: 360)
    run.down(movement, movementCentre)
    run.move(movement, CGPoint(x: movementCentre.x + TouchControls.movementRadius,
                               y: movementCentre.y))
    run.down(gesture, gestureCentre)
    run.move(gesture, CGPoint(x: gestureCentre.x, y: gestureCentre.y + 60))
    check(run.frame().isLeftDeflected, "gameplay input is live before the mode transition")

    run.controls.setNativeMenuMode(.menu)
    check(run.frame() == .neutral,
          "entering the menu clears carried stick, crouch, and queued gesture state")
    let ignored = Finger()
    run.down(ignored, movementCentre)
    run.move(ignored, CGPoint(x: movementCentre.x + TouchControls.movementRadius,
                              y: movementCentre.y))
    run.beginPinch()
    run.pinch(scale: 1 + TouchControls.pinchScaleDelta, lookAroundState: .normal)
    check(run.frame() == .neutral,
          "raw gameplay touch and pinch input stay disabled under dedicated menu controls")

    run.controls.setNativeMenuMode(.progress)
    let progressIgnored = Finger()
    run.down(progressIgnored, movementCentre)
    run.move(progressIgnored,
             CGPoint(x: movementCentre.x + TouchControls.movementRadius,
                     y: movementCentre.y))
    check(run.frame() == .neutral,
          "unavailable progress state remains inert instead of leaking gameplay touch")
}

@MainActor
private func nativeMenuSuppressionCancellationAndResetAreSafe() {
    print("menu chrome follows controller suppression and cancellation boundaries")
    check(TouchControls.nativeMenuControlsAreVisible(mode: .menu, isSuppressed: false),
          "menu controls are visible without physical-input suppression")
    check(!TouchControls.nativeMenuControlsAreVisible(mode: .menu, isSuppressed: true),
          "physical controller activity suppresses menu touch chrome")
    check(!TouchControls.nativeMenuControlsAreVisible(mode: .progress, isSuppressed: false),
          "unavailable progress does not present controls with unproven labels")
    check(TouchControls.nativeMenuControlsAreVisible(
        mode: .progress, progress: progressSnapshot(screen: 0), isSuppressed: false),
          "validated progress stats present exact touch controls")
    check(!TouchControls.nativeMenuControlsAreVisible(
        mode: .progress, progress: progressSnapshot(screen: 0), isSuppressed: true),
          "physical controller activity suppresses progress touch chrome")
    check(TouchControls.capturesNativeMenuInput(mode: .progress),
          "progress captures raw gameplay touch even when its command set is inert")

    var run = Runner()
    run.controls.setNativeMenuMode(.menu)
    run.controls.performNativeMenuAction(.confirm)
    run.controls.setNativeMenuMode(.gameplay)
    check(run.frame() == .neutral, "leaving the native menu cancels an unfinished pulse")

    run.controls.setNativeMenuMode(.menu)
    run.controls.performNativeMenuAction(.back)
    run.controls.reset()
    check(run.frame() == .neutral, "lifecycle reset clears dedicated menu input")
}

private func nativeWarpActionsAreStructurallyGatedAndExact() {
    print("warp-gate actions validate exact authoritative semantics")
    let prompt = NativeWarpGateTouchSnapshot.circleUseAvailable(sequence: 10)
    check(NativeWarpGateTouchAction.available(in: .gameplay, snapshot: prompt)
          == [.useWarpGate],
          "the Circle-use prompt exposes only Use Warp Gate")
    check(NativeWarpGateTouchAction.available(in: .pause, snapshot: prompt).isEmpty,
          "a warp snapshot outside gameplay cannot override native-menu semantics")

    for slot in 0...4 {
        let list = warpList(slot: Int32(slot), mask: UInt32(1 << slot),
                            sequence: UInt32(slot * 2 + 20))
        check(NativeWarpGateTouchAction.available(in: .gameplay, snapshot: list)
              == [.previous, .next, .warp, .back],
              "destination slot \(slot) accepts only the five-bit permitted mask")
    }
    check(NativeWarpGateTouchAction.available(
        in: .gameplay, snapshot: warpList(slot: 2, mask: 0b00011)).isEmpty,
          "a selected destination outside the permitted mask fails closed")
    check(NativeWarpGateTouchAction.available(
        in: .gameplay, snapshot: warpList(slot: 2, moving: true)) == [.warp, .back],
          "selection movement gates Left and Right but retains source-proven Warp and Back")
    check(NativeWarpGateTouchAction.available(
        in: .gameplay, snapshot: .transitioning(sequence: 30)).isEmpty,
          "warp transition presents no actions")
    check(NativeWarpGateTouchAction.available(
        in: .gameplay, snapshot: .invalid).isEmpty
          && NativeWarpGateTouchAction.available(
            in: .gameplay, snapshot: .validUnavailable(sequence: 32)).isEmpty,
          "invalid and valid unavailable states both present no actions")

    let invalidSlotLow = warpList(slot: -1)
    let invalidSlotHigh = warpList(slot: 5)
    let invalidMask = warpList(mask: 0x20)
    let unpermittedSelection = warpList(slot: 4, mask: 0x0f)
    let malformedPrompt = NativeWarpGateTouchSnapshot(
        valid: true, state: .circleUseAvailable, selectedSlot: 0,
        permittedMask: 1, selectionMoving: false, sequence: 34)
    let oddPublication = NativeWarpGateTouchSnapshot.circleUseAvailable(sequence: 35)
    let rejectedSchema = NativeWarpGateTouchSnapshot(
        valid: false, state: .destinationListActive, selectedSlot: 0,
        permittedMask: 1, selectionMoving: false, sequence: 36)
    check([invalidSlotLow, invalidSlotHigh, invalidMask, unpermittedSelection,
           malformedPrompt, oddPublication, rejectedSchema].allSatisfy {
        NativeWarpGateTouchAction.available(in: .gameplay, snapshot: $0).isEmpty
    }, "odd or invalid schema, slots, masks, selections, and fields fail closed")

    check(NativeWarpGateTouchAction.useWarpGate.button.bit == .circle
          && NativeWarpGateTouchAction.previous.button.bit == .left
          && NativeWarpGateTouchAction.next.button.bit == .right
          && NativeWarpGateTouchAction.warp.button.bit == .circle
          && NativeWarpGateTouchAction.back.button.bit == .triangle,
          "warp actions map exactly to Circle, Left, Right, Circle, and Triangle")
    check(NativeWarpGateTouchAction.back.button != NativeMenuTouchAction.back.button
          && NativeWarpGateTouchAction.warp.button != NativeMenuTouchAction.confirm.button,
          "warp Back and Warp do not reuse the menu's Square and Cross actions")
    check(NativeWarpGateTouchAction.allCases.map(\.label)
          == ["Use Warp Gate", "Previous", "Next", "Warp", "Back"],
          "warp controls retain their exact accessible labels")
}

private func nativeWarpDestinationLayoutAdaptsWithoutClipping() {
    print("warp destination actions adapt without changing their semantics")
    let wide = NativeWarpGateTouchLayout(availableWidth: 794, actionCount: 4)
    check(wide.arrangement == .wideRow && wide.columnCount == 4
          && wide.buttonWidth == NativeWarpGateTouchLayout.wideButtonMinimumWidth,
          "ordinary wide layouts preserve the four-button 104-point row")

    let compactWidths: [CGFloat] = [353, 280, 232]
    for width in compactWidths {
        let layout = NativeWarpGateTouchLayout(availableWidth: width, actionCount: 4)
        let occupiedWidth = layout.buttonWidth * CGFloat(layout.columnCount)
            + NativeWarpGateTouchLayout.compactSpacing * CGFloat(layout.columnCount - 1)
        check(layout.arrangement == .compactGrid && layout.columnCount == 2,
              "each compact portrait or multitasking width uses two columns")
        check(occupiedWidth <= width && layout.buttonWidth
              >= NativeWarpGateTouchLayout.minimumTargetDimension,
              "each compact layout fits without clipping 44-point targets")
    }
    check(NativeWarpGateTouchLayout.buttonMinimumHeight
          >= NativeWarpGateTouchLayout.minimumTargetDimension,
          "every wide and compact destination action keeps a 44-point minimum target")

    let prompt = NativeWarpGateTouchLayout(availableWidth: 232, actionCount: 1)
    check(prompt.arrangement == .wideRow && prompt.columnCount == 1
          && prompt.buttonWidth == 168,
          "the single Use Warp Gate prompt retains its existing presentation")
}

@MainActor
private func nativeWarpPromptCoexistsAndRejectsStaleActions() {
    print("warp prompt coexists with gameplay and rejects stale closures")
    var run = Runner()
    run.controls.setNativeMenuMode(.gameplay)
    let prompt = NativeWarpGateTouchSnapshot.circleUseAvailable(sequence: 40)
    run.controls.setWarpGateTouchSnapshot(prompt)

    let movement = Finger()
    let centre = CGPoint(x: 180, y: 650)
    run.down(movement, centre)
    run.move(movement, CGPoint(x: centre.x + TouchControls.movementRadius * 0.4,
                               y: centre.y))
    run.controls.performNativeWarpGateAction(.useWarpGate, for: prompt)
    check(run.controls.consumeHapticEvents() == [.button(.circle)],
          "accepted Use Warp Gate emits one immediate Circle haptic")
    let combined = run.frame()
    check(combined.isLeftDeflected && combined.buttons == .circle,
          "the explicit prompt button coexists with ordinary gameplay movement")

    run.controls.performNativeWarpGateAction(.useWarpGate, for: prompt)
    run.controls.performNativeWarpGateAction(.useWarpGate, for: prompt)
    let newerPrompt = NativeWarpGateTouchSnapshot.circleUseAvailable(sequence: 42)
    run.controls.setWarpGateTouchSnapshot(newerPrompt)
    check(run.controls.touches.isEmpty && run.frame() == .neutral,
          "a sequence change cancels carried touch plus active and queued prompt pulses")
    run.controls.performNativeWarpGateAction(.useWarpGate, for: prompt)
    check(run.frame() == .neutral && run.controls.consumeHapticEvents().isEmpty,
          "an action closure from the prior sequence fails closed")

    run.controls.performNativeWarpGateAction(.useWarpGate, for: newerPrompt)
    run.controls.setNativeMenuMode(.pause)
    check(run.frame() == .neutral && run.controls.consumeHapticEvents().isEmpty,
          "leaving gameplay cancels an unfinished prompt action")
    run.controls.setNativeMenuMode(.gameplay)
    let listAtSameSequence = warpList(slot: 1, sequence: newerPrompt.sequence)
    run.controls.setWarpGateTouchSnapshot(listAtSameSequence)
    check(run.frame() == .neutral && run.controls.consumeHapticEvents().isEmpty,
          "a same-sequence semantic transition still cancels queued input and feedback")
    run.controls.performNativeWarpGateAction(.previous, for: newerPrompt)
    check(run.frame() == .neutral,
          "an action from a prior semantic snapshot is rejected even if sequence did not advance")
}

@MainActor
private func nativeWarpListActionsSwipesAndResetAreExact() {
    print("warp list emits exact isolated bytes, haptics, and horizontal swipes")
    var run = Runner()
    run.controls.setNativeMenuMode(.gameplay)
    let list = warpList(slot: 2, sequence: 50)
    run.controls.setWarpGateTouchSnapshot(list)
    for action in [NativeWarpGateTouchAction.previous, .next, .warp, .back] {
        run.controls.performNativeWarpGateAction(action, for: list)
    }
    check(run.controls.consumeHapticEvents() == [
        .button(.left), .button(.right), .button(.circle), .button(.triangle),
    ], "list actions emit one exact immediate haptic each")
    let frame = run.frame()
    check(frame.buttons == [.left, .right, .circle, .triangle]
          && !frame.isLeftDeflected && !frame.isRightDeflected,
          "list actions emit only Left, Right, Circle, and Triangle pad bytes")
    check(!frame.buttons.contains(.cross) && !frame.buttons.contains(.square),
          "list actions never leak menu Confirm/Cross or Back/Square")

    let nextList = warpList(slot: 3, sequence: 52)
    run.controls.setWarpGateTouchSnapshot(nextList)
    check(run.controls.performNativeWarpGateSwipe(
        translation: CGSize(width: -TouchControls.nativeWarpSwipeDistance, height: 2),
        for: nextList), "an unambiguous leftward list swipe selects Previous")
    check(run.controls.consumeHapticEvents() == [.button(.left)]
          && run.frame().buttons == .left,
          "leftward swipe emits exactly one Left pulse and haptic")

    let lastList = warpList(slot: 4, sequence: 54)
    run.controls.setWarpGateTouchSnapshot(lastList)
    check(run.controls.performNativeWarpGateSwipe(
        translation: CGSize(width: TouchControls.nativeWarpSwipeDistance, height: -2),
        for: lastList), "an unambiguous rightward list swipe selects Next")
    check(run.controls.consumeHapticEvents() == [.button(.right)]
          && run.frame().buttons == .right,
          "rightward swipe emits exactly one Right pulse and haptic")
    check(!run.controls.performNativeWarpGateSwipe(
        translation: CGSize(width: 2, height: TouchControls.nativeWarpSwipeDistance),
        for: lastList), "vertical list swipes remain inert without a source meaning")
    check(!run.controls.performNativeWarpGateSwipe(
        translation: CGSize(width: TouchControls.nativeWarpSwipeDistance,
                            height: TouchControls.nativeWarpSwipeDistance),
        for: lastList), "ambiguous diagonal list swipes remain inert")

    let movedList = warpList(slot: 4, moving: true, sequence: 56)
    run.controls.setWarpGateTouchSnapshot(movedList)
    check(!run.controls.performNativeWarpGateSwipe(
        translation: CGSize(width: TouchControls.nativeWarpSwipeDistance, height: 0),
        for: movedList), "selection-moving state rejects even a clear horizontal swipe")
    run.controls.performNativeWarpGateAction(.warp, for: movedList)
    run.controls.performNativeWarpGateAction(.back, for: movedList)
    check(run.controls.consumeHapticEvents() == [.button(.circle), .button(.triangle)]
          && run.frame().buttons == [.circle, .triangle],
          "selection-moving state retains exact Warp/Circle and Back/Triangle input")
    check(!run.controls.performNativeWarpGateSwipe(
        translation: CGSize(width: -TouchControls.nativeWarpSwipeDistance, height: 0),
        for: lastList), "a horizontal swipe from the prior sequence fails closed")

    run.controls.setWarpGateTouchSnapshot(list)
    run.controls.performNativeWarpGateAction(.back, for: list)
    run.controls.reset()
    check(run.frame() == .neutral && run.controls.consumeHapticEvents().isEmpty,
          "lifecycle reset clears warp pulses and touch-owned feedback")
}

@MainActor
private func nativeWarpCaptureAndSuppressionAreFailClosed() {
    print("warp capture and controller suppression follow the authoritative phase")
    let prompt = NativeWarpGateTouchSnapshot.circleUseAvailable(sequence: 60)
    let list = warpList(sequence: 62)
    let moving = warpList(moving: true, sequence: 64)
    let transitioning = NativeWarpGateTouchSnapshot.transitioning(sequence: 66)
    let malformedList = NativeWarpGateTouchSnapshot(
        valid: false, state: .destinationListActive, selectedSlot: 0,
        permittedMask: 1, selectionMoving: false, sequence: 68)
    check(!TouchControls.capturesWarpGateTouchInput(mode: .gameplay, snapshot: .invalid)
          && !TouchControls.capturesWarpGateTouchInput(
            mode: .gameplay, snapshot: .validUnavailable(sequence: 58))
          && !TouchControls.capturesWarpGateTouchInput(mode: .gameplay, snapshot: prompt),
          "invalid, valid unavailable, and Circle-use states begin as ordinary gameplay touch")
    check(TouchControls.capturesWarpGateTouchInput(mode: .gameplay, snapshot: list)
          && TouchControls.capturesWarpGateTouchInput(mode: .gameplay, snapshot: moving)
          && TouchControls.capturesWarpGateTouchInput(
            mode: .gameplay, snapshot: transitioning),
          "valid destination, selection-moving, and transition states capture gameplay touch")
    check(!TouchControls.capturesWarpGateTouchInput(
        mode: .gameplay, snapshot: malformedList),
          "a malformed native snapshot cannot suppress ordinary gameplay touch")
    check(!TouchControls.capturesWarpGateTouchInput(mode: .pause, snapshot: list),
          "warp capture cannot replace the active native-menu owner")

    check(TouchControls.warpGateTouchControlsAreVisible(
        mode: .gameplay, snapshot: prompt, isSuppressed: false)
          && TouchControls.warpGateTouchControlsAreVisible(
            mode: .gameplay, snapshot: list, isSuppressed: false),
          "prompt and settled list show their exact actions without suppression")
    check(!TouchControls.warpGateTouchControlsAreVisible(
        mode: .gameplay, snapshot: prompt, isSuppressed: true)
          && !TouchControls.warpGateTouchControlsAreVisible(
            mode: .gameplay, snapshot: list, isSuppressed: true),
          "physical-controller activity suppresses all warp chrome")
    check(TouchControls.warpGateTouchControlsAreVisible(
        mode: .gameplay, snapshot: moving, isSuppressed: false)
          && !TouchControls.warpGateTouchControlsAreVisible(
            mode: .gameplay, snapshot: transitioning, isSuppressed: false),
          "selection movement retains Warp and Back while transition presents no actions")
    check(!TouchControls.warpGateTouchControlsAreVisible(
        mode: .gameplay, snapshot: malformedList, isSuppressed: false),
          "a malformed list neither captures nor presents actions")

    var suppressed = Runner()
    suppressed.controls.setNativeMenuMode(.gameplay)
    suppressed.controls.setWarpGateTouchSnapshot(prompt)
    suppressed.controls.performNativeWarpGateAction(
        .useWarpGate, for: prompt, isSuppressed: true)
    check(suppressed.frame() == .neutral
          && suppressed.controls.consumeHapticEvents().isEmpty,
          "physical-controller suppression rejects a hidden prompt action and haptic")
    suppressed.controls.setWarpGateTouchSnapshot(list)
    check(!suppressed.controls.performNativeWarpGateSwipe(
        translation: CGSize(width: TouchControls.nativeWarpSwipeDistance, height: 0),
        for: list, isSuppressed: true),
          "physical-controller suppression rejects the hidden full-screen list gesture")

    var run = Runner()
    run.controls.setNativeMenuMode(.gameplay)
    run.controls.setWarpGateTouchSnapshot(list)
    let ignored = Finger()
    let centre = CGPoint(x: 180, y: 650)
    run.down(ignored, centre)
    run.move(ignored, CGPoint(x: centre.x + TouchControls.movementRadius, y: centre.y))
    run.beginPinch()
    run.pinch(scale: 1 + TouchControls.pinchScaleDelta, lookAroundState: .normal)
    check(run.frame() == .neutral,
          "captured list touch cannot leak gameplay movement, gesture, or pinch input")

    run.controls.setWarpGateTouchSnapshot(transitioning)
    run.controls.performNativeWarpGateAction(.back, for: transitioning)
    check(run.frame() == .neutral && run.controls.consumeHapticEvents().isEmpty,
          "transitioning captures input while rejecting every explicit action")

    run.controls.setWarpGateTouchSnapshot(.validUnavailable(sequence: 70))
    let resumed = Finger()
    run.down(resumed, centre)
    run.move(resumed, CGPoint(x: centre.x + TouchControls.movementRadius, y: centre.y))
    check(run.frame().isLeftDeflected,
          "a valid unavailable state resumes ordinary gameplay touch")
}

@MainActor
private func nativeWarpTransientInvalidReadsRetainNeutralCapture() {
    print("transient invalid warp publications retain neutral capture after destination ownership")
    var run = Runner()
    run.controls.setNativeMenuMode(.gameplay)
    check(!run.controls.capturesWarpGateTouchInput,
          "an invalid bridge read before any capture is ordinary unavailable")

    let list = warpList(slot: 2, sequence: 80)
    run.controls.setWarpGateTouchSnapshot(list)
    run.controls.performNativeWarpGateAction(.next, for: list)
    check(run.controls.capturesWarpGateTouchInput && run.frame().buttons == .right,
          "a valid destination publication establishes full-screen capture")

    run.controls.setWarpGateTouchSnapshot(.invalid)
    check(run.controls.warpGateTouchSnapshot == .invalid
          && run.controls.capturesWarpGateTouchInput
          && NativeWarpGateTouchAction.available(
            in: .gameplay, snapshot: run.controls.warpGateTouchSnapshot).isEmpty
          && run.frame() == .neutral,
          "an invalid read remains explicit while retaining neutral capture and no actions")

    let oddPrompt = NativeWarpGateTouchSnapshot.circleUseAvailable(sequence: 81)
    run.controls.setWarpGateTouchSnapshot(oddPrompt)
    run.controls.performNativeWarpGateAction(.useWarpGate, for: oddPrompt)
    check(run.controls.capturesWarpGateTouchInput && run.frame() == .neutral
          && run.controls.consumeHapticEvents().isEmpty,
          "an odd in-progress publication cannot release capture or emit an action")

    let malformedTransition = NativeWarpGateTouchSnapshot(
        valid: true, state: .transitioning, selectedSlot: -1,
        permittedMask: 0, selectionMoving: true, sequence: 82)
    run.controls.setWarpGateTouchSnapshot(malformedTransition)
    check(run.controls.capturesWarpGateTouchInput
          && NativeWarpGateTouchAction.available(
            in: .gameplay, snapshot: malformedTransition).isEmpty,
          "a malformed transition remains a neutral capture state")

    let prompt = NativeWarpGateTouchSnapshot.circleUseAvailable(sequence: 84)
    run.controls.setWarpGateTouchSnapshot(prompt)
    check(!run.controls.capturesWarpGateTouchInput
          && NativeWarpGateTouchAction.available(in: .gameplay, snapshot: prompt)
            == [.useWarpGate],
          "only a valid Circle-use publication releases capture to its exact action")

    run.controls.setWarpGateTouchSnapshot(.invalid)
    check(!run.controls.capturesWarpGateTouchInput,
          "invalid remains ordinary unavailable after a valid non-capturing publication")

    run.controls.setWarpGateTouchSnapshot(.transitioning(sequence: 86))
    run.controls.setWarpGateTouchSnapshot(.invalid)
    check(run.controls.capturesWarpGateTouchInput,
          "a valid transition also establishes capture across a transient invalid read")
    run.controls.setWarpGateTouchSnapshot(.validUnavailable(sequence: 88))
    check(!run.controls.capturesWarpGateTouchInput,
          "a valid unavailable publication explicitly releases retained capture")
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
        modernPinchZoomUsesAuthoritativeDirection()
        modernPinchZoomFailsClosedWithoutARequestedTransition()
        pinchZoomIsModernOnlyAndLifecycleSafe()
        styleSwitchClearsInterruptedInput()
        classicButtonsMapDirectly()
        classicHitTargetsLeaveArtworkAndBytesIntact()
        classicSticksAreSymmetricalAndAnalog()
        classicGeometryStaysSafeAndBalanced()
        classicHasNoTriggerOverlay()
        classicMultitouchReachesOneFrame()
        pausePresentationFollowsNativeMenuState()
        controllerSuppressionKeepsTouchRecovery()
        nativeMenuActionsAreTruthfullyGatedAndLabelled()
        nativeMenuActionsEmitOnlyExpectedInputBytes()
        nativeProgressListSwipeIsOneShotAndStateGated()
        nativeMenuTransitionPreventsGameplayLeakage()
        nativeMenuSuppressionCancellationAndResetAreSafe()
        nativeWarpActionsAreStructurallyGatedAndExact()
        nativeWarpDestinationLayoutAdaptsWithoutClipping()
        nativeWarpPromptCoexistsAndRejectsStaleActions()
        nativeWarpListActionsSwipesAndResetAreExact()
        nativeWarpCaptureAndSuppressionAreFailClosed()
        nativeWarpTransientInvalidReadsRetainNeutralCapture()

        print(failures == 0 ? "\nall checks passed" : "\n\(failures) checks FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
