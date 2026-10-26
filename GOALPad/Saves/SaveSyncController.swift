import Foundation
import SwiftUI
import UniformTypeIdentifiers

private extension Notification.Name {
    nonisolated static let goalpadCloudSaveContentDidChange = Notification.Name(
        "GOALPadCloudSaveContentDidChange")
}

/// Keeps observing the private save subtree after the engine's bounded initial discovery pass.
/// FileProvider can expose a newer cross-device revision minutes after that first snapshot.
@MainActor
private final class CloudSaveMetadataMonitor {
    private let notificationCenter: NotificationCenter
    private let cloudRoot: () -> URL?
    private let didChange: () -> Void
    private var query: NSMetadataQuery?
    private var updateObserver: NSObjectProtocol?

    init(notificationCenter: NotificationCenter,
         cloudRoot: @escaping () -> URL?,
         didChange: @escaping () -> Void) {
        self.notificationCenter = notificationCenter
        self.cloudRoot = cloudRoot
        self.didChange = didChange
    }

    func start() {
        guard query == nil, let root = cloudRoot()?.standardizedFileURL else { return }
        let query = NSMetadataQuery()
        query.operationQueue = .main
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K BEGINSWITH %@",
                                      NSMetadataItemPathKey, root.path)
        let observer = notificationCenter.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.didChange() }
        }
        guard query.start() else {
            notificationCenter.removeObserver(observer)
            return
        }
        self.query = query
        updateObserver = observer
    }

    func restart() {
        stop()
        start()
    }

    func stop() {
        query?.stop()
        query = nil
        if let updateObserver {
            notificationCenter.removeObserver(updateObserver)
            self.updateObserver = nil
        }
    }
}

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
        return applicationSupportDirectory
            .appending(path: "OpenGOAL/jak1/saves", directoryHint: .isDirectory)
    }

    static var jak2LocalSavesDirectory: URL {
        applicationSupportDirectory
            .appending(path: "OpenGOAL/jak2/saves", directoryHint: .isDirectory)
    }

    static var localConflictsDirectory: URL {
        applicationSupportDirectory
            .appending(path: "GOALPad/SaveConflicts", directoryHint: .isDirectory)
    }

    static var jak2LocalConflictsDirectory: URL {
        applicationSupportDirectory
            .appending(path: "GOALPad/Jak2/SaveConflicts", directoryHint: .isDirectory)
    }

    static var stateFile: URL {
        applicationSupportDirectory
            .appending(path: "GOALPad/SaveSync/state-v1.json", directoryHint: .notDirectory)
    }

    static var jak2StateFile: URL {
        applicationSupportDirectory
            .appending(path: "GOALPad/Jak2/SaveSync/state-v1.json",
                       directoryHint: .notDirectory)
    }

    static func cloudLocations() -> CloudSaveLocations? {
        cloudLocations(savesPath: "OpenGOAL/jak1/saves",
                       conflictsPath: "GOALPad/SaveConflicts")
    }

    static func jak2CloudLocations() -> CloudSaveLocations? {
        cloudLocations(savesPath: "OpenGOAL/jak2/saves",
                       conflictsPath: "GOALPad/Jak2/SaveConflicts")
    }

    private static func cloudLocations(savesPath: String,
                                       conflictsPath: String) -> CloudSaveLocations? {
        let manager = FileManager.default
        guard let identityToken = manager.ubiquityIdentityToken,
              let accountIdentifier = try? NSKeyedArchiver.archivedData(
                  withRootObject: identityToken, requiringSecureCoding: false),
              let container = manager.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        let documents = container.appending(path: "Documents", directoryHint: .isDirectory)
        return CloudSaveLocations(
            savesRoot: documents.appending(path: savesPath,
                                            directoryHint: .isDirectory),
            conflictsRoot: documents.appending(path: conflictsPath,
                                                directoryHint: .isDirectory),
            accountIdentifier: accountIdentifier)
    }

    static func cloudUnavailableReason() -> CloudSaveUnavailableReason {
        let manager = FileManager.default
        guard manager.ubiquityIdentityToken != nil else { return .accountUnavailable }
        guard manager.url(forUbiquityContainerIdentifier: nil) != nil else {
            return .containerUnavailable
        }
        return .unknown
    }
}

