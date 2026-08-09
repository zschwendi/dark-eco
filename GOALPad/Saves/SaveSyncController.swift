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
        case loadingArchives
        case restoringArchive
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
                gameplayReadinessDidChange?()
            }
        }
    }
    private(set) var status: Status
    private(set) var transferMessage: String?
    private(set) var activeOperation: Operation?
    private(set) var isGameplayActive = false
    private(set) var recentResolutions: [SaveResolution]
    private(set) var archivedSaves: [ArchivedSaveCandidate] = []
    private(set) var lastSuccessfulSyncDate: Date?

    private let defaults: UserDefaults
    private let engine: SaveSyncEngine
    private var frameCheckTask: Task<Void, Never>?
    private var frameCheckGeneration = 0
    private var pendingSyncMode: SaveSyncMode?
    private var gameplayReadinessDidChange: (() -> Void)?

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
            || activeOperation == .restoringArchive
    }

    var hasPendingFrameCheck: Bool { frameCheckTask != nil }

    func setGameplayReadinessHandler(_ handler: @escaping () -> Void) {
        gameplayReadinessDidChange = handler
    }

    var progressMessage: String? {
        switch activeOperation {
        case .syncing: "Syncing saves…"
        case .checking: "Checking saves…"
        case .importing: "Importing saves…"
        case .exporting: "Exporting saves…"
        case .loadingArchives: "Loading preserved saves…"
        case .restoringArchive: "Making preserved save active…"
        case nil: nil
        }
    }

    func refreshArchivedSaves() async {
        guard !isBusy else { return }
        activeOperation = .loadingArchives
        do {
            archivedSaves = try await engine.archivedSaveCandidates()
        } catch {
            transferMessage = "Preserved saves issue: \(error.localizedDescription)"
        }
        activeOperation = nil
    }

    func promoteArchivedSave(_ candidate: ArchivedSaveCandidate) async {
        guard !isBusy else { return }
        guard !isGameplayActive else {
            transferMessage = "Pause gameplay before changing the active save."
            return
        }
        activeOperation = .restoringArchive
        transferMessage = "Making Save Slot \(candidate.slotNumber) active…"
        var shouldSync = false
        do {
            let restored = try await engine.promoteArchivedSave(id: candidate.id)
            transferMessage = "Save Slot \(restored.slotNumber) is now active. "
                + "The previous active copy was preserved."
            archivedSaves = try await engine.archivedSaveCandidates()
            shouldSync = isEnabled
        } catch {
            transferMessage = "Preserved save issue: \(error.localizedDescription)"
        }
        activeOperation = nil
        if shouldSync { enqueueSync(.bidirectional) }
        await drainPendingSync()
    }

    func prepare() async {
        guard isEnabled else { return }
        await syncNow()
    }

    func syncNow(mode requestedMode: SaveSyncMode? = nil) async {
        guard isEnabled else { return }
        defer { gameplayReadinessDidChange?() }
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
                status = .failed("Save recovery is incomplete. Retry sync before playing.")
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

nonisolated struct CloudSyncPresentationState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case disabled
        case waiting
        case syncing
        case unavailable
        case synced
        case failed
    }

    let phase: Phase
    let summary: String
    let progressMessage: String?
    let lastSyncDate: Date?
    let actionTitle: String
    let isActionEnabled: Bool
}

@MainActor
enum CloudSyncPresentation {
    static func state(settings: PresentationSettings,
                      saves: SaveSyncController) -> CloudSyncPresentationState {
        state(settingsEnabled: settings.cloudSyncEnabled,
              settingsStatus: settings.syncStatus,
              settingsSummary: settings.syncSummary,
              settingsLastSyncDate: settings.lastSyncDate,
              savesEnabled: saves.isEnabled,
              savesStatus: saves.status,
              savesSummary: saves.summary,
              savesLastSyncDate: saves.lastSyncDate,
              savesIsBusy: saves.isBusy,
              savesIsSyncing: saves.activeOperation == .syncing
                  || saves.activeOperation == .checking,
              savesProgressMessage: saves.progressMessage)
    }

