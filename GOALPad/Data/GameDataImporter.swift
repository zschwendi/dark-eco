import Foundation
import OSLog

nonisolated private let importLog = Logger(subsystem: "com.zephyrstudiosllc.eco",
                                           category: "Import")

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
    let profile: GameDataProfile
    private let worker: GameDataInstallWorker
    private let preparedFolderProducer = PreparedFolderCandidateProducer()
    private let rawISOProducer: RawISOCandidateProducer
    private let zippedISOProducer: ZIPISOCandidateProducer
    private var task: Task<Void, Never>?

    init(
        profile: GameDataProfile = .active,
        worker: GameDataInstallWorker? = nil
    ) {
        self.profile = profile
        self.worker = worker ?? GameDataInstallWorker(configuration: .app(for: profile))
        let rawISOProducer = RawISOCandidateProducer(profile: profile)
        self.rawISOProducer = rawISOProducer
        zippedISOProducer = ZIPISOCandidateProducer(downstream: rawISOProducer)
    }

    var isRunning: Bool {
        switch state {
        case .scanning, .copying, .cancelling: return true
        default: return false
        }
    }

    var isTaskActive: Bool { task != nil }

    var canChooseSource: Bool { task == nil }

    private var isActivatingCandidate: Bool {
        guard case .copying(let progress) = state else { return false }
        return progress.phase == .activatingCandidate
    }

    var canImportRawMedia: Bool {
        profile.supportsRawMediaPreparation && RawISOCandidateProducer.isAvailable(for: profile)
    }

    /// `source` may be a supported raw or ZIP-contained disc image, the directory holding `iso/`
    /// and `fr3/`, or either of those two prepared directories on its own.
    func start(from source: URL, onFinish: @escaping @MainActor () -> Void) {
        guard task == nil else { return }
        let producer: any GameDataCandidateProducing
        switch GameDataImportSource(url: source) {
        case .preparedFolder:
            producer = preparedFolderProducer
        case .rawISO where canImportRawMedia:
            producer = rawISOProducer
        case .zippedISO where canImportRawMedia:
            producer = zippedISOProducer
        case .rawISO:
            state = .failed(GameDataImportFailure(
                code: .appResourcesUnavailable,
                message: rawISOUnavailableMessage,
                candidatePreserved: false
            ))
            onFinish()
            return
        case .zippedISO:
            state = .failed(GameDataImportFailure(
                code: .appResourcesUnavailable,
                message: zippedISOUnavailableMessage,
                candidatePreserved: false
            ))
            onFinish()
            return
        case .unsupportedArchive:
            state = .failed(GameDataImportFailure(
                code: .unsupportedArchive,
                message: unsupportedArchiveMessage,
                candidatePreserved: false
            ))
            onFinish()
            return
        }

        state = .scanning
        task = Task { [self, producer] in
            let finalState: State
            var shouldNotifyFinish = false
            do {
                let result = try await worker.install(
                    from: source,
                    using: producer
                ) { progress in
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        if case .cancelling = self.state { return }
                        self.state = progress.phase == .scanning ? .scanning : .copying(progress)
                    }
                }
                finalState = .finished(
                    filesCopied: result.filesCopied,
                    filesSkipped: result.filesSkipped
                )
                shouldNotifyFinish = true
                importLog.notice("Activated compatible game data with \(result.filesCopied) prepared file(s)")
            } catch is CancellationError {
                finalState = .cancelled
            } catch let failure as GameDataImportFailure {
                finalState = .failed(failure)
                shouldNotifyFinish = true
            } catch {
                finalState = .failed(GameDataImportFailure(
                    code: .stagingFailed,
                    message: error.localizedDescription,
                    candidatePreserved: true
                ))
                shouldNotifyFinish = true
            }
            task = nil
            state = finalState
            if shouldNotifyFinish { onFinish() }
        }
    }

    func cancel() {
        requestCancellation()
    }

    func appDidEnterBackground() {
        requestCancellation()
    }

    private func requestCancellation() {
        guard task != nil, !isActivatingCandidate else { return }
        if case .cancelling = state { return }
        state = .cancelling
        task?.cancel()
    }

    func reset() {
        guard task == nil else { return }
        state = .idle
    }

    private var rawISOUnavailableMessage: String {
        guard profile.supportsRawMediaPreparation else {
            return "Raw .iso preparation is not available for \(profile.displayName) in this build. "
                + "Choose a prepared OpenGOAL \(profile.preparedFolderName) folder instead."
        }
        return "Raw .iso preparation is not available in this build. "
            + "Choose a prepared game-data folder instead."
    }

    private var zippedISOUnavailableMessage: String {
        guard profile.supportsRawMediaPreparation else {
            return "ZIP-to-ISO preparation is not available for \(profile.displayName) in this build. "
                + "Choose a prepared OpenGOAL \(profile.preparedFolderName) folder instead."
        }
        return "ZIP-to-ISO preparation is not available in this build. "
            + "Choose a prepared game-data folder instead."
    }

    private var unsupportedArchiveMessage: String {
        guard profile.supportsRawMediaPreparation else {
            return "This archive format is not supported for \(profile.displayName). Choose a prepared "
                + "OpenGOAL \(profile.preparedFolderName) folder."
        }
        return "This archive format is not supported. Choose a standard .zip containing one .iso, "
            + "a raw .iso, or prepared game data."
    }
}
