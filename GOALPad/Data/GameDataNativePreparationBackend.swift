import Foundation

nonisolated struct GameDataNativePreparationResources: Equatable, Sendable {
    let projectResourceURL: URL
    let sourceObjectPackURL: URL
}

nonisolated enum GameDataNativePreparationPhase: Int, Sendable {
    case validatingSourcePack = 1
    case extractingISO = 2
    case catalogingRetail = 3
    case generatingData = 4
    case preparingFR3 = 5
    case generatingRecipe = 6
    case materializingOutput = 7
    case finalizingCandidate = 8
    case validatingProjectResources = 9
}

nonisolated struct GameDataNativePreparationProgress: Sendable {
    let phase: GameDataNativePreparationPhase
    let completed: UInt64
    let total: UInt64
    let bytesCompleted: UInt64
    let phaseLabel: String
    let currentItem: String
}

nonisolated struct GameDataNativePreparationFailure: Error, Sendable {
    let domain: String
    let code: Int
    let message: String
}

/// One native composer implementation bound to exactly one game profile.
///
/// Keeping the supported profile beside the operation prevents a linked Jak 1 composer from being
/// reused for Jak II merely because both titles' resource folders happen to exist in the app.
nonisolated struct GameDataNativePreparationBackend: Sendable {
    typealias ProgressHandler = @Sendable (GameDataNativePreparationProgress) async -> Void
    typealias Preparation = @Sendable (
        URL,
        URL,
        GameDataNativePreparationResources,
        @escaping ProgressHandler
    ) async throws -> Int

    let profileIdentifier: GameDataProfile.Identifier
    private let availability: @Sendable () -> Bool
    private let preparation: Preparation

    init(
        profileIdentifier: GameDataProfile.Identifier,
        isAvailable: @escaping @Sendable () -> Bool,
        prepare: @escaping Preparation
    ) {
        self.profileIdentifier = profileIdentifier
        availability = isAvailable
        preparation = prepare
    }

    func isAvailable(for profile: GameDataProfile) -> Bool {
        profile.identifier == profileIdentifier && availability()
    }

    func prepare(
        for profile: GameDataProfile,
        sourceURL: URL,
        candidateURL: URL,
        resources: GameDataNativePreparationResources,
        report: @escaping ProgressHandler
    ) async throws -> Int {
        guard isAvailable(for: profile) else {
            throw GameDataNativePreparationFailure(
                domain: "com.zephyrstudiosllc.eco.GameDataPreparationRouting",
                code: 1,
                message: "No matching native preparation backend is available for \(profile.displayName)."
            )
        }
        return try await preparation(sourceURL, candidateURL, resources, report)
    }
}