nonisolated struct SaveSyncProfile: Sendable {
    let format: OpenGOALSaveFormat
    let localSavesDirectory: URL
    let localConflictsDirectory: URL
    let stateFile: URL
    let cloudLocations: @Sendable () -> CloudSaveLocations?
    let cloudUnavailableReason: @Sendable () -> CloudSaveUnavailableReason
    let coordinateCloudAccess: Bool
    let supportsManagedSaveSync: Bool
    let supportsSaveTransfer: Bool
    let managedSaveSyncUnavailableMessage: String
    let enabledDefaultsKey: String
    let lastResolutionsDefaultsKey: String

    static func jak1() -> SaveSyncProfile {
        SaveSyncProfile(
            format: .jak1,
            localSavesDirectory: SaveDataLayout.localSavesDirectory,
            localConflictsDirectory: SaveDataLayout.localConflictsDirectory,
            stateFile: SaveDataLayout.stateFile,
            cloudLocations: { SaveDataLayout.cloudLocations() },
            cloudUnavailableReason: { SaveDataLayout.cloudUnavailableReason() },
            coordinateCloudAccess: true,
            supportsManagedSaveSync: true,
            supportsSaveTransfer: true,
            managedSaveSyncUnavailableMessage: "Managed save sync is unavailable.",
            enabledDefaultsKey: "iCloudSavesEnabled",
            lastResolutionsDefaultsKey: "lastSaveAutoResolutions")
    }

    static func jak2() -> SaveSyncProfile {
        let cloudLocations: @Sendable () -> CloudSaveLocations? = {
            SaveDataLayout.jak2CloudLocations()
        }
        return SaveSyncProfile(
            format: .jak2,
            localSavesDirectory: SaveDataLayout.jak2LocalSavesDirectory,
            localConflictsDirectory: SaveDataLayout.jak2LocalConflictsDirectory,
            stateFile: SaveDataLayout.jak2StateFile,
            cloudLocations: cloudLocations,
            cloudUnavailableReason: { SaveDataLayout.cloudUnavailableReason() },
            coordinateCloudAccess: true,
            supportsManagedSaveSync: true,
            supportsSaveTransfer: true,
            managedSaveSyncUnavailableMessage: "Managed save sync is unavailable.",
            enabledDefaultsKey: "jak2ICloudSavesEnabled",
            lastResolutionsDefaultsKey: "jak2LastSaveAutoResolutions")
    }
}

