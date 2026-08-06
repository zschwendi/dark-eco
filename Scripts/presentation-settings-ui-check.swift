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
    "Use Modern Everywhere",
    "Use Classic Everywhere",
    "profileSection(.controls)",
    "profileSection(.graphics)",
    "Section(\"iCloud\")",
    "Toggle(\"Sync Settings\"",
    "Toggle(\"Sync Saves\"",
    "Button(cloudState.actionTitle)",
    "Button(\"Reset Jak 1 Settings\"",
], in: view), "Jak 1 Settings leads with Modern and presents one iCloud block")
check(!view.contains("profileSection(.audio)")
        && !view.contains("profileSection(.interface)")
        && store.contains("var audioProfile: SettingsProfile")
        && store.contains("var interfaceProfile: SettingsProfile"),
      "empty Audio and UI forms are hidden without removing their persisted fields")
check(view.components(separatedBy: ".fileImporter(").count - 1 == 1
        && view.contains("private enum SaveTransferPicker"),
      "one picker routes both save import and export choices")
check(view.components(separatedBy: "Section(\"iCloud\")").count - 1 == 1
        && !view.contains("Section(\"iCloud Settings\")")
        && !view.contains("Section(\"iCloud Saves\")")
        && view.contains("Label(cloudState.summary")
        && view.contains("cloudState.lastSyncDate")
        && view.contains("CloudSyncPresentation.synchronize"),
      "one iCloud status, date, and action coordinate both independent domains")
check(view.contains("if let message = cloudState.progressMessage")
        && view.contains(".disabled(!cloudState.isActionEnabled)"),
      "combined cloud progress disables its single conflicting action")
check(view.contains("ordinary four Jak save slots")
        && !view.contains("resolution.relativePath")
        && !view.contains("Section(\"Automatic Resolution\")")
        && !view.contains("BASCUS-"),
      "save UI describes slots and automatic preservation without internal paths")
check(view.contains("Section(\"Developer\")")
        && view.contains("Toggle(\"Show Developer Logs\"")
        && store.contains("var developerLogsEnabledOverride: Bool?")
        && store.contains("developerLogsEnabledOverride ?? false"),
      "developer logs are an off-by-default setting in the compatible synced document")
check(view.contains("older divergent copies were preserved automatically")
        && !view.contains("switch resolution.basis"),
      "automatic resolution copy remains generic across engine ranking cases")
check(view.contains("settings.globalProfile?.title ?? \"Mixed\""),
      "a mixed set of section profiles is shown as Mixed, not as a preset")
check(view.contains("settings.profile(for: .graphics) == .modern")
        && view.contains("Toggle(\"Fit to Screen\"")
        && !view.contains("Hor+"),
      "Fit to Screen is visible only for Modern graphics without implementation jargon")
check(store.contains("var graphicsModernFillWidthOverride: Bool?")
        && store.contains("var graphicsProfile: SettingsProfile = .modern")
        && store.contains("return graphicsModernFillWidthOverride ?? true"),
      "Graphics and Fill Width default to Modern while preserving a user override")
check(occursInOrder(["case modern", "case classic"], in: store)
        && store.contains("enum SettingsProfile: String, CaseIterable, Codable"),
      "CaseIterable ordering changes without changing string-backed document compatibility")
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
check(content.contains("session.presentationSettings.profile(for: .controls)")
        && content.contains("session.touch.setStyle(profile == .modern ? .modern : .classic)"),
      "the Controls profile selects the matching live touch model")
check(content.contains("session.isRunning && session.isNativeMenuOpen")
        && content.contains("Text(\"Eco\")")
        && content.contains("Image(systemName: \"gearshape\")")
        && content.contains("session.presentationSettings.developerLogsEnabled")
        && !content.contains("showDiagnostics")
        && !content.contains("line.3.horizontal"),
      "native menu truth gates the white Eco Settings control and optional logs")
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
