// A deterministic check of the on-screen controls, run on the host.
//
// The simulator can only be driven with one mouse, so the things that matter most here - two
// fingers at once, and exactly how many frames a synthesised press is held for - cannot be
// observed there. This drives `TouchControls` directly instead, one frame at a time.
//
//   Scripts/run-touch-controls-check.sh
//
// It links no engine: `TouchControls` only needs the button bits and the analog neutral value out
// of `GOALPadRuntimeBridge.h`.

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
    /// The iPad Pro 11-inch's landscape point size.
    static let screen = CGSize(width: 1210, height: 834)

    let controls = TouchControls()
    var clock: TimeInterval = 0

    /// Run one frame and return the pad state the engine would have been handed.
    mutating func frame() -> TouchPadState {
        clock += 1.0 / 60
        return controls.frameState()
    }

    /// Run `count` frames and return the button mask of each.
    mutating func frames(_ count: Int) -> [GOALPadButton] {
        (0..<count).map { _ in frame().buttons }
    }

    func down(_ finger: Finger, _ x: CGFloat, _ y: CGFloat) {
        controls.began(ObjectIdentifier(finger), at: CGPoint(x: x, y: y), in: Self.screen,
                       at: clock)
    }

    func move(_ finger: Finger, _ x: CGFloat, _ y: CGFloat) {
        controls.moved(ObjectIdentifier(finger), to: CGPoint(x: x, y: y))
    }

    func up(_ finger: Finger) {
        controls.ended(ObjectIdentifier(finger), at: clock)
    }
}

private let neutral = UInt8(GOALPadAnalogNeutral)

@MainActor
private func stickPlacementIsStationary() {
    print("the stick is placed where the finger lands and stays there")
    var run = Runner()
    let thumb = Finger()
    run.down(thumb, 200, 600)
    check(run.frame().leftX == neutral, "a placed finger that has not moved is centred")

    run.move(thumb, 290, 600)
    var state = run.frame()
    check(state.leftX == 254 && state.leftY == neutral, "a full-radius drag right is hard right")

    // Ten frames with the finger held exactly where it was dragged to: a stick that re-centred
    // itself under the finger would fall back to neutral here.
    for _ in 0..<10 { state = run.frame() }
    check(state.leftX == 254, "the deflection is held while the finger is held")

    run.move(thumb, 245, 645)
    state = run.frame()
    check(state.leftX == 191 && state.leftY == 191, "half a radius diagonally is half deflection")

    run.move(thumb, 500, 600)
    check(run.frame().leftX == 254, "beyond the radius is clamped, not wrapped")

    run.move(thumb, 200, 510)
    check(run.frame().leftY == 0, "up the screen is the low byte, the way the PS2 pad reported it")

    run.up(thumb)
    check(run.frame().leftX == neutral, "lifting the finger centres the stick")
}

@MainActor
private func swipesHoldTheirButton() {
    print("a swipe is held long enough for GOAL to see the edge, then released")
    var run = Runner()
    let finger = Finger()
    run.down(finger, 900, 500)
    run.move(finger, 900, 440)   // 60 points up, past the 44 point threshold
    run.up(finger)

    let held = run.frames(12).map { $0.contains(.cross) }
    check(held.prefix(TouchControls.holdFrames).allSatisfy { $0 },
          "cross is held for \(TouchControls.holdFrames) frames")
    check(!held[TouchControls.holdFrames], "cross is released on the next frame")
    check(held.dropFirst(TouchControls.holdFrames).allSatisfy { !$0 }, "and stays released")

    print("a swipe held down keeps its button down")
    var long = Runner()
    let held2 = Finger()
    long.down(held2, 900, 500)
    long.move(held2, 900, 400)
    let during = long.frames(30).map { $0.contains(.cross) }
    check(during.allSatisfy { $0 }, "30 frames with the finger still down are all held")
    long.up(held2)
    let after = long.frames(6).map { $0.contains(.cross) }
    check(!after.allSatisfy { $0 }, "and it releases once the finger goes")
}

@MainActor
private func swipeDirectionsMap() {
    print("each swipe direction maps to its face button")
    for (dx, dy, expected, name) in [(CGFloat(0), CGFloat(-70), GOALPadButton.cross, "up"),
                                     (-70, 0, .square, "left"),
                                     (70, 0, .circle, "right")] {
        var run = Runner()
        let finger = Finger()
        run.down(finger, 900, 500)
        run.move(finger, 900 + dx, 500 + dy)
        run.up(finger)
        check(run.frames(3).allSatisfy { $0 == expected },
              "swipe \(name) is the one button it should be")
    }

    var down = Runner()
    let finger = Finger()
    down.down(finger, 900, 500)
    down.move(finger, 900, 570)
    down.up(finger)
    check(down.frames(10).allSatisfy(\.isEmpty), "swipe down is unmapped and is not a tap either")
}

