import Foundation

nonisolated enum SettingsProfile: String, CaseIterable, Codable, Sendable {
    case modern
    case classic

    var title: String { rawValue.capitalized }
}

nonisolated enum SettingsSection: CaseIterable, Codable, Sendable {
    case controls
    case graphics
    case audio
    case interface

    var title: String {
        switch self {
        case .controls: "Controls"
        case .graphics: "Graphics"
        case .audio: "Audio"
        case .interface: "UI"
        }
    }
}

nonisolated struct PresentationSettingsDocument: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    var schemaVersion = Self.schemaVersion
    var controlsProfile: SettingsProfile = .classic
    var graphicsProfile: SettingsProfile = .modern
    var audioProfile: SettingsProfile = .classic
    var interfaceProfile: SettingsProfile = .classic

    /// `nil` means the selected profile's default. This option belongs to Modern, whose default is
    /// enabled; Classic always uses the preserved compatibility view.
    var graphicsModernFillWidthOverride: Bool?
    /// Optional so existing same-schema documents decode unchanged. Modern uses stereoscopic
    /// window rendering by default on visionOS; Classic and an explicit opt-out use Comfort.
    var graphicsModernStereo3DOverride: Bool?
    /// Optional so Build 93 settings documents decode without a migration. Developer logs are
    /// hidden by default and belong to this title's synced settings document.
    var developerLogsEnabledOverride: Bool?
    /// Optional so existing documents inherit the default-on gameplay rumble behavior.
    var rumbleEnabledOverride: Bool?
    /// Optional for compatibility with Build 93 documents. Automatic preserves the accepted
    /// activity-driven source selection while explicit choices follow the player across devices.
    var primaryInputSourceOverride: PrimaryInputSource?
    /// Optional so every existing title-scoped document decodes as the exact established mapping.
    /// Only customized Jak 1 physical-input bindings need to occupy the synced document.
    var jak1InputBindingsOverride: Jak1InputBindings?
    var modifiedAt: Date
    var writerID: String

    init(modifiedAt: Date = Date(), writerID: String) {
        self.modifiedAt = modifiedAt
        self.writerID = writerID
    }

    func profile(for section: SettingsSection) -> SettingsProfile {
        switch section {
        case .controls: controlsProfile
        case .graphics: graphicsProfile
        case .audio: audioProfile
        case .interface: interfaceProfile
        }
    }

    mutating func setProfile(_ profile: SettingsProfile, for section: SettingsSection) {
        switch section {
        case .controls: controlsProfile = profile
        case .graphics: graphicsProfile = profile
        case .audio: audioProfile = profile
        case .interface: interfaceProfile = profile
        }
    }

    var globalProfile: SettingsProfile? {
        let profiles = SettingsSection.allCases.map { profile(for: $0) }
        guard let first = profiles.first, profiles.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    var graphicsFillWidth: Bool {
        guard graphicsProfile == .modern else { return false }
        return graphicsModernFillWidthOverride ?? true
    }

    var graphicsStereo3D: Bool {
        guard graphicsProfile == .modern else { return false }
        return graphicsModernStereo3DOverride ?? true
    }

    var developerLogsEnabled: Bool {
        developerLogsEnabledOverride ?? false
    }

    var rumbleEnabled: Bool {
        rumbleEnabledOverride ?? true
    }

    var primaryInputSource: PrimaryInputSource {
        primaryInputSourceOverride ?? .automatic
    }

    var jak1InputBindings: Jak1InputBindings {
        jak1InputBindingsOverride ?? .standard
    }

    mutating func restoreDefaults(for section: SettingsSection) {
        switch section {
        case .graphics:
            graphicsModernFillWidthOverride = nil
            graphicsModernStereo3DOverride = nil
        case .controls:
            primaryInputSourceOverride = nil
            jak1InputBindingsOverride = nil
        case .audio, .interface:
            break
        }
    }

    mutating func resetAll() {
        controlsProfile = .classic
        graphicsProfile = .modern
        audioProfile = .classic
        interfaceProfile = .classic
        graphicsModernFillWidthOverride = nil
        graphicsModernStereo3DOverride = nil
        developerLogsEnabledOverride = nil
        rumbleEnabledOverride = nil
        primaryInputSourceOverride = nil
        jak1InputBindingsOverride = nil
    }
}

