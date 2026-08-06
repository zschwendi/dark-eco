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
let touchEditor = source(at: root + "/GOALPad/Game/TouchLayoutEditorView.swift")
let touchRuntime = source(at: root + "/GOALPad/Game/TouchControls.swift")

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
check(view.contains("ordinary four Jak save slots")
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
        && view.contains("settings.restoreDefaults(for: section)")
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
        && view.contains("TouchLayoutEditorView(settings: settings)")
        && view.contains("LabeledContent(\"Touch Layout\"")
        && view.contains("settings.jak1TouchLayout.isDefault"),
      "Controls exposes the title-scoped touch editor and every persisted customization seam")
check(touchEditor.contains("Picker(\"Layout\"")
        && touchEditor.contains("Section(\"Preview\")")
        && touchEditor.contains("DragGesture(minimumDistance: 1")
        && touchEditor.contains("TouchLayoutGeometry.normalizedPosition")
        && touchEditor.contains("Picker(\"Action\"")
        && touchEditor.contains("TouchGestureDirection.remappableCases")
        && touchEditor.contains("Swipe \\(direction.title)")
        && touchEditor.contains("LabeledContent(\"Swipe Down\", value: \"Crouch (Fixed)\")")
        && touchEditor.contains("LabeledContent(\"Opacity\"")
        && touchEditor.contains("LabeledContent(\"Size\"")
        && touchEditor.contains("Button(\"Reset Layout\", role: .destructive)")
        && touchEditor.contains("Button(\"Reset \\(selectedControl.title)\"")
        && touchEditor.contains("Classic intentionally exposes no separate")
        && touchEditor.contains("L2 or R2 control"),
      "the editor directly manipulates every active profile control and offers safe resets")
check(touchEditor.contains(".accessibilityLabel(control.title)")
        && touchEditor.contains(".accessibilityValue(accessibilityValue(for: control))")
        && touchEditor.contains(".accessibilityHint(\"Drag to reposition")
        && touchEditor.contains(".accessibilityAction(named: \"Move Left\"")
        && touchEditor.contains(".accessibilityAction(named: \"Move Right\"")
        && touchEditor.contains(".accessibilityAction(named: \"Move Up\"")
        && touchEditor.contains(".accessibilityAction(named: \"Move Down\"")
        && touchEditor.contains(".accessibilityAction(named: \"Use Default Position\"")
        && touchEditor.contains(".frame(width: hitFrame.width, height: hitFrame.height)"),
      "preview controls retain 44-point interaction frames and VoiceOver movement actions")
check(touchLayout.contains("static let minimumHitDimension: CGFloat = 44")
        && touchLayout.contains("struct NormalizedTouchPosition: Codable")
        && touchLayout.contains("static func normalizedPosition")
        && touchLayout.contains("static let remappableCases: [Self] = [.up, .left, .right]")
        && touchLayout.contains("return down == .crouch")
        && touchLayout.contains("case classicLeftShoulder")
        && touchLayout.contains("case classicRightShoulder")
        && !touchLayout.contains("case classicL2")
        && !touchLayout.contains("case classicR2"),
      "the pure model uses normalized safe geometry without representable dead Classic triggers")
check(content.contains("session.presentationSettings.jak1TouchLayout")
        && content.contains("session.touch.setLayoutCustomization(layout)")
        && touchRuntime.contains("func setLayoutCustomization")
        && touchRuntime.contains("layoutCustomization.gestureAction")
        && touchRuntime.contains("layoutCustomization.action(for: movementControl)"),
      "persisted layout, gesture, and whole-stick remaps reach the live touch runtime")
check(content.contains("session.presentationSettings.jak1InputBindings")
        && content.contains("session.input.setBindings(bindings)")
        && view.contains("settings.setControllerStickRoles(roles)"),
      "synced and in-view stick-role changes reach the live physical-input seam")
check(content.contains("session.isRunning && session.isNativeMenuOpen")
        && content.contains("Text(\"Eco\")")
        && content.contains("Image(systemName: \"gearshape\")")
        && content.contains(".frame(minHeight: 44)")
        && content.contains("session.presentationSettings.developerLogsEnabled")
        && !content.contains("showDiagnostics")
        && !content.contains("line.3.horizontal"),
      "native menu truth gates a 44-point white Eco Settings control and optional logs")
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
check(content.contains("LabeledContent(\"Jak 1 Settings\", value: \"Available\")")
        && content.contains("SettingsTitleStatusRow(title: \"Jak II\")")
        && content.contains("SettingsTitleStatusRow(title: \"Jak 3\")")
        && content.contains("LabeledContent(title, value: \"Planned\")")
        && view.contains(".navigationTitle(\"Jak 1 Settings\")"),
      "only Jak 1 settings are functional and its navigation title is title-scoped")
check(content.contains("if session.isRunning && !isOpen { settingsPresentation = nil }"),
      "leaving the native menu still dismisses an in-game Settings sheet")
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
