import Foundation

nonisolated extension GameDataProfile {
    static let initialProfile: GameDataProfile = .jak1

    static func profile(for title: GameLibraryTitle) -> GameDataProfile? {
        switch title {
        case .jak1: .jak1
        case .jak2: .jak2
        case .jak3: nil
        }
    }

    var title: GameLibraryTitle {
        switch identifier {
        case .jak1: .jak1
        case .jak2: .jak2
        }
    }
}
