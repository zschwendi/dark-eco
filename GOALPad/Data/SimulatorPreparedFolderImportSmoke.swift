#if targetEnvironment(simulator)
import Foundation

/// Opt-in synthetic coverage for the app importer on an iOS simulator. The fixture stays under a
/// disposable temporary root and does not exercise Files providers, raw media, or physical hardware.
@MainActor
enum SimulatorPreparedFolderImportSmoke {
    private static let argumentPrefix = "--goalpad-prepared-folder-import-smoke="
    private static let resultPrefix = "goalpad-prepared-folder-import-smoke-"

    static func runIfRequested() async {
        guard let argument = CommandLine.arguments.first(where: {
            $0.hasPrefix(argumentPrefix)
        }) else {
            return
        }

        let token = String(argument.dropFirst(argumentPrefix.count))
        guard isValid(token: token) else {
            print("GOALPAD_PREPARED_FOLDER_IMPORT_SMOKE FAIL invalid-token")
            return
        }

        let resultURL = FileManager.default.temporaryDirectory.appending(
            path: resultPrefix + token + ".json",
            directoryHint: .notDirectory
        )
        try? FileManager.default.removeItem(at: resultURL)

        do {
            let report = try await run(token: token)
            try write(report, to: resultURL)
            print("GOALPAD_PREPARED_FOLDER_IMPORT_SMOKE PASS token=\(token) files=\(report.expectedFileCount)")
        } catch {
            let report = Report(
                schemaVersion: 1,
                status: "FAIL",
                token: token,
                expectedFileCount: expectedPaths.count,
                successFilesCopied: nil,
                failureCode: nil,
                preservedCandidateCount: nil,
                checks: [:],
                error: error.localizedDescription
            )
            do {
                try write(report, to: resultURL)
            } catch {
                print("GOALPAD_PREPARED_FOLDER_IMPORT_SMOKE FAIL result-write")
                return
            }
            print("GOALPAD_PREPARED_FOLDER_IMPORT_SMOKE FAIL token=\(token)")
        }
    }

