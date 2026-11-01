import Foundation
import Metal
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

private struct ResolveUniforms {
    var clipFromQuad: simd_float4x4
    var fade: Float
}

private struct EyeSource {
    let color: any MTLTexture
    let depth: any MTLTexture
}

private struct ViewDraw {
    let viewport: MTLViewport
}

private struct Renderer {
    let device: any MTLDevice
    let queue: any MTLCommandQueue
    let library: any MTLLibrary
    let depthState: any MTLDepthStencilState

    func pipeline(color: MTLPixelFormat,
                  depth: MTLPixelFormat = .depth32Float,
                  fragment: String = "vision_immersive_screen_fragment")
        -> any MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "vision_immersive_screen_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: fragment)
        descriptor.colorAttachments[0].pixelFormat = color
        descriptor.depthAttachmentPixelFormat = depth
        if depth == .depth32Float_stencil8 {
            descriptor.stencilAttachmentPixelFormat = depth
        }
        return try! device.makeRenderPipelineState(descriptor: descriptor)
    }

    func texture(_ format: MTLPixelFormat, width: Int, height: Int, slices: Int = 1,
                 usage: MTLTextureUsage) -> any MTLTexture {
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

    func colorSource(rightEye: Bool) -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 4, height: 4, mipmapped: false)
        descriptor.usage = [.shaderRead]
        let texture = device.makeTexture(descriptor: descriptor)!
        var pixels = [UInt8](repeating: 0, count: 4 * 4 * 4)
        for y in 0..<4 {
            for x in 0..<4 {
                let quadrant = (x < 2 ? 0 : 1) + (y < 2 ? 0 : 2)
                let bgra: [UInt8]
                if rightEye {
                    bgra = [
                        [0, 255, 255, 0],     // yellow
                        [255, 0, 255, 0],     // magenta
                        [255, 255, 0, 0],     // cyan
                        [192, 192, 192, 0],
                    ][quadrant]
                } else {
                    bgra = [
                        [0, 0, 255, 0],       // red
                        [0, 255, 0, 0],       // green
                        [255, 0, 0, 0],       // blue
                        [64, 64, 64, 0],
                    ][quadrant]
                }
                let offset = (y * 4 + x) * 4
                pixels.replaceSubrange(offset..<offset + 4, with: bgra)
            }
        }
        texture.replace(region: MTLRegionMake2D(0, 0, 4, 4), mipmapLevel: 0,
                        withBytes: pixels, bytesPerRow: 16)
        return texture
    }

    func countPatternColorSource(nonBlackColumns: Int) -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 4, height: 4, mipmapped: false)
        descriptor.usage = [.shaderRead]
        let texture = device.makeTexture(descriptor: descriptor)!
        var pixels = [UInt8](repeating: 0, count: 4 * 4 * 4)
        for y in 0..<4 {
            for x in 0..<min(max(nonBlackColumns, 0), 4) {
                let offset = (y * 4 + x) * 4
                pixels.replaceSubrange(offset..<offset + 4, with: [0, 0, 255, 255])
            }
        }
        texture.replace(region: MTLRegionMake2D(0, 0, 4, 4), mipmapLevel: 0,
                        withBytes: pixels, bytesPerRow: 16)
        return texture
    }

    func depthSource(_ value: Double) -> any MTLTexture {
        let texture = texture(.depth32Float_stencil8, width: 4, height: 4,
                              usage: [.renderTarget, .shaderRead])
        let commandBuffer = queue.makeCommandBuffer()!
        let descriptor = MTLRenderPassDescriptor()
        descriptor.depthAttachment.texture = texture
        descriptor.depthAttachment.loadAction = .clear
        descriptor.depthAttachment.storeAction = .store
        descriptor.depthAttachment.clearDepth = value
        descriptor.stencilAttachment.texture = texture
        descriptor.stencilAttachment.loadAction = .clear
        descriptor.stencilAttachment.storeAction = .dontCare
        commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)!.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        precondition(commandBuffer.status == .completed)
        return texture
    }

    func present(sources: [EyeSource], fade: Float,
                 passes: [VisionImmersivePass], views: [ViewDraw],
                 colors: [any MTLTexture], depths: [any MTLTexture],
                 pipeline: any MTLRenderPipelineState,
                 afterResolve: ((any MTLCommandBuffer) -> Void)? = nil) {
        precondition(sources.count == 2 && views.count == 2)
        let commandBuffer = queue.makeCommandBuffer()!
        for pass in passes {
            let descriptor = MTLRenderPassDescriptor()
            descriptor.colorAttachments[0].texture = colors[pass.textureIndex]
            descriptor.colorAttachments[0].slice = pass.sliceIndex
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].storeAction = .store
            descriptor.colorAttachments[0].clearColor = MTLClearColor(
                red: 0, green: 0, blue: 0, alpha: 1)
            descriptor.depthAttachment.texture = depths[pass.textureIndex]
            descriptor.depthAttachment.slice = pass.sliceIndex
            descriptor.depthAttachment.loadAction = .clear
            descriptor.depthAttachment.storeAction = .store
            descriptor.depthAttachment.clearDepth = 0
            if depths[pass.textureIndex].pixelFormat == .depth32Float_stencil8 {
                descriptor.stencilAttachment.texture = depths[pass.textureIndex]
                descriptor.stencilAttachment.slice = pass.sliceIndex
                descriptor.stencilAttachment.loadAction = .clear
                descriptor.stencilAttachment.storeAction = .dontCare
            }
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)!
            encoder.setRenderPipelineState(pipeline)
            encoder.setDepthStencilState(depthState)
            encoder.setCullMode(.none)
            for viewIndex in pass.viewIndices {
                var uniforms = ResolveUniforms(
                    clipFromQuad: VisionImmersiveResolve.clipFromQuad, fade: fade)
                encoder.setViewport(views[viewIndex].viewport)
                encoder.setVertexBytes(
                    &uniforms, length: MemoryLayout<ResolveUniforms>.stride, index: 0)
                encoder.setFragmentBytes(
                    &uniforms, length: MemoryLayout<ResolveUniforms>.stride, index: 0)
                encoder.setFragmentTexture(sources[viewIndex].color, index: 0)
                encoder.setFragmentTexture(sources[viewIndex].depth, index: 1)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
            encoder.endEncoding()
        }
        afterResolve?(commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        precondition(commandBuffer.status == .completed,
                     "per-eye resolve command buffer failed: \(String(describing: commandBuffer.error))")
    }

    func read(_ texture: any MTLTexture, slice: Int = 0,
              bytesPerPixel: Int) -> [UInt8] {
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
        precondition(commandBuffer.status == .completed)
        return Array(UnsafeBufferPointer(
            start: buffer.contents().assumingMemoryBound(to: UInt8.self), count: length))
    }
}

