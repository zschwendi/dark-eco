import Foundation

nonisolated extension GameDataProfile {
    static var initialProfile: GameDataProfile {
        #if GOALPAD_JAK2
        .jak2
        #else
        .jak1
        #endif
    }

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
