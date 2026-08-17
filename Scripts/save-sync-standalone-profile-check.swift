import Foundation

@main
private struct SaveSyncStandaloneProfileCheck {
    static func main() {
        let profile = SaveSyncProfile.jak2()
        guard profile.format == .jak2,
              profile.localSavesDirectory.path.hasSuffix("OpenGOAL/jak2/saves"),
              profile.localConflictsDirectory.path.hasSuffix("GOALPad/Jak2/SaveConflicts"),
              profile.stateFile.path.hasSuffix("GOALPad/Jak2/SaveSync/state-v1.json"),
              profile.supportsSaveTransfer,
              !profile.supportsManagedSaveSync,
              !profile.coordinateCloudAccess,
              profile.cloudLocations() == nil,
              profile.managedSaveSyncUnavailableMessage.contains("no iCloud save entitlement"),
              profile.managedSaveSyncUnavailableMessage.contains("Export saves through Files")
        else {
            print("standalone Jak II save profile check failed")
            Foundation.exit(1)
        }

        let sectionVisibility = SaveSettingsSectionVisibility(
            supportsManagedSaveSync: profile.supportsManagedSaveSync,
            supportsSaveTransfer: profile.supportsSaveTransfer)
        guard !sectionVisibility.showsICloudSection,
              sectionVisibility.showsSaveTransferSection
        else {
            print("standalone Jak II save settings visibility check failed")
            Foundation.exit(1)
        }

        let sourceRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let controllerURL = sourceRoot.appending(
            path: "GOALPad/Saves/SaveSyncController.swift", directoryHint: .notDirectory)
        guard let controllerSource = try? String(contentsOf: controllerURL, encoding: .utf8),
              !controllerSource.contains("#if !GOALPAD_JAK2"),
              controllerSource.contains("if sectionVisibility.showsICloudSection {\n"
                  + "                Section(\"iCloud\") {"),
              controllerSource.contains("if sectionVisibility.showsSaveTransferSection {"),
              controllerSource.contains("Label(\"Import Saves\""),
              controllerSource.contains("Label(\"Export Saves\""),
              controllerSource.contains("Text(sync.managedSaveSyncUnavailableMessage)")
        else {
            print("standalone Jak II save settings source seam check failed")
            Foundation.exit(1)
        }

        print("standalone Jak II save profile checks passed")
    }
}