/// Frozen outside `presentation-v1.json` so an older same-schema writer cannot erase it.
nonisolated struct Jak1TouchLayoutSettingsDocument: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    var schemaVersion = Self.schemaVersion
    var jak1TouchLayoutOverride: TouchLayoutCustomization?
    var dynamicLeftStickOverride: Bool?
    var modifiedAt: Date
    var writerID: String

    init(jak1TouchLayoutOverride: TouchLayoutCustomization? = nil,
         dynamicLeftStickOverride: Bool? = nil,
         modifiedAt: Date = Date(), writerID: String) {
        self.jak1TouchLayoutOverride = jak1TouchLayoutOverride
        self.dynamicLeftStickOverride = dynamicLeftStickOverride
        self.modifiedAt = modifiedAt
        self.writerID = writerID
    }

    var jak1TouchLayout: TouchLayoutCustomization {
        jak1TouchLayoutOverride ?? .standard
    }

    var dynamicLeftStick: Bool {
        dynamicLeftStickOverride ?? true
    }
}

private struct EmbeddedJak1TouchLayoutDocument: Decodable {
    let schemaVersion: Int
    let jak1TouchLayoutOverride: TouchLayoutCustomization?
    let modifiedAt: Date
    let writerID: String
}

private extension Jak1TouchLayoutSettingsDocument {
    init?(migratingEmbeddedData data: Data) {
        guard let embedded = try? JSONDecoder().decode(EmbeddedJak1TouchLayoutDocument.self,
                                                       from: data),
              embedded.schemaVersion == PresentationSettingsDocument.schemaVersion,
              let layout = embedded.jak1TouchLayoutOverride else {
            return nil
        }
        self.init(jak1TouchLayoutOverride: layout,
                  modifiedAt: embedded.modifiedAt,
                  writerID: embedded.writerID)
    }
}

nonisolated struct PresentationSettingsConfiguration: Sendable {
    let localDocumentURL: URL
    let cloudDocumentURL: @Sendable () -> URL?
    let coordinateCloudAccess: Bool
    let cloudConflictDocumentData: @Sendable (URL) throws -> [Data]
    let now: @Sendable () -> Date

    init(localDocumentURL: URL, cloudDocumentURL: @escaping @Sendable () -> URL?,
         coordinateCloudAccess: Bool,
         cloudConflictDocumentData: @escaping @Sendable (URL) throws -> [Data] = { _ in [] },
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.localDocumentURL = localDocumentURL
        self.cloudDocumentURL = cloudDocumentURL
        self.coordinateCloudAccess = coordinateCloudAccess
        self.cloudConflictDocumentData = cloudConflictDocumentData
        self.now = now
    }

    var localTouchLayoutDocumentURL: URL {
        localDocumentURL.deletingLastPathComponent()
            .appending(path: "jak1-touch-layout-v1.json", directoryHint: .notDirectory)
    }

    func cloudTouchLayoutDocumentURL() -> URL? {
        cloudDocumentURL()?.deletingLastPathComponent()
            .appending(path: "jak1-touch-layout-v1.json", directoryHint: .notDirectory)
    }
}

