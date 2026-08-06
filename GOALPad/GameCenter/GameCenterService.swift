//
//  GameCenterService.swift
//  GOALPad
//

import Combine
import GameKit
import SwiftUI

#if os(macOS)
import AppKit
private typealias GameCenterPlatformViewController = NSViewController
#elseif os(iOS) || os(visionOS)
import UIKit
private typealias GameCenterPlatformViewController = UIViewController
#endif

@MainActor
final class GameCenterService: ObservableObject {
    @Published private(set) var state = GameCenterAuthenticationState.idle
    @Published fileprivate var authenticationRequest: GameCenterAuthenticationRequest?

    private var hasStarted = false
    private var accessPointContext = GameCenterAccessPointContext.unknown

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        let accessPoint = GKAccessPoint.shared
        accessPoint.location = .topLeading
        state = .authenticating
        updateAccessPoint()

        GKLocalPlayer.local.authenticateHandler = { [weak self] controller, error in
            self?.authenticationDidChange(controller: controller, error: error)
        }
    }

    func setGameplayActive(_ isGameplayActive: Bool) {
        accessPointContext = isGameplayActive ? .gameplay : .launcher
        updateAccessPoint()
    }

    private func authenticationDidChange(
        controller: GameCenterPlatformViewController?,
        error: Error?
    ) {
        guard let controller else {
            let localPlayer = GKLocalPlayer.local
            authenticationRequest = nil
            state = .resolved(
                isAuthenticated: localPlayer.isAuthenticated,
                playerName: localPlayer.isAuthenticated ? localPlayer.displayName : nil,
                errorDescription: error?.localizedDescription
            )
            updateAccessPoint()
            return
        }

        state = .authenticating
        authenticationRequest = GameCenterAuthenticationRequest(controller: controller)
        updateAccessPoint()
    }

    private func updateAccessPoint() {
        GKAccessPoint.shared.isActive = state.enablesAccessPoint(in: accessPointContext)
    }
}

struct GameCenterRootView<Content: View>: View {
    @StateObject private var gameCenter = GameCenterService()
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .environmentObject(gameCenter)
            .onAppear {
                gameCenter.start()
            }
            .sheet(item: $gameCenter.authenticationRequest) { request in
                GameCenterAuthenticationControllerView(controller: request.controller)
                    .interactiveDismissDisabled()
            }
    }
}

private struct GameCenterAuthenticationRequest: Identifiable {
    let id: ObjectIdentifier
    let controller: GameCenterPlatformViewController

    init(controller: GameCenterPlatformViewController) {
        id = ObjectIdentifier(controller)
        self.controller = controller
    }
}

#if os(macOS)
private struct GameCenterAuthenticationControllerView: NSViewControllerRepresentable {
    let controller: NSViewController

    func makeNSViewController(context: Context) -> NSViewController {
        controller
    }

    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}
}
#elseif os(iOS) || os(visionOS)
private struct GameCenterAuthenticationControllerView: UIViewControllerRepresentable {
    let controller: UIViewController

    func makeUIViewController(context: Context) -> UIViewController {
        controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
#endif
