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

/// The source between two markers, so a style assertion cannot match an unrelated control.
private func excerpt(from start: String, to end: String, in source: String) -> String {
    guard let lower = source.range(of: start),
          let upper = source.range(of: end, range: lower.upperBound..<source.endIndex) else {
        return ""
    }
    return String(source[lower.lowerBound..<upper.upperBound])
}

guard CommandLine.arguments.count == 2 else {
    print("usage: swift Scripts/presentation-settings-ui-check.swift <repository-root>")
    Foundation.exit(2)
}

let root = CommandLine.arguments[1]
let experimentalStereoGate = "#if os(visionOS) && GOALPAD_EXPERIMENTAL_VISION_STEREO"
let view = source(at: root + "/GOALPad/Saves/SaveSyncController.swift")
let store = source(at: root + "/GOALPad/Game/PresentationSettings.swift")
let session = source(at: root + "/GOALPad/Game/GameSession.swift")
let content = source(at: root + "/GOALPad/ContentView.swift")
let renderer = source(at: root + "/GOALPad/Game/RenderSettings.swift")
let touchLayout = source(at: root + "/GOALPad/Game/TouchLayoutSettings.swift")
let touchGuide = source(at: root + "/GOALPad/Game/TouchControlsGuideView.swift")
let touchSticks = source(at: root + "/GOALPad/Game/TouchStickSettingsView.swift")
let touchControlsView = source(at: root + "/GOALPad/Game/TouchControlsView.swift")

check(occursInOrder([
    "Section(\"Game\")",
    "SettingsGamePicker(selectedTitle: selectedTitle",
    "isGameRunning: isGameRunning",
    "selectTitle: selectSettingsTitle)",
    "if isGameRunning",
    "Label(\"Return to Library\"",
    "DisclosureGroup(isExpanded: expansion(for: .controls))",
], in: view)
        && view.contains(".confirmationDialog(\"Return to Library?\"")
        && view.contains("Progress since your last in-game save will be lost."),
      "the title picker is available before import and precedes a confirmed, loss-aware return")
check(view.contains("private var titleColor: Color")
        && view.contains("#if os(visionOS)\n        return .white.opacity(0.8)")
        && view.contains(".foregroundStyle(titleColor)"),
      "inactive visionOS game choices remain legible")
check(content.contains("ToolbarItem(placement: .topBarTrailing)")
        && content.contains("Image(systemName: \"power\")")
        && content.contains(".foregroundStyle(.red)")
        && content.contains(".accessibilityLabel(\"Return to Library\")")
        && content.contains(".confirmationDialog(\"Return to Library?\""),
      "visionOS Settings exposes the confirmed red top-trailing power action")
check(view.contains("Label(\"Touch Controls Guide\", systemImage: \"hand.tap\")")
        && occursInOrder(["Label(\"Touch Controls Guide\"", "Toggle(\"Rumble\"",
                          "LabeledContent(\"Touch Sticks\""], in: view)
        && view.contains("#if os(iOS)")
        && view.contains("TouchControlsGuideView(gameTitle: selectedTitle == .jak2 ? .jak2 : .jak1)")
        && touchGuide.contains("struct TouchControlsGuideSheet")
        && touchGuide.contains("struct TouchControlsGuideView")
        && touchGuide.contains("if gameTitle == .jak2")
        && occursInOrder(["title: \"Swipe Actions\"", "title: \"Speeder Controls\""],
                         in: touchGuide)
        && touchGuide.contains("Swipe anywhere on the right side\\n- Up: Jump")
        && touchGuide.contains("- Down: Crouch\\n- Left: Punch\\n- Right: Spin Kick")
        && touchGuide.contains(".systemImage(\"hand.draw\")")
        && touchGuide.contains(".systemImage(\"flag.pattern.checkered.2.crossed\")")
        && touchGuide.contains("guideRow(symbol: .text(\"L\"), title: \"Movement\")")
        && touchGuide.contains("guideRow(symbol: .text(\"R\"), title: \"Camera\")")
        && touchGuide.contains("Swipe up and hold to accelerate. Swipe down to hop brake.")
        && touchGuide.contains("title: \"Tap Action\"")
        && touchGuide.contains("title: \"Jetboard & Vehicles\"")
        && touchGuide.contains("title: \"Look Around\"")
        && touchGuide.contains("red up, dark right, yellow down, blue left")
        && touchGuide.contains("title: \"Game Prompts\"")
        && touchGuide.contains("D-pad, Back, Confirm, Settings, and Resume")
        && touchGuide.contains("Dark Eco also supports wireless gamepads for controller input.")
        && touchGuide.contains("Jak II Touch Controls")
        && touchGuide.contains("Jak 1 Touch Controls"),
      "Controls begins with title-aware guides covering both shipped gesture contracts")
