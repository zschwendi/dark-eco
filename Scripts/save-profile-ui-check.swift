import Foundation

private var failures = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("  ok   \(message)")
    } else {
        print("  FAIL \(message)")
        failures += 1
    }
}

private func source(at path: String) -> String {
    do {
        return try String(contentsOfFile: path, encoding: .utf8)
    } catch {
        print("  FAIL could not read \(path): \(error.localizedDescription)")
        Foundation.exit(1)
    }
}

guard CommandLine.arguments.count == 2 else {
    print("usage: swift Scripts/save-profile-ui-check.swift <repository-root>")
    Foundation.exit(2)
}

let root = CommandLine.arguments[1]
let content = source(at: root + "/GOALPad/ContentView.swift")
let controller = source(at: root + "/GOALPad/Saves/SaveSyncController.swift")

check(content.contains("if GameDataProfile.active.supportsManagedSaveSync")
        && content.contains("LabeledContent(\"Jak II Saves\", value: \"Local Only\")"),
      "Jak II displays local-only save status instead of the Jak 1 settings route")
check(content.contains("State(initialValue: GameDataProfile.active.supportsManagedSaveSync")
        && content.contains("? initialPath")
        && content.contains(": [])"),
      "a direct settings entry cannot preload the Jak 1 save screen for Jak II")
check(controller.contains("guard supportsManagedSaveSync else { return true }")
        && controller.contains("guard supportsManagedSaveSync, isEnabled else { return }"),
      "Jak II lifecycle calls bypass the Jak 1 recovery and cloud merge engine")

if failures == 0 {
    print("save profile UI checks passed")
} else {
    print("save profile UI checks failed: \(failures)")
    Foundation.exit(1)
}
