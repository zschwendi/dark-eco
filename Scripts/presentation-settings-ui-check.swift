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
let touchLayout = source(at: root + "/GOALPad/Game/TouchLayoutSettings.swift")
let touchGuide = source(at: root + "/GOALPad/Game/TouchControlsGuideView.swift")
let touchControlsView = source(at: root + "/GOALPad/Game/TouchControlsView.swift")

check(occursInOrder([
    "if isGameRunning",
    "Label(\"Return to Library\"",
    "controlsSection",
], in: view)
        && view.contains(".confirmationDialog(\"Return to Library?\"")
        && view.contains("Progress since your last in-game save will be lost."),
      "running-game Settings begins with a confirmed, loss-aware return to the Library")
check(view.contains("Label(\"Touch Controls Guide\", systemImage: \"hand.tap\")")
        && touchGuide.contains("struct TouchControlsGuideSheet")
        && touchGuide.contains("struct TouchControlsGuideView")
        && occursInOrder(["title: \"Move\"", "title: \"Camera\"",
                          "title: \"Zoom and Fire\"", "title: \"Jump or Accelerate\"",
                          "title: \"Punch\"",
                          "title: \"Spin or Interact\"", "title: \"Crouch\"",
                          "title: \"Contextual Actions\""], in: touchGuide),
      "Controls begins with a reusable visual touch guide covering the shipped gesture contract")
check(content.contains("@AppStorage(\"jak1TouchControlsGuideVersion\")")
        && content.contains("readiness == .active, touchControlsGuideVersion < 1")
        && content.contains("isShowingTouchControlsGuide = true")
        && content.contains("touchControlsGuideVersion = 1")
        && content.contains("private func returnToLibrary()")
        && occursInOrder(["settingsPresentation = nil", "launcherDestination = .library",
                          "session.shutdown()"], in: content),
      "the first playable iOS session presents the guide once and confirmed exit tears down into Library")

check(occursInOrder([
    "controlsSection",
    "profileSection(.graphics)",
    "Section(\"iCloud\")",
    "Toggle(\"Sync Settings\"",
    "Toggle(\"Sync Saves\"",
    "Button(cloudState.actionTitle)",
    "Button(\"Reset \\(GameLibraryTitle.jak1.name) Settings\"",
], in: view), "canonical-title Settings presents plain Controls, a Graphics profile, and one iCloud block")
check(view.contains("Section(\"Controls\")")
        && !view.contains("Section(\"Preset\")")
        && !view.contains("Use Modern Everywhere")
        && !view.contains("Use Classic Everywhere")
        && !view.contains("settings.applyPreset")
        && !view.contains("globalProfileTitle")
        && !view.contains("settings.globalProfile")
        && !view.contains("profileSection(.controls)"),
      "Controls has no Classic or global-profile selector")
check(!view.contains("profileSection(.audio)")
        && !view.contains("profileSection(.interface)")
        && store.contains("var audioProfile: SettingsProfile")
        && store.contains("var interfaceProfile: SettingsProfile"),
      "empty Audio and UI forms are hidden without removing their persisted fields")
check(view.components(separatedBy: ".fileImporter(").count - 1 == 1
        && view.contains("private enum SaveTransferPicker")
        && !view.contains("isShowingSavePicker")
        && view.contains("get: { saveTransferPicker != nil }"),
      "one stable picker state routes both save import and export choices")
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
check(view.contains("the four \\(GameLibraryTitle.jak1.name) save slots")
        && !view.contains("resolution.relativePath")
        && !view.contains("Section(\"Automatic Resolution\")")
        && !view.contains("BASCUS-"),
      "save UI describes slots and automatic preservation without internal paths")
check(view.contains("Section(\"Preserved Saves\")")
        && view.contains("Make Save Slot \\(candidate.slotNumber) Active")
        && view.contains("The current active copy will be preserved before replacement.")
        && view.contains("candidate.completionPercentage")
        && view.contains("candidate.saveGeneration")
        && view.contains("candidate.source.rawValue")
        && !view.contains("Text(candidate.id)"),
      "preserved native saves can become active using human metadata without exposing paths")
check(view.contains("Section(\"Developer\")")
        && view.contains("Toggle(\"Show Developer Logs\"")
        && store.contains("var developerLogsEnabledOverride: Bool?")
        && store.contains("developerLogsEnabledOverride ?? false"),
      "developer logs are an off-by-default setting in the compatible synced document")
