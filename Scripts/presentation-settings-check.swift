import Foundation

private var failures = 0

@MainActor
private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("  ok   \(message)")
    } else {
        print("  FAIL \(message)")
        failures += 1
    }
}

private final class Fixture: @unchecked Sendable {
    let root: URL
    let local: URL
    let cloud: URL
    let defaults: UserDefaults
    let defaultsSuiteName: String

    init(name: String) throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "goalpad-presentation-settings-\(UUID().uuidString)",
                       directoryHint: .isDirectory)
        local = root.appending(path: "local/presentation-v1.json", directoryHint: .notDirectory)
        cloud = root.appending(path: "cloud/Documents/GOALPad/Settings/presentation-v1.json",
                               directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defaultsSuiteName = "goalpad-presentation-settings-\(name)-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
    }

    func configuration(cloudAvailable: Bool = true) -> PresentationSettingsConfiguration {
        PresentationSettingsConfiguration(localDocumentURL: local,
                                          cloudDocumentURL: { cloudAvailable ? self.cloud : nil },
                                          coordinateCloudAccess: false)
    }
}

@MainActor
private func settings(_ fixture: Fixture, writerID: String,
                      cloudAvailable: Bool = true) -> PresentationSettings {
    PresentationSettings(defaults: fixture.defaults,
                         configuration: fixture.configuration(cloudAvailable: cloudAvailable),
                         writerID: writerID)
}

private func readDocument(at url: URL) -> PresentationSettingsDocument? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(PresentationSettingsDocument.self, from: data)
}