check(content.contains("@AppStorage(\"jak1TouchControlsGuideVersion\")")
        && content.contains("@AppStorage(\"jak2TouchControlsGuideVersion\")")
        && content.contains("readiness == .active, selectedTouchControlsGuideVersion < 1")
        && content.contains("session.presentTouchControlsGuide()")
        && content.contains("isShowingTouchControlsGuide = true")
        && content.contains("acknowledgeSelectedTouchControlsGuide()")
        && content.contains("jak2TouchControlsGuideVersion = 1")
        && content.contains("jak1TouchControlsGuideVersion = 1")
        && content.contains("TouchControlsGuideSheet(gameTitle: touchGameTitle)")
        && content.contains("session.dismissTouchControlsGuide()")
        && content.contains("private func returnToLibrary()")
        && occursInOrder(["settingsPresentation = nil", "launcherDestination = .library",
                          "session.shutdown()"], in: content),
      "each title presents its guide once and confirmed exit tears down into Library")

check(occursInOrder([
    "DisclosureGroup(isExpanded: expansion(for: .controls))",
    "DisclosureGroup(isExpanded: expansion(for: .graphics))",
    "Section(\"iCloud\")",
    "Toggle(\"Sync Settings\"",
    "Toggle(\"Sync Saves\"",
    "Button(cloudState.actionTitle)",
    "Button(\"Reset All to Defaults\"",
], in: view), "Jak 1 Settings keeps compact Controls, Graphics, and iCloud categories in one form")
check(view.components(separatedBy: "Toggle(\"Rumble\"").count - 1 == 1
        && !view.contains("Section(\"Gameplay\")")
        && store.contains("case .controls:\n            rumbleEnabledOverride = nil"),
      "Rumble lives inside Controls and the duplicate Gameplay section is gone")
check(view.contains("Label(\"Controls\", systemImage: \"gamecontroller\")")
        && view.contains("DisclosureGroup(isExpanded: expansion(for: .controls))")
        && view.contains("DisclosureGroup(isExpanded: expansion(for: .graphics))")
        && view.contains("DisclosureGroup(isExpanded: expansion(for: .iCloud))")
        && view.contains("DisclosureGroup(isExpanded: expansion(for: .saves))")
        && !view.contains("expansion(for: .developer)")
        && !view.contains("Section(\"Preset\")")
        && !view.contains("Use Modern Everywhere")
        && !view.contains("Use Classic Everywhere")
        && !view.contains("settings.applyPreset")
        && !view.contains("globalProfileTitle")
        && !view.contains("settings.globalProfile")
        && !view.contains("profileSection(.controls)"),
      "the compact categories have no Classic or global-profile selector")
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
        && view.contains("cloudState.settingsLastSyncDate")
        && view.contains("LabeledContent(\"Last settings sync\"")
        && view.contains("cloudState.savesLastSyncDate")
        && view.contains("LabeledContent(\"Last saves sync\"")
        && view.contains("CloudSyncPresentation.synchronize")
        && !view.contains("saves upload only while playing"),
      "one iCloud status and action preserve independent domain dates")
check(view.contains(".navigationTitle(\"\\(selectedTitle.settingsPickerLabel) Settings\")"),
      "settings title identifies the selected Jak game")
check(view.contains("if cloudState.progressMessage != nil")
        && view.contains(".disabled(!cloudState.isActionEnabled)"),
      "combined cloud progress disables its single conflicting action")
let rowLabelStyle = excerpt(from: "private struct SettingsRowLabelStyle",
                            to: "struct SaveSettingsView", in: view)
