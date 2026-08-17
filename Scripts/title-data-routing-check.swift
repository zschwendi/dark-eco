import Foundation

@MainActor private var failures = 0

@MainActor
private func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  ok   \(message)")
    } else {
        print("  FAIL \(message)")
        failures += 1
    }
}

@main
private struct TitleDataRoutingCheck {
    @MainActor static func main() {
        check(GameDataProfile.profile(for: .jak1) == .jak1,
              "Jak 1 maps to the Jak 1 data profile")
        check(GameDataProfile.profile(for: .jak2) == .jak2,
              "Jak II maps to the Jak II data profile")
        check(GameDataProfile.profile(for: .jak3) == nil,
              "planned Jak 3 has no importable data profile")
        check(GameDataProfile.jak1.title == .jak1 && GameDataProfile.jak2.title == .jak2,
              "profile-to-title routing is symmetric")
        check(GameLibraryCardAction.resolve(title: .jak1, state: .notImported)
                == .verifyData(.jak1)
              && GameLibraryCardAction.resolve(title: .jak2, state: .notImported)
                == .verifyData(.jak2),
              "setup actions retain the clicked supported title")
        check(GameLibraryCardAction.resolve(title: .jak1, state: .ready)
                == .start(.jak1)
              && GameLibraryCardAction.resolve(title: .jak2, state: .ready)
                == .start(.jak2),
              "each imported supported title keeps its own direct-start action")
        check(GameLibraryTitle.jak1.settingsPickerLabel == "Jak 1"
              && GameLibraryTitle.jak2.settingsPickerLabel == "Jak II"
              && GameLibraryTitle.jak3.settingsPickerLabel == "Jak 3",
              "settings uses compact title labels without the Jak 1 shelf title")
        check(GameLibraryCardAction.resolve(title: .jak3, state: .planned)
                == .showUnsupported(.jak3),
              "Jak 3 remains outside setup and import routing")

        if failures == 0 {
            print("title data routing checks passed")
        } else {
            print("title data routing checks failed")
            Foundation.exit(1)
        }
    }
}
