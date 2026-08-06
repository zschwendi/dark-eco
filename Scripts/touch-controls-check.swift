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
    static let stats = CGRect(x: 720, y: 690, width: 102, height: 66)
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
        controls.setPillFrame(.stats, Self.stats)
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
        let pillHits = [layout.selectPillFrame, layout.statsPillFrame,
                        layout.startPillFrame].map {
            $0.insetBy(dx: -10, dy: -12)
        }
        check(pillHits.allSatisfy {
            let intersection = $0.intersection(layout.rightStickHitFrame)
            return intersection.isNull || intersection.width <= 0.001 || intersection.height <= 0.001
        }, "Modern layout \(index + 1) clears all three centre-pill hit targets")
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
    print("Start, Select, and Stats remain explicit controls")
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

    let stats = Finger()
    run.down(stats, CGPoint(x: Runner.stats.midX, y: Runner.stats.midY))
    let heldStats = run.frames(3)
    check(heldStats.allSatisfy { $0.buttons.contains(.L2) && $0.buttons.contains(.R2) },
          "Stats holds the exact L2+R2 controller chord")
    check(heldStats.allSatisfy {
        !$0.buttons.contains(.select) && !$0.buttons.contains(.triangle)
    }, "Stats does not alias Select or Triangle")
    run.up(stats)
    check(run.frames(TouchControls.holdFrames + TouchControls.releaseFrames + 2).last!
        .buttons.intersection([.L2, .R2]).isEmpty,
          "Stats releases both trigger bits after the finger lifts")
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
    print("touch haptics are discrete and reset-safe")
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

}

@MainActor
private func semanticZoomButtonIsExactAndFailClosed() {
    print("the semantic zoom button emits one authoritative Triangle toggle")
    for mode in [GOALPadLookAroundState.normal, .firstPerson] {
        var run = Runner()
        check(run.controls.performZoomToggle(lookAroundState: mode),
              "\(mode) accepts a zoom toggle")
        check(run.controls.consumeHapticEvents() == [.gesture(.triangle)],
              "\(mode) emits one zoom haptic")
        let frames = run.frames(TouchControls.holdFrames + TouchControls.releaseFrames + 2)
        check(frames.prefix(TouchControls.holdFrames).allSatisfy {
            $0.buttons.contains(.triangle)
        }, "\(mode) emits one complete Triangle pulse")
        check(frames.dropFirst(TouchControls.holdFrames).allSatisfy {
            !$0.buttons.contains(.triangle)
        }, "\(mode) ends with a deterministic release")
    }

    var unknown = Runner()
    check(!unknown.controls.performZoomToggle(lookAroundState: .unknown)
          && unknown.frame() == .neutral
          && unknown.controls.consumeHapticEvents().isEmpty,
          "unknown camera state cannot emit zoom input")

    var captured = Runner()
    captured.controls.setNativeMenuMode(.pause)
    check(!captured.controls.performZoomToggle(lookAroundState: .normal)
          && captured.frame() == .neutral
          && captured.controls.consumeHapticEvents().isEmpty,
          "a native-menu owner rejects gameplay zoom input")
}