nonisolated enum PresentationSettingsLayout {
    static var applicationSupportDirectory: URL {
        (try? FileManager.default.url(for: .applicationSupportDirectory,
                                      in: .userDomainMask, appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appending(path: "Library/Application Support", directoryHint: .isDirectory)
    }

    static var localDocumentURL: URL {
        applicationSupportDirectory
            .appending(path: "GOALPad/Settings/presentation-v1.json", directoryHint: .notDirectory)
    }

    static func cloudDocumentURL() -> URL? {
        let manager = FileManager.default
        guard manager.ubiquityIdentityToken != nil,
              let container = manager.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        return container
            .appending(path: "Documents/GOALPad/Settings", directoryHint: .isDirectory)
            .appending(path: "presentation-v1.json", directoryHint: .notDirectory)
    }

    static func unresolvedConflictData(at url: URL) throws -> [Data] {
        try (NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).map {
            try Data(contentsOf: $0.url)
        }
    }

    static func resolveConflicts(at url: URL) throws {
        let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
        guard !conflicts.isEmpty else { return }
        for conflict in conflicts {
            conflict.isResolved = true
        }
        try NSFileVersion.removeOtherVersionsOfItem(at: url)
    }
}

nonisolated struct PresentationSettingsCloudState: Sendable {
    let url: URL
    let document: PresentationSettingsDocument?
    let hasConflicts: Bool
    let touchLayoutURL: URL
    let touchLayoutDocument: Jak1TouchLayoutSettingsDocument?
    let touchLayoutFileExists: Bool
    let touchLayoutHasConflicts: Bool
    let embeddedTouchLayoutDocument: Jak1TouchLayoutSettingsDocument?

    init(url: URL, document: PresentationSettingsDocument?, hasConflicts: Bool,
         touchLayoutURL: URL? = nil,
         touchLayoutDocument: Jak1TouchLayoutSettingsDocument? = nil,
         touchLayoutFileExists: Bool = false,
         touchLayoutHasConflicts: Bool = false,
         embeddedTouchLayoutDocument: Jak1TouchLayoutSettingsDocument? = nil) {
        self.url = url
        self.document = document
        self.hasConflicts = hasConflicts
        self.touchLayoutURL = touchLayoutURL ?? url.deletingLastPathComponent()
            .appending(path: "jak1-touch-layout-v1.json", directoryHint: .notDirectory)
        self.touchLayoutDocument = touchLayoutDocument
        self.touchLayoutFileExists = touchLayoutFileExists
        self.touchLayoutHasConflicts = touchLayoutHasConflicts
        self.embeddedTouchLayoutDocument = embeddedTouchLayoutDocument
    }
}

nonisolated protocol PresentationSettingsCloudStoring: Sendable {
    func read() async throws -> PresentationSettingsCloudState?
    func write(_ document: PresentationSettingsDocument, to url: URL) async throws
    func write(_ document: Jak1TouchLayoutSettingsDocument, to url: URL) async throws
}

private actor PresentationSettingsCloudStore: PresentationSettingsCloudStoring {
    private let configuration: PresentationSettingsConfiguration
    private let manager = FileManager.default

    init(configuration: PresentationSettingsConfiguration) {
        self.configuration = configuration
    }

    func read() async throws -> PresentationSettingsCloudState? {
        guard let url = configuration.cloudDocumentURL() else { return nil }
        let touchLayoutURL = configuration.cloudTouchLayoutDocumentURL()
            ?? url.deletingLastPathComponent()
                .appending(path: "jak1-touch-layout-v1.json", directoryHint: .notDirectory)

        var presentationCandidates: [(document: PresentationSettingsDocument,
                                      embedded: Jak1TouchLayoutSettingsDocument?)] = []
        var presentationConflictData: [Data] = []
        if manager.fileExists(atPath: url.path) {
            try await ensureDocumentIsCurrent(at: url)
            let primaryData = try readData(at: url)
            presentationConflictData = try configuration.cloudConflictDocumentData(url)
            presentationCandidates = ([primaryData] + presentationConflictData).compactMap { data in
                guard let value = try? JSONDecoder().decode(PresentationSettingsDocument.self,
                                                            from: data),
                      value.schemaVersion == PresentationSettingsDocument.schemaVersion else {
                    return nil
                }
                return (value, Jak1TouchLayoutSettingsDocument(migratingEmbeddedData: data))
            }
        }

        let presentationWinner = presentationCandidates.max { lhs, rhs in
            if lhs.document.modifiedAt != rhs.document.modifiedAt {
                return lhs.document.modifiedAt < rhs.document.modifiedAt
            }
            return lhs.document.writerID < rhs.document.writerID
        }

        var touchLayoutDocuments: [Jak1TouchLayoutSettingsDocument] = []
        var touchLayoutConflictData: [Data] = []
        let touchLayoutFileExists = manager.fileExists(atPath: touchLayoutURL.path)
        if touchLayoutFileExists {
            try await ensureDocumentIsCurrent(at: touchLayoutURL)
            let primaryData = try readData(at: touchLayoutURL)
            touchLayoutConflictData = try configuration.cloudConflictDocumentData(touchLayoutURL)
            touchLayoutDocuments = ([primaryData] + touchLayoutConflictData).compactMap { data in
                guard let value = try? JSONDecoder().decode(Jak1TouchLayoutSettingsDocument.self,
                                                            from: data),
                      value.schemaVersion == Jak1TouchLayoutSettingsDocument.schemaVersion else {
                    return nil
                }
                return value
            }
        }
        let touchLayoutWinner = touchLayoutDocuments.max { lhs, rhs in
            if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt < rhs.modifiedAt }
            return lhs.writerID < rhs.writerID
        }

        return PresentationSettingsCloudState(
            url: url,
            document: presentationWinner?.document,
            hasConflicts: !presentationConflictData.isEmpty,
            touchLayoutURL: touchLayoutURL,
            touchLayoutDocument: touchLayoutWinner,
            touchLayoutFileExists: touchLayoutFileExists,
            touchLayoutHasConflicts: !touchLayoutConflictData.isEmpty,
            embeddedTouchLayoutDocument: presentationWinner?.embedded)
    }

    func write(_ document: PresentationSettingsDocument, to url: URL) async throws {
        try writeData(JSONEncoder().encode(document), to: url)
    }

    func write(_ document: Jak1TouchLayoutSettingsDocument, to url: URL) async throws {
        try writeData(JSONEncoder().encode(document), to: url)
    }

    private func writeData(_ data: Data, to url: URL) throws {
        guard configuration.coordinateCloudAccess else {
            try manager.createDirectory(at: url.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return
        }
        try coordinatedWrite(at: url, replacing: true) { [manager] coordinatedURL in
            try manager.createDirectory(at: coordinatedURL.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
            try data.write(to: coordinatedURL, options: .atomic)
        }
        try PresentationSettingsLayout.resolveConflicts(at: url)
    }

    private func readData(at url: URL) throws -> Data {
        guard configuration.coordinateCloudAccess else { return try Data(contentsOf: url) }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var readResult: Result<Data, Error>?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) {
            coordinatedURL in
            readResult = Result { try Data(contentsOf: coordinatedURL) }
        }
        if let coordinationError { throw coordinationError }
        guard let readResult else { throw CocoaError(.fileReadUnknown) }
        return try readResult.get()
    }

    private func ensureDocumentIsCurrent(at url: URL) async throws {
        let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey,
                                                       .ubiquitousItemDownloadingStatusKey])
        guard values.isUbiquitousItem == true,
              values.ubiquitousItemDownloadingStatus != .current else { return }
        try manager.startDownloadingUbiquitousItem(at: url)
        for _ in 0..<600 {
            try await Task.sleep(for: .milliseconds(100))
            let current = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if current.ubiquitousItemDownloadingStatus == .current { return }
        }
        throw CocoaError(.fileReadNoSuchFile)
    }

    /// File coordination cannot target a nested item that does not exist yet. Coordinate the
    /// nearest existing ancestor, then rebuild the intended destination below its coordinated URL.
    private func coordinatedWrite(at destination: URL, replacing: Bool,
                                  _ operation: (URL) throws -> Void) throws {
        let destinationExists = manager.fileExists(atPath: destination.path)
        var coordinatedItem = destination
        while !manager.fileExists(atPath: coordinatedItem.path),
              coordinatedItem.pathComponents.count > 1 {
            coordinatedItem.deleteLastPathComponent()
        }
        let relativeComponents = destination.pathComponents
            .dropFirst(coordinatedItem.pathComponents.count)
        let options: NSFileCoordinator.WritingOptions = destinationExists && replacing
            ? .forReplacing : []
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var operationError: Error?
        coordinator.coordinate(writingItemAt: coordinatedItem, options: options,
                               error: &coordinationError) { coordinatedURL in
            let resolvedDestination = relativeComponents.reduce(coordinatedURL) {
                $0.appending(path: $1)
            }
            do { try operation(resolvedDestination) } catch { operationError = error }
        }
        if let coordinationError { throw coordinationError }
        if let operationError { throw operationError }
    }
}

