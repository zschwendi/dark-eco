import Foundation
import simd

#if VISION_SENSE_API_STUBS
enum Jak1ControllerControl {
    case buttonA, buttonB, buttonX, buttonY
    case leftShoulder, rightShoulder, leftTrigger, rightTrigger
    case leftThumbstickButton, rightThumbstickButton, menu, options
}

struct Jak1ControllerSnapshot {
    mutating func set(_ control: Jak1ControllerControl, pressed: Bool, value: Float) {}
    func isPressed(_ control: Jak1ControllerControl) -> Bool { false }
    func value(for control: Jak1ControllerControl) -> Float { 0 }
}
#else
nonisolated(unsafe) private var failures = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("  ok   \(message)")
    } else {
        print("  FAIL \(message)")
        failures += 1
    }
}

private func sample(_ time: TimeInterval, _ x: Float = 0, _ y: Float = 0,
                    _ z: Float = 0, tracked: Bool = true)
    -> SpatialAttackGestureRecognizer.Sample {
    .init(timestamp: time, position: SIMD3(x, y, z), isTracked: tracked)
}

private func transform(translation: SIMD3<Float> = .zero,
                       yaw: Float = 0) -> simd_float4x4 {
    var value = simd_float4x4(simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)))
    value.columns.3 = SIMD4(translation, 1)
    return value
}

private let senseLeft = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
private let senseRight = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

/// The anchor origin stays fixed, so only the aim pose can move a window-route sample.
private func aimPose(_ time: TimeInterval, _ x: Float = 0, _ y: Float = 0, _ z: Float = 0,
                     yaw: Float = 0, id: UUID = senseLeft, tracked: Bool = true,
                     aim: simd_float4x4?? = .none) -> SpatialAccessoryPoseSample {
    .init(accessoryID: id, timestamp: time, isPositionTracked: tracked,
          originFromAccessory: transform(translation: SIMD3(9, 9, 9)),
          originFromAim: aim ?? transform(translation: SIMD3(x, y, z), yaw: yaw))
}

private func headPose(_ time: TimeInterval, _ x: Float = 0, _ y: Float = 0, _ z: Float = 0,
                      id: UUID = senseLeft) -> SpatialAccessoryPoseSample {
    .init(accessoryID: id, timestamp: time, isPositionTracked: true,
          originFromAccessory: transform(translation: SIMD3(x, y, z)), originFromAim: nil)
}

/// Drives the window route one display frame at a time, exactly as the adapter does.
private func windowFrame(_ router: inout SpatialAttackMotionRouter, clock: TimeInterval,
                         _ poses: [SpatialAccessoryPoseSample],
                         allowed: Bool = true, now: TimeInterval? = nil) -> SpatialAttackGesture {
    if allowed { router.updateAccessoryAim(clock: clock, poses: poses) }
    return router.consume(allowed: allowed, reference: .accessoryAim, now: now)
}

private func routerChecks() {
    var window = SpatialAttackMotionRouter()
    check(windowFrame(&window, clock: 1.00, [aimPose(1.00)]) == [],
          "window route establishes a baseline from the aim pose")
    check(windowFrame(&window, clock: 1.06, [aimPose(1.06, 0.005, 0, -0.045)]) == [],
          "window route ignores a partial thrust")
    check(windowFrame(&window, clock: 1.12, [aimPose(1.12, 0.009, 0.003, -0.115)]) == .punch,
          "a fast thrust along the aim ray punches in the ordinary window")
    check(windowFrame(&window, clock: 1.13, [aimPose(1.12, 0.009, 0.003, -0.115)]) == [],
          "re-polling the same measured anchor on a later frame cannot punch again")
    check(window.consume(allowed: true, reference: .accessoryAim) == [],
          "a delivered punch is consumed exactly once")

    var turned = SpatialAttackMotionRouter()
    _ = windowFrame(&turned, clock: 1.00, [aimPose(1.00, yaw: .pi / 2)])
    check(windowFrame(&turned, clock: 1.10, [aimPose(1.10, -0.115, 0, 0, yaw: .pi / 2)]) == .punch,
          "a controller aimed along world -X punches when thrust along its own ray")
    var sideways = SpatialAttackMotionRouter()
    _ = windowFrame(&sideways, clock: 1.00, [aimPose(1.00, yaw: .pi / 2)])
    check(windowFrame(&sideways, clock: 1.10, [aimPose(1.10, 0, 0, -0.115, yaw: .pi / 2)]) == [],
          "motion across a turned controller's aim ray is not a jab")

    var shake = SpatialAttackMotionRouter()
    _ = windowFrame(&shake, clock: 2.00, [aimPose(2.00)])
    check(windowFrame(&shake, clock: 2.10, [aimPose(2.10, 0.070)]) == [],
          "one lateral aim-axis stroke is not a spin")
    check(windowFrame(&shake, clock: 2.20, [aimPose(2.20)]) == .spin,
          "a lateral aim-axis reversal spins in the ordinary window")

    var stale = SpatialAttackMotionRouter()
    _ = windowFrame(&stale, clock: 3.00, [aimPose(2.95)])
    check(windowFrame(&stale, clock: 3.10, [aimPose(2.97, 0, 0, -0.115)]) == []
            && windowFrame(&stale, clock: 3.16, [aimPose(3.16, 0, 0, -0.230)]) == [],
          "an anchor older than the window clock clears the stroke and cannot punch")

    var gap = SpatialAttackMotionRouter()
    _ = windowFrame(&gap, clock: 4.00, [aimPose(4.00)])
    _ = windowFrame(&gap, clock: 4.06, [aimPose(4.06, 0, 0, -0.045)])
    check(windowFrame(&gap, clock: 4.30, [aimPose(4.30, 0, 0, -0.115)]) == [],
          "a stalled window frame clock clears the partial jab")
    var backwards = SpatialAttackMotionRouter()
    _ = windowFrame(&backwards, clock: 4.00, [aimPose(4.00)])
    _ = windowFrame(&backwards, clock: 4.06, [aimPose(4.06, 0, 0, -0.045)])
    check(windowFrame(&backwards, clock: 4.05, [aimPose(4.12, 0, 0, -0.115)]) == [],
          "a window clock that moves backwards clears the partial jab")

    var invalid = SpatialAttackMotionRouter()
    var nonFinite = transform()
    nonFinite.columns.3.z = .nan
    _ = windowFrame(&invalid, clock: 5.00, [aimPose(5.00)])
    check(windowFrame(&invalid, clock: 5.06, [aimPose(5.06, aim: .some(nonFinite))]) == []
            && windowFrame(&invalid, clock: 5.12, [aimPose(5.12, 0, 0, -0.115)]) == [],
          "a non-finite aim pose resets the accessory instead of completing a jab")
    var missingAim = SpatialAttackMotionRouter()
    var missingEvents: SpatialAttackGesture = []
    for (index, z) in [Float(0), -0.045, -0.115, -0.230].enumerated() {
        let time = 5.0 + Double(index) * 0.06
        missingEvents.formUnion(windowFrame(&missingAim, clock: time,
                                            [aimPose(time, 0, 0, z, aim: .some(nil))]))
    }
    check(missingEvents.isEmpty, "an accessory without an aim location never attacks in a window")
    var untracked = SpatialAttackMotionRouter()
    _ = windowFrame(&untracked, clock: 5.00, [aimPose(5.00)])
    _ = windowFrame(&untracked, clock: 5.06, [aimPose(5.06, 0, 0, -0.045, tracked: false)])
    check(windowFrame(&untracked, clock: 5.12, [aimPose(5.12, 0, 0, -0.115)]) == [],
          "orientation-only or lost tracking clears the partial jab")

    var menu = SpatialAttackMotionRouter()
    _ = windowFrame(&menu, clock: 6.00, [aimPose(6.00)])
    _ = windowFrame(&menu, clock: 6.06, [aimPose(6.06, 0, 0, -0.045)])
    check(windowFrame(&menu, clock: 6.08, [aimPose(6.08, 0, 0, -0.080)], allowed: false) == []
            && windowFrame(&menu, clock: 6.12, [aimPose(6.12, 0, 0, -0.115)]) == [],
          "a suppressed menu or pause frame discards motion that began before it")

    var disconnect = SpatialAttackMotionRouter()
    _ = windowFrame(&disconnect, clock: 7.00, [aimPose(7.00)])
    _ = windowFrame(&disconnect, clock: 7.06, [aimPose(7.06, 0, 0, -0.045)])
    _ = windowFrame(&disconnect, clock: 7.08, [])
    check(windowFrame(&disconnect, clock: 7.12, [aimPose(7.12, 0, 0, -0.115)]) == [],
          "a disconnected accessory needs a fresh baseline when it returns")

    var both = SpatialAttackMotionRouter()
    _ = windowFrame(&both, clock: 8.00, [aimPose(8.00), aimPose(8.00, id: senseRight)])
    check(windowFrame(&both, clock: 8.10, [aimPose(8.10, 0, 0, -0.115),
                                           aimPose(8.10, 0, 0, -0.115, id: senseRight)])
            == .punch,
          "simultaneous jabs from both halves produce one Square press")

    var head = SpatialAttackMotionRouter()
    head.update(originFromDevice: transform(), clock: 9.00, poses: [headPose(9.00)])
    head.update(originFromDevice: transform(), clock: 9.06,
                poses: [headPose(9.06, 0.005, 0, -0.045)])
    head.update(originFromDevice: transform(), clock: 9.12,
                poses: [headPose(9.12, 0.009, 0.003, -0.115)])
    head.update(originFromDevice: transform(), clock: 9.13,
                poses: [headPose(9.12, 0.009, 0.003, -0.115)])
    check(head.consume(allowed: true, reference: .head) == .punch
            && head.consume(allowed: true, reference: .head) == [],
          "the immersive head route still punches once across compositor frames")
    var headLoss = SpatialAttackMotionRouter()
    headLoss.update(originFromDevice: transform(), clock: 9.00, poses: [headPose(9.00)])
    headLoss.update(originFromDevice: nil, clock: 9.06, poses: [headPose(9.06, 0, 0, -0.045)])
    headLoss.update(originFromDevice: transform(), clock: 9.12,
                    poses: [headPose(9.12, 0, 0, -0.115)])
    check(headLoss.consume(allowed: true, reference: .head) == [],
          "a missing compositor head pose clears the immersive stroke")

    var handoff = SpatialAttackMotionRouter()
    handoff.update(originFromDevice: transform(), clock: 10.00, poses: [headPose(10.00)])
    handoff.update(originFromDevice: transform(), clock: 10.06,
                   poses: [headPose(10.06, 0, 0, -0.045)])
    check(windowFrame(&handoff, clock: 10.12, [aimPose(10.12, 0, 0, -0.115)]) == [],
          "leaving the immersive space discards head-referenced motion before the window route")
    var competing = SpatialAttackMotionRouter()
    _ = windowFrame(&competing, clock: 11.00, [aimPose(11.00)])
    competing.updateAccessoryAim(clock: 11.10, poses: [aimPose(11.10, 0, 0, -0.115)])
    check(competing.consume(allowed: true, reference: .head) == []
            && competing.consume(allowed: true, reference: .accessoryAim) == [],
          "the immersive route never drains or later re-delivers window-route attacks")
}