@MainActor
private func modernChromeAddsZoomWithoutMovingAcceptedPills() {
    print("zoom keeps the accepted Stats and Start pill centres unchanged")
    let chrome = ModernTouchChromeLayout(size: Runner.screen)
    check(chrome.statsFrame == CGRect(x: 513, y: 762, width: 82, height: 42),
          "Stats retains the accepted left pill frame")
    check(chrome.startFrame == CGRect(x: 615, y: 762, width: 82, height: 42),
          "Start retains the accepted right pill frame")
    check(chrome.centeredSessionFrame
          == CGRect(x: 564, y: 762, width: 82, height: 42)
          && chrome.centeredSessionFrame.midX == Runner.screen.width / 2,
          "a captured start or pause menu centers its sole session pill")
    check(ModernTouchChromeLayout.zoomGap == ModernTouchChromeLayout.pillSpacing,
          "Zoom-to-Stats and Stats-to-Start use the same spacing")
    check(chrome.zoomFrame == CGRect(x: 451, y: 762, width: 42, height: 42),
          "zoom is an independent 42-point circle immediately left of Stats")
    check(chrome.zoomFrame.maxX + ModernTouchChromeLayout.zoomGap
          == chrome.statsFrame.minX
          && chrome.statsFrame.minX - chrome.zoomFrame.maxX
          == chrome.startFrame.minX - chrome.statsFrame.maxX
          && chrome.zoomFrame.midY == chrome.statsFrame.midY,
          "zoom is equally gap-separated and vertically centered without offsetting the pills")
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
        .select: CGRect(x: 123, y: 18.5, width: 34, height: 15),
        .stats: CGRect(x: 123, y: 62.5, width: 34, height: 15),
        .start: CGRect(x: 123, y: 106.5, width: 34, height: 15),
    ]
    check(layout.buttonFrames == expectedVisualFrames,
          "the compact Classic artwork fits all three centre pills deterministically")

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
private func classicHasOnlyTheStatsTriggerChord() {
    print("Classic exposes one explicit Stats chord without separate trigger controls")
    let layout = ClassicTouchLayout(size: Runner.screen,
                                    safeAreaInsets: Runner.safeAreaInsets)
    check(Set(layout.buttonFrames.keys) == Set(ClassicTouchLayout.buttons),
          "the overlay contains exactly the declared Classic controls")
    check(ClassicTouchLayout.buttons.filter { $0 != .stats }.allSatisfy {
        !$0.bit.contains(.L2) && !$0.bit.contains(.R2)
    } && TouchButton.stats.bit == [.L2, .R2],
          "only Stats maps to the exact L2+R2 chord")
    check(ClassicTouchLayout.usesPillArtwork(for: .stats)
          && !ClassicTouchLayout.usesPillArtwork(for: .triangle),
          "Classic Stats uses pill artwork rather than circular face-button geometry")
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
private func customizedModernLayoutPinsRemapsAndPreservesSkipSafety() {
    print("customized Modern controls pin safely and remap only existing outputs")
    var customization = TouchLayoutCustomization.standard
    customization.setPosition(NormalizedTouchPosition(x: 0.2, y: 0.72),
                              for: .modernMovement)
    customization.setPosition(NormalizedTouchPosition(x: 0.25, y: 0.38),
                              for: .modernActions)
    customization.setAction(.cameraStick, for: .modernMovement)
    customization.setGestureAction(.square, for: .up)
    customization.setAction(.start, for: .modernSelect)
    customization.setSizePercent(130, for: .modernMovement)
    customization.setOpacityPercent(45, for: .modernCamera)

    var run = Runner(style: .modern)
    run.controls.setLayoutCustomization(customization)
    let layout = ModernTouchLayout(size: Runner.screen,
                                   safeAreaInsets: Runner.safeAreaInsets,
                                   customization: customization)
    check(layout.movementHitFrame != nil && layout.actionGestureHitFrame != nil,
          "dragged dynamic controls become explicit pinned safe-area targets")
    check(layout.safeBounds.contains(layout.movementArtworkFrame)
          && layout.safeBounds.contains(layout.actionGestureFrame),
          "pinned Modern artwork remains inside the safe screen")

    let outside = Finger()
    run.down(outside, CGPoint(x: 40, y: Runner.screen.height - 80))
    check(run.frame() == .neutral,
          "pinning movement stops unrelated left-side touches from stealing the stick")
    run.up(outside)

    let movement = Finger()
    let movementCentre = CGPoint(x: layout.movementArtworkFrame.midX,
                                 y: layout.movementArtworkFrame.midY)
    run.down(movement, movementCentre)
    run.move(movement, CGPoint(x: movementCentre.x
                               + TouchControls.movementRadius * 1.3,
                               y: movementCentre.y))
    var state = run.frame()
    check(!state.isLeftDeflected && state.isRightDeflected,
          "the pinned movement source emits the remapped camera stick vector")
    run.up(movement)

    let gesture = Finger()
    let gestureCentre = CGPoint(x: layout.actionGestureFrame.midX,
                                y: layout.actionGestureFrame.midY)
    run.down(gesture, gestureCentre)
    run.move(gesture, CGPoint(x: gestureCentre.x,
                              y: gestureCentre.y - TouchControls.swipeDistance - 4))
    state = run.frame()
    check(state.buttons.contains(.square) && !state.buttons.contains(.cross),
          "the pinned up swipe works across halves and emits its swapped safe face action")
    run.up(gesture)

    let combo = Finger()
    run.down(combo, gestureCentre)
    let crouchPeak = CGPoint(x: gestureCentre.x,
                             y: gestureCentre.y + TouchControls.swipeDistance + 8)
    run.move(combo, crouchPeak)
    run.move(combo, CGPoint(x: gestureCentre.x - TouchControls.swipeDistance - 8,
                            y: crouchPeak.y))
    state = run.frame()
    check(state.buttons.contains(.L1) && state.buttons.contains(.square),
          "Crouch stays on Down and its left combo stays Square after face-swipe remapping")
    run.move(combo, CGPoint(x: gestureCentre.x - TouchControls.swipeDistance - 8,
                            y: crouchPeak.y - TouchControls.rollJumpDistance - 8))
    check(run.frame().buttons.contains(.cross),
          "the crouch reversal combo stays Cross after face-swipe remapping")
    run.up(combo)
    check(TouchControls.gestureArtworkIsLit(button: .square, swiped: nil,
                                            jumpTriggered: false, punchTriggered: true)
          && !TouchControls.gestureArtworkIsLit(button: .cross, swiped: nil,
                                                jumpTriggered: false, punchTriggered: true)
          && TouchControls.gestureArtworkIsLit(button: .cross, swiped: nil,
                                               jumpTriggered: true, punchTriggered: false),
          "combo artwork lights the remapped Square or Cross chip by output action")

    let selectSource = Finger()
    run.down(selectSource, CGPoint(x: Runner.select.midX, y: Runner.select.midY))
    check(run.frame().buttons.contains(.start),
          "the Select source can emit the swapped Pause action")
    run.up(selectSource)

    let skipSnapshot = NativeCutsceneSkipTouchSnapshot.triangleQueryAvailable(sequence: 40)
    run.controls.setNativeMenuMode(.gameplay)
    run.controls.setCutsceneSkipTouchSnapshot(skipSnapshot)
    let remappedSelectSource = Finger()
    run.down(remappedSelectSource, CGPoint(x: Runner.start.midX, y: Runner.start.midY))
    check(run.frame() == .neutral,
          "the remapped Select source still waits for a validated SKIP release")
    run.up(remappedSelectSource)
    check(run.frames(TouchControls.holdFrames).allSatisfy { $0.buttons.contains(.triangle) },
          "SKIP safety follows the Select action without exposing an early or unsafe button")
}

@MainActor
private func customizedClassicLayoutClampsRemapsAndKeepsMinimumTargets() {
    print("customized Classic controls clamp, resize, and remap active controls only")
    var customization = TouchLayoutCustomization.standard
    customization.setPosition(NormalizedTouchPosition(x: 1, y: 0), for: .classicCross)
    customization.setSizePercent(65, for: .classicCross)
    customization.setOpacityPercent(30, for: .classicCross)
    customization.setAction(.triangle, for: .classicCross)
    customization.setAction(.cameraStick, for: .classicMovement)

    let layout = ClassicTouchLayout(size: CGSize(width: 393, height: 852),
                                    safeAreaInsets: TouchSafeAreaInsets(
                                        top: 59, leading: 0, bottom: 34, trailing: 0),
                                    customization: customization)
    let crossFrame = layout.frame(for: .cross)!
    let crossHit = layout.hitFrame(for: .cross)!
    check(layout.safeBounds.contains(crossFrame) && layout.safeBounds.contains(crossHit),
          "an edge-pinned resized Classic control remains inside its safe bounds")
    check(crossHit.width >= 44 && crossHit.height >= 44,
          "a visually smaller Classic control keeps a 44-point hit target")
    check(customization.opacity(for: .classicCross) == 0.3,
          "Classic opacity is independent from its hit target and action")

    var run = Runner(style: .classic, size: CGSize(width: 393, height: 852),
                     safeAreaInsets: TouchSafeAreaInsets(
                        top: 59, leading: 0, bottom: 34, trailing: 0),
                     rightStickFrame: .zero)
    run.controls.setLayoutCustomization(customization)
    let cross = Finger()
    run.down(cross, CGPoint(x: crossFrame.midX, y: crossFrame.midY))
    check(run.frame().buttons == .triangle,
          "the customized Cross source emits only its swapped Triangle action")
    run.up(cross)

    let movement = Finger()
    let movementCentre = CGPoint(x: layout.leftStickFrame.midX,
                                 y: layout.leftStickFrame.midY)
    run.down(movement, movementCentre)
    run.move(movement, CGPoint(x: movementCentre.x + layout.leftStickRadius,
                               y: movementCentre.y))
    let state = run.frame()
    check(!state.isLeftDeflected && state.isRightDeflected,
          "a Classic whole-stick remap reaches the camera axes without splitting them")
}

@MainActor
private func resizedClassicSticksUseTheirMinimumHitFrames() {
    print("resized Classic sticks retain exact axes across their 44-point hit targets")
    let size = CGSize(width: 240, height: 320)
    var customization = TouchLayoutCustomization.standard
    customization.setPosition(NormalizedTouchPosition(x: 0.25, y: 0),
                              for: .classicMovement)
    customization.setPosition(NormalizedTouchPosition(x: 0.75, y: 0),
                              for: .classicCamera)
    customization.setSizePercent(65, for: .classicMovement)
    customization.setSizePercent(65, for: .classicCamera)
    for control in TouchLayoutControlID.controls(for: .classic)
    where control != .classicMovement && control != .classicCamera {
        customization.setPosition(NormalizedTouchPosition(x: 0.5, y: 1), for: control)
    }
    let layout = ClassicTouchLayout(size: size, customization: customization)
    let leftVisual = layout.leftStickFrame
    let rightVisual = layout.rightStickFrame
    let leftHit = layout.hitFrame(for: .classicMovement)!
    let rightHit = layout.hitFrame(for: .classicCamera)!
    check(leftVisual.width < 44 && rightVisual.width < 44
          && leftHit.width == 44 && rightHit.width == 44,
          "both reduced stick visuals retain computed 44-point hit frames")

    let leftPoint = CGPoint(x: (leftVisual.maxX + leftHit.maxX) / 2,
                            y: leftVisual.midY)
    check(!leftVisual.contains(leftPoint) && leftHit.contains(leftPoint),
          "the movement test point is outside its visual but inside its hit frame")
    var movementRun = Runner(style: .classic, size: size, rightStickFrame: .zero)
    movementRun.controls.setLayoutCustomization(customization)
    let movement = Finger()
    movementRun.down(movement, leftPoint)
    let movementState = movementRun.frame()
    check(movementState.leftX == 254 && movementState.leftY == neutral
          && movementState.rightX == neutral && movementState.rightY == neutral,
          "the movement minimum target emits the exact full-right left-stick axes")

    let rightPoint = CGPoint(x: (rightVisual.maxX + rightHit.maxX) / 2,
                             y: rightVisual.midY)
    check(!rightVisual.contains(rightPoint) && rightHit.contains(rightPoint),
          "the camera test point is outside its visual but inside its hit frame")
    var cameraRun = Runner(style: .classic, size: size, rightStickFrame: .zero)
    cameraRun.controls.setLayoutCustomization(customization)
    let camera = Finger()
    cameraRun.down(camera, rightPoint)
    let cameraState = cameraRun.frame()
    check(cameraState.rightX == 254 && cameraState.rightY == neutral
          && cameraState.leftX == neutral && cameraState.leftY == neutral,
          "the camera minimum target emits the exact full-right right-stick axes")
}

@MainActor
private func overlappingControlsFollowVisualStackOrder() {
    print("overlapping controls use one explicit hit order matching their visual stack")
    let centre = NormalizedTouchPosition(x: 0.5, y: 0.5)
    check(ModernTouchLayout.visualOrder == TouchLayoutControlID.visualOrder(for: .modern)
          && ClassicTouchLayout.visualOrder == TouchLayoutControlID.visualOrder(for: .classic),
          "gameplay layouts share the same visual order used by the editor preview")

    var allModern = TouchLayoutCustomization.standard
    for control in TouchLayoutControlID.controls(for: .modern) {
        allModern.setPosition(centre, for: control)
    }
    var cameraFirst = Runner(style: .modern)
    cameraFirst.controls.setLayoutCustomization(allModern)
    let cameraTouch = Finger()
    let screenCentre = CGPoint(x: Runner.screen.width / 2, y: Runner.screen.height / 2)
    cameraFirst.down(cameraTouch, screenCentre)
    cameraFirst.move(cameraTouch, CGPoint(x: screenCentre.x + TouchControls.rightStickRadius,
                                          y: screenCentre.y))
    let cameraState = cameraFirst.frame()
    check(cameraState.rightX == 254 && cameraState.leftX == neutral
          && cameraState.buttons.isEmpty,
          "Modern camera wins over overlapping pills, actions, and movement")

    var pillsOverActions = TouchLayoutCustomization.standard
    let stackedModernControls: [TouchLayoutControlID] = [
        .modernMovement, .modernActions, .modernSelect, .modernStats, .modernStart,
    ]
    for control in stackedModernControls {
        pillsOverActions.setPosition(centre, for: control)
    }
    var topPill = Runner(style: .modern)
    topPill.controls.setLayoutCustomization(pillsOverActions)
    let pillTouch = Finger()
    topPill.down(pillTouch, screenCentre)
    check(topPill.frame().buttons == .start,
          "Modern Start wins the explicit reverse render order of overlapping pills")

    var actionsOverMovement = TouchLayoutCustomization.standard
    actionsOverMovement.setPosition(centre, for: .modernMovement)
    actionsOverMovement.setPosition(centre, for: .modernActions)
    var topAction = Runner(style: .modern)
    topAction.controls.setLayoutCustomization(actionsOverMovement)
    let actionTouch = Finger()
    topAction.down(actionTouch, screenCentre)
    topAction.move(actionTouch, CGPoint(x: screenCentre.x,
                                        y: screenCentre.y - TouchControls.swipeDistance - 4))
    check(topAction.frame().buttons == .cross,
          "Modern actions win over overlapping movement")

    var allClassic = TouchLayoutCustomization.standard
    for control in TouchLayoutControlID.controls(for: .classic) {
        allClassic.setPosition(centre, for: control)
    }
    var topClassicButton = Runner(style: .classic)
    topClassicButton.controls.setLayoutCustomization(allClassic)
    let classicButtonTouch = Finger()
    topClassicButton.down(classicButtonTouch, screenCentre)
    check(topClassicButton.frame().buttons == .cross,
          "Classic Cross wins the reverse render order over buttons and both sticks")

    var overlappingSticks = TouchLayoutCustomization.standard
    overlappingSticks.setPosition(centre, for: .classicMovement)
    overlappingSticks.setPosition(centre, for: .classicCamera)
    var topClassicStick = Runner(style: .classic)
    topClassicStick.controls.setLayoutCustomization(overlappingSticks)
    let overlappingStickLayout = ClassicTouchLayout(size: Runner.screen,
                                                     safeAreaInsets: Runner.safeAreaInsets,
                                                     customization: overlappingSticks)
    let classicStickTouch = Finger()
    topClassicStick.down(classicStickTouch, screenCentre)
    topClassicStick.move(classicStickTouch,
                         CGPoint(x: screenCentre.x + overlappingStickLayout.rightStickRadius,
                                 y: screenCentre.y))
    let classicStickState = topClassicStick.frame()
    check(classicStickState.rightX == 254 && classicStickState.leftX == neutral,
          "Classic camera stick wins over overlapping movement like the Z render order")
}

@MainActor
private func liveLayoutChangesCancelOwnedInput() {
    print("a live layout change cancels all input owned by the previous geometry")
    var run = Runner(style: .modern)
    let movement = Finger()
    let crouch = Finger()
    let start = Finger()
    let movementCentre = CGPoint(x: 180, y: 650)
    let gestureCentre = CGPoint(x: 900, y: 360)
    run.down(movement, movementCentre)
    run.move(movement, CGPoint(x: movementCentre.x + TouchControls.movementRadius,
                               y: movementCentre.y))
    run.down(crouch, gestureCentre)
    run.move(crouch, CGPoint(x: gestureCentre.x,
                             y: gestureCentre.y + TouchControls.swipeDistance + 4))
    run.down(start, CGPoint(x: Runner.start.midX, y: Runner.start.midY))
    let ownedState = run.frame()
    check(ownedState.leftX == 254 && ownedState.buttons.contains(.L1)
          && ownedState.buttons.contains(.start),
          "the old layout owns simultaneous stick, crouch, and pill state before replacement")

    var replacement = TouchLayoutCustomization.standard
    replacement.setPosition(NormalizedTouchPosition(x: 0.3, y: 0.3),
                            for: .modernMovement)
    run.controls.setLayoutCustomization(replacement)
    check(run.controls.touches.isEmpty && !run.controls.isEngaged
          && run.controls.consumeHapticEvents().isEmpty
          && run.frames(TouchControls.holdFrames + TouchControls.releaseFrames).allSatisfy {
              $0 == .neutral
          }, "applying live geometry cancels touches, pulses, haptics, and carried axes")

    run.move(movement, CGPoint(x: 400, y: 400))
    run.up(crouch)
    run.up(start)
    check(run.frame() == .neutral,
          "late events from the old geometry cannot revive cancelled input")

    let layout = ModernTouchLayout(size: Runner.screen,
                                   safeAreaInsets: Runner.safeAreaInsets,
                                   customization: replacement)
    let newMovement = Finger()
    let newCentre = CGPoint(x: layout.movementArtworkFrame.midX,
                            y: layout.movementArtworkFrame.midY)
    run.down(newMovement, newCentre)
    run.move(newMovement, CGPoint(x: newCentre.x + TouchControls.movementRadius,
                                  y: newCentre.y))
    check(run.frame().leftX == 254,
          "a new touch immediately uses the replacement layout")
}

@MainActor
private func cutsceneSkipIsContextualExactAndLifecycleSafe() {
    print("SKIP is a validated release-edge Triangle action with stale-work cancellation")
    let available = NativeCutsceneSkipTouchSnapshot.triangleQueryAvailable(sequence: 10)
    let unavailable = NativeCutsceneSkipTouchSnapshot.validUnavailable(sequence: 12)
    let odd = NativeCutsceneSkipTouchSnapshot.triangleQueryAvailable(sequence: 11)

    check(TouchControls.cutsceneSkipIsAvailable(in: .gameplay, snapshot: available),
          "a valid even Triangle-query publication enables SKIP in gameplay")
    check(!TouchControls.cutsceneSkipIsAvailable(in: .pause, snapshot: available)
          && !TouchControls.cutsceneSkipIsAvailable(in: .gameplay, snapshot: unavailable)
          && !TouchControls.cutsceneSkipIsAvailable(in: .gameplay, snapshot: odd)
          && !TouchControls.cutsceneSkipIsAvailable(in: .gameplay, snapshot: .invalid),
          "wrong mode, unavailable, odd, and invalid publications fail closed")
    check(TouchControls.artworkLabel(for: .stats, sessionAction: .pause,
                                     cutsceneSkipAvailable: true) == "SKIP"
          && TouchControls.artworkLabel(for: .stats, sessionAction: .pause,
                                        cutsceneSkipAvailable: false) == "STATS",
          "the Stats artwork changes to SKIP only for validated availability")

    var accepted = Runner()
    accepted.controls.setNativeMenuMode(.gameplay)
    accepted.controls.setCutsceneSkipTouchSnapshot(available)
    let acceptedFinger = Finger()
    accepted.down(acceptedFinger, CGPoint(x: Runner.stats.midX, y: Runner.stats.midY))
    check(accepted.controls.isPillDown(.stats) && accepted.frame() == .neutral
          && accepted.controls.consumeHapticEvents().isEmpty,
          "touch-down owns SKIP without sending an early pad edge")
    accepted.up(acceptedFinger)
    check(accepted.controls.consumeHapticEvents() == [.button(.triangle)],
          "a completed current SKIP tap emits one Triangle haptic")
    let acceptedFrames = accepted.frames(TouchControls.holdFrames
                                          + TouchControls.releaseFrames + 2)
    check(acceptedFrames.prefix(TouchControls.holdFrames).allSatisfy {
        $0.buttons == .triangle
    } && acceptedFrames.dropFirst(TouchControls.holdFrames).allSatisfy {
        !$0.buttons.contains(.triangle)
    }, "a completed current SKIP tap emits one isolated Triangle pulse")

    var ordinaryStats = Runner()
    ordinaryStats.controls.setNativeMenuMode(.gameplay)
    ordinaryStats.controls.setCutsceneSkipTouchSnapshot(unavailable)
    let statsFinger = Finger()
    ordinaryStats.down(statsFinger, CGPoint(x: Runner.stats.midX, y: Runner.stats.midY))
    check(ordinaryStats.frame().buttons == [.L2, .R2]
          && ordinaryStats.controls.consumeHapticEvents() == [.button(.stats)],
          "Stats keeps its ordinary trigger chord while SKIP is unavailable")

    var changedSequence = Runner()
    changedSequence.controls.setNativeMenuMode(.gameplay)
    changedSequence.controls.setCutsceneSkipTouchSnapshot(available)
    let sequenceFinger = Finger()
    changedSequence.down(sequenceFinger, CGPoint(x: Runner.stats.midX,
                                                  y: Runner.stats.midY))
    changedSequence.controls.setCutsceneSkipTouchSnapshot(
        .triangleQueryAvailable(sequence: 14))
    changedSequence.up(sequenceFinger)
    check(changedSequence.frames(TouchControls.holdFrames + 2).allSatisfy { $0 == .neutral }
          && changedSequence.controls.consumeHapticEvents().isEmpty,
          "an owner-sequence change cancels a pending SKIP tap")

    var stale = Runner()
    stale.controls.setNativeMenuMode(.gameplay)
    stale.controls.setCutsceneSkipTouchSnapshot(available)
    let staleFinger = Finger()
    stale.down(staleFinger, CGPoint(x: Runner.stats.midX, y: Runner.stats.midY))
    stale.controls.setCutsceneSkipTouchSnapshot(.invalid)
    stale.up(staleFinger)
    check(stale.frames(TouchControls.holdFrames + 2).allSatisfy { $0 == .neutral }
          && stale.controls.consumeHapticEvents().isEmpty,
          "a stale native read cancels a pending SKIP tap")

    var changedMode = Runner()
    changedMode.controls.setNativeMenuMode(.gameplay)
    changedMode.controls.setCutsceneSkipTouchSnapshot(available)
    let modeFinger = Finger()
    changedMode.down(modeFinger, CGPoint(x: Runner.stats.midX, y: Runner.stats.midY))
    changedMode.controls.setNativeMenuMode(.pause)
    changedMode.up(modeFinger)
    check(changedMode.frames(TouchControls.holdFrames + 2).allSatisfy { $0 == .neutral }
          && changedMode.controls.consumeHapticEvents().isEmpty,
          "leaving gameplay cancels a pending SKIP tap")
}

@MainActor
private func pausePresentationFollowsNativeMenuState() {
    print("native menu drives Pause/Resume artwork and visibility")
    check(TouchControls.artworkLabel(for: .start, sessionAction: .pause) == "PAUSE",
          "gameplay Start artwork says PAUSE")
    check(TouchControls.artworkLabel(for: .start, sessionAction: .resume) == "RESUME",
          "native-menu Start artwork says RESUME")
    check(TouchControls.artworkLabel(for: .start, sessionAction: .start) == "START",
          "title-prompt Start artwork says START")
    check(TouchControls.artworkLabel(for: .start, sessionAction: nil) == "START",
          "unknown session state falls back to the physical Start label")
    check(TouchControls.artworkLabel(for: .stats, sessionAction: .pause) == "STATS",
          "Stats keeps its ordinary label outside a skippable cutscene")

    check(TouchControls.artworkIsVisible(isEngaged: false, isSuppressed: false,
                                         hasTouches: false, isNativeMenuOpen: true),
          "the native menu keeps idle fallback artwork visible")
    check(!TouchControls.artworkIsVisible(isEngaged: false, isSuppressed: true,
                                          hasTouches: false, isNativeMenuOpen: true),
          "controller suppression hides idle native-menu artwork")
    check(TouchControls.artworkIsVisible(isEngaged: false, isSuppressed: true,
                                         hasTouches: true, isNativeMenuOpen: true),
          "a live touch restores native-menu artwork under suppression")
    check(!TouchControls.artworkIsVisible(isEngaged: false, isSuppressed: true,
                                          hasTouches: false, isNativeMenuOpen: false,
                                          isAwaitingTitleStart: true),
          "controller suppression hides the exact title Start artwork")
    check(TouchControls.artworkIsVisible(isEngaged: false, isSuppressed: true,
                                         hasTouches: true, isNativeMenuOpen: false,
                                         isAwaitingTitleStart: true),
          "a live title-screen touch restores the Start artwork")

    var run = Runner()
    let finger = Finger()
    let centre = CGPoint(x: Runner.start.midX, y: Runner.start.midY)
    run.down(finger, centre)
    check(run.frame().buttons.contains(.start),
          "Pause/Resume presentation preserves the Start input bit")
}

@MainActor
private func semanticTitleStartBypassesArtworkGeometryAndSurvivesCadence() {
    print("title Start uses its semantic action instead of cached artwork geometry")
    let controls = TouchControls(style: .modern)
    controls.setNativeMenuState(.gameplay, progress: .unavailable,
                                titleStartState: .awaiting)

    // Deliberately do not register a Start pill frame. The title target is a real SwiftUI Button
    // and must reach the ordinary pad pulse without consulting pillFrames.
    controls.performNativeMenuAction(.start)
    check(controls.consumeHapticEvents() == [.button(.start)],
          "the semantic title action owns one immediate Start feedback event")
    check(controls.frameState().buttons.contains(.start),
          "the next engine frame receives the title Start edge")

    controls.setNativeMenuState(.gameplay, progress: .unavailable,
                                titleStartState: .notAwaiting)
    let remainingHold = (0..<(TouchControls.holdFrames - 1)).map { _ in
        controls.frameState()
    }
    check(remainingHold.allSatisfy { $0.buttons.contains(.start) },
          "the Start pulse survives the title-state transition for its full hold cadence")
    check((0..<TouchControls.releaseFrames).map { _ in controls.frameState() }
        .allSatisfy { !$0.buttons.contains(.start) },
          "the title Start cadence ends with a deterministic release")
}

private func sessionControlStateMatrixIsExactAndFailClosed() {
    print("app-owned Start, Pause, and Resume follow exact native state")
    check(NativeSessionControlPresentation.reduce(
        mode: .gameplay, titleStartState: .notAwaiting, progress: .unavailable,
        runReadiness: .preRun)
          == NativeSessionControlPresentation(action: .start, isEnabled: false),
          "boot and pre-run gameplay say Start without inventing an active save")
    check(NativeSessionControlPresentation.reduce(
        mode: .gameplay, titleStartState: .titleSequence, progress: .unavailable,
        runReadiness: .titlePrompt)
          == NativeSessionControlPresentation(action: .start, isEnabled: false),
          "the authored title animation cannot be mislabeled active gameplay")
    check(NativeSessionControlPresentation.reduce(
        mode: .gameplay, titleStartState: .awaiting, progress: .unavailable,
        runReadiness: .preRun)
          == NativeSessionControlPresentation(action: .start, isEnabled: true),
          "the exact titlePrompt state presents Start")
    check(NativeSessionControlPresentation.reduce(
        mode: .gameplay, titleStartState: .notAwaiting, progress: .unavailable,
        runReadiness: .active)
          == NativeSessionControlPresentation(action: .pause, isEnabled: true),
          "active gameplay presents Pause")
    check(NativeSessionControlPresentation.reduce(
        mode: .pause, titleStartState: .unknown, progress: .unavailable)
          == NativeSessionControlPresentation(action: .resume, isEnabled: true),
          "bare native pause presents Resume")

    let gameplayProgress = progressSnapshot(screen: 3, startingScreen: 0,
                                            canExitWithStart: false, canGoBack: true)
    check(NativeSessionControlPresentation.reduce(
        mode: .progress, titleStartState: .unknown, progress: gameplayProgress,
        runReadiness: .active)
          == NativeSessionControlPresentation(action: .resume, isEnabled: false),
          "gameplay-origin progress keeps Resume visible while native Start is transiently disabled")

    let titleProgress = progressSnapshot(screen: 28, startingScreen: 27,
                                         canExitWithStart: true, canGoBack: true)
    check(NativeSessionControlPresentation.reduce(
        mode: .progress, titleStartState: .unknown, progress: titleProgress,
        runReadiness: .titleMenu)
          == NativeSessionControlPresentation(action: .start, isEnabled: true),
          "title-origin progress uses the physical Start label for Back/exit")

    let titleWait = GameplayRunReadiness.advance(
        .active, mode: .gameplay, titleStartState: .awaiting, progress: .unavailable)
    let titleMenu = GameplayRunReadiness.advance(
        titleWait, mode: .progress, titleStartState: .unknown, progress: titleProgress)
    let activeRun = GameplayRunReadiness.advance(
        titleMenu, mode: .gameplay, titleStartState: .notAwaiting, progress: .unavailable)
    check(titleWait == .titlePrompt && titleMenu == .titleMenu && activeRun == .active,
          "title wait, title menu, and resumed gameplay form the exact run-readiness sequence")

    let snapshotlessTitleMenu = GameplayRunReadiness.advance(
        titleWait, mode: .progress, titleStartState: .unknown, progress: .unavailable)
    let snapshotlessActiveRun = GameplayRunReadiness.advance(
        snapshotlessTitleMenu, mode: .gameplay, titleStartState: .notAwaiting,
        progress: .unavailable)
    check(snapshotlessTitleMenu == .titleMenu && snapshotlessActiveRun == .active,
          "the observed title prompt and progress owner cannot strand loaded gameplay pre-run")
    let exactTitleSequence = GameplayRunReadiness.advance(
        .preRun, mode: .gameplay, titleStartState: .titleSequence,
        progress: .unavailable)
    let directActiveRun = GameplayRunReadiness.advance(
        exactTitleSequence, mode: .gameplay, titleStartState: .notAwaiting,
        progress: .unavailable)
    check(exactTitleSequence == .titlePrompt && directActiveRun == .active,
          "leaving the exact title target sequence activates gameplay without a progress snapshot")
    check(GameplayRunReadiness.advance(
        .preRun, mode: .gameplay, titleStartState: .notAwaiting,
        progress: .unavailable) == .active,
          "an already-loaded exact non-title gameplay target cannot remain stranded pre-run")
    check(GameplayRunReadiness.advance(
        .active, mode: .gameplay, titleStartState: .titleSequence,
        progress: .unavailable) == .titlePrompt,
          "returning to the exact title sequence suppresses active gameplay chrome")
    check(GameplayRunReadiness.advance(
        .active, mode: .gameplay, titleStartState: .unknown,
        progress: .unavailable) == .active,
          "a transient unknown read preserves the last proven presentation without flicker")
    check(GameplayRunReadiness.advance(
        .preRun, mode: .progress, titleStartState: .unknown,
        progress: .unavailable) == .preRun,
          "an unproven progress owner cannot invent an active run before the title prompt")

    let pcOnly = progressSnapshot(screen: 35, startingScreen: 0,
                                  canExitWithStart: true, canGoBack: true)
    check(NativeMenuTouchAction.available(in: .progress, progress: pcOnly)
          == [.back],
          "an eligible PC-only screen keeps Back while session Resume stays in the bottom pill")

    for statsScreen in 1...2 {
        let stats = progressSnapshot(screen: statsScreen, startingScreen: statsScreen,
                                     canExitWithStart: true, canGoBack: true)
        check(NativeMenuTouchAction.available(in: .progress, progress: stats)
              == [.up, .down, .precursorOrbs, .fuelCells, .scoutFlies, .settings],
              "stats screen \(statsScreen) has level navigation plus its face-button actions")
    }

    let validBack = progressSnapshot(screen: 3, option: 2, startingScreen: 0,
                                     canExitWithStart: true, canGoBack: true)
    check(NativeMenuTouchAction.available(in: .progress, progress: validBack)
          == [.up, .down, .back, .confirm],
          "exact can-go-back adds Back without relabelling another action")
    check(NativeMenuTouchAction.available(in: .progress, progress: validBack)
          == [.up, .down, .back, .confirm],
          "physical-input activity cannot reduce the proven progress touch action set")

    let fileBack = progressSnapshot(screen: 16, option: 4, startingScreen: 16,
                                    canExitWithStart: false, canGoBack: true)
    check(NativeMenuTouchAction.available(in: .progress, progress: fileBack)
          == [.up, .down, .back, .confirm],
          "file lists retain their source-proven Back beside the separate session pill")

    let selected = progressSnapshot(screen: 3, option: 2, selected: true,
                                    startingScreen: 0, canExitWithStart: true,
                                    canGoBack: true)
    check(NativeMenuTouchAction.available(in: .progress, progress: selected)
          == [.left, .right, .cancel, .confirm],
          "a selected option preserves Cancel and does not invent Back")

    check(NativeSessionControlPresentation.reduce(
        mode: .gameplay, titleStartState: .unknown, progress: .unavailable,
        runReadiness: .preRun)
          == NativeSessionControlPresentation(action: .start, isEnabled: false)
          && NativeSessionControlPresentation.reduce(
            mode: .progress, titleStartState: .unknown,
            progress: progressSnapshot(screen: 35)) == nil
          && NativeSessionControlPresentation.reduce(
            mode: .unknown, titleStartState: .awaiting, progress: titleProgress) == nil,
          "unknown title stays disabled Start while invalid progress and master mode fail closed")
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
          "a failed recovery callback does not claim that ownership changed")
}

