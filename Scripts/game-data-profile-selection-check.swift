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
            check(!expected.supportsRawMediaPreparation && expected.supportsRuntimeLaunch,
                  "the Jak II shell enables native launch without claiming a raw-media composer")
            check(!expected.supportsManagedSaveSync,
                  "the Jak II shell keeps Jak 1 cloud merge unavailable")
            check(GameLibraryCardAction.resolve(
                title: activeTitle,
                state: .bootstrapReady,
                activeTitle: activeTitle,
                supportsRuntimeLaunch: expected.supportsRuntimeLaunch
            ) == .start,
                  "the Jak II library routes bootstrap-ready data into the native runtime")
            let offer = GameLibraryOfferCopy.importMessage(
                for: activeTitle,
                canImportRawISO: true
            )
            check(offer.contains("out/jak2") && offer.contains("bootstrap")
                  && offer.contains("Experimental native launch")
                  && offer.contains("raw ISO/ZIP preparation remains unavailable"),
                  "the Jak II library offer stays prepared-only and labels launch experimental")
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
