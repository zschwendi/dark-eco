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

    static let localFolderActionTitle = "Use a file in the Dark Eco folder…"

    static let localFolderDialogTitle = "Choose a file in the Dark Eco folder"

    static let localFolderLocation = "Files › Browse › On My iPhone (or On My iPad) › Dark Eco"

    static let localFolderEmptyGuidance = "No ISO, ZIP, or 7z was found directly in the Dark Eco folder. "
        + "Copy the file to \(localFolderLocation), not inside a subfolder, then try again."

    static let localFolderTooManyItemsGuidance = "The Dark Eco folder has too many items to list. "
        + "Move unused source files to another folder, then try again, or use Choose game data…. "
        + "Keep your installed game data and save folders."

    static let localFolderUnreadableGuidance = "Dark Eco could not read its folder. "
        + "Try again, or use Choose game data… instead."

    static let localFolderChangedGuidance = "That file is no longer in the Dark Eco folder or was replaced. "
        + "Check the folder and try again."

    static let pickerTapGuidance = "If a file in the picker doesn't respond, try tapping its icon or "
        + "switching to List view. Or copy the file to \(localFolderLocation) and use the option above. "
        + "That copy uses extra storage until you delete it."
}
