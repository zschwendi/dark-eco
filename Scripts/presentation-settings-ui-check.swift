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
check(view.contains("settings.globalProfile?.title ?? \"Mixed\""),
      "a mixed set of section profiles is shown as Mixed, not as a preset")
check(view.contains("settings.profile(for: .graphics) == .modern")
        && view.contains("Fill Width (Hor+)"),
      "Fill Width is visible only for Modern graphics")
check(store.contains("var graphicsModernFillWidthOverride: Bool?")
        && store.contains("return graphicsModernFillWidthOverride ?? true"),
      "Modern Fill Width defaults on while preserving a user override")
check(!store.contains("SaveSyncEngine") && !store.contains("TouchControls"),
      "presentation settings remain separate from save and touch behavior")
check(content.contains("session.presentationSettings.graphicsFillWidth")
        && content.contains("session.settings.horizontalPlusEnabled = enabled")
        && renderer.contains("surface.setHorizontalPlusEnabled(horizontalPlusEnabled)"),
      "the effective Graphics setting reaches only the opt-in Hor+ renderer seam")
check(occursInOrder([
    "let presentationSettings = PresentationSettings()",
    "await presentationSettings.prepare()",
    "await saveSync.prepare()",
], in: session), "settings preparation is independent of the existing save preparation")

if failures == 0 {
    print("presentation settings UI checks passed")
} else {
    print("presentation settings UI checks failed: \(failures)")
    Foundation.exit(1)
}
