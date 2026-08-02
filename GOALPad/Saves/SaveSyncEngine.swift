import CryptoKit
import Foundation

/// The only directories the save synchronizer may touch. Gameplay continues to use `localRoot`;
/// the iCloud paths are a mirror and conflict archive only.
nonisolated struct CloudSaveLocations: Sendable {
    let savesRoot: URL
    let conflictsRoot: URL
    let accountIdentifier: Data
}

nonisolated private enum SaveSyncError: LocalizedError {
    case cloudDownloadTimedOut(String)
    case fileChangedDuringRead(String)

    var errorDescription: String? {
        switch self {
        case .cloudDownloadTimedOut(let path):
            return "iCloud did not finish downloading \(path). Try syncing again."
        case .fileChangedDuringRead(let path):
            return "A save was still changing while syncing: \(path). Try syncing again."
        }
    }
}

nonisolated struct SaveSyncOutcome: Sendable, Equatable {
    nonisolated enum Availability: Sendable, Equatable {
        case available
        case unavailable
    }

    let availability: Availability
    let uploaded: Int
    let downloaded: Int
    let conflicts: [String]
    let completedAt: Date

    static func unavailable(at date: Date = Date()) -> SaveSyncOutcome {
        SaveSyncOutcome(availability: .unavailable, uploaded: 0, downloaded: 0,
                        conflicts: [], completedAt: date)
    }
}

