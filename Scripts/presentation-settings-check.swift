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
private func defaultsAreClassic() async throws {
    print("defaults preserve the accepted Classic baseline")
    let fixture = try Fixture(name: "defaults")
    let value = settings(fixture, writerID: "device-a")
    check(value.globalProfile == .classic, "all four sections begin in Classic")
    check(value.graphicsFillWidth == false, "Classic never enables Fill Width")
    check(value.cloudSyncEnabled, "settings cloud sync defaults on independently of saves")
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
    check(value.globalProfile == .classic && !value.graphicsFillWidth,
          "Reset All restores the Classic baseline")
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

@main
private struct PresentationSettingsCheck {
    static func main() async {
        do {
            try await defaultsAreClassic()
            try await profilesCanBeMixedWithoutLosingOptions()
            try await localOptOutDoesNotTouchCloud()
            try await cloudSettingsConvergeAsOneDocument()
            try await newerCloudDocumentWinsDeterministically()
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
