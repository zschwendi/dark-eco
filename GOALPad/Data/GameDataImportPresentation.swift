import Foundation

/// Player-facing import wording derived only from the importer capabilities and published phases.
nonisolated enum GameDataImportPresentation {
    static func acceptedSources(
        for profile: GameDataProfile = .active,
        rawISOAvailable: Bool
    ) -> String {
        if rawISOAvailable && profile.supportsRawMediaPreparation {
            let sources = "Prepared OpenGOAL \(profile.preparedFolderName) folder, ISO disc image, "
                + "or ZIP archive with exactly one ISO"
            guard profile.readiness == .experimentalTitleAndGameplay else { return sources }
            return sources + " (\(profile.readinessContractLabel ?? "experimental launch contract"); "
                + "full-game completeness is not verified)"
        }
        if profile.readiness == .experimentalTitleAndGameplay {
            return "Prepared OpenGOAL \(profile.preparedFolderName) folder ("
                + "\(profile.readinessContractLabel ?? "experimental launch contract"); "
                + "full-game completeness is not verified)"
        }
        return "Prepared OpenGOAL \(profile.preparedFolderName) folder"
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
