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
                == "Prepared OpenGOAL out/jak1 folder",
              "prepared-folder-only builds do not advertise raw media")
        check(GameDataImportPresentation.acceptedSources(rawISOAvailable: true)
                == "Prepared OpenGOAL out/jak1 folder, ISO disc image, or standard ZIP with exactly one ISO",
              "raw-media-capable builds advertise only the ISO and one-ISO ZIP paths")
        check(GameDataImportPresentation.backgroundGuidance(phaseLabel: "Validating candidate")
                == "Keep Eco open and in the foreground. Validating candidate is not safe to continue while Eco is backgrounded.",
              "every active phase names itself and truthfully requires foreground execution")
        check(GameDataImportPresentation.cancellationGuidance(isActivating: false)
                == "You can cancel now. Your active game data will not be replaced.",
              "pre-activation cancellation preserves the active install")
        check(GameDataImportPresentation.cancellationGuidance(isActivating: true)
                == "Final activation is in progress and can no longer be cancelled.",
              "activation does not promise a cancellation that the worker cannot honor")
        check(GameDataImportPresentation.cancelledRecovery.contains("was not replaced")
                && GameDataImportPresentation.cancelledRecovery.contains("candidate remains available for recovery"),
              "cancellation stays visible with bounded recovery guidance")

        if failures == 0 {
            print("game data import presentation checks passed")
        } else {
            print("game data import presentation checks failed")
            Foundation.exit(1)
        }
    }
}