    private static func run(token: String) async throws -> Report {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appending(
            path: "goalpad-prepared-folder-import-smoke-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? manager.removeItem(at: root) }

        let activeParent = root.appending(path: "Active", directoryHint: .isDirectory)
        let active = activeParent.appending(
            path: GameDataLayout.gameDirectoryName,
            directoryHint: .isDirectory
        )
        let staging = root.appending(path: "Staging", directoryHint: .isDirectory)
        let successSource = root.appending(path: "SuccessSource", directoryHint: .isDirectory)
        let failureSource = root.appending(path: "FailureSource", directoryHint: .isDirectory)

        try writePreparedData(at: active, payloadPrefix: "prior-active")
        try writePreparedData(at: successSource, payloadPrefix: "success-candidate")
        try writePreparedData(at: failureSource, payloadPrefix: "failure-candidate")

        let priorActive = try preparedSnapshot(at: active)
        let successSourceBefore = try preparedSnapshot(at: successSource)
        let failureSourceBefore = try preparedSnapshot(at: failureSource)
        let worker = GameDataInstallWorker(configuration: .init(
            activeDirectory: active,
            stagingRoot: staging
        ))

        var checks: [String: Bool] = [:]
        let successImporter = GameDataImporter(worker: worker)
        let success = await importSource(successSource, with: successImporter)
        checks["successInitialStateScanning"] = success.initialState == "scanning"

        let successFilesCopied: Int?
        switch successImporter.state {
        case .finished(let copied, let skipped):
            successFilesCopied = copied
            checks["successFinalStateFinished"] = success.finalState == "finished"
            checks["successFilesCopiedExact"] = copied == expectedPaths.count
            checks["successFilesSkippedZero"] = skipped == 0
        default:
            successFilesCopied = nil
            checks["successFinalStateFinished"] = false
            checks["successFilesCopiedExact"] = false
            checks["successFilesSkippedZero"] = false
        }

        let activatedSnapshot = try preparedSnapshot(at: active)
        checks["successActiveChanged"] = activatedSnapshot != priorActive
        checks["successActiveMatchesSource"] = activatedSnapshot == successSourceBefore
        checks["successSourceUnchanged"] = try preparedSnapshot(at: successSource)
            == successSourceBefore
        checks["successInspectorReady"] = GameDataInspector.inspect(gameDirectory: active).status
            == .ready
        checks["successCandidatesCleaned"] = candidateDirectories(in: staging).isEmpty
        checks["successIncomingCleaned"] = incomingDirectories(in: activeParent).isEmpty

        try manager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o555))],
            ofItemAtPath: activeParent.path
        )
        defer {
            try? manager.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o755))],
                ofItemAtPath: activeParent.path
            )
        }
        let failureImporter = GameDataImporter(worker: worker)
        let failure = await importSource(failureSource, with: failureImporter)
        try manager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: activeParent.path
        )
        checks["failureInitialStateScanning"] = failure.initialState == "scanning"

        let failureCode: String?
        switch failureImporter.state {
        case .failed(let value):
            failureCode = value.code.rawValue
            checks["failureFinalStateActivationFailed"] = failure.finalState == "failed"
                && value.code == .activationFailed
            checks["failureReportsCandidatePreserved"] = value.candidatePreserved
        default:
            failureCode = nil
            checks["failureFinalStateActivationFailed"] = false
            checks["failureReportsCandidatePreserved"] = false
        }

        checks["failureActiveUnchanged"] = try preparedSnapshot(at: active)
            == activatedSnapshot
        checks["failureSourceUnchanged"] = try preparedSnapshot(at: failureSource)
            == failureSourceBefore
        checks["failureIncomingAbsent"] = incomingDirectories(in: activeParent).isEmpty

        let preservedCandidates = candidateDirectories(in: staging)
        checks["failurePreservesOneCandidate"] = preservedCandidates.count == 1
        if let preservedCandidate = preservedCandidates.first {
            checks["failureCandidateMatchesSource"] = try preparedSnapshot(at: preservedCandidate)
                == failureSourceBefore
            checks["failureCandidateInspectorReady"] = GameDataInspector.inspect(
                gameDirectory: preservedCandidate
            ).status == .ready
        } else {
            checks["failureCandidateMatchesSource"] = false
            checks["failureCandidateInspectorReady"] = false
        }

        guard checks.values.allSatisfy({ $0 }) else {
            let failed = checks.filter { !$0.value }.keys.sorted().joined(separator: ",")
            throw SmokeError.failedChecks(failed)
        }

        return Report(
            schemaVersion: 1,
            status: "PASS",
            token: token,
            expectedFileCount: expectedPaths.count,
            successFilesCopied: successFilesCopied,
            failureCode: failureCode,
            preservedCandidateCount: preservedCandidates.count,
            checks: checks,
            error: nil
        )
    }

    private static func importSource(
        _ source: URL,
        with importer: GameDataImporter
    ) async -> (initialState: String, finalState: String) {
        var initialState = "unknown"
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            importer.start(from: source) {
                continuation.resume()
            }
            initialState = stateName(importer.state)
        }
        return (initialState, stateName(importer.state))
    }

    private static func stateName(_ state: GameDataImporter.State) -> String {
        switch state {
        case .idle: "idle"
        case .scanning: "scanning"
        case .copying: "copying"
        case .finished: "finished"
        case .cancelled: "cancelled"
        case .failed: "failed"
        }
    }

    private static var expectedPaths: [String] {
        let iso = Set(GameDataManifest.bootArchives + GameDataManifest.levelArchives)
            .map { GameDataLayout.isoDirectoryName + "/" + $0 }
        let fr3 = Set(GameDataManifest.levelGeometry)
            .map { GameDataLayout.fr3DirectoryName + "/" + $0 }
        return (iso + fr3).sorted()
    }

    private static func writePreparedData(at root: URL, payloadPrefix: String) throws {
        for relativePath in expectedPaths {
            let destination = root.appending(path: relativePath, directoryHint: .notDirectory)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("\(payloadPrefix):\(relativePath)".utf8).write(
                to: destination,
                options: .atomic
            )
        }
    }

    private static func preparedSnapshot(at root: URL) throws -> [String: Data] {
        let manager = FileManager.default
        let topLevel = try manager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let topLevelNames = Set(topLevel.map(\.lastPathComponent))
        guard topLevelNames == Set([
            GameDataLayout.isoDirectoryName,
            GameDataLayout.fr3DirectoryName,
        ]) else {
            throw SmokeError.unexpectedLayout(root.lastPathComponent)
        }

        var snapshot: [String: Data] = [:]
        for relativePath in expectedPaths {
            snapshot[relativePath] = try Data(contentsOf: root.appending(path: relativePath))
        }

        let actualPaths = try [GameDataLayout.isoDirectoryName, GameDataLayout.fr3DirectoryName]
            .flatMap { name in
                try manager.contentsOfDirectory(
                    at: root.appending(path: name, directoryHint: .isDirectory),
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ).map { name + "/" + $0.lastPathComponent }
            }
            .sorted()
        guard actualPaths == expectedPaths else {
            throw SmokeError.unexpectedLayout(root.lastPathComponent)
        }
        return snapshot
    }

    private static func candidateDirectories(in staging: URL) -> [URL] {
        let attempts = staging.appending(path: "Attempts", directoryHint: .isDirectory)
        return ((try? FileManager.default.contentsOfDirectory(
            at: attempts,
            includingPropertiesForKeys: nil
        )) ?? []).filter { $0.lastPathComponent.hasSuffix(".candidate") }
    }

    private static func incomingDirectories(in activeParent: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(
            at: activeParent,
            includingPropertiesForKeys: nil
        )) ?? []).filter { $0.lastPathComponent.hasPrefix(".Jak1-") }
    }

    private static func isValid(token: String) -> Bool {
        !token.isEmpty && token.count <= 64
            && token.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).contains($0)
            }
    }

    private static func write(_ report: Report, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: url, options: .atomic)
    }

    private struct Report: Codable {
        let schemaVersion: Int
        let status: String
        let token: String
        let expectedFileCount: Int
        let successFilesCopied: Int?
        let failureCode: String?
        let preservedCandidateCount: Int?
        let checks: [String: Bool]
        let error: String?
    }

    private enum SmokeError: LocalizedError {
        case failedChecks(String)
        case unexpectedLayout(String)

        var errorDescription: String? {
            switch self {
            case .failedChecks(let checks):
                "Failed checks: \(checks)"
            case .unexpectedLayout(let name):
                "Unexpected prepared-data layout in \(name)."
            }
        }
    }
}
#endif
