#if GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE
import Foundation
import Metal
import os

/// Bounded aggregate-only evidence for native and resolved immersive frames. Four 8x8 GPU sample
/// grids reach shared memory after command-buffer completion; only counts and depth ranges are
/// serialized, never full images or individual samples.
nonisolated final class VisionImmersiveRenderEvidenceSampler: @unchecked Sendable {
    static let sampleGridSize = 8
    static let samplesPerEye = sampleGridSize * sampleGridSize
    static let nonBlackThreshold: Float = 1.0 / 1_024.0

    struct ResolvedEye {
        let colorTexture: any MTLTexture
        let depthTexture: any MTLTexture
        let originX: Double
        let originY: Double
        let width: Double
        let height: Double
        let sliceIndex: Int
    }

    struct Aggregate: Codable, Equatable, Sendable {
        let sampleCount: Int
        let nonBlackRGBCount: Int
        let finiteDepthCount: Int
        let positiveDepthCount: Int
        let minimumDepth: Float?
        let maximumDepth: Float?
    }

    struct EyeEvidence: Codable, Equatable, Sendable {
        let source: Aggregate
        let resolved: Aggregate
    }

    struct Observation: Codable, Equatable, Sendable {
        let nativeRenderSerial: UInt64
        let poseIdentity: UInt64
        let compositorFrameIndex: UInt64
        let presentationTime: TimeInterval
        let fade: Float
        let resolvedVisible: Bool
        let eyes: [EyeEvidence]
    }

    struct Completion: Sendable {
        let observation: Observation
        let becameVisible: Bool
    }

    struct Ticket: @unchecked Sendable {
        fileprivate let buffer: any MTLBuffer
        fileprivate let metadata: Metadata
    }

    enum SamplerError: LocalizedError {
        case missingKernel(String)
        case pipeline(String)
        case invalidTextures
        case bufferAllocation
        case commandEncoder

        var errorDescription: String? {
            switch self {
            case .missingKernel(let name):
                "The immersive render evidence kernel \(name) is missing."
            case .pipeline(let message):
                "The immersive render evidence pipeline failed: \(message)"
            case .invalidTextures:
                "The immersive render evidence textures or view regions are invalid."
            case .bufferAllocation:
                "Metal could not allocate the bounded immersive render evidence buffer."
            case .commandEncoder:
                "Metal could not encode immersive render evidence sampling."
            }
        }
    }

    fileprivate struct Metadata: Sendable {
        let nativeRenderSerial: UInt64
        let poseIdentity: UInt64
        let compositorFrameIndex: UInt64
        let presentationTime: TimeInterval
        let fade: Float
    }

    private struct SampleRegion {
        var region: SIMD4<Float>
        var parameters: SIMD4<UInt32>
    }

    private struct State {
        var firstSampleUptime: TimeInterval?
        var firstVisibleUptime: TimeInterval?
        var timedOut = false
        var scheduledSerials: Set<UInt64> = []
        var inFlightSerials: Set<UInt64> = []
        var firstPreVisible: Observation?
        var lastPreVisible: Observation?
        var firstVisible: Observation?
        var advancing: [Observation] = []
    }

    private struct Document: Codable, Sendable {
        let schemaVersion: Int
        let attempt: UInt64
        let status: String
        let nonBlackThreshold: Float
        let sampleGridWidth: Int
        let sampleGridHeight: Int
        let observations: [Observation]
        let updatedAt: Date
    }

    private struct ScheduleDecision {
        let shouldSchedule: Bool
        let timeoutDocument: Document?
    }

    private static let sourceLeftOffset = 0
    private static let sourceRightOffset = samplesPerEye
    private static let resolvedLeftOffset = samplesPerEye * 2
    private static let resolvedRightOffset = samplesPerEye * 3
    private static let totalSamples = samplesPerEye * 4
    private static let maximumInFlight = 2
    private static let maximumScheduled = 256
    private static let captureTimeoutSeconds: TimeInterval = 3
    private static let advancingFrameCount = 3

    private let device: any MTLDevice
    private let sample2DPipeline: any MTLComputePipelineState
    private let sample2DArrayPipeline: any MTLComputePipelineState
    private let attempt: UInt64
    private let outputURL: URL?
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let writerQueue = DispatchQueue(
        label: "com.zephyrstudiosllc.eco.immersive-render-evidence",
        qos: .utility)

    init(device: any MTLDevice, library: any MTLLibrary, attempt: UInt64,
         outputURL: URL? = VisionImmersiveRenderEvidenceSampler.defaultOutputURL) throws {
        self.device = device
        self.attempt = attempt
        self.outputURL = outputURL
        guard let function2D = library.makeFunction(name: "vision_immersive_sample_2d") else {
            throw SamplerError.missingKernel("vision_immersive_sample_2d")
        }
        guard let function2DArray = library.makeFunction(
            name: "vision_immersive_sample_2d_array") else {
            throw SamplerError.missingKernel("vision_immersive_sample_2d_array")
        }
        do {
            sample2DPipeline = try device.makeComputePipelineState(function: function2D)
            sample2DArrayPipeline = try device.makeComputePipelineState(function: function2DArray)
        } catch {
            throw SamplerError.pipeline(error.localizedDescription)
        }
    }

    func encodeIfNeeded(nativeColorTextures: [any MTLTexture],
                        nativeDepthTextures: [any MTLTexture],
                        resolvedEyes: [ResolvedEye],
                        fade: Float,
                        nativeRenderSerial: UInt64,
                        poseIdentity: UInt64,
                        compositorFrameIndex: UInt64,
                        presentationTime: TimeInterval,
                        commandBuffer: any MTLCommandBuffer) throws -> Ticket? {
        let metadata = Metadata(
            nativeRenderSerial: nativeRenderSerial,
            poseIdentity: poseIdentity,
            compositorFrameIndex: compositorFrameIndex,
            presentationTime: presentationTime,
            fade: fade
        )
        let decision = schedule(metadata)
        if let document = decision.timeoutDocument { write(document) }
        guard decision.shouldSchedule else { return nil }
        guard validate(nativeColorTextures: nativeColorTextures,
                       nativeDepthTextures: nativeDepthTextures,
                       resolvedEyes: resolvedEyes) else {
            throw SamplerError.invalidTextures
        }
        let length = Self.totalSamples * MemoryLayout<SIMD4<Float>>.stride
        guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
            throw SamplerError.bufferAllocation
        }
        buffer.label = "Dark Eco bounded immersive render evidence"
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw SamplerError.commandEncoder
        }
        encoder.label = "Dark Eco aggregate immersive render evidence"

        try encodeEye(
            color: nativeColorTextures[0], depth: nativeDepthTextures[0],
            region: SIMD4<Float>(0, 0, Float(nativeColorTextures[0].width),
                                 Float(nativeColorTextures[0].height)),
            sliceIndex: 0, outputOffset: Self.sourceLeftOffset,
            buffer: buffer, encoder: encoder)
        try encodeEye(
            color: nativeColorTextures[1], depth: nativeDepthTextures[1],
            region: SIMD4<Float>(0, 0, Float(nativeColorTextures[1].width),
                                 Float(nativeColorTextures[1].height)),
            sliceIndex: 0, outputOffset: Self.sourceRightOffset,
            buffer: buffer, encoder: encoder)
        try encodeEye(
            color: resolvedEyes[0].colorTexture, depth: resolvedEyes[0].depthTexture,
            region: Self.region(resolvedEyes[0]), sliceIndex: resolvedEyes[0].sliceIndex,
            outputOffset: Self.resolvedLeftOffset, buffer: buffer, encoder: encoder)
        try encodeEye(
            color: resolvedEyes[1].colorTexture, depth: resolvedEyes[1].depthTexture,
            region: Self.region(resolvedEyes[1]), sliceIndex: resolvedEyes[1].sliceIndex,
            outputOffset: Self.resolvedRightOffset, buffer: buffer, encoder: encoder)
        encoder.endEncoding()
        return Ticket(buffer: buffer, metadata: metadata)
    }

    /// Reads the shared aggregate buffer only from the command buffer's completion handler.
    func complete(_ ticket: Ticket) -> Completion {
        let values = UnsafeBufferPointer(
            start: ticket.buffer.contents().assumingMemoryBound(to: SIMD4<Float>.self),
            count: Self.totalSamples)
        let sourceLeft = Self.aggregate(values: values, offset: Self.sourceLeftOffset)
        let sourceRight = Self.aggregate(values: values, offset: Self.sourceRightOffset)
        let resolvedLeft = Self.aggregate(values: values, offset: Self.resolvedLeftOffset)
        let resolvedRight = Self.aggregate(values: values, offset: Self.resolvedRightOffset)
        let visible = resolvedLeft.nonBlackRGBCount > 0 && resolvedRight.nonBlackRGBCount > 0
        let observation = Observation(
            nativeRenderSerial: ticket.metadata.nativeRenderSerial,
            poseIdentity: ticket.metadata.poseIdentity,
            compositorFrameIndex: ticket.metadata.compositorFrameIndex,
            presentationTime: ticket.metadata.presentationTime,
            fade: ticket.metadata.fade,
            resolvedVisible: visible,
            eyes: [
                EyeEvidence(source: sourceLeft, resolved: resolvedLeft),
                EyeEvidence(source: sourceRight, resolved: resolvedRight),
            ]
        )

        let update = state.withLock { state -> (Bool, Document) in
            state.inFlightSerials.remove(ticket.metadata.nativeRenderSerial)
            let becameVisible = visible && state.firstVisible == nil
            if becameVisible {
                state.firstVisible = observation
                state.firstVisibleUptime = ProcessInfo.processInfo.systemUptime
            } else if let visibleSerial = state.firstVisible?.nativeRenderSerial,
                      observation.nativeRenderSerial > visibleSerial,
                      !state.advancing.contains(where: {
                          $0.nativeRenderSerial == observation.nativeRenderSerial
                      }), state.advancing.count < Self.advancingFrameCount {
                state.advancing.append(observation)
                state.advancing.sort { $0.nativeRenderSerial < $1.nativeRenderSerial }
            } else if state.firstVisible == nil {
                state.firstPreVisible = state.firstPreVisible ?? observation
                state.lastPreVisible = observation
            }
            return (becameVisible, makeDocument(state))
        }
        write(update.1)
        return Completion(observation: observation, becameVisible: update.0)
    }

    private func schedule(_ metadata: Metadata) -> ScheduleDecision {
        state.withLock { state in
            let now = ProcessInfo.processInfo.systemUptime
            if state.firstSampleUptime == nil {
                state.firstSampleUptime = now
            }
            guard metadata.presentationTime.isFinite, metadata.fade.isFinite,
                  !state.timedOut else {
                return ScheduleDecision(shouldSchedule: false, timeoutDocument: nil)
            }
            if let firstVisible = state.firstVisible {
                if state.advancing.count < Self.advancingFrameCount,
                   let visibleUptime = state.firstVisibleUptime,
                   now - visibleUptime > Self.captureTimeoutSeconds {
                    state.timedOut = true
                    return ScheduleDecision(
                        shouldSchedule: false, timeoutDocument: makeDocument(state))
                }
                let alreadyScheduled = state.scheduledSerials.lazy.filter {
                    $0 > firstVisible.nativeRenderSerial
                }.count
                guard metadata.nativeRenderSerial > firstVisible.nativeRenderSerial,
                      alreadyScheduled < Self.advancingFrameCount else {
                    return ScheduleDecision(shouldSchedule: false, timeoutDocument: nil)
                }
            } else if let start = state.firstSampleUptime,
                      now - start > Self.captureTimeoutSeconds {
                state.timedOut = true
                return ScheduleDecision(
                    shouldSchedule: false, timeoutDocument: makeDocument(state))
            }
            guard state.scheduledSerials.count < Self.maximumScheduled,
                  state.inFlightSerials.count < Self.maximumInFlight,
                  !state.scheduledSerials.contains(metadata.nativeRenderSerial) else {
                return ScheduleDecision(shouldSchedule: false, timeoutDocument: nil)
            }
            state.scheduledSerials.insert(metadata.nativeRenderSerial)
            state.inFlightSerials.insert(metadata.nativeRenderSerial)
            return ScheduleDecision(shouldSchedule: true, timeoutDocument: nil)
        }
    }

    private func encodeEye(color: any MTLTexture,
                           depth: any MTLTexture,
                           region: SIMD4<Float>,
                           sliceIndex: Int,
                           outputOffset: Int,
                           buffer: any MTLBuffer,
                           encoder: any MTLComputeCommandEncoder) throws {
        let pipeline: any MTLComputePipelineState
        switch color.textureType {
        case .type2D:
            guard depth.textureType == .type2D, sliceIndex == 0 else {
                throw SamplerError.invalidTextures
            }
            pipeline = sample2DPipeline
        case .type2DArray:
            guard depth.textureType == .type2DArray,
                  (0..<color.arrayLength).contains(sliceIndex),
                  (0..<depth.arrayLength).contains(sliceIndex) else {
                throw SamplerError.invalidTextures
            }
            pipeline = sample2DArrayPipeline
        default:
            throw SamplerError.invalidTextures
        }
        var uniforms = SampleRegion(
            region: region,
            parameters: SIMD4<UInt32>(UInt32(outputOffset), UInt32(sliceIndex), 0, 0))
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(color, index: 0)
        encoder.setTexture(depth, index: 1)
        encoder.setBuffer(buffer, offset: 0, index: 0)
        encoder.setBytes(&uniforms, length: MemoryLayout<SampleRegion>.stride, index: 1)
        encoder.dispatchThreads(
            MTLSize(width: Self.sampleGridSize, height: Self.sampleGridSize, depth: 1),
            threadsPerThreadgroup: MTLSize(width: Self.sampleGridSize,
                                          height: Self.sampleGridSize, depth: 1))
    }

    private func validate(nativeColorTextures: [any MTLTexture],
                          nativeDepthTextures: [any MTLTexture],
                          resolvedEyes: [ResolvedEye]) -> Bool {
        guard nativeColorTextures.count == 2, nativeDepthTextures.count == 2,
              resolvedEyes.count == 2 else { return false }
        for (color, depth) in zip(nativeColorTextures, nativeDepthTextures) {
            guard color.device === device, depth.device === device,
                  color.textureType == .type2D, depth.textureType == .type2D,
                  color.usage.contains(.shaderRead), depth.usage.contains(.shaderRead),
                  color.width > 0, color.height > 0,
                  color.width == depth.width, color.height == depth.height else { return false }
        }
        for eye in resolvedEyes {
            let values = [eye.originX, eye.originY, eye.width, eye.height]
            guard eye.colorTexture.device === device, eye.depthTexture.device === device,
                  eye.colorTexture.textureType == eye.depthTexture.textureType,
                  eye.colorTexture.usage.contains(.shaderRead),
                  eye.depthTexture.usage.contains(.shaderRead),
                  values.allSatisfy(\.isFinite), eye.originX >= 0, eye.originY >= 0,
                  eye.width > 0, eye.height > 0,
                  eye.originX + eye.width <= Double(eye.colorTexture.width),
                  eye.originY + eye.height <= Double(eye.colorTexture.height) else { return false }
        }
        return true
    }

    private func makeDocument(_ state: State) -> Document {
        var observations: [Observation] = []
        if let first = state.firstPreVisible { observations.append(first) }
        if let last = state.lastPreVisible,
           last.nativeRenderSerial != state.firstPreVisible?.nativeRenderSerial {
            observations.append(last)
        }
        if let visible = state.firstVisible { observations.append(visible) }
        observations.append(contentsOf: state.advancing.prefix(Self.advancingFrameCount))
        let status: String
        if state.timedOut, state.firstVisible == nil {
            status = "timedOutWaitingForVisibleFrame"
        } else if state.timedOut {
            status = "timedOutCollectingAdvancingFrames"
        } else if state.firstVisible == nil {
            status = "waitingForVisibleFrame"
        } else if state.advancing.count < Self.advancingFrameCount {
            status = "collectingAdvancingFrames"
        } else {
            status = "complete"
        }
        return Document(
            schemaVersion: 1,
            attempt: attempt,
            status: status,
            nonBlackThreshold: Self.nonBlackThreshold,
            sampleGridWidth: Self.sampleGridSize,
            sampleGridHeight: Self.sampleGridSize,
            observations: observations,
            updatedAt: Date()
        )
    }

    private func write(_ document: Document) {
        guard let outputURL else { return }
        writerQueue.async {
            do {
                try FileManager.default.createDirectory(
                    at: outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(document).write(to: outputURL, options: .atomic)
            } catch {
                // Diagnostics never alter gameplay. A pipeline/encoding failure is fatal earlier;
                // a cache write failure leaves the in-memory readiness result authoritative.
            }
        }
    }

    private static func aggregate(values: UnsafeBufferPointer<SIMD4<Float>>,
                                  offset: Int) -> Aggregate {
        var nonBlack = 0
        var finiteDepth = 0
        var positiveDepth = 0
        var minimumDepth: Float?
        var maximumDepth: Float?
        for index in offset..<(offset + samplesPerEye) {
            let sample = values[index]
            if sample.x.isFinite, sample.y.isFinite, sample.z.isFinite,
               max(sample.x, max(sample.y, sample.z)) > nonBlackThreshold {
                nonBlack += 1
            }
            if sample.w.isFinite {
                finiteDepth += 1
                if sample.w > 0 { positiveDepth += 1 }
                minimumDepth = minimumDepth.map { min($0, sample.w) } ?? sample.w
                maximumDepth = maximumDepth.map { max($0, sample.w) } ?? sample.w
            }
        }
        return Aggregate(
            sampleCount: samplesPerEye,
            nonBlackRGBCount: nonBlack,
            finiteDepthCount: finiteDepth,
            positiveDepthCount: positiveDepth,
            minimumDepth: minimumDepth,
            maximumDepth: maximumDepth
        )
    }

    private static func region(_ eye: ResolvedEye) -> SIMD4<Float> {
        SIMD4<Float>(Float(eye.originX), Float(eye.originY),
                     Float(eye.width), Float(eye.height))
    }

    private static var defaultOutputURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "DarkEcoDiagnostics", directoryHint: .isDirectory)
            .appending(path: "immersive-render-evidence.json", directoryHint: .notDirectory)
    }
}
#endif
