import QuartzCore
import SwiftUI

#if os(visionOS)
import GameController
#endif

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

    #if os(visionOS)
    @Environment(VisionPresentationCoordinator.self) private var visionPresentation
    let isStereoRendererReady: Bool
    let onStereoFrame: VisionWindowStereoFrameHandler?

    init(onFrame: @escaping (CFTimeInterval) -> Void,
         isStereoRendererReady: Bool = false,
         onStereoFrame: VisionWindowStereoFrameHandler? = nil) {
        self.onFrame = onFrame
        self.isStereoRendererReady = isStereoRendererReady
        self.onStereoFrame = onStereoFrame
    }
    #endif

    var body: some View {
        #if os(visionOS)
        Group {
            if visionPresentation.isStereoWindowActive, onStereoFrame != nil {
                VisionWindowStereoSurfaceView { frame in
                    onStereoFrame?(frame) ?? .skipped
                }
            } else {
                conventionalSurface
            }
        }
        .onChange(of: isStereoRendererReady, initial: true) { _, isReady in
            visionPresentation.setStereoRendererAvailable(isReady && onStereoFrame != nil)
        }
        .onDisappear {
            visionPresentation.setStereoRendererAvailable(false)
        }
        .overlay(alignment: .topLeading) {
            VisionGamepadEventRoutingAnchorView()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        #else
        conventionalSurface
        #endif
    }

    private var conventionalSurface: some View {
        SurfaceRepresentable(onFrame: onFrame)
            .ignoresSafeArea()
            .background(.black)
    }
}

#if os(visionOS)

/// visionOS otherwise turns gamepad actions into gaze-and-pinch UI events. Route the gameplay
/// window through Game Controller without adding a visible or interactive gameplay view.
private final class VisionGamepadEventRoutingAnchor: UIView {
    private let gamepadInteraction: GCEventInteraction = {
        let interaction = GCEventInteraction()
        interaction.handledEventTypes = .gamepad
        return interaction
    }()
    private weak var interactionHost: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        routeGamepadEvents(through: window)
    }

    func detach() {
        routeGamepadEvents(through: nil)
    }

    private func routeGamepadEvents(through host: UIView?) {
        guard interactionHost !== host else { return }
        interactionHost?.removeInteraction(gamepadInteraction)
        interactionHost = host
        host?.addInteraction(gamepadInteraction)
    }
}

private struct VisionGamepadEventRoutingAnchorView: UIViewRepresentable {
    func makeUIView(context: Context) -> VisionGamepadEventRoutingAnchor {
        VisionGamepadEventRoutingAnchor(frame: .zero)
    }

    func updateUIView(_ view: VisionGamepadEventRoutingAnchor, context: Context) {}

    static func dismantleUIView(_ view: VisionGamepadEventRoutingAnchor,
                                coordinator: Void) {
        view.detach()
    }
}

#endif

/// Xcode's generated iPad scene manifest supports multiple windows, while the native renderer has
/// one process-wide surface. Keep that surface assigned to exactly one active host view. Other
/// active windows retain their display links so ownership transfers without needing a second scene
/// activation callback, but only the selected owner is allowed to drive or resize the renderer.
@MainActor
private final class PresentationSurfaceCoordinator {
    static let shared = PresentationSurfaceCoordinator()

    private final class Candidate {
        let layer: CAMetalLayer
        var drawableSize = CGSize.zero

        init(layer: CAMetalLayer) {
            self.layer = layer
        }
    }

    private var state = PresentationOwnershipState<ObjectIdentifier>()
    private var candidates: [ObjectIdentifier: Candidate] = [:]
    private var attachedOwner: ObjectIdentifier?

    func register(_ host: AnyObject, layer: CAMetalLayer) {
        let candidate = ObjectIdentifier(host)
        if candidates[candidate] == nil {
            candidates[candidate] = Candidate(layer: layer)
            state.register(candidate)
        }
    }

    func activate(_ host: AnyObject, layer: CAMetalLayer) {
        let candidate = ObjectIdentifier(host)
        register(host, layer: layer)
        state.activate(candidate)
        reconcileAttachment()
    }

    func deactivate(_ host: AnyObject) {
        state.deactivate(ObjectIdentifier(host))
        reconcileAttachment()
    }

    func unregister(_ host: AnyObject) {
        let candidate = ObjectIdentifier(host)
        state.unregister(candidate)
        candidates.removeValue(forKey: candidate)
        reconcileAttachment()
    }

    func updateDrawableSize(_ size: CGSize, for host: AnyObject) {
        let candidate = ObjectIdentifier(host)
        candidates[candidate]?.drawableSize = size
        guard state.isOwner(candidate) else { return }
        GOALPadRenderSurface.shared.setDrawableSize(size)
    }

    func isOwner(_ host: AnyObject) -> Bool {
        state.isOwner(ObjectIdentifier(host))
    }

    private func reconcileAttachment() {
        guard attachedOwner != state.owner else { return }
        attachedOwner = state.owner
        guard let owner = state.owner, let candidate = candidates[owner] else {
            GOALPadRenderSurface.shared.attach(nil)
            return
        }
        GOALPadRenderSurface.shared.attach(candidate.layer)
        GOALPadRenderSurface.shared.setDrawableSize(candidate.drawableSize)
    }
}