check(rowLabelStyle.contains("configuration.icon\n                .foregroundStyle(DarkEcoTheme.accent)")
        && rowLabelStyle.contains("configuration.title\n                .foregroundStyle(.primary)")
        && view.contains(".labelStyle(SettingsRowLabelStyle())")
        && view.contains(".tint(DarkEcoTheme.accent)")
        && view.contains("Label(\"Controls\", systemImage: \"gamecontroller\")")
        && view.contains("Label(\"Graphics\", systemImage: \"display\")")
        && view.contains("Label(\"Manage Save Files\", systemImage: \"externaldrive\")")
        && view.contains("Label(\"Refresh Preserved Saves\", systemImage: \"arrow.clockwise\")")
        && view.contains("Label(\"Import Saves\", systemImage: \"square.and.arrow.down\")")
        && view.contains("Label(\"Export Saves\", systemImage: \"square.and.arrow.up\")")
        && view.contains("Label(\"Sync Options\", systemImage: \"icloud\")"),
      "Settings row icons use Eco purple while row labels use the readable primary style")
let restoreControls = excerpt(from: "Button(\"Restore Controls Defaults\")",
                              to: "private var graphicsContent", in: view)
let restoreGraphics = excerpt(from: "Button(\"Restore Graphics Defaults\")",
                              to: "private var primaryInputSourceChoices", in: view)
let restorePositions = excerpt(from: "Button(\"Restore Default Positions\")",
                               to: ".navigationTitle(\"Touch Sticks\")", in: touchSticks)
check(restoreControls.contains("settings.restoreDefaults(for: .controls)")
        && restoreControls.contains("}\n            .foregroundStyle(.secondary)\n    }")
        && restoreGraphics.contains("settings.restoreDefaults(for: .graphics)")
        && restoreGraphics.contains("}\n            .foregroundStyle(.secondary)\n    }")
        && restorePositions.contains("settings.setTouchControlPosition(nil, for: .modernCamera)")
        && restorePositions.contains("}\n                .foregroundStyle(.secondary)")
        && view.contains("Button(\"Reset All to Defaults\", role: .destructive)")
        && view.contains("isConfirmingResetAll")
        && view.contains("\"Reset all settings?\"")
        && view.contains("This restores the default controls and graphics settings."),
      "Restore Defaults stays subdued and Reset All requires confirmation")
check(occursInOrder([
    "Button(\"Reset All to Defaults\", role: .destructive)",
    "Label(\"About\", systemImage: \"info.circle\")",
    "Text(GOALPadBuildIdentity.versionText)",
], in: view)
        && view.contains("EcoAboutView(tipStore: tipStore)")
        && view.contains("@State private var tipStore = EcoTipStore()"),
      "About follows Reset and the version/build footer is the final Settings content")
check(view.contains("Dark Eco imports and exports four compatible save slots.")
        && view.contains("restore a preserved native save.")
        && !view.contains("the four \\(GameLibraryTitle.jak1.name) save slots")
        && !view.contains("preserved native \\(GameLibraryTitle.jak1.name) save")
        && !view.contains("resolution.relativePath")
        && !view.contains("Section(\"Automatic Resolution\")")
        && !view.contains("BASCUS-"),
      "save UI describes slots and automatic preservation without internal paths")
check(view.contains("Text(\"Preserved Saves\")")
        && view.contains("Make Save Slot \\(candidate.slotNumber) Active")
        && view.contains("The current active copy will be preserved before replacement.")
        && view.contains("candidate.completionPercentage")
        && view.contains("candidate.saveGeneration")
        && view.contains("candidate.source.rawValue")
        && !view.contains("Text(candidate.id)"),
      "preserved native saves can become active using human metadata without exposing paths")
check(!view.contains("Label(\"Developer\", systemImage: \"wrench.and.screwdriver\")")
        && !view.contains("Toggle(\"Show Developer Logs\"")
        && store.contains("var developerLogsEnabledOverride: Bool?")
        && store.contains("developerLogsEnabledOverride ?? false"),
      "Developer Settings stay hidden while their compatible field remains decodable")
check(view.contains("older divergent copies were preserved automatically")
        && !view.contains("switch resolution.basis"),
      "automatic resolution copy remains generic across engine ranking cases")
check(view.contains("Toggle(\"ProMotion\"")
        && !view.contains("Toggle(\"High Frame Rate\"")
        && !view.contains("Allows up to 120 fps on supported ProMotion displays.")
        && !view.contains("Applies the next time ")
        && store.contains("var graphicsHighFrameRateOverride: Bool?")
        && store.contains("var graphicsHighFrameRate: Bool")
        && store.contains("graphicsHighFrameRateOverride ?? (graphicsProfile == .modern)")
        && store.contains("func setGraphicsHighFrameRate(_ enabled: Bool)")
        && content.contains("session.setHighFrameRateEnabled(enabled)")
        && session.contains("func setHighFrameRateEnabled(_ enabled: Bool)"),
      "Graphics exposes concise profile-aware ProMotion that applies live")
