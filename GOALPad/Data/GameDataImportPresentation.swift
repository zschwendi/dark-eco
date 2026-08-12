import Foundation

/// Player-facing import wording derived only from the importer capabilities and published phases.
nonisolated enum GameDataImportPresentation {
    static func acceptedSources(rawISOAvailable: Bool) -> [String] {
        if rawISOAvailable {
            return [
                "ISO",
                "ZIP or 7z with exactly one ISO",
                "Prepared game data folder",
            ]
        }
        return ["Prepared game data folder"]
    }

    static let backgroundGuidance = "Keep Dark Eco open and in the foreground until setup finishes."

    static let completedStorageGuidance = "Game data is stored in the Dark Eco folder on this device. "
        + "Keep that copy. After setup completes, you can delete the original ISO, archive, or prepared folder."
}
