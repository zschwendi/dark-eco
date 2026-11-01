import Foundation
import Metal
import simd

// Renders GOALPad/Vision/Immersive/VisionImmersivePresentation.metal on this Mac's GPU with the
// pass plan and full-viewport policy from VisionImmersivePresentationPlan.swift, mirroring the immersive
// presenter's clear-then-draw pass structure, and reads the pixels back. This is deterministic
// presentation evidence only; it does not exercise CompositorServices or a headset.

private var failures = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("  ok   \(message)")
    } else {
        print("  FAIL \(message)")
        failures += 1
    }
}

private struct FullViewportUniforms {
    var clipFromQuad: simd_float4x4
    var fade: Float
}

private struct ViewDraw {
    let viewport: MTLViewport
    let clipFromQuad: simd_float4x4
}

private struct Renderer {
    let device: any MTLDevice
    let queue: any MTLCommandQueue
    let library: any MTLLibrary
    let depthState: any MTLDepthStencilState

    func pipeline(color: MTLPixelFormat) -> any MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "vision_immersive_screen_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "vision_immersive_screen_fragment")
        descriptor.colorAttachments[0].pixelFormat = color
        descriptor.depthAttachmentPixelFormat = .depth32Float
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            fatalError("could not build the immersive presentation pipeline for \(color)")
        }
        return pipeline
    }

    func texture(_ format: MTLPixelFormat, width: Int, height: Int, slices: Int = 1,
                 usage: MTLTextureUsage = [.renderTarget]) -> any MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = slices > 1 ? .type2DArray : .type2D
        descriptor.pixelFormat = format
        descriptor.width = width
        descriptor.height = height
        descriptor.arrayLength = slices
        descriptor.usage = usage
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)!
    }

    /// The presenter's per-pass structure: clear color to opaque black and depth to reverse-Z far,
    /// then draw every view that shares the pass across its entire viewport.
    func present(_ source: (any MTLTexture)?, fade: Float, passes: [VisionImmersivePass],
                 views: [ViewDraw], colors: [any MTLTexture], depths: [any MTLTexture],
                 pipeline: any MTLRenderPipelineState) {
        let commandBuffer = queue.makeCommandBuffer()!
        for pass in passes {
            let descriptor = MTLRenderPassDescriptor()
            descriptor.colorAttachments[0].texture = colors[pass.textureIndex]
            descriptor.colorAttachments[0].slice = pass.sliceIndex
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].storeAction = .store
            descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0,
                                                                     alpha: 1)
            descriptor.depthAttachment.texture = depths[pass.textureIndex]
            descriptor.depthAttachment.slice = pass.sliceIndex
            descriptor.depthAttachment.loadAction = .clear
            descriptor.depthAttachment.storeAction = .store
            descriptor.depthAttachment.clearDepth = 0
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)!
            if let source {
                encoder.setRenderPipelineState(pipeline)
                encoder.setDepthStencilState(depthState)
                encoder.setCullMode(.none)
                encoder.setFragmentTexture(source, index: 0)
                for viewIndex in pass.viewIndices {
                    var uniforms = FullViewportUniforms(
                        clipFromQuad: views[viewIndex].clipFromQuad, fade: fade)
                    encoder.setViewport(views[viewIndex].viewport)
                    encoder.setVertexBytes(
                        &uniforms, length: MemoryLayout<FullViewportUniforms>.stride, index: 0)
                    encoder.setFragmentBytes(
                        &uniforms, length: MemoryLayout<FullViewportUniforms>.stride, index: 0)
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                }
            }
            encoder.endEncoding()
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        precondition(commandBuffer.status == .completed, "presentation command buffer failed")
    }

    func clear(_ texture: any MTLTexture, slice: Int, to color: MTLClearColor) {
        let commandBuffer = queue.makeCommandBuffer()!
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].slice = slice
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = color
        commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)!.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    func read(_ texture: any MTLTexture, slice: Int = 0, bytesPerPixel: Int) -> [UInt8] {
        let bytesPerRow = texture.width * bytesPerPixel
        let length = bytesPerRow * texture.height
        let buffer = device.makeBuffer(length: length, options: .storageModeShared)!
        let commandBuffer = queue.makeCommandBuffer()!
        let blit = commandBuffer.makeBlitCommandEncoder()!
        blit.copy(from: texture, sourceSlice: slice, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
                  to: buffer, destinationOffset: 0, destinationBytesPerRow: bytesPerRow,
                  destinationBytesPerImage: length)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return Array(UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: UInt8.self),
                                         count: length))
    }
}

