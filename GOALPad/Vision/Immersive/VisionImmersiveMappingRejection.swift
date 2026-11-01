#if GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE
import Foundation

/// Bounded metadata for the first compositor drawable mapping the presenter rejected. It records
/// only texture shapes and view mappings: no poses, projections, pixels, timestamps, or assets.
nonisolated enum VisionImmersiveMappingRejection {
    static let schemaVersion = 1
    /// At most this many drawables get detailed entries.
    static let maximumDrawableCount = 4
    /// Global limits across all detailed drawables, so total work and file size stay bounded.
    static let maximumViewCount = 8
    static let maximumTextureCount = 8

    enum Guard: String, Codable, Sendable {
        case builtInCount
        case rateMaps
        case viewCount
        case passPlan
        case requestViewCount
    }

    enum Target: String, Codable, Sendable {
        case builtIn
        case capture
        case unknown
    }

    enum TextureRole: String, Codable, Sendable {
        case color
        case depth
    }

    /// JSON cannot carry NaN or infinity, so every viewport scalar keeps an optional finite value,
    /// an explicit classification, and its round-trip text.
    struct Scalar: Codable, Equatable, Sendable {
        enum Kind: String, Codable, Sendable {
            case finite
            case nan
            case positiveInfinity
            case negativeInfinity
        }

        let value: Double?
        let kind: Kind
        let text: String

        init(_ scalar: Double) {
            if scalar.isNaN {
                value = nil
                kind = .nan
            } else if scalar.isInfinite {
                value = nil
                kind = scalar > 0 ? .positiveInfinity : .negativeInfinity
            } else {
                value = scalar
                kind = .finite
            }
            text = "\(scalar)"
        }
    }

    /// Raw view values read from the compositor; viewport order matches MTLViewport.
    struct ViewInput: Sendable {
        let textureIndex: Int
        let sliceIndex: Int
        let originX: Double
        let originY: Double
        let width: Double
        let height: Double
        let nearDepth: Double
        let farDepth: Double
    }

    struct TextureInput: Sendable {
        let textureType: UInt
        let width: Int
        let height: Int
        let arrayLength: Int
    }

    struct Texture: Codable, Equatable, Sendable {
        let role: TextureRole
        let index: Int
        let textureType: UInt
        let width: Int
        let height: Int
        let arrayLength: Int
    }

    struct View: Codable, Equatable, Sendable {
        let index: Int
        let textureIndex: Int
        let sliceIndex: Int
        let originX: Scalar
        let originY: Scalar
        let width: Scalar
        let height: Scalar
        let nearDepth: Scalar
        let farDepth: Scalar
    }

    /// Counts are the drawable's true counts; `views` and `textures` hold only the entries that
    /// fit the global budget.
    struct Drawable: Codable, Equatable, Sendable {
        let index: Int
        let target: Target
        let viewCount: Int
        let rasterizationRateMapCount: Int
        let colorTextureCount: Int
        let depthTextureCount: Int
        let views: [View]
        let textures: [Texture]
    }

    struct Document: Codable, Equatable, Sendable {
        let schemaVersion: Int
        let attempt: UInt64
        let layerFrameIndex: UInt64
        let rejectedGuard: Guard
        let failingDrawableIndex: Int?
        let drawableCount: Int
        let builtInDrawableCount: Int
        let totalViewCount: Int
        let totalRasterizationRateMapCount: Int
        let totalColorTextureCount: Int
        let totalDepthTextureCount: Int
        let drawables: [Drawable]
        let omittedDrawableCount: Int
        let omittedViewCount: Int
        let omittedTextureCount: Int
    }

    /// Accessors over one source drawable. Counts are read for every drawable; detailed view and
    /// texture accessors run only for entries inside the global budget.
    struct Accessors<Source> {
        let target: (Source) -> Target
        let viewCount: (Source) -> Int
        let rasterizationRateMapCount: (Source) -> Int
        let colorTextureCount: (Source) -> Int
        let depthTextureCount: (Source) -> Int
        let view: (Source, Int) -> ViewInput
        let colorTexture: (Source, Int) -> TextureInput
        let depthTexture: (Source, Int) -> TextureInput
    }

    static func document<Source>(attempt: UInt64,
                                 layerFrameIndex: UInt64,
                                 rejectedGuard: Guard,
                                 failingDrawableIndex: Int?,
                                 drawables sources: [Source],
                                 accessors: Accessors<Source>) -> Document {
        var remainingViews = maximumViewCount
        var remainingTextures = maximumTextureCount
        var drawables: [Drawable] = []
        drawables.reserveCapacity(min(sources.count, maximumDrawableCount))
        var totalViews = 0
        var totalRateMaps = 0
        var totalColor = 0
        var totalDepth = 0
        var builtInCount = 0
        var includedViews = 0
        var includedTextures = 0
        for (drawableIndex, source) in sources.enumerated() {
            let target = accessors.target(source)
            let viewCount = max(0, accessors.viewCount(source))
            let rateMapCount = max(0, accessors.rasterizationRateMapCount(source))
            let colorCount = max(0, accessors.colorTextureCount(source))
            let depthCount = max(0, accessors.depthTextureCount(source))
            if target == .builtIn { builtInCount += 1 }
            totalViews += viewCount
            totalRateMaps += rateMapCount
            totalColor += colorCount
            totalDepth += depthCount
            guard drawableIndex < maximumDrawableCount else { continue }

            var views: [View] = []
            for viewIndex in 0..<min(viewCount, remainingViews) {
                let view = accessors.view(source, viewIndex)
                views.append(View(
                    index: viewIndex,
                    textureIndex: view.textureIndex,
                    sliceIndex: view.sliceIndex,
                    originX: Scalar(view.originX),
                    originY: Scalar(view.originY),
                    width: Scalar(view.width),
                    height: Scalar(view.height),
                    nearDepth: Scalar(view.nearDepth),
                    farDepth: Scalar(view.farDepth)))
            }
            remainingViews -= views.count

            var textures: [Texture] = []
            for (role, count, read) in [
                (TextureRole.color, colorCount, accessors.colorTexture),
                (TextureRole.depth, depthCount, accessors.depthTexture),
            ] {
                let included = min(count, remainingTextures)
                for textureIndex in 0..<included {
                    let texture = read(source, textureIndex)
                    textures.append(Texture(
                        role: role,
                        index: textureIndex,
                        textureType: texture.textureType,
                        width: texture.width,
                        height: texture.height,
                        arrayLength: texture.arrayLength))
                }
                remainingTextures -= included
            }
            includedViews += views.count
            includedTextures += textures.count
            drawables.append(Drawable(
                index: drawableIndex,
                target: target,
                viewCount: viewCount,
                rasterizationRateMapCount: rateMapCount,
                colorTextureCount: colorCount,
                depthTextureCount: depthCount,
                views: views,
                textures: textures))
        }
        return Document(
            schemaVersion: schemaVersion,
            attempt: attempt,
            layerFrameIndex: layerFrameIndex,
            rejectedGuard: rejectedGuard,
            failingDrawableIndex: failingDrawableIndex,
            drawableCount: sources.count,
            builtInDrawableCount: builtInCount,
            totalViewCount: totalViews,
            totalRasterizationRateMapCount: totalRateMaps,
            totalColorTextureCount: totalColor,
            totalDepthTextureCount: totalDepth,
            drawables: drawables,
            omittedDrawableCount: sources.count - drawables.count,
            omittedViewCount: totalViews - includedViews,
            omittedTextureCount: totalColor + totalDepth - includedTextures)
    }
}