private func evidenceEyes(colors: [any MTLTexture],
                          depths: [any MTLTexture],
                          mappings: [VisionImmersiveViewMapping])
    -> [VisionImmersiveRenderEvidenceSampler.ResolvedEye] {
    mappings.map { mapping in
        VisionImmersiveRenderEvidenceSampler.ResolvedEye(
            colorTexture: colors[mapping.textureIndex],
            depthTexture: depths[mapping.textureIndex],
            originX: mapping.viewport.originX,
            originY: mapping.viewport.originY,
            width: mapping.viewport.width,
            height: mapping.viewport.height,
            sliceIndex: mapping.sliceIndex
        )
    }
}

private func viewport(_ x: Double, _ width: Double = 64) -> MTLViewport {
    MTLViewport(originX: x, originY: 0, width: width, height: 64, znear: 0, zfar: 1)
}

private func mapping(texture: Int, slice: Int, viewport: MTLViewport)
    -> VisionImmersiveViewMapping {
    VisionImmersiveViewMapping(
        textureIndex: texture,
        sliceIndex: slice,
        viewport: VisionImmersiveViewport(
            originX: viewport.originX, originY: viewport.originY,
            width: viewport.width, height: viewport.height,
            nearDepth: viewport.znear, farDepth: viewport.zfar))
}

private func shape(_ width: Int, slices: Int = 1) -> VisionImmersiveTargetShape {
    VisionImmersiveTargetShape(width: width, height: 64, sliceCount: slices)
}

private func pixel(_ bytes: [UInt8], width: Int, x: Int, y: Int) -> [Int] {
    let offset = (y * width + x) * 4
    return bytes[offset..<offset + 4].map(Int.init)
}

private func depth(_ bytes: [UInt8], width: Int, x: Int, y: Int) -> Float {
    let offset = (y * width + x) * 4
    return bytes[offset..<offset + 4].withUnsafeBytes {
        $0.loadUnaligned(as: Float.self)
    }
}

private func close(_ actual: [Int], _ expected: [Int], tolerance: Int = 1) -> Bool {
    actual.count == expected.count && zip(actual, expected).allSatisfy {
        abs($0 - $1) <= tolerance
    }
}

private func encodedToLinear(_ encoded: Float) -> Float {
    encoded <= 0.04045
        ? encoded / 12.92
        : pow((encoded + 0.055) / 1.055, 2.4)
}

private func verifyEncodedEye(_ bytes: [UInt8], targetWidth: Int, originX: Int,
                              rightEye: Bool, label: String) {
    let expected = rightEye
        ? [[0, 255, 255, 255], [255, 0, 255, 255],
           [255, 255, 0, 255], [192, 192, 192, 255]]
        : [[0, 0, 255, 255], [0, 255, 0, 255],
           [255, 0, 0, 255], [64, 64, 64, 255]]
    check(close(pixel(bytes, width: targetWidth, x: originX, y: 0), expected[0])
            && close(pixel(bytes, width: targetWidth, x: originX + 63, y: 0), expected[1])
            && close(pixel(bytes, width: targetWidth, x: originX, y: 63), expected[2])
            && close(pixel(bytes, width: targetWidth, x: originX + 63, y: 63), expected[3]),
          "\(label) keeps all UV edges and the correct eye image")
}

private func checkDedicated(_ renderer: Renderer, sources: [EyeSource]) {
    print("Dedicated per-eye resolve")
    let colors = (0..<2).map { _ in
        renderer.texture(.rgba16Float, width: 64, height: 64, usage: [.renderTarget])
    }
    let depths = (0..<2).map { _ in
        renderer.texture(.depth32Float, width: 64, height: 64, usage: [.renderTarget])
    }
    let view = viewport(0)
    let target = shape(64)
    let passes = VisionImmersivePassPlanner.passes(
        views: [mapping(texture: 0, slice: 0, viewport: view),
                mapping(texture: 1, slice: 0, viewport: view)],
        colorTargets: [target, target], depthTargets: [target, target])!
    renderer.present(sources: sources, fade: 1, passes: passes,
                     views: [ViewDraw(viewport: view), ViewDraw(viewport: view)],
                     colors: colors, depths: depths,
                     pipeline: renderer.pipeline(color: .rgba16Float))

    func floatChannel(_ bytes: [UInt8], _ x: Int, _ y: Int, _ channel: Int) -> Float {
        let offset = (y * 64 + x) * 8 + channel * 2
        let bits = UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
        return Float(Float16(bitPattern: bits))
    }
    let left = renderer.read(colors[0], bytesPerPixel: 8)
    let right = renderer.read(colors[1], bytesPerPixel: 8)
    check(abs(floatChannel(left, 0, 0, 0) - 1) < 0.001
            && abs(floatChannel(left, 0, 0, 1)) < 0.001
            && abs(floatChannel(right, 0, 0, 0) - 1) < 0.001
            && abs(floatChannel(right, 0, 0, 1) - 1) < 0.001,
          "float targets retain distinct left-red and right-yellow encoded-to-linear colors")
    let leftDepth = renderer.read(depths[0], bytesPerPixel: 4)
    let rightDepth = renderer.read(depths[1], bytesPerPixel: 4)
    check(abs(depth(leftDepth, width: 64, x: 32, y: 32) - 0.25) < 1e-6
            && abs(depth(rightDepth, width: 64, x: 32, y: 32) - 0.75) < 1e-6,
          "dedicated targets retain distinct left and right physical depth")

    renderer.present(sources: sources, fade: 0.5, passes: passes,
                     views: [ViewDraw(viewport: view), ViewDraw(viewport: view)],
                     colors: colors, depths: depths,
                     pipeline: renderer.pipeline(color: .rgba16Float))
    let fadedLeft = renderer.read(colors[0], bytesPerPixel: 8)
    let fadedRight = renderer.read(colors[1], bytesPerPixel: 8)
    let expectedFade = encodedToLinear(0.5)
    check(abs(floatChannel(fadedLeft, 0, 0, 0) - expectedFade) < 0.002
            && abs(floatChannel(fadedRight, 0, 0, 0) - expectedFade) < 0.002
            && abs(floatChannel(fadedRight, 0, 0, 1) - expectedFade) < 0.002,
          "PCRTC fade scales encoded eye colors before their shared linear-light decode")
}

private func checkLayered(_ renderer: Renderer, sources: [EyeSource]) {
    print("Layered per-eye resolve")
    let color = renderer.texture(.bgra8Unorm_srgb, width: 64, height: 64, slices: 2,
                                 usage: [.renderTarget])
    let depthTarget = renderer.texture(.depth32Float, width: 64, height: 64, slices: 2,
                                       usage: [.renderTarget])
    let view = viewport(0)
    let target = shape(64, slices: 2)
    let passes = VisionImmersivePassPlanner.passes(
        views: [mapping(texture: 0, slice: 0, viewport: view),
                mapping(texture: 0, slice: 1, viewport: view)],
        colorTargets: [target], depthTargets: [target])!
    renderer.present(sources: sources, fade: 1, passes: passes,
                     views: [ViewDraw(viewport: view), ViewDraw(viewport: view)],
                     colors: [color], depths: [depthTarget],
                     pipeline: renderer.pipeline(color: .bgra8Unorm_srgb))
    for eye in 0..<2 {
        let bytes = renderer.read(color, slice: eye, bytesPerPixel: 4)
        verifyEncodedEye(bytes, targetWidth: 64, originX: 0, rightEye: eye == 1,
                         label: "layered slice \(eye)")
        let depthBytes = renderer.read(depthTarget, slice: eye, bytesPerPixel: 4)
        let expected: Float = eye == 0 ? 0.25 : 0.75
        check(abs(depth(depthBytes, width: 64, x: 32, y: 32) - expected) < 1e-6,
              "layered slice \(eye) keeps its eye's physical depth")
    }
}

