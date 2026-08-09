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
/// Application Support, validates that candidate, and only then switches `Documents/Jak1`.
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
    private let worker: GameDataInstallWorker
    private let preparedFolderProducer: any GameDataCandidateProducing
    private let rawISOProducer = RawISOCandidateProducer()
    private let zippedISOProducer: ZIPISOCandidateProducer
    private let idleTimerAssertions: DeviceIdleTimerAssertions
    private var task: Task<Void, Never>?
    private(set) var isImportWorkActive = false

    init(
        worker: GameDataInstallWorker = GameDataInstallWorker(),
        preparedFolderProducer: any GameDataCandidateProducing = PreparedFolderCandidateProducer(),
        idleTimerAssertions: DeviceIdleTimerAssertions? = nil
    ) {
        self.worker = worker
        self.preparedFolderProducer = preparedFolderProducer
        self.idleTimerAssertions = idleTimerAssertions ?? .shared
        zippedISOProducer = ZIPISOCandidateProducer(downstream: rawISOProducer)
    }

    var isRunning: Bool {
        switch state {
        case .scanning, .copying, .cancelling: return true
        default: return false
        }
    }

    var canStart: Bool { task == nil }

    /// `source` may be a supported raw or ZIP-contained disc image, the directory holding `iso/`
    /// and `fr3/`, or either of those two prepared directories on its own.
    func start(from source: URL, onFinish: @escaping @MainActor () async -> Void) {
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
            Task { await onFinish() }
            return
        case .zippedISO:
            state = .failed(GameDataImportFailure(
                code: .appResourcesUnavailable,
                message: "ZIP-to-ISO preparation is not available in this build. "
                    + "Choose a prepared game-data folder instead.",
                candidatePreserved: false
            ))
            Task { await onFinish() }
            return
        case .unsupportedArchive:
            state = .failed(GameDataImportFailure(
                code: .unsupportedArchive,
                message: "This archive format is not supported. Choose a standard .zip "
                    + "containing one .iso, a raw .iso, or prepared game data.",
                candidatePreserved: false
            ))
            Task { await onFinish() }
            return
        }

        state = .scanning
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
                        self.state = progress.phase == .scanning ? .scanning : .copying(progress)
                    }
                }
                setImportWorkActive(false)
                importLog.notice("Activated compatible game data with \(result.filesCopied) prepared file(s)")
                await onFinish()
                state = .finished(
                    filesCopied: result.filesCopied,
                    filesSkipped: result.filesSkipped
                )
            } catch is CancellationError {
                setImportWorkActive(false)
                state = .cancelled
            } catch let failure as GameDataImportFailure {
                setImportWorkActive(false)
                state = .failed(failure)
                await onFinish()
            } catch {
                setImportWorkActive(false)
                state = .failed(GameDataImportFailure(
                    code: .stagingFailed,
                    message: error.localizedDescription,
                    candidatePreserved: true
                ))
                await onFinish()
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
}