/// A 4x4 BGRA8 game frame: red top-left, green top-right, blue bottom-left, mid-gray
/// bottom-right, each a 2x2 block, with alpha deliberately zero as the game target often has.
private func makeGameFrame(_ renderer: Renderer) -> any MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 4,
                                                              height: 4, mipmapped: false)
    descriptor.usage = [.shaderRead]
    let texture = renderer.device.makeTexture(descriptor: descriptor)!
    var pixels = [UInt8](repeating: 0, count: 4 * 4 * 4)
    for y in 0..<4 {
        for x in 0..<4 {
            let bgr: [UInt8] = switch (x < 2, y < 2) {
            case (true, true): [0, 0, 255]
            case (false, true): [0, 255, 0]
            case (true, false): [255, 0, 0]
            case (false, false): [128, 128, 128]
            }
            let offset = (y * 4 + x) * 4
            pixels.replaceSubrange(offset..<offset + 3, with: bgr)
        }
    }
    texture.replace(region: MTLRegionMake2D(0, 0, 4, 4), mipmapLevel: 0, withBytes: pixels,
                    bytesPerRow: 16)
    return texture
}

private func pixel(_ bytes: [UInt8], width: Int, x: Int, y: Int) -> [Int] {
    let offset = (y * width + x) * 4
    return bytes[offset..<offset + 4].map(Int.init)
}

private func close(_ actual: [Int], _ expected: [Int], tolerance: Int = 1) -> Bool {
    actual.count == expected.count && zip(actual, expected).allSatisfy {
        abs($0 - $1) <= tolerance
    }
}

private func linear(_ encoded: Double) -> Double {
    encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
}

private func viewport(_ x: Double, _ width: Double, _ height: Double) -> MTLViewport {
    MTLViewport(originX: x, originY: 0, width: width, height: height, znear: 0, zfar: 1)
}

private func mapping(texture: Int, slice: Int, _ viewport: MTLViewport)
    -> VisionImmersiveViewMapping {
    VisionImmersiveViewMapping(
        textureIndex: texture, sliceIndex: slice,
        viewport: VisionImmersiveViewport(originX: viewport.originX, originY: viewport.originY,
                                          width: viewport.width, height: viewport.height,
                                          nearDepth: viewport.znear, farDepth: viewport.zfar))
}