private enum LiftRoute {
    case window
    case head(simd_float4x4)
}

/// A measured Sense half whose anchor origin sits at `height` above a resting point in
/// gravity-aligned origin space. Its aim location rides 5 cm along its own pointing ray.
private func liftPose(_ time: TimeInterval, _ height: Float, id: UUID,
                      x: Float = 0, z: Float = 0,
                      rotation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)),
                      tracked: Bool = true, timestamp: TimeInterval? = nil)
    -> SpatialAccessoryPoseSample {
    var accessory = simd_float4x4(rotation)
    accessory.columns.3 = SIMD4((id == senseLeft ? -0.2 : 0.2) + x, 1.0 + height, -0.4 + z, 1)
    return .init(accessoryID: id, timestamp: timestamp ?? time, isPositionTracked: tracked,
                 originFromAccessory: accessory,
                 originFromAim: accessory * transform(translation: SIMD3(0, 0, -0.05)))
}

private func liftFrame(_ router: inout SpatialAttackMotionRouter, _ route: LiftRoute,
                       clock: TimeInterval, _ poses: [SpatialAccessoryPoseSample],
                       allowed: Bool = true) -> SpatialAttackGesture {
    switch route {
    case .window:
        return windowFrame(&router, clock: clock, poses, allowed: allowed, now: clock)
    case .head(let originFromDevice):
        router.update(originFromDevice: originFromDevice, clock: clock, poses: poses)
        return router.consume(allowed: allowed, reference: .head, now: clock)
    }
}

/// Heights from `start` to `end` over `frames` frames, excluding `start`.
private func ramp(_ start: Float, _ end: Float, _ frames: Int) -> [Float] {
    (1...frames).map { start + (end - start) * Float($0) / Float(frames) }
}

private let liftStep: TimeInterval = 0.02
/// Rest, then a 0.8 m/s lift to 16 cm, then a hold.
private let quickLift: [Float] = [0, 0] + ramp(0, 0.16, 10) + Array(repeating: 0.16, count: 15)

/// Runs both halves through per-frame heights; a nil entry omits that half from the frame.
private func liftRun(_ route: LiftRoute, left: [Float?], right: [Float?],
                     start: TimeInterval = 20, router: inout SpatialAttackMotionRouter,
                     leftRotation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)),
                     rightRotation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)),
                     allowed: (Int) -> Bool = { _ in true }) -> [SpatialAttackGesture] {
    (0..<max(left.count, right.count)).map { index in
        let time = start + Double(index) * liftStep
        var poses: [SpatialAccessoryPoseSample] = []
        if index < left.count, let height = left[index] {
            poses.append(liftPose(time, height, id: senseLeft, rotation: leftRotation))
        }
        if index < right.count, let height = right[index] {
            poses.append(liftPose(time, height, id: senseRight, rotation: rightRotation))
        }
        return liftFrame(&router, route, clock: time, poses, allowed: allowed(index))
    }
}

private func liftRun(_ route: LiftRoute, left: [Float?], right: [Float?],
                     leftRotation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)),
                     rightRotation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)),
                     allowed: @escaping (Int) -> Bool = { _ in true })
    -> [SpatialAttackGesture] {
    var router = SpatialAttackMotionRouter()
    return liftRun(route, left: left, right: right, router: &router,
                   leftRotation: leftRotation, rightRotation: rightRotation, allowed: allowed)
}

/// Frames on which a Cross press starts, so a held jump counts once.
private func jumpPresses(_ frames: [SpatialAttackGesture]) -> [Int] {
    frames.indices.filter {
        frames[$0].contains(.jump) && ($0 == 0 || !frames[$0 - 1].contains(.jump))
    }
}

