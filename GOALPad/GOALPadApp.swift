//
//  GOALPadApp.swift
//  GOALPad
//
//  Created by Zach on 7/30/26.
//

import Foundation
import SwiftUI

enum GOALPadBuildIdentity {
    static let displayName = value(for: "CFBundleDisplayName", fallback: "Eco Pro")
    static let version = value(for: "CFBundleShortVersionString", fallback: "unknown")
    static let build = value(for: "CFBundleVersion", fallback: "unknown")
    static let displayText = "\(displayName) \(version) (\(build))"

    private static func value(for key: String, fallback: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? fallback
    }
}

@main
struct GOALPadApp: App {
    var body: some Scene {
        WindowGroup {
            GameCenterRootView {
                ContentView()
            }
        }
    }
}
