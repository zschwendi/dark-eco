import Darwin
import Foundation
import OSLog

nonisolated private let installLog = Logger(subsystem: "com.zephyrstudiosllc.eco",
                                            category: "GameDataInstall")

/// Progress shared by prepared-folder and raw-disc imports.
nonisolated struct GameDataImportProgress: Sendable {
    nonisolated enum Phase: String, Sendable {
        case scanning
        case stagingCurrentInstall
        case preparingCandidate
        case validatingCandidate
        case activatingCandidate

        var label: String {
            switch self {
            case .scanning: return "Scanning"
            case .stagingCurrentInstall: return "Preserving current data"
            case .preparingCandidate: return "Preparing candidate"
            case .validatingCandidate: return "Validating candidate"
            case .activatingCandidate: return "Activating candidate"
            }
        }
    }

    var phase: Phase
    var filesCopied = 0
    var filesTotal = 0
    var bytesCopied: Int64 = 0
    var bytesTotal: Int64 = 0
    var currentFile = ""

    var fraction: Double? {
        switch phase {
        case .scanning, .validatingCandidate, .activatingCandidate:
            return nil
        case .stagingCurrentInstall, .preparingCandidate:
            if bytesTotal > 0 {
                return Double(bytesCopied) / Double(bytesTotal)
            }
            return filesTotal > 0 ? Double(filesCopied) / Double(filesTotal) : nil
        }
    }
}

/// A recoverable failure. The active install is unchanged for every failure reported here.
nonisolated struct GameDataImportFailure: Error, Sendable {
    nonisolated enum Code: String, Sendable {
        case busy
        case sourceUnavailable
        case invalidPreparedFolder
        case unsupportedArchive
        case invalidDiscImage
        case unsupportedDiscRevision
        case insufficientStorage
        case appResourcesUnavailable
        case preparationFailed
        case stagingFailed
        case candidateIncomplete
        case activationFailed
    }

    let code: Code
    let message: String
    let candidatePreserved: Bool

    var recoveryMessage: String {
        candidatePreserved ? message + " The staged candidate was kept for recovery."
            : message
    }
}

nonisolated struct GameDataImportResult: Sendable {
    let filesCopied: Int
    let filesSkipped: Int
}

/// Typed boundary for producing a desktop-compatible `iso/` plus `fr3/` candidate.
nonisolated protocol GameDataCandidateProducing: Sendable {
    func prepareCandidate(
        from source: URL,
        activeDirectory: URL,
        candidateDirectory: URL,
        report: @escaping @Sendable (GameDataImportProgress) async -> Void
    ) async throws -> GameDataImportResult
}