check(view.contains("Toggle(\"90 Hz\"")
        && view.contains("settings.graphicsVisionHighFrameRate")
        && view.contains("settings.setGraphicsVisionHighFrameRate($0)")
        && store.contains("var graphicsVisionHighFrameRateOverride: Bool?")
        && store.contains("graphicsVisionHighFrameRateOverride ?? true")
        && content.contains("session.setVisionHighFrameRateEnabled(enabled)")
        && session.contains("func setVisionHighFrameRateEnabled(_ enabled: Bool)"),
      "visionOS exposes its independent live 90 Hz preference")
check(store.contains("var graphicsModernFillWidthOverride: Bool?")
        && store.contains("var graphicsProfile: SettingsProfile = .modern")
        && store.contains("graphicsModernFillWidthOverride ?? (graphicsProfile == .modern)")
        && view.contains("Toggle(\"Fit to Screen\"")
        && view.contains("settings.setGraphicsFillWidth($0)")
        && view.contains("Off preserves the original 4:3 view.")
        && !view.contains("if settings.profile(for: .graphics) == .modern {\n                Toggle(\"Fit to Screen\"")
        && content.contains("VisionWindowGeometryView(")
        && content.contains("session.isRunning")
        && content.contains("!session.presentationSettings.graphicsFillWidth"),
      "both profiles expose Fit to Screen while Classic defaults to a 4:3 vision window")
check(view.contains(experimentalStereoGate)
        && view.contains("Toggle(\"Stereoscopic 3D\"")
        && view.contains("settings.setGraphicsStereo3D")
        && !view.contains("if settings.profile(for: .graphics) == .modern")
        && store.contains("var graphicsModernStereo3DOverride: Bool?")
        && store.contains("graphicsModernStereo3DOverride ?? (graphicsProfile == .modern)")
        && content.contains("session.presentationSettings.graphicsStereo3D")
        && content.contains("synchronizeVisionPresentation()")
        && content.contains(experimentalStereoGate),
      "both profiles expose the same controls while shipping stereo remains source-gated")
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
        && content.contains("session.presentationSettings.jak1TouchLayout")
        && content.contains("session.touch.setLayoutCustomization("),
      "presentation settings keep the accepted touch-layout runtime seam without a Classic profile")
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
check(occursInOrder(["Label(\"Touch Controls Guide\"", "LabeledContent(\"Touch Sticks\""], in: view)
        && !view.contains("Toggle(\"Dynamic Left Stick\"")
        && touchSticks.contains("Toggle(\"Dynamic Left Stick\"")
        && content.contains("session.presentationSettings.dynamicLeftStick")
        && content.contains("session.touch.setDynamicLeftStick(enabled)")
        && store.contains("if section == .controls {")
        && store.contains("func resetAll()")
        && store.contains("setDynamicLeftStick(true)"),
      "Touch Controls Guide leads Controls while Dynamic Left Stick stays inside Touch Sticks")
check(occursInOrder(["LabeledContent(\"Touch Sticks\"", "Picker(\"Touch Actions\"",
                     "Text(\"Gestures\").tag(false)", "Text(\"Buttons\").tag(true)",
                     "#endif", "Button(\"Restore Controls Defaults\""], in: view)
        && view.contains("settings.setTouchFaceButtonsEnabled($0)")
        && store.contains("var touchFaceButtonsEnabledOverride: Bool?")
        && store.contains("touchFaceButtonsEnabledOverride ?? false")
        && content.contains("session.presentationSettings.touchFaceButtonsEnabled")
        && content.contains("session.touch.setFaceButtonsEnabled(enabled)")
        && touchGuide.contains("title: \"Optional Buttons\""),
      "the iOS Touch Actions choice defaults to Gestures and reaches the live touch owner")
check(content.contains("if session.isRunning")
        && content.contains("session.isNativeMenuOpen")
        && content.contains("session.presentationSettings.developerLogsEnabled")
        && !content.contains("showDiagnostics")
        && touchControlsView.contains("NativeEcoSettingsPresentation.isVisible")
        && touchControlsView.contains("Button { performOpenSettings() }")
        && touchControlsView.contains("capturedSettingsButtonIsVisible")
        && touchControlsView.contains("capturedPillLabel(\"SETTINGS\", isEnabled: true)")
        && !touchControlsView.contains("Text(\"DARK ECO\")")
        && touchControlsView.contains(".foregroundStyle(.white.opacity(isEnabled ? 0.8 : 0.42))")
        && touchControlsView.contains(".accessibilityLabel(\"Settings\")"),
      "native menu truth gates the icon-only Settings control and optional logs")
