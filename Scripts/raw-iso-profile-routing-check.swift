import Foundation

let GOALPadGameDataPreparationErrorDomain =
    "com.zephyrstudiosllc.eco.GameDataPreparation"

func GOALPadGameDataPreparationIsAvailable() -> Bool { true }

enum GOALPadGameDataPreparationErrorCode: Int {
    case invalidArgument = 1
    case cancelled = 2
    case callbackFailed = 3
    case sourcePackFailed = 4
    case isoOpenFailed = 5
    case isoValidationFailed = 6
    case unsupportedRevision = 7
    case graphFailed = 8
    case retailCatalogFailed = 9
    case generatedDataFailed = 10
    case fr3Failed = 11
    case recipeFailed = 12
    case candidateCreateFailed = 13
    case workWriteFailed = 14
    case insufficientStorage = 15
    case materializationFailed = 16
    case candidateFinalizeFailed = 17
    case candidateCleanupFailed = 18
    case allocationFailed = 19
    case unexpectedFailure = 20
    case alreadyStarted = 21
    case projectResourcesFailed = 22
}

enum GOALPadGameDataPreparationPhase: Int {
    case validatingSourcePack = 1
}

final class GOALPadGameDataPreparationProgress {
    let phase = GOALPadGameDataPreparationPhase.validatingSourcePack
    let phaseLabel = "Verifying preparation resources"
    let completed: UInt64 = 1
    let total: UInt64 = 1
    let bytesCompleted: UInt64 = 128
    let currentItem = ""
}

final class GOALPadGameDataPreparationSummary {
    let archivesWritten: UInt32 = 2
    let flatFilesWritten: UInt32 = 3
    let fr3FilesWritten: UInt32 = 4
}

private final class NativeJobRecorder: @unchecked Sendable {
    static let shared = NativeJobRecorder()

    private let lock = NSLock()
    private var storedStarts = 0
    private var storedProjectResourceURL: URL?
    private var storedSourceObjectPackURL: URL?

    func reset() {
        lock.withLock {
            storedStarts = 0
            storedProjectResourceURL = nil
            storedSourceObjectPackURL = nil
        }
    }

    func record(projectResourceURL: URL, sourceObjectPackURL: URL) {
        lock.withLock {
            storedStarts += 1
            storedProjectResourceURL = projectResourceURL
            storedSourceObjectPackURL = sourceObjectPackURL
        }
    }

    var snapshot: (starts: Int, project: URL?, sourcePack: URL?) {
        lock.withLock {
            (storedStarts, storedProjectResourceURL, storedSourceObjectPackURL)
        }
    }
}

final class GOALPadGameDataPreparationJob {
    private let projectResourceURL: URL
    private let sourceObjectPackURL: URL

    init(
        sourceURL _: URL,
        candidateURL _: URL,
        projectResourceURL: URL,
        sourceObjectPackURL: URL
    ) {
        self.projectResourceURL = projectResourceURL
        self.sourceObjectPackURL = sourceObjectPackURL
    }

    func start(
        progress: @escaping (GOALPadGameDataPreparationProgress) -> Void,
        completion: @escaping (GOALPadGameDataPreparationSummary?, Error?) -> Void
    ) {
        NativeJobRecorder.shared.record(
            projectResourceURL: projectResourceURL,
            sourceObjectPackURL: sourceObjectPackURL
        )
        progress(GOALPadGameDataPreparationProgress())
        completion(GOALPadGameDataPreparationSummary(), nil)
    }

    func cancel() {}
}

enum GOALPadRuntimeBridge {
    static func isKernelRunning() -> Bool { false }
}

private actor BackendInvocationRecorder {
    private var count = 0

    func record() { count += 1 }
    func value() -> Int { count }
}

@MainActor private var failures = 0

@MainActor
private func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  ok   \(message)")
    } else {
        print("  FAIL \(message)")
        failures += 1
    }
}

