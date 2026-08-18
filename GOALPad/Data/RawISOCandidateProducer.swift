import Foundation

/// Produces a complete desktop-compatible candidate from one supported profile disc image.
nonisolated struct RawISOCandidateProducer: GameDataCandidateProducing {
    private let profile: GameDataProfile
    private let resources: GameDataNativePreparationResources?
    private let nativePreparationBackend: GameDataNativePreparationBackend
    private let overallProgressRange: ClosedRange<Double>
    private let availableCapacity: @Sendable (URL) -> UInt64?

    /// The validated extraction, bounded FR3 work tree, and final prepared output coexist.
    static let jak2MinimumWorkingSpaceBytes: UInt64 = 5 * 1_024 * 1_024 * 1_024

    static func isAvailable(
        for profile: GameDataProfile,
        in bundle: Bundle = .main,
        nativePreparationBackend: GameDataNativePreparationBackend = .appJak1Composer
    ) -> Bool {
        RawISOCandidateProducer(
            profile: profile,
            bundle: bundle,
            nativePreparationBackend: nativePreparationBackend
        ).isAvailable
    }

    init(
        profile: GameDataProfile,
        bundle: Bundle = .main,
        nativePreparationBackend: GameDataNativePreparationBackend = .appJak1Composer,
        overallProgressRange: ClosedRange<Double> = 0.15...0.85,
        availableCapacity: @escaping @Sendable (URL) -> UInt64? = volumeAvailableCapacity
    ) {
        self.init(
            profile: profile,
            resourceURL: { bundle.url(forResource: $0, withExtension: nil) },
            nativePreparationBackend: nativePreparationBackend,
            overallProgressRange: overallProgressRange,
            availableCapacity: availableCapacity
        )
    }

    init(
        profile: GameDataProfile,
        resourceURL: (String) -> URL?,
        nativePreparationBackend: GameDataNativePreparationBackend,
        overallProgressRange: ClosedRange<Double> = 0.15...0.85,
        availableCapacity: @escaping @Sendable (URL) -> UInt64? = volumeAvailableCapacity
    ) {
        self.profile = profile
        let projectResourceURL = resourceURL(profile.projectResourceName)
        let sourceObjectPackURL = resourceURL(profile.sourceObjectPackName)
        resources = if let projectResourceURL, let sourceObjectPackURL {
            GameDataNativePreparationResources(
                projectResourceURL: projectResourceURL,
                sourceObjectPackURL: sourceObjectPackURL
            )
        } else {
            nil
        }
        self.nativePreparationBackend = nativePreparationBackend
        self.overallProgressRange = overallProgressRange
        self.availableCapacity = availableCapacity
    }

    var isAvailable: Bool {
        resources != nil && nativePreparationBackend.isAvailable(for: profile)
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
        guard nativePreparationBackend.isAvailable(for: profile) else {
            throw GameDataImportFailure(
                code: .appResourcesUnavailable,
                message: "This build has no verified native disc-image preparation backend for "
                    + "\(profile.displayName).",
                candidatePreserved: false
            )
        }
        guard let resources else {
            throw GameDataImportFailure(
                code: .appResourcesUnavailable,
                message: "This build is missing its verified game-data preparation resources.",
                candidatePreserved: false
            )
        }
        if profile.identifier == .jak2,
           let capacity = availableCapacity(candidateDirectory.deletingLastPathComponent()),
           capacity < Self.jak2MinimumWorkingSpaceBytes
        {
            throw GameDataImportFailure(
                code: .insufficientStorage,
                message: "Jak II preparation needs at least 5 GB of free working space. "
                    + "Free more space and try again.",
                candidatePreserved: false
            )
        }
        do {
            let filesWritten = try await nativePreparationBackend.prepare(
                for: profile,
                sourceURL: source,
                candidateURL: candidateDirectory,
                resources: resources,
                report: { nativeProgress in
                    await report(progress(from: nativeProgress))
                }
            )
            try Task.checkCancellation()
            return GameDataImportResult(filesCopied: filesWritten, filesSkipped: 0)
        } catch let failure as GameDataNativePreparationFailure {
            let isNativeFailure = nativePreparationBackend.ownsNativeFailure(failure)
            if isNativeFailure,
               failure.code == GOALPadGameDataPreparationErrorCode.cancelled.rawValue
            {
                throw CancellationError()
            }
            throw Self.importFailure(
                code: failure.code,
                message: failure.message,
                isNativeFailure: isNativeFailure,
                candidateDirectory: candidateDirectory
            )
        }
    }

    private static func volumeAvailableCapacity(at directory: URL) -> UInt64? {
        let values = try? directory.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ])
        return values?.volumeAvailableCapacityForImportantUsage
            .flatMap { $0 > 0 ? UInt64($0) : nil }
            ?? values?.volumeAvailableCapacity.flatMap { $0 > 0 ? UInt64($0) : nil }
    }

    private func progress(
        from native: GameDataNativePreparationProgress
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
        code: Int,
        message: String,
        isNativeFailure: Bool,
        candidateDirectory: URL
    ) -> GameDataImportFailure {
        let preserved = FileManager.default.fileExists(atPath: candidateDirectory.path)
        guard isNativeFailure,
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

nonisolated extension GameDataNativePreparationBackend {
    static let appJak1Composer = GameDataNativePreparationBackend(
        profileIdentifier: .jak1,
        nativeErrorDomain: GOALPadGameDataPreparationErrorDomain,
        isAvailable: { GOALPadGameDataPreparationIsAvailable() },
        prepare: { sourceURL, candidateURL, resources, report in
            try await runAppJak1Composer(
                sourceURL: sourceURL,
                candidateURL: candidateURL,
                resources: resources,
                report: report
            )
        }
    )

    private static func runAppJak1Composer(
        sourceURL: URL,
        candidateURL: URL,
        resources: GameDataNativePreparationResources,
        report: @escaping ProgressHandler
    ) async throws -> Int {
        let nativeJob = GOALPadGameDataPreparationJob(
            sourceURL: sourceURL,
            candidateURL: candidateURL,
            projectResourceURL: resources.projectResourceURL,
            sourceObjectPackURL: resources.sourceObjectPackURL
        )
        let job = NativePreparationJobBox(nativeJob)
        let (progressStream, progressContinuation) =
            AsyncStream<GameDataNativePreparationProgress>.makeStream(
                bufferingPolicy: .bufferingNewest(1)
            )
        let reportingTask = Task.detached(priority: .utility) {
            for await progress in progressStream {
                await report(progress)
            }
        }

        let outcome: NativePreparationOutcome = await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                job.value.start(progress: { nativeProgress in
                    let phase = GameDataNativePreparationPhase(
                        rawValue: Int(nativeProgress.phase.rawValue)
                    ) ?? .validatingSourcePack
                    progressContinuation.yield(GameDataNativePreparationProgress(
                        phase: phase,
                        completed: nativeProgress.completed,
                        total: nativeProgress.total,
                        bytesCompleted: nativeProgress.bytesCompleted,
                        phaseLabel: nativeProgress.phaseLabel,
                        currentItem: nativeProgress.currentItem.isEmpty
                            ? nativeProgress.phaseLabel : nativeProgress.currentItem
                    ))
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
            return filesWritten
        case .failure(let domain, let code, let message):
            throw GameDataNativePreparationFailure(
                domain: domain,
                code: code,
                message: message
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