private func checkColorRoundTrip(_ renderer: Renderer, _ game: any MTLTexture) {
    print("sRGB compositor target")
    let pipeline = renderer.pipeline(color: .bgra8Unorm_srgb)
    let color = renderer.texture(.bgra8Unorm_srgb, width: 64, height: 64)
    let depth = renderer.texture(.depth32Float, width: 64, height: 64)
    let view = viewport(0, 64, 64)
    let passes = VisionImmersivePassPlanner.passes(
        views: [mapping(texture: 0, slice: 0, view)],
        colorTargets: [VisionImmersiveTargetShape(width: 64, height: 64, sliceCount: 1)],
        depthTargets: [VisionImmersiveTargetShape(width: 64, height: 64, sliceCount: 1)])!

    renderer.present(game, fade: 1, passes: passes,
                     views: [ViewDraw(viewport: view,
                                      clipFromQuad: VisionImmersiveFullViewport.clipFromQuad)],
                     colors: [color], depths: [depth], pipeline: pipeline)
    var bytes = renderer.read(color, bytesPerPixel: 4)
    check(close(pixel(bytes, width: 64, x: 16, y: 16), [0, 0, 255, 255]),
          "top-left game texels stay red at the top left (BGRA 0,0,255,255)")
    check(close(pixel(bytes, width: 64, x: 48, y: 16), [0, 255, 0, 255]),
          "top-right texels stay green, so the image is not mirrored")
    check(close(pixel(bytes, width: 64, x: 16, y: 48), [255, 0, 0, 255]),
          "bottom-left texels stay blue, so the image is not flipped")
    check(close(pixel(bytes, width: 64, x: 48, y: 48), [128, 128, 128, 255]),
          "mid-gray keeps its display-encoded value through the sRGB target")
    check(stride(from: 3, to: bytes.count, by: 4).allSatisfy { bytes[$0] == 255 },
          "the full viewport is opaque even though the game target's alpha is zero")

    renderer.present(game, fade: 0.5, passes: passes,
                     views: [ViewDraw(viewport: view,
                                      clipFromQuad: VisionImmersiveFullViewport.clipFromQuad)],
                     colors: [color], depths: [depth], pipeline: pipeline)
    bytes = renderer.read(color, bytesPerPixel: 4)
    check(close(pixel(bytes, width: 64, x: 48, y: 48), [64, 64, 64, 255])
            && close(pixel(bytes, width: 64, x: 16, y: 16), [0, 0, 128, 255]),
          "the PCRTC blackout scales display-encoded values like the present pass")
}

private func checkLinearTarget(_ renderer: Renderer, _ game: any MTLTexture) {
    print("Linear float compositor target")
    let pipeline = renderer.pipeline(color: .rgba16Float)
    let color = renderer.texture(.rgba16Float, width: 64, height: 64)
    let depth = renderer.texture(.depth32Float, width: 64, height: 64)
    let view = viewport(0, 64, 64)
    let passes = VisionImmersivePassPlanner.passes(
        views: [mapping(texture: 0, slice: 0, view)],
        colorTargets: [VisionImmersiveTargetShape(width: 64, height: 64, sliceCount: 1)],
        depthTargets: [VisionImmersiveTargetShape(width: 64, height: 64, sliceCount: 1)])!
    renderer.present(game, fade: 1, passes: passes,
                     views: [ViewDraw(viewport: view,
                                      clipFromQuad: VisionImmersiveFullViewport.clipFromQuad)],
                     colors: [color], depths: [depth], pipeline: pipeline)
    let bytes = renderer.read(color, bytesPerPixel: 8)
    func channel(_ x: Int, _ y: Int, _ component: Int) -> Double {
        let offset = (y * 64 + x) * 8 + component * 2
        let bits = UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
        return Double(Float(Float16(bitPattern: bits)))
    }
    let expectedGray = linear(128.0 / 255.0)
    check(abs(channel(48, 48, 0) - expectedGray) < 0.002
            && abs(channel(48, 48, 1) - expectedGray) < 0.002
            && abs(channel(48, 48, 3) - 1) < 0.001,
          "mid-gray is written as linear light (\(String(format: "%.4f", expectedGray)))")
    check(abs(channel(16, 16, 0) - 1) < 0.001 && abs(channel(16, 16, 1)) < 0.001,
          "red stays pure red in linear light")
}

private func checkDedicatedTargets(_ renderer: Renderer, _ game: any MTLTexture) {
    print("Dedicated compositor targets")
    let pipeline = renderer.pipeline(color: .bgra8Unorm_srgb)
    let colors = (0..<2).map { _ in
        renderer.texture(.bgra8Unorm_srgb, width: 64, height: 64)
    }
    let depths = (0..<2).map { _ in
        renderer.texture(.depth32Float, width: 64, height: 64)
    }
    let view = viewport(0, 64, 64)
    let shape = VisionImmersiveTargetShape(width: 64, height: 64, sliceCount: 1)
    let passes = VisionImmersivePassPlanner.passes(
        views: [mapping(texture: 0, slice: 0, view),
                mapping(texture: 1, slice: 0, view)],
        colorTargets: [shape, shape], depthTargets: [shape, shape])!
    let draws = (0..<2).map { _ in
        ViewDraw(viewport: view, clipFromQuad: VisionImmersiveFullViewport.clipFromQuad)
    }
    renderer.present(game, fade: 1, passes: passes, views: draws,
                     colors: colors, depths: depths, pipeline: pipeline)
    for (index, color) in colors.enumerated() {
        let bytes = renderer.read(color, bytesPerPixel: 4)
        check(close(pixel(bytes, width: 64, x: 0, y: 0), [0, 0, 255, 255])
                && close(pixel(bytes, width: 64, x: 63, y: 63), [128, 128, 128, 255]),
              "dedicated target \(index) is covered from corner to corner")
    }
}

