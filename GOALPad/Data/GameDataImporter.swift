import Foundation
import OSLog

#if canImport(UIKit)
import UIKit
#endif

nonisolated private let importLog = Logger(subsystem: "com.zephyrstudiosllc.eco",
                                           category: "Import")

@MainActor
final class DeviceIdleTimerAssertions {
    enum Owner: Hashable {
        case gameDataImport
        case gameplay
    }

    static let shared = DeviceIdleTimerAssertions()

    private var owners: Set<Owner> = []
    private let apply: @MainActor (Bool) -> Void

    init(apply: @escaping @MainActor (Bool) -> Void = { disabled in
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }) {
        self.apply = apply
    }

    func setDisabled(_ disabled: Bool, for owner: Owner) {
        let wasDisabled = !owners.isEmpty
        if disabled {
            owners.insert(owner)
        } else {
            owners.remove(owner)
        }
        let isDisabled = !owners.isEmpty
        if isDisabled != wasDisabled {
            apply(isDisabled)
        }
    }
}

/// Main-actor state for compatible game-data selection.
///
/// File work is serialized by `GameDataInstallWorker`: it writes a recoverable candidate in
/// Application Support, validates that candidate, and only then switches the selected profile's
/// Documents directory.
@MainActor
@Observable
final class GameDataImporter {
    typealias Progress = GameDataImportProgress

    nonisolated enum State: Sendable {
        case idle
        case scanning
        case copying(Progress)
        case cancelling
        case finished(filesCopied: Int, filesSkipped: Int)
        case cancelled
        case failed(GameDataImportFailure)
    }

    private(set) var state: State = .idle
    let profile = GameDataProfile.active
    private let worker: GameDataInstallWorker
    private let preparedFolderProducer: any GameDataCandidateProducing
    private let rawISOProducer: RawISOCandidateProducer
    private let archivedISOProducer: ZIPISOCandidateProducer
    private let idleTimerAssertions: DeviceIdleTimerAssertions
    private var task: Task<Void, Never>?
    private(set) var isImportWorkActive = false
    private var highestReportedOverallProgress = 0.0

    init(
        worker: GameDataInstallWorker = GameDataInstallWorker(),
        preparedFolderProducer: any GameDataCandidateProducing = PreparedFolderCandidateProducer(),
        idleTimerAssertions: DeviceIdleTimerAssertions? = nil
    ) {
        self.worker = worker
        self.preparedFolderProducer = preparedFolderProducer
        self.idleTimerAssertions = idleTimerAssertions ?? .shared
        rawISOProducer = RawISOCandidateProducer()
        archivedISOProducer = ZIPISOCandidateProducer(
            downstream: RawISOCandidateProducer(
                overallProgressRange: 0.25...0.85
            )
        )
    }

    var isRunning: Bool {
        switch state {
        case .scanning, .copying, .cancelling: return true
        default: return false
        }
    }

    var canStart: Bool { task == nil }

    var canImportRawMedia: Bool {
        profile.supportsRawMediaPreparation
            && RawISOCandidateProducer.isAvailable()
    }

    /// `source` may be a supported raw or archived disc image, the directory holding `iso/`
    /// and `fr3/`, or either of those two prepared directories on its own.
    func start(from source: URL, onFinish: @escaping @MainActor () async -> Void) {
        guard task == nil else { return }
        let producer: any GameDataCandidateProducing
        switch GameDataImportSource(url: source) {
        case .preparedFolder:
            producer = preparedFolderProducer
        case .rawISO where canImportRawMedia:
            producer = rawISOProducer
        case .archivedISO where canImportRawMedia:
            producer = archivedISOProducer
        case .rawISO:
            state = .failed(GameDataImportFailure(
                code: .appResourcesUnavailable,
                message: rawISOUnavailableMessage,
                candidatePreserved: false
            ))
            Task { await onFinish() }
            return
        case .archivedISO:
            state = .failed(GameDataImportFailure(
                code: .appResourcesUnavailable,
                message: archivedISOUnavailableMessage,
                candidatePreserved: false
            ))
            Task { await onFinish() }
            return
        case .unsupportedArchive:
            state = .failed(GameDataImportFailure(
                code: .unsupportedArchive,
                message: unsupportedArchiveMessage,
                candidatePreserved: false
            ))
            Task { await onFinish() }
            return
        }

        state = .scanning
        highestReportedOverallProgress = 0
        setImportWorkActive(true)
        task = Task { [self, producer] in
            do {
                let result = try await worker.install(
                    from: source,
                    using: producer
                ) { progress in
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        if case .cancelling = self.state { return }
                        var displayedProgress = progress
                        self.highestReportedOverallProgress = max(
                            self.highestReportedOverallProgress,
                            progress.overallProgress
                        )
                        displayedProgress.overallProgressOverride =
                            self.highestReportedOverallProgress
                        self.state = progress.phase == .scanning
                            ? .scanning : .copying(displayedProgress)
                    }
                }
                setImportWorkActive(false)
                importLog.notice("Activated compatible game data with \(result.filesCopied) prepared file(s)")
                await onFinish()
                state = .finished(
                    filesCopied: result.filesCopied,
                    filesSkipped: result.filesSkipped
                )
            } catch {
                setImportWorkActive(false)
                if Task.isCancelled || error is CancellationError {
                    state = .cancelled
                } else if let failure = error as? GameDataImportFailure {
                    importLog.error(
                        "Import failed with code \(failure.code.rawValue, privacy: .public): \(failure.message, privacy: .private)"
                    )
                    state = .failed(failure)
                    await onFinish()
                } else {
                    state = .failed(GameDataImportFailure(
                        code: .stagingFailed,
                        message: error.localizedDescription,
                        candidatePreserved: true
                    ))
                    await onFinish()
                }
            }
            task = nil
        }
    }

    func cancel() {
        guard isImportWorkActive else { return }
        state = .cancelling
        task?.cancel()
    }

    func reset() {
        guard task == nil else { return }
        state = .idle
    }

    private func setImportWorkActive(_ active: Bool) {
        guard isImportWorkActive != active else { return }
        isImportWorkActive = active
        idleTimerAssertions.setDisabled(active, for: .gameDataImport)
    }

    private var rawISOUnavailableMessage: String {
        guard profile.supportsRawMediaPreparation else {
            return "Raw .iso preparation is not available for \(profile.displayName) in this build. "
                + "Choose a prepared OpenGOAL \(profile.preparedFolderName) folder instead."
        }
        return "Raw .iso preparation is not available in this build. "
            + "Choose a prepared game-data folder instead."
    }

    private var archivedISOUnavailableMessage: String {
        guard profile.supportsRawMediaPreparation else {
            return "Archive-to-ISO preparation is not available for \(profile.displayName) in this build. "
                + "Choose a prepared OpenGOAL \(profile.preparedFolderName) folder instead."
        }
        return "Archive-to-ISO preparation is not available in this build. "
            + "Choose a prepared game-data folder instead."
    }

    private var unsupportedArchiveMessage: String {
        guard profile.supportsRawMediaPreparation else {
            return "This archive format is not supported for \(profile.displayName). Choose a prepared "
                + "OpenGOAL \(profile.preparedFolderName) folder."
        }
        return "This archive format is not supported. Choose a ZIP or 7z containing one ISO, "
            + "a raw ISO, or prepared game data."
    }
}
