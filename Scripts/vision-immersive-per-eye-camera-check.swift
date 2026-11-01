import simd

private var failures = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("  ok   \(message)")
    } else {
        print("  FAIL \(message)")
        failures += 1
    }
}

private func translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
    simd_float4x4(columns: (
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(0, 0, 1, 0),
        SIMD4<Float>(x, y, z, 1)
    ))
}

private func rotationY(_ radians: Float) -> simd_float4x4 {
    let c = cos(radians)
    let s = sin(radians)
    return simd_float4x4(columns: (
        SIMD4<Float>(c, 0, -s, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(s, 0, c, 0),
        SIMD4<Float>(0, 0, 0, 1)
    ))
}

private func rotationX(_ radians: Float) -> simd_float4x4 {
    let c = cos(radians)
    let s = sin(radians)
    return simd_float4x4(columns: (
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, c, s, 0),
        SIMD4<Float>(0, -s, c, 0),
        SIMD4<Float>(0, 0, 0, 1)
    ))
}

private func projection(horizontalScale: Float, offset: Float) -> simd_float4x4 {
    simd_float4x4(columns: (
        SIMD4<Float>(horizontalScale, 0, 0, 0),
        SIMD4<Float>(0, 1.25, 0, 0),
        SIMD4<Float>(offset, 0, 0.01, -1),
        SIMD4<Float>(0, 0, 0.1, 0)
    ))
}

private func request(time: Double, pose: simd_float4x4,
                     deviceFromEyes: [simd_float4x4],
                     projections: [simd_float4x4],
                     aspects: [Float],
                     entry: simd_float4x4,
                     identity: UInt64,
                     skyGeneration: Bool = false) -> VisionImmersiveFrameRequest? {
    let cull = simd_float4x4(diagonal: SIMD4<Float>(1.1, 1.2, 0.01, 1))
    let cameras: [VisionImmersiveViewCamera]?
    if skyGeneration {
        cameras = VisionImmersiveCameraMath.makeCameras(
            originFromDevice: pose,
            deviceFromEyes: deviceFromEyes,
            clipFromEyes: projections,
            aspectRatios: aspects,
            entryOriginFromGameCameraMeters: entry,
            binocularCullClipFromDevice: cull,
            skyGeneration: true)
    } else {
        // Default callers: no skyGeneration argument.
        cameras = VisionImmersiveCameraMath.makeCameras(
            originFromDevice: pose,
            deviceFromEyes: deviceFromEyes,
            clipFromEyes: projections,
            aspectRatios: aspects,
            entryOriginFromGameCameraMeters: entry,
            binocularCullClipFromDevice: cull)
    }
    guard let cameras else { return nil }
    return VisionImmersiveFrameRequest(
        presentationTime: time,
        originFromDevice: pose,
        cameras: cameras,
        poseIdentity: identity
    )
}

