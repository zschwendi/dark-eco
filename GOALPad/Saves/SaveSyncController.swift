import Foundation
import SwiftUI
import UniformTypeIdentifiers

nonisolated enum SaveDataLayout {
    static var applicationSupportDirectory: URL {
        (try? FileManager.default.url(for: .applicationSupportDirectory,
                                      in: .userDomainMask, appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appending(path: "Library/Application Support", directoryHint: .isDirectory)
    }

    /// OpenGOAL's existing desktop-compatible memcard directory. The kernel keeps using this
    /// exact local path; iCloud is never passed to native gameplay code.
    static var localSavesDirectory: URL {
        applicationSupportDirectory
            .appending(path: "OpenGOAL/jak1/saves", directoryHint: .isDirectory)
    }

    static var localConflictsDirectory: URL {
        applicationSupportDirectory
            .appending(path: "GOALPad/SaveConflicts", directoryHint: .isDirectory)
    }

    static var stateFile: URL {
        applicationSupportDirectory
            .appending(path: "GOALPad/SaveSync/state-v1.json", directoryHint: .notDirectory)
    }

    static func cloudLocations() -> CloudSaveLocations? {
        let manager = FileManager.default
        guard let identityToken = manager.ubiquityIdentityToken,
              let accountIdentifier = try? NSKeyedArchiver.archivedData(
                  withRootObject: identityToken, requiringSecureCoding: false),
              let container = manager.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        let documents = container.appending(path: "Documents", directoryHint: .isDirectory)
        return CloudSaveLocations(
            savesRoot: documents.appending(path: "OpenGOAL/jak1/saves",
                                            directoryHint: .isDirectory),
            conflictsRoot: documents.appending(path: "GOALPad/SaveConflicts",
                                                directoryHint: .isDirectory),
            accountIdentifier: accountIdentifier)
    }
}

@MainActor
@Observable
final class SaveSyncController {
    enum Status: Equatable {
        case disabled
        case waiting
        case syncing
        case unavailable
        case synced(Date, uploaded: Int, downloaded: Int, resolutions: [SaveResolution])
        case failed(String)
    }

    private static let enabledDefaultsKey = "iCloudSavesEnabled"
    private static let lastResolutionsDefaultsKey = "lastSaveAutoResolutions"

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledDefaultsKey)
            if isEnabled {
                status = .waiting
                Task { await syncNow() }
            } else {
                frameCheckTask?.cancel()
                frameCheckTask = nil
                status = .disabled
            }
        }
    }
    private(set) var status: Status
    private(set) var transferMessage: String?
    private(set) var isTransferring = false
    private(set) var isGameplayActive = false
    private(set) var recentResolutions: [SaveResolution]

    private let defaults: UserDefaults
    private let engine: SaveSyncEngine
    private var isWorking = false
    private var frameCheckTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, engine: SaveSyncEngine? = nil) {
        self.defaults = defaults
        let enabled: Bool
        if defaults.object(forKey: Self.enabledDefaultsKey) == nil {
            enabled = true
        } else {
            enabled = defaults.bool(forKey: Self.enabledDefaultsKey)
        }
        isEnabled = enabled
        status = enabled ? .waiting : .disabled
        if let data = defaults.data(forKey: Self.lastResolutionsDefaultsKey),
           let stored = try? JSONDecoder().decode([SaveResolution].self, from: data) {
            recentResolutions = stored
        } else {
            recentResolutions = []
        }
        self.engine = engine ?? SaveSyncEngine(configuration: .init(
            localRoot: SaveDataLayout.localSavesDirectory,
            localConflictsRoot: SaveDataLayout.localConflictsDirectory,
            stateFile: SaveDataLayout.stateFile,
            cloudLocations: { SaveDataLayout.cloudLocations() },
            coordinateCloudAccess: true))
    }

    func prepare() async {
        guard isEnabled else { return }
        await syncNow()
    }

    func syncNow(mode requestedMode: SaveSyncMode? = nil) async {
        guard isEnabled, !isWorking else { return }
        let mode = requestedMode ?? (isGameplayActive ? .uploadOnly : .bidirectional)
        isWorking = true
        status = .syncing
        defer { isWorking = false }
        do {
            let outcome = try await engine.sync(mode: mode)
            guard isEnabled else {
                status = .disabled
                return
            }
            apply(outcome)
        } catch {
            guard isEnabled else {
                status = .disabled
                return
            }
            status = .failed(error.localizedDescription)
        }
    }

    func syncBeforeGameplay() async {
        setGameplayActive(false)
        while isWorking {
            try? await Task.sleep(for: .milliseconds(10))
        }
        await syncNow(mode: .bidirectional)
    }

    /// Called after completed gameplay frames. The native save is synchronous, so any successful
    /// memcard write is closed before this check runs. Coalescing keeps file I/O off the hot loop.
    func gameplayFrameCompleted() {
        guard isEnabled, !isWorking, frameCheckTask == nil else { return }
        frameCheckTask = Task { [weak self] in
            guard let self else { return }
            defer { frameCheckTask = nil }
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard isEnabled, !Task.isCancelled else { return }
            do {
                if let outcome = try await engine.syncIfLocalFilesChanged(mode: .uploadOnly) {
                    guard isEnabled else {
                        status = .disabled
                        return
                    }
                    apply(outcome)
                }
            } catch {
                guard isEnabled else {
                    status = .disabled
                    return
                }
                status = .failed(error.localizedDescription)
            }
        }
    }

    func importSaves(from source: URL) async {
        guard !isTransferring else { return }
        guard !isGameplayActive else {
            transferMessage = "Pause gameplay before importing saves."
            return
        }
        isTransferring = true
        transferMessage = "Importing saves…"
        defer { isTransferring = false }
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        do {
            let result = try await engine.importSaves(from: source)
            transferMessage = result.fileCount == 0
                ? "The selected saves already match this device."
                : "Imported \(result.fileCount) save file(s). Replaced copies were preserved."
            if isEnabled { await syncNow() }
        } catch {
            transferMessage = "Import issue: \(error.localizedDescription)"
        }
    }

    func exportSaves(to destination: URL) async {
        guard !isTransferring else { return }
        isTransferring = true
        transferMessage = "Exporting saves…"
        defer { isTransferring = false }
        let accessed = destination.startAccessingSecurityScopedResource()
        defer { if accessed { destination.stopAccessingSecurityScopedResource() } }
        do {
            let result = try await engine.exportSaves(to: destination)
            let folder = result.destination?.deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
                ?? "the selected folder"
            transferMessage = "Exported \(result.fileCount) save file(s) to \(folder)."
        } catch {
            transferMessage = "Export issue: \(error.localizedDescription)"
        }
    }

    func clearTransferMessage() {
        transferMessage = nil
    }

    func acknowledgeRecentResolutions() {
        recentResolutions = []
        defaults.removeObject(forKey: Self.lastResolutionsDefaultsKey)
    }

    func setGameplayActive(_ active: Bool) {
        isGameplayActive = active
        if !active {
            frameCheckTask?.cancel()
            frameCheckTask = nil
        }
    }

    var summary: String {
        switch status {
        case .disabled: return "Off — saves stay on this device"
        case .waiting: return "Waiting to sync"
        case .syncing: return "Syncing…"
        case .unavailable: return "iCloud unavailable — using local saves"
        case .synced(_, let uploaded, let downloaded, let resolutions):
            if !resolutions.isEmpty { return resolutionNotice(for: resolutions) }
            if uploaded == 0 && downloaded == 0 { return "Up to date" }
            return "Synced: \(uploaded) uploaded, \(downloaded) downloaded"
        case .failed(let message): return "Sync issue: \(message)"
        }
    }

    var lastSyncDate: Date? {
        switch status {
        case .synced(let date, _, _, _): return date
        default: return nil
        }
    }

    func resolutionDescription(_ resolution: SaveResolution) -> String {
        let winner = resolution.winner.rawValue
        switch resolution.basis {
        case .completionPercentage(let percentage):
            return "\(winner) won at \(String(format: "%.0f", percentage))% completion; "
                + "the other copy was preserved."
        case .onlyValidJak1Bank:
            return "\(winner) was the only valid Jak 1 save; the other copy was preserved."
        case .modificationDate:
            return "\(winner) was newer; the other copy was preserved."
        case .localGameplayAuthority:
            return "this device stayed active because the dates tied; the iCloud copy was preserved."
        case .activeGameplayAuthority:
            return "this device stayed active during gameplay; the iCloud copy was preserved."
        }
    }

    private func apply(_ outcome: SaveSyncOutcome) {
        guard outcome.availability == .available else {
            status = .unavailable
            return
        }
        if !outcome.resolutions.isEmpty {
            recentResolutions = outcome.resolutions
            if let data = try? JSONEncoder().encode(recentResolutions) {
                defaults.set(data, forKey: Self.lastResolutionsDefaultsKey)
            }
        }
        status = .synced(outcome.completedAt, uploaded: outcome.uploaded,
                         downloaded: outcome.downloaded, resolutions: outcome.resolutions)
    }

    private func resolutionNotice(for resolutions: [SaveResolution]) -> String {
        if resolutions.count == 1, let resolution = resolutions.first {
            return "Auto-resolved: \(resolutionDescription(resolution))"
        }
        let localWins = resolutions.filter { $0.winner == .local }.count
        let cloudWins = resolutions.count - localWins
        return "Auto-resolved \(resolutions.count) saves: this device won \(localWins), "
            + "iCloud won \(cloudWins); every other copy was preserved."
    }
}