private func jumpChecks() {
    let lookingDown = simd_float4x4(simd_quatf(angle: -.pi / 3, axis: SIMD3(1, 0, 0)))
    let routes: [(String, LiftRoute)] = [
        ("window", .window), ("immersive", .head(transform())),
        ("immersive looking down", .head(lookingDown)),
    ]
    let rest = Array(repeating: Float(0), count: quickLift.count)

    for (name, route) in routes {
        let paired = liftRun(route, left: quickLift, right: quickLift)
        check(jumpPresses(paired).count == 1 && paired.allSatisfy { $0 == [] || $0 == .jump },
              "\(name): a quick lift of both halves emits exactly one Cross pulse")
        check(jumpPresses(paired).first.map { $0 <= 9 } == true,
              "\(name): the jump fires during the lift, not after the hold")

        let twice = [Float(0), 0] + ramp(0, 0.16, 10) + ramp(0.16, 0.04, 8)
            + ramp(0.04, 0.20, 10) + Array(repeating: 0.20, count: 15)
        let repeated = jumpPresses(liftRun(route, left: twice, right: twice))
        check(repeated.count == 2 && repeated[1] - repeated[0] >= 2
                && Double(repeated[1] - repeated[0]) * liftStep <= 0.60,
              "\(name): lowering and lifting both again emits a second, separate pulse")

        check(jumpPresses(liftRun(route, left: quickLift, right: rest)).isEmpty
                && jumpPresses(liftRun(route, left: rest, right: quickLift)).isEmpty,
              "\(name): lifting either single half never jumps")
        let lowering = Array(quickLift.reversed())
        check(jumpPresses(liftRun(route, left: lowering, right: lowering)).isEmpty,
              "\(name): lowering both halves never jumps")
    }

    var sameID = SpatialAttackMotionRouter()
    var sameIDEvents: SpatialAttackGesture = []
    for (index, height) in quickLift.enumerated() {
        let time = 30 + Double(index) * liftStep
        sameIDEvents.formUnion(windowFrame(&sameID, clock: time, [
            liftPose(time - 0.005, height, id: senseLeft),
            liftPose(time, height, id: senseLeft),
        ]))
    }
    check(!sameIDEvents.contains(.jump), "one half reported twice per frame cannot pair with itself")

    let delayed = Array(repeating: Float(0), count: 8) + quickLift
    check(jumpPresses(liftRun(.window, left: quickLift, right: delayed)).isEmpty
            && jumpPresses(liftRun(.head(transform()), left: delayed, right: quickLift)).isEmpty,
          "lifts that start 160 ms apart are not one paired jump")
    let slow = [Float(0)] + ramp(0, 0.16, 20)
    check(jumpPresses(liftRun(.window, left: slow, right: slow)).isEmpty,
          "a 0.4 m/s lift of both halves is too slow to jump")
    var scoop = SpatialAttackMotionRouter()
    var scoopEvents: SpatialAttackGesture = []
    for (index, height) in ([Float(0)] + ramp(0, 0.12, 8)).enumerated() {
        let time = 39 + Double(index) * liftStep
        scoopEvents.formUnion(windowFrame(&scoop, clock: time, [
            liftPose(time, height, id: senseLeft, z: -1.6 * height),
            liftPose(time, height, id: senseRight, z: -1.6 * height),
        ]))
    }
    check(!scoopEvents.contains(.jump), "a mostly forward scoop of both halves never jumps")
    let small = [Float(0)] + ramp(0, 0.06, 5) + Array(repeating: 0.06, count: 10)
    check(jumpPresses(liftRun(.window, left: small, right: small)).isEmpty,
          "a fast 6 cm twitch of both halves never jumps")
    let noise: [Float] = (0..<40).map { $0.isMultiple(of: 2) ? 0.008 : -0.008 }
    check(jumpPresses(liftRun(.head(transform()), left: noise, right: noise)).isEmpty,
          "tracked jitter on both halves never jumps")
    let held = Array(repeating: Float(0.16), count: 30)
    check(jumpPresses(liftRun(.window, left: quickLift + held, right: quickLift + held)).count == 1,
          "holding both halves up emits one pulse only")

    // Horizontal jabs and shakes keep their own buttons and never jump.
    var jab = SpatialAttackMotionRouter()
    var jabEvents: SpatialAttackGesture = []
    for (index, z) in ([Float(0)] + ramp(0, -0.16, 8)).enumerated() {
        let time = 40 + Double(index) * liftStep
        jabEvents.formUnion(windowFrame(&jab, clock: time, [
            liftPose(time, 0, id: senseLeft, z: z), liftPose(time, 0, id: senseRight, z: z),
        ]))
    }
    check(jabEvents == .punch, "a paired forward jab punches without jumping")
    var shake = SpatialAttackMotionRouter()
    var shakeEvents: SpatialAttackGesture = []
    for (index, x) in ([Float(0)] + ramp(0, 0.08, 5) + ramp(0.08, 0, 5)).enumerated() {
        let time = 41 + Double(index) * liftStep
        shakeEvents.formUnion(windowFrame(&shake, clock: time, [
            liftPose(time, 0, id: senseLeft, x: x), liftPose(time, 0, id: senseRight, x: x),
        ]))
    }
    check(shakeEvents == .spin, "a paired lateral shake spins without jumping")

    var rotation = SpatialAttackMotionRouter()
    var rotationEvents: SpatialAttackGesture = []
    for index in 0..<20 {
        let time = 42 + Double(index) * liftStep
        let pitch = simd_quatf(angle: Float(index) * 0.12, axis: SIMD3(1, 0, 0))
        rotationEvents.formUnion(windowFrame(&rotation, clock: time, [
            liftPose(time, 0, id: senseLeft, rotation: pitch),
            liftPose(time, 0, id: senseRight, rotation: pitch),
        ]))
    }
    check(!rotationEvents.contains(.jump), "pitching both halves upward in place never jumps")

    var headOnly = SpatialAttackMotionRouter()
    var headEvents: SpatialAttackGesture = []
    for index in 0..<20 {
        let time = 43 + Double(index) * liftStep
        var head = simd_float4x4(simd_quatf(angle: Float(index) * -0.05, axis: SIMD3(1, 0, 0)))
        head.columns.3 = SIMD4(0, 1.6 + Float(index) * 0.016, 0, 1)
        headOnly.update(originFromDevice: head, clock: time,
                        poses: [liftPose(time, 0, id: senseLeft), liftPose(time, 0, id: senseRight)])
        headEvents.formUnion(headOnly.consume(allowed: true, reference: .head))
    }
    check(headEvents.isEmpty, "rising or nodding the head alone never jumps")

    for (name, angle, axis) in [("pitched down", -Float.pi / 3, SIMD3<Float>(1, 0, 0)),
                                ("rolled", Float.pi / 2, SIMD3<Float>(0, 0, 1))] {
        let turned = simd_quatf(angle: angle, axis: axis)
        let opposite = simd_quatf(angle: -angle, axis: axis)
        check(jumpPresses(liftRun(.window, left: quickLift, right: quickLift,
                                 leftRotation: turned, rightRotation: opposite)).count == 1
                && jumpPresses(liftRun(.head(transform()), left: quickLift, right: quickLift,
                                      leftRotation: turned, rightRotation: opposite)).count == 1,
              "lifting halves \(name) still jumps once in both routes")
    }

    // Suppression, tracking loss, and route changes discard partial and pending jumps.
    check(jumpPresses(liftRun(.window, left: quickLift, right: quickLift,
                             allowed: { !(4...12).contains($0) })).isEmpty
            && jumpPresses(liftRun(.head(transform()), left: quickLift, right: quickLift,
                                  allowed: { !(4...12).contains($0) })).isEmpty,
          "a menu or pause frame during the lift discards it instead of jumping later")

    var untracked = SpatialAttackMotionRouter()
    var untrackedEvents: [SpatialAttackGesture] = []
    for (index, height) in quickLift.enumerated() {
        let time = 50 + Double(index) * liftStep
        untrackedEvents.append(windowFrame(&untracked, clock: time, [
            liftPose(time, height, id: senseLeft, tracked: !(5...6).contains(index)),
            liftPose(time, height, id: senseRight),
        ]))
    }
    check(jumpPresses(untrackedEvents).isEmpty,
          "losing position tracking on one half mid-lift discards the pair")

    let dropped: [Float?] = quickLift.enumerated().map { (5...6).contains($0.offset) ? nil : $0.element }
    check(jumpPresses(liftRun(.head(transform()), left: dropped, right: quickLift)).isEmpty,
          "a half that disappears mid-lift needs a fresh baseline")

    var stale = SpatialAttackMotionRouter()
    var staleEvents: SpatialAttackGesture = []
    for (index, height) in quickLift.enumerated() {
        let time = 60 + Double(index) * liftStep
        let anchorTime = index >= 5 && index <= 12 ? 60 + 4 * liftStep : time
        staleEvents.formUnion(windowFrame(&stale, clock: time, [
            liftPose(time, index >= 5 && index <= 12 ? quickLift[4] : height, id: senseLeft,
                     timestamp: anchorTime),
            liftPose(time, height, id: senseRight),
        ]))
    }
    check(!staleEvents.contains(.jump), "a half whose anchor stops updating cannot complete a pair")

    var clockGap = SpatialAttackMotionRouter()
    var gapEvents: [SpatialAttackGesture] = []
    for (index, height) in quickLift.enumerated() {
        let time = 70 + Double(index) * liftStep + (index >= 6 ? 0.2 : 0)
        gapEvents.append(windowFrame(&clockGap, clock: time, [
            liftPose(time, height, id: senseLeft), liftPose(time, height, id: senseRight),
        ]))
    }
    check(jumpPresses(gapEvents).isEmpty, "a stalled frame clock mid-lift discards the pair")

    var backwards = SpatialAttackMotionRouter()
    var backwardsEvents: SpatialAttackGesture = []
    for (index, height) in quickLift.enumerated() {
        let time = 80 + Double(index) * liftStep
        backwardsEvents.formUnion(windowFrame(&backwards, clock: index == 6 ? time - 0.05 : time, [
            liftPose(time, height, id: senseLeft), liftPose(time, height, id: senseRight),
        ]))
    }
    check(!backwardsEvents.contains(.jump), "a backwards frame clock mid-lift discards the pair")

    var nonFinite = SpatialAttackMotionRouter()
    var nonFiniteEvents: SpatialAttackGesture = []
    for (index, height) in quickLift.enumerated() {
        let time = 85 + Double(index) * liftStep
        var left = liftPose(time, height, id: senseLeft)
        if index == 6 {
            var origin = left.originFromAccessory
            origin.columns.3.y = .nan
            left = .init(accessoryID: senseLeft, timestamp: time, isPositionTracked: true,
                         originFromAccessory: origin, originFromAim: left.originFromAim)
        }
        nonFiniteEvents.formUnion(windowFrame(&nonFinite, clock: time,
                                              [left, liftPose(time, height, id: senseRight)]))
    }
    check(!nonFiniteEvents.contains(.jump), "a non-finite anchor origin mid-lift discards the pair")

    var handoff = SpatialAttackMotionRouter()
    var handoffEvents: SpatialAttackGesture = []
    for (index, height) in quickLift.enumerated() {
        let time = 90 + Double(index) * liftStep
        let poses = [liftPose(time, height, id: senseLeft), liftPose(time, height, id: senseRight)]
        handoffEvents.formUnion(index < 6
            ? liftFrame(&handoff, .head(transform()), clock: time, poses)
            : liftFrame(&handoff, .window, clock: time, poses))
    }
    check(!handoffEvents.contains(.jump), "leaving the immersive space mid-lift discards the pair")

    let relift = Array(repeating: Float(0.16), count: 5) + ramp(0.16, 0.0, 10) + quickLift
    check(jumpPresses(liftRun(.window, left: relift, right: relift, start: 51.0,
                             router: &untracked)).count == 1,
          "after tracking returns, a fresh paired lift jumps once")

    // A jump recognized by compositor updates but not yet drained is dropped by a suppressed
    // frame, and a fresh lift still works afterwards.
    var reacquire = SpatialAttackMotionRouter()
    for (index, height) in quickLift.prefix(13).enumerated() {
        let time = 100 + Double(index) * liftStep
        reacquire.update(originFromDevice: transform(), clock: time, poses: [
            liftPose(time, height, id: senseLeft), liftPose(time, height, id: senseRight),
        ])
    }
    var control = reacquire
    check(control.consume(allowed: true, reference: .head) == .jump,
          "compositor updates alone leave one undrained jump pending")
    // A half whose next anchor arrives after more than the sample gap clears the undrained jump.
    func hold(_ router: inout SpatialAttackMotionRouter, leftTimestamp: TimeInterval) {
        router.update(originFromDevice: transform(), clock: 100.30, poses: [
            liftPose(100.30, 0.16, id: senseLeft, timestamp: leftTimestamp),
            liftPose(100.30, 0.16, id: senseRight),
        ])
        router.update(originFromDevice: transform(), clock: 100.37, poses: [
            liftPose(100.37, 0.16, id: senseLeft), liftPose(100.37, 0.16, id: senseRight),
        ])
    }
    var skipped = reacquire
    hold(&skipped, leftTimestamp: 100.24)
    var unskipped = reacquire
    hold(&unskipped, leftTimestamp: 100.30)
    check(unskipped.consume(allowed: true, reference: .head) == .jump
            && skipped.consume(allowed: true, reference: .head) == [],
          "a participant's anchor gap clears a jump that was not yet drained")
    let suppressed = reacquire.consume(allowed: false, reference: .head)
    let afterSuppression = liftRun(.head(transform()), left: held, right: held, start: 100.26,
                                   router: &reacquire)
    let fresh = liftRun(.head(transform()), left: quickLift.map { $0 + 0.16 },
                        right: quickLift.map { $0 + 0.16 }, start: 100.86, router: &reacquire)
    check(suppressed == [] && jumpPresses(afterSuppression).isEmpty && jumpPresses(fresh).count == 1,
          "a suppressed frame never replays a jump, and a fresh lift jumps afterwards")

}

