import SwiftUI

nonisolated enum SettingsProfile: Equatable, Sendable {
    case modern
    case classic
}

struct ContentView: View {
    var body: some View {
        EmptyView()
    }
}

nonisolated enum EcoTipTransactionObserver {
    static func run() async {}
}