private func checkShared(_ renderer: Renderer, sources: [EyeSource]) {
    print("Shared per-eye resolve")
    let color = renderer.texture(.bgra8Unorm_srgb, width: 128, height: 64,
                                 usage: [.renderTarget])
    let depthTarget = renderer.texture(.depth32Float, width: 128, height: 64,
                                       usage: [.renderTarget])
    let left = viewport(0)
    let right = viewport(64)
    let target = shape(128)
    let passes = VisionImmersivePassPlanner.passes(
        views: [mapping(texture: 0, slice: 0, viewport: left),
                mapping(texture: 0, slice: 0, viewport: right)],
        colorTargets: [target], depthTargets: [target])!
    check(passes.count == 1 && passes[0].viewIndices == [0, 1],
          "shared side-by-side eyes use one non-erasing pass")
    renderer.present(sources: sources, fade: 1, passes: passes,
                     views: [ViewDraw(viewport: left), ViewDraw(viewport: right)],
                     colors: [color], depths: [depthTarget],
                     pipeline: renderer.pipeline(color: .bgra8Unorm_srgb))
    let bytes = renderer.read(color, bytesPerPixel: 4)
    verifyEncodedEye(bytes, targetWidth: 128, originX: 0, rightEye: false,
                     label: "shared left viewport")
    verifyEncodedEye(bytes, targetWidth: 128, originX: 64, rightEye: true,
                     label: "shared right viewport")
    let depthBytes = renderer.read(depthTarget, bytesPerPixel: 4)
    check(abs(depth(depthBytes, width: 128, x: 32, y: 32) - 0.25) < 1e-6
            && abs(depth(depthBytes, width: 128, x: 96, y: 32) - 0.75) < 1e-6,
          "shared viewports retain distinct left and right physical depth")
}

private func checkFarDepthNudge(_ renderer: Renderer, sources: [EyeSource]) {
    print("Reverse-Z far-sky depth")
    let zeroSources = [
        EyeSource(color: sources[0].color, depth: renderer.depthSource(0)),
        sources[1],
    ]
    let colors = (0..<2).map { _ in
        renderer.texture(.bgra8Unorm_srgb, width: 64, height: 64, usage: [.renderTarget])
    }
    let depths = (0..<2).map { _ in
        renderer.texture(.depth32Float, width: 64, height: 64, usage: [.renderTarget])
    }
    let view = viewport(0)
    let target = shape(64)
    let passes = VisionImmersivePassPlanner.passes(
        views: [mapping(texture: 0, slice: 0, viewport: view),
                mapping(texture: 1, slice: 0, viewport: view)],
        colorTargets: [target, target], depthTargets: [target, target])!
    renderer.present(sources: zeroSources, fade: 1, passes: passes,
                     views: [ViewDraw(viewport: view), ViewDraw(viewport: view)],
                     colors: colors, depths: depths,
                     pipeline: renderer.pipeline(color: .bgra8Unorm_srgb))
    let bytes = renderer.read(depths[0], bytesPerPixel: 4)
    check(abs(depth(bytes, width: 64, x: 32, y: 32)
              - VisionImmersiveResolve.minimumReverseZDepth) < 1e-9,
          "exact native reverse-Z far depth receives only the documented tiny positive nudge")
}

private func checkD32S8CompositorRoundTrip(_ renderer: Renderer, sources: [EyeSource]) {
    print("D32S8 compositor-style depth round trip")
    let view = viewport(0)
    let target = shape(64)
    let passes = VisionImmersivePassPlanner.passes(
        views: [mapping(texture: 0, slice: 0, viewport: view),
                mapping(texture: 1, slice: 0, viewport: view)],
        colorTargets: [target, target], depthTargets: [target, target])!
    let compositorColors = (0..<2).map { _ in
        renderer.texture(.bgra8Unorm_srgb, width: 64, height: 64,
                         usage: [.renderTarget])
    }
    let compositorDepths = (0..<2).map { _ in
        renderer.texture(.depth32Float_stencil8, width: 64, height: 64,
                         usage: [.renderTarget, .shaderRead])
    }
    renderer.present(
        sources: sources,
        fade: 1,
        passes: passes,
        views: [ViewDraw(viewport: view), ViewDraw(viewport: view)],
        colors: compositorColors,
        depths: compositorDepths,
        pipeline: renderer.pipeline(color: .bgra8Unorm_srgb,
                                    depth: .depth32Float_stencil8)
    )

    let probeSources = [
        EyeSource(color: sources[0].color, depth: compositorDepths[0]),
        EyeSource(color: sources[1].color, depth: compositorDepths[1]),
    ]
    let probeColors = (0..<2).map { _ in
        renderer.texture(.bgra8Unorm_srgb, width: 64, height: 64,
                         usage: [.renderTarget])
    }
    let probeDepths = (0..<2).map { _ in
        renderer.texture(.depth32Float, width: 64, height: 64,
                         usage: [.renderTarget])
    }
    renderer.present(
        sources: probeSources,
        fade: 1,
        passes: passes,
        views: [ViewDraw(viewport: view), ViewDraw(viewport: view)],
        colors: probeColors,
        depths: probeDepths,
        pipeline: renderer.pipeline(color: .bgra8Unorm_srgb)
    )
    let left = renderer.read(probeDepths[0], bytesPerPixel: 4)
    let right = renderer.read(probeDepths[1], bytesPerPixel: 4)
    check(abs(depth(left, width: 64, x: 32, y: 32) - 0.25) < 1e-6
            && abs(depth(right, width: 64, x: 32, y: 32) - 0.75) < 1e-6,
          "D32S8 accepts fragment depth and remains directly sampleable without a texture view")
}

