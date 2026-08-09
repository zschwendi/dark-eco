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

        let activeTitle: GameLibraryTitle = expected.identifier == .jak1 ? .jak1 : .jak2

        if expected == .jak2 {
            check(expected.preparedFolderName == "out/jak2",
                  "the Jak II shell accepts the OpenGOAL prepared root")
            check(!expected.supportsRawMediaPreparation && !expected.supportsRuntimeLaunch,
                  "the Jak II shell keeps raw media and gameplay unavailable")
            check(GameLibraryCardAction.resolve(
                title: activeTitle,
                state: .bootstrapReady,
                activeTitle: activeTitle,
                supportsRuntimeLaunch: expected.supportsRuntimeLaunch
            ) == .openSetup,
                  "the Jak II library opens setup rather than gameplay")
            let offer = GameLibraryOfferCopy.importMessage(
                for: activeTitle,
                canImportRawISO: true
            )
            check(offer.contains("out/jak2") && offer.contains("bootstrap")
                  && offer.contains("raw ISO/ZIP preparation are unavailable"),
                  "the Jak II library offer stays prepared-only")
        } else {
            check(expected.preparedFolderName == "out/jak1",
                  "the public build retains the Jak 1 prepared root")
            check(expected.supportsRawMediaPreparation && expected.supportsRuntimeLaunch,
                  "the public build retains Jak 1 capabilities")
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
