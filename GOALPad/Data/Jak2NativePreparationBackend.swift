#if os(iOS) && canImport(GOALPadJak2Runtime)
import Foundation
import GOALPadJak2Runtime

nonisolated extension GameDataNativePreparationBackend {
    static let appJak2Composer = GameDataNativePreparationBackend(
        profileIdentifier: .jak2,
        nativeErrorDomain: GOALPadJak2GameDataPreparationErrorDomain,
        isAvailable: {
            GOALPadJak2GameDataPreparationIsAvailable()
        },
        prepare: { sourceURL, candidateURL, resources, report in
            try await runAppJak2Composer(
                sourceURL: sourceURL,
                candidateURL: candidateURL,
                resources: resources,
                report: report
            )
        }
    )

    private static func runAppJak2Composer(
        sourceURL: URL,
        candidateURL: URL,
        resources: GameDataNativePreparationResources,
        report: @escaping ProgressHandler
    ) async throws -> Int {
        let nativeJob = GOALPadJak2GameDataPreparationJob(
            sourceURL: sourceURL,
            candidateURL: candidateURL,
            projectResourceURL: resources.projectResourceURL,
            sourceObjectPackURL: resources.sourceObjectPackURL
        )
        let job = Jak2NativePreparationJobBox(nativeJob)
        let (progressStream, progressContinuation) =
            AsyncStream<GameDataNativePreparationProgress>.makeStream(
                bufferingPolicy: .bufferingNewest(1)
            )
        let reportingTask = Task.detached(priority: .utility) {
            for await progress in progressStream {
                await report(progress)
            }
        }

        let outcome: Jak2NativePreparationOutcome = await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                job.value.start(progress: {
                    (nativeProgress: GOALPadJak2GameDataPreparationProgress) in
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
                }, completion: {
                    (summary: GOALPadJak2GameDataPreparationSummary?, error: Error?) in
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
                            domain: GOALPadJak2GameDataPreparationErrorDomain,
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

nonisolated private final class Jak2NativePreparationJobBox: @unchecked Sendable {
    let value: GOALPadJak2GameDataPreparationJob

    init(_ value: GOALPadJak2GameDataPreparationJob) {
        self.value = value
    }

    func cancel() {
        value.cancel()
    }
}

nonisolated private enum Jak2NativePreparationOutcome: Sendable {
    case success(filesWritten: Int)
    case failure(domain: String, code: Int, message: String)
}
#else
import Foundation

nonisolated extension GameDataNativePreparationBackend {
    static let appJak2Composer = GameDataNativePreparationBackend(
        profileIdentifier: .jak2,
        isAvailable: { false },
        prepare: { _, _, _, _ in 0 }
    )
}
#endif