private func checkAggregateEvidence(_ renderer: Renderer, depths: [any MTLTexture]) {
    print("Bounded source/resolved aggregate evidence")
    let sampler = try! VisionImmersiveRenderEvidenceSampler(
        device: renderer.device, library: renderer.library, attempt: 41, outputURL: nil)
    let view = viewport(0)

    let blackSources = [
        EyeSource(color: renderer.countPatternColorSource(nonBlackColumns: 0),
                  depth: depths[0]),
        EyeSource(color: renderer.countPatternColorSource(nonBlackColumns: 0),
                  depth: depths[1]),
    ]
    let layeredMappings = [
        mapping(texture: 0, slice: 0, viewport: view),
        mapping(texture: 0, slice: 1, viewport: view),
    ]
    let layeredTarget = shape(64, slices: 2)
    let layeredPasses = VisionImmersivePassPlanner.passes(
        views: layeredMappings,
        colorTargets: [layeredTarget], depthTargets: [layeredTarget])!
    let layeredColors = [renderer.texture(
        .bgra8Unorm_srgb, width: 64, height: 64, slices: 2,
        usage: [.renderTarget, .shaderRead])]
    let layeredDepths = [renderer.texture(
        .depth32Float_stencil8, width: 64, height: 64, slices: 2,
        usage: [.renderTarget, .shaderRead])]
    var blackTicket: VisionImmersiveRenderEvidenceSampler.Ticket?
    renderer.present(
        sources: blackSources,
        fade: 1,
        passes: layeredPasses,
        views: [ViewDraw(viewport: view), ViewDraw(viewport: view)],
        colors: layeredColors,
        depths: layeredDepths,
        pipeline: renderer.pipeline(color: .bgra8Unorm_srgb,
                                    depth: .depth32Float_stencil8)
    ) { commandBuffer in
        blackTicket = try! sampler.encodeIfNeeded(
            nativeColorTextures: blackSources.map(\.color),
            nativeDepthTextures: blackSources.map(\.depth),
            resolvedEyes: evidenceEyes(
                colors: layeredColors, depths: layeredDepths, mappings: layeredMappings),
            fade: 1,
            nativeRenderSerial: 100,
            poseIdentity: 200,
            compositorFrameIndex: 300,
            presentationTime: 1,
            commandBuffer: commandBuffer
        )
    }
    let black = sampler.complete(blackTicket!)
    check(!black.becameVisible && !black.observation.resolvedVisible,
          "an all-black layered result cannot report the first visible game frame")
    check(black.observation.eyes.allSatisfy {
              $0.source.nonBlackRGBCount == 0 && $0.resolved.nonBlackRGBCount == 0
          },
          "2D-array sampling records zero source and resolved nonblack samples")
    check(black.observation.eyes[0].resolved.positiveDepthCount == 64
            && black.observation.eyes[1].resolved.positiveDepthCount == 64,
          "all-black color evidence still records both resolved physical-depth grids")

    let visibleSources = [
        EyeSource(color: renderer.countPatternColorSource(nonBlackColumns: 4),
                  depth: depths[0]),
        EyeSource(color: renderer.countPatternColorSource(nonBlackColumns: 2),
                  depth: depths[1]),
    ]
    let dedicatedMappings = [
        mapping(texture: 0, slice: 0, viewport: view),
        mapping(texture: 1, slice: 0, viewport: view),
    ]
    let dedicatedTarget = shape(64)
    let dedicatedPasses = VisionImmersivePassPlanner.passes(
        views: dedicatedMappings,
        colorTargets: [dedicatedTarget, dedicatedTarget],
        depthTargets: [dedicatedTarget, dedicatedTarget])!
    let dedicatedColors = (0..<2).map { _ in renderer.texture(
        .bgra8Unorm_srgb, width: 64, height: 64,
        usage: [.renderTarget, .shaderRead]) }
    let dedicatedDepths = (0..<2).map { _ in renderer.texture(
        .depth32Float_stencil8, width: 64, height: 64,
        usage: [.renderTarget, .shaderRead]) }
    var visibleTicket: VisionImmersiveRenderEvidenceSampler.Ticket?
    renderer.present(
        sources: visibleSources,
        fade: 0.75,
        passes: dedicatedPasses,
        views: [ViewDraw(viewport: view), ViewDraw(viewport: view)],
        colors: dedicatedColors,
        depths: dedicatedDepths,
        pipeline: renderer.pipeline(color: .bgra8Unorm_srgb,
                                    depth: .depth32Float_stencil8)
    ) { commandBuffer in
        visibleTicket = try! sampler.encodeIfNeeded(
            nativeColorTextures: visibleSources.map(\.color),
            nativeDepthTextures: visibleSources.map(\.depth),
            resolvedEyes: evidenceEyes(
                colors: dedicatedColors, depths: dedicatedDepths,
                mappings: dedicatedMappings),
            fade: 0.75,
            nativeRenderSerial: 101,
            poseIdentity: 201,
            compositorFrameIndex: 301,
            presentationTime: 1.01,
            commandBuffer: commandBuffer
        )
    }
    let visible = sampler.complete(visibleTicket!)
    let left = visible.observation.eyes[0]
    let right = visible.observation.eyes[1]
    check(visible.becameVisible && visible.observation.resolvedVisible,
          "both nonblack resolved eyes report the first visible game frame")
    check(left.source.nonBlackRGBCount > right.source.nonBlackRGBCount
            && left.resolved.nonBlackRGBCount > right.resolved.nonBlackRGBCount
            && right.resolved.nonBlackRGBCount > 0,
          "the 8x8 aggregates preserve distinct left/right nonblack coverage")
    check(abs((left.resolved.minimumDepth ?? 0) - 0.25) < 1e-6
            && abs((left.resolved.maximumDepth ?? 0) - 0.25) < 1e-6
            && abs((right.resolved.minimumDepth ?? 0) - 0.75) < 1e-6
            && abs((right.resolved.maximumDepth ?? 0) - 0.75) < 1e-6,
          "the aggregates preserve distinct left/right D32S8 depth ranges")
    check(visible.observation.fade == 0.75
            && visible.observation.nativeRenderSerial == 101
            && visible.observation.poseIdentity == 201
            && visible.observation.compositorFrameIndex == 301,
          "aggregate evidence records fade and native/render pose/compositor identities")
}

// MARK: - Native menu plane

/// The presenter's menu PSO pairs the resolve vertex with this fragment.
private let menuPlaneFragment = "vision_immersive_menu_plane_fragment"

/// Original synthetic conventional frame: four distinct quadrant colors (top-left, top-right,
/// bottom-left, bottom-right) make orientation, mirroring and aspect visible.
private let menuQuadrantRGB: [SIMD3<Float>] = [
    SIMD3(230, 40, 40), SIMD3(40, 200, 60), SIMD3(50, 70, 220), SIMD3(240, 220, 60),
]
private let menuQuadrantNames = ["top-left red", "top-right green", "bottom-left blue",
                                 "bottom-right yellow"]

private func xyz3(_ column: SIMD4<Float>) -> SIMD3<Float> {
    SIMD3(column.x, column.y, column.z)
}

/// Explicit synthetic eye calibration: device-from-eye pose plus off-axis frustum tangents
/// (left and down negative).
private struct MenuEyeCalibration {
    let deviceFromEye: simd_float4x4
    let left: Float
    let right: Float
    let down: Float
    let up: Float
}

/// Finite reverse-Z clip range: the near distance maps to depth 1 and the far distance to 0.
private struct MenuClipRange {
    let near: Float
    let far: Float

    func depth(distance: Float) -> Float {
        near * (far - distance) / (distance * (far - near))
    }

    func distance(depth: Float) -> Float {
        near * far / (depth * (far - near) + near)
    }
}

private struct MenuPlane {
    let center: SIMD3<Float>
    let right: SIMD3<Float>
    let up: SIMD3<Float>
    let size: SIMD2<Float>

    var back: SIMD3<Float> { simd_cross(right, up) }