@MainActor
@Observable
final class PresentationSettings {
    enum SyncStatus: Equatable {
        case disabled
        case waiting
        case syncing
        case unavailable
        case synced(Date)
        case failed(String)
    }

    private static let cloudSyncEnabledKey = "iCloudPresentationSettingsSyncEnabled"
    private static let writerIDKey = "presentationSettingsWriterID"

    var cloudSyncEnabled: Bool {
        didSet {
            defaults.set(cloudSyncEnabled, forKey: Self.cloudSyncEnabledKey)
            if cloudSyncEnabled {
                syncStatus = .waiting
                Task { [weak self] in await self?.syncNow() }
            } else {
                syncStatus = .disabled
            }
        }
    }

    private(set) var syncStatus: SyncStatus
    private(set) var document: PresentationSettingsDocument
    private(set) var touchLayoutDocument: Jak1TouchLayoutSettingsDocument
    private(set) var lastSuccessfulSyncDate: Date?

    private let defaults: UserDefaults
    private let configuration: PresentationSettingsConfiguration
    private let cloudStore: any PresentationSettingsCloudStoring
    private let localWriterID: String
    private let manager = FileManager.default
    private var hasLocalDocument: Bool
    private var hasLocalTouchLayoutDocument: Bool
    private var isSyncing = false
    private var syncRequested = false
    private var documentRevision: UInt64 = 0

