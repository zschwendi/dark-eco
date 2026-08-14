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

    var localTouchLayout: URL {
        local.deletingLastPathComponent()
            .appending(path: "jak1-touch-layout-v1.json", directoryHint: .notDirectory)
    }

    var cloudTouchLayout: URL {
        cloud.deletingLastPathComponent()
            .appending(path: "jak1-touch-layout-v1.json", directoryHint: .notDirectory)
    }

    func configuration(cloudAvailable: Bool = true) -> PresentationSettingsConfiguration {
        PresentationSettingsConfiguration(localDocumentURL: local,
                                          cloudDocumentURL: { cloudAvailable ? self.cloud : nil },
                                          coordinateCloudAccess: false)
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var tick: TimeInterval = 2_200_000_000

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        tick += 1
        return Date(timeIntervalSince1970: tick)
    }
}

private struct TestCloudError: LocalizedError {
    var errorDescription: String? { "intentional cloud test failure" }
}

private struct Build116PresentationDocument: Codable {
    var schemaVersion: Int
    var controlsProfile: SettingsProfile
    var graphicsProfile: SettingsProfile
    var audioProfile: SettingsProfile
    var interfaceProfile: SettingsProfile
    var graphicsModernFillWidthOverride: Bool?
    var developerLogsEnabledOverride: Bool?
    var primaryInputSourceOverride: PrimaryInputSource?
    var jak1InputBindingsOverride: Jak1InputBindings?
    var modifiedAt: Date
    var writerID: String
}

