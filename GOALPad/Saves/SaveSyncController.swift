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
    enum Operation: Equatable {
        case syncing
        case checking
        case importing
        case exporting
    }

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
                cancelPendingFrameCheck()
                pendingSyncMode = nil
                status = .disabled
            }
        }
    }
    private(set) var status: Status
    private(set) var transferMessage: String?
    private(set) var activeOperation: Operation?
    private(set) var isGameplayActive = false
    private(set) var recentResolutions: [SaveResolution]
    private(set) var lastSuccessfulSyncDate: Date?

    private let defaults: UserDefaults
    private let engine: SaveSyncEngine
    private var frameCheckTask: Task<Void, Never>?
    private var frameCheckGeneration = 0
    private var pendingSyncMode: SaveSyncMode?

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
        lastSuccessfulSyncDate = nil
        self.engine = engine ?? SaveSyncEngine(configuration: .init(
            localRoot: SaveDataLayout.localSavesDirectory,
            localConflictsRoot: SaveDataLayout.localConflictsDirectory,
            stateFile: SaveDataLayout.stateFile,
            cloudLocations: { SaveDataLayout.cloudLocations() },
            coordinateCloudAccess: true))
    }

    var isBusy: Bool { activeOperation != nil }

    var isTransferring: Bool {
        activeOperation == .importing || activeOperation == .exporting
    }

    var hasPendingFrameCheck: Bool { frameCheckTask != nil }

    var progressMessage: String? {
        switch activeOperation {
        case .syncing: "Syncing saves…"
        case .checking: "Checking saves…"
        case .importing: "Importing saves…"
        case .exporting: "Exporting saves…"
        case nil: nil
        }
    }

    func prepare() async {
        guard isEnabled else { return }
        await syncNow()
    }

    func syncNow(mode requestedMode: SaveSyncMode? = nil) async {
        guard isEnabled else { return }
        let mode = requestedMode ?? (isGameplayActive ? .uploadOnly : .bidirectional)
        enqueueSync(mode)
        await drainPendingSync()
    }

    func syncBeforeGameplay() async -> Bool {
        setGameplayActive(false)
        while isBusy || frameCheckTask != nil || pendingSyncMode != nil {
            do {
                try await Task.sleep(for: .milliseconds(10))
            } catch {
                return false
            }
        }
        if isEnabled {
            await syncNow(mode: .bidirectional)
        }
        activeOperation = .checking
        do {
            let hasUnsafeLocalMutation = try await engine.hasUnsafePendingLocalMutation()
            activeOperation = nil
            guard !hasUnsafeLocalMutation else {
                status = .failed("Save recovery is incomplete. Retry iCloud Saves before playing.")
                return false
            }
            return true
        } catch {
            activeOperation = nil
            status = .failed(error.localizedDescription)
            return false
        }
    }

    /// Called after completed gameplay frames. The native save is synchronous, so any successful
    /// memcard write is closed before this check runs. Coalescing keeps file I/O off the hot loop.
    func gameplayFrameCompleted() {
        guard isEnabled, isGameplayActive, !isBusy, frameCheckTask == nil else { return }
        frameCheckGeneration += 1
        let generation = frameCheckGeneration
        frameCheckTask = Task { [weak self] in
            guard let self else { return }
            defer { clearFrameCheckTask(for: generation) }
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard isEnabled, !Task.isCancelled, generation == frameCheckGeneration else { return }
            guard !isBusy else {
                enqueueSync(.uploadOnly)
                return
            }
            activeOperation = .checking
            do {
                if let outcome = try await engine.syncIfLocalFilesChanged(mode: .uploadOnly) {
                    guard isEnabled else {
                        status = .disabled
                        activeOperation = nil
                        return
                    }
                    apply(outcome)
                }
            } catch is CancellationError {
                // Cancellation during the debounce is expected; active save work is not cancelled.
            } catch {
                guard isEnabled else {
                    status = .disabled
                    activeOperation = nil
                    return
                }
                status = .failed(error.localizedDescription)
            }
            activeOperation = nil
            await drainPendingSync()
        }
    }

    func importSaves(from source: URL) async {
        guard !isBusy else { return }
        guard !isGameplayActive else {
            transferMessage = "Pause gameplay before importing saves."
            return
        }
        activeOperation = .importing
        transferMessage = "Importing saves…"
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        var shouldSync = false
        do {
            let result = try await engine.importSaves(from: source)
            transferMessage = result.fileCount == 0
                ? "The selected saves already match this device."
                : "Imported \(result.fileCount) save file(s). Replaced copies were preserved."
            shouldSync = isEnabled
        } catch {
            transferMessage = "Import issue: \(error.localizedDescription)"
        }
        activeOperation = nil
        if shouldSync { enqueueSync(.bidirectional) }
        await drainPendingSync()
    }

    func exportSaves(to destination: URL) async {
        guard !isBusy else { return }
        activeOperation = .exporting
        transferMessage = "Exporting saves…"
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
        activeOperation = nil
        await drainPendingSync()
    }

    func clearTransferMessage() {
        transferMessage = nil
    }

    func reportPickerIssue(_ error: Error) {
        if error is CancellationError { return }
        if let cocoaError = error as? CocoaError, cocoaError.code == .userCancelled { return }
        transferMessage = "Save picker issue: \(error.localizedDescription)"
    }

    func acknowledgeRecentResolutions() {
        recentResolutions = []
        defaults.removeObject(forKey: Self.lastResolutionsDefaultsKey)
    }

    func setGameplayActive(_ active: Bool) {
        isGameplayActive = active
        if !active {
            cancelPendingFrameCheck()
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
        lastSuccessfulSyncDate
    }

    private func enqueueSync(_ mode: SaveSyncMode) {
        switch (pendingSyncMode, mode) {
        case (.bidirectional, _), (_, .bidirectional):
            pendingSyncMode = .bidirectional
        case (_, .uploadOnly):
            pendingSyncMode = .uploadOnly
        }
    }

    private func drainPendingSync() async {
        guard activeOperation == nil else { return }
        while isEnabled, let mode = pendingSyncMode {
            pendingSyncMode = nil
            activeOperation = .syncing
            status = .syncing
            do {
                let outcome = try await engine.sync(mode: mode)
                guard isEnabled else {
                    activeOperation = nil
                    status = .disabled
                    pendingSyncMode = nil
                    return
                }
                apply(outcome)
            } catch is CancellationError {
                if isEnabled { status = .waiting }
            } catch {
                status = isEnabled ? .failed(error.localizedDescription) : .disabled
            }
            activeOperation = nil
            if Task.isCancelled {
                if pendingSyncMode != nil {
                    Task { [weak self] in await self?.drainPendingSync() }
                }
                return
            }
        }
        if !isEnabled {
            pendingSyncMode = nil
            status = .disabled
        }
    }

    private func cancelPendingFrameCheck() {
        guard activeOperation != .checking else { return }
        frameCheckGeneration += 1
        frameCheckTask?.cancel()
        frameCheckTask = nil
    }

    private func clearFrameCheckTask(for generation: Int) {
        guard frameCheckGeneration == generation else { return }
        frameCheckTask = nil
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
        lastSuccessfulSyncDate = outcome.completedAt
        status = .synced(outcome.completedAt, uploaded: outcome.uploaded,
                         downloaded: outcome.downloaded, resolutions: outcome.resolutions)
    }

    private func resolutionNotice(for resolutions: [SaveResolution]) -> String {
        "Synced save slots; older divergent copies were preserved automatically."
    }
}