nonisolated struct SaveSettingsSectionVisibility: Equatable, Sendable {
    let showsICloudSection: Bool
    let showsSaveTransferSection: Bool

    init(supportsManagedSaveSync: Bool, supportsSaveTransfer: Bool) {
        showsICloudSection = supportsManagedSaveSync
        showsSaveTransferSection = supportsSaveTransfer
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

    var supportsManagedSaveSync: Bool {
        profile.supportsManagedSaveSync
    }

    var supportsSaveTransfer: Bool {
        profile.supportsSaveTransfer
    }

    var managedSaveSyncUnavailableMessage: String {
        profile.managedSaveSyncUnavailableMessage
    }

    var saveTitleName: String {
        profile.format.titleName
    }

    var isEnabled: Bool {
        didSet {
            guard supportsManagedSaveSync else {
                if isEnabled { isEnabled = false }
                return
            }
            defaults.set(isEnabled, forKey: profile.enabledDefaultsKey)
            if isEnabled {
                cloudMetadataMonitor?.start()
                markBidirectionalSyncRequired()
                status = .waiting
                scheduleAutomaticSync(.bidirectional, announceWaiting: true)
            } else {
                cloudMetadataMonitor?.stop()
                cancelPendingCloudContentChange()
                cancelPendingGameplaySaveCheck()
                pendingSyncMode = nil
                automaticSyncGeneration += 1
                automaticSyncTask?.cancel()
                automaticSyncTask = nil
                cloudUnavailableMessage = nil
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
    private let profile: SaveSyncProfile
    private let engine: SaveSyncEngine
    private var gameplaySaveCheckTask: Task<Void, Never>?
    private var gameplaySaveCheckGeneration = 0
    @ObservationIgnored private var isCheckingGameplaySaves = false
    private var pendingSyncMode: SaveSyncMode?
    private var activeSyncMode: SaveSyncMode?
    private var needsBidirectionalSyncBeforeGameplay = true
    private var bidirectionalSyncRequirementGeneration: UInt64 = 0
    private var gameplayReadinessDidChange: (() -> Void)?
    private var automaticSyncTask: Task<Void, Never>?
    private var automaticSyncGeneration = 0
    private var cloudContentChangeTask: Task<Void, Never>?
    private var cloudContentChangeGeneration = 0
    private var observedSaveFileCount: Int?
    private var cloudDownloadDeferred = false
    private var cloudUploadPending = false
    @ObservationIgnored
    nonisolated(unsafe) private var ubiquityIdentityObserver: NSObjectProtocol?
    @ObservationIgnored
    nonisolated(unsafe) private var cloudContentChangeObserver: NSObjectProtocol?
    @ObservationIgnored
    private var cloudMetadataMonitor: CloudSaveMetadataMonitor?
    private(set) var cloudUnavailableMessage: String?

    private let notificationCenter: NotificationCenter
    private let cloudContentChangeDebounce: Duration
    private let gameplaySaveCompletionDebounce: Duration
    private let pregameWaitInterval: Duration
    private let pregameWaitAttempts: Int
    private let pregameCancellationWaitAttempts: Int

    init(profile: SaveSyncProfile = .jak1(),
         defaults: UserDefaults = .standard, engine: SaveSyncEngine? = nil,
         notificationCenter: NotificationCenter = .default,
         ubiquityIdentityDidChangeNotification: Notification.Name =
            .NSUbiquityIdentityDidChange,
         cloudContentDidChangeNotification: Notification.Name =
            .goalpadCloudSaveContentDidChange,
         cloudContentChangeDebounce: Duration = .milliseconds(250),
         gameplaySaveCompletionDebounce: Duration = .milliseconds(250),
         pregameWaitInterval: Duration = .milliseconds(50),
         pregameWaitAttempts: Int = 160,
         pregameCancellationWaitAttempts: Int = 20) {
        self.defaults = defaults
        self.profile = profile
        self.notificationCenter = notificationCenter
        self.cloudContentChangeDebounce = cloudContentChangeDebounce
        self.gameplaySaveCompletionDebounce = gameplaySaveCompletionDebounce
        self.pregameWaitInterval = pregameWaitInterval
        self.pregameWaitAttempts = pregameWaitAttempts
        self.pregameCancellationWaitAttempts = pregameCancellationWaitAttempts
        let enabled: Bool
        if !profile.supportsManagedSaveSync {
            enabled = false
        } else if defaults.object(forKey: profile.enabledDefaultsKey) == nil {
            enabled = true
        } else {
            enabled = defaults.bool(forKey: profile.enabledDefaultsKey)
        }
        isEnabled = enabled
        status = enabled ? .waiting : .disabled
        if let data = defaults.data(forKey: profile.lastResolutionsDefaultsKey),
           let stored = try? JSONDecoder().decode([SaveResolution].self, from: data) {
            recentResolutions = stored
        } else {
            recentResolutions = []
        }
        lastSuccessfulSyncDate = nil
        cloudUnavailableMessage = nil
        observedSaveFileCount = nil
        cloudMetadataMonitor = nil
        let usesProductionEngine = engine == nil
        self.engine = engine ?? SaveSyncEngine(configuration: .init(
            localRoot: profile.localSavesDirectory,
            localConflictsRoot: profile.localConflictsDirectory,
            stateFile: profile.stateFile,
            format: profile.format,
            cloudLocations: profile.cloudLocations,
            coordinateCloudAccess: profile.coordinateCloudAccess,
            cloudUnavailableReason: profile.cloudUnavailableReason))
        ubiquityIdentityObserver = notificationCenter.addObserver(
            forName: ubiquityIdentityDidChangeNotification, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.ubiquityIdentityDidChange()
            }
        }
        cloudContentChangeObserver = notificationCenter.addObserver(
            forName: cloudContentDidChangeNotification, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cloudContentDidChange()
            }
        }
        if usesProductionEngine {
            let monitor = CloudSaveMetadataMonitor(
                notificationCenter: notificationCenter,
                cloudRoot: { profile.cloudLocations()?.savesRoot },
                didChange: {
                    notificationCenter.post(name: cloudContentDidChangeNotification,
                                            object: nil)
                })
            cloudMetadataMonitor = monitor
            if enabled { monitor.start() }
        }
    }

    deinit {
        if let ubiquityIdentityObserver {
            notificationCenter.removeObserver(ubiquityIdentityObserver)
        }
        if let cloudContentChangeObserver {
            notificationCenter.removeObserver(cloudContentChangeObserver)
        }
    }

    var isBusy: Bool { activeOperation != nil }

    private var hasActiveSaveWork: Bool {
        activeOperation != nil || isCheckingGameplaySaves
    }

    var isTransferring: Bool {
        activeOperation == .importing || activeOperation == .exporting
            || activeOperation == .restoringArchive
    }

    var hasPendingGameplaySaveCheck: Bool { gameplaySaveCheckTask != nil }

    func setGameplayReadinessHandler(_ handler: @escaping () -> Void) {
        gameplayReadinessDidChange = handler
    }

    var progressMessage: String? {
        switch activeOperation {
        case .syncing:
            activeSyncMode == .uploadOnly ? "Uploading saves…" : "Syncing saves…"
        case .checking: "Checking saves…"
        case .importing: "Importing saves…"
        case .exporting: "Exporting saves…"
        case .loadingArchives: "Loading preserved saves…"
        case .restoringArchive: "Making preserved save active…"
        case nil: nil
        }
    }

    func refreshArchivedSaves() async {
        guard !hasActiveSaveWork else { return }
        activeOperation = .loadingArchives
        do {
            archivedSaves = try await engine.archivedSaveCandidates()
        } catch {
            transferMessage = "Preserved saves issue: \(error.localizedDescription)"
        }
        activeOperation = nil
        await drainPendingSync()
    }

    func promoteArchivedSave(_ candidate: ArchivedSaveCandidate) async {
        guard !hasActiveSaveWork else { return }
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
        launcherDidAppear()
    }

    /// Reconciles saves as soon as the Library is visible, before a title starts gameplay.
    /// Repeated appearance callbacks share an already queued or active bidirectional sync.
    func launcherDidAppear() {
        guard isEnabled else { return }
        cloudMetadataMonitor?.start()
        guard !isGameplayActive else { return }
        guard activeSyncMode != .bidirectional, pendingSyncMode != .bidirectional else { return }
        scheduleAutomaticSync(.bidirectional, announceWaiting: true)
    }

    func syncNow(mode requestedMode: SaveSyncMode? = nil) async {
        guard isEnabled else { return }
        defer { gameplayReadinessDidChange?() }
        let mode = requestedMode ?? (isGameplayActive ? .uploadOnly : .bidirectional)
        enqueueSync(mode)
        await drainPendingSync()
    }

    func syncBeforeGameplay() async -> Bool {
        guard supportsManagedSaveSync else { return true }
        setGameplayActive(false)
        var waitAttempts = 0
        while hasPregameSaveWork {
            guard waitAttempts < pregameWaitAttempts else {
                return await finishTimedOutPregameSync()
            }
            waitAttempts += 1
            do {
                try await Task.sleep(for: pregameWaitInterval)
            } catch {
                return false
            }
        }
        if isEnabled, needsBidirectionalSyncBeforeGameplay {
            scheduleAutomaticSync(.bidirectional)
            while hasPregameSaveWork {
                guard waitAttempts < pregameWaitAttempts else {
                    return await finishTimedOutPregameSync()
                }
                waitAttempts += 1
                do {
                    try await Task.sleep(for: pregameWaitInterval)
                } catch {
                    return false
                }
            }
        }
        return await checkLocalGameplaySafety()
    }

    /// Importing can outlive the launcher's first provider snapshot. Require one final cloud
    /// reconciliation before the newly imported game is allowed to boot.
    func gameDataImportDidFinish() {
        guard isEnabled else { return }
        markBidirectionalSyncRequired()
        gameplayReadinessDidChange?()
    }

    private func checkLocalGameplaySafety() async -> Bool {
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

    /// Called once when the native memcard reports a newly completed save. The write is synchronous,
    /// so the bank is closed before this event; coalescing keeps file I/O off the frame loop.
    func gameplaySaveCompleted() {
        guard isEnabled, isGameplayActive else { return }
        guard !hasActiveSaveWork else {
            enqueueSync(.uploadOnly)
            return
        }
        guard gameplaySaveCheckTask == nil else { return }
        gameplaySaveCheckGeneration += 1
        let generation = gameplaySaveCheckGeneration
        let debounce = gameplaySaveCompletionDebounce
        gameplaySaveCheckTask = Task { [weak self] in
            do {
                try await Task.sleep(for: debounce)
            } catch {
                self?.clearGameplaySaveCheckTask(for: generation)
                return
            }
            await self?.checkGameplaySaveCompletion(for: generation)
        }
    }

    private func checkGameplaySaveCompletion(for generation: Int) async {
        guard isEnabled, isGameplayActive, !Task.isCancelled,
              generation == gameplaySaveCheckGeneration else {
            clearGameplaySaveCheckTask(for: generation)
            return
        }
        guard !hasActiveSaveWork else {
            enqueueSync(.uploadOnly)
            clearGameplaySaveCheckTask(for: generation)
            return
        }

        isCheckingGameplaySaves = true
        do {
            if let outcome = try await engine.syncIfLocalFilesChanged(mode: .uploadOnly) {
                if isEnabled {
                    apply(outcome, mode: .uploadOnly)
                } else {
                    status = .disabled
                }
            }
        } catch is CancellationError {
            // Lifecycle cancellation is expected; no new save check is synthesized.
        } catch {
            status = isEnabled ? .failed(error.localizedDescription) : .disabled
        }
        isCheckingGameplaySaves = false
        clearGameplaySaveCheckTask(for: generation)
        await drainPendingSync()
    }

    func importSaves(from source: URL) async {
        guard !hasActiveSaveWork else { return }
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
        guard !hasActiveSaveWork else { return }
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
        defaults.removeObject(forKey: profile.lastResolutionsDefaultsKey)
    }

    func setGameplayActive(_ active: Bool) {
        let wasActive = isGameplayActive
        isGameplayActive = active
        if !active {
            cancelPendingGameplaySaveCheck()
        }
        if wasActive, !active {
            markBidirectionalSyncRequired()
        }
    }

    var summary: String {
        switch status {
        case .disabled: return "Off — saves stay on this device"
        case .waiting: return "Waiting to sync"
        case .syncing: return "Syncing…"
        case .unavailable:
            let localSummary = "iCloud unavailable — using local saves"
            guard let cloudUnavailableMessage else { return localSummary }
            return localSummary + ". " + cloudUnavailableMessage
        case .synced(_, let uploaded, let downloaded, let resolutions):
            if cloudDownloadDeferred {
                return "Newer iCloud saves are waiting — return to the Library to download them"
            }
            if cloudUploadPending {
                return "Waiting for iCloud to finish uploading saves"
            }
            if observedSaveFileCount == 0 {
                return "No saves found on this device or in iCloud"
            }
            if !resolutions.isEmpty { return resolutionNotice(for: resolutions) }
            if uploaded == 0 && downloaded == 0 {
                return "No differences found in currently available iCloud saves"
            }
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

    private var hasPregameSaveWork: Bool {
        hasActiveSaveWork || gameplaySaveCheckTask != nil || cloudContentChangeTask != nil
            || pendingSyncMode != nil || automaticSyncTask != nil
    }

    private func scheduleAutomaticSync(_ mode: SaveSyncMode,
                                       announceWaiting: Bool = false) {
        enqueueSync(mode)
        if announceWaiting, activeOperation == nil {
            status = .waiting
        }
        guard automaticSyncTask == nil else { return }
        automaticSyncGeneration += 1
        let generation = automaticSyncGeneration
        automaticSyncTask = Task { [weak self] in
            guard let self else { return }
            while self.hasActiveSaveWork {
                do {
                    try await Task.sleep(for: .milliseconds(10))
                } catch {
                    self.finishAutomaticSync(generation: generation)
                    return
                }
            }
            await self.drainPendingSync()
            self.finishAutomaticSync(generation: generation)
        }
    }

    private func finishAutomaticSync(generation: Int) {
        guard automaticSyncGeneration == generation else { return }
        automaticSyncTask = nil
        gameplayReadinessDidChange?()
    }

    private func finishTimedOutPregameSync() async -> Bool {
        let timedOutDuringCloudSync = activeOperation == .syncing
            || activeSyncMode != nil || pendingSyncMode != nil || automaticSyncTask != nil
            || cloudContentChangeTask != nil
        if timedOutDuringCloudSync {
            cancelPendingCloudContentChange()
            pendingSyncMode = nil
            automaticSyncTask?.cancel()
        }

        var cancellationAttempts = 0
        while hasActiveSaveWork || gameplaySaveCheckTask != nil || cloudContentChangeTask != nil
                || automaticSyncTask != nil {
            guard cancellationAttempts < pregameCancellationWaitAttempts else {
                status = .failed("Save preparation is still finishing. Wait a moment and try Play again.")
                gameplayReadinessDidChange?()
                return false
            }
            cancellationAttempts += 1
            do {
                try await Task.sleep(for: pregameWaitInterval)
            } catch {
                return false
            }
        }

        if timedOutDuringCloudSync {
            status = .failed("iCloud saves did not respond in time. Using local saves; use Sync in Settings to retry.")
        }
        return await checkLocalGameplaySafety()
    }

    private func ubiquityIdentityDidChange() {
        guard isEnabled else { return }
        cloudMetadataMonitor?.restart()
        markBidirectionalSyncRequired()
        cloudUnavailableMessage = nil
        if activeOperation == nil {
            status = .waiting
        }
        scheduleAutomaticSync(isGameplayActive ? .uploadOnly : .bidirectional)
    }

    private func cloudContentDidChange() {
        guard isEnabled else { return }
        markBidirectionalSyncRequired()
        cloudContentChangeGeneration += 1
        let generation = cloudContentChangeGeneration
        cloudContentChangeTask?.cancel()
        cloudContentChangeTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: cloudContentChangeDebounce)
            } catch {
                return
            }
            guard isEnabled, generation == cloudContentChangeGeneration else { return }
            cloudContentChangeTask = nil
            scheduleAutomaticSync(isGameplayActive ? .uploadOnly : .bidirectional)
        }
        gameplayReadinessDidChange?()
    }

    private func cancelPendingCloudContentChange() {
        cloudContentChangeGeneration += 1
        cloudContentChangeTask?.cancel()
        cloudContentChangeTask = nil
    }

    private func markBidirectionalSyncRequired() {
        bidirectionalSyncRequirementGeneration &+= 1
        needsBidirectionalSyncBeforeGameplay = true
    }

    private func drainPendingSync() async {
        guard !hasActiveSaveWork else { return }
        while isEnabled, let mode = pendingSyncMode {
            pendingSyncMode = nil
            activeOperation = .syncing
            activeSyncMode = mode
            status = .syncing
            let requirementGenerationAtStart = bidirectionalSyncRequirementGeneration
            var completedBidirectionalReconciliation = false
            do {
                let outcome = try await engine.sync(mode: mode)
                guard isEnabled else {
                    activeOperation = nil
                    activeSyncMode = nil
                    status = .disabled
                    pendingSyncMode = nil
                    return
                }
                apply(outcome, mode: mode)
                completedBidirectionalReconciliation = outcome.availability == .available
                    && !outcome.requiresBidirectionalSync && !outcome.cloudUploadPending
            } catch is CancellationError {
                if isEnabled { status = .waiting }
            } catch {
                status = isEnabled ? .failed(error.localizedDescription) : .disabled
            }
            if mode == .bidirectional {
                needsBidirectionalSyncBeforeGameplay = !completedBidirectionalReconciliation
                    || requirementGenerationAtStart != bidirectionalSyncRequirementGeneration
            }
            activeOperation = nil
            activeSyncMode = nil
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

    private func cancelPendingGameplaySaveCheck() {
        guard !isCheckingGameplaySaves else { return }
        gameplaySaveCheckTask?.cancel()
        gameplaySaveCheckGeneration += 1
        gameplaySaveCheckTask = nil
    }

    private func clearGameplaySaveCheckTask(for generation: Int) {
        guard gameplaySaveCheckGeneration == generation else { return }
        gameplaySaveCheckTask = nil
    }

    private func apply(_ outcome: SaveSyncOutcome, mode: SaveSyncMode) {
        guard outcome.availability == .available else {
            cloudUnavailableMessage = outcome.unavailableReason?.recoveryMessage
            status = .unavailable
            return
        }
        cloudUnavailableMessage = nil
        observedSaveFileCount = outcome.observedLocalFileCount
            + outcome.observedCloudFileCount
        cloudDownloadDeferred = outcome.requiresBidirectionalSync
        cloudUploadPending = outcome.cloudUploadPending
        if cloudDownloadDeferred || cloudUploadPending {
            needsBidirectionalSyncBeforeGameplay = true
        }
        if !outcome.resolutions.isEmpty {
            recentResolutions = outcome.resolutions
            if let data = try? JSONEncoder().encode(recentResolutions) {
                defaults.set(data, forKey: profile.lastResolutionsDefaultsKey)
            }
        }
        if !cloudDownloadDeferred, !cloudUploadPending,
           (observedSaveFileCount ?? 0) > 0, mode == .bidirectional {
            lastSuccessfulSyncDate = outcome.completedAt
        }
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
        case uploadOnly
        case unavailable
        case synced
        case failed
    }

    let phase: Phase
    let summary: String
    let progressMessage: String?
    let settingsEnabled: Bool
    let settingsSummary: String
    let settingsLastSyncDate: Date?
    let savesEnabled: Bool
    let savesSummary: String
    let savesLastSyncDate: Date?
    let savesAreUploadOnly: Bool
    let actionTitle: String
    let isActionEnabled: Bool

    var lastSyncDate: Date? {
        [settingsLastSyncDate, savesLastSyncDate].compactMap { $0 }.max()
    }
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
              savesProgressMessage: saves.progressMessage,
              savesGameplayActive: saves.isGameplayActive)
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
                      savesProgressMessage: String?,
                      savesGameplayActive: Bool = false) -> CloudSyncPresentationState {
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
        } else if savesEnabled && savesGameplayActive {
            phase = .uploadOnly
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

        let savesAreUploadOnly = savesEnabled && savesGameplayActive
        let canUseUploadOnlySummary = savesSummary == "Up to date"
            || savesSummary.hasPrefix("No differences found")
            || savesSummary.hasPrefix("Synced:")
        let displayedSavesSummary = savesAreUploadOnly && savesFailure == nil
            && !savesUnavailable && canUseUploadOnlySummary
            ? "Gameplay active — saves upload only"
            : savesSummary
        let actionTitle: String
        if phase == .failed || phase == .unavailable {
            actionTitle = "Retry"
        } else if savesAreUploadOnly {
            actionTitle = settingsEnabled ? "Sync Settings & Upload Saves" : "Upload Saves"
        } else {
            actionTitle = "Sync"
        }

        return CloudSyncPresentationState(
            phase: phase,
            summary: summary(phase: phase,
                             settingsEnabled: settingsEnabled,
                             settingsSummary: settingsSummary,
                             settingsFailure: settingsFailure,
                             settingsUnavailable: settingsUnavailable,
                             savesEnabled: savesEnabled,
                             savesSummary: displayedSavesSummary,
                             savesFailure: savesFailure,
                             savesUnavailable: savesUnavailable,
                             progressMessage: progressMessage),
            progressMessage: progressMessage,
            settingsEnabled: settingsEnabled,
            settingsSummary: settingsSummary,
            settingsLastSyncDate: settingsLastSyncDate,
            savesEnabled: savesEnabled,
            savesSummary: displayedSavesSummary,
            savesLastSyncDate: savesLastSyncDate,
            savesAreUploadOnly: savesAreUploadOnly,
            actionTitle: actionTitle,
            isActionEnabled: anyEnabled && !settingsSyncing && !savesSyncing
                && !(savesEnabled && savesIsBusy))
    }

    static func synchronize(settingsEnabled: Bool,
                            savesEnabled: Bool,
                            syncSettings: () async -> Void,
                            syncSaves: () async -> Void) async {
        guard !Task.isCancelled else { return }
        if settingsEnabled, savesEnabled {
            async let settingsSync: Void = syncSettings()
            async let savesSync: Void = syncSaves()
            _ = await (settingsSync, savesSync)
        } else if settingsEnabled {
            await syncSettings()
        } else if savesEnabled {
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
                let savesPrefix = "iCloud unavailable — using local saves"
                let recovery = savesSummary.hasPrefix(savesPrefix)
                    ? savesSummary.dropFirst(savesPrefix.count) : ""
                return "iCloud unavailable — using local settings and saves" + recovery
            }
            if settingsUnavailable {
                return "iCloud unavailable for settings — using local settings"
            }
            return savesSummary
        case .waiting:
            return "Waiting to sync"
        case .uploadOnly:
            if settingsEnabled { return settingsSummary }
            return savesSummary
        case .synced:
            if settingsEnabled && !savesEnabled { return settingsSummary }
            if savesEnabled && !settingsEnabled { return savesSummary }
            return savesSummary == "Up to date" ? "Up to date" : savesSummary
        }
    }
}

private struct SettingsGamePicker: View {
    let selectedTitle: GameLibraryTitle
    let isGameRunning: Bool
    let selectTitle: (GameLibraryTitle) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach([GameLibraryTitle.jak1, .jak2]) { title in
                Button { selectTitle(title) } label: {
                    SettingsGamePickerChoice(
                        title: title.settingsPickerLabel,
                        isSelected: title == selectedTitle,
                        availability: isGameRunning && title != selectedTitle
                            ? "Locked while playing" : "Available",
                        showsAvailability: false
                    )
                }
                .buttonStyle(.plain)
                .disabled(isGameRunning || title == selectedTitle)
            }
            SettingsGamePickerChoice(title: GameLibraryTitle.jak3.settingsPickerLabel,
                                     isSelected: false,
                                     availability: "Planned",
                                     showsAvailability: true)
        }
        .accessibilityValue("\(selectedTitle.settingsPickerLabel) selected")
    }
}

