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
    await first.syncNow()

    let second = PresentationSettings(defaults: fixtureB.defaults, configuration: sharedConfigurationB,
                                      writerID: "device-b")
    await second.prepare()
    check(second.profile(for: .graphics) == .modern && second.profile(for: .audio) == .modern,
          "a second device receives every changed section profile together")
    check(!second.graphicsFillWidth, "the second device receives the customized Modern option")
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