struct SaveSettingsView: View {
    @Bindable var sync: SaveSyncController
    @State private var isChoosingImport = false
    @State private var isChoosingExportDestination = false

    var body: some View {
        Form {
            Section("iCloud Saves") {
                Toggle("Sync saves with iCloud", isOn: $sync.isEnabled)
                Label(sync.summary, systemImage: statusSymbol)
                    .foregroundStyle(statusColor)
                if let date = sync.lastSyncDate {
                    LabeledContent("Last sync", value: date.formatted(date: .abbreviated,
                                                                      time: .shortened))
                }
                Button("Sync Now") { Task { await sync.syncNow() } }
                    .disabled(!sync.isEnabled || sync.status == .syncing)
            }

            Section("Save Files") {
                Button {
                    sync.clearTransferMessage()
                    isChoosingImport = true
                } label: {
                    Label("Import Saves", systemImage: "square.and.arrow.down")
                }
                .disabled(sync.isTransferring || sync.isGameplayActive)
                Button {
                    sync.clearTransferMessage()
                    isChoosingExportDestination = true
                } label: {
                    Label("Export Saves", systemImage: "square.and.arrow.up")
                }
                .disabled(sync.isTransferring)
                Text("Import an OpenGOAL `saves` folder, or export the unchanged desktop layout "
                     + "under `OpenGOAL/jak1/saves`.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if sync.isGameplayActive {
                    Text("Pause gameplay before importing saves.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let message = sync.transferMessage {
                    Text(message).font(.callout)
                }
            }

            if !sync.recentResolutions.isEmpty {
                Section("Automatic Resolution") {
                    ForEach(sync.recentResolutions, id: \.relativePath) { resolution in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(resolution.relativePath)
                                .font(.system(.caption, design: .monospaced))
                            Text(sync.resolutionDescription(resolution))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button("Dismiss Details") { sync.acknowledgeRecentResolutions() }
                }
            }
        }
        .navigationTitle("Settings")
        .fileImporter(isPresented: $isChoosingImport,
                      allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let source = urls.first {
                Task { await sync.importSaves(from: source) }
            }
        }
        .fileImporter(isPresented: $isChoosingExportDestination,
                      allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let destination = urls.first {
                Task { await sync.exportSaves(to: destination) }
            }
        }
    }

    private var statusSymbol: String {
        switch sync.status {
        case .disabled: return "icloud.slash"
        case .waiting, .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .unavailable, .failed: return "exclamationmark.icloud"
        case .synced: return "checkmark.icloud"
        }
    }

    private var statusColor: Color {
        switch sync.status {
        case .unavailable: return .secondary
        case .failed: return .orange
        default: return .primary
        }
    }
}