/// Height over elapsed time, piecewise linear through `(time, height)` keys and flat outside them.
private func heightProfile(_ keys: [(TimeInterval, Float)])
    -> @Sendable (TimeInterval) -> Float {
    { time in
        guard let upper = keys.firstIndex(where: { $0.0 > time }) else { return keys.last!.1 }
        guard upper > 0 else { return keys[0].1 }
        let (t0, h0) = keys[upper - 1]
        let (t1, h1) = keys[upper]
        return h0 + (h1 - h0) * Float((time - t0) / (t1 - t0))
    }
}

/// A quick 0.8 m/s paired lift to 16 cm, then the arms stay up for a second.
private let heldLift = heightProfile([(0, 0), (0.04, 0), (0.24, 0.16), (1.4, 0.16)])
/// Lift, lower 12 cm, lift again, then hold.
private let doubleLift = heightProfile([(0, 0), (0.04, 0), (0.24, 0.16), (0.40, 0.04),
                                        (0.60, 0.20), (1.4, 0.20)])

private struct ConsumedFrame {
    let time: TimeInterval
    let gestures: SpatialAttackGesture
}

/// Per-tick deviations from a clean run, applied only on the tick that requests them.
private struct TickEvent {
    var omitRight = false
    var untrackRight = false
    var allowed = true
    var resetBefore = false
    var otherRoute = false
    var produce = true
    var consumerTime: TimeInterval?
}

