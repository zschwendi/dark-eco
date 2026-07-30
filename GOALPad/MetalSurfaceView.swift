import MetalKit
import OSLog
import SwiftUI

private final class MetalRenderer: NSObject, MTKViewDelegate {
    private let commandQueue: MTLCommandQueue
    private var loggedFirstFrame = false

    init?(view: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue()
        else {
            return nil
        }

        self.commandQueue = commandQueue
        super.init()
        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.025, green: 0.055, blue: 0.09, alpha: 1)
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.delegate = self
    }

    func mtkView(_: MTKView, drawableSizeWillChange _: CGSize) {}

    func draw(in view: MTKView) {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else {
            return
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()

        if !loggedFirstFrame {
            loggedFirstFrame = true
            Logger(subsystem: "com.zephyrstudiosllc.GOALPad", category: "Metal")
                .notice("First Metal frame submitted")
        }
    }
}

#if canImport(UIKit)
private struct MetalViewRepresentable: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        context.coordinator.makeView()
    }

    func updateUIView(_: MTKView, context _: Context) {}

    final class Coordinator {
        private var renderer: MetalRenderer?

        func makeView() -> MTKView {
            let view = MTKView()
            renderer = MetalRenderer(view: view)
            return view
        }
    }
}
#elseif canImport(AppKit)
private struct MetalViewRepresentable: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MTKView {
        context.coordinator.makeView()
    }

    func updateNSView(_: MTKView, context _: Context) {}

    final class Coordinator {
        private var renderer: MetalRenderer?

        func makeView() -> MTKView {
            let view = MTKView()
            renderer = MetalRenderer(view: view)
            return view
        }
    }
}
#endif

struct MetalSurfaceView: View {
    var body: some View {
        MetalViewRepresentable()
            .ignoresSafeArea()
    }
}