check(view.contains("older divergent copies were preserved automatically")
        && !view.contains("switch resolution.basis"),
      "automatic resolution copy remains generic across engine ranking cases")
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
check(!content.contains("session.presentationSettings.profile(for: .controls)")
        && !content.contains("session.touch.setStyle(")
        && !content.contains("session.presentationSettings.jak1TouchLayout")
        && !content.contains("session.touch.setLayoutCustomization("),
      "presentation settings no longer drive a Classic touch profile or touch-layout runtime")
check(view.contains("Picker(\"Primary Controller\"")
        && view.contains("settings.primaryInputSource")
        && view.contains("input.availablePrimarySources")
        && view.contains("input.setPrimarySource($0)")
        && view.contains("Not Connected")
        && content.contains("session.presentationSettings.primaryInputSource")
        && content.contains("session.input.setPrimarySource(source)"),
      "Jak 1 Primary Controller shows connected choices and updates live input arbitration")
check(view.contains("ControllerBindingsSettingsView")
        && view.contains("KeyboardMouseBindingsSettingsView")
        && view.contains("Controller Bindings")
        && view.contains("Mouse & Keyboard Bindings")
        && view.contains("No controller connected")
        && view.contains("Keyboard not connected")
        && view.contains("Mouse not connected")
        && view.contains("Bindings remain available and will apply")
        && view.contains("Saved bindings remain available and apply"),
      "physical binding editors report unavailable hardware without hiding saved mappings")
check(view.contains("ForEach(Jak1ControllerControl.allCases")
        && view.contains("Picker(\"Stick Roles\"")
        && view.contains("Jak1ControllerStickRoles.allCases")
        && view.contains("Swapped Sticks exchanges those whole-stick roles")
        && view.contains("ForEach(Jak1ControllerAnalogRole.allCases")
        && view.contains("settings.setControllerSensitivityPercent")
        && view.contains("settings.setControllerDeadZonePercent")
        && view.contains("settings.setControllerInvertHorizontal")
        && view.contains("settings.setControllerInvertVertical")
        && view.contains("Jak1ControllerStickSettings.minimumSensitivityPercent")
        && view.contains("Jak1ControllerStickSettings.maximumDeadZonePercent")
        && view.contains("Stick Sensitivity")
        && view.contains("Stick Additional Dead Zone")
        && view.contains("0% additional dead zone preserve the default")
        && view.contains("without splitting ")
        && view.contains("KeyboardMouseKey.keyboardCases")
        && view.contains("KeyboardMouseKey.mouseCases")
        && view.contains("Text(\"Not Used\").tag(nil as Jak1InputAction?)")
        && view.contains("Choosing an action already in use swaps"),
      "controller and mouse/keyboard editors expose the deterministic swap policy")
check(view.contains("Text(\"Mouse / Trackpad Camera\")")
        && view.contains("LabeledContent(\"Sensitivity\"")
        && view.contains("Slider(value: Binding(")
        && view.contains("Jak1MouseCameraSettings.minimumSensitivityPercent")
        && view.contains("Jak1MouseCameraSettings.maximumSensitivityPercent")
        && view.contains(".accessibilityLabel(\"Camera Sensitivity\")")
        && view.contains("Toggle(\"Invert Horizontal\"")
        && view.contains("Toggle(\"Invert Vertical\"")
        && view.contains("motion remains dedicated to camera control")
        && view.contains("input.setBindings(settings.jak1InputBindings)"),
      "mouse camera sensitivity and independent directions are accessible and apply live")
check(view.contains("Movement defaults to W, A, S, and D")
        && view.contains("Movement directions are ordinary ")
        && view.contains("remappable actions in the same keyboard binding list")
        && !view.contains("KeyboardMovementSettingsView")
        && !view.contains("setKeyboardMovementControl"),
      "WASD movement remains in the single key-to-action binding surface")
check(store.contains("var jak1InputBindingsOverride: Jak1InputBindings?")
        && store.contains("jak1InputBindingsOverride ?? .standard")
        && store.contains("func setControllerAction")
        && store.contains("func setKeyboardMouseAction")
        && store.contains("func setControllerStickRoles")
        && store.contains("func setControllerSensitivityPercent")
        && store.contains("func setControllerDeadZonePercent")
        && store.contains("func setControllerInvertHorizontal")
        && store.contains("func setControllerInvertVertical")
        && store.contains("func setMouseCameraSensitivityPercent")
        && store.contains("func setMouseCameraInvertHorizontal")
        && store.contains("func setMouseCameraInvertVertical")
        && view.contains("settings.restoreDefaults(for: .controls)")
        && view.contains("input.setBindings(settings.jak1InputBindings)"),
      "title-scoped persisted remaps participate in Controls and full-settings resets")