    static func state(settingsEnabled: Bool,
                      settingsStatus: PresentationSettings.SyncStatus,
                      settingsSummary: String,
                      settingsLastSyncDate: Date?,
                      savesEnabled: Bool,
                      savesStatus: SaveSyncController.Status,
                      savesSummary: String,
                      savesLastSyncDate: Date?,
                      savesIsBusy: Bool,
                      savesIsSyncing: Bool,
                      savesProgressMessage: String?) -> CloudSyncPresentationState {
        let settingsFailure = settingsEnabled ? failureMessage(for: settingsStatus) : nil
        let savesFailure = savesEnabled ? failureMessage(for: savesStatus) : nil
        let settingsUnavailable = settingsEnabled && settingsStatus == .unavailable
        let savesUnavailable = savesEnabled && savesStatus == .unavailable
        let settingsSyncing = settingsEnabled && settingsStatus == .syncing
        let savesSyncing = savesEnabled && (savesStatus == .syncing || savesIsSyncing)
        let anyEnabled = settingsEnabled || savesEnabled
        let phase: CloudSyncPresentationState.Phase

        if settingsFailure != nil || savesFailure != nil {
            phase = .failed
        } else if settingsSyncing || savesSyncing {
            phase = .syncing
        } else if settingsUnavailable || savesUnavailable {
            phase = .unavailable
        } else if isWaiting(settingsEnabled: settingsEnabled, status: settingsStatus)
                    || isWaiting(savesEnabled: savesEnabled, status: savesStatus) {
            phase = .waiting
        } else {
            phase = anyEnabled ? .synced : .disabled
        }

        let progressMessage: String?
        switch (settingsSyncing, savesSyncing) {
        case (true, true): progressMessage = "Syncing settings and saves…"
        case (true, false): progressMessage = "Syncing settings…"
        case (false, true): progressMessage = savesProgressMessage ?? "Syncing saves…"
        case (false, false): progressMessage = nil
        }

        return CloudSyncPresentationState(
            phase: phase,
            summary: summary(phase: phase,
                             settingsEnabled: settingsEnabled,
                             settingsSummary: settingsSummary,
                             settingsFailure: settingsFailure,
                             settingsUnavailable: settingsUnavailable,
                             savesEnabled: savesEnabled,
                             savesSummary: savesSummary,
                             savesFailure: savesFailure,
                             savesUnavailable: savesUnavailable,
                             progressMessage: progressMessage),
            progressMessage: progressMessage,
            lastSyncDate: [settingsLastSyncDate, savesLastSyncDate].compactMap { $0 }.max(),
            actionTitle: phase == .failed || phase == .unavailable ? "Retry" : "Sync",
            isActionEnabled: anyEnabled && !settingsSyncing && !savesSyncing
                && !(savesEnabled && savesIsBusy))
    }

    static func synchronize(settingsEnabled: Bool,
                            savesEnabled: Bool,
                            syncSettings: () async -> Void,
                            syncSaves: () async -> Void) async {
        guard !Task.isCancelled else { return }
        if settingsEnabled {
            await syncSettings()
        }
        guard !Task.isCancelled else { return }
        if savesEnabled {
            await syncSaves()
        }
    }

    private static func failureMessage(
        for status: PresentationSettings.SyncStatus
    ) -> String? {
        guard case .failed(let message) = status else { return nil }
        return message
    }

    private static func failureMessage(for status: SaveSyncController.Status) -> String? {
        guard case .failed(let message) = status else { return nil }
        return message
    }

    private static func isWaiting(settingsEnabled: Bool,
                                  status: PresentationSettings.SyncStatus) -> Bool {
        guard settingsEnabled else { return false }
        return status == .waiting || status == .disabled
    }

    private static func isWaiting(savesEnabled: Bool,
                                  status: SaveSyncController.Status) -> Bool {
        guard savesEnabled else { return false }
        return status == .waiting || status == .disabled
    }

    private static func summary(
        phase: CloudSyncPresentationState.Phase,
        settingsEnabled: Bool,
        settingsSummary: String,
        settingsFailure: String?,
        settingsUnavailable: Bool,
        savesEnabled: Bool,
        savesSummary: String,
        savesFailure: String?,
        savesUnavailable: Bool,
        progressMessage: String?
    ) -> String {
        switch phase {
        case .disabled:
            return "Off — settings and saves stay on this device"
        case .failed:
            let issues = [settingsFailure.map { "Settings — \($0)" },
                          savesFailure.map { "Saves — \($0)" }].compactMap { $0 }
            return "Sync issue: " + issues.joined(separator: "; ")
        case .syncing:
            return progressMessage ?? "Syncing…"
        case .unavailable:
            if settingsUnavailable && savesUnavailable {
                return "iCloud unavailable — using local settings and saves"
            }
            if settingsUnavailable {
                return "iCloud unavailable for settings — using local settings"
            }
            return "iCloud unavailable for saves — using local saves"
        case .waiting:
            return "Waiting to sync"
        case .synced:
            if settingsEnabled && !savesEnabled { return settingsSummary }
            if savesEnabled && !settingsEnabled { return savesSummary }
            return savesSummary == "Up to date" ? "Up to date" : savesSummary
        }
    }
}

