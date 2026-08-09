import Foundation

/// Keeps native gameplay saves in OpenGOAL's per-game desktop layout. Save-sync bookkeeping stays
/// outside that directory and in its own game namespace so it can never be consumed as a memcard.
nonisolated enum SaveDataLayout {
    static var applicationSupportDirectory: URL {
        (try? FileManager.default.url(for: .applicationSupportDirectory,
                                      in: .userDomainMask, appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appending(path: "Library/Application Support", directoryHint: .isDirectory)
    }

    static var localSavesDirectory: URL {
        localSavesDirectory(for: .active, in: applicationSupportDirectory)
    }

    static var localConflictsDirectory: URL {
        localConflictsDirectory(for: .active, in: applicationSupportDirectory)
    }

    static var stateFile: URL {
        stateFile(for: .active, in: applicationSupportDirectory)
    }

    static func localSavesDirectory(
        for profile: GameDataProfile,
        in applicationSupportDirectory: URL
    ) -> URL {
        applicationSupportDirectory.appending(
            path: "OpenGOAL/\(profile.identifier.rawValue)/saves",
            directoryHint: .isDirectory
        )
    }

    static func localConflictsDirectory(
        for profile: GameDataProfile,
        in applicationSupportDirectory: URL
    ) -> URL {
        applicationSupportDirectory.appending(
            path: profile.identifier == .jak1
                ? "GOALPad/SaveConflicts"
                : "GOALPad/Jak2/SaveConflicts",
            directoryHint: .isDirectory
        )
    }

    static func stateFile(
        for profile: GameDataProfile,
        in applicationSupportDirectory: URL
    ) -> URL {
        applicationSupportDirectory.appending(
            path: profile.identifier == .jak1
                ? "GOALPad/SaveSync/state-v1.json"
                : "GOALPad/Jak2/SaveSync/state-v1.json",
            directoryHint: .notDirectory
        )
    }

    static func cloudLocations(for profile: GameDataProfile = .active) -> CloudSaveLocations? {
        guard profile.supportsManagedSaveSync else { return nil }
        let manager = FileManager.default
        guard let identityToken = manager.ubiquityIdentityToken,
              let accountIdentifier = try? NSKeyedArchiver.archivedData(
                  withRootObject: identityToken, requiringSecureCoding: false),
              let container = manager.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        let documents = container.appending(path: "Documents", directoryHint: .isDirectory)
        return CloudSaveLocations(
            savesRoot: documents.appending(path: "OpenGOAL/jak1/saves",
                                            directoryHint: .isDirectory),
            conflictsRoot: documents.appending(path: "GOALPad/SaveConflicts",
                                                directoryHint: .isDirectory),
            accountIdentifier: accountIdentifier)
    }
}