/// Producer ticks at `rate`. The window route samples only on game frames, as its adapter does;
/// the immersive route ingests every compositor tick and drains on the game frames `consumes`
/// schedules. Consumer time is the tick time unless an event overrides it.
private func steppedRun(_ route: LiftRoute, rate: Double, duration: TimeInterval = 1.4,
                        profile: (TimeInterval) -> Float = heldLift,
                        router: inout SpatialAttackMotionRouter,
                        consumes: (Int) -> Bool = { _ in true },
                        event: (Int) -> TickEvent = { _ in TickEvent() }) -> [ConsumedFrame] {
    let start: TimeInterval = 200
    var frames: [ConsumedFrame] = []
    for tick in 0..<Int(duration * rate) {
        let time = start + Double(tick) / rate
        let change = event(tick)
        if change.resetBefore { router.reset() }
        let height = profile(time - start)
        var poses = [liftPose(time, height, id: senseLeft)]
        if !change.omitRight {
            poses.append(liftPose(time, height, id: senseRight, tracked: !change.untrackRight))
        }
        let consumerTime = change.consumerTime ?? time
        var window = false
        if case .window = route { window = true }
        if change.otherRoute { window.toggle() }
        if window {
            guard consumes(tick) else { continue }
            if change.allowed, change.produce { router.updateAccessoryAim(clock: time, poses: poses) }
            frames.append(.init(time: time, gestures: router.consume(
                allowed: change.allowed, reference: .accessoryAim, now: consumerTime)))
        } else {
            if change.produce {
                router.update(originFromDevice: transform(), clock: time, poses: poses)
            }
            guard consumes(tick) else { continue }
            frames.append(.init(time: time, gestures: router.consume(
                allowed: change.allowed, reference: .head, now: consumerTime)))
        }
    }
    return frames
}

/// Each Cross press as its first held frame time and the first released frame time after it.
private func pressSpans(_ frames: [ConsumedFrame]) -> [(start: TimeInterval, end: TimeInterval?)] {
    var spans: [(start: TimeInterval, end: TimeInterval?)] = []
    for (index, frame) in frames.enumerated() {
        let held = frame.gestures.contains(.jump)
        let wasHeld = index > 0 && frames[index - 1].gestures.contains(.jump)
        if held, !wasHeld { spans.append((frame.time, nil)) }
        if !held, wasHeld { spans[spans.count - 1].end = frame.time }
    }
    return spans
}

private func heldFor(_ span: (start: TimeInterval, end: TimeInterval?)) -> TimeInterval? {
    span.end.map { $0 - span.start }
}

private func jumpHoldChecks() {
    let hold = SpatialAttackMotionRouter.jumpHoldDuration
    // (name, producer tick rate, longest gap between game frames, game-frame ticks)
    let gameRates: [(String, Double, TimeInterval, (Int) -> Bool)] = [
        ("90 Hz", 90, 1.0 / 90, { _ in true }),
        // 60 Hz game frames scheduled on 90 Hz compositor ticks: two of every three ticks.
        ("60 Hz on 90 Hz ticks", 90, 2.0 / 90,
         { $0 == 0 || ($0 * 2) / 3 != (($0 - 1) * 2) / 3 }),
        ("60 Hz", 60, 1.0 / 60, { _ in true }),
    ]
    for (rateName, rate, frameGap, consumes) in gameRates {
        for (routeName, route) in [("window", LiftRoute.window), ("immersive", .head(transform()))] {
            let name = "\(routeName) \(rateName)"
            var router = SpatialAttackMotionRouter()
            let clean = steppedRun(route, rate: rate, router: &router, consumes: consumes)
            let spans = pressSpans(clean)
            check(spans.count == 1 && heldFor(spans[0]).map {
                      $0 >= 0.10 && $0 >= hold && $0 <= hold + frameGap + 1e-9 } == true,
                  "\(name): a paired lift holds Cross >= 0.10 s, then releases on its own")
            check(clean.allSatisfy { $0.gestures == [] || $0.gestures == .jump },
                  "\(name): the held jump carries no Square or Circle")

            var repeated = SpatialAttackMotionRouter()
            let twice = pressSpans(steppedRun(route, rate: rate, profile: doubleLift,
                                              router: &repeated, consumes: consumes))
            check(twice.count == 2 && twice.allSatisfy { heldFor($0).map { $0 >= 0.10 } == true }
                    && twice[1].start > twice[0].end!,
                  "\(name): lowering and lifting again gives a second held press after a release")

            guard let pressTick = clean.first(where: { $0.gestures.contains(.jump) })
                .map({ Int((($0.time - 200) * rate).rounded()) }) else { continue }
            let cancelTick = pressTick + 3
            let cancelTime = 200 + Double(cancelTick) / rate
            let cancels: [(String, TickEvent)] = [
                ("a missing half", TickEvent(omitRight: true)),
                ("lost tracking", TickEvent(untrackRight: true)),
                ("a menu frame", TickEvent(allowed: false)),
                ("a router reset", TickEvent(resetBefore: true)),
                ("a route change", TickEvent(otherRoute: true)),
                ("a backwards consumer clock", TickEvent(consumerTime: cancelTime - 0.05)),
                ("a non-finite consumer clock", TickEvent(consumerTime: .nan)),
            ]
            for (cause, change) in cancels {
                var cancelled = SpatialAttackMotionRouter()
                let frames = steppedRun(route, rate: rate, router: &cancelled,
                                        consumes: { $0 == cancelTick || consumes($0) },
                                        event: { $0 == cancelTick ? change : TickEvent() })
                let spans = pressSpans(frames)
                check(spans.count == 1 && spans[0].end.map { abs($0 - cancelTime) < 1e-9 } == true,
                      "\(name): \(cause) releases a held jump at once and never re-presses it")
            }

            var stopped = SpatialAttackMotionRouter()
            let stoppedSpans = pressSpans(steppedRun(
                route, rate: rate, router: &stopped, consumes: consumes,
                event: { $0 > pressTick ? TickEvent(produce: false) : TickEvent() }))
            check(stoppedSpans.count == 1 && heldFor(stoppedSpans[0]).map {
                      $0 >= hold && $0 <= hold + frameGap + 1e-9 } == true,
                  "\(name): a stopped pose producer cannot extend or replay a held jump")
        }
    }

    // Two jumps recognized before any game frame: regular 60 Hz frames deliver two held presses
    // with a release between; a stalled consumer drops the stale second one instead.
    func queuedTwo() -> SpatialAttackMotionRouter {
        var router = SpatialAttackMotionRouter()
        let fast = [Float(0), 0] + ramp(0, 0.16, 10) + ramp(0.16, 0.04, 6) + ramp(0.04, 0.20, 10)
        for (index, height) in fast.enumerated() {
            let time = 110 + Double(index) * 0.01
            router.update(originFromDevice: transform(), clock: time, poses: [
                liftPose(time, height, id: senseLeft), liftPose(time, height, id: senseRight),
            ])
        }
        return router
    }
    var regular = queuedTwo()
    let regularFrames = (0..<30).map { index -> ConsumedFrame in
        let time = 110.28 + Double(index) / 60
        return .init(time: time, gestures: regular.consume(allowed: true, reference: .head,
                                                           now: time))
    }
    let queued = pressSpans(regularFrames)
    check(queued.count == 2 && queued.allSatisfy { heldFor($0).map { $0 >= 0.10 } == true }
            && queued[1].start > queued[0].end!,
          "a queued second jump starts only after the first hold has a released frame")
    var stalled = queuedTwo()
    let stalledFrames = [110.28, 110.78, 110.80, 110.82].map {
        stalled.consume(allowed: true, reference: .head, now: $0)
    }
    check(stalledFrames == [.jump, [], [], []],
          "after a stalled consumer, a stale queued jump is dropped instead of replayed")
}

