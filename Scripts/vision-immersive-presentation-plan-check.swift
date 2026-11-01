import simd

// Compiled together with GOALPad/Vision/Immersive/VisionImmersivePresentationPlan.swift and
// -D GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE by Scripts/run-vision-immersive-proof-check.sh.

private var failures = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("  ok   \(message)")
    } else {
        print("  FAIL \(message)")
        failures += 1
    }
}

private func near(_ a: Float, _ b: Float, _ tolerance: Float = 1e-4) -> Bool {
    abs(a - b) <= tolerance
}

private func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool {
    abs(a - b) <= tolerance
}

private func viewport(_ x: Double, _ y: Double, _ width: Double, _ height: Double)
    -> VisionImmersiveViewport {
    VisionImmersiveViewport(originX: x, originY: y, width: width, height: height,
                            nearDepth: 0, farDepth: 1)
}

private func mapping(_ texture: Int, _ slice: Int, _ viewport: VisionImmersiveViewport)
    -> VisionImmersiveViewMapping {
    VisionImmersiveViewMapping(textureIndex: texture, sliceIndex: slice, viewport: viewport)
}

private func shape(_ width: Int, _ height: Int, slices: Int = 1) -> VisionImmersiveTargetShape {
    VisionImmersiveTargetShape(width: width, height: height, sliceCount: slices)
}

private func ndc(_ clipFromQuad: simd_float4x4, _ x: Float, _ y: Float) -> SIMD3<Float> {
    let clip = clipFromQuad * SIMD4<Float>(x, y, 0, 1)
    return SIMD3<Float>(clip.x, clip.y, clip.z) / clip.w
}

private func checkPassPlanning() {
    print("Pass planning")
    let full = viewport(0, 0, 100, 80)
    let dedicated = VisionImmersivePassPlanner.passes(
        views: [mapping(0, 0, full), mapping(1, 0, full)],
        colorTargets: [shape(100, 80), shape(100, 80)],
        depthTargets: [shape(100, 80), shape(100, 80)]
    )
    check(dedicated == [
        VisionImmersivePass(textureIndex: 0, sliceIndex: 0, viewIndices: [0]),
        VisionImmersivePass(textureIndex: 1, sliceIndex: 0, viewIndices: [1]),
    ], "dedicated layout gives each eye its own texture pass")

    let layered = VisionImmersivePassPlanner.passes(
        views: [mapping(0, 0, full), mapping(0, 1, full)],
        colorTargets: [shape(100, 80, slices: 2)],
        depthTargets: [shape(100, 80, slices: 2)]
    )
    check(layered == [
        VisionImmersivePass(textureIndex: 0, sliceIndex: 0, viewIndices: [0]),
        VisionImmersivePass(textureIndex: 0, sliceIndex: 1, viewIndices: [1]),
    ], "layered layout gives each eye its own array slice")

    let shared = VisionImmersivePassPlanner.passes(
        views: [mapping(0, 0, viewport(0, 0, 100, 80)), mapping(0, 0, viewport(100, 0, 100, 80))],
        colorTargets: [shape(200, 80)],
        depthTargets: [shape(200, 80)]
    )
    check(shared == [VisionImmersivePass(textureIndex: 0, sliceIndex: 0, viewIndices: [0, 1])],
          "shared layout draws both side-by-side eyes inside one clearing pass")

    let mono = VisionImmersivePassPlanner.passes(
        views: [mapping(0, 0, full)], colorTargets: [shape(100, 80)], depthTargets: [shape(100, 80)]
    )
    check(mono == [VisionImmersivePass(textureIndex: 0, sliceIndex: 0, viewIndices: [0])],
          "a single-view drawable such as capture or Simulator still plans one pass")

    let rejected: [(String, [VisionImmersiveViewMapping], [VisionImmersiveTargetShape],
                    [VisionImmersiveTargetShape])] = [
        ("no views", [], [shape(100, 80)], [shape(100, 80)]),
        ("missing texture", [mapping(1, 0, full)], [shape(100, 80)], [shape(100, 80)]),
        ("2D texture asked for slice 1", [mapping(0, 1, full)], [shape(100, 80)],
         [shape(100, 80)]),
        ("viewport past the right edge", [mapping(0, 0, viewport(1, 0, 100, 80))],
         [shape(100, 80)], [shape(100, 80)]),
        ("empty viewport", [mapping(0, 0, viewport(0, 0, 0, 80))], [shape(100, 80)],
         [shape(100, 80)]),
        ("non-finite viewport", [mapping(0, 0, viewport(.nan, 0, 100, 80))], [shape(100, 80)],
         [shape(100, 80)]),
        ("overlapping eyes in one slice",
         [mapping(0, 0, viewport(0, 0, 100, 80)), mapping(0, 0, viewport(99, 0, 100, 80))],
         [shape(200, 80)], [shape(200, 80)]),
        ("depth texture size differs", [mapping(0, 0, full)], [shape(100, 80)],
         [shape(100, 79)]),
        ("depth texture missing", [mapping(0, 0, full), mapping(1, 0, full)],
         [shape(100, 80), shape(100, 80)], [shape(100, 80)]),
    ]
    for (name, views, colors, depths) in rejected {
        check(VisionImmersivePassPlanner.passes(views: views, colorTargets: colors,
                                                depthTargets: depths) == nil,
              "rejects \(name)")
    }
}

