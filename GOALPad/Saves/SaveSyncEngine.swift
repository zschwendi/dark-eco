import CryptoKit
import Foundation

/// The only directories the save synchronizer may touch. Gameplay continues to use `localRoot`;
/// the iCloud paths are a mirror and conflict archive only.
nonisolated struct CloudSaveLocations: Sendable {
    let savesRoot: URL
    let conflictsRoot: URL
    let accountIdentifier: Data
}

nonisolated enum CloudSaveUnavailableReason: Sendable, Equatable {
    case accountUnavailable
    case containerUnavailable
    case unknown

    var recoveryMessage: String {
        switch self {
        case .accountUnavailable:
            return "Sign in to iCloud and enable iCloud Drive, then retry."
        case .containerUnavailable:
            return "iCloud Drive is not ready for saves on this device. Check iCloud Drive, then retry."
        case .unknown:
            return "iCloud saves are not available on this device right now. Try again later."
        }
    }
}

nonisolated private enum SaveSyncError: LocalizedError {
    case cloudDownloadTimedOut(String)
    case fileChangedDuringRead(String)
    case localChangedDuringMerge(String)
    case cloudChangedDuringMerge(String)
    case invalidPairMutationState(String)
    case noSavesFound(String)
    case unsafeImportSelection(String)
    case archivedSaveUnavailable(String)

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
        case .invalidPairMutationState(let path):
            return "An interrupted save merge has an unexpected state at \(path). Try syncing again."
        case .noSavesFound(let path):
            return "No OpenGOAL saves for \(GameLibraryTitle.jak1.name) were found in \(path)."
        case .unsafeImportSelection(let path):
            return "Select the exact OpenGOAL/jak1/saves folder or its "
                + "\(GameLibraryTitle.jak1.name) slot folder, not \(path)."
        case .archivedSaveUnavailable:
            return "That preserved save is no longer available. Refresh the list and try again."
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
        case saveGeneration(UInt32)
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

nonisolated enum ArchivedSaveSource: String, Sendable, Equatable {
    case thisDevice = "This Device"
    case iCloud = "iCloud"
    case beforeImport = "Before Import"
    case beforeRestore = "Before Restore"
}

nonisolated struct ArchivedSaveCandidate: Sendable, Equatable, Identifiable {
    /// Opaque controller identity. UI must never display this archive-relative path.
    let id: String
    let slotNumber: Int
    let source: ArchivedSaveSource
    let modificationDate: Date?
    let saveGeneration: UInt32
    let completionPercentage: Float
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
    let unavailableReason: CloudSaveUnavailableReason?

    init(availability: Availability, uploaded: Int, downloaded: Int,
         resolutions: [SaveResolution], completedAt: Date,
         unavailableReason: CloudSaveUnavailableReason? = nil) {
        self.availability = availability
        self.uploaded = uploaded
        self.downloaded = downloaded
        self.resolutions = resolutions
        self.completedAt = completedAt
        self.unavailableReason = unavailableReason
    }

    static func unavailable(reason: CloudSaveUnavailableReason = .unknown,
                            at date: Date = Date()) -> SaveSyncOutcome {
        SaveSyncOutcome(availability: .unavailable, uploaded: 0, downloaded: 0,
                        resolutions: [], completedAt: date, unavailableReason: reason)
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
        let cloudUnavailableReason: @Sendable () -> CloudSaveUnavailableReason
        let coordinateCloudAccess: Bool
        let fileSettleDelay: Duration
        let downloadPollInterval: Duration
        let downloadPollAttempts: Int
        let mutationHook: @Sendable (SaveMutationPoint) throws -> Void
        let beforeLocalReplacement: @Sendable () throws -> Void
        let beforeCloudReplacement: @Sendable () throws -> Void
        let beforeLocalSourceValidation: @Sendable () throws -> Void
        let beforeCloudSourceValidation: @Sendable () throws -> Void
        let afterPairIntentPrepared: @Sendable () throws -> Void
        let afterPairIntentCommitted: @Sendable () throws -> Void
        let afterPairFileMutationBeforePhaseSave: @Sendable (SaveMutationPoint) throws -> Void
        let beforeStateWrite: @Sendable (String?) throws -> Void
        let operationAwaitHook: @Sendable () async -> Void

        init(localRoot: URL, localConflictsRoot: URL, stateFile: URL,
             cloudLocations: @escaping CloudLocationsProvider, coordinateCloudAccess: Bool,
             fileSettleDelay: Duration = .milliseconds(100),
             downloadPollInterval: Duration = .milliseconds(100),
             downloadPollAttempts: Int = 50,
             cloudUnavailableReason:
                @escaping @Sendable () -> CloudSaveUnavailableReason = { .unknown },
             mutationHook: @escaping @Sendable (SaveMutationPoint) throws -> Void = { _ in },
             beforeLocalReplacement: @escaping @Sendable () throws -> Void = {},
             beforeCloudReplacement: @escaping @Sendable () throws -> Void = {},
             beforeLocalSourceValidation: @escaping @Sendable () throws -> Void = {},
             beforeCloudSourceValidation: @escaping @Sendable () throws -> Void = {},
             afterPairIntentPrepared: @escaping @Sendable () throws -> Void = {},
             afterPairIntentCommitted: @escaping @Sendable () throws -> Void = {},
             afterPairFileMutationBeforePhaseSave:
                @escaping @Sendable (SaveMutationPoint) throws -> Void = { _ in },
             beforeStateWrite: @escaping @Sendable (String?) throws -> Void = { _ in },
             operationAwaitHook: @escaping @Sendable () async -> Void = {}) {
            self.localRoot = localRoot
            self.localConflictsRoot = localConflictsRoot
            self.stateFile = stateFile
            self.cloudLocations = cloudLocations
            self.cloudUnavailableReason = cloudUnavailableReason
            self.coordinateCloudAccess = coordinateCloudAccess
            self.fileSettleDelay = fileSettleDelay
            self.downloadPollInterval = downloadPollInterval
            self.downloadPollAttempts = downloadPollAttempts
            self.mutationHook = mutationHook
            self.beforeLocalReplacement = beforeLocalReplacement
            self.beforeCloudReplacement = beforeCloudReplacement
            self.beforeLocalSourceValidation = beforeLocalSourceValidation
            self.beforeCloudSourceValidation = beforeCloudSourceValidation
            self.afterPairIntentPrepared = afterPairIntentPrepared
            self.afterPairIntentCommitted = afterPairIntentCommitted
            self.afterPairFileMutationBeforePhaseSave = afterPairFileMutationBeforePhaseSave
            self.beforeStateWrite = beforeStateWrite
            self.operationAwaitHook = operationAwaitHook
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

    private struct ArchiveDescriptor {
        let relativePath: String
        let canonicalBankPath: String
        let bankIndex: Int
        let source: ArchivedSaveSource
        let hash: String
    }

    private struct ConflictRecord: Codable, Equatable {
        let localHash: String
        let cloudHash: String
    }

    private struct JournaledSaveFile: Codable, Equatable {
        let data: Data
        let modificationDate: Date?
        let hash: String
    }

    private enum PairMutationSource: String, Codable {
        case local
        case iCloud
        case imported
    }

    private enum PairMutationPhase: String, Codable {
        case prepared
        case committed
        case oddRemoved
        case evenReplaced
        case oddWritten
    }

    private struct PairMutationIntent: Codable, Equatable {
        let evenPath: String
        let oddPath: String
        let targetCopy: SaveResolution.Copy
        let sourceKind: PairMutationSource
        let cloudAccountIdentifier: Data?
        let sourceEven: JournaledSaveFile?
        let sourceOdd: JournaledSaveFile?
        let targetEvenHash: String?
        let targetOddHash: String?
        let persistPairBaseline: Bool
        let resolution: SaveResolution?
        var phase: PairMutationPhase
    }

    private struct State: Codable {
        var baselineHashes: [String: String] = [:]
        var slotBaselineHashes: [String: String] = [:]
        var conflicts: [String: ConflictRecord] = [:]
        var cloudAccountIdentifier: Data?
        var pairMutationIntent: PairMutationIntent? = nil

        private enum CodingKeys: String, CodingKey {
            case baselineHashes
            case slotBaselineHashes
            case conflicts
            case cloudAccountIdentifier
            case pairMutationIntent
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
            pairMutationIntent = try container.decodeIfPresent(
                PairMutationIntent.self, forKey: .pairMutationIntent)
        }
    }

    private let configuration: Configuration
    private let manager = FileManager()
    private var lastLocalStamps: [String: FileStamp]?
    private var operationInProgress = false
    private var operationWaiters: [CheckedContinuation<Void, Never>] = []
    private static let jak1BankFileSize = 0x10800
    private static let maximumImportFiles = 8

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    /// Performs an unconditional launch, foreground, or user-requested synchronization.
    func sync(mode: SaveSyncMode = .bidirectional) async throws -> SaveSyncOutcome {
        await acquireOperation()
        defer { releaseOperation() }
        try Task.checkCancellation()
        await configuration.operationAwaitHook()
        try Task.checkCancellation()
        return try await syncUnlocked(mode: mode)
    }

    private func syncUnlocked(mode: SaveSyncMode) async throws -> SaveSyncOutcome {
        try manager.createDirectory(at: configuration.localRoot,
                                    withIntermediateDirectories: true)
        var state = try loadState()

        guard let cloud = configuration.cloudLocations() else {
            return try await syncWithoutCloud(
                mode: mode, state: &state, reason: configuration.cloudUnavailableReason())
        }

        try createDirectory(at: cloud.savesRoot,
                            coordinated: configuration.coordinateCloudAccess)
        try createDirectory(at: cloud.conflictsRoot,
                            coordinated: configuration.coordinateCloudAccess)

        var resolutions: [SaveResolution] = []
        var uploaded = 0
        var downloaded = 0
        if let intent = state.pairMutationIntent {
            try validatePairMutationIntent(intent)
            if intent.phase == .prepared, intent.sourceKind == .imported {
                state.pairMutationIntent = nil
                try saveState(state)
            } else if intent.sourceKind != .imported,
                      intent.cloudAccountIdentifier != cloud.accountIdentifier {
                if intent.targetCopy == .iCloud || intent.phase == .prepared {
                    // The local canonical source is intact. A different account must rank its
                    // own remote copy from scratch rather than replaying writes for the old one.
                    state.pairMutationIntent = nil
                    try saveState(state)
                } else if mode == .uploadOnly {
                    let localFiles = try await files(in: configuration.localRoot,
                                                     coordinated: false)
                    lastLocalStamps = localFiles.mapValues {
                        FileStamp(size: $0.data.count,
                                  modificationDate: $0.modificationDate)
                    }
                    return SaveSyncOutcome(availability: .available, uploaded: 0,
                                           downloaded: 0, resolutions: [],
                                           completedAt: Date())
                } else {
                    let localFiles = try await files(in: configuration.localRoot,
                                                     coordinated: false)
                    let target = jak1SlotSnapshot(evenPath: intent.evenPath,
                                                  files: localFiles)
                    let normalized = try normalizePairMutationPhase(
                        intent, targetIdentity: target.identity, state: &state)
                    let source = journalSourceSnapshot(normalized)
                    downloaded += try resumePairMutation(
                        normalized, liveSource: source, liveTarget: target,
                        cloud: nil, state: &state)
                    if let resolution = normalized.resolution {
                        resolutions.append(resolution)
                    }
                }
            }
        }
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
        let allPaths = Set(localFiles.keys).union(cloudFiles.keys)

        var slotEvenPaths = Set(allPaths.compactMap(jak1SlotEvenPath)).sorted()
        if let pendingPath = state.pairMutationIntent?.evenPath {
            if let pendingIndex = slotEvenPaths.firstIndex(of: pendingPath) {
                slotEvenPaths.remove(at: pendingIndex)
            }
            slotEvenPaths.insert(pendingPath, at: 0)
        }
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
            if state.pairMutationIntent != nil {
                lastLocalStamps = processedLocalStamps
                return SaveSyncOutcome(availability: .available, uploaded: uploaded,
                                       downloaded: downloaded, resolutions: resolutions,
                                       completedAt: Date())
            }
        }

        for relativePath in allPaths.sorted() where jak1BankIndex(relativePath) == nil {
            let local = localFiles[relativePath]
            let remote = cloudFiles[relativePath]

            if mode == .uploadOnly {
                switch (local, remote) {
                case let (local?, remote?) where local.hash != remote.hash:
                    try archiveOriginal(remote, relativePath: relativePath,
                                        source: .iCloud, cloud: cloud)
                    try assertLocalSourceFile(relativePath: relativePath, matches: local)
                    try assertCloudFile(relativePath: relativePath, matches: remote, cloud: cloud)
                    try write(local, relativePath: relativePath, to: cloud.savesRoot,
                              coordinated: configuration.coordinateCloudAccess)
                    state.baselineHashes[relativePath] = local.hash
                    resolutions.append(SaveResolution(relativePath: relativePath,
                                                      winner: .local,
                                                      basis: .activeGameplayAuthority))
                    uploaded += 1
                case let (local?, nil):
                    try assertLocalSourceFile(relativePath: relativePath, matches: local)
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
                try assertLocalSourceFile(relativePath: relativePath, matches: local)
                try assertCloudFile(relativePath: relativePath, matches: nil, cloud: cloud)
                try write(local, relativePath: relativePath, to: cloud.savesRoot,
                          coordinated: configuration.coordinateCloudAccess)
                state.baselineHashes[relativePath] = local.hash
                uploaded += 1

            case let (nil, remote?):
                try assertCloudSourceFile(relativePath: relativePath, matches: remote,
                                          cloud: cloud)
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
                    try assertCloudSourceFile(relativePath: relativePath, matches: remote,
                                              cloud: cloud)
                    try assertLocalFile(relativePath: relativePath, matches: local)
                    try write(remote, relativePath: relativePath, to: configuration.localRoot,
                              coordinated: false)
                    state.baselineHashes[relativePath] = remote.hash
                    processedLocalStamps[relativePath] = FileStamp(
                        size: remote.data.count, modificationDate: remote.modificationDate)
                    downloaded += 1
                } else if baseline == remote.hash, baseline != local.hash {
                    try assertLocalSourceFile(relativePath: relativePath, matches: local)
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
                        try assertLocalSourceFile(relativePath: relativePath, matches: local)
                        try assertCloudFile(relativePath: relativePath, matches: remote,
                                            cloud: cloud)
                        try write(local, relativePath: relativePath, to: cloud.savesRoot,
                                  coordinated: configuration.coordinateCloudAccess)
                        state.baselineHashes[relativePath] = local.hash
                        uploaded += 1
                    case .iCloud:
                        try assertCloudSourceFile(relativePath: relativePath, matches: remote,
                                                  cloud: cloud)
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

    private func syncWithoutCloud(mode: SaveSyncMode, state: inout State,
                                  reason: CloudSaveUnavailableReason = .unknown) async throws
        -> SaveSyncOutcome {
        let localFiles = try await files(in: configuration.localRoot, coordinated: false)
        var processedLocalStamps = localFiles.mapValues {
            FileStamp(size: $0.data.count, modificationDate: $0.modificationDate)
        }
        var downloaded = 0
        var resolutions: [SaveResolution] = []
        if let intent = state.pairMutationIntent {
            try validatePairMutationIntent(intent)
            if intent.targetCopy == .iCloud
                || (intent.phase == .prepared && intent.sourceKind == .imported) {
                // No local canonical bytes were touched by a cloud-target intent. Dropping it
                // lets offline import proceed; a later cloud sync will rank and repair the copy.
                state.pairMutationIntent = nil
                try saveState(state)
            } else if mode == .bidirectional, intent.phase != .prepared {
                let target = jak1SlotSnapshot(evenPath: intent.evenPath, files: localFiles)
                let normalized = try normalizePairMutationPhase(
                    intent, targetIdentity: target.identity, state: &state)
                let source = journalSourceSnapshot(normalized)
                downloaded = try resumePairMutation(
                    normalized, liveSource: source, liveTarget: target,
                    cloud: nil, state: &state)
                updateLocalStamps(for: source, in: &processedLocalStamps)
                if let resolution = normalized.resolution {
                    resolutions.append(resolution)
                }
            }
        }
        lastLocalStamps = processedLocalStamps
        return SaveSyncOutcome(availability: .unavailable, uploaded: 0,
                               downloaded: downloaded, resolutions: resolutions,
                               completedAt: Date(), unavailableReason: reason)
    }

    /// Cheaply checks the local save directory after a completed game frame. A full hash-based
    /// merge only runs when a save file's size or modification date changed.
    func syncIfLocalFilesChanged(mode: SaveSyncMode = .bidirectional) async throws
        -> SaveSyncOutcome? {
        await acquireOperation()
        defer { releaseOperation() }
        try Task.checkCancellation()
        await configuration.operationAwaitHook()
        try Task.checkCancellation()
        let current = try stamps(in: configuration.localRoot)
        guard current != lastLocalStamps else { return nil }
        return try await syncUnlocked(mode: mode)
    }

    /// Imports the unchanged OpenGOAL save directory layout into the local gameplay authority.
    /// Existing divergent local files are archived before the selected copies replace them.
    func importSaves(from selectedDirectory: URL) async throws -> SaveTransferResult {
        await acquireOperation()
        defer { releaseOperation() }
        try Task.checkCancellation()
        await configuration.operationAwaitHook()
        try Task.checkCancellation()
        return try await importSavesUnlocked(from: selectedDirectory)
    }

    /// Lists only complete, checksum-valid native Jak 1 banks from the local preservation mirror.
    /// Each bank is independently loadable, so legacy archives do not need an event manifest to
    /// remain recoverable. Internal archive filenames stay behind the controller/UI boundary.
    func archivedSaveCandidates() async throws -> [ArchivedSaveCandidate] {
        await acquireOperation()
        defer { releaseOperation() }
        try Task.checkCancellation()
        await configuration.operationAwaitHook()
        try Task.checkCancellation()

        var candidates: [ArchivedSaveCandidate] = []
        for url in try fileURLs(in: configuration.localConflictsRoot, coordinated: false) {
            let relativePath = relativePath(of: url, under: configuration.localConflictsRoot)
            guard let descriptor = archiveDescriptor(for: relativePath),
                  let safeURL = safeArchiveURL(for: relativePath),
                  safeURL.standardizedFileURL == url.standardizedFileURL else { continue }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey,
                                                           .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  values.fileSize == Self.jak1BankFileSize else { continue }
            let file = try await stableFile(at: url, coordinated: false,
                                            relativeTo: configuration.localConflictsRoot,
                                            expectedSize: Self.jak1BankFileSize)
            guard descriptor.hash == file.hash,
                  let metadata = jak1BankMetadata(in: file,
                                                  relativePath: descriptor.canonicalBankPath)
            else { continue }
            candidates.append(ArchivedSaveCandidate(
                id: descriptor.relativePath,
                slotNumber: descriptor.bankIndex / 2 + 1,
                source: descriptor.source,
                modificationDate: file.modificationDate,
                saveGeneration: metadata.saveCount,
                completionPercentage: metadata.completionPercentage))
        }
        return candidates.sorted {
            if $0.modificationDate != $1.modificationDate {
                return ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast)
            }
            if $0.saveGeneration != $1.saveGeneration {
                return $0.saveGeneration > $1.saveGeneration
            }
            return $0.id < $1.id
        }
    }

    /// Makes one validated preserved bank the local canonical save for its original slot. The
    /// existing active pair is archived first, then the normal journaled pair mutation writes the
    /// chosen bank as the even member and removes any stale odd member. A later ordinary sync
    /// mirrors that native-format authority to iCloud.
    func promoteArchivedSave(id: String) async throws -> ArchivedSaveCandidate {
        await acquireOperation()
        defer { releaseOperation() }
        try Task.checkCancellation()
        await configuration.operationAwaitHook()
        try Task.checkCancellation()

        guard let descriptor = archiveDescriptor(for: id) else {
            throw SaveSyncError.archivedSaveUnavailable(id)
        }
        guard let sourceURL = safeArchiveURL(for: descriptor.relativePath) else {
            throw SaveSyncError.archivedSaveUnavailable(id)
        }
        guard manager.fileExists(atPath: sourceURL.path) else {
            throw SaveSyncError.archivedSaveUnavailable(id)
        }
        let sourceValues = try sourceURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard sourceValues.isRegularFile == true, sourceValues.isSymbolicLink != true,
              sourceValues.fileSize == Self.jak1BankFileSize else {
            throw SaveSyncError.archivedSaveUnavailable(id)
        }
        let archived = try await stableFile(at: sourceURL, coordinated: false,
                                            relativeTo: configuration.localConflictsRoot,
                                            expectedSize: Self.jak1BankFileSize)
        guard archived.hash == descriptor.hash,
              let metadata = jak1BankMetadata(in: archived,
                                              relativePath: descriptor.canonicalBankPath)
        else {
            throw SaveSyncError.archivedSaveUnavailable(id)
        }

        var state = try loadState()
        if let pending = state.pairMutationIntent {
            try validatePairMutationIntent(pending)
            if pending.targetCopy == .iCloud
                || (pending.phase == .prepared && pending.sourceKind == .imported) {
                state.pairMutationIntent = nil
                try saveState(state)
            } else if pending.targetCopy == .local, pending.phase != .prepared {
                _ = try await syncWithoutCloud(mode: .bidirectional, state: &state)
            } else {
                throw SaveSyncError.invalidPairMutationState(pending.evenPath)
            }
        }

        let evenIndex = descriptor.bankIndex - descriptor.bankIndex % 2
        let evenPath = jak1BankPath(beside: descriptor.canonicalBankPath, index: evenIndex)
        let existingFiles = try await files(in: configuration.localRoot, coordinated: false)
        let existing = jak1SlotSnapshot(evenPath: evenPath, files: existingFiles)
        for path in [existing.evenPath, existing.oddPath] {
            guard let file = existing.file(at: path), file.hash != archived.hash else { continue }
            try write(file, relativePath: path + ".before-restore-" + file.hash,
                      to: configuration.localConflictsRoot, coordinated: false)
        }

        let source = jak1SlotSnapshot(evenPath: evenPath, files: [evenPath: archived])
        guard source.effectiveMetadata != nil else {
            throw SaveSyncError.archivedSaveUnavailable(id)
        }
        let intent = pairMutationIntent(
            source: source, target: existing, targetCopy: .local,
            sourceKind: .imported, cloudAccountIdentifier: state.cloudAccountIdentifier)
        _ = try beginPairMutation(intent, liveSource: source, liveTarget: existing,
                                  cloud: nil, state: &state)
        lastLocalStamps = nil
        return ArchivedSaveCandidate(
            id: descriptor.relativePath,
            slotNumber: evenIndex / 2 + 1,
            source: descriptor.source,
            modificationDate: archived.modificationDate,
            saveGeneration: metadata.saveCount,
            completionPercentage: metadata.completionPercentage)
    }

    private func importSavesUnlocked(from selectedDirectory: URL) async throws
        -> SaveTransferResult {
        var state = try loadState()
        if let pending = state.pairMutationIntent {
            try validatePairMutationIntent(pending)
            if pending.targetCopy == .iCloud
                || (pending.phase == .prepared && pending.sourceKind == .imported) {
                state.pairMutationIntent = nil
                try saveState(state)
            } else if pending.targetCopy == .local, pending.phase != .prepared {
                _ = try await syncWithoutCloud(mode: .bidirectional, state: &state)
            } else {
                throw SaveSyncError.invalidPairMutationState(pending.evenPath)
            }
        }
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
            let intent = pairMutationIntent(
                source: incoming, target: existing, targetCopy: .local,
                sourceKind: .imported,
                cloudAccountIdentifier: state.cloudAccountIdentifier)
            _ = try beginPairMutation(intent, liveSource: incoming, liveTarget: existing,
                                      cloud: nil, state: &state)
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

    /// A committed local-target journal means gameplay storage may be between two bank phases.
    /// Callers must keep the runtime paused until recovery either clears it or reports an error.
    func hasUnsafePendingLocalMutation() async throws -> Bool {
        await acquireOperation()
        defer { releaseOperation() }
        try Task.checkCancellation()
        let state = try loadState()
        guard let intent = state.pairMutationIntent else { return false }
        try validatePairMutationIntent(intent)
        return intent.targetCopy == .local && intent.phase != .prepared
    }

    /// Writes a stable desktop-compatible `OpenGOAL/jak1/saves` tree without changing local saves.
    func exportSaves(to selectedDirectory: URL) async throws -> SaveTransferResult {
        await acquireOperation()
        defer { releaseOperation() }
        try Task.checkCancellation()
        await configuration.operationAwaitHook()
        try Task.checkCancellation()
        return try await exportSavesUnlocked(to: selectedDirectory)
    }

    private func exportSavesUnlocked(to selectedDirectory: URL) async throws
        -> SaveTransferResult {
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
        var local = jak1SlotSnapshot(evenPath: evenPath, files: localFiles)
        var remote = jak1SlotSnapshot(evenPath: evenPath, files: cloudFiles)
        var recoveredUploaded = 0
        var recoveredDownloaded = 0
        let paths = [local.evenPath, local.oddPath]
        defer {
            for path in paths { state.baselineHashes.removeValue(forKey: path) }
        }

        if let recovered = try recoverPairMutationIfPossible(
            evenPath: evenPath, local: local, remote: remote, cloud: cloud, mode: mode,
            state: &state, processedLocalStamps: &processedLocalStamps,
            resolutions: &resolutions) {
            if recovered.sourceChanged,
               mode == .bidirectional || recovered.intent.targetCopy == .iCloud {
                recoveredUploaded = recovered.uploaded
                recoveredDownloaded = recovered.downloaded
                let committedSource = journalSourceSnapshot(recovered.intent)
                if recovered.intent.targetCopy == .local {
                    local = committedSource
                } else {
                    remote = committedSource
                }
            } else {
                return (recovered.uploaded, recovered.downloaded)
            }
        }

        if local.identity == remote.identity {
            state.slotBaselineHashes[evenPath] = local.identity
            return (recoveredUploaded, recoveredDownloaded)
        }

        if mode == .uploadOnly {
            guard local.hasFiles else {
                if remote.hasFiles { state.slotBaselineHashes[evenPath] = remote.identity }
                return (recoveredUploaded, recoveredDownloaded)
            }
            if remote.hasFiles {
                try preserveCloudSlotDivergence(remote: remote, against: local, cloud: cloud)
                resolutions.append(SaveResolution(relativePath: evenPath,
                                                  winner: .local,
                                                  basis: .activeGameplayAuthority))
            }
            let resolution = remote.hasFiles ? SaveResolution(
                relativePath: evenPath, winner: .local,
                basis: .activeGameplayAuthority) : nil
            let changed = try replaceJak1SlotDuringSync(local, replacing: remote,
                                                        targetCopy: .iCloud, cloud: cloud,
                                                        state: &state,
                                                        resolution: resolution)
            state.slotBaselineHashes[evenPath] = local.identity
            return (recoveredUploaded + changed, recoveredDownloaded)
        }

        if local.hasFiles, !remote.hasFiles {
            let changed = try replaceJak1SlotDuringSync(local, replacing: remote,
                                                        targetCopy: .iCloud, cloud: cloud,
                                                        state: &state)
            state.slotBaselineHashes[evenPath] = local.identity
            return (recoveredUploaded + changed, recoveredDownloaded)
        }
        if !local.hasFiles, remote.hasFiles {
            let changed = try replaceJak1SlotDuringSync(remote, replacing: local,
                                                        targetCopy: .local, cloud: cloud,
                                                        state: &state)
            updateLocalStamps(for: remote, in: &processedLocalStamps)
            state.slotBaselineHashes[evenPath] = remote.identity
            return (recoveredUploaded, recoveredDownloaded + changed)
        }

        let baseline = state.slotBaselineHashes[evenPath]
            ?? legacyPairBaseline(local: local, remote: remote, state: state)
        let presenceDiffers = (local.even != nil) != (remote.even != nil)
            || (local.odd != nil) != (remote.odd != nil)
        if !presenceDiffers, baseline == local.identity, baseline != remote.identity {
            try preserveSlotDivergence(local: local, remote: remote, cloud: cloud)
            let changed = try replaceJak1SlotDuringSync(remote, replacing: local,
                                                        targetCopy: .local, cloud: cloud,
                                                        state: &state)
            updateLocalStamps(for: remote, in: &processedLocalStamps)
            state.slotBaselineHashes[evenPath] = remote.identity
            return (recoveredUploaded, recoveredDownloaded + changed)
        }
        if !presenceDiffers, baseline == remote.identity, baseline != local.identity {
            try preserveSlotDivergence(local: local, remote: remote, cloud: cloud)
            let changed = try replaceJak1SlotDuringSync(local, replacing: remote,
                                                        targetCopy: .iCloud, cloud: cloud,
                                                        state: &state)
            state.slotBaselineHashes[evenPath] = local.identity
            return (recoveredUploaded + changed, recoveredDownloaded)
        }

        try preserveSlotDivergence(local: local, remote: remote, cloud: cloud)
        let resolution = resolveSlotDivergence(local: local, remote: remote)
        resolutions.append(resolution)
        switch resolution.winner {
        case .local:
            let changed = try replaceJak1SlotDuringSync(local, replacing: remote,
                                                        targetCopy: .iCloud, cloud: cloud,
                                                        state: &state,
                                                        resolution: resolution)
            state.slotBaselineHashes[evenPath] = local.identity
            return (recoveredUploaded + changed, recoveredDownloaded)
        case .iCloud:
            let changed = try replaceJak1SlotDuringSync(remote, replacing: local,
                                                        targetCopy: .local, cloud: cloud,
                                                        state: &state,
                                                        resolution: resolution)
            updateLocalStamps(for: remote, in: &processedLocalStamps)
            state.slotBaselineHashes[evenPath] = remote.identity
            return (recoveredUploaded, recoveredDownloaded + changed)
        }
    }

    private func replaceJak1SlotDuringSync(
        _ source: Jak1SlotSnapshot,
        replacing target: Jak1SlotSnapshot,
        targetCopy: SaveResolution.Copy,
        cloud: CloudSaveLocations,
        state: inout State,
        resolution: SaveResolution? = nil
    ) throws -> Int {
        let intent = pairMutationIntent(
            source: source, target: target, targetCopy: targetCopy,
            sourceKind: targetCopy == .local ? .iCloud : .local,
            cloudAccountIdentifier: cloud.accountIdentifier,
            resolution: resolution)
        return try beginPairMutation(intent, liveSource: source, liveTarget: target,
                                     cloud: cloud, state: &state)
    }

    private func recoverPairMutationIfPossible(
        evenPath: String,
        local: Jak1SlotSnapshot,
        remote: Jak1SlotSnapshot,
        cloud: CloudSaveLocations,
        mode: SaveSyncMode,
        state: inout State,
        processedLocalStamps: inout [String: FileStamp],
        resolutions: inout [SaveResolution]
    ) throws -> (uploaded: Int, downloaded: Int, intent: PairMutationIntent,
                 sourceChanged: Bool)? {
        guard let intent = state.pairMutationIntent, intent.evenPath == evenPath else {
            return nil
        }
        try validatePairMutationIntent(intent)
        guard intent.sourceKind == .imported
                || intent.cloudAccountIdentifier == cloud.accountIdentifier else {
            throw SaveSyncError.invalidPairMutationState(evenPath)
        }
        if mode == .uploadOnly, intent.targetCopy == .local {
            return (0, 0, intent, false)
        }

        let liveSource = intent.targetCopy == .local ? remote : local
        let liveTarget = intent.targetCopy == .local ? local : remote
        let sourceChanged = liveSource.identity != journalSourceSnapshot(intent).identity
        if intent.phase == .prepared,
           intent.sourceKind == .imported
            || liveSource.identity != journalSourceSnapshot(intent).identity
            || liveTarget.identity != expectedTargetIdentity(for: intent) {
            state.pairMutationIntent = nil
            try saveState(state)
            return nil
        }
        let normalizedIntent = try normalizePairMutationPhase(
            intent, targetIdentity: liveTarget.identity, state: &state)

        let changed = try resumePairMutation(normalizedIntent, liveSource: liveSource,
                                             liveTarget: liveTarget, cloud: cloud,
                                             state: &state)
        let journalSource = journalSourceSnapshot(normalizedIntent)
        if normalizedIntent.targetCopy == .local {
            updateLocalStamps(for: journalSource, in: &processedLocalStamps)
        }
        if let resolution = normalizedIntent.resolution {
            resolutions.append(resolution)
        }
        return normalizedIntent.targetCopy == .local
            ? (0, changed, normalizedIntent, sourceChanged)
            : (changed, 0, normalizedIntent, sourceChanged)
    }

    private func beginPairMutation(_ intent: PairMutationIntent,
                                   liveSource: Jak1SlotSnapshot,
                                   liveTarget: Jak1SlotSnapshot,
                                   cloud: CloudSaveLocations?,
                                   state: inout State) throws -> Int {
        try validatePairMutationIntent(intent)
        guard state.pairMutationIntent == nil else {
            throw SaveSyncError.invalidPairMutationState(intent.evenPath)
        }
        state.pairMutationIntent = intent
        try saveState(state)
        try configuration.afterPairIntentPrepared()
        do {
            try assertLivePairSourceMatches(liveSource, intent: intent, cloud: cloud)
            try assertLivePairTargetMatches(liveTarget, intent: intent, cloud: cloud)
        } catch {
            state.pairMutationIntent = nil
            try saveState(state)
            throw error
        }
        return try resumePairMutation(intent, liveSource: liveSource,
                                      liveTarget: liveTarget, cloud: cloud,
                                      state: &state)
    }

    private func pairMutationIntent(source: Jak1SlotSnapshot,
                                    target: Jak1SlotSnapshot,
                                    targetCopy: SaveResolution.Copy,
                                    sourceKind: PairMutationSource,
                                    cloudAccountIdentifier: Data?,
                                    resolution: SaveResolution? = nil) -> PairMutationIntent {
        PairMutationIntent(evenPath: source.evenPath, oddPath: source.oddPath,
                           targetCopy: targetCopy,
                           sourceKind: sourceKind,
                           cloudAccountIdentifier: cloudAccountIdentifier,
                           sourceEven: source.even.map(journaledSaveFile),
                           sourceOdd: source.odd.map(journaledSaveFile),
                           targetEvenHash: target.even?.hash,
                           targetOddHash: target.odd?.hash,
                           persistPairBaseline: sourceKind != .imported,
                           resolution: resolution,
                           phase: .prepared)
    }

    private func resumePairMutation(_ storedIntent: PairMutationIntent,
                                    liveSource: Jak1SlotSnapshot,
                                    liveTarget: Jak1SlotSnapshot,
                                    cloud: CloudSaveLocations?,
                                    state: inout State) throws -> Int {
        guard var intent = state.pairMutationIntent, intent == storedIntent else {
            throw SaveSyncError.invalidPairMutationState(storedIntent.evenPath)
        }
        if intent.phase == .prepared {
            try assertLivePairSourceMatches(liveSource, intent: intent, cloud: cloud)
            try assertLivePairTargetMatches(liveTarget, intent: intent, cloud: cloud)
            intent.phase = .committed
            state.pairMutationIntent = intent
            try saveState(state)
            try configuration.afterPairIntentCommitted()
            try assertTargetMatchesJournalPhase(intent, cloud: cloud)
            try assertLivePairSourceMatches(liveSource, intent: intent, cloud: cloud)
        }

        let source = journalSourceSnapshot(intent)
        let root: URL
        let coordinated: Bool
        if intent.targetCopy == .local {
            root = configuration.localRoot
            coordinated = false
        } else {
            guard let cloud else { throw SaveSyncError.invalidPairMutationState(intent.evenPath) }
            root = cloud.savesRoot
            coordinated = configuration.coordinateCloudAccess
        }

        let oddChanged = source.odd?.hash != intent.targetOddHash
        let evenChanged = source.even?.hash != intent.targetEvenHash
        let changed = (oddChanged ? 1 : 0) + (evenChanged ? 1 : 0)

        if intent.phase == .committed {
            try assertTargetMatchesJournalPhase(intent, cloud: cloud)
            if oddChanged, intent.targetOddHash != nil {
                try remove(relativePath: intent.oddPath, from: root, coordinated: coordinated)
                try configuration.afterPairFileMutationBeforePhaseSave(.removedOdd)
            }
            intent.phase = .oddRemoved
            state.pairMutationIntent = intent
            try saveState(state)
            if oddChanged, intent.targetOddHash != nil {
                try configuration.mutationHook(.removedOdd)
            }
        }

        if intent.phase == .oddRemoved {
            try assertTargetMatchesJournalPhase(intent, cloud: cloud)
            if evenChanged {
                if let sourceEven = source.even {
                    try write(sourceEven, relativePath: intent.evenPath,
                              to: root, coordinated: coordinated)
                } else if intent.targetEvenHash != nil {
                    try remove(relativePath: intent.evenPath, from: root,
                               coordinated: coordinated)
                }
                try configuration.afterPairFileMutationBeforePhaseSave(.replacedEven)
            }
            intent.phase = .evenReplaced
            state.pairMutationIntent = intent
            try saveState(state)
            if evenChanged { try configuration.mutationHook(.replacedEven) }
        }

        if intent.phase == .evenReplaced {
            try assertTargetMatchesJournalPhase(intent, cloud: cloud)
            if oddChanged, let sourceOdd = source.odd {
                try write(sourceOdd, relativePath: intent.oddPath,
                          to: root, coordinated: coordinated)
                try configuration.afterPairFileMutationBeforePhaseSave(.wroteOdd)
            }
            intent.phase = .oddWritten
            state.pairMutationIntent = intent
            try saveState(state)
            if oddChanged, source.odd != nil { try configuration.mutationHook(.wroteOdd) }
        }

        try assertJournalTargetMatches(source, intent: intent, cloud: cloud)
        if intent.persistPairBaseline {
            state.slotBaselineHashes[intent.evenPath] = source.identity
        }
        state.pairMutationIntent = nil
        try saveState(state)
        return changed
    }

    private func slotIdentity(evenHash: String?, oddHash: String?) -> String {
        "even=" + (evenHash ?? "missing") + ";odd=" + (oddHash ?? "missing")
    }

    private func journaledSaveFile(_ file: SaveFile) -> JournaledSaveFile {
        JournaledSaveFile(data: file.data, modificationDate: file.modificationDate,
                          hash: file.hash)
    }

    private func journalSourceSnapshot(_ intent: PairMutationIntent) -> Jak1SlotSnapshot {
        var files: [String: SaveFile] = [:]
        if let even = intent.sourceEven {
            files[intent.evenPath] = SaveFile(data: even.data,
                                              modificationDate: even.modificationDate,
                                              hash: even.hash)
        }
        if let odd = intent.sourceOdd {
            files[intent.oddPath] = SaveFile(data: odd.data,
                                             modificationDate: odd.modificationDate,
                                             hash: odd.hash)
        }
        return jak1SlotSnapshot(evenPath: intent.evenPath, files: files)
    }

    private func validatePairMutationIntent(_ intent: PairMutationIntent) throws {
        let evenComponents = URL(fileURLWithPath: intent.evenPath).pathComponents
        guard !intent.evenPath.hasPrefix("/"), !evenComponents.contains(".."),
              jak1SlotEvenPath(intent.evenPath) == intent.evenPath,
              jak1BankPath(beside: intent.evenPath,
                           index: (jak1BankIndex(intent.evenPath) ?? -1) + 1) == intent.oddPath,
              intent.sourceEven != nil || intent.sourceOdd != nil,
              (intent.targetEvenHash == nil || isSHA256(intent.targetEvenHash)),
              (intent.targetOddHash == nil || isSHA256(intent.targetOddHash)) else {
            throw SaveSyncError.invalidPairMutationState(intent.evenPath)
        }
        if intent.sourceKind == .local, intent.targetCopy != .iCloud {
            throw SaveSyncError.invalidPairMutationState(intent.evenPath)
        }
        if intent.sourceKind == .iCloud, intent.targetCopy != .local {
            throw SaveSyncError.invalidPairMutationState(intent.evenPath)
        }
        if intent.sourceKind != .imported, intent.cloudAccountIdentifier == nil {
            throw SaveSyncError.invalidPairMutationState(intent.evenPath)
        }
        if let resolution = intent.resolution {
            let expectedWinner: SaveResolution.Copy = intent.targetCopy == .local
                ? .iCloud : .local
            guard intent.sourceKind != .imported,
                  resolution.relativePath == intent.evenPath,
                  resolution.winner == expectedWinner else {
                throw SaveSyncError.invalidPairMutationState(intent.evenPath)
            }
        }
        for file in [intent.sourceEven, intent.sourceOdd].compactMap({ $0 }) {
            if file.data.count != Self.jak1BankFileSize {
                throw SaveSyncError.invalidPairMutationState(intent.evenPath)
            }
            let digest = SHA256.hash(data: file.data)
                .map { String(format: "%02x", $0) }.joined()
            guard digest == file.hash else {
                throw SaveSyncError.invalidPairMutationState(intent.evenPath)
            }
        }
    }

    private func isSHA256(_ hash: String?) -> Bool {
        guard let hash, hash.count == 64 else { return false }
        return hash.allSatisfy { $0.isHexDigit }
    }

    private func expectedTargetIdentity(for intent: PairMutationIntent) -> String {
        let hashes = expectedTargetHashes(for: intent)
        return slotIdentity(evenHash: hashes.even, oddHash: hashes.odd)
    }

    private func expectedTargetHashes(for intent: PairMutationIntent)
        -> (even: String?, odd: String?) {
        var evenHash = intent.targetEvenHash
        var oddHash = intent.targetOddHash
        let sourceEvenHash = intent.sourceEven?.hash
        let sourceOddHash = intent.sourceOdd?.hash

        switch intent.phase {
        case .prepared, .committed:
            break
        case .oddRemoved:
            if sourceOddHash != oddHash, oddHash != nil { oddHash = nil }
        case .evenReplaced:
            if sourceOddHash != oddHash, oddHash != nil { oddHash = nil }
            if sourceEvenHash != evenHash { evenHash = sourceEvenHash }
        case .oddWritten:
            evenHash = sourceEvenHash
            oddHash = sourceOddHash
        }
        return (evenHash, oddHash)
    }

    private func nextPhase(after phase: PairMutationPhase) -> PairMutationPhase? {
        switch phase {
        case .prepared: return .committed
        case .committed: return .oddRemoved
        case .oddRemoved: return .evenReplaced
        case .evenReplaced: return .oddWritten
        case .oddWritten: return nil
        }
    }

    private func normalizePairMutationPhase(_ storedIntent: PairMutationIntent,
                                            targetIdentity: String,
                                            state: inout State) throws
        -> PairMutationIntent {
        if targetIdentity == expectedTargetIdentity(for: storedIntent) {
            return storedIntent
        }
        guard storedIntent.phase != .prepared,
              let nextPhase = nextPhase(after: storedIntent.phase) else {
            throw SaveSyncError.invalidPairMutationState(storedIntent.evenPath)
        }
        var advanced = storedIntent
        advanced.phase = nextPhase
        guard targetIdentity == expectedTargetIdentity(for: advanced) else {
            throw SaveSyncError.invalidPairMutationState(storedIntent.evenPath)
        }
        state.pairMutationIntent = advanced
        try saveState(state)
        return advanced
    }

    private func expectedTargetSnapshot(for intent: PairMutationIntent) -> Jak1SlotSnapshot {
        let hashes = expectedTargetHashes(for: intent)
        var files: [String: SaveFile] = [:]
        if let evenHash = hashes.even {
            files[intent.evenPath] = SaveFile(data: Data(), modificationDate: nil,
                                              hash: evenHash)
        }
        if let oddHash = hashes.odd {
            files[intent.oddPath] = SaveFile(data: Data(), modificationDate: nil,
                                             hash: oddHash)
        }
        return jak1SlotSnapshot(evenPath: intent.evenPath, files: files)
    }

    private func assertTargetMatchesJournalPhase(_ intent: PairMutationIntent,
                                                 cloud: CloudSaveLocations?) throws {
        let expected = expectedTargetSnapshot(for: intent)
        if intent.targetCopy == .local {
            try assertLocalSlotMatches(expected)
        } else {
            guard let cloud else {
                throw SaveSyncError.invalidPairMutationState(intent.evenPath)
            }
            try assertCloudSlotMatches(expected, root: cloud.savesRoot,
                                       coordinated: configuration.coordinateCloudAccess)
        }
    }

    private func assertLivePairSourceMatches(_ liveSource: Jak1SlotSnapshot,
                                             intent: PairMutationIntent,
                                             cloud: CloudSaveLocations?) throws {
        guard liveSource.identity == journalSourceSnapshot(intent).identity else {
            throw intent.sourceKind == .iCloud
                ? SaveSyncError.cloudChangedDuringMerge(intent.evenPath)
                : SaveSyncError.localChangedDuringMerge(intent.evenPath)
        }
        switch intent.sourceKind {
        case .local:
            try assertLocalSourceSlotMatches(liveSource)
        case .iCloud:
            guard let cloud else {
                throw SaveSyncError.invalidPairMutationState(intent.evenPath)
            }
            try assertCloudSourceSlotMatches(liveSource, root: cloud.savesRoot,
                                             coordinated: configuration.coordinateCloudAccess)
        case .imported:
            break
        }
    }

    private func assertLivePairTargetMatches(_ liveTarget: Jak1SlotSnapshot,
                                             intent: PairMutationIntent,
                                             cloud: CloudSaveLocations?) throws {
        guard liveTarget.identity == expectedTargetIdentity(for: intent) else {
            throw SaveSyncError.invalidPairMutationState(intent.evenPath)
        }
        if intent.targetCopy == .local {
            try assertLocalSlotMatches(liveTarget)
        } else {
            guard let cloud else {
                throw SaveSyncError.invalidPairMutationState(intent.evenPath)
            }
            try assertCloudSlotMatches(liveTarget, root: cloud.savesRoot,
                                       coordinated: configuration.coordinateCloudAccess)
        }
    }

    private func assertJournalTargetMatches(_ source: Jak1SlotSnapshot,
                                            intent: PairMutationIntent,
                                            cloud: CloudSaveLocations?) throws {
        if intent.targetCopy == .local {
            try assertLocalSlotMatches(source)
        } else {
            guard let cloud else {
                throw SaveSyncError.invalidPairMutationState(intent.evenPath)
            }
            try assertCloudSlotMatches(source, root: cloud.savesRoot,
                                       coordinated: configuration.coordinateCloudAccess)
        }
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
        if (localMetadata != nil) != (remoteMetadata != nil) {
            return SaveResolution(relativePath: path,
                                  winner: localMetadata != nil ? .local : .iCloud,
                                  basis: .onlyValidJak1Bank)
        }

        let localDate = localMetadata == nil
            ? slotModificationDate(local) : local.effectiveFile?.modificationDate
        let remoteDate = remoteMetadata == nil
            ? slotModificationDate(remote) : remote.effectiveFile?.modificationDate
        if let localDate, let remoteDate, localDate != remoteDate {
            return SaveResolution(relativePath: path,
                                  winner: localDate > remoteDate ? .local : .iCloud,
                                  basis: .modificationDate)
        }
        if let localMetadata, let remoteMetadata,
           localMetadata.saveCount != remoteMetadata.saveCount {
            let winner: SaveResolution.Copy = localMetadata.saveCount
                > remoteMetadata.saveCount ? .local : .iCloud
            return SaveResolution(relativePath: path,
                                  winner: winner,
                                  basis: .saveGeneration(max(localMetadata.saveCount,
                                                             remoteMetadata.saveCount)))
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

    private func archiveDescriptor(for relativePath: String) -> ArchiveDescriptor? {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }
        let markers: [(String, ArchivedSaveSource)] = [
            (".local-", .thisDevice),
            (".icloud-", .iCloud),
            (".before-import-", .beforeImport),
            (".before-restore-", .beforeRestore),
        ]
        for (marker, source) in markers {
            guard let range = relativePath.range(of: marker, options: .backwards) else { continue }
            let canonicalPath = String(relativePath[..<range.lowerBound])
            let hash = String(relativePath[range.upperBound...])
            guard let bankIndex = jak1BankIndex(canonicalPath), isSHA256(hash) else { continue }
            return ArchiveDescriptor(relativePath: relativePath,
                                     canonicalBankPath: canonicalPath,
                                     bankIndex: bankIndex,
                                     source: source,
                                     hash: hash)
        }
        return nil
    }

    private func safeArchiveURL(for relativePath: String) -> URL? {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }
        let candidate = components.reduce(configuration.localConflictsRoot) {
            $0.appending(path: String($1), directoryHint: .notDirectory)
        }
        let rootPath = configuration.localConflictsRoot.resolvingSymlinksInPath()
            .standardizedFileURL.path
        let resolvedPath = candidate.resolvingSymlinksInPath().standardizedFileURL.path
        guard resolvedPath.hasPrefix(rootPath + "/") else { return nil }
        return candidate
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
        let baseName = "Eco Save Export"
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
        try assertLocalSnapshotFile(relativePath: relativePath, matches: expected)
    }

    private func assertLocalSourceFile(relativePath: String, matches expected: SaveFile?) throws {
        try configuration.beforeLocalSourceValidation()
        try assertLocalSnapshotFile(relativePath: relativePath, matches: expected)
    }

    private func assertLocalSnapshotFile(relativePath: String,
                                         matches expected: SaveFile?) throws {
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
        try assertLocalSlotSnapshotMatches(expected)
    }

    private func assertLocalSourceSlotMatches(_ expected: Jak1SlotSnapshot) throws {
        try configuration.beforeLocalSourceValidation()
        try assertLocalSlotSnapshotMatches(expected)
    }

    private func assertLocalSlotSnapshotMatches(_ expected: Jak1SlotSnapshot) throws {
        for path in [expected.evenPath, expected.oddPath] {
            try assertLocalSnapshotFile(relativePath: path, matches: expected.file(at: path))
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

    private func assertCloudSourceFile(relativePath: String, matches expected: SaveFile,
                                       cloud: CloudSaveLocations) throws {
        try configuration.beforeCloudSourceValidation()
        try assertCloudFile(relativePath: relativePath, matches: expected,
                            root: cloud.savesRoot,
                            coordinated: configuration.coordinateCloudAccess)
    }

    private func assertCloudSourceSlotMatches(_ expected: Jak1SlotSnapshot, root: URL,
                                              coordinated: Bool) throws {
        try configuration.beforeCloudSourceValidation()
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

    private func acquireOperation() async {
        if !operationInProgress {
            operationInProgress = true
            return
        }
        await withCheckedContinuation { continuation in
            operationWaiters.append(continuation)
        }
    }

    private func releaseOperation() {
        if operationWaiters.isEmpty {
            operationInProgress = false
        } else {
            operationWaiters.removeFirst().resume()
        }
    }

    private func loadState() throws -> State {
        guard manager.fileExists(atPath: configuration.stateFile.path) else { return State() }
        return try JSONDecoder().decode(State.self, from: Data(contentsOf: configuration.stateFile))
    }

    private func saveState(_ state: State) throws {
        try configuration.beforeStateWrite(state.pairMutationIntent?.phase.rawValue)
        try manager.createDirectory(at: configuration.stateFile.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: configuration.stateFile, options: .atomic)
    }
}
