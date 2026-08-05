import Foundation

nonisolated enum SettingsProfile: String, CaseIterable, Codable, Sendable {
    case classic
    case modern

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
    var graphicsProfile: SettingsProfile = .classic
    var audioProfile: SettingsProfile = .classic
    var interfaceProfile: SettingsProfile = .classic

    /// `nil` means the selected profile's default. The only current graphics option belongs to
    /// Modern, whose default is enabled; Classic always behaves as Build 89 regardless.
    var graphicsModernFillWidthOverride: Bool?
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

    mutating func restoreDefaults(for section: SettingsSection) {
        switch section {
        case .graphics:
            graphicsModernFillWidthOverride = nil
        case .controls, .audio, .interface:
            break
        }
    }

    mutating func resetAll() {
        controlsProfile = .classic
        graphicsProfile = .classic
        audioProfile = .classic
        interfaceProfile = .classic
        graphicsModernFillWidthOverride = nil
    }
}

nonisolated struct PresentationSettingsConfiguration: Sendable {
    let localDocumentURL: URL
    let cloudDocumentURL: @Sendable () -> URL?
    let coordinateCloudAccess: Bool
    let now: @Sendable () -> Date

    init(localDocumentURL: URL, cloudDocumentURL: @escaping @Sendable () -> URL?,
         coordinateCloudAccess: Bool, now: @escaping @Sendable () -> Date = { Date() }) {
        self.localDocumentURL = localDocumentURL
        self.cloudDocumentURL = cloudDocumentURL
        self.coordinateCloudAccess = coordinateCloudAccess
        self.now = now
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

    private let defaults: UserDefaults
    private let configuration: PresentationSettingsConfiguration
    private let localWriterID: String
    private let manager = FileManager.default
    private var hasLocalDocument: Bool
    private var isSyncing = false

    init(defaults: UserDefaults = .standard,
         configuration: PresentationSettingsConfiguration? = nil,
         writerID: String? = nil) {
        self.defaults = defaults
        let storedWriterID = writerID ?? defaults.string(forKey: Self.writerIDKey) ?? UUID().uuidString
        if writerID == nil, defaults.string(forKey: Self.writerIDKey) == nil {
            defaults.set(storedWriterID, forKey: Self.writerIDKey)
        }
        localWriterID = storedWriterID
        self.configuration = configuration ?? PresentationSettingsConfiguration(
            localDocumentURL: PresentationSettingsLayout.localDocumentURL,
            cloudDocumentURL: { PresentationSettingsLayout.cloudDocumentURL() },
            coordinateCloudAccess: true)
        if let data = try? Data(contentsOf: self.configuration.localDocumentURL),
           let stored = try? JSONDecoder().decode(PresentationSettingsDocument.self, from: data),
           stored.schemaVersion == PresentationSettingsDocument.schemaVersion {
            document = stored
            hasLocalDocument = true
        } else {
            document = PresentationSettingsDocument(modifiedAt: self.configuration.now(),
                                                    writerID: storedWriterID)
            hasLocalDocument = false
        }
        let enabled = defaults.object(forKey: Self.cloudSyncEnabledKey) == nil
            || defaults.bool(forKey: Self.cloudSyncEnabledKey)
        cloudSyncEnabled = enabled
        syncStatus = enabled ? .waiting : .disabled
    }

    var globalProfile: SettingsProfile? { document.globalProfile }

    var graphicsFillWidth: Bool { document.graphicsFillWidth }

    var lastSyncDate: Date? {
        if case let .synced(date) = syncStatus { return date }
        return nil
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

    func restoreDefaults(for section: SettingsSection) {
        change { $0.restoreDefaults(for: section) }
    }

    func resetAll() {
        change { $0.resetAll() }
    }

    func prepare() async {
        guard cloudSyncEnabled else { return }
        await syncNow()
    }

    func syncNow() async {
        guard cloudSyncEnabled, !isSyncing else { return }
        isSyncing = true
        syncStatus = .syncing
        defer { isSyncing = false }

        guard let cloudURL = configuration.cloudDocumentURL() else {
            syncStatus = .unavailable
            return
        }

        do {
            let remote = try await readCloudDocument(at: cloudURL)
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
            if winner != document || !hasLocalDocument {
                document = winner
                try writeLocalDocument(winner)
                hasLocalDocument = true
            }
            if remote != winner {
                try writeCloudDocument(winner, to: cloudURL)
            }
            syncStatus = .synced(configuration.now())
        } catch {
            syncStatus = .failed(error.localizedDescription)
        }
    }

    private func change(_ update: (inout PresentationSettingsDocument) -> Void) {
        update(&document)
        document.modifiedAt = configuration.now()
        document.writerID = writerID
        do {
            try writeLocalDocument(document)
            hasLocalDocument = true
        } catch {
            syncStatus = .failed(error.localizedDescription)
            return
        }
        guard cloudSyncEnabled else { return }
        Task { [weak self] in await self?.syncNow() }
    }

    private var writerID: String { localWriterID }

    private func isNewer(_ lhs: PresentationSettingsDocument,
                         than rhs: PresentationSettingsDocument) -> Bool {
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
        return lhs.writerID > rhs.writerID
    }

    private func readCloudDocument(at url: URL) async throws -> PresentationSettingsDocument? {
        guard manager.fileExists(atPath: url.path) else { return nil }
        try await ensureCloudDocumentIsCurrent(at: url)
        let data = try Data(contentsOf: url)
        let document = try JSONDecoder().decode(PresentationSettingsDocument.self, from: data)
        return document.schemaVersion == PresentationSettingsDocument.schemaVersion ? document : nil
    }

    private func ensureCloudDocumentIsCurrent(at url: URL) async throws {
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

    private func writeLocalDocument(_ document: PresentationSettingsDocument) throws {
        try manager.createDirectory(at: configuration.localDocumentURL.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(document)
        try data.write(to: configuration.localDocumentURL, options: .atomic)
    }

    private func writeCloudDocument(_ document: PresentationSettingsDocument, to url: URL) throws {
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(document)
        guard configuration.coordinateCloudAccess else {
            try data.write(to: url, options: .atomic)
            return
        }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var writeError: Error?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing,
                               error: &coordinationError) { coordinatedURL in
            do {
                try data.write(to: coordinatedURL, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }
}