@MainActor
private func build128ChromeStateMatrixAndRightStickRecovery() {
    print("Build 128 keeps gameplay chrome persistent and idles only the R artwork")
    check(TouchControls.rightStickFadeOutDelay == 3,
          "the R-stick artwork uses the exact three-second idle delay")

    let persistentCases: [(GOALPadGameMode, GameplayRunReadiness, Bool, Bool, Bool, Bool)] = [
        (.gameplay, .active, false, false, false, true),
        (.gameplay, .preRun, false, false, false, false),
        (.gameplay, .active, true, false, false, false),
        (.pause, .active, false, false, false, false),
        (.progress, .active, false, false, false, false),
        (.gameplay, .active, false, true, false, false),
        (.gameplay, .active, false, true, true, true),
    ]
    for (mode, readiness, awaiting, suppressed, hasTouches, expected) in persistentCases {
        check(TouchControls.persistentGameplayChromeIsVisible(
            mode: mode,
            runReadiness: readiness,
            isAwaitingTitleStart: awaiting,
            isSuppressed: suppressed,
            hasTouches: hasTouches) == expected,
              "persistent chrome matrix rejects title/menu/controller states exactly")
    }

    check(TouchControls.titleStartChromeIsVisible(
        mode: .gameplay, isAwaitingTitleStart: true,
        isSuppressed: false, hasTouches: false),
          "the title prompt presents its centered Start control")
    check(!TouchControls.titleStartChromeIsVisible(
        mode: .gameplay, isAwaitingTitleStart: false,
        isSuppressed: false, hasTouches: false)
          && !TouchControls.titleStartChromeIsVisible(
            mode: .pause, isAwaitingTitleStart: true,
            isSuppressed: false, hasTouches: false),
          "title Start is absent from active gameplay and captured native menus")

    check(TouchControls.rightStickArtworkIsVisible(
        mode: .gameplay, runReadiness: .active, isAwaitingTitleStart: false,
        cutsceneSkipAvailable: false, isEngaged: true,
        isSuppressed: false, hasTouches: false),
          "engaged active gameplay shows the fixed R-stick artwork")
    check(!TouchControls.rightStickArtworkIsVisible(
        mode: .gameplay, runReadiness: .active, isAwaitingTitleStart: false,
        cutsceneSkipAvailable: false, isEngaged: false,
        isSuppressed: false, hasTouches: false),
          "idle gameplay hides only the fixed R-stick artwork")
    check(!TouchControls.rightStickArtworkIsVisible(
        mode: .gameplay, runReadiness: .active, isAwaitingTitleStart: false,
        cutsceneSkipAvailable: true, isEngaged: true,
        isSuppressed: false, hasTouches: false),
          "authoritative SKIP ownership hides the conflicting camera chrome")
    check(!TouchControls.rightStickArtworkIsVisible(
        mode: .pause, runReadiness: .active, isAwaitingTitleStart: false,
        cutsceneSkipAvailable: false, isEngaged: true,
        isSuppressed: false, hasTouches: false),
          "captured pause hides the gameplay R-stick artwork")

    var hiddenStick = Runner()
    hiddenStick.controls.setNativeMenuState(
        .gameplay, progress: .unavailable, titleStartState: .notAwaiting,
        runReadiness: .active)
    hiddenStick.controls.reset()
    check(!hiddenStick.controls.isEngaged,
          "reset deterministically models fully idle R-stick artwork")
    let camera = Finger()
    let cameraCentre = CGPoint(x: Runner.rightStick.midX, y: Runner.rightStick.midY)
    hiddenStick.down(camera, cameraCentre)
    hiddenStick.move(camera, CGPoint(x: cameraCentre.x + TouchControls.rightStickRadius,
                                     y: cameraCentre.y))
    check(hiddenStick.controls.isEngaged && hiddenStick.frame().isRightDeflected,
          "the first drag on hidden R artwork both restores it and controls the camera")

    hiddenStick.up(camera)
    hiddenStick.controls.reset()
    check(hiddenStick.controls.performZoomToggle(lookAroundState: .normal)
          && hiddenStick.controls.isEngaged,
          "a semantic Zoom tap also restores touch presentation immediately")

    hiddenStick.controls.setWarpGateTouchSnapshot(.validUnavailable(sequence: 200))
    check(hiddenStick.controls.isEngaged,
          "a non-capturing warp publication cannot erase the active-gameplay R reveal")
    hiddenStick.controls.setWarpGateTouchSnapshot(warpList(sequence: 202))
    check(!hiddenStick.controls.isEngaged,
          "destination-list capture still cancels gameplay chrome and input")
    hiddenStick.controls.setWarpGateTouchSnapshot(.validUnavailable(sequence: 204))
    check(hiddenStick.controls.isEngaged,
          "leaving warp capture restores the discoverable R control")

    hiddenStick.controls.reset()
    hiddenStick.controls.restoreGameplayChromeAfterInterruption()
    check(hiddenStick.controls.isEngaged,
          "foreground recovery explicitly restores active-gameplay R presentation")

    hiddenStick.controls.reset()
    let movement = Finger()
    hiddenStick.down(movement, CGPoint(x: 170, y: 650))
    check(hiddenStick.controls.isEngaged
          && TouchControls.rightStickArtworkIsVisible(
            mode: .gameplay, runReadiness: .active, isAwaitingTitleStart: false,
            cutsceneSkipAvailable: false, isEngaged: hiddenStick.controls.isEngaged,
            isSuppressed: false, hasTouches: true),
          "the first ordinary screen touch, including movement, immediately reveals R")
}

