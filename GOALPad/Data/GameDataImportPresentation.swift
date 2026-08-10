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

    static func backgroundGuidance(phaseLabel: String, isActivating: Bool) -> String {
        if isActivating {
            return "Keep Eco open and in the foreground. Final activation cannot be cancelled."
        }
        return "Keep Eco open and in the foreground. The screen stays awake during \(phaseLabel); "
            + "backgrounding cancels the import safely."
    }

    static func cancellationGuidance(isActivating: Bool) -> String {
        isActivating
            ? "Final activation is in progress and can no longer be cancelled."
            : "You can cancel now. Your active game data will not be replaced."
    }

    static func workDetail(
        filesCopied: Int,
        filesTotal: Int,
        bytesProcessed: Int64,
        currentFile: String
    ) -> String? {
        guard filesTotal > 0 else { return nil }
        var detail = "\(filesCopied) of \(filesTotal)"
        if bytesProcessed > 0 {
            detail += " · " + ByteCountFormatter.string(
                fromByteCount: bytesProcessed,
                countStyle: .file
            ) + " processed"
        }
        if !currentFile.isEmpty {
            detail += " · \(currentFile)"
        }
        return detail
    }

    static let cancelledRecovery = "Import cancelled after native cleanup. Your active game data was not replaced. Choose a source again to restart."
}
