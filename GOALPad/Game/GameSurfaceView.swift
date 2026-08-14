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
    var targetFrameRate = 60
    var hidesCursorInFullScreen = false

    #if os(visionOS) && GOALPAD_EXPERIMENTAL_VISION_STEREO
    @Environment(VisionPresentationCoordinator.self) private var visionPresentation
    let isStereoRendererReady: Bool
    let onStereoFrame: VisionWindowStereoFrameHandler?

    init(onFrame: @escaping (CFTimeInterval) -> Void,
         targetFrameRate: Int = 60,
         isStereoRendererReady: Bool = false,
         onStereoFrame: VisionWindowStereoFrameHandler? = nil) {
        self.onFrame = onFrame
        self.targetFrameRate = targetFrameRate
        self.isStereoRendererReady = isStereoRendererReady
        self.onStereoFrame = onStereoFrame
    }
    #endif

    var body: some View {
        #if os(visionOS) && GOALPAD_EXPERIMENTAL_VISION_STEREO
        Group {
            if visionPresentation.isStereoWindowActive, onStereoFrame != nil {
                VisionWindowStereoSurfaceView { frame in
                    onStereoFrame?(frame) ?? .skipped
                }
                .handlesGameControllerEvents(matching: .gamepad)
            } else {
                conventionalSurface
                    .handlesGameControllerEvents(matching: .gamepad)
            }
        }
        .onChange(of: isStereoRendererReady, initial: true) { _, isReady in
            visionPresentation.setStereoRendererAvailable(isReady && onStereoFrame != nil)
        }
        .onDisappear {
            visionPresentation.setStereoRendererAvailable(false)
        }
        #elseif os(visionOS)
        conventionalSurface
            .handlesGameControllerEvents(matching: .gamepad)
        #else
        conventionalSurface
        #endif
    }

    private var conventionalSurface: some View {
        SurfaceRepresentable(onFrame: onFrame,
                             targetFrameRate: targetFrameRate,
                             hidesCursorInFullScreen: hidesCursorInFullScreen)
            .ignoresSafeArea()
            .background(.black)
    }
}

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
    var targetFrameRate = 60 {
        didSet {
            guard targetFrameRate != oldValue, let frameLink else { return }
            configureFrameRate(for: frameLink)
        }
    }
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
        configureFrameRate(for: link)
        link.add(to: .main, forMode: .common)
        frameLink = link
    }

    private func configureFrameRate(for link: CADisplayLink) {
        #if os(visionOS)
        if targetFrameRate >= 90 {
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: 90, maximum: 90, preferred: 90)
            return
        }
        #endif
        #if os(iOS)
        let screenMaximum = window?.screen.maximumFramesPerSecond ?? 60
        if targetFrameRate >= 120, screenMaximum > 60 {
            let maximum = Float(min(screenMaximum, 120))
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: 60, maximum: maximum, preferred: maximum)
            return
        }
        #endif
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
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
    let targetFrameRate: Int
    let hidesCursorInFullScreen: Bool

    func makeUIView(context: Context) -> UIView {
        let view = MetalHostView()
        view.onFrame = onFrame
        view.targetFrameRate = targetFrameRate
        view.isOpaque = true
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        guard let view = view as? MetalHostView else { return }
        view.onFrame = onFrame
        view.targetFrameRate = targetFrameRate
    }
}

#elseif canImport(AppKit)

/// The macOS launcher uses the same Metal surface and frame callback as the mobile app.
private final class MetalHostView: NSView {
    var onFrame: ((CFTimeInterval) -> Void)?
    var hidesCursorInFullScreen = false {
        didSet { updateCursorVisibility() }
    }
    private var frameLink: CADisplayLink?
    private var observesApplicationLifecycle = false
    private var cursorIsHidden = false
    private var mouseIsInside = false
    private var cursorTrackingArea: NSTrackingArea?

    override func makeBackingLayer() -> CALayer { CAMetalLayer() }

    private var metalLayer: CAMetalLayer? { layer as? CAMetalLayer }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            stopObservingApplicationLifecycle()
            showCursorIfNeeded()
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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cursorTrackingArea { removeTrackingArea(cursorTrackingArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        cursorTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        mouseIsInside = true
        updateCursorVisibility()
    }

    override func mouseExited(with event: NSEvent) {
        mouseIsInside = false
        updateCursorVisibility()
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
        updateCursorVisibility()
    }

    private func suspendPresentation() {
        frameLink?.invalidate()
        frameLink = nil
        PresentationSurfaceCoordinator.shared.deactivate(self)
        updateCursorVisibility()
    }

    private func startObservingApplicationLifecycle() {
        guard !observesApplicationLifecycle else { return }
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(applicationDidResignActive(_:)),
                           name: NSApplication.didResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(applicationDidBecomeActive(_:)),
                           name: NSApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(windowFullScreenDidChange(_:)),
                           name: NSWindow.didEnterFullScreenNotification, object: nil)
        center.addObserver(self, selector: #selector(windowFullScreenDidChange(_:)),
                           name: NSWindow.didExitFullScreenNotification, object: nil)
        observesApplicationLifecycle = true
    }

    private func stopObservingApplicationLifecycle() {
        guard observesApplicationLifecycle else { return }
        let center = NotificationCenter.default
        center.removeObserver(self, name: NSApplication.didResignActiveNotification, object: nil)
        center.removeObserver(self, name: NSApplication.didBecomeActiveNotification, object: nil)
        center.removeObserver(self, name: NSWindow.didEnterFullScreenNotification, object: nil)
        center.removeObserver(self, name: NSWindow.didExitFullScreenNotification, object: nil)
        observesApplicationLifecycle = false
    }

    @objc private func applicationDidResignActive(_ notification: Notification) {
        suspendPresentation()
    }

    @objc private func applicationDidBecomeActive(_ notification: Notification) {
        guard window != nil else { return }
        resumePresentation()
    }

    @objc private func windowFullScreenDidChange(_ notification: Notification) {
        guard let changedWindow = notification.object as? NSWindow,
              changedWindow === window else { return }
        updateCursorVisibility()
    }

    private func updateCursorVisibility() {
        let shouldHide = hidesCursorInFullScreen && mouseIsInside
            && NSApplication.shared.isActive
            && window?.styleMask.contains(.fullScreen) == true
        if shouldHide, !cursorIsHidden {
            NSCursor.hide()
            cursorIsHidden = true
        } else if !shouldHide {
            showCursorIfNeeded()
        }
    }

    private func showCursorIfNeeded() {
        guard cursorIsHidden else { return }
        NSCursor.unhide()
        cursorIsHidden = false
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
    let targetFrameRate: Int
    let hidesCursorInFullScreen: Bool

    func makeNSView(context: Context) -> NSView {
        let view = MetalHostView()
        view.wantsLayer = true
        view.onFrame = onFrame
        view.hidesCursorInFullScreen = hidesCursorInFullScreen
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? MetalHostView)?.onFrame = onFrame
        (view as? MetalHostView)?.hidesCursorInFullScreen = hidesCursorInFullScreen
    }
}

#endif