check(content.contains("@State private var settingsPresentation: SettingsSheetPresentation?")
        && content.contains(".sheet(item: $settingsPresentation)")
        && content.contains(".id(presentation.id)")
        && !content.contains("showSettings"),
      "one item-backed Settings presentation keeps a stable identity while it is open")
check(content.contains("#if GOALPAD_APPSTORE_CAPTURE")
        && content.contains("arguments.contains(\"-EcoCaptureGameSetup\")")
        && content.contains("arguments.contains(\"-EcoCaptureSettings\")")
        && !content.contains("EcoCaptureEmptyTitle"),
      "release-media builds can open the three truthful storefront states without retail data")
check(content.contains("openSettings: presentSettings")
        && content.contains("openSettings: presentSettings")
        && content.contains("SettingsSheetView(sync: session.saveSync")
        && !content.contains("SettingsSheetEntry")
        && !content.contains("SettingsTitleListView")
        && !content.contains("NavigationStack(path: $path)"),
      "every entry opens the direct Settings form without a title-list interstitial")
check(view.contains("private struct SettingsGamePicker")
        && view.contains("Section(\"Game\")")
        && view.contains("ForEach([GameLibraryTitle.jak1, .jak2])")
        && view.contains("Button { selectTitle(title) }")
        && view.contains(".disabled(isGameRunning || title == selectedTitle)")
        && view.contains("title: title.settingsPickerLabel")
        && view.contains("SettingsGamePickerChoice(title: GameLibraryTitle.jak3.settingsPickerLabel")
        && view.contains("availability: \"Planned\"")
        && view.contains("showsAvailability: true")
        && view.contains("if showsAvailability")
        && view.contains("Locked while playing")
        && view.contains("\\(selectedTitle.settingsPickerLabel) selected")
        && view.contains(".navigationTitle(\"\\(selectedTitle.settingsPickerLabel) Settings\")"),
      "settings selects either supported title before import, locks to gameplay, and labels Jak 3 Planned")
check(content.contains("selectedTitle: session.title")
        && content.contains("selectSettingsTitle: selectSettingsTitle")
        && view.contains("let selectedTitle: GameLibraryTitle")
        && view.contains("let selectSettingsTitle: (GameLibraryTitle) -> Void")
        && !view.contains("if isGameRunning {\n                Section(\"Game\")"),
      "Settings receives the selected session title without requiring imported game data")
check(occursInOrder(["Section(\"iCloud\")", "Label(cloudState.summary",
                     "DisclosureGroup(isExpanded: expansion(for: .iCloud))"], in: view)
        && !view.contains("Section(\"Saves\")")
        && occursInOrder(["if (sync.isTransferring",
                          "if let message = sync.transferMessage",
                          "DisclosureGroup(isExpanded: expansion(for: .saves))"], in: view),
      "cloud and save transfer status avoid an empty Saves section")
check(content.contains("if session.isRunning && !isOpen { settingsPresentation = nil }"),
      "leaving the native menu still dismisses an in-game Settings sheet")
check(content.contains("@Environment(\\.dismiss) private var dismiss")
        && content.contains("ToolbarItem(placement: .confirmationAction)")
        && content.contains("Button(\"Done\") { dismiss() }")
        && content.contains("ToolbarItem(placement: .topBarLeading)")
        && content.contains(".accessibilityLabel(\"Close Settings\")"),
      "Settings retains an app-owned iOS Done exit and a visible visionOS Close")
check(occursInOrder([
    "presentationSettings = PresentationSettings(profile: presentationProfile)",
    "await GameSessionPreparation.run(",
    "refreshDataReport: { await self.refreshDataReport() }",
    "prepareSettings: { await self.presentationSettings.prepare() }",
    "prepareSaves: { await self.saveSync.prepare() }",
], in: session), "local data publishes before independent settings and save preparation")

if failures == 0 {
    print("presentation settings UI checks passed")
} else {
    print("presentation settings UI checks failed: \(failures)")
    Foundation.exit(1)
}
