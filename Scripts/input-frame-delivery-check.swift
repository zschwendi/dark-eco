import Foundation

// A display callback that runs no GOAL frame must not consume input. GOAL reads only the latest
// pad state when its dispatcher runs, so these checks feed real touch and keyboard/mouse state
// through InputFrameDelivery and record what each GOAL frame would read.

private var failures = 0

private func check(_ condition: Bool, _ message: String) {
    print(condition ? "  ok   \(message)" : "  FAIL \(message)")
    if !condition { failures += 1 }
}

private func risingEdges(_ reads: [Bool]) -> Int {
    var previous = false
    var edges = 0
    for pressed in reads {
        if pressed && !previous { edges += 1 }
        previous = pressed
    }
    return edges
}

@MainActor
private func touchTapsSurviveCallbacksWithoutGOALFrames() {
    // 60 Hz logical time on 120 Hz callbacks: every other callback runs a GOAL frame.
    let controls = TouchControls(style: .modern)
    controls.setNativeMenuState(.gameplay, progress: .unavailable, titleStartState: .awaiting)
    var delivery = InputFrameDelivery<TouchPadState>()
    var reads: [Bool] = []
    controls.performNativeMenuAction(.start)
    for callback in 0..<12 {
        let frame = delivery.frame { controls.frameState() }
        if callback == 0 {
            // A second tap during the first one's hold queues a separate press.
            controls.performNativeMenuAction(.start)
        }
        let goalFrameRan = callback % 2 == 0
        if goalFrameRan { reads.append(frame.buttons.contains(.start)) }
        delivery.finish(goalFrameRan: goalFrameRan)
    }
    check(risingEdges(reads) == 2,
          "two queued taps reach GOAL as two press edges when releases land on empty callbacks "
              + "(reads \(reads))")
}

private func mouseMovementSurvivesUntilAGOALFrameReadsIt() {
    let neutral = UInt8(GOALPadAnalogNeutral)
    var mouse = KeyboardMouseInputState()
    var delivery = InputFrameDelivery<KeyboardMouseFrame>()
    var reads: [UInt8] = []
    mouse.addMouseMovement(deltaX: 40, deltaY: 0)
    for goalFrameRan in [false, false, true, true] {
        let frame = delivery.frame { mouse.consumeFrame() }
        if goalFrameRan { reads.append(frame.rightX) }
        delivery.finish(goalFrameRan: goalFrameRan)
    }
    check(reads.count == 2 && reads[0] != neutral && reads[1] == neutral,
          "mouse movement before two empty callbacks is read by exactly one GOAL frame "
              + "(reads \(reads))")

    // Movement that arrives while a frame is held accumulates for the following GOAL frame.
    reads = []
    mouse.addMouseMovement(deltaX: 40, deltaY: 0)
    _ = delivery.frame { mouse.consumeFrame() }
    delivery.finish(goalFrameRan: false)
    mouse.addMouseMovement(deltaX: 40, deltaY: 0)
    for _ in 0..<2 {
        let frame = delivery.frame { mouse.consumeFrame() }
        reads.append(frame.rightX)
        delivery.finish(goalFrameRan: true)
    }
    check(reads[0] != neutral && reads[1] != neutral,
          "movement added while a frame waits is kept for the next GOAL frame (reads \(reads))")
    let drained = delivery.frame { mouse.consumeFrame() }
    check(drained.rightX == neutral, "all movement is consumed once it has been read")
}

@MainActor
private func ordinaryCallbacksSampleEveryFrame() {
    let controls = TouchControls(style: .modern)
    controls.setNativeMenuState(.gameplay, progress: .unavailable, titleStartState: .awaiting)
    var delivery = InputFrameDelivery<TouchPadState>()
    controls.performNativeMenuAction(.start)
    var reads: [Bool] = []
    for _ in 0..<(TouchControls.holdFrames + TouchControls.releaseFrames) {
        reads.append(delivery.frame { controls.frameState() }.buttons.contains(.start))
        delivery.finish(goalFrameRan: true)
    }
    check(reads == Array(repeating: true, count: TouchControls.holdFrames)
              + Array(repeating: false, count: TouchControls.releaseFrames),
          "callbacks that each run a GOAL frame keep the ordinary hold and release cadence")

    var reset = InputFrameDelivery<Int>()
    _ = reset.frame { 1 }
    reset.finish(goalFrameRan: false)
    reset.reset()
    check(reset.frame { 2 } == 2, "a reset drops a held frame so stale input is not replayed")
}

@main
@MainActor
private enum InputFrameDeliveryCheck {
    static func main() {
        touchTapsSurviveCallbacksWithoutGOALFrames()
        mouseMovementSurvivesUntilAGOALFrameReadsIt()
        ordinaryCallbacksSampleEveryFrame()
        guard failures == 0 else {
            print("input frame delivery checks failed: \(failures)")
            exit(1)
        }
        print("input frame delivery checks passed")
    }
}
