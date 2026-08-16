import Foundation

/// Produces a complete desktop-compatible candidate from one supported profile disc image.
nonisolated struct RawISOCandidateProducer: GameDataCandidateProducing {
    private let profile: GameDataProfile
    private let projectResourceURL: URL?
    private let sourceObjectPackURL: URL?
    private let overallProgressRange: ClosedRange<Double>

    static func isAvailable(
        for profile: GameDataProfile = .active,
        in bundle: Bundle = .main
    ) -> Bool {
        GOALPadGameDataPreparationIsAvailable()
            && bundle.url(forResource: profile.projectResourceName, withExtension: nil) != nil
            && bundle.url(forResource: profile.sourceObjectPackName, withExtension: nil) != nil
    }

    init(
        profile: GameDataProfile = .active,
        bundle: Bundle = .main,
        overallProgressRange: ClosedRange<Double> = 0.15...0.85
    ) {
        self.profile = profile
        projectResourceURL = bundle.url(
            forResource: profile.projectResourceName,
            withExtension: nil
        )
        sourceObjectPackURL = bundle.url(
            forResource: profile.sourceObjectPackName,
            withExtension: nil
        )
        self.overallProgressRange = overallProgressRange
    }

    func prepareCandidate(
        from source: URL,
        activeDirectory _: URL,
        candidateDirectory: URL,
        report: @escaping @Sendable (GameDataImportProgress) async -> Void
    ) async throws -> GameDataImportResult {
        try Task.checkCancellation()
        guard !GOALPadRuntimeBridge.isKernelRunning() else {
            throw GameDataImportFailure(
                code: .busy,
                message: "Close the running game before preparing new game data.",
                candidatePreserved: false
            )
        }
        guard let projectResourceURL, let sourceObjectPackURL else {
            throw GameDataImportFailure(
                code: .appResourcesUnavailable,
                message: "This build is missing its verified game-data preparation resources.",
                candidatePreserved: false
            )
        }

        let nativeJob = GOALPadGameDataPreparationJob(
            sourceURL: source,
            candidateURL: candidateDirectory,
            projectResourceURL: projectResourceURL,
            sourceObjectPackURL: sourceObjectPackURL
        )
        let job = NativePreparationJobBox(nativeJob)
        let (progressStream, progressContinuation) =
            AsyncStream<GameDataImportProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let reportingTask = Task.detached(priority: .utility) {
            for await progress in progressStream {
                await report(progress)
            }
        }

        let outcome: NativePreparationOutcome = await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                job.value.start(progress: { nativeProgress in
                    progressContinuation.yield(self.progress(from: nativeProgress))
                }, completion: { summary, error in
                    if let error {
                        let nativeError = error as NSError
                        continuation.resume(returning: .failure(
                            domain: nativeError.domain,
                            code: nativeError.code,
                            message: nativeError.localizedDescription
                        ))
                    } else if let summary {
                        continuation.resume(returning: .success(
                            filesWritten: Int(summary.archivesWritten)
                                + Int(summary.flatFilesWritten)
                                + Int(summary.fr3FilesWritten)
                        ))
                    } else {
                        continuation.resume(returning: .failure(
                            domain: GOALPadGameDataPreparationErrorDomain,
                            code: GOALPadGameDataPreparationErrorCode.unexpectedFailure.rawValue,
                            message: "Native preparation returned no result."
                        ))
                    }
                })
            }
        }, onCancel: {
            job.cancel()
            progressContinuation.finish()
        })

        progressContinuation.finish()
        await reportingTask.value
        try Task.checkCancellation()

        switch outcome {
        case .success(let filesWritten):
            return GameDataImportResult(filesCopied: filesWritten, filesSkipped: 0)
        case .failure(let domain, let code, let message):
            if domain == GOALPadGameDataPreparationErrorDomain,
               code == GOALPadGameDataPreparationErrorCode.cancelled.rawValue
            {
                throw CancellationError()
            }
            throw Self.importFailure(
                domain: domain,
                code: code,
                message: message,
                candidateDirectory: candidateDirectory
            )
        }
    }

    private func progress(
        from native: GOALPadGameDataPreparationProgress
    ) -> GameDataImportProgress {
        let item = native.currentItem.isEmpty ? native.phaseLabel : native.currentItem
        let phaseFraction = native.total > 0
            ? Double(native.completed) / Double(native.total)
            : 0
        let phaseIndex: Int
        let phaseCount: Int
        if profile.identifier == .jak2 {
            phaseCount = 9
            phaseIndex = native.phase == .validatingProjectResources
                ? 1 : Int(native.phase.rawValue)
        } else {
            phaseCount = 8
            phaseIndex = Int(native.phase.rawValue) - 1
        }
        let overallProgress = GameDataImportProgress.mappedProgress(
            in: overallProgressRange,
            phaseIndex: phaseIndex,
            phaseCount: phaseCount,
            fraction: phaseFraction
        )
        return GameDataImportProgress(
            phase: .preparingCandidate,
            filesCopied: Int(clamping: native.completed),
            filesTotal: Int(clamping: native.total),
            bytesCopied: Int64(clamping: native.bytesCompleted),
            currentFile: item,
            overallProgressOverride: overallProgress
        )
    }

    private static func importFailure(
        domain: String,
        code: Int,
        message: String,
        candidateDirectory: URL
    ) -> GameDataImportFailure {
        let preserved = FileManager.default.fileExists(atPath: candidateDirectory.path)
        guard domain == GOALPadGameDataPreparationErrorDomain,
              let nativeCode = GOALPadGameDataPreparationErrorCode(rawValue: code)
        else {
            return GameDataImportFailure(
                code: .preparationFailed,
                message: message.isEmpty
                    ? "Native game-data preparation failed unexpectedly." : message,
                candidatePreserved: preserved
            )
        }

        switch nativeCode {
        case .isoOpenFailed:
            return GameDataImportFailure(
                code: .sourceUnavailable,
                message: "The selected disc image could not be opened.",
                candidatePreserved: preserved
            )
        case .isoValidationFailed:
            return GameDataImportFailure(
                code: .invalidDiscImage,
                message: message.isEmpty
                    ? "The selected file is not a valid supported disc image." : message,
                candidatePreserved: preserved
            )
        case .unsupportedRevision:
            return GameDataImportFailure(
                code: .unsupportedDiscRevision,
                message: message.isEmpty ? "This disc revision is not supported." : message,
                candidatePreserved: preserved
            )
        case .sourcePackFailed, .projectResourcesFailed:
            return GameDataImportFailure(
                code: .appResourcesUnavailable,
                message: message.isEmpty
                    ? "This build's preparation resources are missing or do not match." : message,
                candidatePreserved: preserved
            )
        case .insufficientStorage:
            return GameDataImportFailure(
                code: .insufficientStorage,
                message: "There is not enough free space to prepare this game data.",
                candidatePreserved: preserved
            )
        case .candidateCreateFailed, .workWriteFailed, .materializationFailed,
             .candidateFinalizeFailed, .candidateCleanupFailed:
            return GameDataImportFailure(
                code: .stagingFailed,
                message: message.isEmpty
                    ? "Dark Eco could not write the prepared game-data candidate." : message,
                candidatePreserved: preserved
            )
        case .cancelled:
            return GameDataImportFailure(
                code: .preparationFailed,
                message: "Game-data preparation was cancelled.",
                candidatePreserved: preserved
            )
        case .invalidArgument, .callbackFailed, .graphFailed, .retailCatalogFailed,
             .generatedDataFailed, .fr3Failed, .recipeFailed, .allocationFailed,
             .unexpectedFailure, .alreadyStarted:
            return GameDataImportFailure(
                code: .preparationFailed,
                message: message.isEmpty
                    ? "Native game-data preparation could not be completed." : message,
                candidatePreserved: preserved
            )
        @unknown default:
            return GameDataImportFailure(
                code: .preparationFailed,
                message: "Native game-data preparation returned an unknown error.",
                candidatePreserved: preserved
            )
        }
    }
}

nonisolated private final class NativePreparationJobBox: @unchecked Sendable {
    let value: GOALPadGameDataPreparationJob

    init(_ value: GOALPadGameDataPreparationJob) {
        self.value = value
    }

    func cancel() {
        value.cancel()
    }
}

nonisolated private enum NativePreparationOutcome: Sendable {
    case success(filesWritten: Int)
    case failure(domain: String, code: Int, message: String)
}
