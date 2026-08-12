import Foundation

/// Player-facing import wording derived only from the importer capabilities and published phases.
nonisolated enum GameDataImportPresentation {
    static func acceptedSources(rawISOAvailable: Bool) -> [String] {
        if rawISOAvailable {
            return [
                "ISO",
                "ZIP with exactly one ISO",
                "Prepared game data folder",
            ]
        }
        return ["Prepared game data folder"]
    }

    static let backgroundGuidance = "Keep Dark Eco open and in the foreground until setup finishes."

    static func cancellationGuidance(isActivating: Bool) -> String {
        isActivating
            ? "Finishing setup cannot be cancelled."
            : "You can cancel. Your current game data will stay unchanged."
    }

    static let cancelledRecovery = "Import cancelled. Your current game data was not replaced. Choose a source and try again."
}