private func checkLayeredSlices(_ renderer: Renderer, _ game: any MTLTexture) {
    print("Layered compositor target")
    let pipeline = renderer.pipeline(color: .bgra8Unorm_srgb)
    let color = renderer.texture(.bgra8Unorm_srgb, width: 64, height: 64, slices: 2)
    let depth = renderer.texture(.depth32Float, width: 64, height: 64, slices: 2)
    let view = viewport(0, 64, 64)
    let shape = VisionImmersiveTargetShape(width: 64, height: 64, sliceCount: 2)
    let passes = VisionImmersivePassPlanner.passes(
        views: [mapping(texture: 0, slice: 0, view),
                mapping(texture: 0, slice: 1, view)], colorTargets: [shape],
        depthTargets: [shape])!
    renderer.present(game, fade: 1, passes: passes,
                     views: [ViewDraw(
                                viewport: view,
                                clipFromQuad: VisionImmersiveFullViewport.clipFromQuad),
                             ViewDraw(
                                viewport: view,
                                clipFromQuad: VisionImmersiveFullViewport.clipFromQuad)],
                     colors: [color], depths: [depth], pipeline: pipeline)
    for slice in 0..<2 {
        let bytes = renderer.read(color, slice: slice, bytesPerPixel: 4)
        check(close(pixel(bytes, width: 64, x: 0, y: 0), [0, 0, 255, 255])
                && close(pixel(bytes, width: 64, x: 63, y: 63), [128, 128, 128, 255]),
              "layered slice \(slice) is covered from corner to corner")
    }
}

private func checkSharedLayout(_ renderer: Renderer, _ game: any MTLTexture) {
    print("Shared compositor target")
    let pipeline = renderer.pipeline(color: .bgra8Unorm_srgb)
    let color = renderer.texture(.bgra8Unorm_srgb, width: 128, height: 64)
    let depth = renderer.texture(.depth32Float, width: 128, height: 64)
    let left = viewport(0, 64, 64)
    let right = viewport(64, 64, 64)
    let shape = VisionImmersiveTargetShape(width: 128, height: 64, sliceCount: 1)
    let passes = VisionImmersivePassPlanner.passes(
        views: [mapping(texture: 0, slice: 0, left), mapping(texture: 0, slice: 0, right)],
        colorTargets: [shape], depthTargets: [shape])!
    check(passes.count == 1, "both side-by-side eyes share one clearing pass")
    renderer.present(game, fade: 1, passes: passes,
                     views: [ViewDraw(
                                viewport: left,
                                clipFromQuad: VisionImmersiveFullViewport.clipFromQuad),
                             ViewDraw(
                                viewport: right,
                                clipFromQuad: VisionImmersiveFullViewport.clipFromQuad)],
                     colors: [color], depths: [depth], pipeline: pipeline)
    let bytes = renderer.read(color, bytesPerPixel: 4)
    check(close(pixel(bytes, width: 128, x: 16, y: 16), [0, 0, 255, 255])
            && close(pixel(bytes, width: 128, x: 80, y: 16), [0, 0, 255, 255])
            && close(pixel(bytes, width: 128, x: 0, y: 0), [0, 0, 255, 255])
            && close(pixel(bytes, width: 128, x: 63, y: 63), [128, 128, 128, 255])
            && close(pixel(bytes, width: 128, x: 64, y: 0), [0, 0, 255, 255])
            && close(pixel(bytes, width: 128, x: 127, y: 63), [128, 128, 128, 255]),
          "both shared eye viewports remain covered from corner to corner")
}