#if canImport(UIKit)

private final class MetalHostView: UIView {
    var onFrame: ((CFTimeInterval) -> Void)?
    private var frameLink: CADisplayLink?
    private var observesSceneLifecycle = false

    override class var layerClass: AnyClass { CAMetalLayer.self }

    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopObservingSceneLifecycle()
            stopDisplayLink()
            PresentationSurfaceCoordinator.shared.unregister(self)
            return
        }
        startObservingSceneLifecycle()
        guard window?.windowScene?.activationState == .foregroundActive else {
            suspendPresentation()
            return
        }
        resumePresentation()
    }

    private func resumePresentation() {
        #if os(visionOS)
        layer.contentsScale = contentScaleFactor
        #else
        layer.contentsScale = window?.screen.nativeScale ?? layer.contentsScale
        #endif
        PresentationSurfaceCoordinator.shared.activate(self, layer: metalLayer)
        updateDrawableSize()
        startDisplayLink()
    }

    private func suspendPresentation() {
        stopDisplayLink()
        PresentationSurfaceCoordinator.shared.deactivate(self)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        let scale = layer.contentsScale
        PresentationSurfaceCoordinator.shared.updateDrawableSize(
            CGSize(width: bounds.width * scale, height: bounds.height * scale), for: self)
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

    private func startObservingSceneLifecycle() {
        guard !observesSceneLifecycle else { return }
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(sceneWillDeactivate(_:)),
                           name: UIScene.willDeactivateNotification, object: nil)
        center.addObserver(self, selector: #selector(sceneDidActivate(_:)),
                           name: UIScene.didActivateNotification, object: nil)
        observesSceneLifecycle = true
    }

    private func stopObservingSceneLifecycle() {
        guard observesSceneLifecycle else { return }
        let center = NotificationCenter.default
        center.removeObserver(self, name: UIScene.willDeactivateNotification, object: nil)
        center.removeObserver(self, name: UIScene.didActivateNotification, object: nil)
        observesSceneLifecycle = false
    }

    private func belongsToCurrentScene(_ notification: Notification) -> Bool {
        guard let scene = notification.object as? UIScene,
              let windowScene = window?.windowScene else { return false }
        return scene === windowScene
    }

    @objc private func sceneWillDeactivate(_ notification: Notification) {
        guard belongsToCurrentScene(notification) else { return }
        suspendPresentation()
    }

    @objc private func sceneDidActivate(_ notification: Notification) {
        guard belongsToCurrentScene(notification), window != nil else { return }
        resumePresentation()
    }

    @objc private func step(_ link: CADisplayLink) {
        guard PresentationSurfaceCoordinator.shared.isOwner(self) else { return }
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
    private var observesApplicationLifecycle = false

    override func makeBackingLayer() -> CALayer { CAMetalLayer() }

    private var metalLayer: CAMetalLayer? { layer as? CAMetalLayer }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            stopObservingApplicationLifecycle()
            frameLink?.invalidate()
            frameLink = nil
            PresentationSurfaceCoordinator.shared.unregister(self)
            return
        }
        startObservingApplicationLifecycle()
        guard NSApplication.shared.isActive else {
            suspendPresentation()
            return
        }
        resumePresentation()
    }

    private func resumePresentation() {
        guard let window else { return }
        wantsLayer = true
        layer?.contentsScale = window.backingScaleFactor
        if let metalLayer {
            PresentationSurfaceCoordinator.shared.activate(self, layer: metalLayer)
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

    private func suspendPresentation() {
        frameLink?.invalidate()
        frameLink = nil
        PresentationSurfaceCoordinator.shared.deactivate(self)
    }

    private func startObservingApplicationLifecycle() {
        guard !observesApplicationLifecycle else { return }
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(applicationDidResignActive(_:)),
                           name: NSApplication.didResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(applicationDidBecomeActive(_:)),
                           name: NSApplication.didBecomeActiveNotification, object: nil)
        observesApplicationLifecycle = true
    }

    private func stopObservingApplicationLifecycle() {
        guard observesApplicationLifecycle else { return }
        let center = NotificationCenter.default
        center.removeObserver(self, name: NSApplication.didResignActiveNotification, object: nil)
        center.removeObserver(self, name: NSApplication.didBecomeActiveNotification, object: nil)
        observesApplicationLifecycle = false
    }

    @objc private func applicationDidResignActive(_ notification: Notification) {
        suspendPresentation()
    }

    @objc private func applicationDidBecomeActive(_ notification: Notification) {
        guard window != nil else { return }
        resumePresentation()
    }

    override func layout() {
        super.layout()
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        let scale = layer?.contentsScale ?? 1
        PresentationSurfaceCoordinator.shared.updateDrawableSize(
            CGSize(width: bounds.width * scale, height: bounds.height * scale), for: self)
    }

    @objc private func step(_ link: CADisplayLink) {
        guard PresentationSurfaceCoordinator.shared.isOwner(self) else { return }
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