    init(defaults: UserDefaults = .standard,
         configuration: PresentationSettingsConfiguration? = nil,
         writerID: String? = nil,
         cloudStore: (any PresentationSettingsCloudStoring)? = nil) {
        self.defaults = defaults
        let storedWriterID = writerID ?? defaults.string(forKey: Self.writerIDKey) ?? UUID().uuidString
        if writerID == nil, defaults.string(forKey: Self.writerIDKey) == nil {
            defaults.set(storedWriterID, forKey: Self.writerIDKey)
        }
        localWriterID = storedWriterID
        let resolvedConfiguration = configuration ?? PresentationSettingsConfiguration(
            localDocumentURL: PresentationSettingsLayout.localDocumentURL,
            cloudDocumentURL: { PresentationSettingsLayout.cloudDocumentURL() },
            coordinateCloudAccess: true,
            cloudConflictDocumentData: { try PresentationSettingsLayout.unresolvedConflictData(at: $0) })
        self.configuration = resolvedConfiguration
        self.cloudStore = cloudStore
            ?? PresentationSettingsCloudStore(configuration: resolvedConfiguration)
        let localPresentationData = try? Data(contentsOf: self.configuration.localDocumentURL)
        if let data = localPresentationData,
           let stored = try? JSONDecoder().decode(PresentationSettingsDocument.self, from: data),
           stored.schemaVersion == PresentationSettingsDocument.schemaVersion {
            document = stored
            hasLocalDocument = true
        } else {
            document = PresentationSettingsDocument(modifiedAt: self.configuration.now(),
                                                    writerID: storedWriterID)
            hasLocalDocument = false
        }
        let localTouchLayoutFileExists = FileManager.default.fileExists(
            atPath: self.configuration.localTouchLayoutDocumentURL.path)
        if let data = try? Data(contentsOf: self.configuration.localTouchLayoutDocumentURL),
           let stored = try? JSONDecoder().decode(Jak1TouchLayoutSettingsDocument.self, from: data),
           stored.schemaVersion == Jak1TouchLayoutSettingsDocument.schemaVersion {
            touchLayoutDocument = stored
            hasLocalTouchLayoutDocument = true
        } else if !localTouchLayoutFileExists, let localPresentationData,
                  let migrated = Jak1TouchLayoutSettingsDocument(
                    migratingEmbeddedData: localPresentationData) {
            touchLayoutDocument = migrated
            hasLocalTouchLayoutDocument = true
        } else {
            touchLayoutDocument = Jak1TouchLayoutSettingsDocument(
                modifiedAt: self.configuration.now(), writerID: storedWriterID)
            hasLocalTouchLayoutDocument = false
        }
        let enabled = defaults.object(forKey: Self.cloudSyncEnabledKey) == nil
            || defaults.bool(forKey: Self.cloudSyncEnabledKey)
        cloudSyncEnabled = enabled
        syncStatus = enabled ? .waiting : .disabled
        lastSuccessfulSyncDate = nil
        if hasLocalTouchLayoutDocument && !localTouchLayoutFileExists {
            do {
                try writeLocalTouchLayoutDocument(touchLayoutDocument)
            } catch {
                hasLocalTouchLayoutDocument = false
                syncStatus = .failed(error.localizedDescription)
            }
        }
    }

    var globalProfile: SettingsProfile? { document.globalProfile }

    var graphicsProfile: SettingsProfile { document.graphicsProfile }

    var graphicsFillWidth: Bool { document.graphicsFillWidth }

    var graphicsStereo3D: Bool { document.graphicsStereo3D }

    var developerLogsEnabled: Bool { document.developerLogsEnabled }

    var rumbleEnabled: Bool { document.rumbleEnabled }

    var primaryInputSource: PrimaryInputSource { document.primaryInputSource }