private func checkCameraConstructionAndCompatibility() {
    print("Per-eye camera math")
    let entry = translation(1, 1.6, -2) * rotationY(0.2)
    let deviceFromEyes = [translation(-0.032, 0, 0), translation(0.032, 0, 0)]
    let projections = [projection(horizontalScale: 1.08, offset: -0.015),
                       projection(horizontalScale: 1.08, offset: 0.015)]
    let aspects: [Float] = [1.07, 1.07]
    let initial = request(time: 10, pose: entry, deviceFromEyes: deviceFromEyes,
                          projections: projections, aspects: aspects, entry: entry,
                          identity: 1)!
    check(initial.isValid && initial.cameras.count == 2,
          "a tracked entry pose produces exactly two valid cameras")

    let expectedLeft = simd_inverse(entry * deviceFromEyes[0]) * entry
    let expectedRight = simd_inverse(entry * deviceFromEyes[1]) * entry
    check(VisionImmersiveCameraMath.near(
            initial.cameras[0].eyeFromGameCameraMeters, expectedLeft, tolerance: 1e-5)
          && VisionImmersiveCameraMath.near(
            initial.cameras[1].eyeFromGameCameraMeters, expectedRight, tolerance: 1e-5),
          "each eye uses inverse(originFromDevice * deviceFromEye) * entryOriginFromGameCamera")
    check(VisionImmersiveCameraMath.near(
            initial.cameras[0].binocularCullFromGameCameraMeters,
            initial.cameras[1].binocularCullFromGameCameraMeters,
            tolerance: 0),
          "both eyes share one conservative binocular cull matrix")

    let movedPose = translation(1.08, 1.63, -1.9) * rotationY(0.27)
    let moved = request(time: 10.011, pose: movedPose, deviceFromEyes: deviceFromEyes,
                        projections: projections, aspects: aspects, entry: entry,
                        identity: 2)!
    check(initial.isOpticallyCompatible(with: moved),
          "common head motion preserves relative calibration and permits anchored frame reuse")
    check(!VisionImmersiveCameraMath.near(
            initial.cameras[0].eyeFromGameCameraMeters,
            moved.cameras[0].eyeFromGameCameraMeters,
            tolerance: 1e-3),
          "head motion still changes the native per-eye game-camera transform")

    let changedProjection = request(
        time: 10.022, pose: movedPose, deviceFromEyes: deviceFromEyes,
        projections: [projection(horizontalScale: 1.09, offset: -0.015), projections[1]],
        aspects: aspects, entry: entry, identity: 3)!
    check(!moved.isOpticallyCompatible(with: changedProjection),
          "a changed optical projection rejects cached native images")

    let changedAspect = request(time: 10.022, pose: movedPose,
                                deviceFromEyes: deviceFromEyes,
                                projections: projections, aspects: [1.07, 1.08],
                                entry: entry, identity: 4)!
    check(!moved.isOpticallyCompatible(with: changedAspect),
          "a changed view aspect rejects cached native images")

    let changedCalibration = request(
        time: 10.022, pose: movedPose,
        deviceFromEyes: [deviceFromEyes[0], translation(0.034, 0, 0)],
        projections: projections, aspects: aspects, entry: entry, identity: 5)!
    check(!moved.isOpticallyCompatible(with: changedCalibration),
          "a changed relative eye calibration rejects cached native images")

    let invalidCount = VisionImmersiveFrameRequest(
        presentationTime: 10,
        originFromDevice: entry,
        cameras: [initial.cameras[0]],
        poseIdentity: 6
    )
    check(!invalidCount.isValid, "a request without exactly two eyes is invalid")
    check(VisionImmersiveCameraMath.makeCameras(
            originFromDevice: simd_float4x4(),
            deviceFromEyes: deviceFromEyes,
            clipFromEyes: projections,
            aspectRatios: aspects,
            entryOriginFromGameCameraMeters: entry,
            binocularCullClipFromDevice: matrix_identity_float4x4) == nil,
          "a singular tracked pose fails closed")
}

private func checkCullPolicy() {
    print("Binocular cull policy")
    check(VisionImmersiveBinocularCullPolicy.increaseTangents
            == SIMD4<Float>(repeating: 0.02),
          "binocular tangents expand slightly and symmetrically")
    let broadened = VisionImmersiveBinocularCullPolicy.broaderDepthRange(
        than: SIMD2<Float>(100, 0.1))
    check(broadened.x == 500 && broadened.y == 0.05,
          "reverse-Z culling reaches farther and nearer than the compositor default")
    let worldRange = VisionImmersiveBinocularCullPolicy.broaderDepthRange(
        than: SIMD2<Float>(5_000, 0.1))
    check(worldRange == SIMD2<Float>(20_000, 0.05),
          "the native world projection retains a broader binocular cull range")
    let fallback = VisionImmersiveBinocularCullPolicy.broaderDepthRange(
        than: SIMD2<Float>(.nan, 0))
    check(fallback == SIMD2<Float>(500, 0.05),
          "invalid compositor depth bounds use the bounded conservative fallback")
}

