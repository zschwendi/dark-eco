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

private func occursInOrder(_ needles: [String], in source: String) -> Bool {
    var lower = source.startIndex
    for needle in needles {
        guard let match = source.range(of: needle, range: lower..<source.endIndex) else {
            return false
        }
        lower = match.upperBound
    }
    return true
}

guard CommandLine.arguments.count == 2 else {
    print("usage: swift Scripts/presentation-settings-ui-check.swift <repository-root>")
    Foundation.exit(2)
}

let root = CommandLine.arguments[1]
let view = source(at: root + "/GOALPad/Saves/SaveSyncController.swift")
let store = source(at: root + "/GOALPad/Game/PresentationSettings.swift")
let session = source(at: root + "/GOALPad/Game/GameSession.swift")
let content = source(at: root + "/GOALPad/ContentView.swift")
let renderer = source(at: root + "/GOALPad/Game/RenderSettings.swift")

check(occursInOrder([
    "Section(\"Preset\")",
    "Use Classic Everywhere",
    "Use Modern Everywhere",
    "profileSection(.controls)",
    "profileSection(.graphics)",
    "profileSection(.audio)",
    "profileSection(.interface)",
    "Section(\"iCloud Settings\")",
    "Sync settings with iCloud",
    "Section(\"iCloud Saves\")",
    "Button(\"Reset All\"",
], in: view), "Settings presents the global preset, all four sections, independent sync, and Reset All")
check(view.components(separatedBy: ".fileImporter(").count - 1 == 1
        && view.contains("private enum SaveTransferPicker"),
      "one picker routes both save import and export choices")
check(view.contains("Sync Settings Now") && view.contains("Sync Saves Now")
        && view.contains("Retry Settings Sync") && view.contains("Retry Save Sync")
        && !view.contains("Button(\"Sync Now\")"),
      "manual pulls remain available while error states use distinct retry labels")
check(view.contains("ProgressView(\"Syncing settings…\")")
        && view.contains("ProgressView(message)")
        && view.contains(".disabled(sync.isBusy)"),
      "settings and save work expose progress while conflicting controls stay disabled")
check(view.contains("ordinary four Jak save slots")
        && !view.contains("resolution.relativePath")
        && !view.contains("Section(\"Automatic Resolution\")")
        && !view.contains("BASCUS-"),
      "save UI describes slots and automatic preservation without internal paths")
check(view.contains("older divergent copies were preserved automatically")
        && !view.contains("switch resolution.basis"),
      "automatic resolution copy remains generic across engine ranking cases")
check(view.contains("settings.globalProfile?.title ?? \"Mixed\""),
      "a mixed set of section profiles is shown as Mixed, not as a preset")
check(view.contains("settings.profile(for: .graphics) == .modern")
        && view.contains("Fill Width (Hor+)"),
      "Fill Width is visible only for Modern graphics")
check(store.contains("var graphicsModernFillWidthOverride: Bool?")
        && store.contains("var graphicsProfile: SettingsProfile = .modern")
        && store.contains("return graphicsModernFillWidthOverride ?? true"),
      "Graphics and Fill Width default to Modern while preserving a user override")
check(!store.contains("SaveSyncEngine") && !store.contains("TouchControls"),
      "presentation settings remain separate from save and touch behavior")
check(store.contains("actor PresentationSettingsCloudStore")
        && store.contains("try await cloudStore.read()")
        && store.contains("try await cloudStore.write")
        && store.contains("lastSuccessfulSyncDate"),
      "iCloud settings I/O is actor-owned and preserves the latest successful sync date")
check(content.contains("session.presentationSettings.graphicsFillWidth")
        && content.contains("session.settings.horizontalPlusEnabled = enabled")
        && renderer.contains("surface.setHorizontalPlusEnabled(horizontalPlusEnabled)"),
      "the effective Graphics setting reaches only the opt-in Hor+ renderer seam")
check(occursInOrder([
    "let presentationSettings = PresentationSettings()",
    "async let settingsPreparation: Void = presentationSettings.prepare()",
    "await saveSync.prepare()",
    "await settingsPreparation",
], in: session), "settings preparation is independent of the existing save preparation")

if failures == 0 {
    print("presentation settings UI checks passed")
} else {
    print("presentation settings UI checks failed: \(failures)")
    Foundation.exit(1)
}