private let shakeHold: TimeInterval = 0.5

/// Per-frame offsets at `rate` along a cosine-eased path through `(seconds, target)` legs that
/// starts from rest at zero, then holds the final target for `shakeHold`.
private func easedPath(_ legs: [(TimeInterval, Float)], rest: TimeInterval = 0.1,
                       rate: Double = 90) -> [Float] {
    var offsets = Array(repeating: Float(0), count: Int((rest * rate).rounded()))
    var from: Float = 0
    for (duration, target) in legs {
        let frames = max(1, Int((duration * rate).rounded()))
        offsets += (1...frames).map { frame in
            from + (target - from) * (1 - cos(.pi * Float(frame) / Float(frames))) / 2
        }
        from = target
    }
    return offsets + Array(repeating: from, count: Int((shakeHold * rate).rounded()))
}

/// `legs` alternating out-and-back legs of `leg` metres at an average `speed`.
private func shakePath(leg: Float, speed: Float, legs: Int = 2, direction: Float = 1,
                       rest: TimeInterval = 0.1, rate: Double = 90) -> [Float] {
    easedPath((0..<legs).map { (TimeInterval(leg / speed), $0.isMultiple(of: 2) ? direction * leg : 0) },
              rest: rest, rate: rate)
}

/// One sideways-and-back gesture: `leg` metres out at `out` m/s, an optional pause at the turn,
/// then back to the start at `back` m/s.
private func outAndBack(leg: Float, out: Float, pause: TimeInterval = 0, back: Float? = nil,
                        direction: Float = 1, rest: TimeInterval = 0.1,
                        rate: Double = 90) -> [Float] {
    var legs: [(TimeInterval, Float)] = [(TimeInterval(leg / out), direction * leg)]
    if pause > 0 { legs.append((pause, direction * leg)) }
    legs.append((TimeInterval(leg / (back ?? out)), 0))
    return easedPath(legs, rest: rest, rate: rate)
}

private func recognizerRun(_ offsets: [Float], rate: Double = 90,
                           configuration: SpatialAttackGestureRecognizer.Configuration
                            = .experimental) -> [SpatialAttackGesture] {
    var recognizer = SpatialAttackGestureRecognizer(configuration: configuration)
    return offsets.enumerated().map { index, offset in
        recognizer.update(sample(Double(index) / rate, offset))
    }
}

/// Moves one Sense half (or both) along `axis`, expressed in the route's reference axes, while
/// any other half stays tracked and still.
private func shakeRun(_ route: LiftRoute, offsets: [Float], axis: SIMD3<Float> = SIMD3(1, 0, 0),
                      id: UUID = senseLeft, both: Bool = false,
                      rate: Double = 90) -> [SpatialAttackGesture] {
    var router = SpatialAttackMotionRouter()
    let other = id == senseLeft ? senseRight : senseLeft
    return offsets.enumerated().map { index, offset in
        let time = 300 + Double(index) / rate
        let local = axis * offset
        let poses: [SpatialAccessoryPoseSample]
        switch route {
        case .window:
            poses = [aimPose(time, local.x, local.y, local.z, id: id),
                     both ? aimPose(time, local.x, local.y, local.z, id: other)
                          : aimPose(time, id: other)]
        case .head(let originFromDevice):
            let world = originFromDevice * SIMD4(local, 0)
            poses = [headPose(time, world.x, world.y, world.z, id: id),
                     both ? headPose(time, world.x, world.y, world.z, id: other)
                          : headPose(time, id: other)]
        }
        return liftFrame(&router, route, clock: time, poses)
    }
}

/// Exactly one Circle press and nothing else, delivered before the hand settles.
private func spinsOnce(_ frames: [SpatialAttackGesture], path: [Float], rate: Double = 90) -> Bool {
    let attacks = frames.indices.filter { !frames[$0].isEmpty }
    return attacks.count == 1 && frames[attacks[0]] == .spin
        && attacks[0] < path.count - Int((shakeHold * rate).rounded())
}

private func shakeChecks() {
    // Build 244 tuning: 60 mm legs at 0.45 m/s with a 0.34 s reversal.
    let previous = SpatialAttackGestureRecognizer.Configuration(
        shakeStrokeWindow: 0.28, shakeReversalWindow: 0.34,
        shakeMinimumStrokeDistance: 0.060, shakeMinimumSpeed: 0.45)
    let gentle = shakePath(leg: 0.040, speed: 0.20)
    check(recognizerRun(gentle, configuration: previous).allSatisfy(\.isEmpty)
            && spinsOnce(recognizerRun(gentle), path: gentle),
          "a relaxed 40 mm, 0.2 m/s shake the previous tuning ignored now spins")

    // The hand may start moving at any point relative to the recognizer's own resets.
    for (name, leg, speed) in [("40 mm at 0.20 m/s", Float(0.040), Float(0.20)),
                               ("40 mm at 0.25 m/s", 0.040, 0.25),
                               ("35 mm at 0.20 m/s", 0.035, 0.20)] {
        for rate in [90.0, 60.0] {
            var missed: [String] = []
            for restStep in 0...15 {
                for direction: Float in [1, -1] {
                    let rest = Double(restStep) * 0.02
                    let path = shakePath(leg: leg, speed: speed, direction: direction,
                                         rest: rest, rate: rate)
                    if !spinsOnce(recognizerRun(path, rate: rate), path: path, rate: rate) {
                        missed.append("rest \(rest) s dir \(direction)")
                    }
                }
            }
            check(missed.isEmpty, "\(name) at \(Int(rate)) Hz spins once from every start phase"
                    + (missed.isEmpty ? "" : "; missed \(missed)"))
        }
    }

    let routes: [(String, LiftRoute)] = [
        ("window", .window), ("immersive", .head(transform())),
        ("immersive turned", .head(transform(yaw: .pi / 2))),
    ]
    for (routeName, route) in routes {
        for (handName, id) in [("left", senseLeft), ("right", senseRight)] {
            check([Float(1), -1].allSatisfy { direction in
                      let path = shakePath(leg: 0.040, speed: 0.20, direction: direction)
                      return spinsOnce(shakeRun(route, offsets: path, id: id), path: path)
                  },
                  "\(routeName): a relaxed 40 mm shake of the \(handName) half spins once either way")
        }
    }

    let lateral = SIMD3<Float>(1, 0, 0)
    let jitter: (Int) -> Float = { $0.isMultiple(of: 2) ? 0.003 : -0.003 }
    let rejected: [(String, [Float], SIMD3<Float>)] = [
        ("a one-sided 40 mm sweep", easedPath([(0.20, 0.040)]), lateral),
        ("a long one-sided 150 mm sweep", easedPath([(0.50, 0.150)]), lateral),
        ("a 40 mm sweep that returns slowly", easedPath([(0.20, 0.040), (0.80, 0)]), lateral),
        // Only the speed floor rejects this lazy sway; only the return share rejects the reach.
        ("a lazy 0.06 m/s sway of 34 mm legs", shakePath(leg: 0.034, speed: 0.06, legs: 4), lateral),
        ("a 150 mm reach that snaps 40 mm back", easedPath([(0.60, 0.150), (0.15, 0.110)]), lateral),
        ("a quick 20 mm twitch out and back", easedPath([(0.05, 0.020), (0.05, 0)]), lateral),
        ("±10 mm tracked jitter", (0..<90).map { $0.isMultiple(of: 2) ? 0.010 : -0.010 }, lateral),
        ("a slow 0.06 m/s, 60 mm sway with ±3 mm jitter",
         easedPath([(1.0, 0.060), (1.0, 0), (1.0, 0.060), (1.0, 0)]).enumerated()
            .map { $1 + jitter($0) }, lateral),
        ("an 80 mm forward oscillation with 48 mm sideways",
         easedPath([(0.20, 0.080), (0.20, 0), (0.20, 0.080), (0.20, 0)]), SIMD3(0.6, 0, -1)),
        ("an 80 mm vertical oscillation with 48 mm sideways",
         easedPath([(0.20, 0.080), (0.20, 0), (0.20, 0.080), (0.20, 0)]), SIMD3(0.6, 1, 0)),
    ]
    for (name, path, axis) in rejected {
        check(routes.prefix(2).allSatisfy { shakeRun($0.1, offsets: path, axis: axis)
                                                .allSatisfy(\.isEmpty) },
              "window and immersive: \(name) never attacks")
    }

    let together = shakePath(leg: 0.040, speed: 0.20)
    check(routes.prefix(2).allSatisfy {
              spinsOnce(shakeRun($0.1, offsets: together, both: true), path: together)
          },
          "a relaxed shake of both halves together gives one Circle and no Cross")
    let continuous = shakePath(leg: 0.040, speed: 0.20, legs: 8)
    check(routes.prefix(2).allSatisfy { route in
              let frames = shakeRun(route.1, offsets: continuous)
              let spins = frames.indices.filter { !frames[$0].isEmpty }
              return spins.count >= 2 && spins.allSatisfy { frames[$0] == .spin }
                  && zip(spins, spins.dropFirst()).allSatisfy {
                      Double($1 - $0) / 90 >= SpatialAttackGestureRecognizer.Configuration
                          .experimental.attackCooldown
                  }
          },
          "continuous relaxed shaking keeps spinning, one Circle per cooldown")
    gentleShakeChecks(routes: routes)
}