    var jak1InputBindings: Jak1InputBindings { document.jak1InputBindings }

    var jak1TouchLayout: TouchLayoutCustomization { touchLayoutDocument.jak1TouchLayout }

    var dynamicLeftStick: Bool { touchLayoutDocument.dynamicLeftStick }

    var lastSyncDate: Date? {
        lastSuccessfulSyncDate
    }

    var syncSummary: String {
        switch syncStatus {
        case .disabled: "Off — settings stay on this device"
        case .waiting: "Waiting to sync"
        case .syncing: "Syncing…"
        case .unavailable: "iCloud unavailable — using local settings"
        case .synced: "Up to date"
        case .failed(let message): "Sync issue: \(message)"
        }
    }

    func profile(for section: SettingsSection) -> SettingsProfile {
        document.profile(for: section)
    }

    func setProfile(_ profile: SettingsProfile, for section: SettingsSection) {
        change { $0.setProfile(profile, for: section) }
    }

    func applyPreset(_ profile: SettingsProfile) {
        change { document in
            for section in SettingsSection.allCases {
                document.setProfile(profile, for: section)
            }
        }
    }

    func setGraphicsFillWidth(_ enabled: Bool) {
        change { $0.graphicsModernFillWidthOverride = enabled }
    }

    func setGraphicsStereo3D(_ enabled: Bool) {
        change { $0.graphicsModernStereo3DOverride = enabled }
    }

    func setDeveloperLogsEnabled(_ enabled: Bool) {
        change { $0.developerLogsEnabledOverride = enabled }
    }

    func setRumbleEnabled(_ enabled: Bool) {
        change { $0.rumbleEnabledOverride = enabled ? nil : false }
    }

    func setPrimaryInputSource(_ source: PrimaryInputSource) {
        change { $0.primaryInputSourceOverride = source == .automatic ? nil : source }
    }

    func setControllerAction(_ action: Jak1InputAction?, for control: Jak1ControllerControl) {
        var bindings = jak1InputBindings
        bindings.setControllerAction(action, for: control)
        guard bindings != jak1InputBindings else { return }
        change { $0.jak1InputBindingsOverride = bindings == .standard ? nil : bindings }
    }

    func setKeyboardMouseAction(_ action: Jak1InputAction?, for control: KeyboardMouseKey) {
        var bindings = jak1InputBindings
        bindings.setKeyboardMouseAction(action, for: control)
        guard bindings != jak1InputBindings else { return }
        change { $0.jak1InputBindingsOverride = bindings == .standard ? nil : bindings }
    }

    func setControllerStickRoles(_ roles: Jak1ControllerStickRoles) {
        var bindings = jak1InputBindings
        bindings.setControllerStickRoles(roles)
        guard bindings != jak1InputBindings else { return }
        change { $0.jak1InputBindingsOverride = bindings == .standard ? nil : bindings }
    }

    func setControllerSensitivityPercent(_ percent: Int, for role: Jak1ControllerAnalogRole) {
        var bindings = jak1InputBindings
        bindings.setControllerSensitivityPercent(percent, for: role)
        guard bindings != jak1InputBindings else { return }
        change { $0.jak1InputBindingsOverride = bindings == .standard ? nil : bindings }
    }

    func setControllerDeadZonePercent(_ percent: Int, for role: Jak1ControllerAnalogRole) {
        var bindings = jak1InputBindings
        bindings.setControllerDeadZonePercent(percent, for: role)
        guard bindings != jak1InputBindings else { return }
        change { $0.jak1InputBindingsOverride = bindings == .standard ? nil : bindings }
    }

    func setControllerInvertHorizontal(_ inverted: Bool, for role: Jak1ControllerAnalogRole) {
        var bindings = jak1InputBindings
        bindings.setControllerInvertHorizontal(inverted, for: role)
        guard bindings != jak1InputBindings else { return }
        change { $0.jak1InputBindingsOverride = bindings == .standard ? nil : bindings }
    }

    func setControllerInvertVertical(_ inverted: Bool, for role: Jak1ControllerAnalogRole) {
        var bindings = jak1InputBindings
        bindings.setControllerInvertVertical(inverted, for: role)
        guard bindings != jak1InputBindings else { return }
        change { $0.jak1InputBindingsOverride = bindings == .standard ? nil : bindings }
    }

