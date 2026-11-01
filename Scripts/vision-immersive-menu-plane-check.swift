import Foundation
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

private func near(_ a: Float, _ b: Float, _ tolerance: Float = 1e-4) -> Bool {
    a.isFinite && b.isFinite && abs(a - b) <= tolerance
}

private func near(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ tolerance: Float = 1e-4) -> Bool {
    simd_length(a - b) <= tolerance
}

private func translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
    simd_float4x4(columns: (
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(0, 0, 1, 0),
        SIMD4<Float>(x, y, z, 1)
    ))
}

private func rotation(_ radians: Float, _ axis: SIMD3<Float>) -> simd_float4x4 {
    simd_float4x4(simd_quatf(angle: radians, axis: simd_normalize(axis)))
}

private func xyz(_ value: SIMD4<Float>) -> SIMD3<Float> {
    SIMD3<Float>(value.x, value.y, value.z)
}

private func transform(_ matrix: simd_float4x4, _ point: SIMD3<Float>) -> SIMD3<Float> {
    xyz(matrix * SIMD4<Float>(point, 1))
}

/// An independent off-axis right/up/back frustum with Metal reverse-Z: near maps to 1, far to 0.
private struct Frustum {
    let left: Float
    let right: Float
    let bottom: Float
    let top: Float
    let near: Float = 0.1
    let far: Float = 5_000

    var clipFromEye: simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4<Float>(2 / (left + right), 0, 0, 0),
            SIMD4<Float>(0, 2 / (bottom + top), 0, 0),
            SIMD4<Float>((right - left) / (left + right), (top - bottom) / (bottom + top),
                         near / (far - near), -1),
            SIMD4<Float>(0, 0, near * far / (far - near), 0)
        ))
    }

    /// Recovers the eye-space point from normalized device coordinates.
    func eyePoint(ndc: SIMD3<Float>) -> SIMD3<Float> {
        let a = -near / (far - near)
        let b = near * far / (far - near)
        let distance = b / (ndc.z - a)
        let tangentX = (ndc.x * (left + right) + (right - left)) / 2
        let tangentY = (ndc.y * (bottom + top) + (top - bottom)) / 2
        return SIMD3<Float>(tangentX * distance, tangentY * distance, -distance)
    }
}

private func ndc(_ clipFromQuad: simd_float4x4, _ corner: SIMD2<Float>) -> SIMD3<Float> {
    let clip = clipFromQuad * SIMD4<Float>(corner.x, corner.y, 0, 1)
    return SIMD3<Float>(clip.x, clip.y, clip.z) / clip.w
}

private func isOrthonormalRightHanded(_ m: simd_float4x4) -> Bool {
    let x = xyz(m.columns.0), y = xyz(m.columns.1), z = xyz(m.columns.2)
    return near(simd_length(x), 1) && near(simd_length(y), 1) && near(simd_length(z), 1)
        && near(simd_dot(x, y), 0) && near(simd_dot(y, z), 0) && near(simd_dot(x, z), 0)
        && near(simd_dot(simd_cross(x, y), z), 1)
}

