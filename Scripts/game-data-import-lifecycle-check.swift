import Foundation

nonisolated struct RawISOCandidateProducer: GameDataCandidateProducing {
    static func isAvailable() -> Bool { false }

    func prepareCandidate(
        from source: URL,
        activeDirectory: URL,
        candidateDirectory: URL,
        report: @escaping @Sendable (GameDataImportProgress) async -> Void
    ) async throws -> GameDataImportResult {
        fatalError("raw ISO preparation is outside this lifecycle check")
    }
}

nonisolated struct ZIPISOCandidateProducer: GameDataCandidateProducing {
    init(downstream: RawISOCandidateProducer) {}

    func prepareCandidate(
        from source: URL,
        activeDirectory: URL,
        candidateDirectory: URL,
        report: @escaping @Sendable (GameDataImportProgress) async -> Void
    ) async throws -> GameDataImportResult {
        fatalError("ZIP preparation is outside this lifecycle check")
    }
}

private actor ControlledCandidateProducer: GameDataCandidateProducing {
    private var attempts = 0
    private var teardownContinuation: CheckedContinuation<Void, Never>?

    func prepareCandidate(
        from source: URL,
        activeDirectory: URL,
        candidateDirectory: URL,
        report: @escaping @Sendable (GameDataImportProgress) async -> Void
    ) async throws -> GameDataImportResult {
        attempts += 1
        await report(GameDataImportProgress(phase: .preparingCandidate))
        do {
            try await Task.sleep(for: .seconds(60))
            throw CancellationError()
        } catch is CancellationError {
            await withCheckedContinuation { continuation in
                teardownContinuation = continuation
            }
            throw CancellationError()
        }
    }

    func attemptCount() -> Int { attempts }
    func isWaitingForTeardown() -> Bool { teardownContinuation != nil }

    func finishTeardown() {
        teardownContinuation?.resume()
        teardownContinuation = nil
    }
}

@MainActor
private final class IdleTimerRecorder {
    private(set) var values: [Bool] = []

    func record(_ value: Bool) {
        values.append(value)
    }
}

@MainActor private var failures = 0

@MainActor
private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("  ok   \(message)")
    } else {
        print("  FAIL \(message)")
        failures += 1
    }
}

private func waitForAttempts(
    _ expected: Int,
    producer: ControlledCandidateProducer
) async -> Bool {
    for _ in 0..<200 {
        if await producer.attemptCount() == expected { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return await producer.attemptCount() == expected
}

private func waitForTeardown(_ producer: ControlledCandidateProducer) async -> Bool {
    for _ in 0..<200 {
        if await producer.isWaitingForTeardown() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return await producer.isWaitingForTeardown()
}

@MainActor
private func waitForCancelled(_ importer: GameDataImporter) async -> Bool {
    for _ in 0..<200 {
        if case .cancelled = importer.state, importer.canStart { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    if case .cancelled = importer.state { return importer.canStart }
    return false
}

@MainActor
private func importerCancellationWaitsForTeardown() async throws {
    print("import cancellation retains worker and idle-timer ownership until teardown")
    let root = FileManager.default.temporaryDirectory.appending(
        path: "goalpad-import-lifecycle-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appending(path: "source", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

    let worker = GameDataInstallWorker(configuration: .init(
        activeDirectory: root.appending(path: "active", directoryHint: .isDirectory),
        stagingRoot: root.appending(path: "staging", directoryHint: .isDirectory)))
    let producer = ControlledCandidateProducer()
    let recorder = IdleTimerRecorder()
    let idleTimer = DeviceIdleTimerAssertions { recorder.record($0) }
    let importer = GameDataImporter(
        worker: worker,
        preparedFolderProducer: producer,
        idleTimerAssertions: idleTimer)
    var finishCalls = 0

    importer.start(from: source) { finishCalls += 1 }
    let firstAttemptStarted = await waitForAttempts(1, producer: producer)
    check(firstAttemptStarted, "the first import owns the worker")
    check(recorder.values == [true] && importer.isImportWorkActive,
          "active import work asserts the idle timer exactly once")

    importer.cancel()
    if case .cancelling = importer.state {
        check(true, "Cancel publishes a truthful cancelling state")
    } else {
        check(false, "Cancel publishes a truthful cancelling state")
    }
    check(!importer.canStart && recorder.values == [true],
          "cancellation keeps retry disabled and the idle timer asserted during teardown")

    importer.start(from: source) { finishCalls += 1 }
    try? await Task.sleep(for: .milliseconds(30))
    let attemptsDuringTeardown = await producer.attemptCount()
    check(attemptsDuringTeardown == 1,
          "an immediate retry cannot collide with the cancelling worker")
    let firstTeardownStarted = await waitForTeardown(producer)
    check(firstTeardownStarted, "the cancelled producer reaches controlled teardown")
    await producer.finishTeardown()
    let firstCancellationFinished = await waitForCancelled(importer)
    check(firstCancellationFinished,
          "cancelled is published only after teardown releases worker ownership")
    check(recorder.values == [true, false] && !importer.isImportWorkActive,
          "worker completion releases the import idle-timer assertion")

    importer.start(from: source) { finishCalls += 1 }
    let retryStarted = await waitForAttempts(2, producer: producer)
    check(retryStarted,
          "Retry starts normally after cancellation teardown")
    check(recorder.values == [true, false, true],
          "Retry reacquires idle-timer ownership for its own active work")
    importer.cancel()
    let retryTeardownStarted = await waitForTeardown(producer)
    check(retryTeardownStarted, "the retry also enters controlled teardown")
    await producer.finishTeardown()
    let retryCancellationFinished = await waitForCancelled(importer)
    check(retryCancellationFinished, "the retry cancellation completes cleanly")
    check(recorder.values == [true, false, true, false] && finishCalls == 0,
          "each worker lifetime has one balanced idle-timer assertion")
}

@MainActor
private func idleTimerOwnersDoNotClobberEachOther() {
    print("idle-timer assertions preserve independent gameplay and import owners")
    let recorder = IdleTimerRecorder()
    let assertions = DeviceIdleTimerAssertions { recorder.record($0) }

    assertions.setDisabled(true, for: .gameDataImport)
    assertions.setDisabled(true, for: .gameplay)
    assertions.setDisabled(false, for: .gameDataImport)
    check(recorder.values == [true],
          "releasing import ownership keeps the gameplay assertion active")
    assertions.setDisabled(false, for: .gameplay)
    check(recorder.values == [true, false],
          "the device idle timer is released after the final owner finishes")
}

@main
private struct GameDataImportLifecycleCheck {
    @MainActor
    static func main() async {
        do {
            try await importerCancellationWaitsForTeardown()
            idleTimerOwnersDoNotClobberEachOther()
        } catch {
            print("  FAIL unexpected error: \(error)")
            failures += 1
        }

        if failures == 0 {
            print("game data import lifecycle checks passed")
        } else {
            print("game data import lifecycle checks failed: \(failures)")
            Foundation.exit(1)
        }
    }
}