    /// Room point for quad coordinates in -1...1 (+x right, +y up).
    func point(_ u: Float, _ v: Float) -> SIMD3<Float> {
        center + right * (u * size.x / 2) + up * (v * size.y / 2)
    }
}

private struct MenuEyeView {
    let originFromEye: simd_float4x4
    let calibration: MenuEyeCalibration
    let viewport: MTLViewport

    var position: SIMD3<Float> { xyz3(originFromEye.columns.3) }
    var rotation: simd_float3x3 {
        simd_float3x3(xyz3(originFromEye.columns.0), xyz3(originFromEye.columns.1),
                      xyz3(originFromEye.columns.2))
    }

    /// Room-space ray through a window-space point. Its eye-space forward component is exactly
    /// one, so the ray parameter at a hit is the hit's eye-space distance along -z.
    func ray(_ x: Double, _ y: Double) -> SIMD3<Float> {
        let c = calibration
        let fx = Float((x - viewport.originX) / viewport.width)
        let fy = Float((y - viewport.originY) / viewport.height)
        return rotation * SIMD3(c.left + fx * (c.right - c.left), c.up - fy * (c.up - c.down), -1)
    }

    /// Window-space position of a room point through this eye's own optics.
    func project(_ point: SIMD3<Float>) -> SIMD2<Double> {
        let eye = rotation.transpose * (point - position)
        precondition(eye.z < 0, "menu fixture point is behind the eye")
        let c = calibration
        let fx = (eye.x / -eye.z - c.left) / (c.right - c.left)
        let fy = (c.up - eye.y / -eye.z) / (c.up - c.down)
        return SIMD2(viewport.originX + Double(fx) * viewport.width,
                     viewport.originY + Double(fy) * viewport.height)
    }
}

/// The synthetic calibration in matrix form: right-up-back eye space to reverse-Z clip space.
private func menuClipFromEye(_ c: MenuEyeCalibration,
                             _ range: MenuClipRange) -> simd_float4x4 {
    let n = range.near
    let f = range.far
    return simd_float4x4(columns: (
        SIMD4(2 / (c.right - c.left), 0, 0, 0),
        SIMD4(0, 2 / (c.up - c.down), 0, 0),
        SIMD4((c.right + c.left) / (c.right - c.left), (c.up + c.down) / (c.up - c.down),
              n / (f - n), -1),
        SIMD4(0, 0, n * f / (f - n), 0)
    ))
}

/// What the presenter hands the vertex stage for one eye: quad -> plane -> room -> eye -> clip.
/// The expectations below never use this matrix; they cast rays through each eye's tangents.
private func menuClipFromQuad(_ plane: MenuPlane, _ eye: MenuEyeView,
                              _ range: MenuClipRange) -> simd_float4x4 {
    let originFromQuad = simd_float4x4(columns: (
        SIMD4(plane.right * (plane.size.x / 2), 0),
        SIMD4(plane.up * (plane.size.y / 2), 0),
        SIMD4(plane.back, 0),
        SIMD4(plane.center, 1)
    ))
    return menuClipFromEye(eye.calibration, range) * eye.originFromEye.inverse * originFromQuad
}

private func menuPose(position: SIMD3<Float>, yaw: Float, pitch: Float = 0,
                      roll: Float = 0) -> simd_float4x4 {
    func radians(_ degrees: Float) -> Float { degrees * .pi / 180 }
    let (sy, cy) = (sin(radians(yaw)), cos(radians(yaw)))
    let (sp, cp) = (sin(radians(pitch)), cos(radians(pitch)))
    let (sr, cr) = (sin(radians(roll)), cos(radians(roll)))
    let yawMatrix = simd_float4x4(columns: (
        SIMD4(cy, 0, -sy, 0), SIMD4(0, 1, 0, 0), SIMD4(sy, 0, cy, 0), SIMD4(0, 0, 0, 1)))
    let pitchMatrix = simd_float4x4(columns: (
        SIMD4(1, 0, 0, 0), SIMD4(0, cp, sp, 0), SIMD4(0, -sp, cp, 0), SIMD4(0, 0, 0, 1)))
    let rollMatrix = simd_float4x4(columns: (
        SIMD4(cr, sr, 0, 0), SIMD4(-sr, cr, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)))
    var pose = yawMatrix * pitchMatrix * rollMatrix
    pose.columns.3 = SIMD4(position, 1)
    return pose
}

/// The comfort placement under test: 2 m along the head's gaze, facing it, gravity up.
private func menuPlane(facing head: simd_float4x4, size: SIMD2<Float>) -> MenuPlane {
    let back = simd_normalize(xyz3(head.columns.2))
    let right = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), back))
    return MenuPlane(center: xyz3(head.columns.3) - back * 2, right: right,
                     up: simd_cross(back, right), size: size)
}

private enum MenuTargetLayout {
    case sharedSideBySide
    case layered
    case dedicated
}

private struct MenuCase {
    let label: String
    let head: simd_float4x4
    let plane: MenuPlane
    let sourceWidth: Int
    let sourceHeight: Int
    let fade: Float
    let range: MenuClipRange
    /// Deliberately unrelated native depth bound at texture(1) during the menu draw.
    let nativeDepth: Double
    let layout: MenuTargetLayout
    let depthFormat: MTLPixelFormat
}

private struct MenuEyeImage {
    let color: [UInt8]
    let depth: [Float]
    let width: Int

    func bgra(_ x: Int, _ y: Int) -> [Int] { pixel(color, width: width, x: x, y: y) }
    func depth(_ x: Int, _ y: Int) -> Float { depth[y * width + x] }
}

private struct MenuEyeTally {
    var outside = 0
    var outsideBad = 0
    var inside = 0
    var depthBad = 0
    var maxDepthError: Float = 0
    var colored = 0
    var colorBad = 0
    var minX = Int.max
    var maxX = Int.min
    var minY = Int.max
    var maxY = Int.min
    var firstBad: String?

    mutating func fail(_ message: String) {
        if firstBad == nil { firstBad = message }
    }
}

private let menuViewSize = 256
private let menuDepthTolerance: Float = 2e-6

