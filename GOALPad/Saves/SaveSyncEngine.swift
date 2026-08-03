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
    case localChangedDuringMerge(String)
    case cloudChangedDuringMerge(String)
    case noSavesFound(String)
    case unsafeImportSelection(String)

    var errorDescription: String? {
        switch self {
        case .cloudDownloadTimedOut(let path):
            return "iCloud did not finish downloading \(path). Try syncing again."
        case .fileChangedDuringRead(let path):
            return "A save was still changing while syncing: \(path). Try syncing again."
        case .localChangedDuringMerge(let path):
            return "A local save changed before iCloud could replace it: \(path). Try syncing again."
        case .cloudChangedDuringMerge(let path):
            return "An iCloud save changed before this device could replace it: \(path). Try syncing again."
        case .noSavesFound(let path):
            return "No OpenGOAL Jak 1 saves were found in \(path)."
        case .unsafeImportSelection(let path):
            return "Select the exact OpenGOAL/jak1/saves folder or its Jak 1 slot folder, not \(path)."
        }
    }
}

nonisolated enum SaveSyncMode: Sendable, Equatable {
    case bidirectional
    case uploadOnly
}

nonisolated enum SaveMutationPoint: Sendable, Equatable {
    case archived
    case removedOdd
    case replacedEven
    case wroteOdd
}

nonisolated struct SaveResolution: Sendable, Equatable, Codable {
    nonisolated enum Copy: String, Sendable, Equatable, Codable {
        case local = "this device"
        case iCloud = "iCloud"
    }

    nonisolated enum Basis: Sendable, Equatable, Codable {
        case completionPercentage(Float)
        case onlyValidJak1Bank
        case modificationDate
        case localGameplayAuthority
        case activeGameplayAuthority
    }

    let relativePath: String
    let winner: Copy
    let basis: Basis
}

nonisolated struct SaveTransferResult: Sendable, Equatable {
    let fileCount: Int
    let destination: URL?
}