@main
enum VisionImmersiveMenuPlaneCheck {
    static func main() {
        let halfIPD: Float = 0.0315
        let worldUp = SIMD3<Float>(0, 1, 0)
        // Small toe-out and asymmetric, mirrored nasal/temporal optics make every input matter.
        let deviceFromEyes = [
            translation(-halfIPD, 0.004, -0.01) * rotation(0.008, worldUp),
            translation(halfIPD, 0.004, -0.01) * rotation(-0.008, worldUp),
        ]
        let frusta = [
            Frustum(left: 1.0, right: 0.85, bottom: 1.1, top: 0.95),
            Frustum(left: 0.85, right: 1.0, bottom: 1.1, top: 0.95),
        ]

        print("Comfort size")
        check(VisionImmersiveMenuPlane.distanceMeters == 2
                && VisionImmersiveMenuPlane.maximumSizeMeters == SIMD2<Float>(1.6, 1.2),
              "the bounded experimental choice is a 1.6 m x 1.2 m window-like frame at 2 m")
        let classic = VisionImmersiveMenuPlane.size(aspectRatio: 640.0 / 480.0)
        check(classic.map { near($0.x, 1.6) && near($0.y, 1.2) } ?? false,
              "a 4:3 conventional frame fills the comfort box")
        let classicDegrees = 2 * atan(0.8 / VisionImmersiveMenuPlane.distanceMeters) * 180 / .pi
        check(near(classicDegrees, 43.6, 0.05), "4:3 subtends about 44 degrees horizontally at 2 m")
        check(VisionImmersiveMenuPlane.size(aspectRatio: 16.0 / 9.0)
                .map { near($0.x, 1.6) && near($0.y, 0.9) } ?? false
                && VisionImmersiveMenuPlane.size(aspectRatio: 0.75)
                .map { near($0.x, 0.9) && near($0.y, 1.2) } ?? false,
              "wider and taller horizontal-plus frames keep their own aspect inside the box")
        check([0, -1, .nan, .infinity].allSatisfy {
            VisionImmersiveMenuPlane.size(aspectRatio: $0) == nil
        },
              "zero, negative, and non-finite aspects are rejected")

        print("Placement")
        let level = VisionImmersiveMenuPlane.originFromPlane(
            originFromDevice: translation(0, 1.5, 0))
        check(level.map {
            near(xyz($0.columns.3), SIMD3(0, 1.5, -2))
                && near(xyz($0.columns.0), SIMD3(1, 0, 0)) && near(xyz($0.columns.1), worldUp)
                && near(xyz($0.columns.2), SIMD3(0, 0, 1))
        } ?? false, "a level head places the plane 2 m ahead, upright and facing the viewer")

        let yaw: Float = 0.6
        let headPosition = SIMD3<Float>(0.4, 1.6, -0.3)
        let rolledHead = translation(headPosition.x, headPosition.y, headPosition.z)
            * rotation(yaw, worldUp) * rotation(0.35, SIMD3(0, 0, 1))
        let yawOnly = rotation(yaw, worldUp)
        let expectedCenter = headPosition + transform(yawOnly, SIMD3(0, 0, -2))
        let expectedRight = transform(yawOnly, SIMD3(1, 0, 0))
        let rolled = VisionImmersiveMenuPlane.originFromPlane(originFromDevice: rolledHead)
        check(rolled.map {
            near(xyz($0.columns.3), expectedCenter) && near(xyz($0.columns.0), expectedRight)
                && near(xyz($0.columns.1), worldUp) && isOrthonormalRightHanded($0)
        } ?? false, "head roll never tilts the plane; yaw sets its facing and centre")

        let pitchedHead = translation(0, 1.5, 0) * rotation(-0.5, SIMD3(1, 0, 0))
        let pitched = VisionImmersiveMenuPlane.originFromPlane(originFromDevice: pitchedHead)
        check(pitched.map {
            near(xyz($0.columns.2), xyz(pitchedHead.columns.2)) && near($0.columns.0.y, 0)
                && simd_dot(xyz($0.columns.1), worldUp) > 0 && isOrthonormalRightHanded($0)
                && near(simd_distance(xyz($0.columns.3), SIMD3(0, 1.5, 0)), 2)
        } ?? false, "a pitched gaze centres the plane on the gaze and keeps its horizon level")

        let downHead = translation(0, 1.5, 0) * rotation(-.pi / 2, SIMD3(1, 0, 0))
        check(VisionImmersiveMenuPlane.originFromPlane(originFromDevice: downHead)
                .map(isOrthonormalRightHanded) ?? false,
              "looking straight down still yields an orthonormal plane")
        var nanHead = translation(0, 1.5, 0)
        nanHead.columns.3.x = .nan
        check(VisionImmersiveMenuPlane.originFromPlane(originFromDevice: nanHead) == nil
                && VisionImmersiveMenuPlane.originFromPlane(
                    originFromDevice: simd_float4x4(diagonal: SIMD4(0, 0, 0, 1))) == nil,
              "non-finite and degenerate head poses are rejected")

        print("Per-eye optics, disparity, and depth")
        guard let size = classic, let plane = rolled else {
            print("  FAIL fixture plane is unavailable")
            exit(1)
        }
        // The plane stays where it was placed; the head later turns partly back and moves.
        let laterHead = translation(0.35, 1.58, -0.2) * rotation(0.2, worldUp)
        var clipFromQuads: [simd_float4x4] = []
        for eye in 0..<2 {
            if let clipFromQuad = VisionImmersiveMenuPlane.clipFromQuad(
                originFromPlane: plane, size: size, originFromDevice: laterHead,
                deviceFromEye: deviceFromEyes[eye], clipFromEye: frusta[eye].clipFromEye) {
                clipFromQuads.append(clipFromQuad)
            }
        }
        check(clipFromQuads.count == 2, "both eyes form a finite plane transform")
        guard clipFromQuads.count == 2 else { exit(1) }

        let corners: [SIMD2<Float>] = [
            SIMD2(-1, -1), SIMD2(1, -1), SIMD2(-1, 1), SIMD2(1, 1), SIMD2(0, 0),
        ]
        func expectedWorld(_ corner: SIMD2<Float>) -> SIMD3<Float> {
            expectedCenter + expectedRight * (corner.x * 0.8) + worldUp * (corner.y * 0.6)
        }
        var projectionMatches = true
        var recoveredMatches = true
        for eye in 0..<2 {
            let eyeFromWorld = simd_inverse(laterHead * deviceFromEyes[eye])
            for corner in corners {
                let eyePoint = transform(eyeFromWorld, expectedWorld(corner))
                let clip = frusta[eye].clipFromEye * SIMD4<Float>(eyePoint, 1)
                let expected = SIMD3<Float>(clip.x, clip.y, clip.z) / clip.w
                let actual = ndc(clipFromQuads[eye], corner)
                projectionMatches = projectionMatches && near(actual.x, expected.x, 1e-4)
                    && near(actual.y, expected.y, 1e-4) && near(actual.z, expected.z, 1e-6)
                recoveredMatches = recoveredMatches
                    && near(frusta[eye].eyePoint(ndc: actual), eyePoint, 2e-3)
            }
        }
        check(projectionMatches,
              "every corner lands where each eye's own projection and eye-from-head pose put it")
        check(recoveredMatches, "reverse-Z depth unprojects to the plane's real eye-space points")

        let recoveredCorners = (0..<2).map { eye in
            corners.map { frusta[eye].eyePoint(ndc: ndc(clipFromQuads[eye], $0)) }
        }
        check(recoveredCorners.allSatisfy { points in
            near(simd_distance(points[0], points[1]), 1.6, 2e-3)
                && near(simd_distance(points[0], points[2]), 1.2, 2e-3)
                && near(simd_dot(points[1] - points[0], points[2] - points[0]), 0, 2e-3)
        }, "each eye sees the same undistorted 1.6 m x 1.2 m (4:3) rectangle")

        let headCenter = transform(laterHead, .zero)
        let worldCenters = (0..<2).map {
            transform(laterHead * deviceFromEyes[$0], recoveredCorners[$0][4])
        }
        check(near(worldCenters[0], worldCenters[1], 2e-3)
                && near(worldCenters[0], expectedCenter, 2e-3),
              "both eyes converge on one world-fixed plane centre")
        let eyeOrigins = (0..<2).map { transform(laterHead * deviceFromEyes[$0], .zero) }
        let leftRay = simd_normalize(expectedCenter - eyeOrigins[0])
        let rightRay = simd_normalize(expectedCenter - eyeOrigins[1])
        let vergence = acos(min(1, simd_dot(leftRay, rightRay)))
        let distance = simd_distance(headCenter, expectedCenter)
        let baseline = simd_distance(eyeOrigins[0], eyeOrigins[1])
        check(distance > 1.9 && distance < 2.1
                && near(vergence, 2 * atan(baseline / 2 / distance), 2e-3),
              "binocular disparity matches the plane's metric distance, not a duplicated screen")
        let centerDepths = (0..<2).map { ndc(clipFromQuads[$0], SIMD2(0, 0)).z }
        check(centerDepths.allSatisfy { $0 > 0 && $0 < 1 }
                && centerDepths.allSatisfy { near(frusta[0].near / $0, 2, 0.15) },
              "compositor depth is finite reverse-Z near 2 m and nearer than the far clear")
        let topRight = ndc(clipFromQuads[0], SIMD2(1, 1))
        let bottomLeft = ndc(clipFromQuads[0], SIMD2(-1, -1))
        let center = ndc(clipFromQuads[0], SIMD2(0, 0))
        check(topRight.x > center.x && topRight.y > center.y
                && bottomLeft.x < center.x && bottomLeft.y < center.y,
              "quad +x/+y stays right/up, so the texture's top row stays at the top")
        let anchoredHere = VisionImmersiveMenuPlane.originFromPlane(originFromDevice: laterHead)
        let recentredCenter = anchoredHere.flatMap {
            VisionImmersiveMenuPlane.clipFromQuad(
                originFromPlane: $0, size: size, originFromDevice: laterHead,
                deviceFromEye: deviceFromEyes[0], clipFromEye: frusta[0].clipFromEye)
        }.map { ndc($0, SIMD2(0, 0)) }
        check(recentredCenter.map { abs($0.x - center.x) > 0.2 } == true,
              "after the head turns, the plane stays in the room instead of following the head")

        print("Invalid transforms")
        var nanProjection = frusta[0].clipFromEye
        nanProjection.columns.0.x = .nan
        var nanPlane = plane
        nanPlane.columns.3.y = .infinity
        check(VisionImmersiveMenuPlane.clipFromQuad(
                originFromPlane: plane, size: size, originFromDevice: laterHead,
                deviceFromEye: simd_float4x4(diagonal: SIMD4(0, 0, 0, 0)),
                clipFromEye: frusta[0].clipFromEye) == nil
                && VisionImmersiveMenuPlane.clipFromQuad(
                    originFromPlane: plane, size: size, originFromDevice: laterHead,
                    deviceFromEye: deviceFromEyes[0], clipFromEye: nanProjection) == nil
                && VisionImmersiveMenuPlane.clipFromQuad(
                    originFromPlane: nanPlane, size: size, originFromDevice: laterHead,
                    deviceFromEye: deviceFromEyes[0], clipFromEye: frusta[0].clipFromEye) == nil
                && VisionImmersiveMenuPlane.clipFromQuad(
                    originFromPlane: plane, size: SIMD2(0, 1.2), originFromDevice: laterHead,
                    deviceFromEye: deviceFromEyes[0], clipFromEye: frusta[0].clipFromEye) == nil,
              "singular eye poses, non-finite optics or planes, and empty sizes fail closed")

        print("Gameplay resolve")
        check(VisionImmersiveResolve.clipFromQuad == matrix_identity_float4x4,
              "per-eye gameplay still resolves each native eye across its whole compositor view")

        if failures == 0 {
            print("visionOS immersive menu-plane checks passed")
        } else {
            print("visionOS immersive menu-plane checks failed: \(failures)")
            exit(1)
        }
    }
}
