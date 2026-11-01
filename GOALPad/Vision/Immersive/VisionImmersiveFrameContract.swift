#if GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE
import Foundation
import Metal
import simd

/// One eye's native game-camera contract for a compositor frame.
nonisolated struct VisionImmersiveViewCamera: Sendable {
    let clipFromEye: simd_float4x4
    let eyeFromGameCameraMeters: simd_float4x4
    let binocularCullFromGameCameraMeters: simd_float4x4
    let aspectRatio: Float
    /// Opt-in head-locked HUD plane (P_eye * inverse(deviceFromEye) * planeFromScreen); nil keeps
    /// HUD draws on their existing path.
    var hudClipFromScreenClip: simd_float4x4? = nil
    /// Opt-in sky-generation context: the common proper rotation gameCameraFromCurrentHead in the
    /// right/up/back basis with zero translation. Identical for both eyes; nil keeps it disabled.
    var gameCameraFromHead: simd_float4x4? = nil
}

/// The exact tracked pose and optics requested for one paired native render.
nonisolated struct VisionImmersiveFrameRequest: Sendable {
    static let viewCount = 2
    static let opticsTolerance: Float = 2e-4

    let presentationTime: TimeInterval
    let originFromDevice: simd_float4x4
    /// Left, then right. Requests with any other count are invalid.
    let cameras: [VisionImmersiveViewCamera]
    /// Identifies the retained ARKit DeviceAnchor used to form this request.
    let poseIdentity: UInt64

    var isValid: Bool {
        presentationTime.isFinite && poseIdentity != 0
            && VisionImmersiveCameraMath.isFinite(originFromDevice)
            && cameras.count == Self.viewCount
            && cameras.allSatisfy {
                $0.aspectRatio.isFinite && $0.aspectRatio > 0
                    && VisionImmersiveCameraMath.isFinite($0.clipFromEye)
                    && VisionImmersiveCameraMath.isFinite($0.eyeFromGameCameraMeters)
                    && VisionImmersiveCameraMath.isFinite(
                        $0.binocularCullFromGameCameraMeters)
                    && ($0.hudClipFromScreenClip.map(VisionImmersiveCameraMath.isFinite) ?? true)
                    && ($0.hudClipFromScreenClip != nil) == (cameras[0].hudClipFromScreenClip != nil)
            }
            && VisionImmersiveCameraMath.isValidSkyGenerationPair(cameras.map(\.gameCameraFromHead))
    }

    /// Head pose is deliberately excluded: a cached image keeps its own DeviceAnchor so the
    /// compositor can reproject it. Reuse is safe only while the optical projections, viewport
    /// aspects, and relative eye calibration are unchanged.
    func isOpticallyCompatible(with other: Self,
                               tolerance: Float = Self.opticsTolerance) -> Bool {
        guard isValid, other.isValid, tolerance.isFinite, tolerance >= 0,
              zip(cameras, other.cameras).allSatisfy({ lhs, rhs in
                  VisionImmersiveCameraMath.near(lhs.clipFromEye, rhs.clipFromEye,
                                                 tolerance: tolerance)
                      && abs(lhs.aspectRatio - rhs.aspectRatio) <= tolerance
                      && Self.compatibleHUD(lhs.hudClipFromScreenClip,
                                            rhs.hudClipFromScreenClip, tolerance: tolerance)
                      // Head rotation is pose; only sky-generation eligibility affects reuse.
                      && (lhs.gameCameraFromHead != nil) == (rhs.gameCameraFromHead != nil)
              }),
              let calibration = relativeEyeCalibration,
              let otherCalibration = other.relativeEyeCalibration else { return false }
        return VisionImmersiveCameraMath.near(
            calibration, otherCalibration, tolerance: tolerance)
    }

    private var relativeEyeCalibration: simd_float4x4? {
        guard cameras.count == Self.viewCount,
              let gameCameraFromRightEye = VisionImmersiveCameraMath.inverse(
                cameras[1].eyeFromGameCameraMeters) else { return nil }
        let leftEyeFromRightEye = cameras[0].eyeFromGameCameraMeters
            * gameCameraFromRightEye
        return VisionImmersiveCameraMath.isFinite(leftEyeFromRightEye)
            ? leftEyeFromRightEye : nil
    }

    private static func compatibleHUD(_ lhs: simd_float4x4?, _ rhs: simd_float4x4?,
                                      tolerance: Float) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case (let left?, let right?):
            return VisionImmersiveCameraMath.near(left, right, tolerance: tolerance)
        default: return false
        }
    }
}