private struct SettingsGamePickerChoice: View {
    let title: String
    let isSelected: Bool
    let availability: String
    let showsAvailability: Bool

    private var titleColor: Color {
        if isSelected { return DarkEcoTheme.accent }
        #if os(visionOS)
        return .white.opacity(0.8)
        #else
        return .secondary
        #endif
    }

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
            if showsAvailability {
                Text(availability)
                    .font(.caption2)
            }
        }
            .foregroundStyle(titleColor)
            .frame(maxWidth: .infinity, minHeight: 32)
            .overlay(alignment: .bottom) {
                if isSelected {
                    Capsule()
                        .fill(DarkEcoTheme.accent)
                        .frame(height: 2)
                        .padding(.horizontal, 12)
                }
            }
            .accessibilityLabel(title)
            .accessibilityValue(isSelected ? "Selected" : availability)
    }
}

private struct SettingsRowLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .foregroundStyle(DarkEcoTheme.accent)
            configuration.title
                .foregroundStyle(.primary)
        }
    }
}

struct SaveSettingsView: View {
    private enum SaveTransferPicker {
        case importSaves
        case exportSaves
    }

    private enum SettingsCategory: Hashable {
        case controls
        case graphics
        case iCloud
        case saves
    }

    @Bindable var sync: SaveSyncController
    @Bindable var settings: PresentationSettings
    @Bindable var input: ControllerInput
    let selectedTitle: GameLibraryTitle
    let isGameRunning: Bool
    let selectSettingsTitle: (GameLibraryTitle) -> Void
    let returnToLibrary: () -> Void
    @State private var saveTransferPicker: SaveTransferPicker?
    @State private var archivedSaveToPromote: ArchivedSaveCandidate?
    @State private var isConfirmingReturnToLibrary = false
    @State private var isConfirmingResetAll = false
    @State private var expandedCategories: Set<SettingsCategory> = []
    @State private var tipStore = EcoTipStore()