/// Serializes all save-file work away from the main actor. The engine is dependency-injected so
/// the merge behavior can be tested with synthetic local and cloud directories.
actor SaveSyncEngine {
    typealias CloudLocationsProvider = @Sendable () -> CloudSaveLocations?

    nonisolated struct Configuration: Sendable {
        let localRoot: URL
        let localConflictsRoot: URL
        let stateFile: URL
        let cloudLocations: CloudLocationsProvider
        let coordinateCloudAccess: Bool
        let fileSettleDelay: Duration
        let downloadPollInterval: Duration
        let downloadPollAttempts: Int

        init(localRoot: URL, localConflictsRoot: URL, stateFile: URL,
             cloudLocations: @escaping CloudLocationsProvider, coordinateCloudAccess: Bool,
             fileSettleDelay: Duration = .milliseconds(100),
             downloadPollInterval: Duration = .milliseconds(100),
             downloadPollAttempts: Int = 600) {
            self.localRoot = localRoot
            self.localConflictsRoot = localConflictsRoot
            self.stateFile = stateFile
            self.cloudLocations = cloudLocations
            self.coordinateCloudAccess = coordinateCloudAccess
            self.fileSettleDelay = fileSettleDelay
            self.downloadPollInterval = downloadPollInterval
            self.downloadPollAttempts = downloadPollAttempts
        }
    }

    private struct FileStamp: Equatable {
        let size: Int
        let modificationDate: Date?
    }

    private struct SaveFile {
        let data: Data
        let modificationDate: Date?
        let hash: String
    }

    private struct ConflictRecord: Codable, Equatable {
        let localHash: String
        let cloudHash: String
    }

    private struct State: Codable {
        var baselineHashes: [String: String] = [:]
        var conflicts: [String: ConflictRecord] = [:]
        var cloudAccountIdentifier: Data?
    }

    private let configuration: Configuration
    private let manager = FileManager()
    private var lastLocalStamps: [String: FileStamp]?

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    /// Performs an unconditional launch, foreground, or user-requested synchronization.
    func sync() async throws -> SaveSyncOutcome {
        try manager.createDirectory(at: configuration.localRoot,
                                    withIntermediateDirectories: true)

        guard let cloud = configuration.cloudLocations() else {
            lastLocalStamps = try stamps(in: configuration.localRoot)
            return .unavailable()
        }

        try createDirectory(at: cloud.savesRoot,
                            coordinated: configuration.coordinateCloudAccess)
        try createDirectory(at: cloud.conflictsRoot,
                            coordinated: configuration.coordinateCloudAccess)

        var state = try loadState()
        if state.cloudAccountIdentifier != cloud.accountIdentifier {
            state.baselineHashes.removeAll()
            state.conflicts.removeAll()
            state.cloudAccountIdentifier = cloud.accountIdentifier
        }
        let localFiles = try await files(in: configuration.localRoot, coordinated: false)
        let cloudFiles = try await files(in: cloud.savesRoot,
                                         coordinated: configuration.coordinateCloudAccess)
        var processedLocalStamps = localFiles.mapValues {
            FileStamp(size: $0.data.count, modificationDate: $0.modificationDate)
        }
        var currentConflicts: [String: ConflictRecord] = [:]
        var uploaded = 0
        var downloaded = 0

        for relativePath in Set(localFiles.keys).union(cloudFiles.keys).sorted() {
            let local = localFiles[relativePath]
            let remote = cloudFiles[relativePath]

            switch (local, remote) {
            case let (local?, nil):
                try write(local, relativePath: relativePath, to: cloud.savesRoot,
                          coordinated: configuration.coordinateCloudAccess)
                state.baselineHashes[relativePath] = local.hash
                uploaded += 1

            case let (nil, remote?):
                try write(remote, relativePath: relativePath, to: configuration.localRoot,
                          coordinated: false)
                state.baselineHashes[relativePath] = remote.hash
                processedLocalStamps[relativePath] = FileStamp(
                    size: remote.data.count, modificationDate: remote.modificationDate)
                downloaded += 1

            case let (local?, remote?) where local.hash == remote.hash:
                state.baselineHashes[relativePath] = local.hash

            case let (local?, remote?):
                let baseline = state.baselineHashes[relativePath]
                if baseline == local.hash, baseline != remote.hash {
                    try write(remote, relativePath: relativePath, to: configuration.localRoot,
                              coordinated: false)
                    state.baselineHashes[relativePath] = remote.hash
                    processedLocalStamps[relativePath] = FileStamp(
                        size: remote.data.count, modificationDate: remote.modificationDate)
                    downloaded += 1
                } else if baseline == remote.hash, baseline != local.hash {
                    try write(local, relativePath: relativePath, to: cloud.savesRoot,
                              coordinated: configuration.coordinateCloudAccess)
                    state.baselineHashes[relativePath] = local.hash
                    uploaded += 1
                } else {
                    let conflict = ConflictRecord(localHash: local.hash, cloudHash: remote.hash)
                    currentConflicts[relativePath] = conflict
                    try preserveConflict(relativePath: relativePath, local: local, remote: remote,
                                         cloud: cloud)
                }

            case (nil, nil):
                break
            }
        }

        state.conflicts = currentConflicts
        try saveState(state)
        // Keep the stamps of the exact snapshots that were merged. If gameplay completed another
        // save while cloud work was still running, the next frame sees that newer stamp and syncs
        // it instead of accidentally treating it as already mirrored.
        lastLocalStamps = processedLocalStamps
        return SaveSyncOutcome(availability: .available, uploaded: uploaded,
                               downloaded: downloaded,
                               conflicts: currentConflicts.keys.sorted(), completedAt: Date())
    }

    /// Cheaply checks the local save directory after a completed game frame. A full hash-based
    /// merge only runs when a save file's size or modification date changed.
    func syncIfLocalFilesChanged() async throws -> SaveSyncOutcome? {
        let current = try stamps(in: configuration.localRoot)
        guard current != lastLocalStamps else { return nil }
        return try await sync()
    }

    private func preserveConflict(relativePath: String, local: SaveFile, remote: SaveFile,
                                  cloud: CloudSaveLocations) throws {
        let localSuffix = ".icloud-" + remote.hash
        let cloudSuffix = ".local-" + local.hash
        try write(remote, relativePath: relativePath + localSuffix,
                  to: configuration.localConflictsRoot, coordinated: false)
        try write(local, relativePath: relativePath + cloudSuffix,
                  to: cloud.conflictsRoot, coordinated: configuration.coordinateCloudAccess)
    }

    private func stamps(in root: URL) throws -> [String: FileStamp] {
        guard manager.fileExists(atPath: root.path) else { return [:] }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey,
                                         .contentModificationDateKey]
        guard let enumerator = manager.enumerator(at: root,
                                                  includingPropertiesForKeys: Array(keys),
                                                  options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else {
            return [:]
        }

        var result: [String: FileStamp] = [:]
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else { continue }
            result[relativePath(of: url, under: root)] = FileStamp(
                size: values.fileSize ?? 0,
                modificationDate: values.contentModificationDate)
        }
        return result
    }

    private func files(in root: URL, coordinated: Bool) async throws -> [String: SaveFile] {
        let urls = try fileURLs(in: root, coordinated: coordinated)
        var result: [String: SaveFile] = [:]
        for url in urls {
            if coordinated {
                try await ensureCloudFileIsCurrent(at: url, relativeTo: root)
            }
            result[relativePath(of: url, under: root)] = try await stableFile(
                at: url, coordinated: coordinated, relativeTo: root)
        }
        return result
    }

    private func fileURLs(in root: URL, coordinated: Bool) throws -> [URL] {
        guard coordinated else { return try uncoordinatedFileURLs(in: root) }

        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<[URL], Error>?
        coordinator.coordinate(readingItemAt: root, options: [], error: &coordinationError) {
            coordinatedRoot in
            result = Result { try self.uncoordinatedFileURLs(in: coordinatedRoot) }
        }
        if let coordinationError { throw coordinationError }
        return try result?.get() ?? { throw CocoaError(.fileReadUnknown) }()
    }

    private func uncoordinatedFileURLs(in root: URL) throws -> [URL] {
        guard manager.fileExists(atPath: root.path) else { return [] }
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let enumerator = manager.enumerator(at: root,
                                                  includingPropertiesForKeys: Array(keys),
                                                  options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else {
            return []
        }

        var result: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            if values.isRegularFile == true { result.append(url) }
        }
        return result.sorted { $0.path < $1.path }
    }

    /// A save write is synchronous but can overlap a foreground or manual sync. Reading the same
    /// bytes twice across a settling interval prevents an in-progress truncating write from ever
    /// becoming the cloud mirror.
    private func stableFile(at url: URL, coordinated: Bool, relativeTo root: URL) async throws
        -> SaveFile {
        let path = relativePath(of: url, under: root)
        for _ in 0..<5 {
            try Task.checkCancellation()
            let firstStamp = try stamp(at: url)
            let firstData = try coordinatedData(at: url, coordinated: coordinated)
            try await Task.sleep(for: configuration.fileSettleDelay)
            let secondData = try coordinatedData(at: url, coordinated: coordinated)
            let secondStamp = try stamp(at: url)
            if firstStamp == secondStamp, firstData == secondData,
               secondStamp.size == secondData.count {
                let digest = SHA256.hash(data: secondData)
                return SaveFile(data: secondData,
                                modificationDate: secondStamp.modificationDate,
                                hash: digest.map { String(format: "%02x", $0) }.joined())
            }
        }
        throw SaveSyncError.fileChangedDuringRead(path)
    }

    private func stamp(at url: URL) throws -> FileStamp {
        let attributes = try manager.attributesOfItem(atPath: url.path)
        return FileStamp(size: (attributes[.size] as? NSNumber)?.intValue ?? 0,
                         modificationDate: attributes[.modificationDate] as? Date)
    }

    private func coordinatedData(at url: URL, coordinated: Bool) throws -> Data {
        guard coordinated else { return try Data(contentsOf: url) }

        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) {
            coordinatedURL in
            result = Result { try Data(contentsOf: coordinatedURL) }
        }
        if let coordinationError { throw coordinationError }
        return try result?.get() ?? { throw CocoaError(.fileReadUnknown) }()
    }

    /// `startDownloadingUbiquitousItem` only starts an asynchronous transfer. Do not attempt to
    /// hash a placeholder until the file provider reports that its content is current.
    private func ensureCloudFileIsCurrent(at url: URL, relativeTo root: URL) async throws {
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey,
                                         .ubiquitousItemDownloadingStatusKey,
                                         .ubiquitousItemDownloadingErrorKey]
        var values = try url.resourceValues(forKeys: keys)
        guard values.isUbiquitousItem == true else { return }
        if values.ubiquitousItemDownloadingStatus == .current { return }

        try manager.startDownloadingUbiquitousItem(at: url)
        for attempt in 0..<max(1, configuration.downloadPollAttempts) {
            try Task.checkCancellation()
            values = try url.resourceValues(forKeys: keys)
            if let error = values.ubiquitousItemDownloadingError { throw error }
            if values.ubiquitousItemDownloadingStatus == .current { return }
            if attempt + 1 < configuration.downloadPollAttempts {
                try await Task.sleep(for: configuration.downloadPollInterval)
            }
        }
        throw SaveSyncError.cloudDownloadTimedOut(relativePath(of: url, under: root))
    }

    private func write(_ file: SaveFile, relativePath: String, to root: URL,
                       coordinated: Bool) throws {
        let destination = root.appending(path: relativePath, directoryHint: .notDirectory)
        let operation: (URL) throws -> Void = { destination in
            try self.manager.createDirectory(at: destination.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
            try file.data.write(to: destination, options: .atomic)
            if let modificationDate = file.modificationDate {
                try self.manager.setAttributes([.modificationDate: modificationDate],
                                               ofItemAtPath: destination.path)
            }
        }
        guard coordinated else {
            try operation(destination)
            return
        }
        try coordinatedWrite(at: destination, replacing: true, operation)
    }

    private func createDirectory(at url: URL, coordinated: Bool) throws {
        guard coordinated else {
            try manager.createDirectory(at: url, withIntermediateDirectories: true)
            return
        }

        try coordinatedWrite(at: url, replacing: false) { coordinatedURL in
            try self.manager.createDirectory(at: coordinatedURL, withIntermediateDirectories: true)
        }
    }

    /// Coordinating a not-yet-created nested item fails before the accessor runs. In that case,
    /// coordinate the nearest existing ancestor and rebuild the relative destination under the
    /// coordinated URL.
    private func coordinatedWrite(at destination: URL, replacing: Bool,
                                  _ operation: (URL) throws -> Void) throws {
        let destinationExists = manager.fileExists(atPath: destination.path)
        var coordinatedItem = destination
        while !manager.fileExists(atPath: coordinatedItem.path),
              coordinatedItem.pathComponents.count > 1 {
            coordinatedItem.deleteLastPathComponent()
        }

        let relativeComponents = destination.pathComponents
            .dropFirst(coordinatedItem.pathComponents.count)
        let options: NSFileCoordinator.WritingOptions = destinationExists && replacing
            ? .forReplacing : []
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var operationError: Error?
        coordinator.coordinate(writingItemAt: coordinatedItem, options: options,
                               error: &coordinationError) { coordinatedURL in
            let resolvedDestination = relativeComponents.reduce(coordinatedURL) {
                $0.appending(path: $1)
            }
            do { try operation(resolvedDestination) } catch { operationError = error }
        }
        if let coordinationError { throw coordinationError }
        if let operationError { throw operationError }
    }

    private func relativePath(of url: URL, under root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private func loadState() throws -> State {
        guard manager.fileExists(atPath: configuration.stateFile.path) else { return State() }
        return try JSONDecoder().decode(State.self, from: Data(contentsOf: configuration.stateFile))
    }

    private func saveState(_ state: State) throws {
        try manager.createDirectory(at: configuration.stateFile.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: configuration.stateFile, options: .atomic)
    }
}
