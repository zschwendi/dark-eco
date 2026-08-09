import Foundation

@MainActor private var failures = 0

@MainActor private func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  ok   \(message)")
    } else {
        print("  FAIL \(message)")
        failures += 1
    }
}

@main
private struct GameDataProfileSelectionCheck {
    @MainActor static func main() {
        #if GOALPAD_JAK2
        let expected = GameDataProfile.jak2
        #else
        let expected = GameDataProfile.jak1
        #endif

        check(GameDataProfile.active == expected,
              "the compilation condition selects exactly one data profile")
        check(GameDataLayout.gameDirectoryName == expected.gameDirectoryName,
              "the default layout follows the selected profile")
        check(GameDataInspector.inspect(
            gameDirectory: URL(fileURLWithPath: "/missing", isDirectory: true)
        ).profile == expected,
              "the default inspector follows the selected profile")
        check(GameDataProfile.jak1.projectResourceName == "OpenGOALProjectResources",
              "Jak 1 selects the exact OpenGOAL project-resource bundle")
        check(GameDataProfile.jak1.sourceObjectPackName == "Jak1SourceObjectPack",
              "Jak 1 selects the exact source-object pack bundle")
        check(GameDataProfile.jak2.projectResourceName == "Jak2ProjectResources",
              "Jak II selects its isolated project-resource bundle")
        check(GameDataProfile.jak2.sourceObjectPackName == "Jak2SourceObjectPack",
              "Jak II selects its isolated source-object pack bundle")
        let nonActiveProfile: GameDataProfile = expected == .jak1 ? .jak2 : .jak1
        check(nonActiveProfile.projectResourceName != expected.projectResourceName
              && nonActiveProfile.sourceObjectPackName != expected.sourceObjectPackName,
              "an explicit non-active profile does not reuse active resource names")

        let applicationSupport = URL(fileURLWithPath: "/app/Library/Application Support",
                                     isDirectory: true)
        check(SaveDataLayout.localSavesDirectory(
            for: .jak1, in: applicationSupport
        ).path == "/app/Library/Application Support/OpenGOAL/jak1/saves",
              "the Jak 1 native save directory remains exact")
        check(SaveDataLayout.localSavesDirectory(
            for: .jak2, in: applicationSupport
        ).path == "/app/Library/Application Support/OpenGOAL/jak2/saves",
              "Jak II uses its own OpenGOAL native save namespace")
        check(SaveDataLayout.localConflictsDirectory(
            for: .jak1, in: applicationSupport
        ).path == "/app/Library/Application Support/GOALPad/SaveConflicts",
              "the Jak 1 local conflict archive remains exact")
        check(SaveDataLayout.stateFile(
            for: .jak1, in: applicationSupport
        ).path == "/app/Library/Application Support/GOALPad/SaveSync/state-v1.json",
              "the Jak 1 save state path remains exact")
        check(SaveDataLayout.localConflictsDirectory(
            for: .jak2, in: applicationSupport
        ).path == "/app/Library/Application Support/GOALPad/Jak2/SaveConflicts",
              "Jak II conflict recovery cannot enter the Jak 1 archive")
        check(SaveDataLayout.stateFile(
            for: .jak2, in: applicationSupport
        ).path == "/app/Library/Application Support/GOALPad/Jak2/SaveSync/state-v1.json",
              "Jak II save state cannot reuse Jak 1 sync state")

        let activeTitle: GameLibraryTitle = expected.identifier == .jak1 ? .jak1 : .jak2

        if expected == .jak2 {
            check(expected.preparedFolderName == "out/jak2",
                  "the Jak II shell accepts the OpenGOAL prepared root")
            check(expected.supportsRawMediaPreparation && expected.supportsRuntimeLaunch,
                  "the Jak II shell enables its selected raw-media composer and native launch")
            check(!expected.supportsManagedSaveSync,
                  "the Jak II shell keeps Jak 1 cloud merge unavailable")
            check(GameLibraryCardAction.resolve(
                title: activeTitle,
                state: .experimentalReady,
                activeTitle: activeTitle,
                supportsRuntimeLaunch: expected.supportsRuntimeLaunch
            ) == .start,
                  "the Jak II library routes launch-contract-ready data into the native runtime")
            let offer = GameLibraryOfferCopy.importMessage(
                for: activeTitle,
                canImportRawISO: true
            )
            check(offer.contains("out/jak2") && offer.contains("title/gameplay launch contract")
                  && offer.contains("Experimental native launch")
                  && offer.contains("supported .iso") && offer.contains("exactly one .iso"),
                  "the Jak II library offer names raw preparation and labels launch experimental")
        } else {
            check(expected.preparedFolderName == "out/jak1",
                  "the public build retains the Jak 1 prepared root")
            check(expected.supportsRawMediaPreparation && expected.supportsRuntimeLaunch,
                  "the public build retains Jak 1 capabilities")
            check(expected.supportsManagedSaveSync,
                  "the public build retains Jak 1 save synchronization")
            check(GameLibraryCardAction.resolve(
                title: activeTitle,
                state: .ready,
                activeTitle: activeTitle,
                supportsRuntimeLaunch: expected.supportsRuntimeLaunch
            ) == .start,
                  "the public library retains Jak 1 launch behavior")
        }

        if failures == 0 {
            print("game data profile selection checks passed")
        } else {
            print("game data profile selection checks failed: \(failures)")
            Foundation.exit(1)
        }
    }
}