/// A completed native stereo frame. The textures and request always travel together so a cached
/// frame can never be presented with a newer pose or an unrelated projection.
nonisolated struct VisionImmersiveGameFrame: @unchecked Sendable {
    /// Left and right BGRA8Unorm game images.
    let colorTextures: [any MTLTexture]
    /// Left and right native shader-readable D32S8 attachments. They are sampled directly as
    /// `depth2d<float>`; Metal does not permit a Depth32Float texture view of D32S8.
    let depthTextures: [any MTLTexture]
    let fade: Float
    let renderSerial: UInt64
    let request: VisionImmersiveFrameRequest

    func isPresentable(on device: any MTLDevice) -> Bool {
        guard request.isValid,
              colorTextures.count == VisionImmersiveFrameRequest.viewCount,
              depthTextures.count == VisionImmersiveFrameRequest.viewCount,
              fade.isFinite, (0...1).contains(fade) else { return false }
        return zip(colorTextures, depthTextures).allSatisfy { color, depth in
            color.device === device && depth.device === device
                && color.textureType == .type2D && depth.textureType == .type2D
                && color.pixelFormat == .bgra8Unorm
                && depth.pixelFormat == .depth32Float_stencil8
                && color.width > 0 && color.height > 0
                && color.width == depth.width && color.height == depth.height
                && color.usage.contains(.shaderRead) && depth.usage.contains(.shaderRead)
        }
    }
}

/// The conventional composed game frame, HUD and menus included, rendered while a native menu owns
/// input. Its pixels do not depend on head pose, so it is always placed with the newest pose.
nonisolated struct VisionImmersiveMenuFrame: @unchecked Sendable {
    let colorTexture: any MTLTexture
    /// Kept only so render evidence can sample it; the menu plane writes its own raster depth.
    let depthTexture: any MTLTexture
    let fade: Float
    let renderSerial: UInt64

    var aspectRatio: Float {
        Float(colorTexture.width) / Float(colorTexture.height)
    }

    func isPresentable(on device: any MTLDevice) -> Bool {
        fade.isFinite && (0...1).contains(fade)
            && colorTexture.device === device && depthTexture.device === device
            && colorTexture.textureType == .type2D && depthTexture.textureType == .type2D
            && colorTexture.pixelFormat == .bgra8Unorm
            && depthTexture.pixelFormat == .depth32Float_stencil8
            && colorTexture.width > 0 && colorTexture.height > 0
            && colorTexture.width == depthTexture.width
            && colorTexture.height == depthTexture.height
            && colorTexture.usage.contains(.shaderRead) && depthTexture.usage.contains(.shaderRead)
    }
}

nonisolated enum VisionImmersivePresentedFrame: @unchecked Sendable {
    /// Gameplay: native per-eye world cameras resolved across each whole eye view.
    case perEye(VisionImmersiveGameFrame)
    /// A native menu owns input: the conventional frame on a finite-depth plane.
    case menuPlane(VisionImmersiveMenuFrame)

    var renderSerial: UInt64 {
        switch self {
        case .perEye(let frame): frame.renderSerial
        case .menuPlane(let frame): frame.renderSerial
        }
    }
}