@MainActor
private func tapsRepeatTheLastSwipe() {
    print("a tap repeats the last swiped button")
    var run = Runner()
    let first = Finger()
    run.down(first, 900, 500)
    run.up(first)
    check(run.frames(3).allSatisfy { $0.contains(.cross) }, "the first tap of a session jumps")

    let swipe = Finger()
    run.down(swipe, 900, 500)
    run.move(swipe, 830, 500)
    run.up(swipe)
    _ = run.frames(10)

    let tap = Finger()
    run.down(tap, 900, 500)
    run.up(tap)
    check(run.frames(3).allSatisfy { $0 == GOALPadButton.square as GOALPadButton },
          "a tap after a left swipe is square, not cross")

    print("two taps are two presses")
    var repeated = Runner()
    let a = Finger()
    repeated.down(a, 900, 500)
    repeated.up(a)
    let firstPress = repeated.frames(TouchControls.holdFrames + TouchControls.releaseFrames)
    let b = Finger()
    repeated.down(b, 900, 500)
    repeated.up(b)
    let secondPress = repeated.frames(TouchControls.holdFrames)
    check(firstPress.filter { $0.contains(.cross) }.count == TouchControls.holdFrames,
          "the first press is exactly \(TouchControls.holdFrames) frames")
    check(firstPress.suffix(TouchControls.releaseFrames).allSatisfy { !$0.contains(.cross) },
          "with \(TouchControls.releaseFrames) released frames after it")
    check(secondPress.allSatisfy { $0.contains(.cross) }, "and the second press is its own press")

    print("a tap that lingers is neither a tap nor a swipe")
    var slow = Runner()
    let resting = Finger()
    slow.down(resting, 900, 500)
    _ = slow.frames(40)          // two thirds of a second
    slow.up(resting)
    check(slow.frames(10).allSatisfy(\.isEmpty), "a resting finger presses nothing")
}

@MainActor
private func fingersWorkTogether() {
    print("moving and jumping at the same time")
    var run = Runner()
    let thumb = Finger()
    let index = Finger()
    run.down(thumb, 200, 600)
    run.move(thumb, 290, 600)
    run.down(index, 900, 500)
    run.move(index, 900, 430)

    let state = run.frame()
    check(state.leftX == 254 && state.buttons.contains(.cross),
          "one frame carries the stick and the jump together")

    run.up(index)
    let after = run.frame()
    check(after.leftX == 254, "lifting the jumping finger leaves the stick alone")
    check(run.controls.stick != nil, "and the stick is still placed")
}

@MainActor
private func cameraDragsAboveTheStick() {
    print("a drag above the placed stick is the right stick, which is what the camera reads")
    var run = Runner()
    let thumb = Finger()
    run.down(thumb, 200, 700)
    run.move(thumb, 200, 640)

    let look = Finger()
    run.down(look, 260, 700 - TouchControls.deflectionRadius - 10)
    check(run.controls.camera != nil, "a finger above the stick's ring is a camera drag")

    run.move(look, 260 + TouchControls.cameraRadius, 700 - TouchControls.deflectionRadius - 10)
    let state = run.frame()
    check(state.rightX == 254 && state.rightY == neutral, "dragged right is hard right")
    check(state.leftY < neutral, "and the stick still reports what it was holding")

    run.up(look)
    check(run.frame().rightX == neutral, "lifting it centres the camera")

    print("a finger beside the stick is not a camera drag")
    let palm = Finger()
    run.down(palm, 260, 700)
    check(run.controls.camera == nil, "a finger level with the stick is ignored")
    run.move(palm, 500, 700)
    check(run.frame().rightX == neutral, "and dragging it does nothing")

    print("the stick's own drag never becomes a camera drag")
    var stickOnly = Runner()
    let only = Finger()
    stickOnly.down(only, 200, 700)
    stickOnly.move(only, 200, 700 - TouchControls.deflectionRadius - 60)
    check(stickOnly.controls.camera == nil, "dragging the stick far up is still the stick")
    check(stickOnly.frame().leftY == 0, "and it is fully deflected up")
}