struct SaveSettingsView: View {
    private enum SaveTransferPicker {
        case importSaves
        case exportSaves
    }

    @Bindable var sync: SaveSyncController
    @Bindable var settings: PresentationSettings
    @Bindable var input: ControllerInput
    let isGameRunning: Bool
    let returnToLibrary: () -> Void
    @State private var saveTransferPicker: SaveTransferPicker?
    @State private var archivedSaveToPromote: ArchivedSaveCandidate?
    @State private var isConfirmingReturnToLibrary = false

    var body: some View {
        Form {
            if isGameRunning {
                Section {
                    Button(role: .destructive) {
                        isConfirmingReturnToLibrary = true
                    } label: {
                        Label("Return to Library",
                              systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } footer: {
                    Text("Closes the running game. Progress since your last in-game save will be lost.")
                }
            }

            controlsSection
            profileSection(.graphics)

            Section("iCloud") {
                Toggle("Sync Settings", isOn: $settings.cloudSyncEnabled)
                    .disabled(settings.syncStatus == .syncing)
                Toggle("Sync Saves", isOn: $sync.isEnabled)
                    .disabled(sync.isBusy)
                Label(cloudState.summary, systemImage: cloudStatusSymbol)
                    .foregroundStyle(cloudStatusColor)
                if let message = cloudState.progressMessage {
                    ProgressView(message)
                }
                if let date = cloudState.lastSyncDate {
                    LabeledContent("Last sync", value: date.formatted(date: .abbreviated,
                                                                      time: .shortened))
                }
                Button(cloudState.actionTitle) {
                    Task {
                        await CloudSyncPresentation.synchronize(
                            settingsEnabled: settings.cloudSyncEnabled,
                            savesEnabled: sync.isEnabled,
                            syncSettings: { await settings.syncNow() },
                            syncSaves: { await sync.syncNow() })
                    }
                }
                .disabled(!cloudState.isActionEnabled)
                Text("Choose settings and save sync independently on this device.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Save Files") {
                Button {
                    sync.clearTransferMessage()
                    saveTransferPicker = .importSaves
                } label: {
                    Label("Import Saves", systemImage: "square.and.arrow.down")
                }
                .disabled(sync.isBusy || sync.isGameplayActive)
                Button {
                    sync.clearTransferMessage()
                    saveTransferPicker = .exportSaves
                } label: {
                    Label("Export Saves", systemImage: "square.and.arrow.up")
                }
                .disabled(sync.isBusy)
                Text("Eco imports and exports the four \(GameLibraryTitle.jak1.name) save slots. When copies "
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

            Section("Preserved Saves") {
                if sync.archivedSaves.isEmpty {
                    Text("No preserved save copies are available.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sync.archivedSaves) { candidate in
                        Button {
                            archivedSaveToPromote = candidate
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Save Slot \(candidate.slotNumber)")
                                Text(archiveSummary(candidate))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(sync.isBusy || sync.isGameplayActive)
                    }
                }
                Button {
                    Task { await sync.refreshArchivedSaves() }
                } label: {
                    Label("Refresh Preserved Saves", systemImage: "arrow.clockwise")
                }
                .disabled(sync.isBusy)
                Text("Choose Make Active to restore a preserved native \(GameLibraryTitle.jak1.name) save. Eco preserves "
                     + "the current active copy before replacing it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Developer") {
                Toggle("Show Developer Logs", isOn: Binding(
                    get: { settings.developerLogsEnabled },
                    set: { settings.setDeveloperLogsEnabled($0) }
                ))
                Text("Shows the live engine readout only while the game's pause or progress menu is open.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Reset \(GameLibraryTitle.jak1.name) Settings", role: .destructive) {
                    settings.resetAll()
                    input.setPrimarySource(settings.primaryInputSource)
                    input.setBindings(settings.jak1InputBindings)
                }
            }
        }
        .navigationTitle("\(GameLibraryTitle.jak1.name) Settings")
        .fileImporter(isPresented: Binding(
            get: { saveTransferPicker != nil },
            set: { if !$0 { saveTransferPicker = nil } }
        ),
                      allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            handleSavePickerResult(result)
        }
        .confirmationDialog(
            "Make this preserved save active?",
            isPresented: Binding(
                get: { archivedSaveToPromote != nil },
                set: { if !$0 { archivedSaveToPromote = nil } }
            ),
            titleVisibility: .visible,
            presenting: archivedSaveToPromote
        ) { candidate in
            Button("Make Save Slot \(candidate.slotNumber) Active") {
                archivedSaveToPromote = nil
                Task { await sync.promoteArchivedSave(candidate) }
            }
            Button("Cancel", role: .cancel) { archivedSaveToPromote = nil }
        } message: { candidate in
            Text(archiveSummary(candidate)
                 + ". The current active copy will be preserved before replacement.")
        }
        .confirmationDialog("Return to Library?",
                            isPresented: $isConfirmingReturnToLibrary,
                            titleVisibility: .visible) {
            Button("Return to Library", role: .destructive) { returnToLibrary() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Eco will close the running game. Progress since your last in-game save will be lost.")
        }
        .task { await sync.refreshArchivedSaves() }
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

    private func archiveSummary(_ candidate: ArchivedSaveCandidate) -> String {
        let completion = String(format: "%.0f%% complete", candidate.completionPercentage)
        let generation = "generation \(candidate.saveGeneration)"
        let source = candidate.source.rawValue
        guard let date = candidate.modificationDate else {
            return "\(completion) · \(generation) · \(source)"
        }
        return "\(completion) · \(generation) · \(source) · "
            + date.formatted(date: .abbreviated, time: .shortened)
    }

    private var cloudState: CloudSyncPresentationState {
        CloudSyncPresentation.state(settings: settings, saves: sync)
    }

    private var cloudStatusSymbol: String {
        switch cloudState.phase {
        case .disabled: "icloud.slash"
        case .waiting, .syncing: "arrow.triangle.2.circlepath.icloud"
        case .unavailable, .failed: "exclamationmark.icloud"
        case .synced: "checkmark.icloud"
        }
    }

    private var cloudStatusColor: Color {
        switch cloudState.phase {
        case .unavailable: return .secondary
        case .failed: return .orange
        default: return .primary
        }
    }

    private var controlsSection: some View {
        Section("Controls") {
            NavigationLink {
                TouchControlsGuideView()
            } label: {
                Label("Touch Controls Guide", systemImage: "hand.tap")
            }
            Picker("Primary Controller", selection: Binding(
                get: { settings.primaryInputSource },
                set: {
                    settings.setPrimaryInputSource($0)
                    input.setPrimarySource($0)
                }
            )) {
                ForEach(primaryInputSourceChoices, id: \.self) { source in
                    Text(primaryInputSourceTitle(source)).tag(source)
                }
            }
            if settings.primaryInputSource != .automatic,
               !input.isSourceAvailable(settings.primaryInputSource) {
                Text("The selected source is not connected. Eco uses Automatic until it returns.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            NavigationLink {
                ControllerBindingsSettingsView(settings: settings, input: input)
            } label: {
                LabeledContent("Controller Bindings", value: controllerBindingStatus)
            }
            NavigationLink {
                KeyboardMouseBindingsSettingsView(settings: settings, input: input)
            } label: {
                LabeledContent("Mouse & Keyboard Bindings",
                               value: keyboardMouseBindingStatus)
            }
            Button("Restore Controls Defaults") {
                settings.restoreDefaults(for: .controls)
                input.setPrimarySource(settings.primaryInputSource)
                input.setBindings(settings.jak1InputBindings)
            }
        }
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
                Toggle("Fit to Screen", isOn: Binding(
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

    private var primaryInputSourceChoices: [PrimaryInputSource] {
        let selected = settings.primaryInputSource
        if input.isSourceAvailable(selected) { return input.availablePrimarySources }
        return input.availablePrimarySources + [selected]
    }

    private func primaryInputSourceTitle(_ source: PrimaryInputSource) -> String {
        guard source != .automatic, !input.isSourceAvailable(source) else { return source.title }
        return "\(source.title) — Not Connected"
    }

    private var controllerBindingStatus: String {
        input.isConnected ? "Connected" : "Not Connected"
    }

    private var keyboardMouseBindingStatus: String {
        switch (input.isKeyboardConnected, input.isMouseConnected) {
        case (true, true): "Connected"
        case (true, false): "Keyboard Only"
        case (false, true): "Mouse Only"
        case (false, false): "Not Connected"
        }
    }

}

private struct ControllerBindingsSettingsView: View {
    @Bindable var settings: PresentationSettings
    @Bindable var input: ControllerInput

    var body: some View {
        Form {
            Section("Controller") {
                if input.isConnected {
                    Label(input.controllerName ?? "Controller connected",
                          systemImage: "gamecontroller.fill")
                } else {
                    Label("No controller connected", systemImage: "gamecontroller")
                    Text("Bindings remain available and will apply when a controller connects.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Picker("Stick Roles", selection: Binding(
                    get: { settings.jak1InputBindings.controllerStickRoles },
                    set: { roles in
                        settings.setControllerStickRoles(roles)
                        input.setBindings(settings.jak1InputBindings)
                    }
                )) {
                    ForEach(Jak1ControllerStickRoles.allCases, id: \.self) { roles in
                        Text(roles.title).tag(roles)
                    }
                }
            } header: {
                Text("Sticks")
            } footer: {
                Text("Standard uses the left stick for movement and the right stick for camera. "
                     + "Swapped Sticks exchanges those whole-stick roles while keeping each "
                     + "stick's X and Y axes together.")
            }

            ForEach(Jak1ControllerAnalogRole.allCases, id: \.self) { role in
                analogSection(role)
            }

            Section {
                ForEach(Jak1ControllerControl.allCases, id: \.self) { control in
                    Picker(control.title, selection: Binding(
                        get: { settings.jak1InputBindings.action(for: control) },
                        set: { action in
                            settings.setControllerAction(action, for: control)
                            input.setBindings(settings.jak1InputBindings)
                        }
                    )) {
                        Text("Not Used").tag(nil as Jak1InputAction?)
                        ForEach(Jak1InputAction.controllerChoices, id: \.self) { action in
                            Text(action.title).tag(Optional(action))
                        }
                    }
                }
            } header: {
                Text("Buttons")
            } footer: {
                Text("Choosing an action already in use swaps the two bindings. "
                     + "Choosing Not Used leaves this button unassigned.")
            }
        }
        .navigationTitle("Controller Bindings")
    }

    @ViewBuilder
    private func analogSection(_ role: Jak1ControllerAnalogRole) -> some View {
        let roleSettings = settings.jak1InputBindings.controllerAnalog.settings(for: role)
        Section {
            LabeledContent("Sensitivity", value: "\(roleSettings.sensitivityPercent)%")
            Slider(value: Binding(
                get: {
                    Double(settings.jak1InputBindings.controllerAnalog
                        .settings(for: role).sensitivityPercent)
                },
                set: { value in
                    settings.setControllerSensitivityPercent(Int(value.rounded()), for: role)
                    input.setBindings(settings.jak1InputBindings)
                }
            ), in: Double(Jak1ControllerStickSettings.minimumSensitivityPercent)
                ... Double(Jak1ControllerStickSettings.maximumSensitivityPercent), step: 25)
            .accessibilityLabel("\(role.title) Stick Sensitivity")
            .accessibilityValue("\(roleSettings.sensitivityPercent) percent")

            LabeledContent("Additional Dead Zone", value: "\(roleSettings.deadZonePercent)%")
            Slider(value: Binding(
                get: {
                    Double(settings.jak1InputBindings.controllerAnalog
                        .settings(for: role).deadZonePercent)
                },
                set: { value in
                    settings.setControllerDeadZonePercent(Int(value.rounded()), for: role)
                    input.setBindings(settings.jak1InputBindings)
                }
            ), in: Double(Jak1ControllerStickSettings.minimumDeadZonePercent)
                ... Double(Jak1ControllerStickSettings.maximumDeadZonePercent), step: 5)
            .accessibilityLabel("\(role.title) Stick Additional Dead Zone")
            .accessibilityValue("\(roleSettings.deadZonePercent) percent")

            Toggle("Invert Horizontal", isOn: Binding(
                get: {
                    settings.jak1InputBindings.controllerAnalog
                        .settings(for: role).invertHorizontal
                },
                set: { inverted in
                    settings.setControllerInvertHorizontal(inverted, for: role)
                    input.setBindings(settings.jak1InputBindings)
                }
            ))
            .accessibilityLabel("\(role.title) Stick Invert Horizontal")
            Toggle("Invert Vertical", isOn: Binding(
                get: {
                    settings.jak1InputBindings.controllerAnalog
                        .settings(for: role).invertVertical
                },
                set: { inverted in
                    settings.setControllerInvertVertical(inverted, for: role)
                    input.setBindings(settings.jak1InputBindings)
                }
            ))
            .accessibilityLabel("\(role.title) Stick Invert Vertical")
        } header: {
            Text("\(role.title) Stick")
        } footer: {
            Text("100% sensitivity and 0% additional dead zone preserve the default. Tuning "
                 + "transforms the complete \(role.title.lowercased()) vector; horizontal and "
                 + "vertical inversion change direction without splitting X/Y ownership.")
        }
    }
}

private struct KeyboardMouseBindingsSettingsView: View {
    @Bindable var settings: PresentationSettings
    @Bindable var input: ControllerInput

    var body: some View {
        Form {
            Section("Availability") {
                Label(input.isKeyboardConnected ? "Keyboard connected" : "Keyboard not connected",
                      systemImage: "keyboard")
                Label(input.isMouseConnected ? "Mouse connected" : "Mouse not connected",
                      systemImage: "computermouse")
                if !input.isKeyboardConnected || !input.isMouseConnected {
                    Text("Saved bindings remain available and apply as each device connects.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Sensitivity",
                               value: "\(settings.jak1InputBindings.mouseCamera.sensitivityPercent)%")
                Slider(value: Binding(
                    get: {
                        Double(settings.jak1InputBindings.mouseCamera.sensitivityPercent)
                    },
                    set: { value in
                        settings.setMouseCameraSensitivityPercent(Int(value.rounded()))
                        input.setBindings(settings.jak1InputBindings)
                    }
                ), in: Double(Jak1MouseCameraSettings.minimumSensitivityPercent)
                    ... Double(Jak1MouseCameraSettings.maximumSensitivityPercent), step: 25)
                .accessibilityLabel("Camera Sensitivity")
                .accessibilityValue(
                    "\(settings.jak1InputBindings.mouseCamera.sensitivityPercent) percent")
                Toggle("Invert Horizontal", isOn: Binding(
                    get: { settings.jak1InputBindings.mouseCamera.invertHorizontal },
                    set: { inverted in
                        settings.setMouseCameraInvertHorizontal(inverted)
                        input.setBindings(settings.jak1InputBindings)
                    }
                ))
                Toggle("Invert Vertical", isOn: Binding(
                    get: { settings.jak1InputBindings.mouseCamera.invertVertical },
                    set: { inverted in
                        settings.setMouseCameraInvertVertical(inverted)
                        input.setBindings(settings.jak1InputBindings)
                    }
                ))
            } header: {
                Text("Mouse / Trackpad Camera")
            } footer: {
                Text("100% preserves the default camera response. Horizontal and vertical "
                     + "direction can be inverted independently. Relative mouse or trackpad "
                     + "motion remains dedicated to camera control.")
            }

            bindingSection(
                "Keyboard",
                controls: KeyboardMouseKey.keyboardCases,
                footer: "Movement defaults to W, A, S, and D. Movement directions are ordinary "
                    + "remappable actions in the same keyboard binding list.")
            bindingSection("Mouse Buttons", controls: KeyboardMouseKey.mouseCases)

            Section {
                Text("Only the keys listed here can drive gameplay. Choosing an action already "
                     + "in use swaps the two bindings; Not Used leaves the input unassigned.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Mouse & Keyboard")
    }

    @ViewBuilder
    private func bindingSection(_ title: String,
                                controls: [KeyboardMouseKey],
                                footer: String? = nil) -> some View {
        Section {
            ForEach(controls, id: \.self) { control in
                Picker(control.title, selection: Binding(
                    get: { settings.jak1InputBindings.action(for: control) },
                    set: { action in
                        settings.setKeyboardMouseAction(action, for: control)
                        input.setBindings(settings.jak1InputBindings)
                    }
                )) {
                    Text("Not Used").tag(nil as Jak1InputAction?)
                    ForEach(Jak1InputAction.allCases, id: \.self) { action in
                        Text(action.title).tag(Optional(action))
                    }
                }
            }
        } header: {
            Text(title)
        } footer: {
            if let footer { Text(footer) }
        }
    }
}
