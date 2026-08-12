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
private struct GameDataImportPresentationCheck {
    @MainActor static func main() {
        check(GameDataImportPresentation.acceptedSources(rawISOAvailable: false)
                == ["Prepared game data folder"],
              "prepared-folder-only builds do not advertise raw media")
        check(GameDataImportPresentation.acceptedSources(rawISOAvailable: true)
                == ["ISO", "ZIP or 7z with exactly one ISO", "Prepared game data folder"],
              "raw-media-capable builds list ISO, one-ISO archives, and prepared data in order")
        check(GameDataImportPresentation.backgroundGuidance
                == "Keep Dark Eco open and in the foreground until setup finishes.",
              "foreground guidance remains concise and safe")
        check(GameDataImportPresentation.completedStorageGuidance
                == "Game data is stored in the Dark Eco folder on this device. Keep that copy. "
                    + "After setup completes, you can delete the original ISO, archive, or prepared folder.",
              "completed setup distinguishes the retained Dark Eco copy from the removable source")
        check(GameDataImportPresentation.cancellationGuidance(isActivating: false)
                == "You can cancel. Your current game data will stay unchanged.",
              "pre-activation cancellation preserves the active install")
        check(GameDataImportPresentation.cancellationGuidance(isActivating: true)
                == "Finishing setup cannot be cancelled.",
              "activation does not promise a cancellation that the worker cannot honor")
        if failures == 0 {
            print("game data import presentation checks passed")
        } else {
            print("game data import presentation checks failed")
            Foundation.exit(1)
        }
    }
}
