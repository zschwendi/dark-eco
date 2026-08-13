//
//  GOALPadApp.swift
//  GOALPad
//
//  Created by Zach on 7/30/26.
//

import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

enum GOALPadBuildIdentity {
    static let displayName = value(for: "CFBundleDisplayName", fallback: "Dark Eco")
    static let version = value(for: "CFBundleShortVersionString", fallback: "unknown")
    static let build = value(for: "CFBundleVersion", fallback: "unknown")
    static let displayText = "\(displayName) \(version) (\(build))"
    static let versionText = "Version \(version) (\(build))"

    private static func value(for key: String, fallback: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? fallback
    }
}

#if os(iOS)
@MainActor
final class SystemGesturePreference {
    private(set) var isImmersiveGameplay = false
    var didChange: (() -> Void)?

    func setImmersiveGameplay(_ isImmersiveGameplay: Bool) {
        guard self.isImmersiveGameplay != isImmersiveGameplay else { return }
        self.isImmersiveGameplay = isImmersiveGameplay
        didChange?()
    }
}

private struct IOSRootView: View {
    let systemGesturePreference: SystemGesturePreference

    var body: some View {
        ContentView(systemGesturePreference: systemGesturePreference)
            .task { await EcoTipTransactionObserver.run() }
    }
}

private final class GameplayHostingController: UIHostingController<IOSRootView> {
    private let systemGesturePreference: SystemGesturePreference

    init() {
        let systemGesturePreference = SystemGesturePreference()
        self.systemGesturePreference = systemGesturePreference
        super.init(rootView: IOSRootView(systemGesturePreference: systemGesturePreference))
        systemGesturePreference.didChange = { [weak self] in
            self?.setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
            self?.setNeedsUpdateOfHomeIndicatorAutoHidden()
        }
    }

    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        systemGesturePreference.isImmersiveGameplay ? .bottom : []
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        systemGesturePreference.isImmersiveGameplay
    }
}

final class GOALPadSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = GameplayHostingController()
        self.window = window
        window.makeKeyAndVisible()
    }
}

@main
final class GOALPadApp: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = GOALPadSceneDelegate.self
        return configuration
    }
}
#else
@main
struct GOALPadApp: App {
    #if os(visionOS) && GOALPAD_EXPERIMENTAL_VISION_STEREO
    @State private var visionPresentation = VisionPresentationCoordinator(graphicsProfile: .modern)
    #endif

    var body: some Scene {
        WindowGroup {
            #if os(visionOS) && GOALPAD_EXPERIMENTAL_VISION_STEREO
            ContentView()
                .environment(visionPresentation)
                .task { await EcoTipTransactionObserver.run() }
            #else
            ContentView()
                .task { await EcoTipTransactionObserver.run() }
            #endif
        }
    }
}
#endif