nonisolated struct SaveSyncOutcome: Sendable, Equatable {
    nonisolated enum Availability: Sendable, Equatable {
        case available
        case unavailable
    }

    let availability: Availability
    let uploaded: Int
    let downloaded: Int
    let resolutions: [SaveResolution]
    let completedAt: Date

    static func unavailable(at date: Date = Date()) -> SaveSyncOutcome {
        SaveSyncOutcome(availability: .unavailable, uploaded: 0, downloaded: 0,
                        resolutions: [], completedAt: date)
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
        let mutationHook: @Sendable (SaveMutationPoint) throws -> Void
        let beforeLocalReplacement: @Sendable () throws -> Void
        let beforeCloudReplacement: @Sendable () throws -> Void

        init(localRoot: URL, localConflictsRoot: URL, stateFile: URL,
             cloudLocations: @escaping CloudLocationsProvider, coordinateCloudAccess: Bool,
             fileSettleDelay: Duration = .milliseconds(100),
             downloadPollInterval: Duration = .milliseconds(100),
             downloadPollAttempts: Int = 600,
             mutationHook: @escaping @Sendable (SaveMutationPoint) throws -> Void = { _ in },
             beforeLocalReplacement: @escaping @Sendable () throws -> Void = {},
             beforeCloudReplacement: @escaping @Sendable () throws -> Void = {}) {
            self.localRoot = localRoot
            self.localConflictsRoot = localConflictsRoot
            self.stateFile = stateFile
            self.cloudLocations = cloudLocations
            self.coordinateCloudAccess = coordinateCloudAccess
            self.fileSettleDelay = fileSettleDelay
            self.downloadPollInterval = downloadPollInterval
            self.downloadPollAttempts = downloadPollAttempts
            self.mutationHook = mutationHook
            self.beforeLocalReplacement = beforeLocalReplacement
            self.beforeCloudReplacement = beforeCloudReplacement
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

    private struct Jak1BankMetadata {
        let saveCount: UInt32
        let completionPercentage: Float
    }

    private struct Jak1SlotSnapshot {
        let evenPath: String
        let oddPath: String
        let even: SaveFile?
        let odd: SaveFile?
        let effectiveFile: SaveFile?
        let effectiveMetadata: Jak1BankMetadata?

        var hasFiles: Bool { even != nil || odd != nil }
        var identity: String {
            "even=" + (even?.hash ?? "missing") + ";odd=" + (odd?.hash ?? "missing")
        }

        func file(at relativePath: String) -> SaveFile? {
            if relativePath == evenPath { return even }
            if relativePath == oddPath { return odd }
            return nil
        }
    }

    private struct ImportFile {
        let relativePath: String
        let url: URL
    }

    private struct ConflictRecord: Codable, Equatable {
        let localHash: String
        let cloudHash: String
    }

    private struct State: Codable {
        var baselineHashes: [String: String] = [:]
        var slotBaselineHashes: [String: String] = [:]
        var conflicts: [String: ConflictRecord] = [:]
        var cloudAccountIdentifier: Data?

        private enum CodingKeys: String, CodingKey {
            case baselineHashes
            case slotBaselineHashes
            case conflicts
            case cloudAccountIdentifier
        }

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            baselineHashes = try container.decodeIfPresent([String: String].self,
                                                            forKey: .baselineHashes) ?? [:]
            slotBaselineHashes = try container.decodeIfPresent([String: String].self,
                                                                forKey: .slotBaselineHashes) ?? [:]
            conflicts = try container.decodeIfPresent([String: ConflictRecord].self,
                                                       forKey: .conflicts) ?? [:]
            cloudAccountIdentifier = try container.decodeIfPresent(
                Data.self, forKey: .cloudAccountIdentifier)
        }
    }

    private let configuration: Configuration
    private let manager = FileManager()
    private var lastLocalStamps: [String: FileStamp]?
    private static let jak1BankFileSize = 0x10800
    private static let maximumImportFiles = 8

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    /// Performs an unconditional launch, foreground, or user-requested synchronization.
    func sync(mode: SaveSyncMode = .bidirectional) async throws -> SaveSyncOutcome {
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
            state.slotBaselineHashes.removeAll()
            state.conflicts.removeAll()
            state.cloudAccountIdentifier = cloud.accountIdentifier
        }
        let localFiles = try await files(in: configuration.localRoot, coordinated: false)
        let cloudFiles = try await files(in: cloud.savesRoot,
                                         coordinated: configuration.coordinateCloudAccess)
        var processedLocalStamps = localFiles.mapValues {
            FileStamp(size: $0.data.count, modificationDate: $0.modificationDate)
        }
        var resolutions: [SaveResolution] = []
        var uploaded = 0
        var downloaded = 0
        let allPaths = Set(localFiles.keys).union(cloudFiles.keys)

        let slotEvenPaths = Set(allPaths.compactMap(jak1SlotEvenPath)).sorted()
        for evenPath in slotEvenPaths {
            let result = try mergeJak1Slot(evenPath: evenPath,
                                           localFiles: localFiles,
                                           cloudFiles: cloudFiles,
                                           cloud: cloud,
                                           mode: mode,
                                           state: &state,
                                           processedLocalStamps: &processedLocalStamps,
                                           resolutions: &resolutions)
            uploaded += result.uploaded
            downloaded += result.downloaded
        }

        for relativePath in allPaths.sorted() where jak1BankIndex(relativePath) == nil {
            let local = localFiles[relativePath]
            let remote = cloudFiles[relativePath]

            if mode == .uploadOnly {
                switch (local, remote) {
                case let (local?, remote?) where local.hash != remote.hash:
                    try archiveOriginal(remote, relativePath: relativePath,
                                        source: .iCloud, cloud: cloud)
                    try assertCloudFile(relativePath: relativePath, matches: remote, cloud: cloud)
                    try write(local, relativePath: relativePath, to: cloud.savesRoot,
                              coordinated: configuration.coordinateCloudAccess)
                    state.baselineHashes[relativePath] = local.hash
                    resolutions.append(SaveResolution(relativePath: relativePath,
                                                      winner: .local,
                                                      basis: .activeGameplayAuthority))
                    uploaded += 1
                case let (local?, nil):
                    try assertCloudFile(relativePath: relativePath, matches: nil, cloud: cloud)
                    try write(local, relativePath: relativePath, to: cloud.savesRoot,
                              coordinated: configuration.coordinateCloudAccess)
                    state.baselineHashes[relativePath] = local.hash
                    uploaded += 1
                case let (local?, remote?) where local.hash == remote.hash:
                    state.baselineHashes[relativePath] = local.hash
                case let (nil, remote?):
                    state.baselineHashes[relativePath] = remote.hash
                default:
                    break
                }
                continue
            }

            switch (local, remote) {
            case let (local?, nil):
                try assertCloudFile(relativePath: relativePath, matches: nil, cloud: cloud)
                try write(local, relativePath: relativePath, to: cloud.savesRoot,
                          coordinated: configuration.coordinateCloudAccess)
                state.baselineHashes[relativePath] = local.hash
                uploaded += 1

            case let (nil, remote?):
                try assertLocalFile(relativePath: relativePath, matches: nil)
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
                    try assertLocalFile(relativePath: relativePath, matches: local)
                    try write(remote, relativePath: relativePath, to: configuration.localRoot,
                              coordinated: false)
                    state.baselineHashes[relativePath] = remote.hash
                    processedLocalStamps[relativePath] = FileStamp(
                        size: remote.data.count, modificationDate: remote.modificationDate)
                    downloaded += 1
                } else if baseline == remote.hash, baseline != local.hash {
                    try assertCloudFile(relativePath: relativePath, matches: remote, cloud: cloud)
                    try write(local, relativePath: relativePath, to: cloud.savesRoot,
                              coordinated: configuration.coordinateCloudAccess)
                    state.baselineHashes[relativePath] = local.hash
                    uploaded += 1
                } else {
                    try preserveConflict(relativePath: relativePath, local: local, remote: remote,
                                         cloud: cloud)
                    let resolution = resolveDivergence(relativePath: relativePath,
                                                       local: local, remote: remote)
                    resolutions.append(resolution)
                    switch resolution.winner {
                    case .local:
                        try assertCloudFile(relativePath: relativePath, matches: remote,
                                            cloud: cloud)
                        try write(local, relativePath: relativePath, to: cloud.savesRoot,
                                  coordinated: configuration.coordinateCloudAccess)
                        state.baselineHashes[relativePath] = local.hash
                        uploaded += 1
                    case .iCloud:
                        try assertLocalFile(relativePath: relativePath, matches: local)
                        try write(remote, relativePath: relativePath,
                                  to: configuration.localRoot, coordinated: false)
                        state.baselineHashes[relativePath] = remote.hash
                        processedLocalStamps[relativePath] = FileStamp(
                            size: remote.data.count, modificationDate: remote.modificationDate)
                        downloaded += 1
                    }
                }

            case (nil, nil):
                break
            }
        }

        // Keep decoding the version-1 state shape, but conflicts no longer await user action.
        state.conflicts.removeAll()
        try saveState(state)
        // Keep the stamps of the exact snapshots that were merged. If gameplay completed another
        // save while cloud work was still running, the next frame sees that newer stamp and syncs
        // it instead of accidentally treating it as already mirrored.
        lastLocalStamps = processedLocalStamps
        return SaveSyncOutcome(availability: .available, uploaded: uploaded,
                               downloaded: downloaded,
                               resolutions: resolutions, completedAt: Date())
    }

    /// Cheaply checks the local save directory after a completed game frame. A full hash-based
    /// merge only runs when a save file's size or modification date changed.
    func syncIfLocalFilesChanged(mode: SaveSyncMode = .bidirectional) async throws
        -> SaveSyncOutcome? {
        let current = try stamps(in: configuration.localRoot)
        guard current != lastLocalStamps else { return nil }
        return try await sync(mode: mode)
    }

    /// Imports the unchanged OpenGOAL save directory layout into the local gameplay authority.
    /// Existing divergent local files are archived before the selected copies replace them.
    func importSaves(from selectedDirectory: URL) async throws -> SaveTransferResult {
        let selectedFiles = try strictImportFiles(in: selectedDirectory)
        var importFiles: [String: SaveFile] = [:]
        for selectedFile in selectedFiles {
            if configuration.coordinateCloudAccess {
                try await ensureCloudFileIsCurrent(at: selectedFile.url,
                                                   relativeTo: selectedDirectory)
            }
            importFiles[selectedFile.relativePath] = try await stableFile(
                at: selectedFile.url,
                coordinated: configuration.coordinateCloudAccess,
                relativeTo: selectedDirectory,
                expectedSize: Self.jak1BankFileSize)
        }
        guard containsLoadableJak1Slot(in: importFiles) else {
            throw SaveSyncError.noSavesFound(selectedDirectory.lastPathComponent)
        }

        try manager.createDirectory(at: configuration.localRoot,
                                    withIntermediateDirectories: true)
        let existingFiles = try await files(in: configuration.localRoot, coordinated: false)
        var imported = 0
        let importedSlotPaths = Set(importFiles.keys.compactMap(jak1SlotEvenPath)).sorted()
        for evenPath in importedSlotPaths {
            let incoming = jak1SlotSnapshot(evenPath: evenPath, files: importFiles)
            let existing = jak1SlotSnapshot(evenPath: evenPath, files: existingFiles)
            for relativePath in [incoming.evenPath, incoming.oddPath] {
                let incomingFile = incoming.file(at: relativePath)
                let existingFile = existing.file(at: relativePath)
                guard incomingFile?.hash != existingFile?.hash else { continue }
                if let existingFile {
                    try write(existingFile,
                              relativePath: relativePath + ".before-import-" + existingFile.hash,
                              to: configuration.localConflictsRoot, coordinated: false)
                }
                if incomingFile != nil { imported += 1 }
            }
            _ = try replaceJak1Slot(incoming, replacing: existing,
                                    to: configuration.localRoot, coordinated: false,
                                    targetCopy: .local)
        }
        for relativePath in importFiles.keys.sorted() where jak1BankIndex(relativePath) == nil {
            guard let incoming = importFiles[relativePath] else { continue }
            if let existing = existingFiles[relativePath], existing.hash != incoming.hash {
                try write(existing,
                          relativePath: relativePath + ".before-import-" + existing.hash,
                          to: configuration.localConflictsRoot, coordinated: false)
            }
            guard existingFiles[relativePath]?.hash != incoming.hash else { continue }
            try write(incoming, relativePath: relativePath, to: configuration.localRoot,
                      coordinated: false)
            imported += 1
        }
        lastLocalStamps = nil
        return SaveTransferResult(fileCount: imported, destination: nil)
    }

    /// Writes a stable desktop-compatible `OpenGOAL/jak1/saves` tree without changing local saves.
    func exportSaves(to selectedDirectory: URL) async throws -> SaveTransferResult {
        let localFiles = try await files(in: configuration.localRoot, coordinated: false)
        guard localFiles.keys.contains(where: isJak1BankPath) else {
            throw SaveSyncError.noSavesFound(configuration.localRoot.lastPathComponent)
        }

        let exportRoot = uniqueExportRoot(in: selectedDirectory)
        let savesRoot = exportRoot.appending(path: "OpenGOAL/jak1/saves",
                                             directoryHint: .isDirectory)
        for relativePath in localFiles.keys.sorted() {
            guard let file = localFiles[relativePath] else { continue }
            try write(file, relativePath: relativePath, to: savesRoot,
                      coordinated: configuration.coordinateCloudAccess)
        }
        return SaveTransferResult(fileCount: localFiles.count, destination: savesRoot)
    }

    private func mergeJak1Slot(
        evenPath: String,
        localFiles: [String: SaveFile],
        cloudFiles: [String: SaveFile],
        cloud: CloudSaveLocations,
        mode: SaveSyncMode,
        state: inout State,
        processedLocalStamps: inout [String: FileStamp],
        resolutions: inout [SaveResolution]
    ) throws -> (uploaded: Int, downloaded: Int) {
        let local = jak1SlotSnapshot(evenPath: evenPath, files: localFiles)
        let remote = jak1SlotSnapshot(evenPath: evenPath, files: cloudFiles)
        let paths = [local.evenPath, local.oddPath]
        defer {
            for path in paths { state.baselineHashes.removeValue(forKey: path) }
        }

        if local.identity == remote.identity {
            state.slotBaselineHashes[evenPath] = local.identity
            return (0, 0)
        }

        if mode == .uploadOnly {
            guard local.hasFiles else {
                if remote.hasFiles { state.slotBaselineHashes[evenPath] = remote.identity }
                return (0, 0)
            }
            if remote.hasFiles {
                try preserveCloudSlotDivergence(remote: remote, against: local, cloud: cloud)
                resolutions.append(SaveResolution(relativePath: evenPath,
                                                  winner: .local,
                                                  basis: .activeGameplayAuthority))
            }
            let changed = try replaceJak1Slot(local, replacing: remote,
                                              to: cloud.savesRoot,
                                              coordinated: configuration.coordinateCloudAccess,
                                              targetCopy: .iCloud)
            state.slotBaselineHashes[evenPath] = local.identity
            return (changed, 0)
        }

        if local.hasFiles, !remote.hasFiles {
            let changed = try replaceJak1Slot(local, replacing: remote,
                                              to: cloud.savesRoot,
                                              coordinated: configuration.coordinateCloudAccess,
                                              targetCopy: .iCloud)
            state.slotBaselineHashes[evenPath] = local.identity
            return (changed, 0)
        }
        if !local.hasFiles, remote.hasFiles {
            let changed = try replaceJak1Slot(remote, replacing: local,
                                              to: configuration.localRoot,
                                              coordinated: false,
                                              targetCopy: .local)
            updateLocalStamps(for: remote, in: &processedLocalStamps)
            state.slotBaselineHashes[evenPath] = remote.identity
            return (0, changed)
        }

        let baseline = state.slotBaselineHashes[evenPath]
            ?? legacyPairBaseline(local: local, remote: remote, state: state)
        if let baseline, orderedMutationIsIncomplete(target: local, baseline: baseline,
                                                     source: remote) {
            try preserveSlotDivergence(local: local, remote: remote, cloud: cloud)
            let changed = try replaceJak1Slot(remote, replacing: local,
                                              to: configuration.localRoot,
                                              coordinated: false,
                                              targetCopy: .local)
            updateLocalStamps(for: remote, in: &processedLocalStamps)
            state.slotBaselineHashes[evenPath] = remote.identity
            return (0, changed)
        }
        if let baseline, orderedMutationIsIncomplete(target: remote, baseline: baseline,
                                                     source: local) {
            try preserveSlotDivergence(local: local, remote: remote, cloud: cloud)
            let changed = try replaceJak1Slot(local, replacing: remote,
                                              to: cloud.savesRoot,
                                              coordinated: configuration.coordinateCloudAccess,
                                              targetCopy: .iCloud)
            state.slotBaselineHashes[evenPath] = local.identity
            return (changed, 0)
        }
        if baseline == local.identity, baseline != remote.identity {
            try preserveSlotDivergence(local: local, remote: remote, cloud: cloud)
            let changed = try replaceJak1Slot(remote, replacing: local,
                                              to: configuration.localRoot,
                                              coordinated: false,
                                              targetCopy: .local)
            updateLocalStamps(for: remote, in: &processedLocalStamps)
            state.slotBaselineHashes[evenPath] = remote.identity
            return (0, changed)
        }
        if baseline == remote.identity, baseline != local.identity {
            try preserveSlotDivergence(local: local, remote: remote, cloud: cloud)
            let changed = try replaceJak1Slot(local, replacing: remote,
                                              to: cloud.savesRoot,
                                              coordinated: configuration.coordinateCloudAccess,
                                              targetCopy: .iCloud)
            state.slotBaselineHashes[evenPath] = local.identity
            return (changed, 0)
        }

        try preserveSlotDivergence(local: local, remote: remote, cloud: cloud)
        let resolution = resolveSlotDivergence(local: local, remote: remote)
        resolutions.append(resolution)
        switch resolution.winner {
        case .local:
            let changed = try replaceJak1Slot(local, replacing: remote,
                                              to: cloud.savesRoot,
                                              coordinated: configuration.coordinateCloudAccess,
                                              targetCopy: .iCloud)
            state.slotBaselineHashes[evenPath] = local.identity
            return (changed, 0)
        case .iCloud:
            let changed = try replaceJak1Slot(remote, replacing: local,
                                              to: configuration.localRoot,
                                              coordinated: false,
                                              targetCopy: .local)
            updateLocalStamps(for: remote, in: &processedLocalStamps)
            state.slotBaselineHashes[evenPath] = remote.identity
            return (0, changed)
        }
    }

    private func replaceJak1Slot(_ source: Jak1SlotSnapshot,
                                 replacing target: Jak1SlotSnapshot,
                                 to root: URL, coordinated: Bool,
                                 targetCopy: SaveResolution.Copy) throws -> Int {
        if targetCopy == .local {
            try assertLocalSlotMatches(target)
        } else {
            try assertCloudSlotMatches(target, root: root, coordinated: coordinated)
        }
        let evenChanged = source.even?.hash != target.even?.hash
        let oddChanged = source.odd?.hash != target.odd?.hash
        let changed = (evenChanged ? 1 : 0) + (oddChanged ? 1 : 0)

        if oddChanged, target.odd != nil {
            try remove(relativePath: target.oddPath, from: root, coordinated: coordinated)
            try configuration.mutationHook(.removedOdd)
        }

        if evenChanged {
            if let sourceEven = source.even {
                try write(sourceEven, relativePath: source.evenPath,
                          to: root, coordinated: coordinated)
            } else if target.even != nil {
                try remove(relativePath: target.evenPath, from: root, coordinated: coordinated)
            }
            try configuration.mutationHook(.replacedEven)
        }

        if oddChanged, let sourceOdd = source.odd {
            try write(sourceOdd, relativePath: source.oddPath,
                      to: root, coordinated: coordinated)
            try configuration.mutationHook(.wroteOdd)
        }
        return changed
    }

    private func updateLocalStamps(for snapshot: Jak1SlotSnapshot,
                                   in stamps: inout [String: FileStamp]) {
        for path in [snapshot.evenPath, snapshot.oddPath] {
            if let file = snapshot.file(at: path) {
                stamps[path] = FileStamp(size: file.data.count,
                                         modificationDate: file.modificationDate)
            } else {
                stamps.removeValue(forKey: path)
            }
        }
    }

    private func legacyPairBaseline(local: Jak1SlotSnapshot, remote: Jak1SlotSnapshot,
                                    state: State) -> String? {
        let localMatches = legacyBaselineMatches(local, state: state)
        let remoteMatches = legacyBaselineMatches(remote, state: state)
        if localMatches, !remoteMatches { return local.identity }
        if remoteMatches, !localMatches { return remote.identity }
        if localMatches, remoteMatches, local.identity == remote.identity { return local.identity }
        return nil
    }

    private func legacyBaselineMatches(_ snapshot: Jak1SlotSnapshot, state: State) -> Bool {
        for path in [snapshot.evenPath, snapshot.oddPath] {
            if state.baselineHashes[path] != snapshot.file(at: path)?.hash { return false }
        }
        return true
    }

    private func orderedMutationIsIncomplete(target: Jak1SlotSnapshot, baseline: String,
                                             source: Jak1SlotSnapshot) -> Bool {
        guard target.odd == nil, source.identity != baseline, let sourceEven = source.even else {
            return false
        }
        let baselineEven = pairMemberHash(in: baseline, label: "even")
        return target.even?.hash == baselineEven || target.even?.hash == sourceEven.hash
    }

    private func pairMemberHash(in identity: String, label: String) -> String? {
        let prefix = label + "="
        guard let component = identity.split(separator: ";").first(where: {
            $0.hasPrefix(prefix)
        }) else { return nil }
        let value = component.dropFirst(prefix.count)
        return value == "missing" ? nil : String(value)
    }

    private func preserveSlotDivergence(local: Jak1SlotSnapshot,
                                        remote: Jak1SlotSnapshot,
                                        cloud: CloudSaveLocations) throws {
        for path in [local.evenPath, local.oddPath] {
            let localFile = local.file(at: path)
            let remoteFile = remote.file(at: path)
            guard localFile?.hash != remoteFile?.hash else { continue }
            if let localFile {
                try archiveOriginal(localFile, relativePath: path, source: .local, cloud: cloud)
            }
            if let remoteFile {
                try archiveOriginal(remoteFile, relativePath: path, source: .iCloud, cloud: cloud)
            }
        }
    }

    private func preserveCloudSlotDivergence(remote: Jak1SlotSnapshot,
                                             against local: Jak1SlotSnapshot,
                                             cloud: CloudSaveLocations) throws {
        for path in [remote.evenPath, remote.oddPath] {
            guard let remoteFile = remote.file(at: path),
                  remoteFile.hash != local.file(at: path)?.hash else { continue }
            try archiveOriginal(remoteFile, relativePath: path, source: .iCloud, cloud: cloud)
        }
    }

    private func archiveOriginal(_ file: SaveFile, relativePath: String,
                                 source: SaveResolution.Copy,
                                 cloud: CloudSaveLocations) throws {
        let label = source == .local ? "local" : "icloud"
        let archivePath = relativePath + "." + label + "-" + file.hash
        try write(file, relativePath: archivePath,
                  to: configuration.localConflictsRoot, coordinated: false)
        try write(file, relativePath: archivePath,
                  to: cloud.conflictsRoot,
                  coordinated: configuration.coordinateCloudAccess)
        try configuration.mutationHook(.archived)
    }

    private func preserveConflict(relativePath: String, local: SaveFile, remote: SaveFile,
                                  cloud: CloudSaveLocations) throws {
        try archiveOriginal(local, relativePath: relativePath, source: .local, cloud: cloud)
        try archiveOriginal(remote, relativePath: relativePath, source: .iCloud, cloud: cloud)
    }

    private func resolveSlotDivergence(local: Jak1SlotSnapshot,
                                       remote: Jak1SlotSnapshot) -> SaveResolution {
        let path = local.evenPath
        let localMetadata = local.effectiveMetadata
        let remoteMetadata = remote.effectiveMetadata
        if let localMetadata, let remoteMetadata,
           localMetadata.completionPercentage != remoteMetadata.completionPercentage {
            let winner: SaveResolution.Copy = localMetadata.completionPercentage
                > remoteMetadata.completionPercentage ? .local : .iCloud
            return SaveResolution(
                relativePath: path,
                winner: winner,
                basis: .completionPercentage(max(localMetadata.completionPercentage,
                                                 remoteMetadata.completionPercentage)))
        }
        if (localMetadata != nil) != (remoteMetadata != nil) {
            return SaveResolution(relativePath: path,
                                  winner: localMetadata != nil ? .local : .iCloud,
                                  basis: .onlyValidJak1Bank)
        }

        let localDate = local.effectiveFile?.modificationDate ?? slotModificationDate(local)
        let remoteDate = remote.effectiveFile?.modificationDate ?? slotModificationDate(remote)
        if let localDate, let remoteDate, localDate != remoteDate {
            return SaveResolution(relativePath: path,
                                  winner: localDate > remoteDate ? .local : .iCloud,
                                  basis: .modificationDate)
        }
        return SaveResolution(relativePath: path, winner: .local,
                              basis: .localGameplayAuthority)
    }

    private func slotModificationDate(_ snapshot: Jak1SlotSnapshot) -> Date? {
        [snapshot.even?.modificationDate, snapshot.odd?.modificationDate]
            .compactMap { $0 }.max()
    }

    private func resolveDivergence(relativePath: String, local: SaveFile,
                                   remote: SaveFile) -> SaveResolution {
        if let localDate = local.modificationDate, let remoteDate = remote.modificationDate,
           localDate != remoteDate {
            return SaveResolution(relativePath: relativePath,
                                  winner: localDate > remoteDate ? .local : .iCloud,
                                  basis: .modificationDate)
        }

        // Equal or missing dates contain no ordering evidence. Keep gameplay's existing local
        // authority; hashes are identities only and are never used to rank divergent saves.
        return SaveResolution(relativePath: relativePath, winner: .local,
                              basis: .localGameplayAuthority)
    }

    private func containsLoadableJak1Slot(in files: [String: SaveFile]) -> Bool {
        Set(files.keys.compactMap(jak1SlotEvenPath)).contains { evenPath in
            jak1SlotSnapshot(evenPath: evenPath, files: files).effectiveMetadata != nil
        }
    }

    private func jak1SlotSnapshot(evenPath: String,
                                  files: [String: SaveFile]) -> Jak1SlotSnapshot {
        let evenIndex = jak1BankIndex(evenPath) ?? 0
        let oddPath = jak1BankPath(beside: evenPath, index: evenIndex + 1)
        let even = files[evenPath]
        let odd = files[oddPath]
        var effectiveFile: SaveFile?
        var effectiveMetadata: Jak1BankMetadata?

        // OpenGOAL gates the whole slot on the even bank and attempts to read an existing odd bank
        // before validating either. Only the writer's exact bank envelope is trusted here.
        let totalBankSize = 0x10800
        if let even, even.data.count == totalBankSize,
           odd == nil || odd?.data.count == totalBankSize {
            let evenMetadata = jak1BankMetadata(in: even, relativePath: evenPath)
            let oddMetadata = odd.flatMap {
                jak1BankMetadata(in: $0, relativePath: oddPath)
            }
            if let evenMetadata, let oddMetadata, let odd {
                if evenMetadata.saveCount > oddMetadata.saveCount {
                    effectiveFile = even
                    effectiveMetadata = evenMetadata
                } else {
                    // The loader chooses the odd bank when save counts tie.
                    effectiveFile = odd
                    effectiveMetadata = oddMetadata
                }
            } else if let evenMetadata {
                effectiveFile = even
                effectiveMetadata = evenMetadata
            } else if let oddMetadata, let odd {
                effectiveFile = odd
                effectiveMetadata = oddMetadata
            }
        }

        return Jak1SlotSnapshot(evenPath: evenPath, oddPath: oddPath,
                                even: even, odd: odd,
                                effectiveFile: effectiveFile,
                                effectiveMetadata: effectiveMetadata)
    }

    /// Jak 1's OpenGOAL writer stores the progress menu's weighted completion percentage in the
    /// 64-byte preview duplicated in each bank header. Only trust it after validating the complete
    /// desktop bank envelope, checksum, duplicated header values, and checksummed game-save copy.
    private func jak1BankMetadata(in file: SaveFile,
                                  relativePath: String) -> Jak1BankMetadata? {
        let headerSize = 0x400
        let bankSize = 0x10000
        let footerOffset = headerSize + bankSize
        guard isJak1BankPath(relativePath), file.data.count == footerOffset + headerSize else {
            return nil
        }

        let headerSaveCount = uint32(in: file.data, at: 0)
        let headerChecksum = uint32(in: file.data, at: 4)
        let headerMagic = uint32(in: file.data, at: 8)
        let headerSaveCount2 = uint32(in: file.data, at: headerSize - 4)
        let footerSaveCount = uint32(in: file.data, at: footerOffset)
        let footerChecksum = uint32(in: file.data, at: footerOffset + 4)
        let footerMagic = uint32(in: file.data, at: footerOffset + 8)
        let footerSaveCount2 = uint32(in: file.data, at: footerOffset + headerSize - 4)
        let magic: UInt32 = 0x1234_5678
        guard headerSaveCount > 0,
              headerSaveCount == headerSaveCount2,
              headerSaveCount == footerSaveCount,
              headerSaveCount == footerSaveCount2,
              headerChecksum == footerChecksum,
              headerMagic == magic, footerMagic == magic,
              headerChecksum == openGOALChecksum(file.data,
                                                 bodyOffset: headerSize,
                                                 bodySize: bankSize),
              uint32(in: file.data, at: headerSize + 4) == 1 else {
            return nil
        }

        let previewProgressBits = uint32(in: file.data, at: 12 + 16)
        let footerProgressBits = uint32(in: file.data, at: footerOffset + 12 + 16)
        let bodyProgressBits = uint32(in: file.data, at: headerSize + 32)
        guard previewProgressBits == footerProgressBits,
              previewProgressBits == bodyProgressBits else {
            return nil
        }
        let progress = Float(bitPattern: previewProgressBits)
        guard progress.isFinite, progress >= 0, progress <= 100 else { return nil }
        return Jak1BankMetadata(saveCount: headerSaveCount,
                                completionPercentage: progress)
    }

    private func openGOALChecksum(_ data: Data, bodyOffset: Int, bodySize: Int) -> UInt32 {
        var checksum: UInt32 = 0
        for offset in stride(from: bodyOffset, to: bodyOffset + bodySize, by: 4) {
            let signMask = UInt32(bitPattern: Int32(bitPattern: checksum) >> 31)
            checksum = (checksum << 1) ^ signMask ^ uint32(in: data, at: offset)
                ^ 0x1234_5678
        }
        return checksum ^ 0xedd1_e666
    }

    private func uint32(in data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private func isJak1BankPath(_ relativePath: String) -> Bool {
        jak1BankIndex(relativePath) != nil
    }

    private func jak1BankIndex(_ relativePath: String) -> Int? {
        let name = URL(fileURLWithPath: relativePath).lastPathComponent
        guard name.hasPrefix("bank"), name.hasSuffix(".bin"), name.count == 9,
              let digit = name.dropFirst(4).first?.wholeNumberValue else { return nil }
        return (0...7).contains(digit) ? digit : nil
    }

    private func jak1SlotEvenPath(_ relativePath: String) -> String? {
        guard let index = jak1BankIndex(relativePath) else { return nil }
        return jak1BankPath(beside: relativePath, index: index - index % 2)
    }

    private func jak1BankPath(beside relativePath: String, index: Int) -> String {
        let directory = (relativePath as NSString).deletingLastPathComponent
        let name = "bank\(index).bin"
        return directory.isEmpty ? name : directory + "/" + name
    }

    private func strictImportFiles(in selectedDirectory: URL) throws -> [ImportFile] {
        let slotName = "BASCUS-97124AYBABTU!"
        let components = selectedDirectory.standardizedFileURL.pathComponents
        let slotDirectory: URL

        let selectedValues = try selectedDirectory.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard selectedValues.isDirectory == true, selectedValues.isSymbolicLink != true else {
            throw SaveSyncError.unsafeImportSelection(selectedDirectory.lastPathComponent)
        }

        if Array(components.suffix(3)) == ["OpenGOAL", "jak1", "saves"] {
            let children = try manager.contentsOfDirectory(
                at: selectedDirectory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [])
            let slotValues = try children.first?.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard children.count == 1, children[0].lastPathComponent == slotName,
                  slotValues?.isDirectory == true, slotValues?.isSymbolicLink != true
            else {
                throw SaveSyncError.unsafeImportSelection(selectedDirectory.lastPathComponent)
            }
            slotDirectory = children[0]
        } else if selectedDirectory.lastPathComponent == slotName {
            slotDirectory = selectedDirectory
        } else {
            throw SaveSyncError.unsafeImportSelection(selectedDirectory.lastPathComponent)
        }

        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey,
                                         .isSymbolicLinkKey, .fileSizeKey]
        let children = try manager.contentsOfDirectory(
            at: slotDirectory,
            includingPropertiesForKeys: Array(keys),
            options: [])
        guard !children.isEmpty, children.count <= Self.maximumImportFiles else {
            throw SaveSyncError.unsafeImportSelection(slotDirectory.lastPathComponent)
        }

        let maximumAggregateBytes = Self.jak1BankFileSize * Self.maximumImportFiles
        var aggregateBytes = 0
        var result: [ImportFile] = []
        for url in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true, values.isDirectory != true,
                  values.isSymbolicLink != true,
                  isJak1BankPath(url.lastPathComponent),
                  values.fileSize == Self.jak1BankFileSize else {
                throw SaveSyncError.unsafeImportSelection(url.lastPathComponent)
            }
            aggregateBytes += values.fileSize ?? 0
            guard aggregateBytes <= maximumAggregateBytes else {
                throw SaveSyncError.unsafeImportSelection(slotDirectory.lastPathComponent)
            }
            result.append(ImportFile(relativePath: slotName + "/" + url.lastPathComponent,
                                     url: url))
        }
        return result
    }

    private func uniqueExportRoot(in selectedDirectory: URL) -> URL {
        let baseName = "Eco Pro Save Export"
        var candidate = selectedDirectory.appending(path: baseName, directoryHint: .isDirectory)
        var suffix = 2
        while manager.fileExists(atPath: candidate.path) {
            candidate = selectedDirectory.appending(path: "\(baseName) \(suffix)",
                                                    directoryHint: .isDirectory)
            suffix += 1
        }
        return candidate
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
    private func stableFile(at url: URL, coordinated: Bool, relativeTo root: URL,
                            expectedSize: Int? = nil) async throws -> SaveFile {
        let path = relativePath(of: url, under: root)
        for _ in 0..<5 {
            try Task.checkCancellation()
            let firstStamp = try stamp(at: url)
            let firstData = try coordinatedData(at: url, coordinated: coordinated,
                                                maximumBytes: expectedSize)
            if let expectedSize, firstData.count != expectedSize {
                throw SaveSyncError.unsafeImportSelection(path)
            }
            try await Task.sleep(for: configuration.fileSettleDelay)
            let secondData = try coordinatedData(at: url, coordinated: coordinated,
                                                 maximumBytes: expectedSize)
            if let expectedSize, secondData.count != expectedSize {
                throw SaveSyncError.unsafeImportSelection(path)
            }
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

    private func coordinatedData(at url: URL, coordinated: Bool,
                                 maximumBytes: Int? = nil) throws -> Data {
        let read: (URL) throws -> Data = { source in
            guard let maximumBytes else { return try Data(contentsOf: source) }
            let handle = try FileHandle(forReadingFrom: source)
            defer { try? handle.close() }
            var result = Data()
            let limit = maximumBytes + 1
            while result.count < limit {
                let readCount = min(64 * 1024, limit - result.count)
                guard let chunk = try handle.read(upToCount: readCount), !chunk.isEmpty else {
                    break
                }
                result.append(chunk)
            }
            return result
        }
        guard coordinated else { return try read(url) }

        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) {
            coordinatedURL in
            result = Result { try read(coordinatedURL) }
        }
        if let coordinationError { throw coordinationError }
        return try result?.get() ?? { throw CocoaError(.fileReadUnknown) }()
    }

    private func assertLocalFile(relativePath: String, matches expected: SaveFile?) throws {
        try configuration.beforeLocalReplacement()
        let destination = configuration.localRoot.appending(
            path: relativePath, directoryHint: .notDirectory)
        guard manager.fileExists(atPath: destination.path) else {
            if expected != nil { throw SaveSyncError.localChangedDuringMerge(relativePath) }
            return
        }
        guard let expected else { throw SaveSyncError.localChangedDuringMerge(relativePath) }
        let currentData = try Data(contentsOf: destination)
        let digest = SHA256.hash(data: currentData)
            .map { String(format: "%02x", $0) }.joined()
        guard digest == expected.hash else {
            throw SaveSyncError.localChangedDuringMerge(relativePath)
        }
    }

    private func assertLocalSlotMatches(_ expected: Jak1SlotSnapshot) throws {
        try configuration.beforeLocalReplacement()
        for path in [expected.evenPath, expected.oddPath] {
            let destination = configuration.localRoot.appending(
                path: path, directoryHint: .notDirectory)
            let expectedFile = expected.file(at: path)
            guard manager.fileExists(atPath: destination.path) else {
                if expectedFile != nil { throw SaveSyncError.localChangedDuringMerge(path) }
                continue
            }
            guard let expectedFile else { throw SaveSyncError.localChangedDuringMerge(path) }
            let currentData = try Data(contentsOf: destination)
            let digest = SHA256.hash(data: currentData)
                .map { String(format: "%02x", $0) }.joined()
            guard digest == expectedFile.hash else {
                throw SaveSyncError.localChangedDuringMerge(path)
            }
        }
    }

    private func assertCloudFile(relativePath: String, matches expected: SaveFile?,
                                 cloud: CloudSaveLocations) throws {
        try configuration.beforeCloudReplacement()
        try assertCloudFile(relativePath: relativePath, matches: expected,
                            root: cloud.savesRoot,
                            coordinated: configuration.coordinateCloudAccess)
    }

    private func assertCloudSlotMatches(_ expected: Jak1SlotSnapshot, root: URL,
                                        coordinated: Bool) throws {
        try configuration.beforeCloudReplacement()
        for path in [expected.evenPath, expected.oddPath] {
            try assertCloudFile(relativePath: path, matches: expected.file(at: path),
                                root: root, coordinated: coordinated)
        }
    }

    private func assertCloudFile(relativePath: String, matches expected: SaveFile?, root: URL,
                                 coordinated: Bool) throws {
        let destination = root.appending(path: relativePath, directoryHint: .notDirectory)
        guard manager.fileExists(atPath: destination.path) else {
            if expected != nil { throw SaveSyncError.cloudChangedDuringMerge(relativePath) }
            return
        }
        guard let expected else { throw SaveSyncError.cloudChangedDuringMerge(relativePath) }
        let currentData = try coordinatedData(at: destination, coordinated: coordinated)
        let digest = SHA256.hash(data: currentData)
            .map { String(format: "%02x", $0) }.joined()
        guard digest == expected.hash else {
            throw SaveSyncError.cloudChangedDuringMerge(relativePath)
        }
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

    private func remove(relativePath: String, from root: URL, coordinated: Bool) throws {
        let destination = root.appending(path: relativePath, directoryHint: .notDirectory)
        guard manager.fileExists(atPath: destination.path) else { return }
        let operation: (URL) throws -> Void = { destination in
            try self.manager.removeItem(at: destination)
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