private actor DelayedCloudStore: PresentationSettingsCloudStoring {
    let url: URL
    private let delayWrites: Bool
    private let delayTouchWrites: Bool
    private var delayNextRead: Bool
    private var storedDocument: PresentationSettingsDocument?
    private var storedTouchLayoutDocument: Jak1TouchLayoutSettingsDocument?
    private var pendingDocument: PresentationSettingsDocument?
    private var pendingTouchLayoutDocument: Jak1TouchLayoutSettingsDocument?
    private var readCount = 0
    private var writeCount = 0
    private var touchWriteCount = 0
    private var releaseReadContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var releaseTouchContinuation: CheckedContinuation<Void, Never>?
    private var readWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var writeWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var touchWriteWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    init(url: URL, initialDocument: PresentationSettingsDocument? = nil,
         delayFirstRead: Bool = false, delayWrites: Bool = true,
         delayTouchWrites: Bool = false) {
        self.url = url
        self.storedDocument = initialDocument
        self.delayNextRead = delayFirstRead
        self.delayWrites = delayWrites
        self.delayTouchWrites = delayTouchWrites
    }

    func read() async throws -> PresentationSettingsCloudState? {
        readCount += 1
        if delayNextRead {
            delayNextRead = false
            await withCheckedContinuation { continuation in
                releaseReadContinuation = continuation
                for waiter in readWaiters.removeValue(forKey: readCount) ?? [] {
                    waiter.resume()
                }
            }
        }
        return PresentationSettingsCloudState(
            url: url,
            document: storedDocument,
            hasConflicts: false,
            touchLayoutDocument: storedTouchLayoutDocument,
            touchLayoutFileExists: storedTouchLayoutDocument != nil)
    }

    func write(_ document: PresentationSettingsDocument, to _: URL) async throws {
        writeCount += 1
        guard delayWrites else {
            storedDocument = document
            return
        }
        await withCheckedContinuation { continuation in
            pendingDocument = document
            releaseContinuation = continuation
            for waiter in writeWaiters.removeValue(forKey: writeCount) ?? [] {
                waiter.resume()
            }
        }
        storedDocument = document
        pendingDocument = nil
    }

    func write(_ document: Jak1TouchLayoutSettingsDocument, to _: URL) async throws {
        touchWriteCount += 1
        guard delayTouchWrites else {
            storedTouchLayoutDocument = document
            return
        }
        await withCheckedContinuation { continuation in
            pendingTouchLayoutDocument = document
            releaseTouchContinuation = continuation
            for waiter in touchWriteWaiters.removeValue(forKey: touchWriteCount) ?? [] {
                waiter.resume()
            }
        }
        storedTouchLayoutDocument = document
        pendingTouchLayoutDocument = nil
    }

    func waitUntilReadStarts(_ expectedCount: Int) async {
        if readCount >= expectedCount, releaseReadContinuation != nil { return }
        await withCheckedContinuation { continuation in
            readWaiters[expectedCount, default: []].append(continuation)
        }
    }

    func waitUntilWriteStarts(_ expectedCount: Int) async {
        if writeCount >= expectedCount, releaseContinuation != nil { return }
        await withCheckedContinuation { continuation in
            writeWaiters[expectedCount, default: []].append(continuation)
        }
    }

    func waitUntilTouchWriteStarts(_ expectedCount: Int) async {
        if touchWriteCount >= expectedCount, releaseTouchContinuation != nil { return }
        await withCheckedContinuation { continuation in
            touchWriteWaiters[expectedCount, default: []].append(continuation)
        }
    }

    func pendingWrite() -> PresentationSettingsDocument? {
        pendingDocument
    }

    func storedValue() -> PresentationSettingsDocument? {
        storedDocument
    }

    func storedTouchValue() -> Jak1TouchLayoutSettingsDocument? {
        storedTouchLayoutDocument
    }

    func completedReadCount() -> Int {
        readCount
    }

    func releaseRead(_ expectedCount: Int) -> Bool {
        guard readCount == expectedCount,
              let continuation = releaseReadContinuation else { return false }
        releaseReadContinuation = nil
        continuation.resume()
        return true
    }

    func releaseWrite(_ expectedCount: Int) -> Bool {
        guard writeCount == expectedCount, let continuation = releaseContinuation else {
            return false
        }
        releaseContinuation = nil
        continuation.resume()
        return true
    }

    func releaseTouchWrite(_ expectedCount: Int) -> Bool {
        guard touchWriteCount == expectedCount,
              let continuation = releaseTouchContinuation else { return false }
        releaseTouchContinuation = nil
        continuation.resume()
        return true
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

private func readTouchLayoutDocument(at url: URL) -> Jak1TouchLayoutSettingsDocument? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(Jak1TouchLayoutSettingsDocument.self, from: data)
}

private func embeddedBuild117DocumentData(
    _ document: PresentationSettingsDocument,
    layout: TouchLayoutCustomization
) throws -> Data {
    let encoder = JSONEncoder()
    var object = try JSONSerialization.jsonObject(with: encoder.encode(document))
        as! [String: Any]
    object["jak1TouchLayoutOverride"] = try JSONSerialization.jsonObject(
        with: encoder.encode(layout))
    return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
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
    check(!value.graphicsHighFrameRate
          && value.document.graphicsHighFrameRateOverride == nil,
          "a same-schema document without ProMotion defaults the presentation preference off")
    check(value.primaryInputSource == .automatic,
          "a Build 93 document defaults the new Primary Controller choice to Automatic")
    check(value.jak1InputBindings == .standard
          && value.jak1InputBindings.controllerStickRoles == .standard
          && value.jak1InputBindings.controllerAnalog == .standard
          && value.jak1InputBindings.mouseCamera == .standard
          && value.document.jak1InputBindingsOverride == nil,
          "a document without remapping data decodes to exact established input defaults")
    check(value.jak1TouchLayout == .standard
          && value.touchLayoutDocument.jak1TouchLayoutOverride == nil
          && value.dynamicLeftStick
          && value.touchLayoutDocument.dynamicLeftStickOverride == nil,
          "a Build 93 document adopts the dynamic-small default without changing its layout")
}

@MainActor
private func embeddedBuild117TouchLayoutMigratesBeforeLegacyRewrite() async throws {
    print("embedded Build 117 touch layout migrates before an old local writer rewrites settings")
    let fixture = try Fixture(name: "embedded-touch-migration")
    let date = Date(timeIntervalSince1970: 2_300_000_000)
    let presentation = PresentationSettingsDocument(modifiedAt: date,
                                                    writerID: "build117-device")
    var layout = TouchLayoutCustomization.standard
    layout.setPosition(NormalizedTouchPosition(x: 0.22, y: 0.71),
                       for: .modernMovement)
    layout.setSizePercent(135, for: .classicCross)
    try FileManager.default.createDirectory(at: fixture.local.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try embeddedBuild117DocumentData(presentation, layout: layout)
        .write(to: fixture.local, options: .atomic)

    let migrated = settings(fixture, writerID: "current-device", cloudAvailable: false)
    check(migrated.jak1TouchLayout == layout
          && readTouchLayoutDocument(at: fixture.localTouchLayout)?.jak1TouchLayout == layout,
          "a missing sidecar is populated from the embedded Build 117 override")

    var legacy = try JSONDecoder().decode(Build116PresentationDocument.self,
                                          from: Data(contentsOf: fixture.local))
    legacy.graphicsProfile = .classic
    legacy.modifiedAt = date.addingTimeInterval(10)
    legacy.writerID = "build116-device"
    try JSONEncoder().encode(legacy).write(to: fixture.local, options: .atomic)

    let restored = settings(fixture, writerID: "new-device", cloudAvailable: false)
    check(restored.profile(for: .graphics) == .classic,
          "the Build 116-shaped whole-document rewrite remains readable")
    check(restored.jak1TouchLayout == layout,
          "the old presentation writer cannot erase the migrated touch sidecar")
}

@MainActor
private func embeddedCloudBuild117TouchLayoutMigratesToSidecar() async throws {
    print("embedded cloud Build 117 touch layout migrates before presentation cleanup")
    let fixture = try Fixture(name: "embedded-cloud-touch-migration")
    let presentation = PresentationSettingsDocument(
        modifiedAt: Date(timeIntervalSince1970: 2_350_000_000),
        writerID: "build117-cloud-device")
    var layout = TouchLayoutCustomization.standard
    layout.setPosition(NormalizedTouchPosition(x: 0.81, y: 0.24), for: .modernCamera)
    layout.setOpacityPercent(60, for: .classicStats)
    try FileManager.default.createDirectory(at: fixture.cloud.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try embeddedBuild117DocumentData(presentation, layout: layout)
        .write(to: fixture.cloud, options: .atomic)

    let migrated = settings(fixture, writerID: "current-device")
    await migrated.prepare()
    let cloudPresentationJSON = try String(contentsOf: fixture.cloud, encoding: .utf8)
    check(migrated.jak1TouchLayout == layout
          && readTouchLayoutDocument(at: fixture.localTouchLayout)?.jak1TouchLayout == layout
          && readTouchLayoutDocument(at: fixture.cloudTouchLayout)?.jak1TouchLayout == layout,
          "cloud migration secures matching local and cloud touch sidecars")
    check(!cloudPresentationJSON.contains("jak1TouchLayoutOverride"),
          "the embedded cloud key is removed only after the sidecar is written")
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
    restored.setRumbleEnabled(false)
    restored.restoreDefaults(for: .controls)
    check(restored.primaryInputSource == .automatic && restored.rumbleEnabled,
          "Restore Controls Defaults restores Automatic source selection and Rumble")
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
          && value.jak1InputBindings.action(for: .tab) == .cross,
          "an explicit Stats key swaps the previous Space binding without duplicate ownership")
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
private func legacyTouchLayoutSidecarPersistsAcrossPresentationResets() async throws {
    print("the legacy touch-layout sidecar is default-omitted, persistent, and preserved by presentation resets")
    let fixture = try Fixture(name: "touch-layout")
    let value = settings(fixture, writerID: "device-a", cloudAvailable: false)
    check(value.jak1TouchLayout == .standard
          && value.touchLayoutDocument.jak1TouchLayoutOverride == nil
          && value.dynamicLeftStick
          && value.touchLayoutDocument.dynamicLeftStickOverride == nil,
          "a fresh title uses dynamic-left and the smallest stick geometry without overrides")

    value.setDynamicLeftStick(true)
    value.setTouchControlPosition(NormalizedTouchPosition(x: 0.18, y: 0.76),
                                  for: .modernMovement)
    value.setTouchControlPosition(NormalizedTouchPosition(x: 0.82, y: 0.72),
                                  for: .modernCamera)
    value.setTouchStickSize(.medium, for: .modernMovement)
    value.setTouchStickSize(.large, for: .modernCamera)
    value.setTouchControlAction(.cameraStick, for: .modernMovement)
    value.setTouchGestureAction(.square, for: .up)
    value.setTouchGestureAction(.circle, for: .down)
    value.setTouchControlOpacityPercent(55, for: .modernActions)
    value.setTouchControlSizePercent(135, for: .classicCross)
    check(value.jak1TouchLayout.position(for: .modernMovement)
            == NormalizedTouchPosition(x: 0.18, y: 0.76)
          && value.jak1TouchLayout.action(for: .modernMovement) == .cameraStick
          && value.jak1TouchLayout.action(for: .modernCamera) == .movementStick
          && value.jak1TouchLayout.gestureAction(for: .up) == .square
          && value.jak1TouchLayout.gestureAction(for: .left) == .cross
          && value.jak1TouchLayout.gestureAction(for: .down) == .crouch
          && value.jak1TouchLayout.opacity(for: .modernActions) == 0.55
          && value.jak1TouchLayout.stickSize(for: .modernMovement) == .medium
          && value.jak1TouchLayout.stickSize(for: .modernCamera) == .large
          && value.jak1TouchLayout.scale(for: .classicCross) == 1.35,
          "positions, discrete stick sizes, remaps, gestures, and opacity update one live value")
    let presentationJSON = (try? String(contentsOf: fixture.local, encoding: .utf8)) ?? ""
    let touchLayoutJSON = try String(contentsOf: fixture.localTouchLayout, encoding: .utf8)
    check(!presentationJSON.contains("jak1TouchLayoutOverride")
          && !presentationJSON.contains("modernMovement"),
          "touch-only writes never add Build 117 fields to the frozen presentation document")
    check(touchLayoutJSON.contains("jak1TouchLayoutOverride")
          && touchLayoutJSON.contains("modernMovement")
          && !touchLayoutJSON.contains("dynamicLeftStickOverride")
          && !touchLayoutJSON.contains("opacityPercent\":100")
          && touchLayoutJSON.contains("sizePercent\":100")
          && touchLayoutJSON.contains("sizePercent\":150"),
          "only customized touch fields occupy the Jak 1 sidecar")

    let restored = settings(fixture, writerID: "device-b", cloudAvailable: false)
    check(restored.jak1TouchLayout == value.jak1TouchLayout
          && restored.dynamicLeftStick,
          "the complete customized layout and dynamic opt-in survive local relaunch decoding")
    restored.resetTouchControl(.modernActions)
    check(restored.jak1TouchLayout.gestureAction(for: .up) == .cross
          && restored.jak1TouchLayout.opacity(for: .modernActions) == 1
          && restored.jak1TouchLayout.position(for: .modernMovement) != nil,
          "Reset Control restores only that control's safe defaults")
    restored.resetTouchLayout()
    check(restored.jak1TouchLayout == .standard
          && restored.touchLayoutDocument.jak1TouchLayoutOverride == nil
          && restored.dynamicLeftStick
          && readTouchLayoutDocument(at: fixture.localTouchLayout) != nil,
          "Reset Layout preserves the independent dynamic-stick preference")
    restored.setTouchControlPosition(NormalizedTouchPosition(x: 0.3, y: 0.7),
                                     for: .modernMovement)
    restored.setTouchControlSizePercent(125, for: .classicCross)
    restored.restoreDefaults(for: .controls)
    check(restored.jak1TouchLayout == .standard
          && restored.dynamicLeftStick
          && restored.touchLayoutDocument.dynamicLeftStickOverride == nil
          && readTouchLayoutDocument(at: fixture.localTouchLayout)?.jak1TouchLayout
            == .standard,
          "Restore Controls Defaults restores dynamic-left and both stick layouts")

    restored.setTouchControlSizePercent(145, for: .classicCamera)
    restored.setDynamicLeftStick(true)
    restored.resetAll()
    check(restored.jak1TouchLayout == .standard
          && restored.dynamicLeftStick
          && restored.touchLayoutDocument.dynamicLeftStickOverride == nil
          && readTouchLayoutDocument(at: fixture.localTouchLayout)?.jak1TouchLayout
            == .standard,
          "Reset Jak 1 Settings restores dynamic-left and both stick layouts")
}

@MainActor
private func explicitFreshResetBeatsOlderRemoteTouchLayout() async throws {
    print("an explicit fresh-device reset defeats an older remote customization")
    let fixture = try Fixture(name: "fresh-reset-tombstone")
    let clock = TestClock()
    var remoteLayout = TouchLayoutCustomization.standard
    remoteLayout.setPosition(NormalizedTouchPosition(x: 0.84, y: 0.28),
                             for: .modernCamera)
    let remote = Jak1TouchLayoutSettingsDocument(
        jak1TouchLayoutOverride: remoteLayout,
        modifiedAt: Date(timeIntervalSince1970: 2_100_000_000),
        writerID: "older-remote")
    try FileManager.default.createDirectory(
        at: fixture.cloudTouchLayout.deletingLastPathComponent(),
        withIntermediateDirectories: true)
    try JSONEncoder().encode(remote).write(to: fixture.cloudTouchLayout, options: .atomic)
    let configuration = PresentationSettingsConfiguration(
        localDocumentURL: fixture.local,
        cloudDocumentURL: { fixture.cloud },
        coordinateCloudAccess: false,
        now: { clock.now() })
    let value = PresentationSettings(defaults: fixture.defaults,
                                     configuration: configuration,
                                     writerID: "local-device")

    value.resetTouchLayout()
    let firstTombstoneData = try Data(contentsOf: fixture.localTouchLayout)
    let localTombstone = readTouchLayoutDocument(at: fixture.localTouchLayout)
    check(localTombstone?.jak1TouchLayoutOverride == nil
          && localTombstone?.writerID == "local-device"
          && localTombstone?.modifiedAt ?? .distantPast > remote.modifiedAt,
          "Reset Layout creates newer local authority even when the live value is already default")
    value.resetTouchLayout()
    let secondTombstoneData = try Data(contentsOf: fixture.localTouchLayout)
    check(secondTombstoneData == firstTombstoneData,
          "Reset Layout remains a no-op once a valid local nil tombstone exists")

    await value.prepare()
    check(value.jak1TouchLayout == .standard
          && readTouchLayoutDocument(at: fixture.localTouchLayout)?
            .jak1TouchLayoutOverride == nil
          && readTouchLayoutDocument(at: fixture.cloudTouchLayout)?
            .jak1TouchLayoutOverride == nil,
          "the explicit local tombstone wins locally and in cloud instead of resurrecting remote")
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
    check(value.graphicsStereo3D, "Modern Graphics begins with Stereoscopic 3D enabled")
    check(value.graphicsHighFrameRate, "Modern Graphics begins with ProMotion enabled")
    check(value.graphicsVisionHighFrameRate,
          "visionOS high refresh begins at 90 Hz independently of the profile")
    check(value.document.graphicsModernFillWidthOverride == nil,
          "the default uses the Modern option value instead of a stored override")
    check(value.document.graphicsModernStereo3DOverride == nil,
          "the stereo default does not require a stored override")
    check(value.cloudSyncEnabled, "settings cloud sync defaults on independently of saves")
}

@MainActor
private func highFrameRatePersistsAndResets() async throws {
    print("ProMotion follows the graphics profile and preserves explicit overrides")
    let fixture = try Fixture(name: "high-frame-rate")
    let value = settings(fixture, writerID: "device-a", cloudAvailable: false)
    check(value.graphicsHighFrameRate
          && value.document.graphicsHighFrameRateOverride == nil,
          "Modern enables ProMotion without storing an override")

    value.setProfile(.classic, for: .graphics)
    check(!value.graphicsHighFrameRate
          && value.document.graphicsHighFrameRateOverride == nil,
          "Classic disables ProMotion without storing an override")

    value.setGraphicsHighFrameRate(true)
    check(value.graphicsHighFrameRate
          && value.document.graphicsHighFrameRateOverride == true
          && readDocument(at: fixture.local)?.graphicsHighFrameRateOverride == true,
          "Classic can persist an explicit ProMotion opt-in")

    let restored = settings(fixture, writerID: "device-b", cloudAvailable: false)
    check(restored.profile(for: .graphics) == .classic && restored.graphicsHighFrameRate,
          "the Classic opt-in survives local relaunch decoding")

    restored.setGraphicsHighFrameRate(false)
    check(!restored.graphicsHighFrameRate
          && restored.document.graphicsHighFrameRateOverride == nil,
          "returning Classic to its off default clears the override")
    restored.setProfile(.modern, for: .graphics)
    restored.setGraphicsHighFrameRate(false)
    check(!restored.graphicsHighFrameRate
          && restored.document.graphicsHighFrameRateOverride == false
          && readDocument(at: fixture.local)?.graphicsHighFrameRateOverride == false,
          "Modern can persist an explicit ProMotion opt-out")

    restored.restoreDefaults(for: .graphics)
    check(restored.graphicsHighFrameRate
          && restored.document.graphicsHighFrameRateOverride == nil,
          "Restore Graphics Defaults returns Modern ProMotion to on")
    restored.setGraphicsHighFrameRate(false)
    restored.resetAll()
    check(restored.graphicsHighFrameRate
          && restored.document.graphicsHighFrameRateOverride == nil,
          "Reset All to Defaults restores Modern ProMotion")
}

@MainActor
private func visionHighFrameRatePersistsAndResets() async throws {
    print("visionOS 90 Hz remains independent of the iOS profile preference")
    let fixture = try Fixture(name: "vision-high-frame-rate")
    let value = settings(fixture, writerID: "device-a", cloudAvailable: false)
    check(value.graphicsVisionHighFrameRate
          && value.document.graphicsVisionHighFrameRateOverride == nil,
          "visionOS defaults to 90 Hz without storing an override")

    value.setProfile(.classic, for: .graphics)
    check(value.graphicsVisionHighFrameRate,
          "Classic keeps the independent visionOS 90 Hz default")
    value.setGraphicsVisionHighFrameRate(false)
    check(!value.graphicsVisionHighFrameRate
          && value.document.graphicsVisionHighFrameRateOverride == false
          && readDocument(at: fixture.local)?.graphicsVisionHighFrameRateOverride == false,
          "visionOS can persist a 60 Hz opt-out")

    let restored = settings(fixture, writerID: "device-b", cloudAvailable: false)
    check(!restored.graphicsVisionHighFrameRate,
          "the visionOS 60 Hz opt-out survives relaunch decoding")
    restored.setGraphicsVisionHighFrameRate(true)
    check(restored.graphicsVisionHighFrameRate
          && restored.document.graphicsVisionHighFrameRateOverride == nil,
          "returning to the 90 Hz default clears the override")
    restored.setGraphicsVisionHighFrameRate(false)
    restored.restoreDefaults(for: .graphics)
    check(restored.graphicsVisionHighFrameRate,
          "Restore Graphics Defaults returns visionOS to 90 Hz")
}

@MainActor
private func fitToScreenCanOverrideEitherProfile() async throws {
    print("shared Graphics controls can explicitly override either profile")
    let fixture = try Fixture(name: "fit-to-screen-profiles")
    let value = settings(fixture, writerID: "device-a", cloudAvailable: false)
    check(value.graphicsFillWidth
          && value.graphicsStereo3D
          && value.document.graphicsModernFillWidthOverride == nil
          && value.document.graphicsModernStereo3DOverride == nil,
          "Modern defaults its shared Graphics options on")

    value.setProfile(.classic, for: .graphics)
    check(!value.graphicsFillWidth && !value.graphicsStereo3D,
          "Classic defaults its shared Graphics options off")
    value.setGraphicsFillWidth(true)
    value.setGraphicsStereo3D(true)
    check(value.graphicsFillWidth
          && value.graphicsStereo3D
          && value.document.graphicsModernFillWidthOverride == true
          && value.document.graphicsModernStereo3DOverride == true,
          "Classic can persist explicit opt-ins from the same controls")

    value.setProfile(.modern, for: .graphics)
    check(value.graphicsFillWidth && value.graphicsStereo3D,
          "the explicit opt-ins remain active when returning to Modern")
    value.setGraphicsFillWidth(false)
    value.setGraphicsStereo3D(false)
    check(!value.graphicsFillWidth
          && !value.graphicsStereo3D
          && value.document.graphicsModernFillWidthOverride == false
          && value.document.graphicsModernStereo3DOverride == false,
          "Modern can persist explicit opt-outs from the same controls")

    value.setProfile(.classic, for: .graphics)
    value.setGraphicsFillWidth(false)
    value.setGraphicsStereo3D(false)
    check(!value.graphicsFillWidth
          && !value.graphicsStereo3D
          && value.document.graphicsModernFillWidthOverride == nil
          && value.document.graphicsModernStereo3DOverride == nil,
          "returning Classic to its off defaults clears both overrides")
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
          && !restoredClassic.graphicsFillWidth
          && !restoredClassic.graphicsStereo3D
          && !restoredClassic.graphicsHighFrameRate,
          "a saved Classic Graphics selection loads unchanged")

    let modernFixture = try Fixture(name: "saved-modern-override")
    var modern = PresentationSettingsDocument(writerID: "device-old")
    modern.graphicsModernFillWidthOverride = false
    modern.graphicsModernStereo3DOverride = false
    try FileManager.default.createDirectory(at: modernFixture.local.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try JSONEncoder().encode(modern).write(to: modernFixture.local, options: .atomic)
    let restoredModern = settings(modernFixture, writerID: "device-new")
    check(restoredModern.profile(for: .graphics) == .modern
          && !restoredModern.graphicsFillWidth
          && !restoredModern.graphicsStereo3D,
          "saved Modern graphics overrides load unchanged")
}

@MainActor
private func profilesCanBeMixedWithoutLosingOptions() async throws {
    print("section profiles are independent and preserve Modern options")
    let fixture = try Fixture(name: "mixed")
    let value = settings(fixture, writerID: "device-a", cloudAvailable: false)
    value.setProfile(.modern, for: .graphics)
    check(value.graphicsFillWidth, "Modern graphics defaults Fill Width on")
    check(value.graphicsStereo3D, "Modern graphics defaults Stereoscopic 3D on")
    check(value.graphicsHighFrameRate, "Modern graphics defaults ProMotion on")
    value.setGraphicsFillWidth(false)
    value.setGraphicsStereo3D(false)
    value.setProfile(.classic, for: .graphics)
    value.setProfile(.modern, for: .audio)
    check(value.globalProfile == nil, "different section profiles report Mixed")
    value.setProfile(.modern, for: .graphics)
    check(!value.graphicsFillWidth && !value.graphicsStereo3D,
          "switching profiles preserves customized Modern graphics values")

    value.restoreDefaults(for: .graphics)
    check(value.graphicsFillWidth && value.graphicsStereo3D,
          "graphics Restore Defaults returns Modern graphics options to on")
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
          && value.graphicsStereo3D
          && value.graphicsHighFrameRate
          && value.document.graphicsModernFillWidthOverride == nil
          && value.document.graphicsModernStereo3DOverride == nil,
          "Reset All restores the default Modern Graphics mix")
}

@MainActor
private func localOptOutDoesNotTouchCloud() async throws {
    print("settings cloud opt-out is local and leaves saves independent")
    let fixture = try Fixture(name: "optout")
    fixture.defaults.set(false, forKey: "iCloudPresentationSettingsSyncEnabled")
    let value = settings(fixture, writerID: "device-a")
    value.setProfile(.modern, for: .graphics)
    value.setTouchControlSizePercent(135, for: .classicCross)
    check(!value.cloudSyncEnabled, "local opt-out is restored")
    check(!FileManager.default.fileExists(atPath: fixture.cloud.path)
          && !FileManager.default.fileExists(atPath: fixture.cloudTouchLayout.path),
          "local opt-out creates neither cloud settings document")
    check(readDocument(at: fixture.local)?.graphicsProfile == .modern,
          "local opt-out still persists the selected section")
    check(readTouchLayoutDocument(at: fixture.localTouchLayout)?
            .jak1TouchLayout.scale(for: .classicCross) == 1.35,
          "local opt-out still persists touch customization in its local sidecar")
}

@MainActor
private func cloudSettingsAndTouchLayoutConverge() async throws {
    print("presentation settings and the isolated touch document sync under one gate")
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
    first.setGraphicsStereo3D(false)
    first.setGraphicsHighFrameRate(false)
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
    check(!second.graphicsFillWidth && !second.graphicsStereo3D,
          "the second device receives the customized Modern options")
    check(!second.graphicsHighFrameRate
          && second.document.graphicsHighFrameRateOverride == false,
          "the second device receives the persisted Modern ProMotion opt-out")
    check(second.jak1InputBindings.action(for: .buttonA) == .square
          && second.jak1InputBindings.action(for: .buttonX) == .cross
          && second.jak1InputBindings.action(for: .spacebar) == .stats
          && second.jak1InputBindings.action(for: .tab) == .cross
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
          "the second device receives the separate complete touch layout document")

    first.resetTouchLayout()
    await first.syncNow()
    await second.syncNow()
    check(second.jak1TouchLayout == .standard
          && readTouchLayoutDocument(at: fixtureA.cloudTouchLayout)?
            .jak1TouchLayoutOverride == nil,
          "a synced nil sidecar tombstone clears a previously customized layout")
}

@MainActor
private func legacyCloudRewriteCannotEraseTouchLayout() async throws {
    print("a staggered Build 116 client cannot erase Build 117 touch layout")
    let fixtureA = try Fixture(name: "staggered-cloud-a")
    let fixtureB = try Fixture(name: "staggered-cloud-b")
    let sharedCloud = fixtureA.cloud
    let configurationA = PresentationSettingsConfiguration(
        localDocumentURL: fixtureA.local,
        cloudDocumentURL: { sharedCloud },
        coordinateCloudAccess: false)
    let configurationB = PresentationSettingsConfiguration(
        localDocumentURL: fixtureB.local,
        cloudDocumentURL: { sharedCloud },
        coordinateCloudAccess: false)
    let current = PresentationSettings(defaults: fixtureA.defaults,
                                       configuration: configurationA,
                                       writerID: "build117-device")
    await current.prepare()
    current.setTouchControlPosition(NormalizedTouchPosition(x: 0.77, y: 0.31),
                                    for: .modernCamera)
    current.setTouchControlOpacityPercent(65, for: .classicStats)
    await current.syncNow()

    let touchBeforeRewrite = try Data(contentsOf: fixtureA.cloudTouchLayout)
    var oldClient = try JSONDecoder().decode(Build116PresentationDocument.self,
                                             from: Data(contentsOf: sharedCloud))
    oldClient.audioProfile = .modern
    oldClient.modifiedAt = Date(timeIntervalSince1970: 4_000_000_000)
    oldClient.writerID = "build116-device"
    let oldRewrite = try JSONEncoder().encode(oldClient)
    try oldRewrite.write(to: sharedCloud, options: .atomic)

    check(!String(decoding: oldRewrite, as: UTF8.self)
            .contains("jak1TouchLayoutOverride"),
          "the Build 116-shaped writer drops every unknown presentation key")
    let touchAfterRewrite = try Data(contentsOf: fixtureA.cloudTouchLayout)
    check(touchAfterRewrite == touchBeforeRewrite,
          "rewriting presentation-v1 leaves jak1-touch-layout-v1 byte-identical")

    let newer = PresentationSettings(defaults: fixtureB.defaults,
                                     configuration: configurationB,
                                     writerID: "new-device")
    await newer.prepare()
    check(newer.profile(for: .audio) == .modern,
          "the newer client still accepts the old client's presentation update")
    check(newer.jak1TouchLayout.position(for: .modernCamera)
            == NormalizedTouchPosition(x: 0.77, y: 0.31)
          && newer.jak1TouchLayout.opacity(for: .classicStats) == 0.65,
          "the newer client independently reapplies the untouched touch sidecar")
}

@MainActor
private func presentationEditSurvivesSuspendedTouchWrite() async throws {
    print("a presentation edit survives a suspended touch-sidecar cloud write")
    let fixture = try Fixture(name: "suspended-touch-write")
    let clock = TestClock()
    var remotePresentation = PresentationSettingsDocument(
        modifiedAt: Date(timeIntervalSince1970: 2_000_000_000),
        writerID: "remote-device")
    remotePresentation.audioProfile = .modern
    var localLayout = TouchLayoutCustomization.standard
    localLayout.setSizePercent(140, for: .classicCamera)
    let localTouchDocument = Jak1TouchLayoutSettingsDocument(
        jak1TouchLayoutOverride: localLayout,
        modifiedAt: Date(timeIntervalSince1970: 2_100_000_000),
        writerID: "local-device")
    try FileManager.default.createDirectory(
        at: fixture.localTouchLayout.deletingLastPathComponent(),
        withIntermediateDirectories: true)
    try JSONEncoder().encode(localTouchDocument)
        .write(to: fixture.localTouchLayout, options: .atomic)
    let configuration = PresentationSettingsConfiguration(
        localDocumentURL: fixture.local,
        cloudDocumentURL: { fixture.cloud },
        coordinateCloudAccess: false,
        now: { clock.now() })
    let cloudStore = DelayedCloudStore(url: fixture.cloud,
                                       initialDocument: remotePresentation,
                                       delayWrites: false,
                                       delayTouchWrites: true)
    let value = PresentationSettings(defaults: fixture.defaults,
                                     configuration: configuration,
                                     writerID: "local-device",
                                     cloudStore: cloudStore)

    let sync = Task { await value.syncNow() }
    await cloudStore.waitUntilTouchWriteStarts(1)
    value.setGraphicsFillWidth(false)
    check(value.profile(for: .audio) == .modern && !value.graphicsFillWidth,
          "the concurrent edit builds on the already-applied remote presentation winner")
    let released = await cloudStore.releaseTouchWrite(1)
    check(released, "the deterministic store releases the suspended sidecar write")
    await sync.value

    let storedPresentation = await cloudStore.storedValue()
    let storedTouchLayout = await cloudStore.storedTouchValue()
    check(value.profile(for: .audio) == .modern
          && !value.graphicsFillWidth
          && storedPresentation == value.document,
          "no stale presentation winner overwrites the edit after the touch await resumes")
    check(storedTouchLayout?.jak1TouchLayout == localLayout,
          "the suspended sidecar write still converges with the presentation revision loop")
}

@MainActor
private func changeDuringCloudWriteQueuesNewestDocument() async throws {
    print("a local change during an in-flight cloud write queues a complete second pass")
    let fixture = try Fixture(name: "delayed-cloud-write")
    let clock = TestClock()
    let configuration = PresentationSettingsConfiguration(
        localDocumentURL: fixture.local,
        cloudDocumentURL: { fixture.cloud },
        coordinateCloudAccess: false,
        now: { clock.now() })
    let cloudStore = DelayedCloudStore(url: fixture.cloud)
    let value = PresentationSettings(defaults: fixture.defaults,
                                     configuration: configuration,
                                     writerID: "device-a",
                                     cloudStore: cloudStore)

    let firstSync = Task { await value.syncNow() }
    await cloudStore.waitUntilWriteStarts(1)
    check(value.syncStatus == .syncing && value.lastSyncDate == nil,
          "the first delayed cloud write remains Syncing rather than Up to date")

    value.setGraphicsFillWidth(false)
    value.setProfile(.modern, for: .audio)
    let firstPending = await cloudStore.pendingWrite()
    check(firstPending?.graphicsModernFillWidthOverride == nil
          && firstPending?.audioProfile == .classic,
          "the in-flight write is the older document snapshot")
    let releasedFirst = await cloudStore.releaseWrite(1)
    check(releasedFirst, "the deterministic store releases the first write")

    await cloudStore.waitUntilWriteStarts(2)
    let newestPending = await cloudStore.pendingWrite()
    check(newestPending?.graphicsModernFillWidthOverride == false
          && newestPending?.audioProfile == .modern,
          "the queued pass writes the newest complete presentation document")
    check(value.syncStatus == .syncing && value.lastSyncDate == nil,
          "status stays Syncing until the newest document finishes writing")
    let releasedSecond = await cloudStore.releaseWrite(2)
    check(releasedSecond, "the deterministic store releases the newest write")
    await firstSync.value

    let stored = await cloudStore.storedValue()
    let isSynced: Bool
    if case .synced = value.syncStatus { isSynced = true } else { isSynced = false }
    check(stored == value.document && isSynced && value.lastSyncDate != nil,
          "only the newest stored document advances status to Up to date")
}

@MainActor
private func changeDuringCloudReadQueuesAnotherPass() async throws {
    print("a local change during an in-flight cloud read queues another complete pass")
    let fixture = try Fixture(name: "delayed-cloud-read")
    let clock = TestClock()
    let configuration = PresentationSettingsConfiguration(
        localDocumentURL: fixture.local,
        cloudDocumentURL: { fixture.cloud },
        coordinateCloudAccess: false,
        now: { clock.now() })
    let cloudStore = DelayedCloudStore(url: fixture.cloud,
                                       delayFirstRead: true, delayWrites: false)
    let value = PresentationSettings(defaults: fixture.defaults,
                                     configuration: configuration,
                                     writerID: "device-a",
                                     cloudStore: cloudStore)

    let firstSync = Task { await value.syncNow() }
    await cloudStore.waitUntilReadStarts(1)
    value.setGraphicsFillWidth(false)
    check(value.syncStatus == .syncing && value.lastSyncDate == nil,
          "a change during the delayed read cannot publish Up to date")
    let released = await cloudStore.releaseRead(1)
    check(released, "the deterministic store releases the first read")
    await firstSync.value

    let reads = await cloudStore.completedReadCount()
    let stored = await cloudStore.storedValue()
    let isSynced: Bool
    if case .synced = value.syncStatus { isSynced = true } else { isSynced = false }
    check(reads == 2,
          "the local revision change forces a second cloud read pass")
    check(stored?.graphicsModernFillWidthOverride == false
          && stored == value.document && isSynced,
          "the read-race pass stores the newest document before publishing Up to date")
}

@MainActor
private func inFlightOptOutAndCloudErrorsRemainExplicit() async throws {
    print("in-flight opt-out and cloud failures retain their explicit status behavior")
    let optOutFixture = try Fixture(name: "in-flight-opt-out")
    let delayedRead = DelayedCloudStore(url: optOutFixture.cloud,
                                        delayFirstRead: true, delayWrites: false)
    let optOut = PresentationSettings(
        defaults: optOutFixture.defaults,
        configuration: optOutFixture.configuration(),
        writerID: "device-a",
        cloudStore: delayedRead)
    let optOutSync = Task { await optOut.syncNow() }
    await delayedRead.waitUntilReadStarts(1)
    optOut.cloudSyncEnabled = false
    let released = await delayedRead.releaseRead(1)
    check(released, "the deterministic store releases the opted-out read")
    await optOutSync.value
    let optOutStored = await delayedRead.storedValue()
    check(optOut.syncStatus == .disabled && optOutStored == nil,
          "opting out during a read stops writes and leaves status Off")

    let failureFixture = try Fixture(name: "cloud-error")
    let remote = PresentationSettingsDocument(writerID: "remote")
    try FileManager.default.createDirectory(
        at: failureFixture.cloud.deletingLastPathComponent(),
        withIntermediateDirectories: true)
    try JSONEncoder().encode(remote).write(to: failureFixture.cloud, options: .atomic)
    let failureConfiguration = PresentationSettingsConfiguration(
        localDocumentURL: failureFixture.local,
        cloudDocumentURL: { failureFixture.cloud },
        coordinateCloudAccess: false,
        cloudConflictDocumentData: { _ in throw TestCloudError() })
    let failed = PresentationSettings(defaults: failureFixture.defaults,
                                      configuration: failureConfiguration,
                                      writerID: "device-a")
    await failed.syncNow()
    let isFailed: Bool
    if case .failed(let message) = failed.syncStatus {
        isFailed = message.contains("intentional cloud test failure")
    } else {
        isFailed = false
    }
    check(isFailed, "a cloud-store error remains an actionable failed status")
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

@MainActor
private func unresolvedTouchSidecarVersionParticipatesInConflictResolution() async throws {
    print("unresolved touch sidecar versions use the same deterministic merge")
    let fixture = try Fixture(name: "touch-file-version-conflict")
    let date = Date(timeIntervalSince1970: 2_150_000_000)
    var currentLayout = TouchLayoutCustomization.standard
    currentLayout.setSizePercent(125, for: .classicCross)
    let current = Jak1TouchLayoutSettingsDocument(
        jak1TouchLayoutOverride: currentLayout,
        modifiedAt: date,
        writerID: "device-a")
    var conflictLayout = TouchLayoutCustomization.standard
    conflictLayout.setOpacityPercent(55, for: .classicStats)
    let conflict = Jak1TouchLayoutSettingsDocument(
        jak1TouchLayoutOverride: conflictLayout,
        dynamicLeftStickOverride: true,
        modifiedAt: date,
        writerID: "device-z")
    try FileManager.default.createDirectory(at: fixture.cloud.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try JSONEncoder().encode(PresentationSettingsDocument(writerID: "remote"))
        .write(to: fixture.cloud, options: .atomic)
    try JSONEncoder().encode(current).write(to: fixture.cloudTouchLayout, options: .atomic)
    let conflictData = try JSONEncoder().encode(conflict)
    let configuration = PresentationSettingsConfiguration(
        localDocumentURL: fixture.local,
        cloudDocumentURL: { fixture.cloud },
        coordinateCloudAccess: false,
        cloudConflictDocumentData: { url in
            url.lastPathComponent == "jak1-touch-layout-v1.json" ? [conflictData] : []
        })
    let value = PresentationSettings(defaults: fixture.defaults,
                                     configuration: configuration,
                                     writerID: "device-local")
    await value.syncNow()
    check(value.jak1TouchLayout == conflictLayout && value.dynamicLeftStick,
          "the highest-ranked unresolved touch sidecar becomes the live layout")
    check(readTouchLayoutDocument(at: fixture.cloudTouchLayout)?.writerID == "device-z",
          "the touch conflict winner replaces the current cloud sidecar")
}

@main
private struct PresentationSettingsCheck {
    static func main() async {
        do {
            try await legacyDocumentAndPickerOrderingRemainCompatible()
            try await embeddedBuild117TouchLayoutMigratesBeforeLegacyRewrite()
            try await embeddedCloudBuild117TouchLayoutMigratesToSidecar()
            try await developerLogsPersistAndReset()
            try await primaryInputSourcePersistsAndResets()
            try await inputBindingsPersistSyncAndReset()
            try await legacyTouchLayoutSidecarPersistsAcrossPresentationResets()
            try await explicitFreshResetBeatsOlderRemoteTouchLayout()
            try await defaultsUseModernGraphics()
            try await highFrameRatePersistsAndResets()
            try await visionHighFrameRatePersistsAndResets()
            try await fitToScreenCanOverrideEitherProfile()
            try await savedChoicesSurviveNewDefaults()
            try await profilesCanBeMixedWithoutLosingOptions()
            try await localOptOutDoesNotTouchCloud()
            try await cloudSettingsAndTouchLayoutConverge()
            try await legacyCloudRewriteCannotEraseTouchLayout()
            try await presentationEditSurvivesSuspendedTouchWrite()
            try await changeDuringCloudReadQueuesAnotherPass()
            try await changeDuringCloudWriteQueuesNewestDocument()
            try await inFlightOptOutAndCloudErrorsRemainExplicit()
            try await coordinatedFirstCloudWriteCreatesItsNestedDocument()
            try await newerCloudDocumentWinsDeterministically()
            try await unresolvedCloudVersionParticipatesInConflictResolution()
            try await unresolvedTouchSidecarVersionParticipatesInConflictResolution()
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
