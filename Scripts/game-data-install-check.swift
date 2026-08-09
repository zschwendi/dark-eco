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
    let profile: GameDataProfile
    let worker: GameDataInstallWorker

    init(profile: GameDataProfile = .jak1) throws {
        self.profile = profile
        root = FileManager.default.temporaryDirectory.appending(
            path: "goalpad-game-data-install-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        active = root.appending(
            path: "Documents/\(profile.gameDirectoryName)", directoryHint: .isDirectory)
        staging = root.appending(
            path: "Library/Application Support/GOALPad/GameDataImport/"
                + profile.gameDirectoryName,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        worker = GameDataInstallWorker(configuration: .init(
            activeDirectory: active,
            stagingRoot: staging,
            profile: profile
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
    let prepared = root.appending(
        path: "out/\(profile.preparedDirectoryName)", directoryHint: .isDirectory)
    try writeCompletePreparedData(at: prepared, profile: profile, payload: payload)
    return prepared
}

@MainActor private func preexistingActiveInstallIsRecognized() throws {
    print("a complete preexisting active install is recognized without importing")
    let fixture = try Fixture()
    try writeCompletePreparedData(at: fixture.active)

    let report = GameDataInspector.inspect(gameDirectory: fixture.active)
    check(report.status == .ready, "the existing Documents/Jak1 install is ready immediately")
    check(report.canBoot, "the existing install keeps the launcher bootable")
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
    let manifest = GameDataProfile.jak1.manifest
    check(result.filesCopied == manifest.requiredFileCount,
          "the result reports every prepared source file")
    check(fixture.candidates.isEmpty, "the activated candidate no longer occupies staging")
    check(!manifest.levelArchives.contains("TSZ.DGO"),
          "the base-retail manifest does not require the repository example zone")
}

@MainActor private func profilesKeepDefaultAndJak2StorageIsolated() {
    print("the public default and Jak II prepared-data contract remain isolated")
    let documents = URL(fileURLWithPath: "/synthetic/Documents", isDirectory: true)
    let jak1 = GameDataLayout.gameDirectory(for: .jak1, in: documents)
    let jak2 = GameDataLayout.gameDirectory(for: .jak2, in: documents)

    check(GameDataProfile.active == .jak1, "the ordinary Swift build still defaults to Jak 1")
    check(jak1.path.hasSuffix("/Documents/Jak1"), "Jak 1 keeps Documents/Jak1")
    check(jak2.path.hasSuffix("/Documents/Jak2"), "Jak II uses Documents/Jak2")
    check(jak1 != jak2, "the two active-install directories cannot overlap")
    let jak1Manifest = GameDataProfile.jak1.manifest
    check(jak1Manifest.requiredSupportFiles.isEmpty
          && jak1Manifest.preparedDataContractVersion == nil
          && jak1Manifest.requiredFileCount == jak1Manifest.bootArchives.count
              + jak1Manifest.levelArchives.count + jak1Manifest.levelGeometry.count,
          "Jak 1 keeps its exact existing readiness manifest")
    check(GameDataProfile.jak2.preparedFolderName == "out/jak2",
          "Jak II accepts the desktop-compatible out/jak2 root")
    let manifest = GameDataProfile.jak2.manifest
    check(manifest.bootArchives == ["KERNEL.CGO", "GAME.CGO"]
          && manifest.levelArchives == [
              "TITLE.DGO", "CWI.DGO", "CTA.DGO", "PRI.DGO", "FEA.DGO", "INTROCST.DGO",
              "LDJAKBRN.DGO",
          ]
          && manifest.levelGeometry == [
              "GAME.fr3", "title.fr3", "ctywide.fr3", "ctysluma.fr3", "prison.fr3",
              "forexita.fr3", "introcst.fr3", "ldjakbrn.fr3",
          ]
          && manifest.requiredSupportFiles == [
              "DEMO1.SBK", "CTYWIDE1.SBK", "FOREXIT1.SBK", "FOREXIT2.SBK",
          ]
          && manifest.preparedDataContractVersion == 1,
          "Jak II declares the source-derived title and initial New Game contract v1")
    check(GameDataProfile.jak2.supportsRawMediaPreparation,
          "Jak II routes raw ISO and ZIP input through its selected composer")
    check(GameDataProfile.jak2.supportsRuntimeLaunch,
          "Jak II contract readiness can enter the experimental native runtime")
}

@MainActor private func jak2TitleAndGameplayCandidateActivatesInItsOwnProfile() async throws {
    print("a prepared out/jak2 candidate reaches launch-contract readiness without a completeness claim")
    let fixture = try Fixture(profile: .jak2)
    let source = try preparedFolder(under: fixture.root, profile: .jak2)
    let result = try await fixture.worker.install(
        from: source,
        using: PreparedFolderCandidateProducer()
    ) { _ in }

    let report = GameDataInspector.inspect(gameDirectory: fixture.active, profile: .jak2)
    check(source.path.hasSuffix("/out/jak2"), "the prepared Jak II root keeps OpenGOAL naming")
    check(result.filesCopied == GameDataProfile.jak2.manifest.requiredFileCount,
          "the candidate contains every title and initial New Game contract file")
    check(report.status == .ready && report.profile == .jak2,
          "the candidate satisfies only the selected Jak II contract")
    check(report.canLaunchRuntime, "the versioned launch contract can enter the native runtime")
    check(report.summary.contains("Jak II title/gameplay launch contract v1 ready")
          && report.summary.contains("initial New Game path")
          && report.summary.contains("full-game data completeness or playability"),
          "Jak II readiness names its bounded contract without claiming complete game data")
    check(!FileManager.default.fileExists(
        atPath: fixture.root.appending(path: "Documents/Jak1").path),
          "a Jak II activation does not create or replace Documents/Jak1")
}

@MainActor private func jak2ThreeFileBootstrapCannotLaunch() throws {
    print("the former three-file Jak II bootstrap cannot satisfy launch readiness")
    let fixture = try Fixture(profile: .jak2)
    try write("fixture", to: fixture.active.appending(path: "iso/KERNEL.CGO"))
    try write("fixture", to: fixture.active.appending(path: "iso/GAME.CGO"))
    try write("fixture", to: fixture.active.appending(path: "fr3/GAME.fr3"))

    let report = GameDataInspector.inspect(gameDirectory: fixture.active, profile: .jak2)
    check(report.canBoot, "the kernel archives remain distinguishable from launch readiness")
    check(report.status == .incomplete && !report.canLaunchRuntime,
          "three bootstrap files cannot be reported ready or launchable")
    check(report.missingLevelArchives.contains("TITLE.DGO")
          && report.missingLevelArchives.contains("PRI.DGO")
          && report.missingLevelGeometry.contains("title.fr3")
          && report.missingLevelGeometry.contains("prison.fr3")
          && report.missingSupportFiles.contains("DEMO1.SBK")
          && report.missingSupportFiles.contains("FOREXIT1.SBK"),
          "the report identifies title, initial gameplay, geometry, and support-file gaps")
    check(report.summary.contains("Jak II title/gameplay launch contract v1")
          && !report.summary.localizedCaseInsensitiveContains("complete"),
          "the incomplete report names the versioned contract without calling it complete")
}

@MainActor private func jak2RecoveryAndSymlinkRulesRemainFailClosed() async throws {
    print("Jak II keeps candidate recovery and symbolic-link rejection")
    let recovery = try Fixture(profile: .jak2)
    let partial = recovery.root.appending(
        path: "partial/out/jak2/iso", directoryHint: .isDirectory)
    try write("kernel", to: partial.appending(path: "KERNEL.CGO"))

    do {
        _ = try await recovery.worker.install(
            from: partial.deletingLastPathComponent(),
            using: PreparedFolderCandidateProducer()
        ) { _ in }
        check(false, "the incomplete Jak II launch candidate is rejected")
    } catch let failure as GameDataImportFailure {
        check(failure.code == .candidateIncomplete && failure.candidatePreserved,
              "the incomplete Jak II candidate remains recoverable")
    }
    let preserved = recovery.candidates.first
    check(preserved.flatMap { read($0.appending(path: "iso/KERNEL.CGO")) } == "kernel",
          "the preserved Jak II candidate stays in its profile staging root")

    let completeRoot = recovery.root.appending(path: "complete", directoryHint: .isDirectory)
    let complete = try preparedFolder(under: completeRoot, profile: .jak2)
    _ = try await recovery.worker.install(
        from: complete,
        using: PreparedFolderCandidateProducer()
    ) { _ in }
    check(GameDataInspector.inspect(gameDirectory: recovery.active, profile: .jak2).status == .ready,
          "a later complete Jak II attempt activates independently")
    check(preserved.map { recovery.candidates.contains($0) } == true,
          "the earlier recoverable candidate is not mixed into the later attempt")

    let unsafe = try Fixture(profile: .jak2)
    let source = unsafe.root.appending(
        path: "unsafe/out/jak2", directoryHint: .isDirectory)
    let iso = source.appending(path: "iso", directoryHint: .isDirectory)
    let kernel = iso.appending(path: "KERNEL.CGO")
    try write("kernel", to: kernel)
    try FileManager.default.createSymbolicLink(
        at: iso.appending(path: "GAME.CGO"),
        withDestinationURL: kernel
    )
    try write("geometry", to: source.appending(path: "fr3/GAME.fr3"))

    do {
        _ = try await unsafe.worker.install(
            from: source,
            using: PreparedFolderCandidateProducer()
        ) { _ in }
        check(false, "a symbolic link cannot enter Jak II staging")
    } catch let failure as GameDataImportFailure {
        check(failure.code == .sourceUnavailable && !failure.candidatePreserved,
              "Jak II reports the unsafe source before creating a candidate")
    }
    check(unsafe.candidates.isEmpty, "unsafe Jak II bytes never enter staging")
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
    check(incompleteCandidate.map { fixture.candidates.contains($0) } == true,
          "the failed candidate was not mixed into or deleted by the later selection")
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
    print("cancellation preserves both the active install and recoverable staging")
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
    let cancelledCandidate = fixture.candidates.first
    check(cancelledCandidate != nil, "the cancelled candidate remains available for recovery")
    let partials = (try? FileManager.default.contentsOfDirectory(
        at: cancelledCandidate?.appending(path: "iso", directoryHint: .isDirectory)
            ?? fixture.staging,
        includingPropertiesForKeys: nil
    ))?.filter { $0.lastPathComponent.hasSuffix(".partial") } ?? []
    check(partials.isEmpty, "cancelled per-file temporary output is removed")
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
    await gate.release()
    _ = try await first.value
    check(GameDataInspector.inspect(gameDirectory: fixture.active).status == .ready,
          "the original request completes without interleaved writes")
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
    check(fixture.candidates.count == 1, "the fully validated candidate remains recoverable")
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
            try await completeCandidateActivates()
            profilesKeepDefaultAndJak2StorageIsolated()
            try await jak2TitleAndGameplayCandidateActivatesInItsOwnProfile()
            try jak2ThreeFileBootstrapCannotLaunch()
            try await jak2RecoveryAndSymlinkRulesRemainFailClosed()
            try await incompleteCandidateIsRecoverable()
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
