import Foundation
import OSLog

nonisolated private let importLog = Logger(subsystem: "com.zephyrstudiosllc.eco",
                                           category: "Import")

/// Main-actor state for compatible game-data selection.
///
/// File work is serialized by `GameDataInstallWorker`: it writes a recoverable candidate in
/// Application Support, validates that candidate, and only then switches `Documents/Jak1`.
@MainActor
@Observable
final class GameDataImporter {
    typealias Progress = GameDataImportProgress

    nonisolated enum State: Sendable {
        case idle
        case scanning
        case copying(Progress)
        case finished(filesCopied: Int, filesSkipped: Int)
        case cancelled
        case failed(GameDataImportFailure)
    }

    private(set) var state: State = .idle
    private let worker: GameDataInstallWorker
    private let preparedFolderProducer = PreparedFolderCandidateProducer()
    private let rawISOProducer = RawISOCandidateProducer()
    private let zippedISOProducer: ZIPISOCandidateProducer
    private var task: Task<Void, Never>?

    init(worker: GameDataInstallWorker = GameDataInstallWorker()) {
        self.worker = worker
        zippedISOProducer = ZIPISOCandidateProducer(downstream: rawISOProducer)
    }

    var isRunning: Bool {
        switch state {
        case .scanning, .copying: return true
        default: return false
        }
    }

    /// `source` may be a supported raw or ZIP-contained disc image, the directory holding `iso/`
    /// and `fr3/`, or either of those two prepared directories on its own.
    func start(from source: URL, onFinish: @escaping @MainActor () -> Void) {
        guard task == nil else { return }
        let producer: any GameDataCandidateProducing
        switch GameDataImportSource(url: source) {
        case .preparedFolder:
            producer = preparedFolderProducer
        case .rawISO where RawISOCandidateProducer.isAvailable():
            producer = rawISOProducer
        case .zippedISO where RawISOCandidateProducer.isAvailable():
            producer = zippedISOProducer
        case .rawISO:
            state = .failed(GameDataImportFailure(
                code: .appResourcesUnavailable,
                message: "Raw .iso preparation is not available in this build. "
                    + "Choose a prepared game-data folder instead.",
                candidatePreserved: false
            ))
            onFinish()
            return
        case .zippedISO:
            state = .failed(GameDataImportFailure(
                code: .appResourcesUnavailable,
                message: "ZIP-to-ISO preparation is not available in this build. "
                    + "Choose a prepared game-data folder instead.",
                candidatePreserved: false
            ))
            onFinish()
            return
        case .unsupportedArchive:
            state = .failed(GameDataImportFailure(
                code: .unsupportedArchive,
                message: "This archive format is not supported. Choose a standard .zip "
                    + "containing one .iso, a raw .iso, or prepared game data.",
                candidatePreserved: false
            ))
            onFinish()
            return
        }

        state = .scanning
        task = Task { [self, producer] in
            do {
                let result = try await worker.install(
                    from: source,
                    using: producer
                ) { progress in
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        self.state = progress.phase == .scanning ? .scanning : .copying(progress)
                    }
                }
                state = .finished(
                    filesCopied: result.filesCopied,
                    filesSkipped: result.filesSkipped
                )
                importLog.notice("Activated compatible game data with \(result.filesCopied) prepared file(s)")
                onFinish()
            } catch is CancellationError {
                state = .cancelled
            } catch let failure as GameDataImportFailure {
                state = .failed(failure)
                onFinish()
            } catch {
                state = .failed(GameDataImportFailure(
                    code: .stagingFailed,
                    message: error.localizedDescription,
                    candidatePreserved: true
                ))
                onFinish()
            }
            task = nil
        }
    }

    func cancel() {
        guard isRunning else { return }
        task?.cancel()
        state = .cancelled
    }

    func reset() {
        guard task == nil else { return }
        state = .idle
    }
}
