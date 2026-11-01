#if os(visionOS) && GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE
import Foundation
import OSLog

nonisolated private let immersiveCameraContractLog = Logger(
    subsystem: "com.zephyrstudiosllc.eco",
    category: "ImmersiveCameraContract"
)

/// One public CompositorServices camera snapshot for offline architecture validation. This is
/// diagnostic evidence only; rendering does not consume the saved snapshot.
nonisolated struct VisionImmersiveCameraContract: Encodable, Sendable {
    struct View: Encodable, Sendable {
        struct Viewport: Encodable, Sendable {
            let originX: Double
            let originY: Double
            let width: Double
            let height: Double
            let nearDepth: Double
            let farDepth: Double
        }

        let index: Int
        let projectionRightUpBackColumnMajor: [Float]
        let deviceFromViewColumnMajor: [Float]
        let textureIndex: Int
        let sliceIndex: Int
        let viewport: Viewport
    }

    let schemaVersion: Int
    let captureScope: String
    let coordinateConvention: String
    let attempt: UInt64
    let layerFrameIndex: UInt64
    let frameDrawableCount: Int
    let capturedDrawableIndex: Int
    let drawableTarget: String
    let drawablePresentationFrameIndex: UInt64
    let drawablePresentationTimestamp: TimeInterval
    let gameFrameAvailable: Bool
    let gameRenderWidth: Int
    let gameRenderHeight: Int
    let deviceAnchorWasAssigned: Bool
    let originFromDeviceColumnMajor: [Float]?
    let entryOriginFromGameCameraMetersColumnMajor: [Float]
    let configurationDefaultDepthRange: [Float]
    let binocularCullClipFromDeviceColumnMajor: [Float]
    let binocularCullIncreaseTangents: [Float]
    let views: [View]
}

nonisolated enum VisionImmersiveCameraContractWriter {
    static let relativePath = "Library/Caches/DarkEcoDiagnostics/immersive-camera-contract.json"

    static func write(_ contract: VisionImmersiveCameraContract) {
        DispatchQueue.global(qos: .utility).async {
            do {
                let fileManager = FileManager.default
                let caches = try fileManager.url(
                    for: .cachesDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                let directory = caches.appendingPathComponent(
                    "DarkEcoDiagnostics", isDirectory: true)
                try fileManager.createDirectory(
                    at: directory, withIntermediateDirectories: true)
                let destination = directory.appendingPathComponent(
                    "immersive-camera-contract.json", isDirectory: false)

                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                var data = try encoder.encode(contract)
                data.append(0x0A)
                try data.write(to: destination, options: .atomic)
                immersiveCameraContractLog.notice(
                    "Captured one immersive camera contract at \(relativePath, privacy: .public)"
                )
            } catch {
                immersiveCameraContractLog.error("""
                    Immersive camera contract capture failed without stopping presentation: \
                    \(error.localizedDescription, privacy: .public)
                    """)
            }
        }
    }
}
#endif