private func checkHUDPlacement() {
    print("HUD plane optics and cache guards")
    let id = matrix_identity_float4x4
    let eyes = [translation(-0.032, 0.01, -0.005) * rotationY(0.03),
                translation(0.032, 0.01, -0.005) * rotationY(-0.03)]
    let projections = [projection(horizontalScale: 1.2, offset: -0.2),
                       projection(horizontalScale: 1.2, offset: 0.2)]
    let original = request(time: 12, pose: id, deviceFromEyes: eyes,
                           projections: projections, aspects: [1.1, 1.1], entry: id, identity: 5)!
    let moved = request(time: 13, pose: translation(1, 1.5, -0.4) * rotationY(0.7),
                        deviceFromEyes: eyes, projections: projections,
                        aspects: [1.1, 1.1], entry: id, identity: 6)!
    for eye in 0..<2 {
        let hud = original.cameras[eye].hudClipFromScreenClip!
        check(VisionImmersiveCameraMath.near(hud, moved.cameras[eye].hudClipFromScreenClip!,
                                             tolerance: 1e-5),
              "HUD remains relative to the head while World follows its pose")
        for x: Float in [-1, 0, 1] {
            for y: Float in [-1, 0, 1] {
                let screen = SIMD4<Float>(x, y, 0.9, 1)
                let recovered = eyes[eye] * simd_inverse(projections[eye]) * hud * screen
                let head = recovered / recovered.w
                check(simd_length(head - SIMD4<Float>(0.8 * x, 0.6 * y, -2, 1)) < 2e-5,
                      "eye \(eye) recovers the authored shared HUD point")
            }
        }
    }
    func replacing(_ cameras: [VisionImmersiveViewCamera]) -> VisionImmersiveFrameRequest {
        VisionImmersiveFrameRequest(presentationTime: original.presentationTime,
            originFromDevice: original.originFromDevice, cameras: cameras,
            poseIdentity: original.poseIdentity)
    }
    var cameras = original.cameras
    var bad = cameras[0].hudClipFromScreenClip!
    bad[0][0] = .nan
    cameras[0].hudClipFromScreenClip = bad
    let nonfinite = replacing(cameras)
    check(!nonfinite.isValid && !original.isOpticallyCompatible(with: nonfinite),
          "nonfinite HUD input cannot be rendered or reuse a cached frame")
    cameras = original.cameras
    cameras[0].hudClipFromScreenClip = nil
    check(!replacing(cameras).isValid, "both eyes must agree on HUD enablement")
    cameras[1].hudClipFromScreenClip = nil
    check(replacing(cameras).isValid && !original.isOpticallyCompatible(with: replacing(cameras)),
          "legacy HUD stays valid but cannot reuse an enabled HUD frame")
    cameras = original.cameras
    cameras[0].hudClipFromScreenClip![3][0] += 0.1
    check(!original.isOpticallyCompatible(with: replacing(cameras)),
          "a changed HUD projection invalidates cached eye pixels")
}