@MainActor
private func gameplayTouchBatchHasOneOrderedOwner() {
    print("gameplay touch recovery and mapping share one ordered UIKit owner")
    var events: [String] = []
    TouchControlsView.forwardGameplayTouchBatch(
        ["A", "B"], isSuppressed: true,
        reclaim: {
            events.append("reclaim")
            return true
        },
        began: { events.append("began-\($0)") })
    check(events == ["reclaim", "began-A", "began-B"],
          "a suppressed batch recovers once before forwarding every touch")

    events.removeAll()
    TouchControlsView.forwardGameplayTouchBatch(
        ["A"], isSuppressed: false,
        reclaim: {
            events.append("unexpected-reclaim")
            return true
        },
        began: { events.append("began-\($0)") })
    check(events == ["began-A"],
          "an unsuppressed batch forwards immediately without recovery")

    var run = Runner()
    let finger = Finger()
    events.removeAll()
    TouchControlsView.forwardGameplayTouchBatch(
        [finger], isSuppressed: true,
        reclaim: {
            events.append("failed-reclaim")
            return false
        },
        began: { forwarded in
            events.append("began")
            run.down(forwarded, CGPoint(x: Runner.start.midX, y: Runner.start.midY))
        })
    check(events == ["failed-reclaim", "began"]
          && run.frame().buttons.contains(.start),
          "failed chrome recovery never gates the UIKit gameplay touch")
}