extension Renderer {
    func menuSource(width: Int, height: Int) -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead]
        let texture = device.makeTexture(descriptor: descriptor)!
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let rgb = menuQuadrantRGB[(x < width / 2 ? 0 : 1) + (y < height / 2 ? 0 : 2)]
                let offset = (y * width + x) * 4
                pixels.replaceSubrange(offset..<offset + 4, with: [
                    UInt8(rgb.z), UInt8(rgb.y), UInt8(rgb.x), 255])
            }
        }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                        withBytes: pixels, bytesPerRow: width * 4)
        return texture
    }

    /// Mirrors the presenter's menu branch: black/far clear, then one plane draw per view with
    /// that view's own clip-from-quad. Unlike the presenter it also binds an unrelated native
    /// depth texture, which the menu fragment must ignore.
    func presentMenu(source: any MTLTexture, nativeDepth: any MTLTexture, fade: Float,
                     clipFromQuads: [simd_float4x4], passes: [VisionImmersivePass],
                     viewports: [MTLViewport], colors: [any MTLTexture],
                     depths: [any MTLTexture], pipeline: any MTLRenderPipelineState) {
        let commandBuffer = queue.makeCommandBuffer()!
        for pass in passes {
            let descriptor = MTLRenderPassDescriptor()
            descriptor.colorAttachments[0].texture = colors[pass.textureIndex]
            descriptor.colorAttachments[0].slice = pass.sliceIndex
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].storeAction = .store
            descriptor.colorAttachments[0].clearColor = MTLClearColor(
                red: 0, green: 0, blue: 0, alpha: 1)
            descriptor.depthAttachment.texture = depths[pass.textureIndex]
            descriptor.depthAttachment.slice = pass.sliceIndex
            descriptor.depthAttachment.loadAction = .clear
            descriptor.depthAttachment.storeAction = .store
            descriptor.depthAttachment.clearDepth = 0
            if depths[pass.textureIndex].pixelFormat == .depth32Float_stencil8 {
                descriptor.stencilAttachment.texture = depths[pass.textureIndex]
                descriptor.stencilAttachment.slice = pass.sliceIndex
                descriptor.stencilAttachment.loadAction = .clear
                descriptor.stencilAttachment.storeAction = .dontCare
            }
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)!
            encoder.setRenderPipelineState(pipeline)
            encoder.setDepthStencilState(depthState)
            encoder.setCullMode(.none)
            for viewIndex in pass.viewIndices {
                var uniforms = ResolveUniforms(clipFromQuad: clipFromQuads[viewIndex], fade: fade)
                encoder.setViewport(viewports[viewIndex])
                encoder.setVertexBytes(
                    &uniforms, length: MemoryLayout<ResolveUniforms>.stride, index: 0)
                encoder.setFragmentBytes(
                    &uniforms, length: MemoryLayout<ResolveUniforms>.stride, index: 0)
                encoder.setFragmentTexture(source, index: 0)
                encoder.setFragmentTexture(nativeDepth, index: 1)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
            encoder.endEncoding()
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        precondition(commandBuffer.status == .completed,
                     "menu plane command buffer failed: \(String(describing: commandBuffer.error))")
    }

    /// Reads the depth aspect of a depth32Float or depth32Float_stencil8 attachment.
    func readDepth(_ texture: any MTLTexture, slice: Int = 0) -> [Float] {
        let bytesPerRow = texture.width * 4
        let length = bytesPerRow * texture.height
        let buffer = device.makeBuffer(length: length, options: .storageModeShared)!
        let commandBuffer = queue.makeCommandBuffer()!
        let blit = commandBuffer.makeBlitCommandEncoder()!
        blit.copy(from: texture, sourceSlice: slice, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
                  to: buffer, destinationOffset: 0, destinationBytesPerRow: bytesPerRow,
                  destinationBytesPerImage: length,
                  options: texture.pixelFormat == .depth32Float_stencil8
                      ? .depthFromDepthStencil : [])
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        precondition(commandBuffer.status == .completed)
        return Array(UnsafeBufferPointer(
            start: buffer.contents().assumingMemoryBound(to: Float.self),
            count: texture.width * texture.height))
    }
}

/// Classifies every pixel of one eye view against an independent ray/plane cast through that
/// eye's own tangents. Pixels within about a pixel of the plane edge, or of a texel boundary for
/// color, are left unclassified; everything else must match exactly.
private func tallyMenuEye(_ image: MenuEyeImage, eye: MenuEyeView, menu: MenuCase)
    -> MenuEyeTally {
    var tally = MenuEyeTally()
    let plane = menu.plane
    func cast(_ x: Double, _ y: Double) -> (uv: SIMD2<Float>, distance: Float)? {
        let direction = eye.ray(x, y)
        let facing = simd_dot(direction, plane.back)
        guard facing < 0 else { return nil }
        let distance = simd_dot(plane.center - eye.position, plane.back) / facing
        guard distance > 0 else { return nil }
        let offset = eye.position + direction * distance - plane.center
        return (SIMD2(simd_dot(offset, plane.right) / (plane.size.x / 2),
                      simd_dot(offset, plane.up) / (plane.size.y / 2)), distance)
    }
    let originX = Int(eye.viewport.originX)
    let originY = Int(eye.viewport.originY)
    for y in originY..<originY + Int(eye.viewport.height) {
        for x in originX..<originX + Int(eye.viewport.width) {
            let bgra = image.bgra(x, y)
            let depth = image.depth(x, y)
            if depth != 0 || bgra[0] != 0 || bgra[1] != 0 || bgra[2] != 0 {
                tally.minX = min(tally.minX, x)
                tally.maxX = max(tally.maxX, x)
                tally.minY = min(tally.minY, y)
                tally.maxY = max(tally.maxY, y)
            }
            let centerX = Double(x) + 0.5
            let centerY = Double(y) + 0.5
            guard let hit = cast(centerX, centerY),
                  let stepX = cast(centerX + 1, centerY),
                  let stepY = cast(centerX, centerY + 1) else {
                continue
            }
            let margin = (abs(stepX.uv - hit.uv) + abs(stepY.uv - hit.uv)) * 1.5
                + SIMD2(repeating: 1e-3)
            let uv = hit.uv
            if abs(uv.x) > 1 + margin.x || abs(uv.y) > 1 + margin.y {
                tally.outside += 1
                if bgra != [0, 0, 0, 255] || depth != 0 {
                    tally.outsideBad += 1
                    tally.fail("outside pixel (\(x),\(y)) bgra \(bgra) depth \(depth)")
                }
                continue
            }
            guard abs(uv.x) < 1 - margin.x && abs(uv.y) < 1 - margin.y else { continue }
            tally.inside += 1
            let expectedDepth = menu.range.depth(distance: hit.distance)
            let error = abs(depth - expectedDepth)
            tally.maxDepthError = max(tally.maxDepthError, error)
            if error > menuDepthTolerance {
                tally.depthBad += 1
                tally.fail("inside pixel (\(x),\(y)) depth \(depth) expected \(expectedDepth)")
            }
            let texel = SIMD2(2 / Float(menu.sourceWidth), 2 / Float(menu.sourceHeight))
            guard abs(uv.x) > texel.x + margin.x && abs(uv.y) > texel.y + margin.y else {
                continue
            }
            tally.colored += 1
            let rgb = menuQuadrantRGB[(uv.x < 0 ? 0 : 1) + (uv.y > 0 ? 0 : 2)]
            let expected = (0..<3).map { Int((rgb[2 - $0] * menu.fade).rounded()) } + [255]
            if !close(bgra, expected, tolerance: 2) {
                tally.colorBad += 1
                tally.fail("inside pixel (\(x),\(y)) bgra \(bgra) expected \(expected)")
            }
        }
    }
    return tally
}

private func menuCalibrations() -> [MenuEyeCalibration] {
    // Explicit synthetic optics: 64 mm baseline, slight toe-out, mirrored asymmetric frusta.
    func offset(_ x: Float, toeOutDegrees: Float) -> simd_float4x4 {
        menuPose(position: SIMD3(x, -0.002, -0.012), yaw: toeOutDegrees)
    }
    return [
        MenuEyeCalibration(deviceFromEye: offset(-0.0315, toeOutDegrees: 1.2),
                           left: -1.05, right: 0.85, down: -0.95, up: 0.80),
        MenuEyeCalibration(deviceFromEye: offset(0.0325, toeOutDegrees: -1.2),
                           left: -0.85, right: 1.05, down: -0.95, up: 0.80),
    ]
}