/// Writes the first mapping rejection per attempt off the render thread. A later rejection in the
/// same or an older attempt never overwrites it; IO errors are ignored.
nonisolated final class VisionImmersiveMappingRejectionRecorder: @unchecked Sendable {
    static let relativePath = "Library/Caches/DarkEcoDiagnostics/immersive-mapping-rejection.json"
    static let shared = VisionImmersiveMappingRejectionRecorder()

    private let outputURL: URL?
    private let writerQueue = DispatchQueue(
        label: "com.zephyrstudiosllc.eco.immersive-mapping-rejection",
        qos: .utility)
    private var recordedAttempt: UInt64?

    init(outputURL: URL? = VisionImmersiveMappingRejectionRecorder.defaultOutputURL) {
        self.outputURL = outputURL
    }

    func record(_ document: VisionImmersiveMappingRejection.Document) {
        guard document.attempt != 0 else { return }
        writerQueue.async { [self] in
            if let recordedAttempt, document.attempt <= recordedAttempt { return }
            recordedAttempt = document.attempt
            write(document)
        }
    }

    /// Test synchronization only. Production callers enqueue the record and continue.
    func flush() {
        writerQueue.sync {}
    }

    private func write(_ document: VisionImmersiveMappingRejection.Document) {
        guard let outputURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(document).write(to: outputURL, options: .atomic)
        } catch {
            // Diagnostic persistence must never alter immersive presentation.
        }
    }

    private static var defaultOutputURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "DarkEcoDiagnostics", directoryHint: .isDirectory)
            .appending(path: "immersive-mapping-rejection.json", directoryHint: .notDirectory)
    }
}
#endif