/// The default one-hand spin is one small, unhurried sideways-and-back motion with either hand.
private func gentleShakeChecks(routes: [(String, LiftRoute)]) {
    // Representative gentle gestures. Build 245 missed each one: the first two are under its
    // 30 mm / 0.18 m/s floors, and it timed the return from the turn, so a pause failed the third.
    let gentle: [(String, Float, Float, TimeInterval, Float?)] = [
        ("25 mm at 0.14 m/s with a 0.12 s pause", 0.025, 0.14, 0.12, nil),
        ("30 mm at 0.12 m/s with a 0.20 s pause", 0.030, 0.12, 0.20, nil),
        ("35 mm at 0.20 m/s with a 0.15 s pause", 0.035, 0.20, 0.15, nil),
        ("25 mm out at 0.15 m/s and back at 0.12 m/s", 0.025, 0.15, 0, 0.12),
    ]
    for (name, leg, speed, pause, back) in gentle {
        for rate in [90.0, 60.0] {
            var missed: [String] = []
            for restStep in 0...15 {
                for direction: Float in [1, -1] {
                    let rest = Double(restStep) * 0.02
                    let path = outAndBack(leg: leg, out: speed, pause: pause, back: back,
                                          direction: direction, rest: rest, rate: rate)
                    if !spinsOnce(recognizerRun(path, rate: rate), path: path, rate: rate) {
                        missed.append("rest \(rest) s dir \(direction)")
                    }
                }
            }
            check(missed.isEmpty, "gentle \(name) at \(Int(rate)) Hz spins once from every start phase"
                    + (missed.isEmpty ? "" : "; missed \(missed)"))
        }
    }

    for (routeName, route) in routes {
        for (handName, id) in [("left", senseLeft), ("right", senseRight)] {
            for rate in [90.0, 60.0] {
                check([Float(1), -1].allSatisfy { direction in
                          let path = outAndBack(leg: 0.025, out: 0.14, pause: 0.12,
                                                direction: direction, rate: rate)
                          return spinsOnce(shakeRun(route, offsets: path, id: id, rate: rate),
                                           path: path, rate: rate)
                      },
                      "\(routeName) \(Int(rate)) Hz: a gentle 25 mm sideways-and-back of the "
                        + "\(handName) half spins once either way")
            }
        }
    }

    let lateral = SIMD3<Float>(1, 0, 0)
    let idle: [Float] = (0..<270).map { frame in
        0.03 * Float(frame) / 90 + (frame.isMultiple(of: 2) ? 0.0025 : -0.0025)
    }
    let thumbstick: [Float] = (0..<360).map { frame in
        let time = Float(frame) / 90
        return 0.015 * sin(2 * .pi * 0.5 * time) + 0.004 * sin(2 * .pi * 8 * time)
    }
    let rejected: [(String, [Float], SIMD3<Float>)] = [
        ("holding still with ±2.5 mm jitter and 0.03 m/s drift", idle, lateral),
        ("thumbstick play: ±4 mm 8 Hz tremor on a ±15 mm 0.5 Hz sway", thumbstick, lateral),
        ("a 0.08 m/s sway of 25 mm legs", shakePath(leg: 0.025, speed: 0.08, legs: 6), lateral),
        ("a quick 18 mm flick out and back", outAndBack(leg: 0.018, out: 0.20), lateral),
        ("a 100 mm sideways reach that bounces 35 mm back",
         easedPath([(0.30, 0.100), (0.15, 0.065)]), lateral),
        ("a 60 mm reach out and back over two seconds",
         easedPath([(0.30, 0.060), (1.40, 0.060), (0.30, 0)]), lateral),
        ("a 25 mm out-and-back that pauses 0.6 s at the turn",
         outAndBack(leg: 0.025, out: 0.14, pause: 0.60), lateral),
        ("a gentle 40 mm forward-and-back with 22 mm sideways",
         outAndBack(leg: 0.040, out: 0.14, pause: 0.12), SIMD3(0.55, 0, -1)),
        ("a gentle 40 mm up-and-down with 22 mm sideways",
         outAndBack(leg: 0.040, out: 0.14, pause: 0.12), SIMD3(0.55, 1, 0)),
    ]
    for (name, path, axis) in rejected {
        check(routes.prefix(2).allSatisfy { shakeRun($0.1, offsets: path, axis: axis)
                                                .allSatisfy(\.isEmpty) },
              "window and immersive: \(name) never attacks")
    }

    let continuous = (0..<6).reduce(into: [Float]()) { path, _ in
        path += outAndBack(leg: 0.025, out: 0.14, pause: 0.08, rest: 0).dropLast(45)
    }
    check(routes.prefix(2).allSatisfy { route in
              let frames = shakeRun(route.1, offsets: continuous)
              let spins = frames.indices.filter { !frames[$0].isEmpty }
              return spins.count >= 3 && spins.allSatisfy { frames[$0] == .spin }
                  && zip(spins, spins.dropFirst()).allSatisfy {
                      Double($1 - $0) / 90 >= SpatialAttackGestureRecognizer.Configuration
                          .experimental.attackCooldown
                  }
          },
          "repeated gentle out-and-backs give one Circle per gesture, never faster than cooldown")

    // Jabs and paired lifts keep their own buttons even with some sideways wobble.
    for (routeName, route) in routes.prefix(2) {
        var jab = SpatialAttackMotionRouter()
        var jabEvents: [SpatialAttackGesture] = []
        let jabPath = [Float(0), 0] + ramp(0, 1, 8) + ramp(1, 0, 12) + Array(repeating: 0, count: 20)
        for (index, amount) in jabPath.enumerated() {
            let time = 400 + Double(index) * liftStep
            jabEvents.append(liftFrame(&jab, route, clock: time, [
                liftPose(time, 0, id: senseRight, x: 0.020 * amount, z: -0.14 * amount),
                liftPose(time, 0, id: senseLeft),
            ]))
        }
        check(jabEvents.filter { !$0.isEmpty } == [.punch],
              "\(routeName): a one-hand jab with 20 mm sideways and its retraction punch once only")

        // Hands drift apart sideways by a quarter of the rise and back together as they lower.
        for (liftName, heights) in [("a paired lift", quickLift),
                                    ("a paired double lift", [Float(0), 0] + ramp(0, 0.16, 10)
                                        + ramp(0.16, 0.04, 8) + ramp(0.04, 0.20, 10)
                                        + Array(repeating: 0.20, count: 15))] {
            var lift = SpatialAttackMotionRouter()
            var liftEvents: [SpatialAttackGesture] = []
            for (index, height) in heights.enumerated() {
                let time = 410 + Double(index) * liftStep
                liftEvents.append(liftFrame(&lift, route, clock: time, [
                    liftPose(time, height, id: senseLeft, x: -0.25 * height),
                    liftPose(time, height, id: senseRight, x: 0.25 * height),
                ]))
            }
            check(!jumpPresses(liftEvents).isEmpty
                    && liftEvents.allSatisfy { !$0.contains(.spin) && !$0.contains(.punch) },
                  "\(routeName): \(liftName) that also spreads sideways jumps without Circle")
        }
    }
}

