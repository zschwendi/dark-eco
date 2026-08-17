// Synthetic checks for recoverable game-data candidate staging and atomic activation.
// No retail game data is read or written.

import Foundation

@MainActor private var failures = 0

@MainActor private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("  ok   \(message)")
    } else {
        print("  FAIL \(message)")
        failures += 1
    }
}

private final class Fixture: @unchecked Sendable {
    let root: URL
    let active: URL
    let staging: URL
    let worker: GameDataInstallWorker

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "goalpad-game-data-install-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        active = root.appending(path: "Documents/Jak1", directoryHint: .isDirectory)
        staging = root.appending(
            path: "Library/Application Support/GOALPad/GameDataImport/Jak1",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        worker = GameDataInstallWorker(configuration: .init(
            activeDirectory: active,
            stagingRoot: staging
        ))
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    var candidates: [URL] {
        let attempts = staging.appending(path: "Attempts", directoryHint: .isDirectory)
        return ((try? FileManager.default.contentsOfDirectory(
            at: attempts,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []).filter { $0.lastPathComponent.hasSuffix(".candidate") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

private actor PauseGate {
    private var paused = false
    private var continuation: CheckedContinuation<Void, Never>?

    func pause() async {
        paused = true
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilPaused() async {
        while !paused {
            await Task.yield()
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor ProgressRecorder {
    private var values: [GameDataImportProgress] = []

    func record(_ progress: GameDataImportProgress) {
        values.append(progress)
    }

    func maximumFilesTotal(in phase: GameDataImportProgress.Phase) -> Int? {
        values.filter { $0.phase == phase }.map(\.filesTotal).max()
    }
}

private struct FailingCandidateProducer: GameDataCandidateProducing {
    func prepareCandidate(
        from _: URL,
        activeDirectory _: URL,
        candidateDirectory _: URL,
        report _: @escaping @Sendable (GameDataImportProgress) async -> Void
    ) async throws -> GameDataImportResult {
        throw GameDataImportFailure(
            code: .preparationFailed,
            message: "synthetic stop after staging cleanup",
            candidatePreserved: false
        )
    }
}

private func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url, options: .atomic)
}

private func read(_ url: URL) -> String? {
    (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) }
}

private func writeCompletePreparedData(
    at prepared: URL,
    profile: GameDataProfile = .jak1,
    payload: String = "fixture"
) throws {
    let manifest = profile.manifest
    let iso = prepared.appending(path: GameDataLayout.isoDirectoryName, directoryHint: .isDirectory)
    let fr3 = prepared.appending(path: GameDataLayout.fr3DirectoryName, directoryHint: .isDirectory)
    for name in Set(manifest.requiredISOFiles) {
        try write(payload, to: iso.appending(path: name))
    }
    for name in manifest.levelGeometry {
        try write(payload, to: fr3.appending(path: name))
    }
}

private func preparedFolder(
    under root: URL,
    profile: GameDataProfile = .jak1,
    payload: String = "fixture"
) throws -> URL {
    let prepared = root.appending(path: "prepared", directoryHint: .isDirectory)
    try writeCompletePreparedData(at: prepared, profile: profile, payload: payload)
    return prepared
}

@MainActor private func preexistingActiveInstallIsRecognized() throws {
    print("a complete preexisting active install is recognized without importing")
    let uncheckedReport = GameDataReport()
    check(uncheckedReport.status == .checking,
          "an unchecked install is not misreported as empty")
    check(!uncheckedReport.canBoot,
          "an unchecked install cannot enable Play before local inspection")

    let fixture = try Fixture()
    try writeCompletePreparedData(at: fixture.active)

    let report = GameDataInspector.inspect(gameDirectory: fixture.active)
    check(report.status == .ready, "the existing Documents/Jak1 install is ready immediately")
    check(report.canBoot, "the existing install keeps the launcher bootable")
    check(report.summary == "Import Complete ("
            + ByteCountFormatter.string(fromByteCount: report.totalBytes, countStyle: .file) + ")"
            && !report.summary.contains("iso/") && !report.summary.contains("fr3/"),
          "the ready summary reports only the user-facing imported size")
    check(fixture.candidates.isEmpty, "recognition does not create an import candidate")
}

@MainActor private func foregroundRefreshPolicyIsGuarded() {
    print("foreground data refresh runs only outside a live startup or session")
    check(GameDataRefreshPolicy.shouldRefreshOnActivation(
        isRunning: false, isBooting: false, isPreparingGameplay: false
    ), "an idle launcher refreshes after returning to the foreground")
    check(!GameDataRefreshPolicy.shouldRefreshOnActivation(
        isRunning: true, isBooting: false, isPreparingGameplay: false
    ), "a running game does not rescan data")
    check(!GameDataRefreshPolicy.shouldRefreshOnActivation(
        isRunning: false, isBooting: true, isPreparingGameplay: false
    ), "a booting game does not rescan data")
    check(!GameDataRefreshPolicy.shouldRefreshOnActivation(
        isRunning: false, isBooting: false, isPreparingGameplay: true
    ), "an in-flight startup does not rescan data")
}

@MainActor private func overallProgressUsesMeasuredWorkAndPhaseFloors() {
    print("overall import progress uses measured copy work and conservative phase floors")
    let scanning = GameDataImportProgress(phase: .scanning)
    let stagingHalf = GameDataImportProgress(phase: .stagingCurrentInstall,
                                              bytesCopied: 50, bytesTotal: 100)
    let preparingStart = GameDataImportProgress(phase: .preparingCandidate,
                                                bytesCopied: 0, bytesTotal: 100)
    let preparingHalf = GameDataImportProgress(phase: .preparingCandidate,
                                               bytesCopied: 50, bytesTotal: 100)
    let preparingComplete = GameDataImportProgress(phase: .preparingCandidate,
                                                   bytesCopied: 100, bytesTotal: 100)

    check(scanning.overallProgress == 0,
          "scanning starts the aggregate bar at zero")
    check(stagingHalf.overallProgress == 0.075,
          "staging advances only by its measured copy fraction")
    check(preparingStart.overallProgress == 0.15
            && preparingHalf.overallProgress == 0.50
            && preparingComplete.overallProgress == 0.85,
          "preparation maps its measured fraction into the stable overall range")
    check(stagingHalf.overallPercent == 8
            && preparingHalf.overallPercent == 50
            && preparingComplete.overallPercent == 85,
          "the aggregate bar exposes rounded whole-percent progress")
    check(GameDataImportProgress(phase: .validatingCandidate).overallProgress == 0.85
            && GameDataImportProgress(phase: .activatingCandidate).overallProgress == 0.95,
          "unmeasured validation and activation use conservative phase floors")
    let archivedExtractionHalf = GameDataImportProgress.mappedProgress(
        in: 0.15...0.25, fraction: 0.5
    )
    let archivedComposerStart = GameDataImportProgress.mappedProgress(
        in: 0.25...0.85, phaseIndex: 0, phaseCount: 8, fraction: 0
    )
    let archivedComposerLate = GameDataImportProgress.mappedProgress(
        in: 0.25...0.85, phaseIndex: 6, phaseCount: 8, fraction: 0.5
    )
    let archivedComposerComplete = GameDataImportProgress.mappedProgress(
        in: 0.25...0.85, phaseIndex: 7, phaseCount: 8, fraction: 1
    )
    check(abs(archivedExtractionHalf - 0.20) < 0.000_001
            && abs(archivedComposerStart - 0.25) < 0.000_001
            && abs(archivedComposerLate - 0.7375) < 0.000_001
            && abs(archivedComposerComplete - 0.85) < 0.000_001,
          "archive extraction and all eight composer phases occupy one aggregate range")
    let overridden = GameDataImportProgress(
        phase: .preparingCandidate,
        bytesCopied: 90,
        bytesTotal: 100,
        overallProgressOverride: 0.42
    )
    check(overridden.overallProgress == 0.42 && overridden.overallPercent == 42,
          "an aggregate override replaces a nested phase's local percentage")
    check(GameDataImportProgress.Phase.preparingCandidate.playerLabel == "Preparing game data"
            && GameDataImportProgress.Phase.activatingCandidate.playerLabel == "Finishing setup",
          "the UI uses player-facing phase labels")
}

@MainActor private func completeCandidateActivates() async throws {
    print("a complete prepared folder activates only after validation")
    let fixture = try Fixture()
    let source = try preparedFolder(under: fixture.root)
    let result = try await fixture.worker.install(
        from: source,
        using: PreparedFolderCandidateProducer()
    ) { _ in }

    let report = GameDataInspector.inspect(gameDirectory: fixture.active)
    check(report.status == .ready, "the activated install satisfies the existing manifest")
    check(result.filesCopied == GameDataManifest.bootArchives.count
        + GameDataManifest.levelArchives.count + GameDataManifest.levelGeometry.count,
          "the result reports every prepared source file")
    check(fixture.candidates.isEmpty, "the activated candidate no longer occupies staging")
    check(!GameDataManifest.levelArchives.contains("TSZ.DGO"),
          "the base-retail manifest does not require the repository example zone")
}

@MainActor private func incompleteCandidateIsRecoverable() async throws {
    print("an incomplete candidate is retained while the active install stays untouched")
    let fixture = try Fixture()
    let activeMarker = fixture.active.appending(path: "iso/ACTIVE.DAT")
    try write("active", to: activeMarker)

    let partialISO = fixture.root.appending(path: "partial/iso", directoryHint: .isDirectory)
    try write("kernel", to: partialISO.appending(path: "KERNEL.CGO"))

    do {
        _ = try await fixture.worker.install(
            from: partialISO,
            using: PreparedFolderCandidateProducer()
        ) { _ in }
        check(false, "the incomplete candidate is rejected")
    } catch let failure as GameDataImportFailure {
        check(failure.code == .candidateIncomplete, "the failure is typed as incomplete")
        check(failure.candidatePreserved, "the failure reports recoverable staging")
    }

    check(read(activeMarker) == "active", "the prior active install was not replaced")
    let incompleteCandidate = fixture.candidates.first
    check(incompleteCandidate.flatMap { read($0.appending(path: "iso/KERNEL.CGO")) } == "kernel",
          "the partial candidate remains isolated for recovery")

    let complete = try preparedFolder(under: fixture.root, payload: "complete")
    _ = try await fixture.worker.install(
        from: complete,
        using: PreparedFolderCandidateProducer()
    ) { _ in }
    check(GameDataInspector.inspect(gameDirectory: fixture.active).status == .ready,
          "a later folder import completes in a new candidate and activates")
    check(read(fixture.active.appending(path: "iso/ACTIVE.DAT")) == "active",
          "the new attempt seeds the unchanged active install")
    check(incompleteCandidate.map { !fixture.candidates.contains($0) } == true,
          "the explicit later selection removes the prior abandoned candidate")
}

@MainActor private func abandonedCandidateCleanupIsExactAndSafe() async throws {
    print("a new attempt removes only exact app-owned abandoned candidate directories")
    let fixture = try Fixture()
    let attempts = fixture.staging.appending(path: "Attempts", directoryHint: .isDirectory)
    let abandoned = attempts.appending(
        path: "\(UUID().uuidString).candidate", directoryHint: .isDirectory)
    let unrelated = attempts.appending(path: "notes.candidate", directoryHint: .isDirectory)
    let external = fixture.root.appending(path: "external", directoryHint: .isDirectory)
    let externalMarker = external.appending(path: "keep.txt")
    let linkedCandidate = attempts.appending(
        path: "\(UUID().uuidString).candidate", directoryHint: .isDirectory)
    try write("abandoned", to: abandoned.appending(path: "marker"))
    try write("unrelated", to: unrelated.appending(path: "marker"))
    try write("external", to: externalMarker)
    try FileManager.default.createSymbolicLink(at: linkedCandidate, withDestinationURL: external)

    do {
        _ = try await fixture.worker.install(
            from: fixture.root,
            using: FailingCandidateProducer()
        ) { _ in }
        check(false, "the synthetic producer still fails after cleanup")
    } catch let failure as GameDataImportFailure {
        check(failure.code == .preparationFailed,
              "cleanup completes before the synthetic producer failure")
    }

    check(!FileManager.default.fileExists(atPath: abandoned.path),
          "an exact UUID candidate directory is removed")
    check(read(unrelated.appending(path: "marker")) == "unrelated",
          "a non-UUID candidate name is preserved")
    let linkValues = try linkedCandidate.resourceValues(forKeys: [.isSymbolicLinkKey])
    check(linkValues.isSymbolicLink == true && read(externalMarker) == "external",
          "candidate cleanup neither removes nor follows a symbolic link")
}

@MainActor private func sourceFilesAreNotCopiedFromActiveFirst() async throws {
    print("active files supplied by the new source are not staged twice")
    let fixture = try Fixture()
    let activeSource = try preparedFolder(under: fixture.root, payload: "active")
    _ = try await fixture.worker.install(
        from: activeSource,
        using: PreparedFolderCandidateProducer()
    ) { _ in }
    try write("keep", to: fixture.active.appending(path: "iso/ACTIVE-ONLY.DAT"))

    let replacementRoot = fixture.root.appending(
        path: "destination-aware", directoryHint: .isDirectory)
    let replacement = try preparedFolder(under: replacementRoot, payload: "replacement")
    let recorder = ProgressRecorder()
    _ = try await fixture.worker.install(
        from: replacement,
        using: PreparedFolderCandidateProducer()
    ) { progress in
        await recorder.record(progress)
    }

    let stagedFiles = await recorder.maximumFilesTotal(in: .stagingCurrentInstall)
    check(stagedFiles == 1,
          "only the active-only file is seeded before the source copy")
    check(read(fixture.active.appending(path: "iso/GAME.CGO")) == "replacement",
          "the source version becomes active without a redundant active copy")
    check(read(fixture.active.appending(path: "iso/ACTIVE-ONLY.DAT")) == "keep",
          "one-directory merge behavior still retains an unsupplied active file")
}

@MainActor private func cancellationKeepsActiveInstall() async throws {
    print("cancellation preserves the active install and removes partial staging")
    let fixture = try Fixture()
    let activeSource = try preparedFolder(under: fixture.root, payload: "active")
    _ = try await fixture.worker.install(
        from: activeSource,
        using: PreparedFolderCandidateProducer()
    ) { _ in }

    let replacementRoot = fixture.root.appending(path: "replacement", directoryHint: .isDirectory)
    let replacement = try preparedFolder(under: replacementRoot, payload: "replacement")
    let largeFile = replacement.appending(path: "iso/KERNEL.CGO")
    try Data(repeating: 0x7a, count: 3 * 1_024 * 1_024).write(to: largeFile, options: .atomic)

    let cancelledImport = Task {
        try await fixture.worker.install(
            from: replacement,
            using: PreparedFolderCandidateProducer()
        ) { progress in
            if progress.phase == .preparingCandidate,
               progress.bytesCopied >= 1_024 * 1_024
            {
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
    }
    do {
        _ = try await cancelledImport.value
        check(false, "the cancelled import does not activate")
    } catch is CancellationError {
        check(true, "cancellation remains a distinct result")
    }

    check(read(fixture.active.appending(path: "iso/GAME.CGO")) == "active",
          "the previous install remains active after cancellation")
    check(fixture.candidates.isEmpty,
          "the cancelled candidate and per-file temporary output are removed")
    _ = try await fixture.worker.install(
        from: replacement,
        using: PreparedFolderCandidateProducer()
    ) { _ in }
    check(read(fixture.active.appending(path: "iso/GAME.CGO")) == "replacement",
          "a fresh retry acquires the released process lease")
}

@MainActor private func concurrentAttemptIsRejected() async throws {
    print("a second request cannot interleave with an active import")
    let fixture = try Fixture()
    let source = try preparedFolder(under: fixture.root)
    let gate = PauseGate()
    let first = Task {
        try await fixture.worker.install(
            from: source,
            using: PreparedFolderCandidateProducer()
        ) { progress in
            if progress.phase == .scanning {
                await gate.pause()
            }
        }
    }

    await gate.waitUntilPaused()
    do {
        _ = try await fixture.worker.install(
            from: source,
            using: PreparedFolderCandidateProducer()
        ) { _ in }
        check(false, "the second request is rejected as busy")
    } catch let failure as GameDataImportFailure {
        check(failure.code == .busy, "the second request gets an explicit busy failure")
    }

    let secondWindowWorker = GameDataInstallWorker(configuration: .init(
        activeDirectory: fixture.active,
        stagingRoot: fixture.staging,
        profile: .jak1
    ))
    do {
        _ = try await secondWindowWorker.install(
            from: source,
            using: PreparedFolderCandidateProducer()
        ) { _ in }
        check(false, "a second worker cannot race the same title roots")
    } catch let failure as GameDataImportFailure {
        check(failure.code == .busy,
              "the process lease rejects a second worker for the same title")
    }

    let equivalentStagingWorker = GameDataInstallWorker(configuration: .init(
        activeDirectory: fixture.root.appending(path: "OtherActive", directoryHint: .isDirectory),
        stagingRoot: fixture.staging.appending(path: "..")
            .appending(path: fixture.staging.lastPathComponent, directoryHint: .isDirectory),
        profile: .jak1
    ))
    do {
        _ = try await equivalentStagingWorker.install(
            from: source,
            using: PreparedFolderCandidateProducer()
        ) { _ in }
        check(false, "an equivalent staging path cannot bypass the process lease")
    } catch let failure as GameDataImportFailure {
        check(failure.code == .busy,
              "the process lease normalizes equivalent staging paths")
    }

    let alternateStagingWorker = GameDataInstallWorker(configuration: .init(
        activeDirectory: fixture.active,
        stagingRoot: fixture.root.appending(path: "OtherStaging", directoryHint: .isDirectory),
        profile: .jak1
    ))
    do {
        _ = try await alternateStagingWorker.install(
            from: source,
            using: PreparedFolderCandidateProducer()
        ) { _ in }
        check(false, "a second staging root cannot race the same active install")
    } catch let failure as GameDataImportFailure {
        check(failure.code == .busy,
              "the process lease also owns the active-install destination")
    }

    let jak2Active = fixture.root.appending(
        path: "Documents/Jak2", directoryHint: .isDirectory)
    let jak2Staging = fixture.root.appending(
        path: "Library/Application Support/GOALPad/GameDataImport/Jak2",
        directoryHint: .isDirectory
    )
    let jak2Source = try preparedFolder(
        under: fixture.root.appending(path: "jak2-source", directoryHint: .isDirectory),
        profile: .jak2
    )
    let jak2Worker = GameDataInstallWorker(configuration: .init(
        activeDirectory: jak2Active,
        stagingRoot: jak2Staging,
        profile: .jak2
    ))
    _ = try await jak2Worker.install(
        from: jak2Source,
        using: PreparedFolderCandidateProducer()
    ) { _ in }
    check(GameDataInspector.inspect(gameDirectory: jak2Active, profile: .jak2).status == .ready,
          "Jak II can import concurrently through its independent active and staging roots")

    await gate.release()
    _ = try await first.value
    check(GameDataInspector.inspect(gameDirectory: fixture.active).status == .ready,
          "the original request completes without interleaved writes")
    _ = try await secondWindowWorker.install(
        from: source,
        using: PreparedFolderCandidateProducer()
    ) { _ in }
    check(GameDataInspector.inspect(gameDirectory: fixture.active).status == .ready,
          "the same-title process lease is released after the original request completes")
}

@MainActor private func cancellationAtActivationBoundaryDoesNotSwap() async throws {
    print("cancellation at the activation progress boundary cannot switch installs")
    let fixture = try Fixture()
    let active = try preparedFolder(under: fixture.root, payload: "active")
    _ = try await fixture.worker.install(
        from: active,
        using: PreparedFolderCandidateProducer()
    ) { _ in }
    let replacementRoot = fixture.root.appending(
        path: "activation-boundary", directoryHint: .isDirectory)
    let replacement = try preparedFolder(under: replacementRoot, payload: "replacement")
    let cancelledImport = Task {
        try await fixture.worker.install(
            from: replacement,
            using: PreparedFolderCandidateProducer()
        ) { progress in
            if progress.phase == .activatingCandidate {
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
    }

    do {
        _ = try await cancelledImport.value
        check(false, "activation-boundary cancellation is observed")
    } catch is CancellationError {
        check(true, "activation-boundary cancellation is distinct")
    }
    check(read(fixture.active.appending(path: "iso/GAME.CGO")) == "active",
          "the atomic switch did not run after cancellation")
    check(fixture.candidates.isEmpty,
          "the cancelled validated candidate is removed after the worker settles")
}

@MainActor private func unsafeSourceIsRejectedBeforeStaging() async throws {
    print("a symbolic-link source entry never enters candidate staging")
    let fixture = try Fixture()
    let iso = fixture.root.appending(path: "unsafe/iso", directoryHint: .isDirectory)
    let kernel = iso.appending(path: "KERNEL.CGO")
    try write("kernel", to: kernel)
    try FileManager.default.createSymbolicLink(
        at: iso.appending(path: "GAME.CGO"),
        withDestinationURL: kernel
    )

    do {
        _ = try await fixture.worker.install(
            from: iso,
            using: PreparedFolderCandidateProducer()
        ) { _ in }
        check(false, "the symbolic-link source is rejected")
    } catch let failure as GameDataImportFailure {
        check(failure.code == .sourceUnavailable, "unsafe source failure is typed")
        check(!failure.candidatePreserved, "no candidate is claimed before staging begins")
    }
    check(fixture.candidates.isEmpty, "unsafe source bytes never enter a candidate")
}

@MainActor private func activationFailurePreservesCandidate() async throws {
    print("activation failure is explicit and keeps the validated candidate")
    let root = FileManager.default.temporaryDirectory.appending(
        path: "goalpad-game-data-activation-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try preparedFolder(under: root)
    let blockedParent = root.appending(path: "blocked")
    try write("not-a-directory", to: blockedParent)
    let staging = root.appending(path: "staging", directoryHint: .isDirectory)
    let worker = GameDataInstallWorker(configuration: .init(
        activeDirectory: blockedParent.appending(path: "Jak1", directoryHint: .isDirectory),
        stagingRoot: staging
    ))

    do {
        _ = try await worker.install(
            from: source,
            using: PreparedFolderCandidateProducer()
        ) { _ in }
        check(false, "the blocked active path prevents activation")
    } catch let failure as GameDataImportFailure {
        check(failure.code == .activationFailed, "activation has a distinct typed failure")
        check(failure.candidatePreserved, "the validated candidate is reported as preserved")
    }
    let attempts = staging.appending(path: "Attempts", directoryHint: .isDirectory)
    let candidates = ((try? FileManager.default.contentsOfDirectory(
        at: attempts,
        includingPropertiesForKeys: nil
    )) ?? []).filter { $0.lastPathComponent.hasSuffix(".candidate") }
    check(candidates.count == 1, "the valid candidate remains at its private staging path")
}

@MainActor private func exclusiveRenameCannotReplaceARacedDestination() throws {
    print("exclusive activation rename cannot replace a newly created destination")
    let root = FileManager.default.temporaryDirectory.appending(
        path: "goalpad-game-data-exclusive-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appending(path: "incoming", directoryHint: .isDirectory)
    let destination = root.appending(path: "Jak1", directoryHint: .isDirectory)
    try write("incoming", to: source.appending(path: "marker"))
    try write("raced", to: destination.appending(path: "marker"))

    do {
        try renameGameDataItem(from: source, to: destination, mode: .exclusive)
        check(false, "exclusive rename rejects the raced destination")
    } catch let error as POSIXError {
        check(error.code == .EEXIST, "exclusive rename reports EEXIST")
    }
    check(read(source.appending(path: "marker")) == "incoming",
          "the candidate remains available after the exclusive failure")
    check(read(destination.appending(path: "marker")) == "raced",
          "the externally created destination is not replaced")
}

@main
private struct GameDataInstallCheck {
    @MainActor static func main() async {
        do {
            try preexistingActiveInstallIsRecognized()
            foregroundRefreshPolicyIsGuarded()
            overallProgressUsesMeasuredWorkAndPhaseFloors()
            try await completeCandidateActivates()
            try await incompleteCandidateIsRecoverable()
            try await abandonedCandidateCleanupIsExactAndSafe()
            try await sourceFilesAreNotCopiedFromActiveFirst()
            try await cancellationKeepsActiveInstall()
            try await concurrentAttemptIsRejected()
            try await cancellationAtActivationBoundaryDoesNotSwap()
            try await unsafeSourceIsRejectedBeforeStaging()
            try await activationFailurePreservesCandidate()
            try exclusiveRenameCannotReplaceARacedDestination()
        } catch {
            print("  FAIL unexpected error: \(error)")
            failures += 1
        }

        if failures == 0 {
            print("game data install checks passed")
        } else {
            print("game data install checks failed: \(failures)")
            Foundation.exit(1)
        }
    }
}