@main
private struct RawISOProfileRoutingCheck {
    @MainActor
    static func main() async {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "goalpad-raw-profile-routing-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appending(path: "disc.iso")
        let candidate = root.appending(path: "candidate", directoryHint: .isDirectory)

        var jak2ResourceNames: [String] = []
        let jak2Project = root.appending(path: "Jak2ProjectResources")
        let jak2Pack = root.appending(path: "Jak2SourceObjectPack")
        let wrongBackendProducer = RawISOCandidateProducer(
            profile: .jak2,
            resourceURL: { name in
                jak2ResourceNames.append(name)
                return name == GameDataProfile.jak2.projectResourceName ? jak2Project : jak2Pack
            },
            nativePreparationBackend: .appJak1Composer
        )

        check(jak2ResourceNames == [
            GameDataProfile.jak2.projectResourceName,
            GameDataProfile.jak2.sourceObjectPackName,
        ], "Jak II looks up only its explicit project and source-pack resource names")
        check(!wrongBackendProducer.isAvailable,
              "the in-process Jak 1 composer never advertises Jak II raw preparation")
        NativeJobRecorder.shared.reset()
        do {
            _ = try await wrongBackendProducer.prepareCandidate(
                from: source,
                activeDirectory: root,
                candidateDirectory: candidate,
                report: { _ in }
            )
            check(false, "wrong-profile preparation is rejected before native work")
        } catch let failure as GameDataImportFailure {
            check(failure.code == .appResourcesUnavailable,
                  "wrong-profile preparation is rejected before native work")
        } catch {
            check(false, "wrong-profile preparation returns the expected typed failure")
        }
        check(NativeJobRecorder.shared.snapshot.starts == 0,
              "wrong-profile routing never constructs or starts the Jak 1 native job")

        let unavailableJak2Producer = RawISOCandidateProducer(
            profile: .jak2,
            resourceURL: { name in
                name == GameDataProfile.jak2.projectResourceName ? jak2Project : jak2Pack
            },
            nativePreparationBackend: .appJak2Composer
        )
        check(!unavailableJak2Producer.isAvailable,
              "the Jak II framework backend fails closed on non-iOS hosts")

        var jak1ResourceNames: [String] = []
        let jak1Project = root.appending(path: "OpenGOALProjectResources")
        let jak1Pack = root.appending(path: "Jak1SourceObjectPack")
        let jak1Producer = RawISOCandidateProducer(
            profile: .jak1,
            resourceURL: { name in
                jak1ResourceNames.append(name)
                return name == GameDataProfile.jak1.projectResourceName ? jak1Project : jak1Pack
            },
            nativePreparationBackend: .appJak1Composer
        )
        #if GOALPAD_JAK2
        check(!jak1Producer.isAvailable,
              "a Jak II-configured app cannot activate the in-process compatibility backend")
        NativeJobRecorder.shared.reset()
        _ = try? await jak1Producer.prepareCandidate(
            from: source,
            activeDirectory: root,
            candidateDirectory: candidate,
            report: { _ in }
        )
        check(NativeJobRecorder.shared.snapshot.starts == 0,
              "a Jak II-configured app never reaches the compatibility native job")
        #else
        check(jak1Producer.isAvailable,
              "the existing Jak 1 composer remains available with both verified resources")
        NativeJobRecorder.shared.reset()
        do {
            let result = try await jak1Producer.prepareCandidate(
                from: source,
                activeDirectory: root,
                candidateDirectory: candidate,
                report: { _ in }
            )
            let snapshot = NativeJobRecorder.shared.snapshot
            check(result.filesCopied == 9 && result.filesSkipped == 0,
                  "Jak 1 preserves the native summary-to-result behavior")
            check(snapshot.starts == 1 && snapshot.project == jak1Project
                    && snapshot.sourcePack == jak1Pack,
                  "Jak 1 passes its exact looked-up resources to the native job")
        } catch {
            check(false, "Jak 1 native preparation remains callable")
        }
        #endif
        check(jak1ResourceNames == [
            GameDataProfile.jak1.projectResourceName,
            GameDataProfile.jak1.sourceObjectPackName,
        ], "Jak 1 resource lookup remains explicit and ordered")

        let jak2BackendCalls = BackendInvocationRecorder()
        let uniqueJak2Backend = GameDataNativePreparationBackend(
            profileIdentifier: .jak2,
            isAvailable: { true },
            prepare: { _, _, resources, _ in
                await jak2BackendCalls.record()
                return resources.projectResourceURL == jak2Project
                    && resources.sourceObjectPackURL == jak2Pack ? 1 : 0
            }
        )
        let injectedJak2Producer = RawISOCandidateProducer(
            profile: .jak2,
            resourceURL: { name in
                name == GameDataProfile.jak2.projectResourceName ? jak2Project : jak2Pack
            },
            nativePreparationBackend: uniqueJak2Backend,
            availableCapacity: { _ in nil }
        )
        check(injectedJak2Producer.isAvailable,
              "Jak II becomes available only when a Jak II-bound backend is injected")
        _ = try? await injectedJak2Producer.prepareCandidate(
            from: source,
            activeDirectory: root,
            candidateDirectory: candidate,
            report: { _ in }
        )
        check(await jak2BackendCalls.value() == 1,
              "the injected Jak II backend receives the preparation request exactly once")

        let storageBackendCalls = BackendInvocationRecorder()
        let storageBackend = GameDataNativePreparationBackend(
            profileIdentifier: .jak2,
            isAvailable: { true },
            prepare: { _, _, _, _ in
                await storageBackendCalls.record()
                return 1
            }
        )
        let exactCapacityProducer = RawISOCandidateProducer(
            profile: .jak2,
            resourceURL: { name in
                name == GameDataProfile.jak2.projectResourceName ? jak2Project : jak2Pack
            },
            nativePreparationBackend: storageBackend,
            availableCapacity: { _ in RawISOCandidateProducer.jak2MinimumWorkingSpaceBytes }
        )
        _ = try? await exactCapacityProducer.prepareCandidate(
            from: source,
            activeDirectory: root,
            candidateDirectory: candidate,
            report: { _ in }
        )
        check(await storageBackendCalls.value() == 1,
              "Jak II preparation starts when the required working space is available")

        let lowCapacityProducer = RawISOCandidateProducer(
            profile: .jak2,
            resourceURL: { name in
                name == GameDataProfile.jak2.projectResourceName ? jak2Project : jak2Pack
            },
            nativePreparationBackend: storageBackend,
            availableCapacity: { _ in RawISOCandidateProducer.jak2MinimumWorkingSpaceBytes - 1 }
        )
        do {
            _ = try await lowCapacityProducer.prepareCandidate(
                from: source,
                activeDirectory: root,
                candidateDirectory: candidate,
                report: { _ in }
            )
            check(false, "low Jak II working space fails before native preparation")
        } catch let failure as GameDataImportFailure {
            check(failure.code == .insufficientStorage && !failure.candidatePreserved,
                  "low Jak II working space fails before native preparation")
        } catch {
            check(false, "low Jak II working space returns the expected typed failure")
        }
        check(await storageBackendCalls.value() == 1,
              "the low-space gate does not invoke the native backend")

        let unknownCapacityProducer = RawISOCandidateProducer(
            profile: .jak2,
            resourceURL: { name in
                name == GameDataProfile.jak2.projectResourceName ? jak2Project : jak2Pack
            },
            nativePreparationBackend: storageBackend,
            availableCapacity: { _ in nil }
        )
        _ = try? await unknownCapacityProducer.prepareCandidate(
            from: source,
            activeDirectory: root,
            candidateDirectory: candidate,
            report: { _ in }
        )
        check(await storageBackendCalls.value() == 2,
              "unavailable capacity information defers to native ENOSPC handling")

        let jak2ErrorDomain = "synthetic.jak2.framework.preparation"
        let cancellingJak2Backend = GameDataNativePreparationBackend(
            profileIdentifier: .jak2,
            nativeErrorDomain: jak2ErrorDomain,
            isAvailable: { true },
            prepare: { _, _, _, _ in
                throw GameDataNativePreparationFailure(
                    domain: jak2ErrorDomain,
                    code: GOALPadGameDataPreparationErrorCode.cancelled.rawValue,
                    message: "Synthetic framework cancellation."
                )
            }
        )
        let cancellingJak2Producer = RawISOCandidateProducer(
            profile: .jak2,
            resourceURL: { name in
                name == GameDataProfile.jak2.projectResourceName ? jak2Project : jak2Pack
            },
            nativePreparationBackend: cancellingJak2Backend,
            availableCapacity: { _ in nil }
        )
        do {
            _ = try await cancellingJak2Producer.prepareCandidate(
                from: source,
                activeDirectory: root,
                candidateDirectory: candidate,
                report: { _ in }
            )
            check(false, "the selected Jak II framework domain preserves cancellation")
        } catch is CancellationError {
            check(true, "the selected Jak II framework domain preserves cancellation")
        } catch {
            check(false, "the selected Jak II framework domain preserves cancellation")
        }

        if failures == 0 {
            print("raw ISO profile routing checks passed")
        } else {
            print("raw ISO profile routing checks failed")
            Foundation.exit(1)
        }
    }
}