check(store.contains("var jak1TouchLayoutOverride: TouchLayoutCustomization?")
        && store.contains("jak1TouchLayoutOverride ?? .standard")
        && store.contains("func setTouchControlPosition")
        && store.contains("func setTouchControlAction")
        && store.contains("func setTouchGestureAction")
        && store.contains("func setTouchControlOpacityPercent")
        && store.contains("func setTouchControlSizePercent")
        && store.contains("func resetTouchControl")
        && store.contains("func resetTouchLayout")
        && !view.contains("TouchLayoutEditorView")
        && !view.contains("LabeledContent(\"Touch Layout\"")
        && !view.contains("settings.jak1TouchLayout")
        && !FileManager.default.fileExists(atPath: root + "/GOALPad/Game/TouchLayoutEditorView.swift"),
      "legacy touch-layout decoding APIs remain compatible without a player-facing editor")
check(touchLayout.contains("static let minimumHitDimension: CGFloat = 44")
        && touchLayout.contains("struct NormalizedTouchPosition: Codable")
        && touchLayout.contains("static func normalizedPosition")
        && touchLayout.contains("static let remappableCases: [Self] = [.up, .left, .right]")
        && touchLayout.contains("return down == .crouch")
        && touchLayout.contains("case classicLeftShoulder")
        && touchLayout.contains("case classicRightShoulder")
        && !touchLayout.contains("case classicL2")
        && !touchLayout.contains("case classicR2"),
      "structural source check: the model declares safe geometry without dead Classic triggers")
check(content.contains("session.presentationSettings.jak1InputBindings")
        && content.contains("session.input.setBindings(bindings)")
        && view.contains("settings.setControllerStickRoles(roles)"),
      "synced and in-view stick-role changes reach the live physical-input seam")
check(content.contains("if session.isRunning")
        && content.contains("session.isNativeMenuOpen")
        && content.contains("session.presentationSettings.developerLogsEnabled")
        && !content.contains("showDiagnostics")
        && touchControlsView.contains("NativeEcoSettingsPresentation.isVisible")
        && touchControlsView.contains("Button { openSettings() }")
        && touchControlsView.contains("Image(systemName: \"gearshape\")")
        && touchControlsView.contains("Text(\"ECO\")")
        && touchControlsView.contains(".foregroundStyle(.white.opacity(0.8))")
        && touchControlsView.contains(".frame(width: Self.pillWidth, height: 42)"),
      "native menu truth gates the white Eco Settings pill and optional logs")
check(content.contains("@State private var settingsPresentation: SettingsSheetPresentation?")
        && content.contains(".sheet(item: $settingsPresentation)")
        && content.contains(".id(presentation.id)")
        && !content.contains("showSettings"),
      "one item-backed Settings presentation keeps a stable identity while it is open")
check(content.contains("presentSettings(.titles)")
        && content.contains("presentSettings(.jak1)")
        && content.contains("@State private var path: [Destination]")
        && content.contains("initialEntry == .jak1 ? [.jak1] : []")
        && content.contains("NavigationStack(path: $path)"),
      "launcher enters the title list while a paused Jak 1 session opens Jak 1 directly")
check(content.contains("LabeledContent(\"\\(GameLibraryTitle.jak1.name) Settings\", value: \"Available\")")
        && content.contains("SettingsTitleStatusRow(title: \"Jak II\")")
        && content.contains("SettingsTitleStatusRow(title: \"Jak 3\")")
        && content.contains("LabeledContent(title, value: \"Planned\")")
        && view.contains(".navigationTitle(\"\\(GameLibraryTitle.jak1.name) Settings\")"),
      "only the first game's settings are functional and use its canonical title")
check(content.contains("if session.isRunning && !isOpen { settingsPresentation = nil }"),
      "leaving the native menu still dismisses an in-game Settings sheet")
check(content.contains("@Environment(\\.dismiss) private var dismiss")
        && content.contains("ToolbarItem(placement: .confirmationAction)")
        && content.contains("Button(\"Done\") { dismiss() }"),
      "every Settings sheet level retains an explicit app-owned Done exit")
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