@main
private struct SpatialAttackGestureCheck {
    static func main() {
        var timestampGate = SpatialSampleTimestampGate()
        check(timestampGate.accepts(1.0)
                && !timestampGate.accepts(1.0)
                && !timestampGate.accepts(0.99)
                && timestampGate.accepts(1.01),
              "measured anchor timestamps are consumed once and must advance")

        var jab = SpatialAttackGestureRecognizer()
        check(jab.update(sample(0)) == [], "jab establishes a baseline")
        check(jab.update(sample(0.06, 0.005, 0, -0.045)) == [],
              "a partial forward movement does not punch")
        check(jab.update(sample(0.12, 0.009, 0.003, -0.115)) == .punch,
              "a fast dominant forward jab emits punch")
        check(jab.update(sample(0.20, 0, 0, 0)) == [],
              "the jab retraction never emits another punch")
        check(jab.update(sample(0.30, 0, 0, -0.115)) == [],
              "jab cooldown suppresses a quick repeat")
        _ = jab.update(sample(0.40, 0, 0, 0))
        _ = jab.update(sample(0.50, 0, 0, 0))
        check(jab.update(sample(0.60, 0, 0, -0.115)) == .punch,
              "retraction plus cooldown rearms a later jab")

        var crossAxisJab = SpatialAttackGestureRecognizer()
        _ = crossAxisJab.update(sample(0))
        check(crossAxisJab.update(sample(0.10, 0.10, 0, -0.11)) == [],
              "large lateral travel rejects a diagonal jab")

        var noise = SpatialAttackGestureRecognizer()
        var noiseEvents: SpatialAttackGesture = []
        for index in 0...10 {
            let time = Double(index) * 0.03
            let sign: Float = index.isMultiple(of: 2) ? 1 : -1
            noiseEvents.formUnion(noise.update(sample(time, sign * 0.006, 0.003, sign * 0.004)))
        }
        check(noiseEvents.isEmpty, "small tracked noise emits no attack")

        var shake = SpatialAttackGestureRecognizer()
        check(shake.update(sample(0)) == [], "shake establishes a baseline")
        check(shake.update(sample(0.10, 0.070)) == [],
              "one lateral stroke is not a spin")
        check(shake.update(sample(0.20, 0.000)) == .spin,
              "a fast lateral reversal emits spin")
        check(shake.update(sample(0.28, -0.075)) == [],
              "shake cooldown bounds the pulse to one frame")

        var crossAxisShake = SpatialAttackGestureRecognizer()
        _ = crossAxisShake.update(sample(0))
        _ = crossAxisShake.update(sample(0.10, 0.07, 0.08, 0))
        check(crossAxisShake.update(sample(0.20, 0, 0.16, 0)) == [],
              "vertical-dominant oscillation is not a lateral shake")

        var loss = SpatialAttackGestureRecognizer()
        _ = loss.update(sample(0))
        _ = loss.update(sample(0.10, 0.070))
        check(loss.update(sample(0.15, tracked: false)) == [],
              "tracking loss clears a partial stroke")
        _ = loss.update(sample(0.20, 0.070))
        check(loss.update(sample(0.30, 0.000)) == [],
              "motion before tracking loss cannot complete afterward")

        let leftID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let rightID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        var eitherHand = SpatialAttackGestureBank()
        _ = eitherHand.update(accessoryID: leftID, sample: sample(0))
        _ = eitherHand.update(accessoryID: rightID, sample: sample(0))
        check(eitherHand.update(accessoryID: leftID,
                                sample: sample(0.10, 0, 0, -0.11)) == .punch,
              "the left accessory can punch independently")
        _ = eitherHand.update(accessoryID: rightID, sample: sample(0.10, -0.07))
        check(eitherHand.update(accessoryID: rightID,
                                sample: sample(0.20, 0.00)) == .spin,
              "the right accessory can spin independently")

        let fixedAccessory = transform(translation: SIMD3(0.25, -0.10, -0.45))
        var headMotion = SpatialAccessoryMotionProjector()
        let initial = headMotion.update(originFromAccessory: fixedAccessory,
                                        originFromReference: transform())
        let afterTranslation = headMotion.update(
            originFromAccessory: fixedAccessory,
            originFromReference: transform(translation: SIMD3(0.20, 0, -0.15)))
        let afterYaw = headMotion.update(
            originFromAccessory: fixedAccessory,
            originFromReference: transform(translation: SIMD3(0.20, 0, -0.15), yaw: .pi / 2))
        let repeatedAnchor = headMotion.update(
            originFromAccessory: fixedAccessory,
            originFromReference: transform(translation: SIMD3(-0.10, 0.12, 0.08), yaw: -.pi / 3))
        check(initial == .zero && afterTranslation == .zero && afterYaw == .zero
                && repeatedAnchor == .zero,
              "head motion or a repeated anchor cannot move a stationary accessory")

        var rotatedAxes = SpatialAccessoryMotionProjector()
        let yawedHead = transform(yaw: .pi / 2)
        _ = rotatedAxes.update(originFromAccessory: transform(), originFromReference: yawedHead)
        let projected = rotatedAxes.update(
            originFromAccessory: transform(translation: SIMD3(-0.11, 0, 0)),
            originFromReference: yawedHead)
        check(projected.map { abs($0.z + 0.11) < 0.001 && abs($0.x) < 0.001 } == true,
              "accessory deltas rotate into the current head axes")

        routerChecks()
        shakeChecks()
        jumpChecks()
        jumpHoldChecks()

        if failures == 0 {
            print("spatial attack gesture checks passed")
        } else {
            print("spatial attack gesture checks failed: \(failures)")
            Foundation.exit(1)
        }
    }
}
#endif
