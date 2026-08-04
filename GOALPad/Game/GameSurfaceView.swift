import QuartzCore
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The view that owns the `CAMetalLayer` the game is presented into, and the display link that
/// drives one frame at a time.
///
/// The layer is handed straight to `GOALPadRenderSurface`, which owns everything drawn into it.
/// This view's only jobs are to keep the drawable size in step with the screen and to call back
/// once per refresh.
struct GameSurfaceView: View {
    /// Called once per display refresh, on the main thread.
    let onFrame: (CFTimeInterval) -> Void

    var body: some View {
        SurfaceRepresentable(onFrame: onFrame)
            .ignoresSafeArea()
            .background(.black)
    }
}

#if canImport(UIKit)

private final class MetalHostView: UIView {
    var onFrame: ((CFTimeInterval) -> Void)?
    private var frameLink: CADisplayLink?

    override class var layerClass: AnyClass { CAMetalLayer.self }

    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopDisplayLink()
            GOALPadRenderSurface.shared.attach(nil)
            return
        }
        #if os(visionOS)
        layer.contentsScale = contentScaleFactor
        #else
        layer.contentsScale = window?.screen.nativeScale ?? layer.contentsScale
        #endif
        GOALPadRenderSurface.shared.attach(metalLayer)
        updateDrawableSize()
        startDisplayLink()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        let scale = layer.contentsScale
        GOALPadRenderSurface.shared.setDrawableSize(
            CGSize(width: bounds.width * scale, height: bounds.height * scale))
    }

    private func startDisplayLink() {
        guard frameLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        // The game runs at 60 Hz; letting a ProMotion display ask for 120 would only spend power.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        frameLink = link
    }

    private func stopDisplayLink() {
        frameLink?.invalidate()
        frameLink = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        onFrame?(link.targetTimestamp)
    }
}

private struct SurfaceRepresentable: UIViewRepresentable {
    let onFrame: (CFTimeInterval) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = MetalHostView()
        view.onFrame = onFrame
        view.isOpaque = true
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        (view as? MetalHostView)?.onFrame = onFrame
    }
}

#elseif canImport(AppKit)

/// The macOS launcher uses the same Metal surface and frame callback as the mobile app.
private final class MetalHostView: NSView {
    var onFrame: ((CFTimeInterval) -> Void)?
    private var frameLink: CADisplayLink?

    override func makeBackingLayer() -> CALayer { CAMetalLayer() }

    private var metalLayer: CAMetalLayer? { layer as? CAMetalLayer }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else {
            frameLink?.invalidate()
            frameLink = nil
            GOALPadRenderSurface.shared.attach(nil)
            return
        }
        wantsLayer = true
        layer?.contentsScale = window.backingScaleFactor
        if let metalLayer {
            GOALPadRenderSurface.shared.attach(metalLayer)
        }
        updateDrawableSize()
        if frameLink == nil {
            let link = displayLink(target: self, selector: #selector(step(_:)))
            // Match the game's 60 Hz clock even when the Mac display supports 120 Hz.
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            frameLink = link
        }
    }

    override func layout() {
        super.layout()
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        let scale = layer?.contentsScale ?? 1
        GOALPadRenderSurface.shared.setDrawableSize(
            CGSize(width: bounds.width * scale, height: bounds.height * scale))
    }

    @objc private func step(_ link: CADisplayLink) {
        onFrame?(link.targetTimestamp)
    }
}

private struct SurfaceRepresentable: NSViewRepresentable {
    let onFrame: (CFTimeInterval) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = MetalHostView()
        view.wantsLayer = true
        view.onFrame = onFrame
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? MetalHostView)?.onFrame = onFrame
    }
}

#endif
