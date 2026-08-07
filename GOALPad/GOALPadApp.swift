//
//  GOALPadApp.swift
//  GOALPad
//
//  Created by Zach on 7/30/26.
//

import Foundation
import SwiftUI

enum GOALPadBuildIdentity {
    static let displayName = value(for: "CFBundleDisplayName", fallback: "Eco")
    static let version = value(for: "CFBundleShortVersionString", fallback: "unknown")
    static let build = value(for: "CFBundleVersion", fallback: "unknown")
    static let displayText = "\(displayName) \(version) (\(build))"

    private static func value(for key: String, fallback: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? fallback
    }
}

@main
struct GOALPadApp: App {
    #if os(visionOS)
    @State private var visionPresentation = VisionPresentationCoordinator(graphicsProfile: .modern)
    #endif

    var body: some Scene {
        WindowGroup {
            #if os(visionOS)
            VisionPresentationSessionBridge(coordinator: visionPresentation) {
                GameCenterRootView {
                    ContentView()
                }
            }
            .task { await EcoTipTransactionObserver.run() }
            #if targetEnvironment(simulator)
            .task { await SimulatorPreparedFolderImportSmoke.runIfRequested() }
            #endif
            #else
            GameCenterRootView {
                ContentView()
            }
            .task { await EcoTipTransactionObserver.run() }
            #if targetEnvironment(simulator)
            .task { await SimulatorPreparedFolderImportSmoke.runIfRequested() }
            #endif
            #endif
        }

        #if os(visionOS)
        GOALPadVisionSpatialScenes(coordinator: visionPresentation)
        #endif
    }
}