/// Renders one case and returns each eye's room point recovered from GPU depth at the plane
/// centre, so cases can be compared for a room-fixed plane.
@discardableResult
private func runMenuCase(_ renderer: Renderer, _ menu: MenuCase,
                         pipeline: any MTLRenderPipelineState) -> [SIMD3<Float>] {
    print("Menu plane: \(menu.label)")
    let size = menuViewSize
    let viewports: [MTLViewport]
    let mappings: [VisionImmersiveViewMapping]
    let targetWidth: Int
    let slices: Int
    let textureCount: Int
    switch menu.layout {
    case .sharedSideBySide:
        viewports = [0, size].map {
            MTLViewport(originX: Double($0), originY: 0, width: Double(size),
                        height: Double(size), znear: 0, zfar: 1)
        }
        mappings = viewports.map { mapping(texture: 0, slice: 0, viewport: $0) }
        (targetWidth, slices, textureCount) = (size * 2, 1, 1)
    case .layered:
        let view = MTLViewport(originX: 0, originY: 0, width: Double(size),
                               height: Double(size), znear: 0, zfar: 1)
        viewports = [view, view]
        mappings = [mapping(texture: 0, slice: 0, viewport: view),
                    mapping(texture: 0, slice: 1, viewport: view)]
        (targetWidth, slices, textureCount) = (size, 2, 1)
    case .dedicated:
        let view = MTLViewport(originX: 0, originY: 0, width: Double(size),
                               height: Double(size), znear: 0, zfar: 1)
        viewports = [view, view]
        mappings = [mapping(texture: 0, slice: 0, viewport: view),
                    mapping(texture: 1, slice: 0, viewport: view)]
        (targetWidth, slices, textureCount) = (size, 1, 2)
    }
    let shape = VisionImmersiveTargetShape(width: targetWidth, height: size, sliceCount: slices)
    let passes = VisionImmersivePassPlanner.passes(
        views: mappings,
        colorTargets: Array(repeating: shape, count: textureCount),
        depthTargets: Array(repeating: shape, count: textureCount))!
    let colors = (0..<textureCount).map { _ in
        renderer.texture(.bgra8Unorm_srgb, width: targetWidth, height: size, slices: slices,
                         usage: [.renderTarget])
    }
    let depths = (0..<textureCount).map { _ in
        renderer.texture(menu.depthFormat, width: targetWidth, height: size, slices: slices,
                         usage: [.renderTarget])
    }
    let calibrations = menuCalibrations()
    let eyes = (0..<2).map {
        MenuEyeView(originFromEye: menu.head * calibrations[$0].deviceFromEye,
                    calibration: calibrations[$0], viewport: viewports[$0])
    }
    let clipFromQuads = eyes.map { menuClipFromQuad(menu.plane, $0, menu.range) }
    renderer.presentMenu(
        source: renderer.menuSource(width: menu.sourceWidth, height: menu.sourceHeight),
        nativeDepth: renderer.depthSource(menu.nativeDepth), fade: menu.fade,
        clipFromQuads: clipFromQuads, passes: passes, viewports: viewports,
        colors: colors, depths: depths, pipeline: pipeline)

    var centers: [SIMD3<Float>] = []
    var expectedBoxes: [SIMD4<Double>] = []
    var measuredBoxes: [SIMD4<Double>] = []
    for (index, eye) in eyes.enumerated() {
        let name = index == 0 ? "left eye" : "right eye"
        let map = mappings[index]
        let image = MenuEyeImage(
            color: renderer.read(colors[map.textureIndex], slice: map.sliceIndex,
                                 bytesPerPixel: 4),
            depth: renderer.readDepth(depths[map.textureIndex], slice: map.sliceIndex),
            width: targetWidth)
        let tally = tallyMenuEye(image, eye: eye, menu: menu)
        if let firstBad = tally.firstBad { print("       first mismatch: \(firstBad)") }

        let viewPixels = size * size
        check(tally.outsideBad == 0 && tally.outside > viewPixels / 4,
              "\(name): all \(tally.outside) pixels outside the projected plane stay opaque "
                + "black at reverse-Z far 0")
        let nativeValue = Float(menu.nativeDepth)
        check(tally.depthBad == 0 && tally.inside > viewPixels / 20,
              "\(name): \(tally.inside) plane pixels carry analytic ray/plane depth "
                + "(max error \(tally.maxDepthError)), not bound native depth \(nativeValue)")
        check(tally.colorBad == 0 && tally.colored > viewPixels / 25,
              "\(name): \(tally.colored) plane pixels show the conventional image's quadrant "
                + "at fade \(menu.fade)")

        // Projected corners through this eye's own optics bound the drawn rectangle. A rolled
        // rectangle's corner is a thin wedge whose tip may cover no pixel centre, hence 2 px.
        let corners = [(-1, 1), (1, 1), (-1, -1), (1, -1)].map {
            eye.project(menu.plane.point(Float($0.0), Float($0.1)))
        }
        let expectedBox = SIMD4(corners.map(\.x).min()!, corners.map(\.x).max()!,
                                corners.map(\.y).min()!, corners.map(\.y).max()!)
        let measuredBox = SIMD4(Double(tally.minX) + 0.5, Double(tally.maxX) + 0.5,
                                Double(tally.minY) + 0.5, Double(tally.maxY) + 0.5)
        expectedBoxes.append(expectedBox - SIMD4(eye.viewport.originX, eye.viewport.originX,
                                                 0, 0))
        measuredBoxes.append(measuredBox - SIMD4(eye.viewport.originX, eye.viewport.originX,
                                                 0, 0))
        let viewEnd = SIMD2(eye.viewport.originX + eye.viewport.width, eye.viewport.height)
        check(tally.minX <= tally.maxX && simd_reduce_max(abs(measuredBox - expectedBox)) <= 2.0
                && measuredBox.x > eye.viewport.originX + 8 && measuredBox.y < viewEnd.x - 8
                && measuredBox.z > 8 && measuredBox.w < viewEnd.y - 8,
              "\(name): drawn extent \(measuredBox) matches projected corners \(expectedBox) "
                + "and is a smaller rectangle inside the view")

        var cornerColors = true
        for (quadrant, (u, v)) in [(-0.85, 0.85), (0.85, 0.85), (-0.85, -0.85),
                                   (0.85, -0.85)].enumerated() {
            let at = eye.project(menu.plane.point(Float(u), Float(v)))
            let expected = (0..<3).map {
                Int((menuQuadrantRGB[quadrant][2 - $0] * menu.fade).rounded())
            } + [255]
            let actual = image.bgra(Int(at.x), Int(at.y))
            if !close(actual, expected, tolerance: 2) {
                cornerColors = false
                print("       \(menuQuadrantNames[quadrant]) corner at \(at): bgra \(actual)")
            }
        }
        check(cornerColors, "\(name): image corners land at the plane's top-left red, "
                + "top-right green, bottom-left blue and bottom-right yellow corners")

        // Physical size from GPU depth: unproject the pixels at 90% of each half-axis.
        func room(_ u: Float, _ v: Float) -> SIMD3<Float> {
            let at = eye.project(menu.plane.point(u, v))
            let x = Int(at.x)
            let y = Int(at.y)
            return eye.position + eye.ray(Double(x) + 0.5, Double(y) + 0.5)
                * menu.range.distance(depth: image.depth(x, y))
        }
        let width = simd_distance(room(-0.9, 0), room(0.9, 0)) / 0.9
        let height = simd_distance(room(0, -0.9), room(0, 0.9)) / 0.9
        check(abs(width - menu.plane.size.x) < 0.025 && abs(height - menu.plane.size.y) < 0.025,
              "\(name): GPU depth unprojects to a \(width) x \(height) m plane "
                + "(expected \(menu.plane.size.x) x \(menu.plane.size.y), aspect "
                + "\(menu.sourceWidth):\(menu.sourceHeight))")
        centers.append(room(0, 0))
    }

    let headPosition = xyz3(menu.head.columns.3)
    let expectedDistance = simd_distance(headPosition, menu.plane.center)
    check(centers.allSatisfy { simd_distance($0, menu.plane.center) < 0.015 }
            && simd_distance(centers[0], centers[1]) < 0.015,
          "both eyes' GPU depth converges on the room plane centre \(menu.plane.center) "
            + "(left \(centers[0]), right \(centers[1]); \(expectedDistance) m from the head)")
    let expectedShift = expectedBoxes[0] - expectedBoxes[1]
    let measuredShift = measuredBoxes[0] - measuredBoxes[1]
    check(abs(expectedShift.x) > 6 && simd_reduce_max(abs(measuredShift - expectedShift)) <= 2.0,
          "the eyes place the plane distinctly: left-minus-right extent shift \(measuredShift) "
            + "matches \(expectedShift) px")
    return centers
}