@MainActor
private func legacyDocumentAndPickerOrderingRemainCompatible() async throws {
    print("legacy documents keep their raw values while pickers lead with Modern")
    check(SettingsProfile.allCases == [.modern, .classic],
          "Modern is the first generated picker choice")
    check(SettingsProfile.modern.rawValue == "modern"
          && SettingsProfile.classic.rawValue == "classic",
          "reordering picker choices does not change persisted raw values")

    let fixture = try Fixture(name: "legacy-document")
    let legacyJSON = Data(
        #"{"schemaVersion":1,"controlsProfile":"modern","graphicsProfile":"classic","audioProfile":"modern","interfaceProfile":"classic","graphicsModernFillWidthOverride":true,"modifiedAt":0,"writerID":"legacy-device"}"#.utf8)
    try FileManager.default.createDirectory(at: fixture.local.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try legacyJSON.write(to: fixture.local, options: .atomic)
    let value = settings(fixture, writerID: "current-device", cloudAvailable: false)
    check(value.profile(for: .controls) == .modern
          && value.profile(for: .graphics) == .classic
          && value.profile(for: .audio) == .modern
          && value.profile(for: .interface) == .classic,
          "the pre-existing four-section document loads without migration loss")
    check(value.document.graphicsModernFillWidthOverride == true,
          "the legacy graphics option remains persisted even while Classic is selected")
    check(!value.developerLogsEnabled,
          "a Build 93 document defaults the newly added developer logs setting off")
    check(value.primaryInputSource == .automatic,
          "a Build 93 document defaults the new Primary Controller choice to Automatic")
    check(value.jak1InputBindings == .standard
          && value.jak1InputBindings.controllerStickRoles == .standard
          && value.jak1InputBindings.controllerAnalog == .standard
          && value.jak1InputBindings.mouseCamera == .standard
          && value.document.jak1InputBindingsOverride == nil,
          "a document without remapping data decodes to exact established input defaults")
    check(value.jak1TouchLayout == .standard
          && value.document.jak1TouchLayoutOverride == nil,
          "a Build 93 document preserves the exact established touch layouts without migration")
}

@MainActor
private func primaryInputSourcePersistsAndResets() async throws {
    print("Primary Controller is a compatible per-game synced setting")
    let fixture = try Fixture(name: "primary-input")
    let value = settings(fixture, writerID: "device-a", cloudAvailable: false)
    check(value.primaryInputSource == .automatic, "Primary Controller begins Automatic")
    value.setPrimaryInputSource(.controller)
    check(value.primaryInputSource == .controller, "Controller can be explicitly preferred")
    let restored = settings(fixture, writerID: "device-b", cloudAvailable: false)
    check(restored.primaryInputSource == .controller,
          "Primary Controller persists in the Jak 1 document")
    restored.restoreDefaults(for: .controls)
    check(restored.primaryInputSource == .automatic,
          "Restore Controls Defaults restores Automatic source selection")
    restored.setPrimaryInputSource(.keyboardMouse)
    restored.resetAll()
    check(restored.primaryInputSource == .automatic,
          "Reset Jak 1 Settings restores Automatic source selection")
}

@MainActor
private func inputBindingsPersistSyncAndReset() async throws {
    print("Jak 1 physical-input bindings persist in the compatible synced document")
    let fixture = try Fixture(name: "input-bindings")
    let value = settings(fixture, writerID: "device-a", cloudAvailable: false)
    check(value.jak1InputBindings == .standard
          && value.jak1InputBindings.controllerStickRoles == .standard
          && value.jak1InputBindings.controllerAnalog == .standard
          && value.jak1InputBindings.mouseCamera == .standard
          && value.document.jak1InputBindingsOverride == nil,
          "a fresh title begins with standard bindings without storing an override")

    value.setControllerAction(.square, for: .buttonA)
    value.setKeyboardMouseAction(.stats, for: .spacebar)
    value.setKeyboardMouseAction(.moveForward, for: .returnOrEnter)
    value.setControllerStickRoles(.swapped)
    value.setControllerSensitivityPercent(150, for: .movement)
    value.setControllerDeadZonePercent(20, for: .movement)
    value.setControllerInvertHorizontal(true, for: .movement)
    value.setControllerSensitivityPercent(75, for: .camera)
    value.setControllerDeadZonePercent(10, for: .camera)
    value.setControllerInvertVertical(true, for: .camera)
    value.setMouseCameraSensitivityPercent(175)
    value.setMouseCameraInvertHorizontal(true)
    value.setMouseCameraInvertVertical(true)
    check(value.jak1InputBindings.action(for: .buttonA) == .square
          && value.jak1InputBindings.action(for: .buttonX) == .cross,
          "controller collision swaps are stored through PresentationSettings")
    check(value.jak1InputBindings.action(for: .spacebar) == .stats
          && value.jak1InputBindings.action(for: .tab) == nil,
          "an explicit added Stats key is stored without duplicate ownership")
    check(value.jak1InputBindings.action(for: .returnOrEnter) == .moveForward
          && value.jak1InputBindings.action(for: .w) == nil,
          "a movement direction can move away from its default W key")
    check(value.jak1InputBindings.controllerStickRoles == .swapped,
          "Swapped Sticks is stored through the same live Jak 1 input binding value")
    check(value.jak1InputBindings.controllerAnalog.movement.sensitivityPercent == 150
          && value.jak1InputBindings.controllerAnalog.movement.deadZonePercent == 20
          && value.jak1InputBindings.controllerAnalog.movement.invertHorizontal
          && value.jak1InputBindings.controllerAnalog.camera.sensitivityPercent == 75
          && value.jak1InputBindings.controllerAnalog.camera.deadZonePercent == 10
          && value.jak1InputBindings.controllerAnalog.camera.invertVertical,
          "movement and camera controller vectors store independent bounded tuning")
    check(value.jak1InputBindings.mouseCamera.sensitivityPercent == 175
          && value.jak1InputBindings.mouseCamera.invertHorizontal
          && value.jak1InputBindings.mouseCamera.invertVertical,
          "mouse sensitivity and both camera directions use that same live binding value")

    let restored = settings(fixture, writerID: "device-b", cloudAvailable: false)
    check(restored.jak1InputBindings == value.jak1InputBindings
          && restored.jak1InputBindings.controllerStickRoles == .swapped
          && restored.jak1InputBindings.controllerAnalog.movement.deadZonePercent == 20
          && restored.jak1InputBindings.controllerAnalog.camera.sensitivityPercent == 75
          && restored.jak1InputBindings.mouseCamera.sensitivityPercent == 175,
          "controller roles/tuning, buttons, keys, movement, and mouse tuning survive local decoding")
    restored.setPrimaryInputSource(.controller)
    restored.restoreDefaults(for: .controls)
    check(restored.jak1InputBindings == .standard
          && restored.jak1InputBindings.controllerStickRoles == .standard
          && restored.jak1InputBindings.controllerAnalog == .standard
          && restored.jak1InputBindings.mouseCamera == .standard
          && restored.document.jak1InputBindingsOverride == nil
          && restored.primaryInputSource == .automatic,
          "Restore Controls Defaults resets all remaps, tuning, and source selection together")

    restored.setControllerAction(.stats, for: .buttonA)
    restored.setKeyboardMouseAction(.cross, for: .mouseLeft)
    restored.setControllerStickRoles(.swapped)
    restored.setControllerDeadZonePercent(25, for: .movement)
    restored.setControllerInvertVertical(true, for: .camera)
    restored.setMouseCameraSensitivityPercent(250)
    restored.setMouseCameraInvertVertical(true)
    restored.resetAll()
    check(restored.jak1InputBindings == .standard
          && restored.jak1InputBindings.controllerStickRoles == .standard
          && restored.jak1InputBindings.controllerAnalog == .standard
          && restored.jak1InputBindings.mouseCamera == .standard
          && restored.document.jak1InputBindingsOverride == nil,
          "Reset Jak 1 Settings restores every physical-input binding, role, and mouse option")
}

@MainActor
private func touchLayoutPersistsSyncsAndResets() async throws {
    print("Jak 1 touch layout is default-omitted, persistent, and reset with Controls")
    let fixture = try Fixture(name: "touch-layout")
    let value = settings(fixture, writerID: "device-a", cloudAvailable: false)
    check(value.jak1TouchLayout == .standard
          && value.document.jak1TouchLayoutOverride == nil,
          "a fresh title uses the existing geometry without storing an override")

    value.setTouchControlPosition(NormalizedTouchPosition(x: 0.18, y: 0.76),
                                  for: .modernMovement)
    value.setTouchControlAction(.cameraStick, for: .modernMovement)
    value.setTouchGestureAction(.square, for: .up)
    value.setTouchControlOpacityPercent(55, for: .modernActions)
    value.setTouchControlSizePercent(135, for: .classicCross)
    check(value.jak1TouchLayout.position(for: .modernMovement)
            == NormalizedTouchPosition(x: 0.18, y: 0.76)
          && value.jak1TouchLayout.action(for: .modernMovement) == .cameraStick
          && value.jak1TouchLayout.action(for: .modernCamera) == .movementStick
          && value.jak1TouchLayout.gestureAction(for: .up) == .square
          && value.jak1TouchLayout.gestureAction(for: .left) == .cross
          && value.jak1TouchLayout.opacity(for: .modernActions) == 0.55
          && value.jak1TouchLayout.scale(for: .classicCross) == 1.35,
          "position, swap remaps, gesture mapping, opacity, and size update one live value")
    let localJSON = try String(contentsOf: fixture.local, encoding: .utf8)
    check(localJSON.contains("jak1TouchLayoutOverride")
          && localJSON.contains("modernMovement")
          && !localJSON.contains("opacityPercent\":100")
          && !localJSON.contains("sizePercent\":100"),
          "only customized touch fields occupy the existing title document")

    let restored = settings(fixture, writerID: "device-b", cloudAvailable: false)
    check(restored.jak1TouchLayout == value.jak1TouchLayout,
          "the complete customized layout survives local relaunch decoding")
    restored.resetTouchControl(.modernActions)
    check(restored.jak1TouchLayout.gestureAction(for: .up) == .cross
          && restored.jak1TouchLayout.opacity(for: .modernActions) == 1
          && restored.jak1TouchLayout.position(for: .modernMovement) != nil,
          "Reset Control restores only that control's safe defaults")
    restored.resetTouchLayout()
    check(restored.jak1TouchLayout == .standard
          && restored.document.jak1TouchLayoutOverride == nil,
          "Reset Layout removes all Modern and Classic layout overrides")
    restored.setTouchControlPosition(NormalizedTouchPosition(x: 0.3, y: 0.7),
                                     for: .modernMovement)
    restored.setTouchControlSizePercent(125, for: .classicCross)
    restored.restoreDefaults(for: .controls)
    check(restored.jak1TouchLayout == .standard
          && restored.document.jak1TouchLayoutOverride == nil,
          "Restore Controls Defaults removes both Modern and Classic customizations")

    restored.setTouchControlSizePercent(145, for: .classicCamera)
    restored.resetAll()
    check(restored.jak1TouchLayout == .standard
          && restored.document.jak1TouchLayoutOverride == nil,
          "Reset Jak 1 Settings also returns the complete touch layout to default")
}

@MainActor
private func developerLogsPersistAndReset() async throws {
    print("developer logs are a synced-document option with a safe default")
    let fixture = try Fixture(name: "developer-logs")
    let value = settings(fixture, writerID: "device-a", cloudAvailable: false)
    check(!value.developerLogsEnabled, "developer logs begin off")
    value.setDeveloperLogsEnabled(true)
    check(value.developerLogsEnabled, "the developer option can be enabled")
    let restored = settings(fixture, writerID: "device-b", cloudAvailable: false)
    check(restored.developerLogsEnabled, "the developer option persists locally")
    restored.resetAll()
    check(!restored.developerLogsEnabled,
          "Reset Jak 1 Settings restores developer logs to off")
}

@MainActor
private func defaultsUseModernGraphics() async throws {
    print("defaults use Modern Graphics without changing other sections")
    let fixture = try Fixture(name: "defaults")
    let value = settings(fixture, writerID: "device-a")
    check(value.globalProfile == nil, "the default section mix reports Mixed")
    check(value.profile(for: .controls) == .classic, "Controls begins in Classic")
    check(value.profile(for: .graphics) == .modern, "Graphics begins in Modern")
    check(value.profile(for: .audio) == .classic, "Audio begins in Classic")
    check(value.profile(for: .interface) == .classic, "UI begins in Classic")
    check(value.graphicsFillWidth, "Modern Graphics begins with Fill Width enabled")
    check(value.document.graphicsModernFillWidthOverride == nil,
          "the default uses the Modern option value instead of a stored override")
    check(value.cloudSyncEnabled, "settings cloud sync defaults on independently of saves")
}

@MainActor
private func savedChoicesSurviveNewDefaults() async throws {
    print("existing saved profile and option choices survive the new defaults")
    let classicFixture = try Fixture(name: "saved-classic")
    var classic = PresentationSettingsDocument(writerID: "device-old")
    classic.setProfile(.modern, for: .controls)
    classic.setProfile(.classic, for: .graphics)
    try FileManager.default.createDirectory(at: classicFixture.local.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try JSONEncoder().encode(classic).write(to: classicFixture.local, options: .atomic)
    let restoredClassic = settings(classicFixture, writerID: "device-new")
    check(restoredClassic.profile(for: .controls) == .modern
          && restoredClassic.profile(for: .graphics) == .classic
          && !restoredClassic.graphicsFillWidth,
          "a saved Classic Graphics selection loads unchanged")

    let modernFixture = try Fixture(name: "saved-modern-override")
    var modern = PresentationSettingsDocument(writerID: "device-old")
    modern.graphicsModernFillWidthOverride = false
    try FileManager.default.createDirectory(at: modernFixture.local.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try JSONEncoder().encode(modern).write(to: modernFixture.local, options: .atomic)
    let restoredModern = settings(modernFixture, writerID: "device-new")
    check(restoredModern.profile(for: .graphics) == .modern
          && !restoredModern.graphicsFillWidth,
          "a saved Modern Fill Width override loads unchanged")
}

@MainActor
private func profilesCanBeMixedWithoutLosingOptions() async throws {
    print("section profiles are independent and preserve Modern options")
    let fixture = try Fixture(name: "mixed")
    let value = settings(fixture, writerID: "device-a", cloudAvailable: false)
    value.setProfile(.modern, for: .graphics)
    check(value.graphicsFillWidth, "Modern graphics defaults Fill Width on")
    value.setGraphicsFillWidth(false)
    value.setProfile(.classic, for: .graphics)
    value.setProfile(.modern, for: .audio)
    check(value.globalProfile == nil, "different section profiles report Mixed")
    value.setProfile(.modern, for: .graphics)
    check(!value.graphicsFillWidth, "switching profiles preserves a customized Fill Width value")

    value.restoreDefaults(for: .graphics)
    check(value.graphicsFillWidth, "graphics Restore Defaults returns Modern Fill Width to on")
    value.applyPreset(.classic)
    check(value.globalProfile == .classic, "global Classic applies to every section")
    check(value.document.graphicsModernFillWidthOverride == nil,
          "global profile changes do not discard section options")
    value.resetAll()
    check(value.globalProfile == nil
          && value.profile(for: .controls) == .classic
          && value.profile(for: .graphics) == .modern
          && value.profile(for: .audio) == .classic
          && value.profile(for: .interface) == .classic
          && value.graphicsFillWidth
          && value.document.graphicsModernFillWidthOverride == nil,
          "Reset All restores the default Modern Graphics mix")
}

@MainActor
private func localOptOutDoesNotTouchCloud() async throws {
    print("settings cloud opt-out is local and leaves saves independent")
    let fixture = try Fixture(name: "optout")
    fixture.defaults.set(false, forKey: "iCloudPresentationSettingsSyncEnabled")
    let value = settings(fixture, writerID: "device-a")
    value.setProfile(.modern, for: .graphics)
    check(!value.cloudSyncEnabled, "local opt-out is restored")
    check(!FileManager.default.fileExists(atPath: fixture.cloud.path),
          "local opt-out does not create a cloud settings document")
    check(readDocument(at: fixture.local)?.graphicsProfile == .modern,
          "local opt-out still persists the selected section")
}

@MainActor
private func cloudSettingsConvergeAsOneDocument() async throws {
    print("the complete profile document syncs together")
    let fixtureA = try Fixture(name: "cloud-a")
    let fixtureB = try Fixture(name: "cloud-b")
    let sharedCloud = fixtureA.cloud
    let sharedConfigurationA = PresentationSettingsConfiguration(localDocumentURL: fixtureA.local,
                                                                   cloudDocumentURL: { sharedCloud },
                                                                   coordinateCloudAccess: false)
    let sharedConfigurationB = PresentationSettingsConfiguration(localDocumentURL: fixtureB.local,
                                                                   cloudDocumentURL: { sharedCloud },
                                                                   coordinateCloudAccess: false)
    let first = PresentationSettings(defaults: fixtureA.defaults, configuration: sharedConfigurationA,
                                     writerID: "device-a")
    await first.prepare()
    first.setProfile(.modern, for: .graphics)
    first.setProfile(.modern, for: .audio)
    first.setGraphicsFillWidth(false)
    first.setControllerAction(.square, for: .buttonA)
    first.setKeyboardMouseAction(.stats, for: .spacebar)
    first.setKeyboardMouseAction(.moveForward, for: .returnOrEnter)
    first.setControllerStickRoles(.swapped)
    first.setControllerSensitivityPercent(175, for: .movement)
    first.setControllerDeadZonePercent(15, for: .camera)
    first.setControllerInvertHorizontal(true, for: .camera)
    first.setMouseCameraSensitivityPercent(150)
    first.setMouseCameraInvertVertical(true)
    first.setTouchControlPosition(NormalizedTouchPosition(x: 0.8, y: 0.3),
                                  for: .modernCamera)
    first.setTouchControlAction(.triangle, for: .classicCross)
    first.setTouchControlOpacityPercent(60, for: .classicStats)
    await first.syncNow()

    let second = PresentationSettings(defaults: fixtureB.defaults, configuration: sharedConfigurationB,
                                      writerID: "device-b")
    await second.prepare()
    check(second.profile(for: .graphics) == .modern && second.profile(for: .audio) == .modern,
          "a second device receives every changed section profile together")
    check(!second.graphicsFillWidth, "the second device receives the customized Modern option")
    check(second.jak1InputBindings.action(for: .buttonA) == .square
          && second.jak1InputBindings.action(for: .buttonX) == .cross
          && second.jak1InputBindings.action(for: .spacebar) == .stats
          && second.jak1InputBindings.action(for: .tab) == nil
          && second.jak1InputBindings.action(for: .returnOrEnter) == .moveForward
          && second.jak1InputBindings.action(for: .w) == nil
          && second.jak1InputBindings.controllerStickRoles == .swapped
          && second.jak1InputBindings.controllerAnalog.movement.sensitivityPercent == 175
          && second.jak1InputBindings.controllerAnalog.camera.deadZonePercent == 15
          && second.jak1InputBindings.controllerAnalog.camera.invertHorizontal
          && second.jak1InputBindings.mouseCamera.sensitivityPercent == 150
          && !second.jak1InputBindings.mouseCamera.invertHorizontal
          && second.jak1InputBindings.mouseCamera.invertVertical,
          "the second device receives the title's remapped controller and mouse tuning")
    check(second.jak1TouchLayout.position(for: .modernCamera)
            == NormalizedTouchPosition(x: 0.8, y: 0.3)
          && second.jak1TouchLayout.action(for: .classicCross) == .triangle
          && second.jak1TouchLayout.action(for: .classicTriangle) == .cross
          && second.jak1TouchLayout.opacity(for: .classicStats) == 0.6,
          "the second device receives the same complete touch layout document")
}

@MainActor
private func coordinatedFirstCloudWriteCreatesItsNestedDocument() async throws {
    print("the first coordinated cloud write targets an existing ancestor")
    let fixture = try Fixture(name: "first-cloud-write")
    let configuration = PresentationSettingsConfiguration(
        localDocumentURL: fixture.local,
        cloudDocumentURL: { fixture.cloud },
        coordinateCloudAccess: true)
    let value = PresentationSettings(defaults: fixture.defaults, configuration: configuration,
                                     writerID: "device-a")
    await value.syncNow()
    let stored = readDocument(at: fixture.cloud)
    check(stored?.globalProfile == nil && stored?.graphicsProfile == .modern,
          "a fresh coordinated cloud stores the default Modern Graphics mix")
    let successfulDate = value.lastSyncDate
    value.cloudSyncEnabled = false
    check(successfulDate != nil && value.lastSyncDate == successfulDate,
          "turning sync off preserves the most recent successful settings sync date")
}

@MainActor
private func newerCloudDocumentWinsDeterministically() async throws {
    print("cloud conflicts use a stable timestamp and writer tie-breaker")
    let fixture = try Fixture(name: "conflict")
    let date = Date(timeIntervalSince1970: 2_000_000_000)
    var localDocument = PresentationSettingsDocument(modifiedAt: date, writerID: "device-a")
    localDocument.setProfile(.modern, for: .controls)
    try FileManager.default.createDirectory(at: fixture.local.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try JSONEncoder().encode(localDocument).write(to: fixture.local, options: .atomic)

    var remote = PresentationSettingsDocument(
        modifiedAt: date, writerID: "device-z")
    remote.setProfile(.modern, for: .interface)
    try FileManager.default.createDirectory(at: fixture.cloud.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try JSONEncoder().encode(remote).write(to: fixture.cloud, options: .atomic)
    let local = settings(fixture, writerID: "device-a")
    await local.syncNow()
    check(local.profile(for: .interface) == .modern && local.profile(for: .controls) == .classic,
          "the equal-time writer tie-breaker replaces the local document as one unit")
}

@MainActor
private func unresolvedCloudVersionParticipatesInConflictResolution() async throws {
    print("unresolved iCloud versions participate in the same deterministic merge")
    let fixture = try Fixture(name: "file-version-conflict")
    let date = Date(timeIntervalSince1970: 2_100_000_000)
    var current = PresentationSettingsDocument(modifiedAt: date, writerID: "device-a")
    current.setProfile(.modern, for: .controls)
    try FileManager.default.createDirectory(at: fixture.cloud.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try JSONEncoder().encode(current).write(to: fixture.cloud, options: .atomic)

    var conflict = PresentationSettingsDocument(modifiedAt: date, writerID: "device-z")
    conflict.setProfile(.modern, for: .interface)
    let conflictData = try JSONEncoder().encode(conflict)
    let configuration = PresentationSettingsConfiguration(
        localDocumentURL: fixture.local,
        cloudDocumentURL: { fixture.cloud },
        coordinateCloudAccess: false,
        cloudConflictDocumentData: { _ in [conflictData] })
    let value = PresentationSettings(defaults: fixture.defaults, configuration: configuration,
                                     writerID: "device-local")
    await value.syncNow()
    check(value.profile(for: .interface) == .modern && value.profile(for: .controls) == .classic,
          "the highest-ranked unresolved version wins as one complete document")
    check(readDocument(at: fixture.cloud)?.writerID == "device-z",
          "the conflict winner replaces the current cloud document")
}

@main
private struct PresentationSettingsCheck {
    static func main() async {
        do {
            try await legacyDocumentAndPickerOrderingRemainCompatible()
            try await developerLogsPersistAndReset()
            try await primaryInputSourcePersistsAndResets()
            try await inputBindingsPersistSyncAndReset()
            try await touchLayoutPersistsSyncsAndResets()
            try await defaultsUseModernGraphics()
            try await savedChoicesSurviveNewDefaults()
            try await profilesCanBeMixedWithoutLosingOptions()
            try await localOptOutDoesNotTouchCloud()
            try await cloudSettingsConvergeAsOneDocument()
            try await coordinatedFirstCloudWriteCreatesItsNestedDocument()
            try await newerCloudDocumentWinsDeterministically()
            try await unresolvedCloudVersionParticipatesInConflictResolution()
        } catch {
            print("  FAIL unexpected error: \(error)")
            failures += 1
        }

        if failures == 0 {
            print("presentation settings checks passed")
        } else {
            print("presentation settings checks failed: \(failures)")
            Foundation.exit(1)
        }
    }
}