private func checkSkyGeneration() {
    print("Sky-generation head rotation")
    let near = VisionImmersiveCameraMath.near
    let id = matrix_identity_float4x4
    let entry = translation(1, 1.6, -2) * rotationY(0.6) * rotationX(-0.15)
    // Asymmetric, canted eyes with asymmetric projections.
    let eyes = [translation(-0.031, 0.004, -0.006) * rotationY(0.04) * rotationX(0.01),
                translation(0.034, -0.002, -0.004) * rotationY(-0.025)]
    let projections = [projection(horizontalScale: 1.1, offset: -0.2),
                       projection(horizontalScale: 1.05, offset: 0.17)]
    let aspects: [Float] = [1.07, 1.07]

    let atEntry = request(time: 20, pose: entry, deviceFromEyes: eyes, projections: projections,
                          aspects: aspects, entry: entry, identity: 1, skyGeneration: true)!
    check(atEntry.isValid, "an enabled sky request at entry is valid")
    check(atEntry.cameras.allSatisfy { near($0.gameCameraFromHead!, id, 1e-5) },
          "H is identity at entry under a nonidentity entry rotation")

    let relative = rotationY(0.35) * rotationX(0.2)
    let lookedAround = entry * relative
    let posed = request(time: 20.01, pose: lookedAround, deviceFromEyes: eyes,
                        projections: projections, aspects: aspects, entry: entry,
                        identity: 2, skyGeneration: true)!
    check(near(posed.cameras[0].gameCameraFromHead!, relative, 1e-5),
          "relative yaw and pitch under a nonidentity entry are recovered")

    let translated = request(time: 20.02,
                             pose: translation(0.4, -0.3, 0.9) * lookedAround,
                             deviceFromEyes: eyes, projections: projections, aspects: aspects,
                             entry: translation(-3, 2, 5) * entry, identity: 3,
                             skyGeneration: true)!
    let h = translated.cameras[0].gameCameraFromHead!
    check(near(h, relative, 1e-4) && h.columns.3 == SIMD4<Float>(0, 0, 0, 1),
          "H ignores head and entry translation")
    check(translated.cameras[0].gameCameraFromHead! == translated.cameras[1].gameCameraFromHead!
            && VisionImmersiveCameraMath.isProperRotation(h),
          "both eyes carry identical proper-rotation H despite canted asymmetric eyes")
    let firstEyeRotation = translated.cameras[0].eyeFromGameCameraMeters
    var inferred = simd_inverse(firstEyeRotation)
    inferred.columns.3 = SIMD4<Float>(0, 0, 0, 1)
    check(!near(inferred, h, 1e-3), "H differs from inverse(first eye rotation) for canted eyes")

    let plain = request(time: 20.02, pose: lookedAround, deviceFromEyes: eyes,
                        projections: projections, aspects: aspects, entry: entry, identity: 4)!
    check(plain.cameras.allSatisfy { $0.gameCameraFromHead == nil },
          "default makeCameras callers keep sky generation disabled")
    check(zip(plain.cameras, posed.cameras).allSatisfy { lhs, rhs in
            lhs.clipFromEye == rhs.clipFromEye
                && lhs.eyeFromGameCameraMeters == rhs.eyeFromGameCameraMeters
                && lhs.binocularCullFromGameCameraMeters == rhs.binocularCullFromGameCameraMeters
                && lhs.hudClipFromScreenClip == rhs.hudClipFromScreenClip
                && lhs.aspectRatio == rhs.aspectRatio },
          "enabling sky generation leaves projection, eye, cull, and HUD matrices unchanged")

    check(atEntry.isOpticallyCompatible(with: posed),
          "head rotation alone keeps cached-frame reuse when sky generation is enabled")
    check(!plain.isOpticallyCompatible(with: posed) && !posed.isOpticallyCompatible(with: plain),
          "enabled and disabled sky requests cannot reuse each other's frames")

    func replacing(_ cameras: [VisionImmersiveViewCamera]) -> VisionImmersiveFrameRequest {
        VisionImmersiveFrameRequest(presentationTime: posed.presentationTime,
            originFromDevice: posed.originFromDevice, cameras: cameras,
            poseIdentity: posed.poseIdentity)
    }
    var cameras = posed.cameras
    cameras[1].gameCameraFromHead = nil
    check(!replacing(cameras).isValid, "both eyes must agree on sky-generation enablement")
    cameras = posed.cameras
    cameras[1].gameCameraFromHead = relative * rotationY(0.01)
    check(!replacing(cameras).isValid, "unequal per-eye H fails closed")
    cameras = posed.cameras
    let reflection = simd_float4x4(diagonal: SIMD4<Float>(-1, 1, 1, 1))
    cameras[0].gameCameraFromHead = reflection
    cameras[1].gameCameraFromHead = reflection
    check(!replacing(cameras).isValid, "a reflection H fails closed")
    let scaled = simd_float4x4(diagonal: SIMD4<Float>(1.1, 1.1, 1.1, 1))
    cameras[0].gameCameraFromHead = scaled
    cameras[1].gameCameraFromHead = scaled
    check(!replacing(cameras).isValid, "a scaled H fails closed")
    let offset = translation(0, 0.1, 0)
    cameras[0].gameCameraFromHead = offset
    cameras[1].gameCameraFromHead = offset
    check(!replacing(cameras).isValid, "a translated H fails closed")
    var nonfinite = id
    nonfinite[0][0] = .nan
    check(!VisionImmersiveCameraMath.isProperRotation(nonfinite), "a nonfinite H is rejected")
    check(request(time: 20.03, pose: lookedAround, deviceFromEyes: eyes,
                  projections: projections, aspects: aspects,
                  entry: entry * simd_float4x4(diagonal: SIMD4<Float>(1, 1, -1, 1)),
                  identity: 5, skyGeneration: true) == nil
            && request(time: 20.03, pose: lookedAround, deviceFromEyes: eyes,
                       projections: projections, aspects: aspects,
                       entry: entry * simd_float4x4(diagonal: SIMD4<Float>(2, 2, 2, 1)),
                       identity: 6, skyGeneration: true) == nil,
          "an enabled request with a reflected or scaled entry fails closed")
}

@main
private enum VisionImmersivePerEyeCameraCheck {
    static func main() {
        checkCameraConstructionAndCompatibility()
        checkCullPolicy()
        checkHUDPlacement()
        checkSkyGeneration()
        guard failures == 0 else {
            print("visionOS per-eye camera checks failed: \(failures)")
            fatalError("per-eye camera check failed")
        }
        print("visionOS per-eye camera checks passed")
    }
}