private func checkFullViewportPolicy() {
    print("Full-viewport MONO policy")
    let transform = VisionImmersiveFullViewport.clipFromQuad
    let corners = [
        ndc(transform, -1, -1), ndc(transform, -1, 1),
        ndc(transform, 1, -1), ndc(transform, 1, 1),
    ]
    check(corners.map(\.x) == [-1, -1, 1, 1]
            && corners.map(\.y) == [-1, 1, -1, 1],
          "the unit quad reaches every clip-space edge without cropping")
    check(corners.allSatisfy {
        near($0.z, VisionImmersiveFullViewport.farDepth)
    }, "every pixel uses the explicit reverse-Z far presentation depth")
    check(VisionImmersiveFullViewport.farDepth == 0,
          "the MONO viewport does not claim a fictitious near spatial surface")
}

private func checkTickCadence() {
    print("Tick cadence")
    var cadence = VisionImmersiveTickCadence()
    let start = 1_000.0
    var ninety: [Double] = []
    for frame in 0..<9 {
        if let time = cadence.scheduledTime(for: start + Double(frame) / 90,
                                            framesPerSecond: 90) {
            ninety.append(time)
        }
    }
    check(ninety.count == 9 && zip(ninety, ninety.dropFirst()).allSatisfy {
        near($1 - $0, 1.0 / 90, 1e-9)
    }, "a 90 Hz game ticks on every 90 Hz compositor frame")

    cadence = VisionImmersiveTickCadence()
    var sixty: [Double] = []
    for frame in 0..<9 {
        if let time = cadence.scheduledTime(for: start + Double(frame) / 90,
                                            framesPerSecond: 60) {
            sixty.append(time)
        }
    }
    check(sixty.count == 6 && zip(sixty, sixty.dropFirst()).allSatisfy {
        near($1 - $0, 1.0 / 60, 1e-9)
    }, "a 60 Hz game ticks on two of every three 90 Hz frames at exact 1/60 s steps")

    cadence = VisionImmersiveTickCadence()
    let first = cadence.scheduledTime(for: start, framesPerSecond: 60)
    let late = cadence.scheduledTime(for: start + 0.050, framesPerSecond: 60)
    check(first == start && late.map { near($0 - start, 3.0 / 60, 1e-9) } == true,
          "a dropped compositor stretch reports the elapsed grid steps for catch-up")

    let resumed = cadence.scheduledTime(for: start + 10, framesPerSecond: 60)
    check(resumed == start + 10, "a gap longer than 0.25 s restarts the schedule")

    let rateChange = cadence.scheduledTime(for: start + 10 + 1.0 / 90, framesPerSecond: 90)
    check(rateChange == start + 10 + 1.0 / 90, "changing the game rate restarts the schedule")

    check(cadence.scheduledTime(for: .nan, framesPerSecond: 60) == nil
            && cadence.scheduledTime(for: start, framesPerSecond: 0) == nil,
          "non-finite times and invalid rates never tick")
}

@main
private enum VisionImmersivePresentationPlanCheck {
    static func main() {
        checkPassPlanning()
        checkFullViewportPolicy()
        checkTickCadence()
        guard failures == 0 else {
            print("visionOS immersive presentation plan checks failed: \(failures)")
            fatalError("immersive presentation plan check failed")
        }
        print("visionOS immersive presentation plan checks passed")
    }
}