    func setMouseCameraSensitivityPercent(_ percent: Int) {
        var bindings = jak1InputBindings
        bindings.setMouseCameraSensitivityPercent(percent)
        guard bindings != jak1InputBindings else { return }
        change { $0.jak1InputBindingsOverride = bindings == .standard ? nil : bindings }
    }

    func setMouseCameraInvertHorizontal(_ inverted: Bool) {
        var bindings = jak1InputBindings
        bindings.setMouseCameraInvertHorizontal(inverted)
        guard bindings != jak1InputBindings else { return }
        change { $0.jak1InputBindingsOverride = bindings == .standard ? nil : bindings }
    }

    func setMouseCameraInvertVertical(_ inverted: Bool) {
        var bindings = jak1InputBindings
        bindings.setMouseCameraInvertVertical(inverted)
        guard bindings != jak1InputBindings else { return }
        change { $0.jak1InputBindingsOverride = bindings == .standard ? nil : bindings }
    }

    func setTouchControlPosition(_ position: NormalizedTouchPosition?,
                                 for control: TouchLayoutControlID) {
        updateTouchLayout { $0.setPosition(position, for: control) }
    }

    func setTouchControlAction(_ action: TouchLayoutAction,
                               for control: TouchLayoutControlID) {
        updateTouchLayout { $0.setAction(action, for: control) }
    }

    func setTouchGestureAction(_ action: TouchLayoutAction,
                               for direction: TouchGestureDirection) {
        updateTouchLayout { $0.setGestureAction(action, for: direction) }
    }

    func setTouchControlOpacityPercent(_ percent: Int,
                                       for control: TouchLayoutControlID) {
        updateTouchLayout { $0.setOpacityPercent(percent, for: control) }
    }

    func setTouchControlSizePercent(_ percent: Int,
                                    for control: TouchLayoutControlID) {
        updateTouchLayout { $0.setSizePercent(percent, for: control) }
    }

    func setTouchStickSize(_ size: TouchStickSize, for control: TouchLayoutControlID) {
        updateTouchLayout { $0.setStickSize(size, for: control) }
    }

    func resetTouchControl(_ control: TouchLayoutControlID) {
        updateTouchLayout { $0.reset(control) }
    }

    func resetTouchLayout() {
        guard touchLayoutDocument.jak1TouchLayoutOverride != nil
                || !hasLocalTouchLayoutDocument else { return }
        changeTouchLayout { $0.jak1TouchLayoutOverride = nil }
    }

    func setDynamicLeftStick(_ enabled: Bool) {
        guard enabled != dynamicLeftStick else { return }
        changeTouchLayout { $0.dynamicLeftStickOverride = enabled ? nil : false }
    }

    func restoreDefaults(for section: SettingsSection) {
        change { $0.restoreDefaults(for: section) }
        if section == .controls {
            resetTouchLayout()
            setDynamicLeftStick(true)
        }
    }

    func resetAll() {
        change { $0.resetAll() }
        resetTouchLayout()
        setDynamicLeftStick(true)
    }

    func prepare() async {
        guard cloudSyncEnabled else { return }
        await syncNow()
    }