struct SaveSettingsView: View {
    private enum SaveTransferPicker {
        case importSaves
        case exportSaves
    }

    @Bindable var sync: SaveSyncController
    @Bindable var settings: PresentationSettings
    @State private var saveTransferPicker: SaveTransferPicker?
    @State private var isShowingSavePicker = false

    var body: some View {
        Form {
            Section("Preset") {
                Menu {
                    Button("Use Classic Everywhere") { settings.applyPreset(.classic) }
                    Button("Use Modern Everywhere") { settings.applyPreset(.modern) }
                } label: {
                    LabeledContent("Global profile", value: globalProfileTitle)
                }
                Text("Changes section profiles without discarding their customized options.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            profileSection(.controls)
            profileSection(.graphics)
            profileSection(.audio)
            profileSection(.interface)

            Section("iCloud Settings") {
                Toggle("Sync settings with iCloud", isOn: $settings.cloudSyncEnabled)
                    .disabled(settings.syncStatus == .syncing)
                Label(settings.syncSummary, systemImage: settingsStatusSymbol)
                    .foregroundStyle(settingsStatusColor)
                if settings.syncStatus == .syncing {
                    ProgressView("Syncing settings…")
                }
                if let date = settings.lastSyncDate {
                    LabeledContent("Last sync", value: date.formatted(date: .abbreviated,
                                                                        time: .shortened))
                }
                if settingsRetryAvailable {
                    Button("Retry Settings Sync") { Task { await settings.syncNow() } }
                        .disabled(!settings.cloudSyncEnabled)
                } else {
                    Button("Sync Settings Now") { Task { await settings.syncNow() } }
                        .disabled(!settings.cloudSyncEnabled || settings.syncStatus == .syncing)
                }
                Text("This switch applies only to this device and does not change iCloud Saves.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("iCloud Saves") {
                Toggle("Sync saves with iCloud", isOn: $sync.isEnabled)
                    .disabled(sync.isBusy)
                Label(sync.summary, systemImage: statusSymbol)
                    .foregroundStyle(statusColor)
                if sync.activeOperation == .syncing || sync.activeOperation == .checking,
                   let message = sync.progressMessage {
                    ProgressView(message)
                }
                if let date = sync.lastSyncDate {
                    LabeledContent("Last sync", value: date.formatted(date: .abbreviated,
                                                                      time: .shortened))
                }
                if saveRetryAvailable {
                    Button("Retry Save Sync") { Task { await sync.syncNow() } }
                        .disabled(!sync.isEnabled || sync.isBusy)
                } else {
                    Button("Sync Saves Now") { Task { await sync.syncNow() } }
                        .disabled(!sync.isEnabled || sync.isBusy)
                }
            }

            Section("Save Files") {
                Button {
                    sync.clearTransferMessage()
                    saveTransferPicker = .importSaves
                    isShowingSavePicker = true
                } label: {
                    Label("Import Saves", systemImage: "square.and.arrow.down")
                }
                .disabled(sync.isBusy || sync.isGameplayActive)
                Button {
                    sync.clearTransferMessage()
                    saveTransferPicker = .exportSaves
                    isShowingSavePicker = true
                } label: {
                    Label("Export Saves", systemImage: "square.and.arrow.up")
                }
                .disabled(sync.isBusy)
                Text("Eco Pro imports and exports the ordinary four Jak save slots. When copies "
                     + "differ, the older copy is preserved automatically.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if sync.isTransferring, let message = sync.progressMessage {
                    ProgressView(message)
                }
                if sync.isGameplayActive {
                    Text("Pause gameplay before importing saves.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let message = sync.transferMessage {
                    Text(message).font(.callout)
                }
            }

            Section {
                Button("Reset All", role: .destructive) { settings.resetAll() }
            }
        }
        .navigationTitle("Settings")
        .fileImporter(isPresented: $isShowingSavePicker,
                      allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            handleSavePickerResult(result)
        }
    }

    private func handleSavePickerResult(_ result: Result<[URL], Error>) {
        let picker = saveTransferPicker
        saveTransferPicker = nil
        switch result {
        case .success(let urls):
            guard let url = urls.first, let picker else { return }
            switch picker {
            case .importSaves:
                Task { await sync.importSaves(from: url) }
            case .exportSaves:
                Task { await sync.exportSaves(to: url) }
            }
        case .failure(let error):
            sync.reportPickerIssue(error)
        }
    }

    private var settingsRetryAvailable: Bool {
        switch settings.syncStatus {
        case .unavailable, .failed: true
        default: false
        }
    }

    private var saveRetryAvailable: Bool {
        switch sync.status {
        case .unavailable, .failed: true
        default: false
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

    private var globalProfileTitle: String {
        settings.globalProfile?.title ?? "Mixed"
    }

    @ViewBuilder
    private func profileSection(_ section: SettingsSection) -> some View {
        Section(section.title) {
            Picker("Profile", selection: Binding(
                get: { settings.profile(for: section) },
                set: { settings.setProfile($0, for: section) }
            )) {
                ForEach(SettingsProfile.allCases, id: \.self) { profile in
                    Text(profile.title).tag(profile)
                }
            }
            .pickerStyle(.segmented)

            if section == .graphics, settings.profile(for: .graphics) == .modern {
                Toggle("Fill Width (Hor+)", isOn: Binding(
                    get: { settings.graphicsFillWidth },
                    set: { settings.setGraphicsFillWidth($0) }
                ))
                Text("Keeps the vertical view and widens the game horizontally to fill the display.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button("Restore \(section.title) Defaults") {
                settings.restoreDefaults(for: section)
            }
        }
    }

    private var settingsStatusSymbol: String {
        switch settings.syncStatus {
        case .disabled: "icloud.slash"
        case .waiting, .syncing: "arrow.triangle.2.circlepath.icloud"
        case .unavailable, .failed: "exclamationmark.icloud"
        case .synced: "checkmark.icloud"
        }
    }

    private var settingsStatusColor: Color {
        switch settings.syncStatus {
        case .unavailable: .secondary
        case .failed: .orange
        default: .primary
        }
    }
}