private func checkMenuPlane(_ renderer: Renderer) {
    let pipelines: [MTLPixelFormat: any MTLRenderPipelineState] = [
        .depth32Float: renderer.pipeline(color: .bgra8Unorm_srgb, depth: .depth32Float,
                                         fragment: menuPlaneFragment),
        .depth32Float_stencil8: renderer.pipeline(color: .bgra8Unorm_srgb,
                                                  depth: .depth32Float_stencil8,
                                                  fragment: menuPlaneFragment),
    ]
    let openingHead = menuPose(position: SIMD3(0.3, 1.6, -0.2), yaw: 20)
    let roomPlane = menuPlane(facing: openingHead, size: SIMD2(1.6, 1.2))
    let opening = MenuCase(
        label: "4:3 frame 2 m ahead at menu open, shared side-by-side target",
        head: openingHead, plane: roomPlane, sourceWidth: 64, sourceHeight: 48, fade: 1,
        range: MenuClipRange(near: 0.08, far: 60), nativeDepth: 0.6,
        layout: .sharedSideBySide, depthFormat: .depth32Float)
    runMenuCase(renderer, opening, pipeline: pipelines[opening.depthFormat]!)

    // The head steps forward and right and turns, pitches and rolls; the plane stays in the
    // room, so it is now nearer, off-axis and tilted relative to both eyes.
    let movedHead = menuPose(
        position: SIMD3(0.3, 1.55, -0.2) + SIMD3(-sin(20 * Float.pi / 180), 0,
                                                  -cos(20 * Float.pi / 180)) * 0.35
            + SIMD3(cos(20 * Float.pi / 180), 0, -sin(20 * Float.pi / 180)) * 0.15,
        yaw: 26, pitch: -5, roll: 10)
    let moved = MenuCase(
        label: "same room-fixed plane after a head shift and tilt, layered D32S8 target",
        head: movedHead, plane: roomPlane, sourceWidth: 64, sourceHeight: 48, fade: 0.5,
        range: MenuClipRange(near: 0.1, far: 40), nativeDepth: 0.9,
        layout: .layered, depthFormat: .depth32Float_stencil8)
    runMenuCase(renderer, moved, pipeline: pipelines[moved.depthFormat]!)

    let pitchedHead = menuPose(position: SIMD3(-0.4, 1.3, 0.5), yaw: -25, pitch: 12, roll: -8)
    let wide = MenuCase(
        label: "16:9 frame 2 m ahead of a pitched, rolled head, dedicated D32S8 targets",
        head: pitchedHead, plane: menuPlane(facing: pitchedHead, size: SIMD2(1.6, 0.9)),
        sourceWidth: 64, sourceHeight: 36, fade: 0.75,
        range: MenuClipRange(near: 0.05, far: 500), nativeDepth: 0.02,
        layout: .dedicated, depthFormat: .depth32Float_stencil8)
    runMenuCase(renderer, wide, pipeline: pipelines[wide.depthFormat]!)

    let openingDepth = opening.range.depth(distance: 2)
    let movedDistance = simd_distance(xyz3(movedHead.columns.3), roomPlane.center)
    check(abs(movedDistance - 2) > 0.2
            && abs(moved.range.depth(distance: movedDistance) - openingDepth) > 0.005,
          "the fixtures cover distinct plane distances (2 m and \(movedDistance) m) and "
            + "depth ranges, so no single literal depth can satisfy them")
}

@main
private enum VisionImmersivePerEyeResolveGPUCheck {
    static func main() {
        guard CommandLine.arguments.count == 2 else {
            print("usage: vision-immersive-per-eye-resolve-gpu-check <metallib>")
            exit(2)
        }
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(
                URL: URL(fileURLWithPath: CommandLine.arguments[1])) else {
            print("Metal or the compiled per-eye resolve shader is unavailable")
            exit(1)
        }
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .always
        depthDescriptor.isDepthWriteEnabled = true
        let renderer = Renderer(
            device: device,
            queue: queue,
            library: library,
            depthState: device.makeDepthStencilState(descriptor: depthDescriptor)!
        )
        let sources = [
            EyeSource(color: renderer.colorSource(rightEye: false),
                      depth: renderer.depthSource(0.25)),
            EyeSource(color: renderer.colorSource(rightEye: true),
                      depth: renderer.depthSource(0.75)),
        ]
        checkDedicated(renderer, sources: sources)
        checkLayered(renderer, sources: sources)
        checkShared(renderer, sources: sources)
        checkFarDepthNudge(renderer, sources: sources)
        checkD32S8CompositorRoundTrip(renderer, sources: sources)
        checkAggregateEvidence(renderer, depths: sources.map(\.depth))
        checkMenuPlane(renderer)
        guard failures == 0 else {
            print("visionOS per-eye resolve GPU checks failed: \(failures)")
            // Redirected stdout is block-buffered and the trap below would discard it.
            fflush(stdout)
            fatalError("per-eye resolve GPU check failed")
        }
        print("visionOS per-eye resolve GPU checks passed on \(device.name)")
    }
}