private func checkFullViewportCoverageAndDepth(_ renderer: Renderer, _ game: any MTLTexture) {
    print("Full-viewport coverage and synthetic depth")
    let pipeline = renderer.pipeline(color: .bgra8Unorm_srgb)
    let color = renderer.texture(.bgra8Unorm_srgb, width: 64, height: 64)
    let depth = renderer.texture(.depth32Float, width: 64, height: 64)
    let view = viewport(0, 64, 64)
    let shape = VisionImmersiveTargetShape(width: 64, height: 64, sliceCount: 1)
    let passes = VisionImmersivePassPlanner.passes(
        views: [mapping(texture: 0, slice: 0, view)], colorTargets: [shape],
        depthTargets: [shape])!
    let draws = [ViewDraw(
        viewport: view, clipFromQuad: VisionImmersiveFullViewport.clipFromQuad)]
    renderer.present(nil, fade: 1, passes: passes, views: draws,
                     colors: [color], depths: [depth], pipeline: pipeline)
    let cleared = renderer.read(color, bytesPerPixel: 4)
    check(stride(from: 0, to: cleared.count, by: 4).allSatisfy {
        Array(cleared[$0..<$0 + 4]) == [0, 0, 0, 255]
    }, "a frame without completed game content is opaque black across the target")

    renderer.present(game, fade: 1, passes: passes, views: draws,
                     colors: [color], depths: [depth], pipeline: pipeline)
    let colorBytes = renderer.read(color, bytesPerPixel: 4)
    let depthBytes = renderer.read(depth, bytesPerPixel: 4)
    func depthValue(_ x: Int, _ y: Int) -> Float {
        let offset = (y * 64 + x) * 4
        return depthBytes[offset..<offset + 4].withUnsafeBytes { $0.loadUnaligned(as: Float.self) }
    }
    check((0..<64).allSatisfy { y in
        (0..<64).allSatisfy { x in
            abs(depthValue(x, y) - VisionImmersiveFullViewport.farDepth) < 1e-6
        }
    }, "every viewport pixel writes the documented reverse-Z far depth")
    check(close(pixel(colorBytes, width: 64, x: 0, y: 0), [0, 0, 255, 255])
            && close(pixel(colorBytes, width: 64, x: 63, y: 0), [0, 255, 0, 255])
            && close(pixel(colorBytes, width: 64, x: 0, y: 63), [255, 0, 0, 255])
            && close(pixel(colorBytes, width: 64, x: 63, y: 63), [128, 128, 128, 255]),
          "the complete game frame reaches all four viewport corners without cropping")
}

@main
private enum VisionImmersivePresentationGPUCheck {
    static func main() {
        guard CommandLine.arguments.count == 2 else {
            print("usage: vision-immersive-presentation-gpu-check <metallib>")
            exit(2)
        }
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(
                  URL: URL(fileURLWithPath: CommandLine.arguments[1])) else {
            print("Metal or the compiled presentation shader is unavailable")
            exit(1)
        }
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .always
        depthDescriptor.isDepthWriteEnabled = true
        let renderer = Renderer(device: device, queue: queue, library: library,
                                depthState: device.makeDepthStencilState(
                                    descriptor: depthDescriptor)!)
        let game = makeGameFrame(renderer)
        checkColorRoundTrip(renderer, game)
        checkLinearTarget(renderer, game)
        checkDedicatedTargets(renderer, game)
        checkLayeredSlices(renderer, game)
        checkSharedLayout(renderer, game)
        checkFullViewportCoverageAndDepth(renderer, game)
        guard failures == 0 else {
            print("visionOS immersive presentation GPU checks failed: \(failures)")
            fatalError("immersive presentation GPU check failed")
        }
        print("visionOS immersive presentation GPU checks passed on \(device.name)")
    }
}