/// Comfortable placement for the conventional frame while a native menu owns input. The plane is
/// fixed in the room where the head looked when the menu opened, and each eye projects it with its
/// own optics, so disparity and compositor depth both match the chosen distance.
nonisolated enum VisionImmersiveMenuPlane {
    static let distanceMeters: Float = 2
    /// A 4:3 frame fills this box exactly, about 44 degrees wide at the chosen distance.
    static let maximumSizeMeters = SIMD2<Float>(1.6, 1.2)

    /// The largest size with the frame's own aspect that fits the comfort box.
    static func size(aspectRatio: Float) -> SIMD2<Float>? {
        guard aspectRatio.isFinite, aspectRatio > 0 else { return nil }
        let bounds = maximumSizeMeters
        return aspectRatio >= bounds.x / bounds.y
            ? SIMD2(bounds.x, bounds.x / aspectRatio)
            : SIMD2(bounds.y * aspectRatio, bounds.y)
    }

    /// Centres the plane along the head's forward direction and turns it to face the head with
    /// gravity up, so head roll never tilts the menu. Nil for a non-finite or degenerate pose.
    static func originFromPlane(originFromDevice: simd_float4x4) -> simd_float4x4? {
        guard VisionImmersiveCameraMath.isFinite(originFromDevice) else { return nil }
        let deviceBack = xyz(originFromDevice.columns.2)
        guard simd_length(deviceBack) > 0.5 else { return nil }
        let back = simd_normalize(deviceBack)
        var right = simd_cross(SIMD3<Float>(0, 1, 0), back)
        if simd_length(right) < 1e-3 {
            // Looking straight up or down: the head's own right axis is the only upright cue.
            let deviceRight = xyz(originFromDevice.columns.0)
            right = deviceRight - simd_dot(deviceRight, back) * back
        }
        guard simd_length(right) > 1e-3 else { return nil }
        right = simd_normalize(right)
        let up = simd_cross(back, right)
        let center = xyz(originFromDevice.columns.3) - back * distanceMeters
        return simd_float4x4(columns: (
            SIMD4<Float>(right, 0),
            SIMD4<Float>(up, 0),
            SIMD4<Float>(back, 0),
            SIMD4<Float>(center, 1)
        ))
    }

    /// Maps the resolve quad's -1...1 corners onto the plane as one eye sees it.
    static func clipFromQuad(originFromPlane: simd_float4x4,
                             size: SIMD2<Float>,
                             originFromDevice: simd_float4x4,
                             deviceFromEye: simd_float4x4,
                             clipFromEye: simd_float4x4) -> simd_float4x4? {
        guard size.x.isFinite, size.y.isFinite, size.x > 0, size.y > 0,
              VisionImmersiveCameraMath.isFinite(originFromPlane),
              VisionImmersiveCameraMath.isFinite(clipFromEye),
              let eyeFromOrigin = VisionImmersiveCameraMath.inverse(
                originFromDevice * deviceFromEye) else { return nil }
        let planeFromQuad = simd_float4x4(diagonal: SIMD4<Float>(size.x / 2, size.y / 2, 1, 1))
        let clipFromQuad = clipFromEye * eyeFromOrigin * originFromPlane * planeFromQuad
        return VisionImmersiveCameraMath.isFinite(clipFromQuad) ? clipFromQuad : nil
    }

    private static func xyz(_ column: SIMD4<Float>) -> SIMD3<Float> {
        SIMD3<Float>(column.x, column.y, column.z)
    }
}

