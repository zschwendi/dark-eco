import Foundation

/// Player-facing import wording derived only from the importer capabilities and published phases.
nonisolated enum GameDataImportPresentation {
    static func acceptedSources(rawISOAvailable: Bool) -> String {
        if rawISOAvailable {
            return "Prepared OpenGOAL out/jak1 folder, ISO disc image, or standard ZIP with exactly one ISO"
        }
        return "Prepared OpenGOAL out/jak1 folder"
    }

    static func backgroundGuidance(phaseLabel: String) -> String {
        "Keep Eco open and in the foreground. \(phaseLabel) is not safe to continue while Eco is backgrounded."
    }

    static func cancellationGuidance(isActivating: Bool) -> String {
        isActivating
            ? "Final activation is in progress and can no longer be cancelled."
            : "You can cancel now. Your active game data will not be replaced."
    }

    static let cancelledRecovery = "Import cancelled. Your active game data was not replaced. Choose a source again. If staging had begun, its candidate remains available for recovery."
}
