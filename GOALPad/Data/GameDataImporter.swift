import Foundation
import OSLog

nonisolated private let importLog = Logger(subsystem: "com.zephyrstudiosllc.eco",
                                           category: "Import")

/// Main-actor state for the prepared-folder picker.
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
    private var task: Task<Void, Never>?

    init(worker: GameDataInstallWorker = GameDataInstallWorker()) {
        self.worker = worker
    }

    var isRunning: Bool {
        switch state {
        case .scanning, .copying: return true
        default: return false
        }
    }

    /// `source` may be the directory that holds `iso/` and `fr3/` (an OpenGOAL `out/jak1`), or
    /// either of those two directories on its own. Raw-disc selection remains disabled until a
    /// producer can satisfy `GameDataCandidateProducing` end to end.
    func start(from source: URL, onFinish: @escaping @MainActor () -> Void) {
        guard task == nil else { return }
        state = .scanning
        task = Task { [self] in
            do {
                let result = try await worker.install(
                    from: source,
                    using: preparedFolderProducer
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
                importLog.notice("Activated prepared Jak 1 data with \(result.filesCopied) copied file(s)")
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