@MainActor
private func theStickAlsoStepsTheDpad() {
    print("the stick presses the D-pad the menus read, one step at a time")
    var run = Runner()
    let thumb = Finger()
    run.down(thumb, 200, 600)
    // 0.6 of the radius right: past the press threshold, and held there.
    run.move(thumb, 200 + 0.6 * TouchControls.deflectionRadius, 600)

    let states = (0..<48).map { _ in run.frame() }
    let right = states.map { $0.buttons.contains(.right) }
    let hold = TouchControls.holdFrames
    let delay = TouchControls.dpadRepeatDelay
    let interval = TouchControls.dpadRepeatInterval

    check(right.prefix(hold).allSatisfy { $0 }, "crossing the threshold is one press")
    check(right[hold..<delay].allSatisfy { !$0 },
          "and then nothing for \(delay) frames, not a bit held down")
    check(right[delay..<(delay + hold)].allSatisfy { $0 }, "it repeats after the delay")
    check(right[(delay + hold)..<(delay + interval)].allSatisfy { !$0 },
          "with a real release between repeats")
    check(right[(delay + interval)..<(delay + interval + hold)].allSatisfy { $0 },
          "and keeps repeating every \(interval) frames")
    check(states.allSatisfy { $0.leftX > 160 },
          "the analog stick is reported the whole time as well")
    check(states.allSatisfy { !$0.buttons.contains(.left) && !$0.buttons.contains(.up) },
          "and no other direction is ever pressed")

    print("a push has to come back before it presses again")
    run.move(thumb, 200 + 0.2 * TouchControls.deflectionRadius, 600)
    // The press that was already in flight finishes first; what matters is that no more follow.
    check(run.frames(20).dropFirst(hold).allSatisfy { !$0.contains(.right) },
          "easing back below the release threshold stops the repeat")
    run.move(thumb, 200 + 0.7 * TouchControls.deflectionRadius, 600)
    check(run.frames(1).allSatisfy { $0.contains(.right) }, "and pushing again is a fresh press")

    print("a small push is analog only")
    var gentle = Runner()
    let easy = Finger()
    gentle.down(easy, 200, 600)
    gentle.move(easy, 200 + 0.4 * TouchControls.deflectionRadius, 600)
    let walked = gentle.frames(40)
    check(walked.allSatisfy(\.isEmpty), "walking speed presses no direction")

    print("a diagonal push is one direction, not two")
    var diagonal = Runner()
    let corner = Finger()
    diagonal.down(corner, 200, 600)
    diagonal.move(corner, 200 + 70, 600 - 60)
    let pressed = diagonal.frames(3)
    check(pressed.allSatisfy { $0.contains(.right) && !$0.contains(.up) },
          "the dominant axis wins")
}

@MainActor
private func pillsAreNotSwipes() {
    print("the pills are hit-tested before the swipe recogniser")
    var run = Runner()
    let start = CGRect(x: 620, y: 760, width: 120, height: 44)
    run.controls.setPillFrame(.start, start)

    let finger = Finger()
    run.down(finger, start.midX, start.midY)
    check(run.controls.isPillDown(.start), "a finger on the pill is the pill")
    check(run.frames(3).allSatisfy { $0.contains(.start) }, "and start is held")

    // A pill sits in the right half, where a drag would otherwise be a swipe.
    run.move(finger, start.midX, start.midY - 120)
    let dragged = run.frames(3)
    check(dragged.allSatisfy { $0.contains(.start) }, "dragging off it keeps start held")
    check(dragged.allSatisfy { !$0.contains(.cross) }, "and never becomes a jump")

    run.up(finger)
    let after = run.frames(TouchControls.holdFrames + 2)
    check(!after.last!.contains(.start), "and it releases when the finger goes")
}

@MainActor
private func visibilityFollowsTouch() {
    print("the controls are only shown while something is being touched")
    let run = Runner()
    check(!run.controls.isEngaged, "nothing is drawn before the first touch")
    let finger = Finger()
    run.down(finger, 200, 600)
    check(run.controls.isEngaged, "a touch shows them")
}

@main
@MainActor
struct TouchControlsCheck {
    static func main() {
        stickPlacementIsStationary()
        swipesHoldTheirButton()
        swipeDirectionsMap()
        tapsRepeatTheLastSwipe()
        fingersWorkTogether()
        theStickAlsoStepsTheDpad()
        cameraDragsAboveTheStick()
        pillsAreNotSwipes()
        visibilityFollowsTouch()

        print(failures == 0 ? "\nall checks passed" : "\n\(failures) checks FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
