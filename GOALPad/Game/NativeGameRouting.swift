import Foundation

nonisolated extension GameDataProfile.Identifier {
    var nativeGameIdentifier: GOALPadGameIdentifier {
        switch self {
        case .jak1: .jak1
        case .jak2: .jak2
        }
    }
}
