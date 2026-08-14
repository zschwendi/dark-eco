import CoreGraphics

nonisolated enum VisionWindowGeometry {
    static let fourByThreeAspectRatio: CGFloat = 4.0 / 3.0

    static func fourByThreeSize(containedIn size: CGSize) -> CGSize? {
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return nil }

        if size.width / size.height > fourByThreeAspectRatio {
            return CGSize(width: size.height * fourByThreeAspectRatio,
                          height: size.height)
        }
        return CGSize(width: size.width,
                      height: size.width / fourByThreeAspectRatio)
    }
}

nonisolated struct VisionWindowGeometryState {
    enum Mode: Equatable {
        case freeform
        case fourByThree
    }

    struct Request: Equatable {
        let mode: Mode
        let size: CGSize?
    }

    private(set) var appliedMode: Mode? = .freeform
    private(set) var pendingMode: Mode?
    private(set) var freeformSize: CGSize?

    mutating func request(locksToFourByThree: Bool,
                          currentSize: CGSize) -> Request? {
        let requestedMode: Mode = locksToFourByThree ? .fourByThree : .freeform
        guard pendingMode == nil, appliedMode != requestedMode else { return nil }

        let requestedSize: CGSize?
        if locksToFourByThree {
            guard let size = VisionWindowGeometry.fourByThreeSize(containedIn: currentSize) else {
                return nil
            }
            if appliedMode != .fourByThree {
                freeformSize = currentSize
            }
            requestedSize = size
        } else {
            requestedSize = freeformSize
        }

        pendingMode = requestedMode
        return Request(mode: requestedMode, size: requestedSize)
    }

    mutating func complete(_ request: Request, succeeded: Bool) {
        guard pendingMode == request.mode else { return }
        pendingMode = nil
        if succeeded {
            appliedMode = request.mode
        }
    }
}

#if os(visionOS)
import OSLog
import SwiftUI
import UIKit

struct VisionWindowGeometryView: UIViewRepresentable {
    let locksToFourByThree: Bool

    func makeUIView(context: Context) -> VisionWindowGeometryHostView {
        let view = VisionWindowGeometryHostView()
        view.update(locksToFourByThree: locksToFourByThree)
        return view
    }

    func updateUIView(_ uiView: VisionWindowGeometryHostView, context: Context) {
        uiView.update(locksToFourByThree: locksToFourByThree)
    }
}

@MainActor
final class VisionWindowGeometryHostView: UIView {
    private static let log = Logger(subsystem: "com.goalpad.app",
                                    category: "VisionWindowGeometry")

    private var state = VisionWindowGeometryState()
    private var locksToFourByThree = false

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyPolicyIfPossible()
    }

    func update(locksToFourByThree: Bool) {
        self.locksToFourByThree = locksToFourByThree
        applyPolicyIfPossible()
    }

    private func applyPolicyIfPossible() {
        guard let window, let windowScene = window.windowScene,
              let request = state.request(
                locksToFourByThree: locksToFourByThree,
                currentSize: window.bounds.size
              ) else { return }

        let restrictions: UIWindowScene.ResizingRestrictions = request.mode == .fourByThree
            ? .uniform : .freeform
        let preferences = UIWindowScene.GeometryPreferences.Vision(
            size: request.size,
            resizingRestrictions: restrictions
        )
        windowScene.requestGeometryUpdate(preferences) { [weak self] error in
            guard let self else { return }
            Self.log.error("Could not update the visionOS window geometry: \(error.localizedDescription)")
            self.state.complete(request, succeeded: false)
            self.applyPolicyIfPossible()
        }
        state.complete(request, succeeded: true)
        applyPolicyIfPossible()
    }
}
#endif