private func progressSnapshot(screen: Int, option: Int = 0,
                              selected: Bool = false,
                              transition: Bool = false,
                              startingScreen: Int = -2,
                              canExitWithStart: Bool = false,
                              canGoBack: Bool = false) -> NativeProgressMenuSnapshot {
    NativeProgressMenuSnapshot(available: true, screenRawValue: screen, optionIndex: option,
                               selectedOption: selected, inTransition: transition,
                               navigationAvailable: startingScreen != -2,
                               startingScreenRawValue: startingScreen,
                               canExitWithStart: canExitWithStart,
                               canGoBack: canGoBack)
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
    check(NativeMenuCommandLayout.width == 148
          && NativeMenuCommandLayout.height == 60
          && NativeMenuCommandLayout.horizontalInset == 16
          && NativeMenuCommandLayout.iconColumnWidth == 20
          && NativeMenuCommandLayout.iconTextSpacing == 10,
          "every right-stack command shares one left inset, icon column, and text gap")
    check(NativeMenuTouchAction.available(in: .pause).isEmpty,
          "pause keeps Resume in the persistent bottom session pill")
    check(NativeMenuTouchAction.available(in: .menu)
          == [.up, .down, .left, .right, .back, .confirm],
          "debug menu exposes its exact D-pad, Square, and X actions without duplicate Resume")
    check(NativeMenuTouchAction.available(in: .progress).isEmpty,
          "progress fails closed without an authoritative internal snapshot")
    let stats = progressSnapshot(screen: 0)
    check(NativeMenuTouchAction.available(in: .progress, progress: stats)
          == [.up, .down, .left, .right,
              .precursorOrbs, .fuelCells, .scoutFlies, .settings],
          "fuel-cell stats expose its exact full D-pad and face-button destinations")
    check(NativeMenuTouchAction.available(
        in: .progress, progress: progressSnapshot(screen: 1))
          == [.up, .down, .precursorOrbs, .fuelCells, .scoutFlies, .settings],
          "other stats retain level navigation without inventing left or right input")
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
          && NativeMenuTouchAction.start.button.bit == .start
          && NativeMenuTouchAction.pause.button.bit == .start
          && NativeMenuTouchAction.resume.button.bit == .start,
          "Confirm, Back, Cancel, Start, Pause, and Resume retain Jak's ordinary pad bytes")
    check(NativeMenuTouchAction.fuelCells.button.bit == .square
          && NativeMenuTouchAction.precursorOrbs.button.bit == .cross
          && NativeMenuTouchAction.scoutFlies.button.bit == .triangle
          && NativeMenuTouchAction.settings.button.bit == .circle,
          "stats destinations use Jak's exact face-button mapping")
    check(NativeMenuTouchAction.confirm.label == "Confirm"
          && NativeMenuTouchAction.back.label == "Back"
          && NativeMenuTouchAction.cancel.label == "Cancel"
          && NativeMenuTouchAction.start.label == "Start"
          && NativeMenuTouchAction.pause.label == "Pause"
          && NativeMenuTouchAction.resume.label == "Resume",
          "command targets have explicit accessible labels")
    check(NativeMenuTouchAction.precursorOrbs.label == "Orbs"
          && NativeMenuTouchAction.fuelCells.label == "Cells"
          && NativeMenuTouchAction.scoutFlies.label == "Flies"
          && NativeMenuTouchAction.settings.label == "Options",
          "stats targets use the requested compact user-facing names")
    check(NativeMenuTouchAction.confirm.systemImage == "xmark"
          && NativeMenuTouchAction.back.systemImage == "circle"
          && NativeMenuTouchAction.cancel.systemImage == "circle"
          && NativeMenuTouchAction.precursorOrbs.systemImage == "xmark"
          && NativeMenuTouchAction.fuelCells.systemImage == "square"
          && NativeMenuTouchAction.scoutFlies.systemImage == "triangle"
          && NativeMenuTouchAction.settings.systemImage == "circle",
          "confirm/cancel and stats rows use the requested PlayStation-shaped symbols")
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

    var fuelCellNavigation = Runner()
    fuelCellNavigation.controls.setNativeMenuState(
        .progress, progress: progressSnapshot(screen: 0))
    for direction in [NativeMenuTouchAction.up, .down, .left, .right] {
        fuelCellNavigation.controls.performNativeMenuAction(direction)
    }
    check(fuelCellNavigation.controls.consumeHapticEvents()
          == [.button(.up), .button(.down), .button(.left), .button(.right)]
          && fuelCellNavigation.frame().buttons
          == [.up, .down, .left, .right],
          "fuel-cell stats D-pad emits all four exact ordinary navigation bytes")

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

    run.controls.setNativeMenuState(
        .progress, progress: progressSnapshot(screen: 3, transition: true,
                                               startingScreen: 0,
                                               canExitWithStart: false))
    run.controls.performNativeMenuAction(.resume)
    check(run.frame() == .neutral && run.controls.consumeHapticEvents().isEmpty,
          "a visible but disabled transitional Resume rejects stale activation")

    run.controls.setNativeMenuState(
        .progress, progress: progressSnapshot(screen: 28, startingScreen: 27,
                                               canExitWithStart: true,
                                               canGoBack: true))
    run.controls.performNativeMenuAction(.start)
    check(run.frame().buttons.contains(.start)
          && run.controls.consumeHapticEvents() == [.button(.start)],
          "an eligible title-progress Start emits the ordinary physical Start pulse")
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
    check(run.controls.performNativeMenuVerticalSwipe(
        translation: CGSize(width: 0, height: -TouchControls.nativeMenuSwipeDistance)),
          "fuel-cell stats accept their source-proven upward level navigation")
    check(run.controls.consumeHapticEvents() == [.button(.up)]
          && run.frame().buttons.contains(.up),
          "fuel-cell stats swipe emits one exact Up pulse")
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
    check(!run.controls.performZoomToggle(lookAroundState: .normal)
          && run.frame() == .neutral,
          "raw gameplay touch and zoom input stay disabled under dedicated menu controls")

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
    print("native menu touch remains available and respects cancellation boundaries")
    check(TouchControls.nativeMenuControlsAreVisible(mode: .menu),
          "menu controls remain touchable alongside physical input")
    check(!TouchControls.nativeMenuControlsAreVisible(mode: .progress),
          "unavailable progress does not present controls with unproven labels")
    check(TouchControls.nativeMenuControlsAreVisible(
        mode: .progress, progress: progressSnapshot(screen: 0)),
          "validated progress stats present exact touch controls")
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
    print("warp capture and always-on touch follow the authoritative phase")
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
        mode: .gameplay, snapshot: prompt)
          && TouchControls.warpGateTouchControlsAreVisible(
            mode: .gameplay, snapshot: list),
          "prompt and settled list keep their exact touch actions available")
    check(TouchControls.warpGateTouchControlsAreVisible(
        mode: .gameplay, snapshot: moving)
          && !TouchControls.warpGateTouchControlsAreVisible(
            mode: .gameplay, snapshot: transitioning),
          "selection movement retains Warp and Back while transition presents no actions")
    check(!TouchControls.warpGateTouchControlsAreVisible(
        mode: .gameplay, snapshot: malformedList),
          "a malformed list neither captures nor presents actions")

    var touchOwned = Runner()
    touchOwned.controls.setNativeMenuMode(.gameplay)
    touchOwned.controls.setWarpGateTouchSnapshot(prompt)
    touchOwned.controls.performNativeWarpGateAction(.useWarpGate, for: prompt)
    check(touchOwned.frame().buttons == .circle
          && touchOwned.controls.consumeHapticEvents() == [.button(.circle)],
          "warp prompt touch emits its action regardless of physical-input ownership")
    touchOwned.controls.setWarpGateTouchSnapshot(list)
    check(touchOwned.controls.performNativeWarpGateSwipe(
        translation: CGSize(width: TouchControls.nativeWarpSwipeDistance, height: 0),
        for: list),
          "full-screen warp swipes remain touchable alongside physical input")

    var run = Runner()
    run.controls.setNativeMenuMode(.gameplay)
    run.controls.setWarpGateTouchSnapshot(list)
    let ignored = Finger()
    let centre = CGPoint(x: 180, y: 650)
    run.down(ignored, centre)
    run.move(ignored, CGPoint(x: centre.x + TouchControls.movementRadius, y: centre.y))
    check(!run.controls.performZoomToggle(lookAroundState: .normal)
          && run.frame() == .neutral,
          "captured list touch cannot leak gameplay movement, gesture, or zoom input")

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