    func syncNow() async {
        guard cloudSyncEnabled else { return }
        guard !isSyncing else {
            syncRequested = true
            return
        }
        isSyncing = true
        syncStatus = .syncing
        defer { isSyncing = false }

        while cloudSyncEnabled {
            syncRequested = false
            let startingRevision = documentRevision
            do {
                guard let remoteState = try await cloudStore.read() else {
                    syncStatus = .unavailable
                    return
                }
                let remote = remoteState.document
                let remoteTouchLayout = remoteState.touchLayoutDocument
                    ?? (remoteState.touchLayoutFileExists
                        ? nil : remoteState.embeddedTouchLayoutDocument)
                guard cloudSyncEnabled else {
                    syncStatus = .disabled
                    return
                }
                let winner: PresentationSettingsDocument
                if !hasLocalDocument, let remote {
                    winner = remote
                } else if let remote {
                    winner = isNewer(document, than: remote) ? document : remote
                } else {
                    winner = document
                }

                let touchLayoutWinner: Jak1TouchLayoutSettingsDocument?
                if !hasLocalTouchLayoutDocument {
                    touchLayoutWinner = remoteTouchLayout
                } else if let remoteTouchLayout {
                    touchLayoutWinner = isNewer(touchLayoutDocument,
                                                than: remoteTouchLayout)
                        ? touchLayoutDocument : remoteTouchLayout
                } else {
                    touchLayoutWinner = touchLayoutDocument
                }
                if let touchLayoutWinner {
                    if touchLayoutWinner != touchLayoutDocument
                        || !hasLocalTouchLayoutDocument {
                        touchLayoutDocument = touchLayoutWinner
                        try writeLocalTouchLayoutDocument(touchLayoutWinner)
                        hasLocalTouchLayoutDocument = true
                    }
                }
                if winner != document || !hasLocalDocument {
                    document = winner
                    try writeLocalDocument(winner)
                    hasLocalDocument = true
                }
                if let touchLayoutWinner,
                   remoteState.touchLayoutDocument != touchLayoutWinner
                    || remoteState.touchLayoutHasConflicts {
                    try await cloudStore.write(touchLayoutWinner,
                                               to: remoteState.touchLayoutURL)
                }
                if documentRevision != startingRevision || syncRequested {
                    continue
                }
                let hasMigratableEmbeddedLayout =
                    remoteState.embeddedTouchLayoutDocument != nil
                    && (!remoteState.touchLayoutFileExists
                        || remoteState.touchLayoutDocument != nil)
                if remote != winner || remoteState.hasConflicts
                    || hasMigratableEmbeddedLayout {
                    try await cloudStore.write(winner, to: remoteState.url)
                }
                guard cloudSyncEnabled else {
                    syncStatus = .disabled
                    return
                }
                if documentRevision != startingRevision || syncRequested {
                    continue
                }
                let completedAt = configuration.now()
                lastSuccessfulSyncDate = completedAt
                syncStatus = .synced(completedAt)
                return
            } catch is CancellationError {
                syncStatus = cloudSyncEnabled ? .waiting : .disabled
                return
            } catch {
                syncStatus = cloudSyncEnabled ? .failed(error.localizedDescription) : .disabled
                return
            }
        }
        syncStatus = .disabled
    }

    private func change(_ update: (inout PresentationSettingsDocument) -> Void) {
        update(&document)
        document.modifiedAt = configuration.now()
        document.writerID = writerID
        do {
            try writeLocalDocument(document)
            hasLocalDocument = true
            documentRevision &+= 1
        } catch {
            syncStatus = .failed(error.localizedDescription)
            return
        }
        guard cloudSyncEnabled else { return }
        Task { [weak self] in await self?.syncNow() }
    }

    private var writerID: String { localWriterID }

    private func updateTouchLayout(_ update: (inout TouchLayoutCustomization) -> Void) {
        var layout = jak1TouchLayout
        update(&layout)
        guard layout != jak1TouchLayout else { return }
        changeTouchLayout {
            $0.jak1TouchLayoutOverride = layout.isDefault ? nil : layout
        }
    }

    private func changeTouchLayout(
        _ update: (inout Jak1TouchLayoutSettingsDocument) -> Void
    ) {
        update(&touchLayoutDocument)
        touchLayoutDocument.modifiedAt = configuration.now()
        touchLayoutDocument.writerID = writerID
        do {
            try writeLocalTouchLayoutDocument(touchLayoutDocument)
            hasLocalTouchLayoutDocument = true
            documentRevision &+= 1
        } catch {
            syncStatus = .failed(error.localizedDescription)
            return
        }
        guard cloudSyncEnabled else { return }
        Task { [weak self] in await self?.syncNow() }
    }

    private func isNewer(_ lhs: PresentationSettingsDocument,
                         than rhs: PresentationSettingsDocument) -> Bool {
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
        return lhs.writerID > rhs.writerID
    }

    private func isNewer(_ lhs: Jak1TouchLayoutSettingsDocument,
                         than rhs: Jak1TouchLayoutSettingsDocument) -> Bool {
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
        return lhs.writerID > rhs.writerID
    }

    private func writeLocalDocument(_ document: PresentationSettingsDocument) throws {
        try manager.createDirectory(at: configuration.localDocumentURL.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(document)
        try data.write(to: configuration.localDocumentURL, options: .atomic)
    }

    private func writeLocalTouchLayoutDocument(
        _ document: Jak1TouchLayoutSettingsDocument
    ) throws {
        try manager.createDirectory(
            at: configuration.localTouchLayoutDocumentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(document)
        try data.write(to: configuration.localTouchLayoutDocumentURL, options: .atomic)
    }

}