nonisolated enum VisionImmersiveCameraMath {
    /// Builds paired view cameras using the head pose captured once at immersive entry as the
    /// game-camera origin. Later head motion is therefore relative to Jak's existing third-person
    /// camera rather than replacing it with a head-locked or world-space screen.
    static func makeCameras(originFromDevice: simd_float4x4,
                            deviceFromEyes: [simd_float4x4],
                            clipFromEyes: [simd_float4x4],
                            aspectRatios: [Float],
                            entryOriginFromGameCameraMeters: simd_float4x4,
                            binocularCullClipFromDevice: simd_float4x4,
                            skyGeneration: Bool = false)
        -> [VisionImmersiveViewCamera]? {
        let count = VisionImmersiveFrameRequest.viewCount
        guard deviceFromEyes.count == count, clipFromEyes.count == count,
              aspectRatios.count == count,
              isFinite(originFromDevice), isFinite(entryOriginFromGameCameraMeters),
              isFinite(binocularCullClipFromDevice),
              let deviceFromOrigin = inverse(originFromDevice) else { return nil }
        let binocularCullFromGameCameraMeters = binocularCullClipFromDevice
            * deviceFromOrigin * entryOriginFromGameCameraMeters
        guard isFinite(binocularCullFromGameCameraMeters) else { return nil }
        var gameCameraFromHead: simd_float4x4?
        if skyGeneration {
            guard let common = self.gameCameraFromHead(
                originFromDevice: originFromDevice,
                entryOriginFromGameCameraMeters: entryOriginFromGameCameraMeters) else { return nil }
            gameCameraFromHead = common
        }

        var cameras: [VisionImmersiveViewCamera] = []
        cameras.reserveCapacity(count)
        for index in 0..<count {
            let originFromEye = originFromDevice * deviceFromEyes[index]
            guard aspectRatios[index].isFinite, aspectRatios[index] > 0,
                  isFinite(deviceFromEyes[index]), isFinite(clipFromEyes[index]),
                  let eyeFromOrigin = inverse(originFromEye) else { return nil }
            let eyeFromGameCameraMeters = eyeFromOrigin
                * entryOriginFromGameCameraMeters
            guard isFinite(eyeFromGameCameraMeters) else { return nil }
            cameras.append(VisionImmersiveViewCamera(
                clipFromEye: clipFromEyes[index],
                eyeFromGameCameraMeters: eyeFromGameCameraMeters,
                binocularCullFromGameCameraMeters: binocularCullFromGameCameraMeters,
                aspectRatio: aspectRatios[index],
                hudClipFromScreenClip: hudClipFromScreenClip(
                    deviceFromEye: deviceFromEyes[index], clipFromEye: clipFromEyes[index]),
                gameCameraFromHead: gameCameraFromHead
            ))
        }
        return cameras
    }

    /// Maps game homogeneous NDC (x, y, z, w) to (0.8x, 0.6y, -2w, w) in device meters: a
    /// 1.6 x 1.2 m plane 2 m ahead of the device. The original z is ignored.
    static let hudPlaneFromScreenClip = simd_float4x4(columns: (
        SIMD4<Float>(0.8, 0, 0, 0),
        SIMD4<Float>(0, 0.6, 0, 0),
        SIMD4<Float>(0, 0, 0, 0),
        SIMD4<Float>(0, 0, -2, 1)
    ))

    /// Head-locked HUD clip for one eye. It uses only the full device-from-eye and projection, so
    /// it is independent of head pose; nil if either input or the result is non-finite.
    static func hudClipFromScreenClip(deviceFromEye: simd_float4x4,
                                      clipFromEye: simd_float4x4) -> simd_float4x4? {
        guard isFinite(deviceFromEye), isFinite(clipFromEye),
              let eyeFromDevice = inverse(deviceFromEye) else { return nil }
        let result = clipFromEye * eyeFromDevice * hudPlaneFromScreenClip
        return isFinite(result) ? result : nil
    }

    static let rotationTolerance: Float = 1e-3

    /// Common head rotation for sky generation: the rotation part of
    /// inverse(entryOriginFromGameCameraMeters) * originFromDevice, translation dropped. It never
    /// depends on per-eye transforms. Nil unless the result is a proper rotation.
    static func gameCameraFromHead(originFromDevice: simd_float4x4,
                                   entryOriginFromGameCameraMeters: simd_float4x4)
        -> simd_float4x4? {
        guard isFinite(originFromDevice),
              let gameCameraFromOrigin = inverse(entryOriginFromGameCameraMeters) else { return nil }
        let full = gameCameraFromOrigin * originFromDevice
        var rotation = full
        rotation.columns.3 = SIMD4<Float>(0, 0, 0, 1)
        return isProperRotation(rotation) ? rotation : nil
    }

    /// Orthonormal 3x3 with determinant near +1, zero translation, and an affine bottom row.
    static func isProperRotation(_ matrix: simd_float4x4,
                                 tolerance: Float = rotationTolerance) -> Bool {
        guard isFinite(matrix), tolerance.isFinite, tolerance >= 0,
              matrix.columns.0.w == 0, matrix.columns.1.w == 0, matrix.columns.2.w == 0,
              matrix.columns.3 == SIMD4<Float>(0, 0, 0, 1) else { return false }
        let basis = simd_float3x3(
            SIMD3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z),
            SIMD3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z),
            SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z))
        let gram = basis.transpose * basis
        for column in 0..<3 {
            for row in 0..<3 where abs(gram[column][row] - (row == column ? 1 : 0)) > tolerance {
                return false
            }
        }
        return abs(simd_determinant(basis) - 1) <= tolerance
    }

    /// Both eyes disabled, or both carrying the same proper rotation.
    static func isValidSkyGenerationPair(_ rotations: [simd_float4x4?]) -> Bool {
        guard rotations.count == VisionImmersiveFrameRequest.viewCount else { return false }
        switch (rotations[0], rotations[1]) {
        case (nil, nil): return true
        case (let left?, let right?):
            return isProperRotation(left) && left == right
        default: return false
        }
    }

    static func inverse(_ matrix: simd_float4x4) -> simd_float4x4? {
        let determinant = simd_determinant(matrix)
        guard determinant.isFinite, abs(determinant) > 1e-8 else { return nil }
        let result = simd_inverse(matrix)
        return isFinite(result) ? result : nil
    }

    static func isFinite(_ matrix: simd_float4x4) -> Bool {
        columns(matrix).allSatisfy { $0.allSatisfy(\.isFinite) }
    }

    static func near(_ lhs: simd_float4x4, _ rhs: simd_float4x4,
                     tolerance: Float) -> Bool {
        zip(columns(lhs), columns(rhs)).allSatisfy { left, right in
            zip(left, right).allSatisfy { abs($0 - $1) <= tolerance }
        }
    }

    private static func columns(_ matrix: simd_float4x4) -> [[Float]] {
        [
            [matrix.columns.0.x, matrix.columns.0.y,
             matrix.columns.0.z, matrix.columns.0.w],
            [matrix.columns.1.x, matrix.columns.1.y,
             matrix.columns.1.z, matrix.columns.1.w],
            [matrix.columns.2.x, matrix.columns.2.y,
             matrix.columns.2.z, matrix.columns.2.w],
            [matrix.columns.3.x, matrix.columns.3.y,
             matrix.columns.3.z, matrix.columns.3.w],
        ]
    }
}
#endif