private func facePrompt(_ requestedButtons: UInt32,
                        sequence: UInt32 = 100) -> NativeFacePromptTouchSnapshot {
    NativeFacePromptTouchSnapshot(valid: true,
                                  requestedButtons: requestedButtons,
                                  sequence: sequence)
}

private func facePromptActions(
    snapshot: NativeFacePromptTouchSnapshot,
    mode: GOALPadGameMode = .gameplay,
    warpVisible: Bool = false,
    warpCaptures: Bool = false,
    cutsceneSkipAvailable: Bool = false
) -> [NativeFacePromptTouchAction] {
    NativeFacePromptTouchAction.available(
        in: mode,
        snapshot: snapshot,
        warpGateControlsVisible: warpVisible,
        warpGateCapturesInput: warpCaptures,
        cutsceneSkipAvailable: cutsceneSkipAvailable)
}

private func nativeFacePromptMappingOrderAndPriorityAreExact() {
    print("face prompts map only exact native bits in stable symbol order")
    let all = facePrompt(NativeFacePromptTouchSnapshot.supportedMask)
    check(all.isStructurallyValid,
          "the complete four-face-button publication is structurally valid")
    check(NativeFacePromptTouchAction.allCases.map(\.glyph) == ["×", "□", "△", "○"]
          && facePromptActions(snapshot: all) == [.cross, .square, .triangle, .circle],
          "visible face controls remain ordered Cross, Square, Triangle, Circle")
    check(NativeFacePromptTouchAction.allCases.map(\.requestedMask) == [
        1 << 14, 1 << 15, 1 << 12, 1 << 13,
    ] && NativeFacePromptTouchAction.allCases.map { $0.button.bit.rawValue } == [
        1 << 14, 1 << 15, 1 << 12, 1 << 13,
    ], "each symbol maps to its exact ordinary pad byte")

    let malformed = [
        NativeFacePromptTouchSnapshot.invalid,
        facePrompt(0),
        facePrompt(NativeFacePromptTouchSnapshot.crossMask, sequence: 101),
        facePrompt(NativeFacePromptTouchSnapshot.supportedMask | (1 << 11)),
        NativeFacePromptTouchSnapshot(valid: false,
                                      requestedButtons: NativeFacePromptTouchSnapshot.crossMask,
                                      sequence: 102),
    ]
    check(malformed.allSatisfy { !($0.isStructurallyValid) }
          && malformed.allSatisfy { facePromptActions(snapshot: $0).isEmpty },
          "invalid, empty, odd, unknown-bit, and rejected publications fail closed")
    check(facePromptActions(snapshot: all, mode: .pause).isEmpty
          && facePromptActions(snapshot: all, warpVisible: true).isEmpty
          && facePromptActions(snapshot: all, warpCaptures: true).isEmpty,
          "native menus and either visible or capturing warp ownership suppress face prompts")

    let triangleAndCross = facePrompt(NativeFacePromptTouchSnapshot.triangleMask
                                      | NativeFacePromptTouchSnapshot.crossMask)
    check(facePromptActions(snapshot: triangleAndCross,
                            cutsceneSkipAvailable: true) == [.cross],
          "SKIP remains the sole Triangle control while unrelated requested symbols remain")
}

