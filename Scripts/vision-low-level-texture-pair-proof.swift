import CryptoKit
import Foundation
import Metal
import RealityKit

private enum ProofError: Error, CustomStringConvertible {
    case unavailable(String)
    case submission(String)
    case validation(String)

    var description: String {
        switch self {
        case .unavailable(let message), .submission(let message), .validation(let message):
            return message
        }
    }
}

private enum Eye: UInt8 {
    case left = 0xa5
    case right = 0x5a
}

private struct CompletedPair {
    let left: Data
    let right: Data
}

@MainActor
private final class PairedLowLevelTextureProof {
    private static let width = 16
    private static let height = 16
    private static let bytesPerPixel = 4
    private static let bytesPerRow = 256

    private let device: any MTLDevice
    private let commandQueue: any MTLCommandQueue
    private let leftTexture: LowLevelTexture
    private let rightTexture: LowLevelTexture
    private let retainedTextureResources: [TextureResource]

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ProofError.unavailable("Metal is unavailable")
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw ProofError.unavailable("Metal command queue creation failed")
        }

        let descriptor = LowLevelTexture.Descriptor(
            pixelFormat: .bgra8Unorm,
            width: Self.width,
            height: Self.height,
            depth: 1,
            mipmapLevelCount: 1,
            textureUsage: [.shaderRead, .renderTarget]
        )
        let leftTexture = try LowLevelTexture(descriptor: descriptor)
        let rightTexture = try LowLevelTexture(descriptor: descriptor)

        self.device = device
        self.commandQueue = commandQueue
        self.leftTexture = leftTexture
        self.rightTexture = rightTexture
        self.retainedTextureResources = [
            try TextureResource(from: leftTexture),
            try TextureResource(from: rightTexture),
        ]
    }

    func run(frameCount: Int) throws -> String {
        guard frameCount >= 256 else {
            throw ProofError.validation("proof must exercise hundreds of frames")
        }

        var actualAggregate = SHA256()
        var expectedAggregate = SHA256()

        for sequence in 0..<frameCount {
            let completed = try submitPair(sequence: sequence)
            let expectedLeft = expectedPixels(sequence: sequence, eye: .left)
            let expectedRight = expectedPixels(sequence: sequence, eye: .right)

            try validate(completed.left, sequence: sequence, eye: .left)
            try validate(completed.right, sequence: sequence, eye: .right)
            guard completed.left != completed.right else {
                throw ProofError.validation("frame \(sequence) produced identical left/right pixels")
            }

            let leftHash = SHA256.hash(data: completed.left)
            let rightHash = SHA256.hash(data: completed.right)
            guard leftHash != rightHash else {
                throw ProofError.validation("frame \(sequence) produced identical left/right hashes")
            }
            guard completed.left == expectedLeft, completed.right == expectedRight else {
                throw ProofError.validation("frame \(sequence) readback did not match its deterministic pair")
            }

            actualAggregate.update(data: completed.left)
            actualAggregate.update(data: completed.right)
            expectedAggregate.update(data: expectedLeft)
            expectedAggregate.update(data: expectedRight)
        }

        let actualHash = hexadecimal(actualAggregate.finalize())
        let expectedHash = hexadecimal(expectedAggregate.finalize())
        guard actualHash == expectedHash else {
            throw ProofError.validation(
                "aggregate hash mismatch: actual=\(actualHash) expected=\(expectedHash)"
            )
        }
        return actualHash
    }

    private func submitPair(sequence: Int) throws -> CompletedPair {
        let readbackLength = Self.bytesPerRow * Self.height
        guard let leftReadback = device.makeBuffer(length: readbackLength, options: .storageModeShared),
              let rightReadback = device.makeBuffer(length: readbackLength, options: .storageModeShared) else {
            throw ProofError.submission("frame \(sequence) readback buffer creation failed")
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw ProofError.submission("frame \(sequence) command buffer creation failed")
        }
        commandBuffer.label = "GOALPad paired LowLevelTexture frame \(sequence)"

        let leftReplacement = leftTexture.replace(using: commandBuffer)
        let rightReplacement = rightTexture.replace(using: commandBuffer)
        try encodeClear(
            texture: leftReplacement,
            color: clearColor(sequence: sequence, eye: .left),
            label: "left sequence \(sequence)",
            commandBuffer: commandBuffer
        )
        try encodeClear(
            texture: rightReplacement,
            color: clearColor(sequence: sequence, eye: .right),
            label: "right sequence \(sequence)",
            commandBuffer: commandBuffer
        )

        guard let blit = commandBuffer.makeBlitCommandEncoder() else {
            throw ProofError.submission("frame \(sequence) blit encoder creation failed")
        }
        blit.label = "paired readback sequence \(sequence)"
        encodeReadback(texture: leftReplacement, buffer: leftReadback, encoder: blit)
        encodeReadback(texture: rightReplacement, buffer: rightReadback, encoder: blit)
        blit.endEncoding()

        commandBuffer.commit()
        // This standalone CLI has no game or UI loop; completion gates only deterministic readback.
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            let detail = commandBuffer.error?.localizedDescription ?? "status \(commandBuffer.status.rawValue)"
            throw ProofError.submission("frame \(sequence) command buffer failed: \(detail)")
        }

        return CompletedPair(
            left: activePixels(from: leftReadback),
            right: activePixels(from: rightReadback)
        )
    }

    private func encodeClear(
        texture: any MTLTexture,
        color: MTLClearColor,
        label: String,
        commandBuffer: any MTLCommandBuffer
    ) throws {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = color
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            throw ProofError.submission("\(label) render encoder creation failed")
        }
        encoder.label = label
        encoder.endEncoding()
    }

    private func encodeReadback(
        texture: any MTLTexture,
        buffer: any MTLBuffer,
        encoder: any MTLBlitCommandEncoder
    ) {
        encoder.copy(
            from: texture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: Self.width, height: Self.height, depth: 1),
            to: buffer,
            destinationOffset: 0,
            destinationBytesPerRow: Self.bytesPerRow,
            destinationBytesPerImage: Self.bytesPerRow * Self.height
        )
    }

    private func activePixels(from buffer: any MTLBuffer) -> Data {
        let rowLength = Self.width * Self.bytesPerPixel
        let base = buffer.contents().assumingMemoryBound(to: UInt8.self)
        var result = Data()
        result.reserveCapacity(rowLength * Self.height)
        for row in 0..<Self.height {
            result.append(base.advanced(by: row * Self.bytesPerRow), count: rowLength)
        }
        return result
    }

    private func expectedPixels(sequence: Int, eye: Eye) -> Data {
        let pixel = encodedPixel(sequence: sequence, eye: eye)
        return Data(Array(repeating: pixel, count: Self.width * Self.height).flatMap { $0 })
    }

    private func validate(_ pixels: Data, sequence: Int, eye: Eye) throws {
        let expected = encodedPixel(sequence: sequence, eye: eye)
        let bytes = [UInt8](pixels)
        for pixelOffset in stride(from: 0, to: bytes.count, by: Self.bytesPerPixel) {
            let actual = Array(bytes[pixelOffset..<(pixelOffset + Self.bytesPerPixel)])
            guard actual == expected else {
                let pixelIndex = pixelOffset / Self.bytesPerPixel
                throw ProofError.validation(
                    "frame \(sequence) \(eye) pixel \(pixelIndex) was \(actual), expected \(expected)"
                )
            }
            let decodedSequence = Int(actual[2]) | (Int(actual[1]) << 8) | (Int(actual[0]) << 16)
            guard decodedSequence == sequence, actual[3] == eye.rawValue else {
                throw ProofError.validation("frame \(sequence) \(eye) sequence or eye marker mismatched")
            }
        }
    }

    private func clearColor(sequence: Int, eye: Eye) -> MTLClearColor {
        let pixel = encodedPixel(sequence: sequence, eye: eye)
        return MTLClearColor(
            red: Double(pixel[2]) / 255.0,
            green: Double(pixel[1]) / 255.0,
            blue: Double(pixel[0]) / 255.0,
            alpha: Double(pixel[3]) / 255.0
        )
    }

    private func encodedPixel(sequence: Int, eye: Eye) -> [UInt8] {
        precondition(sequence >= 0 && sequence <= 0x00ff_ffff)
        return [
            UInt8((sequence >> 16) & 0xff),
            UInt8((sequence >> 8) & 0xff),
            UInt8(sequence & 0xff),
            eye.rawValue,
        ]
    }

    private func hexadecimal<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

@main
private enum VisionLowLevelTexturePairProofMain {
    @MainActor
    static func main() {
        do {
            let frameCount = 512
            let proof = try PairedLowLevelTextureProof()
            let aggregateHash = try proof.run(frameCount: frameCount)
            print(
                "LowLevelTexture paired-update proof passed: frames=\(frameCount) "
                    + "size=16x16 sequence_matched=true distinct=true "
                    + "aggregate_sha256=\(aggregateHash)"
            )
        } catch {
            print("LowLevelTexture paired-update proof failed: \(error)")
            Foundation.exit(1)
        }
    }
}