    var body: some View {
        Form {
            Section("Game") {
                SettingsGamePicker(selectedTitle: selectedTitle,
                                   isGameRunning: isGameRunning,
                                   selectTitle: selectSettingsTitle)
            }

            #if os(macOS)
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
            #endif

            Section {
                DisclosureGroup(isExpanded: expansion(for: .controls)) {
                    controlsContent
                } label: {
                    Label("Controls", systemImage: "gamecontroller")
                }
            }

            Section {
                DisclosureGroup(isExpanded: expansion(for: .graphics)) {
                    graphicsContent
                } label: {
                    Label("Graphics", systemImage: "display")
                }
            }

            if sectionVisibility.showsICloudSection {
                Section("iCloud") {
                    HStack(spacing: 10) {
                        ZStack {
                            Color.clear
                            if cloudState.progressMessage != nil {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                        .frame(width: 18, height: 18)
                        .accessibilityHidden(cloudState.progressMessage == nil)
                        Label(cloudState.summary, systemImage: cloudStatusSymbol)
                    }

                    DisclosureGroup(isExpanded: expansion(for: .iCloud)) {
                        Toggle("Sync Settings", isOn: $settings.cloudSyncEnabled)
                            .disabled(settings.syncStatus == .syncing)
                        Toggle("Sync Saves", isOn: $sync.isEnabled)
                            .disabled(sync.isBusy)
                        if cloudState.settingsEnabled {
                            LabeledContent("Settings", value: cloudState.settingsSummary)
                            if let date = cloudState.settingsLastSyncDate {
                                LabeledContent("Last settings sync", value: date.formatted(
                                    date: .abbreviated, time: .shortened))
                            }
                        }
                        if cloudState.savesEnabled {
                            LabeledContent("Saves", value: cloudState.savesSummary)
                            if let date = cloudState.savesLastSyncDate {
                                LabeledContent("Last saves sync",
                                               value: date.formatted(date: .abbreviated,
                                                                     time: .shortened))
                            }
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
                    } label: {
                        Label("Sync Options", systemImage: "icloud")
                    }
                }
            }

            if sectionVisibility.showsSaveTransferSection {
                if (sync.isTransferring || sync.activeOperation == .loadingArchives),
                   let message = sync.progressMessage {
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

                DisclosureGroup(isExpanded: expansion(for: .saves)) {
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
                    Text("Dark Eco imports and exports four compatible save slots. "
                         + "When copies differ, the older copy is preserved automatically.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    if !sync.supportsManagedSaveSync {
                        Text(sync.managedSaveSyncUnavailableMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Divider()
                    Text("Preserved Saves")
                        .font(.headline)
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
                    Text("Choose Make Active to restore a preserved native save. Dark Eco "
                         + "preserves the current active copy before replacing it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } label: {
                    Label("Manage Save Files", systemImage: "externaldrive")
                }
            }

            Section {
                Button("Reset All to Defaults", role: .destructive) {
                    isConfirmingResetAll = true
                }
            }

            Section {
                NavigationLink {
                    EcoAboutView(tipStore: tipStore)
                } label: {
                    Label("About", systemImage: "info.circle")
                }
            } footer: {
                HStack {
                    Spacer()
                    Text(GOALPadBuildIdentity.versionText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .textCase(nil)
            }
        }
        .foregroundStyle(.primary)
        .navigationTitle("\(selectedTitle.settingsPickerLabel) Settings")
        .labelStyle(SettingsRowLabelStyle())
        .tint(DarkEcoTheme.accent)
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
        .confirmationDialog(
            "Reset all settings?",
            isPresented: $isConfirmingResetAll,
            titleVisibility: .visible
        ) {
            Button("Reset All to Defaults", role: .destructive) {
                settings.resetAll()
                input.setPrimarySource(settings.primaryInputSource)
                input.setBindings(settings.jak1InputBindings)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This restores the default controls and graphics settings.")
        }
        #if os(macOS)
        .confirmationDialog("Return to Library?",
                            isPresented: $isConfirmingReturnToLibrary,
                            titleVisibility: .visible) {
            Button("Return to Library", role: .destructive) { returnToLibrary() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Dark Eco will close the running game. Progress since your last in-game save will be lost.")
        }
        #endif
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

    private var sectionVisibility: SaveSettingsSectionVisibility {
        SaveSettingsSectionVisibility(
            supportsManagedSaveSync: sync.supportsManagedSaveSync,
            supportsSaveTransfer: sync.supportsSaveTransfer)
    }

    private var cloudState: CloudSyncPresentationState {
        CloudSyncPresentation.state(settings: settings, saves: sync)
    }

    private var cloudStatusSymbol: String {
        switch cloudState.phase {
        case .disabled: "icloud.slash"
        case .waiting, .syncing, .uploadOnly: "arrow.triangle.2.circlepath.icloud"
        case .unavailable, .failed: "exclamationmark.icloud"
        case .synced: "checkmark.icloud"
        }
    }

    private func expansion(for category: SettingsCategory) -> Binding<Bool> {
        Binding(
            get: { expandedCategories.contains(category) },
            set: { isExpanded in
                if isExpanded {
                    expandedCategories.insert(category)
                } else {
                    expandedCategories.remove(category)
                }
            }
        )
    }

    @ViewBuilder
    private var controlsContent: some View {
            #if os(iOS)
            NavigationLink {
                TouchControlsGuideView(gameTitle: selectedTitle == .jak2 ? .jak2 : .jak1)
            } label: {
                Label("Touch Controls Guide", systemImage: "hand.tap")
            }
            #endif
            Toggle("Rumble", isOn: Binding(
                get: { settings.rumbleEnabled },
                set: { settings.setRumbleEnabled($0) }
            ))
            #if os(iOS)
            NavigationLink {
                TouchStickSettingsView(settings: settings)
            } label: {
                LabeledContent("Touch Sticks", value: "Size & Position")
            }
            #endif
            #if !os(visionOS)
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
                Text("The selected source is not connected. Dark Eco uses Automatic until it returns.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            #endif
            NavigationLink {
                ControllerBindingsSettingsView(settings: settings, input: input)
            } label: {
                LabeledContent("Controller Bindings", value: controllerBindingStatus)
            }
            #if !os(visionOS)
            NavigationLink {
                KeyboardMouseBindingsSettingsView(settings: settings, input: input)
            } label: {
                LabeledContent("Mouse & Keyboard Bindings",
                               value: keyboardMouseBindingStatus)
            }
            #endif
            Button("Restore Controls Defaults") {
                settings.restoreDefaults(for: .controls)
                input.setPrimarySource(settings.primaryInputSource)
                input.setBindings(settings.jak1InputBindings)
                input.setRumbleEnabled(settings.rumbleEnabled)
            }
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var graphicsContent: some View {
            Picker("Profile", selection: Binding(
                get: { settings.profile(for: .graphics) },
                set: { settings.setProfile($0, for: .graphics) }
            )) {
                ForEach(SettingsProfile.allCases, id: \.self) { profile in
                    Text(profile.title).tag(profile)
                }
            }
            .pickerStyle(.segmented)

            #if os(iOS)
            Toggle("ProMotion", isOn: Binding(
                get: { settings.graphicsHighFrameRate },
                set: { settings.setGraphicsHighFrameRate($0) }
            ))
            #elseif os(visionOS)
            Toggle("90 Hz", isOn: Binding(
                get: { settings.graphicsVisionHighFrameRate },
                set: { settings.setGraphicsVisionHighFrameRate($0) }
            ))
            #endif

            Toggle("Fit to Screen", isOn: Binding(
                get: { settings.graphicsFillWidth },
                set: { settings.setGraphicsFillWidth($0) }
            ))
            Text("On widens the game to fill the window. Off preserves the original 4:3 view.")
                .font(.callout)
                .foregroundStyle(.secondary)

            #if os(visionOS) && GOALPAD_EXPERIMENTAL_VISION_STEREO
            Toggle("Stereoscopic 3D", isOn: Binding(
                get: { settings.graphicsStereo3D },
                set: { settings.setGraphicsStereo3D($0) }
            ))
            Text("Renders a fixed left/right pair from the game's existing camera inside the "
                + "normal game window. Turn it off to use Comfort mode.")
                .font(.callout)
                .foregroundStyle(.secondary)
            #endif

            Button("Restore Graphics Defaults") {
                settings.restoreDefaults(for: .graphics)
            }
            .foregroundStyle(.secondary)
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
                Text("250% is the default camera response. Horizontal and vertical "
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
