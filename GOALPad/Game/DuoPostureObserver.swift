#if os(iOS)
import SwiftUI
import UIKit

/// Reports whether the hosting window scene is in the user-defined laptop posture: the hinge is
/// partially open and the interface is portrait (either way up).
///
/// The callback runs on the main actor on a later turn than the change that caused it, reports the
/// first value once, and afterwards only reports changes. Before iOS 27.1, without a hinge, while
/// the scene is not foreground-active, or while detached, the value is always `false`. This says
/// nothing about where the physical fold is; the upper-half layout is a presentation policy.
struct DuoPostureObserver: UIViewRepresentable {
    let onChange: @MainActor (Bool) -> Void

    func makeUIView(context: Context) -> DuoPostureProbeView {
        let view = DuoPostureProbeView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: DuoPostureProbeView, context: Context) {
        uiView.onChange = onChange
    }

    static func dismantleUIView(_ uiView: DuoPostureProbeView, coordinator: ()) {
        uiView.tearDown()
    }
}

final class DuoPostureProbeView: UIView {
    var onChange: (@MainActor (Bool) -> Void)?

    /// Recreated for every attachment and activation so updates queued by a previous one are
    /// rejected by identity.
    private var hingeInteraction: (any UIInteraction)?
    private var isHingePartiallyOpen = false
    private weak var observedScene: UIWindowScene?
    private var lastDelivered: Bool?
    private var isDeliveryScheduled = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        removeHingeInteraction()
        let scene = window?.windowScene
        if scene !== observedScene {
            stopObservingScene()
            if let scene { startObservingScene(scene) }
        }
        reconcileHingeInteraction()
        scheduleDelivery()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scheduleDelivery()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }

    func tearDown() {
        onChange = nil
        stopObservingScene()
        removeHingeInteraction()
    }

    // MARK: Scene lifecycle

    private func startObservingScene(_ scene: UIWindowScene) {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(sceneWillDeactivate(_:)),
                           name: UIScene.willDeactivateNotification, object: scene)
        center.addObserver(self, selector: #selector(sceneDidActivate(_:)),
                           name: UIScene.didActivateNotification, object: scene)
        observedScene = scene
    }

    private func stopObservingScene() {
        let center = NotificationCenter.default
        center.removeObserver(self, name: UIScene.willDeactivateNotification, object: nil)
        center.removeObserver(self, name: UIScene.didActivateNotification, object: nil)
        observedScene = nil
    }

    @objc private func sceneWillDeactivate(_ notification: Notification) {
        removeHingeInteraction()
        scheduleDelivery()
    }

    @objc private func sceneDidActivate(_ notification: Notification) {
        reconcileHingeInteraction()
        scheduleDelivery()
    }

    // MARK: Hinge

    private var isAttachedAndActive: Bool {
        guard let scene = window?.windowScene, scene === observedScene else { return false }
        return scene.activationState == .foregroundActive
    }

    private func reconcileHingeInteraction() {
        guard isAttachedAndActive else {
            removeHingeInteraction()
            return
        }
        guard hingeInteraction == nil else { return }
        if #available(iOS 27.1, *) {
            let interaction = makeHingeInteraction()
            hingeInteraction = interaction
            addInteraction(interaction)
        }
    }

    private func removeHingeInteraction() {
        if let hingeInteraction {
            removeInteraction(hingeInteraction)
        }
        hingeInteraction = nil
        isHingePartiallyOpen = false
    }

    /// The SDK does not state which thread the handler runs on, so it is nonisolated and hops to
    /// the main actor before reading the update.
    @available(iOS 27.1, *)
    private func makeHingeInteraction() -> UIHingeInteraction {
        UIHingeInteraction { @Sendable [weak self] interaction, update in
            Task { @MainActor [weak self] in
                self?.applyHingeUpdate(update, from: interaction)
            }
        }
    }

    @available(iOS 27.1, *)
    private func applyHingeUpdate(_ update: UIHingeInteraction.Update,
                                  from interaction: UIHingeInteraction) {
        guard let hingeInteraction, hingeInteraction === interaction else { return }
        isHingePartiallyOpen = update.hinge?.status == .partiallyOpen
        scheduleDelivery()
    }

    // MARK: Delivery

    private var currentValue: Bool {
        guard isHingePartiallyOpen, isAttachedAndActive,
              let scene = window?.windowScene else { return false }
        switch scene.effectiveGeometry.interfaceOrientation {
        case .portrait, .portraitUpsideDown:
            return true
        default:
            return false
        }
    }

    /// Coalesces triggers from layout, lifecycle and hinge updates into one read on a later main
    /// actor turn, so the callback never runs inside SwiftUI rendering or UIKit layout.
    private func scheduleDelivery() {
        guard !isDeliveryScheduled else { return }
        isDeliveryScheduled = true
        Task { @MainActor [weak self] in
            self?.deliverIfChanged()
        }
    }

    private func deliverIfChanged() {
        isDeliveryScheduled = false
        guard let onChange else { return }
        let value = currentValue
        guard value != lastDelivered else { return }
        lastDelivered = value
        onChange(value)
    }
}
#endif