@MainActor
private func nativeFacePromptPulsesRejectStaleWorkAndCancelOnLoss() {
    print("face prompts emit exact pulses and cancel only prompt-owned stale work")
    for (index, action) in NativeFacePromptTouchAction.allCases.enumerated() {
        var run = Runner()
        run.controls.setNativeMenuMode(.gameplay)
        let snapshot = facePrompt(action.requestedMask, sequence: UInt32(110 + index * 2))
        run.controls.setFacePromptTouchSnapshot(snapshot)
        run.controls.performFacePromptAction(action, for: snapshot)
        check(run.controls.consumeHapticEvents() == [.button(action.button)]
              && run.frame().buttons == action.button.bit,
              "\(action.accessibilityLabel) emits one exact pad bit and haptic")
        let cadence = run.frames(TouchControls.holdFrames - 1
                                 + TouchControls.releaseFrames)
        check(cadence.prefix(TouchControls.holdFrames - 1).allSatisfy {
            $0.buttons == action.button.bit
        } && cadence.suffix(TouchControls.releaseFrames).allSatisfy {
            $0 == .neutral
        }, "\(action.accessibilityLabel) keeps the ordinary hold and release cadence")
    }

    var stale = Runner()
    stale.controls.setNativeMenuMode(.gameplay)
    let old = facePrompt(NativeFacePromptTouchSnapshot.circleMask, sequence: 130)
    let current = facePrompt(NativeFacePromptTouchSnapshot.circleMask, sequence: 132)
    stale.controls.setFacePromptTouchSnapshot(current)
    stale.controls.performFacePromptAction(.circle, for: old)
    check(stale.frame() == .neutral && stale.controls.consumeHapticEvents().isEmpty,
          "a stale full-snapshot closure is a no-op")
    stale.controls.performFacePromptAction(.cross, for: current)
    check(stale.frame() == .neutral && stale.controls.consumeHapticEvents().isEmpty,
          "an unrequested face action is a no-op")

    var lost = Runner()
    lost.controls.setNativeMenuMode(.gameplay)
    let cross = facePrompt(NativeFacePromptTouchSnapshot.crossMask, sequence: 140)
    lost.controls.setFacePromptTouchSnapshot(cross)
    let movement = Finger()
    let centre = CGPoint(x: 180, y: 650)
    lost.down(movement, centre)
    lost.move(movement, CGPoint(x: centre.x + TouchControls.movementRadius, y: centre.y))
    _ = lost.controls.consumeHapticEvents()
    lost.controls.performFacePromptAction(.cross, for: cross)
    lost.controls.performFacePromptAction(.cross, for: cross)
    lost.controls.setFacePromptTouchSnapshot(.invalid)
    let afterLoss = lost.frame()
    check(afterLoss.isLeftDeflected && !afterLoss.buttons.contains(.cross)
          && lost.controls.consumeHapticEvents().isEmpty,
          "prompt loss cancels its pending pulse and feedback without cancelling raw movement")

    var suppressed = Runner()
    suppressed.controls.setNativeMenuMode(.gameplay)
    let all = facePrompt(NativeFacePromptTouchSnapshot.supportedMask, sequence: 150)
    suppressed.controls.setFacePromptTouchSnapshot(all)
    suppressed.controls.setWarpGateTouchSnapshot(
        .circleUseAvailable(sequence: 152))
    suppressed.controls.performFacePromptAction(.cross, for: all)
    check(suppressed.frame() == .neutral && suppressed.controls.consumeHapticEvents().isEmpty,
          "the accepted visible warp prompt has priority over contextual face actions")

    var skip = Runner()
    skip.controls.setNativeMenuMode(.gameplay)
    let triangle = facePrompt(NativeFacePromptTouchSnapshot.triangleMask, sequence: 160)
    skip.controls.setFacePromptTouchSnapshot(triangle)
    skip.controls.setCutsceneSkipTouchSnapshot(.triangleQueryAvailable(sequence: 162))
    skip.controls.performFacePromptAction(.triangle, for: triangle)
    check(skip.frame() == .neutral && skip.controls.consumeHapticEvents().isEmpty,
          "cutscene SKIP prevents a duplicate contextual Triangle pulse")
}

@main
@MainActor
struct TouchControlsCheck {
    static func main() {
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
        semanticZoomButtonIsExactAndFailClosed()
        modernChromeAddsZoomWithoutMovingAcceptedPills()
        cutsceneSkipIsContextualExactAndLifecycleSafe()
        pausePresentationFollowsNativeMenuState()
        semanticTitleStartBypassesArtworkGeometryAndSurvivesCadence()
        sessionControlStateMatrixIsExactAndFailClosed()
        controllerSuppressionKeepsTouchRecovery()
        build128ChromeStateMatrixAndRightStickRecovery()
        gameplayTouchBatchHasOneOrderedOwner()
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
        nativeFacePromptMappingOrderAndPriorityAreExact()
        nativeFacePromptPulsesRejectStaleWorkAndCancelOnLoss()

        print(failures == 0 ? "\nall checks passed" : "\n\(failures) checks FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