/// Serializes candidate production, validation, and activation away from the main actor.
actor GameDataInstallWorker {
    nonisolated struct Configuration: Sendable {
        let activeDirectory: URL
        let stagingRoot: URL

        nonisolated static var app: Configuration {
            let support = (try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? URL(fileURLWithPath: NSHomeDirectory())
                .appending(path: "Library/Application Support", directoryHint: .isDirectory)
            return Configuration(
                activeDirectory: GameDataLayout.gameDirectory,
                stagingRoot: support.appending(
                    path: "GOALPad/GameDataImport/Jak1", directoryHint: .isDirectory)
            )
        }
    }

    private let configuration: Configuration
    private var isInstalling = false

    init(configuration: Configuration = .app) {
        self.configuration = configuration
    }

    func install(
        from source: URL,
        using producer: any GameDataCandidateProducing,
        report: @escaping @Sendable (GameDataImportProgress) async -> Void
    ) async throws -> GameDataImportResult {
        guard !isInstalling else {
            throw GameDataImportFailure(
                code: .busy,
                message: "Another game-data import is already running.",
                candidatePreserved: false
            )
        }
        isInstalling = true
        defer { isInstalling = false }

        let manager = FileManager.default
        let attempts = configuration.stagingRoot.appending(
            path: "Attempts", directoryHint: .isDirectory)
        let candidate = attempts.appending(
            path: "\(UUID().uuidString).candidate", directoryHint: .isDirectory)

        do {
            try manager.createDirectory(at: attempts,
                                        withIntermediateDirectories: true)
            try excludeFromBackup(configuration.stagingRoot)
        } catch {
            throw GameDataImportFailure(
                code: .stagingFailed,
                message: "Could not prepare private import staging: \(error.localizedDescription)",
                candidatePreserved: manager.fileExists(atPath: candidate.path)
            )
        }

        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }

        do {
            try Task.checkCancellation()
            let result = try await producer.prepareCandidate(
                from: source,
                activeDirectory: configuration.activeDirectory,
                candidateDirectory: candidate,
                report: report
            )

            try Task.checkCancellation()
            await report(GameDataImportProgress(phase: .validatingCandidate))
            try Task.checkCancellation()
            let candidateReport = GameDataInspector.inspect(gameDirectory: candidate)
            guard candidateReport.status == .ready else {
                throw GameDataImportFailure(
                    code: .candidateIncomplete,
                    message: "The prepared candidate is incomplete. \(candidateReport.summary)",
                    candidatePreserved: true
                )
            }

            try Task.checkCancellation()
            await report(GameDataImportProgress(phase: .activatingCandidate))
            try Task.checkCancellation()
            try activate(candidate: candidate)

            installLog.notice("Activated validated Jak 1 candidate")
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as GameDataImportFailure {
            throw failure
        } catch {
            throw GameDataImportFailure(
                code: .stagingFailed,
                message: error.localizedDescription,
                candidatePreserved: manager.fileExists(atPath: candidate.path)
            )
        }
    }

    private func activate(candidate: URL) throws {
        let manager = FileManager.default
        let active = configuration.activeDirectory
        let activeParent = active.deletingLastPathComponent()
        let incoming = activeParent.appending(
            path: ".\(active.lastPathComponent)-\(UUID().uuidString).candidate",
            directoryHint: .isDirectory
        )

        do {
            try manager.createDirectory(at: activeParent, withIntermediateDirectories: true)
        } catch {
            throw GameDataImportFailure(
                code: .activationFailed,
                message: "The candidate was valid, but the active install location is unavailable: "
                    + error.localizedDescription,
                candidatePreserved: manager.fileExists(atPath: candidate.path)
            )
        }
        do {
            try manager.moveItem(at: candidate, to: incoming)
        } catch {
            throw GameDataImportFailure(
                code: .activationFailed,
                message: "The candidate was valid, but could not enter activation: "
                    + error.localizedDescription,
                candidatePreserved: manager.fileExists(atPath: candidate.path)
            )
        }

        var activated = false
        do {
            if manager.fileExists(atPath: active.path) {
                try renameGameDataItem(from: incoming, to: active, mode: .swap)
                activated = true
                // After the swap, `incoming` is the old active install. Cleanup cannot invalidate
                // the newly activated directory, so leave a recoverable sibling if deletion fails.
                do {
                    try manager.removeItem(at: incoming)
                } catch {
                    installLog.error("Could not remove replaced game-data directory: \(error.localizedDescription, privacy: .public)")
                }
            } else {
                try renameGameDataItem(from: incoming, to: active, mode: .exclusive)
                activated = true
            }
        } catch {
            if !activated && manager.fileExists(atPath: incoming.path)
                && !manager.fileExists(atPath: candidate.path)
            {
                try? manager.moveItem(at: incoming, to: candidate)
            }
            let preserved = manager.fileExists(atPath: candidate.path)
                || manager.fileExists(atPath: incoming.path)
            throw GameDataImportFailure(
                code: .activationFailed,
                message: "The candidate was valid, but activation failed: "
                    + error.localizedDescription,
                candidatePreserved: preserved
            )
        }

        // The candidate was excluded from backup before it reached the atomic switch. Nothing
        // after a successful rename may turn a completed activation into a reported failure.
        try? excludeFromBackup(active)
    }
}

/// Preserves the folder import path while directing all writes into a private per-attempt
/// candidate. A failed candidate is never implicitly mixed with a later source selection.
nonisolated struct PreparedFolderCandidateProducer: GameDataCandidateProducing {
    private struct CopyItem: Sendable {
        let source: URL
        let destination: URL
        let size: Int64
        let relativeName: String
    }

    func prepareCandidate(
        from source: URL,
        activeDirectory: URL,
        candidateDirectory: URL,
        report: @escaping @Sendable (GameDataImportProgress) async -> Void
    ) async throws -> GameDataImportResult {
        let manager = FileManager.default
        await report(GameDataImportProgress(phase: .scanning))
        try Task.checkCancellation()

        let sourcePairs = try sourceDirectories(at: source, candidateDirectory: candidateDirectory)
        let sourceWork: [CopyItem]
        do {
            sourceWork = try sourcePairs.flatMap { pair in
                try files(in: pair.source, candidatePreserved: false).map { file in
                    CopyItem(
                        source: file.url,
                        destination: pair.destination.appending(path: file.url.lastPathComponent),
                        size: file.size,
                        relativeName: pair.destination.lastPathComponent + "/"
                            + file.url.lastPathComponent
                    )
                }
            }
        } catch let failure as GameDataImportFailure {
            throw failure
        } catch {
            throw GameDataImportFailure(
                code: .sourceUnavailable,
                message: "Could not read \(source.lastPathComponent): \(error.localizedDescription)",
                candidatePreserved: false
            )
        }
        guard !sourceWork.isEmpty else {
            throw GameDataImportFailure(
                code: .invalidPreparedFolder,
                message: "No iso/ or fr3/ files were found in \(source.lastPathComponent).",
                candidatePreserved: manager.fileExists(atPath: candidateDirectory.path)
            )
        }
        let sourceDestinations = Set(sourceWork.map(\.relativeName))

        if !manager.fileExists(atPath: candidateDirectory.path) {
            try createCandidateLayout(at: candidateDirectory)
            let currentWork = try currentInstallFiles(
                activeDirectory: activeDirectory,
                candidateDirectory: candidateDirectory,
                excluding: sourceDestinations
            )
            if !currentWork.isEmpty {
                _ = try await copy(
                    currentWork,
                    phase: .stagingCurrentInstall,
                    report: report
                )
            }
        } else {
            try createCandidateLayout(at: candidateDirectory)
        }

        let copied = try await copy(sourceWork, phase: .preparingCandidate, report: report)
        return GameDataImportResult(filesCopied: copied, filesSkipped: 0)
    }

    private func sourceDirectories(
        at source: URL,
        candidateDirectory: URL
    ) throws -> [(source: URL, destination: URL)] {
        let destinationISO = candidateDirectory.appending(
            path: GameDataLayout.isoDirectoryName, directoryHint: .isDirectory)
        let destinationFR3 = candidateDirectory.appending(
            path: GameDataLayout.fr3DirectoryName, directoryHint: .isDirectory)

        switch source.lastPathComponent.lowercased() {
        case GameDataLayout.isoDirectoryName:
            return [(source, destinationISO)]
        case GameDataLayout.fr3DirectoryName:
            return [(source, destinationFR3)]
        default:
            return [
                (source.appending(path: GameDataLayout.isoDirectoryName,
                                  directoryHint: .isDirectory), destinationISO),
                (source.appending(path: GameDataLayout.fr3DirectoryName,
                                  directoryHint: .isDirectory), destinationFR3),
            ]
        }
    }

    private func currentInstallFiles(
        activeDirectory: URL,
        candidateDirectory: URL,
        excluding sourceDestinations: Set<String>
    ) throws -> [CopyItem] {
        var result: [CopyItem] = []
        for name in [GameDataLayout.isoDirectoryName, GameDataLayout.fr3DirectoryName] {
            let source = activeDirectory.appending(path: name, directoryHint: .isDirectory)
            let destination = candidateDirectory.appending(path: name, directoryHint: .isDirectory)
            result += try files(in: source, candidatePreserved: true).compactMap { file in
                let relativeName = name + "/" + file.url.lastPathComponent
                guard !sourceDestinations.contains(relativeName) else { return nil }
                return CopyItem(
                    source: file.url,
                    destination: destination.appending(path: file.url.lastPathComponent),
                    size: file.size,
                    relativeName: relativeName
                )
            }
        }
        return result
    }

    private func createCandidateLayout(at candidate: URL) throws {
        let manager = FileManager.default
        for name in [GameDataLayout.isoDirectoryName, GameDataLayout.fr3DirectoryName] {
            try manager.createDirectory(
                at: candidate.appending(path: name, directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
        }
        try excludeFromBackup(candidate)
    }

    private func copy(
        _ work: [CopyItem],
        phase: GameDataImportProgress.Phase,
        report: @escaping @Sendable (GameDataImportProgress) async -> Void
    ) async throws -> Int {
        var progress = GameDataImportProgress(
            phase: phase,
            filesTotal: work.count,
            bytesTotal: work.reduce(0) { $0 + $1.size }
        )
        await report(progress)

        for item in work {
            try Task.checkCancellation()
            progress.currentFile = item.relativeName
            await report(progress)
            do {
                try await copyFileAtomically(item.source, to: item.destination) { bytes in
                    progress.bytesCopied += Int64(bytes)
                    await report(progress)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw GameDataImportFailure(
                    code: .stagingFailed,
                    message: "Copying \(item.relativeName) failed: \(error.localizedDescription)",
                    candidatePreserved: true
                )
            }
            progress.filesCopied += 1
            await report(progress)
        }
        return progress.filesCopied
    }

    private func copyFileAtomically(
        _ source: URL,
        to destination: URL,
        reportBytes: @escaping (Int) async -> Void
    ) async throws {
        let manager = FileManager.default
        try manager.createDirectory(at: destination.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
        let temporary = destination.deletingLastPathComponent().appending(
            path: ".\(destination.lastPathComponent)-\(UUID().uuidString).partial",
            directoryHint: .notDirectory
        )
        guard manager.createFile(atPath: temporary.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? manager.removeItem(at: temporary) }

        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: temporary)
        defer {
            try? input.close()
            try? output.close()
        }

        while true {
            try Task.checkCancellation()
            guard let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty else { break }
            try output.write(contentsOf: data)
            await reportBytes(data.count)
        }
        try output.synchronize()
        try output.close()
        try input.close()
        try renameGameDataItem(from: temporary, to: destination, mode: .replace)
    }

    private func files(in directory: URL,
                       candidatePreserved: Bool) throws -> [(url: URL, size: Int64)] {
        let manager = FileManager.default
        let directoryKeys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        if let values = try? directory.resourceValues(forKeys: directoryKeys),
           values.isSymbolicLink == true
        {
            throw GameDataImportFailure(
                code: .sourceUnavailable,
                message: "Prepared data directories may not be symbolic links (\(directory.lastPathComponent)).",
                candidatePreserved: candidatePreserved
            )
        }
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return []
        }

        let keys: Set<URLResourceKey> = [
            .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
        ]
        let contents = try manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )
        return try contents.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { url in
            let values = try url.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true {
                throw GameDataImportFailure(
                    code: .sourceUnavailable,
                    message: "Prepared data may not contain symbolic links (\(url.lastPathComponent)).",
                    candidatePreserved: candidatePreserved
                )
            }
            guard values.isRegularFile == true else { return nil }
            return (url, Int64(values.fileSize ?? 0))
        }
    }
}

nonisolated private func excludeFromBackup(_ url: URL) throws {
    var mutableURL = url
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try mutableURL.setResourceValues(values)
}

nonisolated enum GameDataRenameMode: Sendable {
    case replace
    case exclusive
    case swap
}

nonisolated func renameGameDataItem(from source: URL, to destination: URL,
                                    mode: GameDataRenameMode) throws {
    let flags: UInt32
    switch mode {
    case .replace: flags = 0
    case .exclusive: flags = UInt32(RENAME_EXCL)
    case .swap: flags = UInt32(RENAME_SWAP)
    }
    let result = source.withUnsafeFileSystemRepresentation { sourcePath in
        destination.withUnsafeFileSystemRepresentation { destinationPath in
            guard let sourcePath, let destinationPath else {
                errno = EINVAL
                return Int32(-1)
            }
            return renamex_np(sourcePath, destinationPath, flags)
        }
    }
    guard result == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
