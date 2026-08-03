// Deterministic host checks for iCloud save mirroring and automatic divergence resolution.
//
// These use synthetic temporary directories and never access an iCloud account or game data.

import CryptoKit
import Foundation

private let memcardDirectory = "BASCUS-97124AYBABTU!"
private let bankPath = memcardDirectory + "/bank0.bin"
private let ordinaryPath = "metadata/save.bin"
private var failures = 0
private var modificationTick: TimeInterval = 1_800_000_000

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("  ok   \(message)")
    } else {
        print("  FAIL \(message)")
        failures += 1
    }
}

private final class Fixture {
    let root: URL
    let local: URL
    let localConflicts: URL
    let cloud: URL
    let cloudConflicts: URL
    let state: URL
    let engine: SaveSyncEngine

    init(cloudAvailable: Bool = true, accountIdentifier: String = "account-a",
         fileSettleDelay: Duration = .milliseconds(1),
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
         operationAwaitHook: @escaping @Sendable () async -> Void = {}) throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "goalpad-save-sync-\(UUID().uuidString)", directoryHint: .isDirectory)
        local = root.appending(path: "local/OpenGOAL/jak1/saves", directoryHint: .isDirectory)
        localConflicts = root.appending(path: "local/GOALPad/SaveConflicts",
                                        directoryHint: .isDirectory)
        cloud = root.appending(path: "cloud/Documents/OpenGOAL/jak1/saves",
                               directoryHint: .isDirectory)
        cloudConflicts = root.appending(path: "cloud/Documents/GOALPad/SaveConflicts",
                                        directoryHint: .isDirectory)
        state = root.appending(path: "local/GOALPad/SaveSync/state-v1.json",
                               directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let locations = CloudSaveLocations(
            savesRoot: cloud,
            conflictsRoot: cloudConflicts,
            accountIdentifier: Data(accountIdentifier.utf8))
        engine = SaveSyncEngine(configuration: .init(
            localRoot: local,
            localConflictsRoot: localConflicts,
            stateFile: state,
            cloudLocations: { cloudAvailable ? locations : nil },
            coordinateCloudAccess: false,
            fileSettleDelay: fileSettleDelay,
            mutationHook: mutationHook,
            beforeLocalReplacement: beforeLocalReplacement,
            beforeCloudReplacement: beforeCloudReplacement,
            beforeLocalSourceValidation: beforeLocalSourceValidation,
            beforeCloudSourceValidation: beforeCloudSourceValidation,
            afterPairIntentPrepared: afterPairIntentPrepared,
            afterPairIntentCommitted: afterPairIntentCommitted,
            afterPairFileMutationBeforePhaseSave: afterPairFileMutationBeforePhaseSave,
            beforeStateWrite: beforeStateWrite,
            operationAwaitHook: operationAwaitHook))
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }
}

private func engine(for fixture: Fixture,
                    cloudAvailable: Bool = true,
                    accountIdentifier: String = "account-a",
                    mutationHook: @escaping @Sendable (SaveMutationPoint) throws -> Void = {
                        _ in
                    },
                    beforeLocalReplacement: @escaping @Sendable () throws -> Void = {},
                    beforeCloudReplacement: @escaping @Sendable () throws -> Void = {},
                    beforeLocalSourceValidation: @escaping @Sendable () throws -> Void = {},
                    beforeCloudSourceValidation: @escaping @Sendable () throws -> Void = {},
                    afterPairIntentPrepared: @escaping @Sendable () throws -> Void = {},
                    afterPairIntentCommitted: @escaping @Sendable () throws -> Void = {},
                    afterPairFileMutationBeforePhaseSave:
                        @escaping @Sendable (SaveMutationPoint) throws -> Void = { _ in },
                    beforeStateWrite: @escaping @Sendable (String?) throws -> Void = { _ in },
                    operationAwaitHook: @escaping @Sendable () async -> Void = {})
    -> SaveSyncEngine {
    let locations = CloudSaveLocations(
        savesRoot: fixture.cloud,
        conflictsRoot: fixture.cloudConflicts,
        accountIdentifier: Data(accountIdentifier.utf8))
    return SaveSyncEngine(configuration: .init(
        localRoot: fixture.local,
        localConflictsRoot: fixture.localConflicts,
        stateFile: fixture.state,
        cloudLocations: { cloudAvailable ? locations : nil },
        coordinateCloudAccess: false,
        fileSettleDelay: .milliseconds(1),
        mutationHook: mutationHook,
        beforeLocalReplacement: beforeLocalReplacement,
        beforeCloudReplacement: beforeCloudReplacement,
        beforeLocalSourceValidation: beforeLocalSourceValidation,
        beforeCloudSourceValidation: beforeCloudSourceValidation,
        afterPairIntentPrepared: afterPairIntentPrepared,
        afterPairIntentCommitted: afterPairIntentCommitted,
        afterPairFileMutationBeforePhaseSave: afterPairFileMutationBeforePhaseSave,
        beforeStateWrite: beforeStateWrite,
        operationAwaitHook: operationAwaitHook))
}

private enum InjectedFailure: Error {
    case mutation(SaveMutationPoint)
    case prepared
    case stateWrite(String?)
}

private final class MutationFault: @unchecked Sendable {
    let target: SaveMutationPoint
    private var hasFired = false

    init(target: SaveMutationPoint) {
        self.target = target
    }

    func callAsFunction(_ point: SaveMutationPoint) throws {
        guard point == target, !hasFired else { return }
        hasFired = true
        throw InjectedFailure.mutation(point)
    }
}

private final class OneShotPreparedFault: @unchecked Sendable {
    private var hasFired = false

    func fire() throws {
        guard !hasFired else { return }
        hasFired = true
        throw InjectedFailure.prepared
    }
}

private final class StateWriteFault: @unchecked Sendable {
    private let target: String?
    private var hasFired = false

    init(target: String?) {
        self.target = target
    }

    func callAsFunction(_ phase: String?) throws {
        guard phase == target, !hasFired else { return }
        hasFired = true
        throw InjectedFailure.stateWrite(phase)
    }
}

private actor OperationGate {
    private var entryCount = 0
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var isReleased = false

    func pauseFirstEntry() async {
        entryCount += 1
        if entryCount == 1 {
            enteredWaiters.forEach { $0.resume() }
            enteredWaiters.removeAll()
            guard !isReleased else { return }
            await withCheckedContinuation { releaseContinuation = $0 }
        }
    }

    func waitUntilEntered() async {
        if entryCount > 0 { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func entries() -> Int { entryCount }

    func release() {
        isReleased = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private final class LocalReplacementRace: @unchecked Sendable {
    let localRoot: URL
    private var hasFired = false

    init(localRoot: URL) {
        self.localRoot = localRoot
    }

    func mutate() throws {
        guard !hasFired else { return }
        hasFired = true
        let date = Date(timeIntervalSince1970: 1_700_001_000)
        try writeBank(progress: 91, saveCount: 10, marker: 91,
                      to: bankFilePath(0), under: localRoot, modificationDate: date)
    }
}

private final class CloudReplacementRace: @unchecked Sendable {
    let cloudRoot: URL
    private var hasFired = false

    init(cloudRoot: URL) {
        self.cloudRoot = cloudRoot
    }

    func mutate() throws {
        guard !hasFired else { return }
        hasFired = true
        let date = Date(timeIntervalSince1970: 1_700_001_000)
        try writeBank(progress: 96, saveCount: 10, marker: 96,
                      to: bankFilePath(0), under: cloudRoot, modificationDate: date)
        try writeBank(progress: 92, saveCount: 9, marker: 92,
                      to: bankFilePath(1), under: cloudRoot, modificationDate: date)
    }
}

private final class OrdinaryFileRace: @unchecked Sendable {
    let root: URL
    let relativePath: String
    let replacement: String
    private var hasFired = false

    init(root: URL, relativePath: String, replacement: String) {
        self.root = root
        self.relativePath = relativePath
        self.replacement = replacement
    }

    func mutate() throws {
        guard !hasFired else { return }
        hasFired = true
        try write(replacement, to: relativePath, under: root)
    }
}

private func file(_ relativePath: String, under root: URL) -> URL {
    root.appending(path: relativePath, directoryHint: .notDirectory)
}

private func bankFilePath(_ index: Int) -> String {
    memcardDirectory + "/bank\(index).bin"
}

private func write(_ text: String, to relativePath: String = bankPath, under root: URL) throws {
    let url = file(relativePath, under: root)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url, options: .atomic)
    modificationTick += 1
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970:
                                                                      modificationTick)],
                                          ofItemAtPath: url.path)
}

private func write(_ text: String, to relativePath: String = bankPath, under root: URL,
                   modificationDate: Date) throws {
    let url = file(relativePath, under: root)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.modificationDate: modificationDate],
                                          ofItemAtPath: url.path)
}

private func setUInt32(_ value: UInt32, in data: inout Data, at offset: Int) {
    data[offset] = UInt8(truncatingIfNeeded: value)
    data[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
    data[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
    data[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
}

private func uint32(in data: Data, at offset: Int) -> UInt32 {
    UInt32(data[offset])
        | (UInt32(data[offset + 1]) << 8)
        | (UInt32(data[offset + 2]) << 16)
        | (UInt32(data[offset + 3]) << 24)
}

private func openGOALChecksum(_ data: Data) -> UInt32 {
    var checksum: UInt32 = 0
    for offset in stride(from: 0x400, to: 0x10400, by: 4) {
        let signMask = UInt32(bitPattern: Int32(bitPattern: checksum) >> 31)
        checksum = (checksum << 1) ^ signMask ^ uint32(in: data, at: offset)
            ^ 0x1234_5678
    }
    return checksum ^ 0xedd1_e666
}

private func jak1Bank(progress: Float, saveCount: UInt32, marker: UInt8) -> Data {
    var data = Data(repeating: 0, count: 0x10800)
    let footer = 0x10400
    setUInt32(saveCount, in: &data, at: 0)
    setUInt32(0x1234_5678, in: &data, at: 8)
    setUInt32(saveCount, in: &data, at: 0x3fc)
    setUInt32(saveCount, in: &data, at: footer)
    setUInt32(0x1234_5678, in: &data, at: footer + 8)
    setUInt32(saveCount, in: &data, at: footer + 0x3fc)
    setUInt32(progress.bitPattern, in: &data, at: 12 + 16)
    setUInt32(progress.bitPattern, in: &data, at: footer + 12 + 16)
    setUInt32(1, in: &data, at: 0x400 + 4)
    setUInt32(progress.bitPattern, in: &data, at: 0x400 + 32)
    data[0x500] = marker
    let checksum = openGOALChecksum(data)
    setUInt32(checksum, in: &data, at: 4)
    setUInt32(checksum, in: &data, at: footer + 4)
    return data
}

private func writeBank(progress: Float, saveCount: UInt32 = 1, marker: UInt8,
                       to relativePath: String = bankPath, under root: URL,
                       modificationDate: Date) throws {
    let url = file(relativePath, under: root)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try jak1Bank(progress: progress, saveCount: saveCount, marker: marker)
        .write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.modificationDate: modificationDate],
                                          ofItemAtPath: url.path)
}

private func data(_ relativePath: String = bankPath, under root: URL) -> Data? {
    try? Data(contentsOf: file(relativePath, under: root))
}

private func loaderSelectedCompletion(evenIndex: Int, under root: URL) -> Float? {
    guard let even = data(bankFilePath(evenIndex), under: root) else { return nil }
    let odd = data(bankFilePath(evenIndex + 1), under: root)
    let selected: Data
    if let odd, uint32(in: even, at: 0) <= uint32(in: odd, at: 0) {
        selected = odd
    } else {
        selected = even
    }
    return Float(bitPattern: uint32(in: selected, at: 0x400 + 32))
}

private func read(_ relativePath: String = bankPath, under root: URL) -> String? {
    guard let data = try? Data(contentsOf: file(relativePath, under: root)) else { return nil }
    return String(decoding: data, as: UTF8.self)
}

private func regularFiles(under root: URL) -> [URL] {
    guard let enumerator = FileManager.default.enumerator(at: root,
                                                          includingPropertiesForKeys: [.isRegularFileKey])
    else { return [] }
    return enumerator.compactMap { item in
        guard let url = item as? URL,
              (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        else { return nil }
        return url
    }
}

private func unavailableKeepsLocalSaves() async throws {
    print("iCloud being unavailable is a local-only success")
    let fixture = try Fixture(cloudAvailable: false)
    try write("local-save", to: ordinaryPath, under: fixture.local)

    let outcome = try await fixture.engine.sync()
    check(outcome.availability == .unavailable, "unavailable is reported without throwing")
    check(read(ordinaryPath, under: fixture.local) == "local-save",
          "the gameplay save is untouched")
    check(!FileManager.default.fileExists(atPath: fixture.cloud.path),
          "no cloud directory is required")
}

private func localOnlyUploadsDesktopLayout() async throws {
    print("a local OpenGOAL memcard is mirrored without changing its layout")
    let fixture = try Fixture()
    let bank = jak1Bank(progress: 10, saveCount: 1, marker: 1)
    let bankURL = file(bankPath, under: fixture.local)
    try FileManager.default.createDirectory(at: bankURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try bank.write(to: bankURL, options: .atomic)

    let outcome = try await fixture.engine.sync()
    check(outcome.uploaded == 1 && outcome.downloaded == 0, "one local bank uploads")
    check(data(under: fixture.cloud) == bank,
          "BASCUS-97124AYBABTU!/bank0.bin is byte-compatible in iCloud")
    check(outcome.resolutions.isEmpty, "a one-sided save needs no resolution")
}

private func cloudOnlyDownloadsBeforeGameplay() async throws {
    print("an iCloud-only memcard becomes a local gameplay save")
    let fixture = try Fixture()
    let bank = jak1Bank(progress: 12, saveCount: 1, marker: 2)
    let bankURL = file(bankPath, under: fixture.cloud)
    try FileManager.default.createDirectory(at: bankURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try bank.write(to: bankURL, options: .atomic)

    let outcome = try await fixture.engine.sync()
    check(outcome.downloaded == 1 && outcome.uploaded == 0, "one cloud bank downloads")
    check(data(under: fixture.local) == bank, "the local OpenGOAL path receives it")
}

private func changedSideWinsAgainstBaseline() async throws {
    print("a known unchanged side can safely receive the changed side")
    let fixture = try Fixture()
    try write("baseline", to: ordinaryPath, under: fixture.local)
    _ = try await fixture.engine.sync()

    try write("new-local-save", to: ordinaryPath, under: fixture.local)
    let localOutcome = try await fixture.engine.syncIfLocalFilesChanged()
    check(localOutcome?.uploaded == 1, "a completed local write triggers an upload")
    check(read(ordinaryPath, under: fixture.cloud) == "new-local-save",
          "the cloud mirror advances")

    try write("new-cloud-save", to: ordinaryPath, under: fixture.cloud)
    let cloudOutcome = try await fixture.engine.sync()
    check(cloudOutcome.downloaded == 1, "a changed cloud bank downloads on the next sync")
    check(read(ordinaryPath, under: fixture.local) == "new-cloud-save",
          "the local gameplay copy advances")
}

private func initialDivergenceUsesNewestDateAndPreservesBoth() async throws {
    print("unrecognized divergent files use modification date and preserve both")
    let fixture = try Fixture()
    try write("local-version", to: ordinaryPath, under: fixture.local)
    try write("cloud-version", to: ordinaryPath, under: fixture.cloud)

    let outcome = try await fixture.engine.sync()
    check(outcome.resolutions == [SaveResolution(relativePath: ordinaryPath, winner: .iCloud,
                                                  basis: .modificationDate)],
          "the newer iCloud file wins without a decision")
    check(read(ordinaryPath, under: fixture.local) == "cloud-version",
          "the gameplay copy advances")
    check(read(ordinaryPath, under: fixture.cloud) == "cloud-version",
          "the cloud mirror stays canonical")

    let localCopies = regularFiles(under: fixture.localConflicts)
    let cloudCopies = regularFiles(under: fixture.cloudConflicts)
    check(localCopies.count == 2, "both original versions have local archive copies")
    check(cloudCopies.count == 2, "both original versions have iCloud archive copies")
    let localArchiveData = Set(localCopies.compactMap { try? Data(contentsOf: $0) })
    let cloudArchiveData = Set(cloudCopies.compactMap { try? Data(contentsOf: $0) })
    let expected = Set([Data("local-version".utf8), Data("cloud-version".utf8)])
    check(localArchiveData == expected, "the local archive contains both originals")
    check(cloudArchiveData == expected, "the iCloud archive contains both originals")
}

private func twoSidedChangeAutomaticallyResolves() async throws {
    print("two changes after a shared baseline also resolve without blocking")
    let fixture = try Fixture()
    try write("baseline", to: ordinaryPath, under: fixture.local)
    _ = try await fixture.engine.sync()
    try write("new-local", to: ordinaryPath, under: fixture.local)
    try write("new-cloud", to: ordinaryPath, under: fixture.cloud)

    let outcome = try await fixture.engine.sync()
    check(outcome.resolutions.first?.winner == .iCloud, "the newer two-sided copy wins")
    check(read(ordinaryPath, under: fixture.local) == "new-cloud",
          "the local authority receives the winner")
    check(read(ordinaryPath, under: fixture.cloud) == "new-cloud",
          "the cloud mirror receives the winner")
}

private func completionPercentageBeatsModificationDate() async throws {
    print("validated OpenGOAL completion percentage ranks real Jak 1 banks")
    let fixture = try Fixture()
    let older = Date(timeIntervalSince1970: 1_700_000_000)
    let newer = older.addingTimeInterval(300)
    try writeBank(progress: 72, marker: 1, under: fixture.local, modificationDate: older)
    try writeBank(progress: 44, marker: 2, under: fixture.cloud, modificationDate: newer)

    let outcome = try await fixture.engine.sync()
    check(outcome.resolutions == [SaveResolution(relativePath: bankPath, winner: .local,
                                                  basis: .completionPercentage(72))],
          "the farther-progress local bank wins even though its date is older")
    check(data(under: fixture.local) == data(under: fixture.cloud),
          "both canonical copies contain the progress winner")
    check(data(under: fixture.local) == jak1Bank(progress: 72, saveCount: 1, marker: 1),
          "the winning bank remains byte-for-byte desktop compatible")
}

private func equalProgressFallsBackToNewestDate() async throws {
    print("equal validated progress falls back to modification date")
    let fixture = try Fixture()
    let older = Date(timeIntervalSince1970: 1_700_000_000)
    let newer = older.addingTimeInterval(300)
    try writeBank(progress: 55, marker: 1, under: fixture.local, modificationDate: older)
    try writeBank(progress: 55, marker: 2, under: fixture.cloud, modificationDate: newer)

    let outcome = try await fixture.engine.sync()
    check(outcome.resolutions.first?.winner == .iCloud,
          "the newer bank wins when neither has farther progress")
    check(outcome.resolutions.first?.basis == .modificationDate,
          "the tie is explicitly date-based")
}

private func validBankBeatsNewerCorruptBank() async throws {
    print("a valid Jak 1 bank beats a newer corrupt bank")
    let fixture = try Fixture()
    let older = Date(timeIntervalSince1970: 1_700_000_000)
    let newer = older.addingTimeInterval(300)
    var corruptHighProgress = jak1Bank(progress: 99, saveCount: 1, marker: 1)
    corruptHighProgress[0x500] ^= 1
    let localURL = file(bankPath, under: fixture.local)
    try FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try corruptHighProgress.write(to: localURL, options: .atomic)
    try FileManager.default.setAttributes([.modificationDate: newer],
                                          ofItemAtPath: localURL.path)
    try writeBank(progress: 12, marker: 2, under: fixture.cloud, modificationDate: older)

    let outcome = try await fixture.engine.sync()
    check(outcome.resolutions.first?.winner == .iCloud,
          "the valid copy wins even when the corrupt copy is newer")
    check(outcome.resolutions.first?.basis == .onlyValidJak1Bank,
          "the resolution explicitly records that only one bank validated")
}

private func pairedBanksResolveAsOneSlot() async throws {
    print("alternating Jak 1 banks resolve as one logical slot")
    let fixture = try Fixture()
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    try writeBank(progress: 80, saveCount: 4, marker: 1,
                  to: bankFilePath(0), under: fixture.local, modificationDate: date)
    try writeBank(progress: 10, saveCount: 3, marker: 2,
                  to: bankFilePath(1), under: fixture.local, modificationDate: date)
    try writeBank(progress: 70, saveCount: 4, marker: 3,
                  to: bankFilePath(0), under: fixture.cloud, modificationDate: date)
    try writeBank(progress: 75, saveCount: 5, marker: 4,
                  to: bankFilePath(1), under: fixture.cloud, modificationDate: date)
    let originalLocalEven = data(bankFilePath(0), under: fixture.local)
    let originalLocalOdd = data(bankFilePath(1), under: fixture.local)

    let outcome = try await fixture.engine.sync()
    check(outcome.resolutions == [SaveResolution(relativePath: bankFilePath(0), winner: .local,
                                                  basis: .completionPercentage(80))],
          "the side whose loader-selected generation is farther wins the whole slot")
    check(data(bankFilePath(0), under: fixture.cloud) == originalLocalEven,
          "the winning even bank replaces its cloud peer")
    check(data(bankFilePath(1), under: fixture.cloud) == originalLocalOdd,
          "the winning odd bank stays paired with its even bank")
    check(loaderSelectedCompletion(evenIndex: 0, under: fixture.local) == 80,
          "the local loader sees the chosen 80% generation")
    check(loaderSelectedCompletion(evenIndex: 0, under: fixture.cloud) == 80,
          "the cloud mirror cannot become a 75% hybrid")

    let localArchives = regularFiles(under: fixture.localConflicts)
    let cloudArchives = regularFiles(under: fixture.cloudConflicts)
    check(localArchives.count == 4, "all four divergent bank originals are archived locally")
    check(cloudArchives.count == 4, "all four divergent bank originals are archived in iCloud")
}

private func pairResolutionRemovesLoserOnlyPeerAfterArchiving() async throws {
    print("pair resolution removes a loser-only peer after archiving it")
    let fixture = try Fixture()
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    try writeBank(progress: 80, saveCount: 4, marker: 1,
                  to: bankFilePath(0), under: fixture.local, modificationDate: date)
    try writeBank(progress: 60, saveCount: 4, marker: 2,
                  to: bankFilePath(0), under: fixture.cloud, modificationDate: date)
    try writeBank(progress: 70, saveCount: 5, marker: 3,
                  to: bankFilePath(1), under: fixture.cloud, modificationDate: date)
    let loserOnlyPeer = data(bankFilePath(1), under: fixture.cloud)

    let outcome = try await fixture.engine.sync()
    check(outcome.resolutions.first?.winner == .local,
          "the 80% local slot beats the 70% cloud slot")
    check(data(bankFilePath(1), under: fixture.local) == nil,
          "the winner remains a one-bank slot")
    check(data(bankFilePath(1), under: fixture.cloud) == nil,
          "the loser-only peer is removed from the canonical cloud pair")
    check(regularFiles(under: fixture.localConflicts).contains {
        (try? Data(contentsOf: $0)) == loserOnlyPeer
    }, "the removed peer remains recoverable in the local archive")
    check(regularFiles(under: fixture.cloudConflicts).contains {
        (try? Data(contentsOf: $0)) == loserOnlyPeer
    }, "the removed peer remains recoverable in the iCloud archive")
}

private func loaderSaveCountTieSelectsOddBank() async throws {
    print("pair comparison reproduces the loader's odd-bank save-count tie")
    let fixture = try Fixture()
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    try writeBank(progress: 90, saveCount: 4, marker: 1,
                  to: bankFilePath(0), under: fixture.local, modificationDate: date)
    try writeBank(progress: 10, saveCount: 4, marker: 2,
                  to: bankFilePath(1), under: fixture.local, modificationDate: date)
    try writeBank(progress: 20, saveCount: 3, marker: 3,
                  to: bankFilePath(0), under: fixture.cloud, modificationDate: date)
    try writeBank(progress: 15, saveCount: 2, marker: 4,
                  to: bankFilePath(1), under: fixture.cloud, modificationDate: date)

    let outcome = try await fixture.engine.sync()
    check(outcome.resolutions.first?.winner == .iCloud,
          "the local odd-bank tie exposes 10%, so the cloud slot's 20% wins")
    check(outcome.downloaded == 2,
          "replacing both local members reports two logical downloads")
    check(loaderSelectedCompletion(evenIndex: 0, under: fixture.local) == 20,
          "the canonical pair follows the loader's exact tie rule")
}

private func equalDatesKeepLocalAuthorityWithoutHashOrdering() async throws {
    print("equal dates keep local gameplay authority without ranking hashes")
    let fixture = try Fixture()
    let sameDate = Date(timeIntervalSince1970: 1_700_000_000)
    try write("local-tie", to: ordinaryPath, under: fixture.local,
              modificationDate: sameDate)
    try write("cloud-tie", to: ordinaryPath, under: fixture.cloud,
              modificationDate: sameDate)

    let outcome = try await fixture.engine.sync()
    check(outcome.resolutions.first?.winner == .local, "the existing local authority wins a tie")
    check(outcome.resolutions.first?.basis == .localGameplayAuthority,
          "hashes are identities only, not an ordering heuristic")
    check(read(ordinaryPath, under: fixture.cloud) == "local-tie",
          "the tied local copy becomes the mirror")
}

private func missingSideIsRestored() async throws {
    print("a missing file is restored instead of propagating a deletion")
    let fixture = try Fixture()
    try write("save", to: ordinaryPath, under: fixture.local)
    _ = try await fixture.engine.sync()
    try FileManager.default.removeItem(at: file(ordinaryPath, under: fixture.local))

    let outcome = try await fixture.engine.syncIfLocalFilesChanged()
    check(outcome?.downloaded == 1, "the surviving cloud bank is downloaded")
    check(read(ordinaryPath, under: fixture.local) == "save", "the local save is restored")
}

private func accountSwitchCannotReuseAnOldBaseline() async throws {
    print("switching iCloud accounts invalidates the old merge baseline")
    let fixture = try Fixture(accountIdentifier: "account-a")
    try write("account-a-save", to: ordinaryPath, under: fixture.local)
    _ = try await fixture.engine.sync()

    let accountBCloud = fixture.root.appending(path: "account-b/Documents/OpenGOAL/jak1/saves",
                                                directoryHint: .isDirectory)
    let accountBConflicts = fixture.root.appending(path: "account-b/Documents/GOALPad/SaveConflicts",
                                                    directoryHint: .isDirectory)
    try write("account-b-save", to: ordinaryPath, under: accountBCloud)
    let accountBLocations = CloudSaveLocations(
        savesRoot: accountBCloud,
        conflictsRoot: accountBConflicts,
        accountIdentifier: Data("account-b".utf8))
    let accountBEngine = SaveSyncEngine(configuration: .init(
        localRoot: fixture.local,
        localConflictsRoot: fixture.localConflicts,
        stateFile: fixture.state,
        cloudLocations: { accountBLocations },
        coordinateCloudAccess: false,
        fileSettleDelay: .milliseconds(1)))

    let outcome = try await accountBEngine.sync()
    check(outcome.resolutions.first?.winner == .iCloud,
          "the new account is compared without account A's baseline")
    check(read(ordinaryPath, under: fixture.local) == "account-b-save",
          "the newer account B save becomes active")
    check(read(ordinaryPath, under: accountBCloud) == "account-b-save",
          "the account B cloud save stays intact")
}

private func changingFileIsReadAgainBeforeUpload() async throws {
    print("a save that changes during a snapshot is read again before upload")
    let fixture = try Fixture(fileSettleDelay: .milliseconds(50))
    try write("first-write", to: ordinaryPath, under: fixture.local)
    let writer = Task {
        try await Task.sleep(for: .milliseconds(10))
        try write("completed-write", to: ordinaryPath, under: fixture.local)
    }

    let outcome = try await fixture.engine.sync()
    try await writer.value
    check(outcome.uploaded == 1, "the stable completed save uploads once")
    check(read(ordinaryPath, under: fixture.cloud) == "completed-write",
          "the first changing snapshot never reaches iCloud")
}

private func newerSaveDuringCloudWorkGetsANextSync() async throws {
    print("a save completed after its snapshot aborts the stale upload and remains pending")
    let fixture = try Fixture(fileSettleDelay: .milliseconds(50))
    try write("first-save", to: ordinaryPath, under: fixture.local)
    for index in 1...6 {
        try write("cloud-\(index)", to: "sync-delay/cloud-\(index).bin",
                  under: fixture.cloud)
    }
    let writer = Task {
        try await Task.sleep(for: .milliseconds(120))
        try write("second-save", to: ordinaryPath, under: fixture.local)
    }

    var staleUploadRejected = false
    do {
        _ = try await fixture.engine.sync()
    } catch {
        staleUploadRejected = true
    }
    try await writer.value
    check(staleUploadRejected, "source CAS rejects the already-stale local snapshot")
    check(read(ordinaryPath, under: fixture.cloud) == nil,
          "the stale local bytes never become the cloud mirror")
    let followUp = try await fixture.engine.syncIfLocalFilesChanged()
    check(followUp?.uploaded == 1, "the later completed save remains detectable")
    check(read(ordinaryPath, under: fixture.cloud) == "second-save",
          "the next sync mirrors the later save")
}

private func uploadOnlyKeepsActiveLocalAuthority() async throws {
    print("active gameplay uploads without replacing the local slot")
    let fixture = try Fixture()
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    try writeBank(progress: 80, saveCount: 6, marker: 1,
                  to: bankFilePath(0), under: fixture.local, modificationDate: date)
    try writeBank(progress: 70, saveCount: 5, marker: 2,
                  to: bankFilePath(1), under: fixture.local, modificationDate: date)
    try writeBank(progress: 95, saveCount: 8, marker: 3,
                  to: bankFilePath(0), under: fixture.cloud,
                  modificationDate: date.addingTimeInterval(60))
    try writeBank(progress: 90, saveCount: 7, marker: 4,
                  to: bankFilePath(1), under: fixture.cloud,
                  modificationDate: date.addingTimeInterval(60))
    let localEven = data(bankFilePath(0), under: fixture.local)
    let localOdd = data(bankFilePath(1), under: fixture.local)
    let cloudEven = data(bankFilePath(0), under: fixture.cloud)
    let cloudOdd = data(bankFilePath(1), under: fixture.cloud)

    let outcome = try await fixture.engine.sync(mode: .uploadOnly)
    check(outcome.downloaded == 0, "active runtime never downloads into gameplay storage")
    check(outcome.uploaded == 2,
          "replacing both pair members reports two logical files, not three mutations")
    check(outcome.resolutions == [SaveResolution(relativePath: bankFilePath(0), winner: .local,
                                                  basis: .activeGameplayAuthority)],
          "the non-blocking result records active gameplay authority for Settings")
    check(data(bankFilePath(0), under: fixture.local) == localEven
            && data(bankFilePath(1), under: fixture.local) == localOdd,
          "the local pair is untouched while frames may run")
    check(data(bankFilePath(0), under: fixture.cloud) == localEven
            && data(bankFilePath(1), under: fixture.cloud) == localOdd,
          "the cloud mirror receives the active local pair")
    let localArchiveData = Set(regularFiles(under: fixture.localConflicts)
        .compactMap { try? Data(contentsOf: $0) })
    let cloudArchiveData = Set(regularFiles(under: fixture.cloudConflicts)
        .compactMap { try? Data(contentsOf: $0) })
    check(localArchiveData == Set([cloudEven, cloudOdd].compactMap { $0 }),
          "both divergent cloud members are archived locally before upload")
    check(cloudArchiveData == Set([cloudEven, cloudOdd].compactMap { $0 }),
          "both divergent cloud members are archived in iCloud before upload")

    let persisted = try JSONEncoder().encode(outcome.resolutions)
    let restored = try JSONDecoder().decode([SaveResolution].self, from: persisted)
    check(restored == outcome.resolutions,
          "the last automatic resolution is persistable until Settings replaces or dismisses it")

    let identical = try await fixture.engine.sync(mode: .uploadOnly)
    check(identical.uploaded == 0 && identical.downloaded == 0,
          "an identical active-runtime pair causes no file changes")
    check(identical.resolutions.isEmpty,
          "an identical active-runtime pair does not persist a false resolution")
}

private func cloudToLocalCASPreservesConcurrentLocalWrite() async throws {
    print("cloud-to-local replacement aborts if gameplay changes the destination")
    let fixture = try Fixture()
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    try writeBank(progress: 20, saveCount: 4, marker: 1,
                  to: bankFilePath(0), under: fixture.local, modificationDate: date)
    try writeBank(progress: 10, saveCount: 3, marker: 2,
                  to: bankFilePath(1), under: fixture.local, modificationDate: date)
    try writeBank(progress: 70, saveCount: 6, marker: 3,
                  to: bankFilePath(0), under: fixture.cloud,
                  modificationDate: date.addingTimeInterval(60))
    try writeBank(progress: 60, saveCount: 5, marker: 4,
                  to: bankFilePath(1), under: fixture.cloud,
                  modificationDate: date.addingTimeInterval(60))
    let cloudEven = data(bankFilePath(0), under: fixture.cloud)
    let cloudOdd = data(bankFilePath(1), under: fixture.cloud)
    let race = LocalReplacementRace(localRoot: fixture.local)
    let racingEngine = engine(for: fixture, beforeLocalReplacement: { try race.mutate() })

    var rejected = false
    do {
        _ = try await racingEngine.sync(mode: .bidirectional)
    } catch {
        rejected = true
    }
    check(rejected, "the compare-and-swap rejects the stale local snapshot")
    check(loaderSelectedCompletion(evenIndex: 0, under: fixture.local) == 91,
          "the concurrent gameplay save remains the local loader winner")
    check(data(bankFilePath(0), under: fixture.local)
            == jak1Bank(progress: 91, saveCount: 10, marker: 91),
          "the exact concurrent local bytes survive the failed replacement")
    check(data(bankFilePath(0), under: fixture.cloud) == cloudEven
            && data(bankFilePath(1), under: fixture.cloud) == cloudOdd,
          "the cloud source is unchanged by the rejected local replacement")
}

private func localToCloudCASPreservesConcurrentCloudWrite() async throws {
    print("local-to-cloud replacement aborts if another device changes the destination")
    let fixture = try Fixture()
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    try writeBank(progress: 80, saveCount: 6, marker: 1,
                  to: bankFilePath(0), under: fixture.local, modificationDate: date)
    try writeBank(progress: 70, saveCount: 5, marker: 2,
                  to: bankFilePath(1), under: fixture.local, modificationDate: date)
    try writeBank(progress: 20, saveCount: 4, marker: 3,
                  to: bankFilePath(0), under: fixture.cloud, modificationDate: date)
    try writeBank(progress: 10, saveCount: 3, marker: 4,
                  to: bankFilePath(1), under: fixture.cloud, modificationDate: date)
    let localEven = data(bankFilePath(0), under: fixture.local)
    let localOdd = data(bankFilePath(1), under: fixture.local)
    let race = CloudReplacementRace(cloudRoot: fixture.cloud)
    let racingEngine = engine(for: fixture, beforeCloudReplacement: { try race.mutate() })

    var rejected = false
    do {
        _ = try await racingEngine.sync(mode: .uploadOnly)
    } catch {
        rejected = true
    }
    check(rejected, "the cloud compare-and-swap rejects the stale destination snapshot")
    check(data(bankFilePath(0), under: fixture.local) == localEven
            && data(bankFilePath(1), under: fixture.local) == localOdd,
          "cloud-side contention never changes the local gameplay pair")
    check(data(bankFilePath(0), under: fixture.cloud)
            == jak1Bank(progress: 96, saveCount: 10, marker: 96)
            && data(bankFilePath(1), under: fixture.cloud)
            == jak1Bank(progress: 92, saveCount: 9, marker: 92),
          "the other device's newer cloud pair is not silently overwritten")
}

private func pairSourceCASRejectsRacesInBothDirections() async throws {
    print("pair source CAS rejects local and cloud changes after snapshot")
    let date = Date(timeIntervalSince1970: 1_700_000_000)

    let localFixture = try Fixture()
    try writeBank(progress: 80, saveCount: 6, marker: 1,
                  to: bankFilePath(0), under: localFixture.local, modificationDate: date)
    try writeBank(progress: 70, saveCount: 5, marker: 2,
                  to: bankFilePath(1), under: localFixture.local, modificationDate: date)
    try writeBank(progress: 20, saveCount: 4, marker: 3,
                  to: bankFilePath(0), under: localFixture.cloud, modificationDate: date)
    try writeBank(progress: 10, saveCount: 3, marker: 4,
                  to: bankFilePath(1), under: localFixture.cloud, modificationDate: date)
    let oldCloudEven = data(bankFilePath(0), under: localFixture.cloud)
    let oldCloudOdd = data(bankFilePath(1), under: localFixture.cloud)
    let localRace = LocalReplacementRace(localRoot: localFixture.local)
    let localSourceEngine = engine(
        for: localFixture, beforeLocalSourceValidation: { try localRace.mutate() })
    var localRejected = false
    do {
        _ = try await localSourceEngine.sync(mode: .uploadOnly)
    } catch {
        localRejected = true
    }
    check(localRejected, "a changed local pair aborts its stale cloud upload")
    check(data(bankFilePath(0), under: localFixture.cloud) == oldCloudEven
            && data(bankFilePath(1), under: localFixture.cloud) == oldCloudOdd,
          "local source contention leaves the cloud target untouched")
    check(loaderSelectedCompletion(evenIndex: 0, under: localFixture.local) == 91,
          "the newer local source generation remains authoritative")
    let localRaceState = try JSONSerialization.jsonObject(
        with: Data(contentsOf: localFixture.state)) as? [String: Any]
    check(localRaceState?["pairMutationIntent"] == nil,
          "prepared local-source drift clears its journal durably")

    let cloudFixture = try Fixture()
    try writeBank(progress: 20, saveCount: 4, marker: 5,
                  to: bankFilePath(0), under: cloudFixture.local, modificationDate: date)
    try writeBank(progress: 10, saveCount: 3, marker: 6,
                  to: bankFilePath(1), under: cloudFixture.local, modificationDate: date)
    _ = try await cloudFixture.engine.sync()
    try writeBank(progress: 70, saveCount: 6, marker: 7,
                  to: bankFilePath(0), under: cloudFixture.cloud,
                  modificationDate: date.addingTimeInterval(60))
    try writeBank(progress: 60, saveCount: 5, marker: 8,
                  to: bankFilePath(1), under: cloudFixture.cloud,
                  modificationDate: date.addingTimeInterval(60))
    let oldLocalEven = data(bankFilePath(0), under: cloudFixture.local)
    let oldLocalOdd = data(bankFilePath(1), under: cloudFixture.local)
    let cloudRace = CloudReplacementRace(cloudRoot: cloudFixture.cloud)
    let cloudSourceEngine = engine(
        for: cloudFixture, beforeCloudSourceValidation: { try cloudRace.mutate() })
    var cloudRejected = false
    do {
        _ = try await cloudSourceEngine.sync(mode: .bidirectional)
    } catch {
        cloudRejected = true
    }
    check(cloudRejected, "a changed cloud pair aborts its stale local download")
    check(data(bankFilePath(0), under: cloudFixture.local) == oldLocalEven
            && data(bankFilePath(1), under: cloudFixture.local) == oldLocalOdd,
          "cloud source contention leaves the local target untouched")
    check(loaderSelectedCompletion(evenIndex: 0, under: cloudFixture.cloud) == 96,
          "the other device's newer cloud source generation survives")
    let cloudRaceState = try JSONSerialization.jsonObject(
        with: Data(contentsOf: cloudFixture.state)) as? [String: Any]
    check(cloudRaceState?["pairMutationIntent"] == nil,
          "prepared cloud-source drift clears its journal durably")
}

private func ordinarySourceCASRejectsRacesInBothDirections() async throws {
    print("ordinary-file source CAS rejects local and cloud changes after snapshot")
    let path = "metadata/session.dat"

    let localFixture = try Fixture()
    try write("local-snapshot", to: path, under: localFixture.local)
    try write("cloud-target", to: path, under: localFixture.cloud)
    let localRace = OrdinaryFileRace(root: localFixture.local, relativePath: path,
                                     replacement: "local-next-generation")
    let localSourceEngine = engine(
        for: localFixture, beforeLocalSourceValidation: { try localRace.mutate() })
    var localRejected = false
    do {
        _ = try await localSourceEngine.sync(mode: .uploadOnly)
    } catch {
        localRejected = true
    }
    check(localRejected, "a changed ordinary local source aborts upload")
    check(read(path, under: localFixture.local) == "local-next-generation",
          "the ordinary local next generation survives")
    check(read(path, under: localFixture.cloud) == "cloud-target",
          "the ordinary cloud target is not overwritten by a stale source")

    let cloudFixture = try Fixture()
    try write("baseline", to: path, under: cloudFixture.local)
    _ = try await cloudFixture.engine.sync()
    try write("cloud-snapshot", to: path, under: cloudFixture.cloud)
    let cloudRace = OrdinaryFileRace(root: cloudFixture.cloud, relativePath: path,
                                     replacement: "cloud-next-generation")
    let cloudSourceEngine = engine(
        for: cloudFixture, beforeCloudSourceValidation: { try cloudRace.mutate() })
    var cloudRejected = false
    do {
        _ = try await cloudSourceEngine.sync(mode: .bidirectional)
    } catch {
        cloudRejected = true
    }
    check(cloudRejected, "a changed ordinary cloud source aborts download")
    check(read(path, under: cloudFixture.local) == "baseline",
          "the ordinary local target remains untouched")
    check(read(path, under: cloudFixture.cloud) == "cloud-next-generation",
          "the ordinary cloud next generation survives")
}

private func interruptedPairMutationRecoversWithoutHybrid() async throws {
    print("odd-first pair replacement recovers after every mutation boundary")
    for point in [SaveMutationPoint.removedOdd, .replacedEven, .wroteOdd] {
        let fixture = try Fixture()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try writeBank(progress: 40, saveCount: 4, marker: 1,
                      to: bankFilePath(0), under: fixture.local, modificationDate: date)
        try writeBank(progress: 30, saveCount: 3, marker: 2,
                      to: bankFilePath(1), under: fixture.local, modificationDate: date)
        _ = try await fixture.engine.sync()

        try writeBank(progress: 80, saveCount: 6, marker: 3,
                      to: bankFilePath(0), under: fixture.local,
                      modificationDate: date.addingTimeInterval(60))
        try writeBank(progress: 70, saveCount: 5, marker: 4,
                      to: bankFilePath(1), under: fixture.local,
                      modificationDate: date.addingTimeInterval(60))
        let winningEven = data(bankFilePath(0), under: fixture.local)
        let winningOdd = data(bankFilePath(1), under: fixture.local)
        let fault = MutationFault(target: point)
        let interruptedEngine = engine(for: fixture, mutationHook: { try fault($0) })

        var injected = false
        do {
            _ = try await interruptedEngine.sync()
        } catch InjectedFailure.mutation(let actualPoint) {
            injected = actualPoint == point
        } catch {}
        check(injected, "fault is injected after \(point)")
        let stateObject = try JSONSerialization.jsonObject(
            with: Data(contentsOf: fixture.state)) as? [String: Any]
        let intent = stateObject?["pairMutationIntent"] as? [String: Any]
        let expectedPhase: String
        switch point {
        case .removedOdd: expectedPhase = "oddRemoved"
        case .replacedEven: expectedPhase = "evenReplaced"
        case .wroteOdd: expectedPhase = "oddWritten"
        case .archived: expectedPhase = "prepared"
        }
        check(intent?["phase"] as? String == expectedPhase,
              "journal phase \(expectedPhase) is durable before restart")
        check(loaderSelectedCompletion(evenIndex: 0, under: fixture.cloud)
                == (point == .removedOdd ? 40 : 80),
              "interrupted \(point) state remains a loadable single generation")

        let recovery = try await engine(for: fixture).sync()
        check(recovery.resolutions.isEmpty,
              "restart recognizes ordered \(point) state without arbitrary conflict ranking")
        check(data(bankFilePath(0), under: fixture.cloud) == winningEven
                && data(bankFilePath(1), under: fixture.cloud) == winningOdd,
              "restart after \(point) completes the winning pair without a hybrid")
        check(loaderSelectedCompletion(evenIndex: 0, under: fixture.cloud) == 80,
              "the recovered \(point) pair selects the intended generation")
    }

    for point in [SaveMutationPoint.removedOdd, .replacedEven, .wroteOdd] {
        let fixture = try Fixture()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try writeBank(progress: 40, saveCount: 4, marker: 11,
                      to: bankFilePath(0), under: fixture.local, modificationDate: date)
        try writeBank(progress: 30, saveCount: 3, marker: 12,
                      to: bankFilePath(1), under: fixture.local, modificationDate: date)
        _ = try await fixture.engine.sync()

        try writeBank(progress: 80, saveCount: 6, marker: 13,
                      to: bankFilePath(0), under: fixture.cloud,
                      modificationDate: date.addingTimeInterval(60))
        try writeBank(progress: 70, saveCount: 5, marker: 14,
                      to: bankFilePath(1), under: fixture.cloud,
                      modificationDate: date.addingTimeInterval(60))
        let winningEven = data(bankFilePath(0), under: fixture.cloud)
        let winningOdd = data(bankFilePath(1), under: fixture.cloud)
        let fault = MutationFault(target: point)
        let interruptedEngine = engine(for: fixture, mutationHook: { try fault($0) })

        var injected = false
        do {
            _ = try await interruptedEngine.sync()
        } catch InjectedFailure.mutation(let actualPoint) {
            injected = actualPoint == point
        } catch {}
        check(injected, "local-target fault is injected after \(point)")
        check(loaderSelectedCompletion(evenIndex: 0, under: fixture.local)
                == (point == .removedOdd ? 40 : 80),
              "interrupted local-target \(point) state stays loadable")

        let recovery = try await engine(for: fixture).sync()
        check(recovery.resolutions.isEmpty,
              "local-target restart recognizes ordered \(point) state from its baseline")
        check(data(bankFilePath(0), under: fixture.local) == winningEven
                && data(bankFilePath(1), under: fixture.local) == winningOdd,
              "local-target restart after \(point) completes without a hybrid")
        check(loaderSelectedCompletion(evenIndex: 0, under: fixture.local) == 80,
              "the recovered local-target \(point) pair selects the intended generation")
    }
}

private func mutationCrashWindowsRecoverFromExactNextPhase() async throws {
    print("pair recovery accepts only the exact file state one phase ahead of the journal")
    let expectedStoredPhase: [SaveMutationPoint: String] = [
        .removedOdd: "committed",
        .replacedEven: "oddRemoved",
        .wroteOdd: "evenReplaced"
    ]
    for point in [SaveMutationPoint.removedOdd, .replacedEven, .wroteOdd] {
        let fault = MutationFault(target: point)
        let fixture = try Fixture()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try writeBank(progress: 40, saveCount: 4, marker: 31,
                      to: bankFilePath(0), under: fixture.local, modificationDate: date)
        try writeBank(progress: 30, saveCount: 3, marker: 32,
                      to: bankFilePath(1), under: fixture.local, modificationDate: date)
        _ = try await fixture.engine.sync()
        try writeBank(progress: 80, saveCount: 6, marker: 33,
                      to: bankFilePath(0), under: fixture.local,
                      modificationDate: date.addingTimeInterval(60))
        try writeBank(progress: 70, saveCount: 5, marker: 34,
                      to: bankFilePath(1), under: fixture.local,
                      modificationDate: date.addingTimeInterval(60))
        let winningEven = data(bankFilePath(0), under: fixture.local)
        let winningOdd = data(bankFilePath(1), under: fixture.local)

        var interrupted = false
        do {
            _ = try await engine(
                for: fixture,
                afterPairFileMutationBeforePhaseSave: { try fault($0) }).sync()
        } catch InjectedFailure.mutation(let actual) {
            interrupted = actual == point
        } catch {}
        check(interrupted, "crash is injected before the \(point) phase save")
        let stateObject = try JSONSerialization.jsonObject(
            with: Data(contentsOf: fixture.state)) as? [String: Any]
        let intent = stateObject?["pairMutationIntent"] as? [String: Any]
        check(intent?["phase"] as? String == expectedStoredPhase[point],
              "the durable journal remains at the phase before \(point)")

        _ = try await engine(for: fixture).sync()
        check(data(bankFilePath(0), under: fixture.cloud) == winningEven
                && data(bankFilePath(1), under: fixture.cloud) == winningOdd,
              "restart normalizes the exact one-step-ahead \(point) state")
    }
}

private func stateWriteFailuresAreRecoverableAtEveryJournalPhase() async throws {
    print("state-write failures preserve a recoverable pair transaction at every phase")
    let targets: [String?] = ["prepared", "committed", "oddRemoved", "evenReplaced",
                              "oddWritten", nil]
    for target in targets {
        let fixture = try Fixture()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try writeBank(progress: 40, saveCount: 4, marker: 41,
                      to: bankFilePath(0), under: fixture.local, modificationDate: date)
        try writeBank(progress: 30, saveCount: 3, marker: 42,
                      to: bankFilePath(1), under: fixture.local, modificationDate: date)
        _ = try await fixture.engine.sync()
        try writeBank(progress: 80, saveCount: 6, marker: 43,
                      to: bankFilePath(0), under: fixture.local,
                      modificationDate: date.addingTimeInterval(60))
        try writeBank(progress: 70, saveCount: 5, marker: 44,
                      to: bankFilePath(1), under: fixture.local,
                      modificationDate: date.addingTimeInterval(60))
        let winningEven = data(bankFilePath(0), under: fixture.local)
        let winningOdd = data(bankFilePath(1), under: fixture.local)
        let fault = StateWriteFault(target: target)
        var interrupted = false
        do {
            _ = try await engine(for: fixture, beforeStateWrite: { try fault($0) }).sync()
        } catch InjectedFailure.stateWrite {
            interrupted = true
        } catch {}
        check(interrupted, "state write fault is injected for \(target ?? "final clear")")

        _ = try await engine(for: fixture).sync()
        check(data(bankFilePath(0), under: fixture.cloud) == winningEven
                && data(bankFilePath(1), under: fixture.cloud) == winningOdd,
              "restart recovers after the \(target ?? "final clear") state write fault")
        let finalState = try JSONSerialization.jsonObject(
            with: Data(contentsOf: fixture.state)) as? [String: Any]
        check(finalState?["pairMutationIntent"] == nil,
              "recovery clears the journal after \(target ?? "final clear")")
    }
}

private func preparedDriftCancelsAndPreparedImportDoesNotBlock() async throws {
    print("prepared intents cancel on drift and an uncommitted import never blocks relaunch")
    let fixture = try Fixture()
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    try writeBank(progress: 40, saveCount: 4, marker: 51,
                  to: bankFilePath(0), under: fixture.local, modificationDate: date)
    try writeBank(progress: 30, saveCount: 3, marker: 52,
                  to: bankFilePath(1), under: fixture.local, modificationDate: date)
    _ = try await fixture.engine.sync()
    try writeBank(progress: 80, saveCount: 6, marker: 53,
                  to: bankFilePath(0), under: fixture.local,
                  modificationDate: date.addingTimeInterval(60))
    try writeBank(progress: 70, saveCount: 5, marker: 54,
                  to: bankFilePath(1), under: fixture.local,
                  modificationDate: date.addingTimeInterval(60))
    let targetRace = CloudReplacementRace(cloudRoot: fixture.cloud)
    var rejected = false
    do {
        _ = try await engine(for: fixture,
                             afterPairIntentPrepared: { try targetRace.mutate() }).sync()
    } catch {
        rejected = true
    }
    check(rejected, "target drift after prepared persistence cancels the stale intent")
    let canceledState = try JSONSerialization.jsonObject(
        with: Data(contentsOf: fixture.state)) as? [String: Any]
    check(canceledState?["pairMutationIntent"] == nil,
          "prepared target drift is cleared durably before the error returns")
    _ = try await engine(for: fixture).sync()
    check(loaderSelectedCompletion(evenIndex: 0, under: fixture.local) == 96,
          "the next merge freshly ranks the target generation that caused prepared drift")

    let importFixture = try Fixture()
    let slot = importFixture.root.appending(
        path: "prepared-import/OpenGOAL/jak1/saves/\(memcardDirectory)",
        directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
    let imported = jak1Bank(progress: 65, saveCount: 5, marker: 55)
    try imported.write(to: slot.appending(path: "bank0.bin"), options: .atomic)
    let preparedFault = OneShotPreparedFault()
    do {
        _ = try await engine(for: importFixture,
                             afterPairIntentPrepared: { try preparedFault.fire() })
            .importSaves(from: slot)
    } catch {}
    let preparedState = try JSONSerialization.jsonObject(
        with: Data(contentsOf: importFixture.state)) as? [String: Any]
    let preparedIntent = preparedState?["pairMutationIntent"] as? [String: Any]
    check(preparedIntent?["phase"] as? String == "prepared",
          "import persists prepared intent before any canonical mutation")
    let importedResult = try await engine(for: importFixture).importSaves(from: slot)
    check(importedResult.fileCount == 1
            && data(bankFilePath(0), under: importFixture.local) == imported,
          "relaunch clears the uncommitted import and performs a fresh import")
}

private func targetContentionBetweenPhasesIsRejected() async throws {
    print("every pair mutation phase compare-and-swaps the exact target identity")
    let fixture = try Fixture()
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    try writeBank(progress: 40, saveCount: 4, marker: 61,
                  to: bankFilePath(0), under: fixture.local, modificationDate: date)
    try writeBank(progress: 30, saveCount: 3, marker: 62,
                  to: bankFilePath(1), under: fixture.local, modificationDate: date)
    _ = try await fixture.engine.sync()
    try writeBank(progress: 80, saveCount: 6, marker: 63,
                  to: bankFilePath(0), under: fixture.local,
                  modificationDate: date.addingTimeInterval(60))
    try writeBank(progress: 70, saveCount: 5, marker: 64,
                  to: bankFilePath(1), under: fixture.local,
                  modificationDate: date.addingTimeInterval(60))
    let external = jak1Bank(progress: 99, saveCount: 10, marker: 65)
    let race = MutationFault(target: .removedOdd)
    var rejected = false
    do {
        _ = try await engine(for: fixture, mutationHook: { point in
            do { try race(point) } catch InjectedFailure.mutation(.removedOdd) {
                try writeBank(progress: 99, saveCount: 10, marker: 65,
                              to: bankFilePath(0), under: fixture.cloud,
                              modificationDate: date.addingTimeInterval(120))
            }
        }).sync()
    } catch {
        rejected = true
    }
    check(rejected, "the next phase rejects a target changed after odd removal")
    check(data(bankFilePath(0), under: fixture.cloud) == external,
          "phase contention preserves the external target generation")
}

private func committedSourceChangeRemainsNextGeneration() async throws {
    print("a source change after journal commit remains a later generation")
    let fixture = try Fixture()
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    try writeBank(progress: 40, saveCount: 4, marker: 1,
                  to: bankFilePath(0), under: fixture.local, modificationDate: date)
    try writeBank(progress: 30, saveCount: 3, marker: 2,
                  to: bankFilePath(1), under: fixture.local, modificationDate: date)
    _ = try await fixture.engine.sync()

    try writeBank(progress: 80, saveCount: 6, marker: 3,
                  to: bankFilePath(0), under: fixture.local,
                  modificationDate: date.addingTimeInterval(60))
    try writeBank(progress: 70, saveCount: 5, marker: 4,
                  to: bankFilePath(1), under: fixture.local,
                  modificationDate: date.addingTimeInterval(60))
    let nextGeneration = CloudReplacementRace(cloudRoot: fixture.local)
    let interruptedEngine = engine(
        for: fixture, afterPairIntentCommitted: { try nextGeneration.mutate() })

    var rejected = false
    do {
        _ = try await interruptedEngine.sync()
    } catch {
        rejected = true
    }
    check(rejected, "post-commit source CAS stops before canonical mutation")
    check(loaderSelectedCompletion(evenIndex: 0, under: fixture.local) == 96,
          "the post-commit local generation remains intact")
    check(loaderSelectedCompletion(evenIndex: 0, under: fixture.cloud) == 40,
          "the target remains at its original baseline after the rejected write")
    let committedState = try JSONSerialization.jsonObject(
        with: Data(contentsOf: fixture.state)) as? [String: Any]
    let committedIntent = committedState?["pairMutationIntent"] as? [String: Any]
    check(committedIntent?["phase"] as? String == "committed",
          "the committed journal remains durable for exact recovery")

    let recovery = try await engine(for: fixture).sync()
    check(recovery.resolutions.isEmpty,
          "baseline-directed recovery does not invent an automatic resolution")
    check(recovery.uploaded == 4,
          "one sync accounts for journal recovery and the preserved next generation")
    check(loaderSelectedCompletion(evenIndex: 0, under: fixture.cloud) == 96,
          "the same pregame sync reconciles the post-commit next generation")
    check(loaderSelectedCompletion(evenIndex: 0, under: fixture.local) == 96,
          "recovery never rolls back the newer source generation")

    let next = try await engine(for: fixture).sync()
    check(next.uploaded == 0 && next.resolutions.isEmpty,
          "the recovered resolution is not surfaced again on the next merge")
    let finalState = try JSONSerialization.jsonObject(
        with: Data(contentsOf: fixture.state)) as? [String: Any]
    check(finalState?["pairMutationIntent"] == nil,
          "exact target verification clears the journal with its baseline")

    let cloudFixture = try Fixture()
    try writeBank(progress: 40, saveCount: 4, marker: 11,
                  to: bankFilePath(0), under: cloudFixture.local, modificationDate: date)
    try writeBank(progress: 30, saveCount: 3, marker: 12,
                  to: bankFilePath(1), under: cloudFixture.local, modificationDate: date)
    _ = try await cloudFixture.engine.sync()
    try writeBank(progress: 80, saveCount: 6, marker: 13,
                  to: bankFilePath(0), under: cloudFixture.cloud,
                  modificationDate: date.addingTimeInterval(60))
    try writeBank(progress: 70, saveCount: 5, marker: 14,
                  to: bankFilePath(1), under: cloudFixture.cloud,
                  modificationDate: date.addingTimeInterval(60))
    let cloudNextGeneration = CloudReplacementRace(cloudRoot: cloudFixture.cloud)
    do {
        _ = try await engine(
            for: cloudFixture,
            afterPairIntentCommitted: { try cloudNextGeneration.mutate() }).sync()
    } catch {}
    let unsafeBeforeRecovery = try await engine(for: cloudFixture)
        .hasUnsafePendingLocalMutation()
    check(unsafeBeforeRecovery,
          "a committed cloud-to-local journal is exposed as unsafe for gameplay")
    let cloudRecovery = try await engine(for: cloudFixture).sync()
    check(cloudRecovery.downloaded == 4
            && loaderSelectedCompletion(evenIndex: 0, under: cloudFixture.local) == 96,
          "one pregame sync recovers then downloads the cloud source's next generation")
    let unsafeAfterRecovery = try await engine(for: cloudFixture)
        .hasUnsafePendingLocalMutation()
    check(!unsafeAfterRecovery,
          "successful local recovery clears the gameplay barrier")
}

private func legitimateOneBankDivergenceIsSurfaced() async throws {
    print("a naturally added odd bank is ranked instead of inferred as recovery")
    let fixture = try Fixture()
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    try writeBank(progress: 40, saveCount: 4, marker: 1,
                  to: bankFilePath(0), under: fixture.local, modificationDate: date)
    _ = try await fixture.engine.sync()
    try writeBank(progress: 70, saveCount: 5, marker: 2,
                  to: bankFilePath(1), under: fixture.cloud,
                  modificationDate: date.addingTimeInterval(60))

    let outcome = try await fixture.engine.sync()
    check(outcome.resolutions == [SaveResolution(relativePath: bankFilePath(0),
                                                  winner: .iCloud,
                                                  basis: .completionPercentage(70))],
          "missing-odd divergence is explicitly ranked and surfaced")
    check(loaderSelectedCompletion(evenIndex: 0, under: fixture.local) == 70,
          "the ranked full pair becomes the local loader generation")
}

private func unavailableRecoveryHonorsTargetDirectionAndMode() async throws {
    print("embedded recovery works offline only for a paused local target")
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let localTargetFixture = try Fixture()
    try writeBank(progress: 40, saveCount: 4, marker: 1,
                  to: bankFilePath(0), under: localTargetFixture.local,
                  modificationDate: date)
    try writeBank(progress: 30, saveCount: 3, marker: 2,
                  to: bankFilePath(1), under: localTargetFixture.local,
                  modificationDate: date)
    _ = try await localTargetFixture.engine.sync()
    try writeBank(progress: 80, saveCount: 6, marker: 3,
                  to: bankFilePath(0), under: localTargetFixture.cloud,
                  modificationDate: date.addingTimeInterval(60))
    try writeBank(progress: 70, saveCount: 5, marker: 4,
                  to: bankFilePath(1), under: localTargetFixture.cloud,
                  modificationDate: date.addingTimeInterval(60))
    let winningEven = data(bankFilePath(0), under: localTargetFixture.cloud)
    let winningOdd = data(bankFilePath(1), under: localTargetFixture.cloud)
    let localFault = MutationFault(target: .replacedEven)
    do {
        _ = try await engine(for: localTargetFixture,
                             mutationHook: { try localFault($0) }).sync()
    } catch {}

    let unavailable = engine(for: localTargetFixture, cloudAvailable: false)
    let uploadOnly = try await unavailable.sync(mode: .uploadOnly)
    check(uploadOnly.downloaded == 0
            && data(bankFilePath(1), under: localTargetFixture.local) == nil,
          "upload-only offline sync never recovers into local gameplay storage")
    let recovered = try await unavailable.sync(mode: .bidirectional)
    check(recovered.availability == .unavailable,
          "offline recovery still reports the provider as unavailable")
    check(data(bankFilePath(0), under: localTargetFixture.local) == winningEven
            && data(bankFilePath(1), under: localTargetFixture.local) == winningOdd,
          "paused offline sync completes the embedded local-target generation")

    let cloudTargetFixture = try Fixture()
    try writeBank(progress: 40, saveCount: 4, marker: 5,
                  to: bankFilePath(0), under: cloudTargetFixture.local,
                  modificationDate: date)
    try writeBank(progress: 30, saveCount: 3, marker: 6,
                  to: bankFilePath(1), under: cloudTargetFixture.local,
                  modificationDate: date)
    _ = try await cloudTargetFixture.engine.sync()
    try writeBank(progress: 80, saveCount: 6, marker: 7,
                  to: bankFilePath(0), under: cloudTargetFixture.local,
                  modificationDate: date.addingTimeInterval(60))
    try writeBank(progress: 70, saveCount: 5, marker: 8,
                  to: bankFilePath(1), under: cloudTargetFixture.local,
                  modificationDate: date.addingTimeInterval(60))
    let activeLocalEven = data(bankFilePath(0), under: cloudTargetFixture.local)
    let activeLocalOdd = data(bankFilePath(1), under: cloudTargetFixture.local)
    let cloudFault = MutationFault(target: .replacedEven)
    do {
        _ = try await engine(for: cloudTargetFixture,
                             mutationHook: { try cloudFault($0) }).sync()
    } catch {}
    _ = try await engine(for: cloudTargetFixture, cloudAvailable: false).sync()
    check(data(bankFilePath(0), under: cloudTargetFixture.local) == activeLocalEven
            && data(bankFilePath(1), under: cloudTargetFixture.local) == activeLocalOdd,
          "offline sync abandons only the cloud-target intent without touching local saves")
    let stillPendingState = try JSONSerialization.jsonObject(
        with: Data(contentsOf: cloudTargetFixture.state)) as? [String: Any]
    check(stillPendingState?["pairMutationIntent"] == nil,
          "the unavailable provider durably clears the safe cloud-target journal")
    _ = try await engine(for: cloudTargetFixture,
                         accountIdentifier: "account-b").sync()
    check(data(bankFilePath(0), under: cloudTargetFixture.local) == activeLocalEven
            && data(bankFilePath(1), under: cloudTargetFixture.local) == activeLocalOdd,
          "a new account ranks from the intact local canonical source")
    let accountMismatchState = try Data(contentsOf: cloudTargetFixture.state)
    let accountMismatchObject = try JSONSerialization.jsonObject(
        with: accountMismatchState) as? [String: Any]
    check(accountMismatchObject?["pairMutationIntent"] == nil,
          "the new account cannot inherit the abandoned account's mutation journal")
}

private func pendingLocalIntentBlocksEveryOtherSlot() async throws {
    print("a pending local-target journal is a barrier for every other save slot")
    let fixture = try Fixture()
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    for evenIndex in [0, 2] {
        try writeBank(progress: 30, saveCount: 3, marker: UInt8(70 + evenIndex),
                      to: bankFilePath(evenIndex), under: fixture.local,
                      modificationDate: date)
        try writeBank(progress: 20, saveCount: 2, marker: UInt8(71 + evenIndex),
                      to: bankFilePath(evenIndex + 1), under: fixture.local,
                      modificationDate: date)
    }
    _ = try await fixture.engine.sync()
    try writeBank(progress: 90, saveCount: 8, marker: 75,
                  to: bankFilePath(0), under: fixture.cloud,
                  modificationDate: date.addingTimeInterval(120))
    try writeBank(progress: 80, saveCount: 7, marker: 76,
                  to: bankFilePath(1), under: fixture.cloud,
                  modificationDate: date.addingTimeInterval(120))
    let slotTwoCloudBefore = data(bankFilePath(2), under: fixture.cloud)
    try writeBank(progress: 70, saveCount: 6, marker: 77,
                  to: bankFilePath(2), under: fixture.local,
                  modificationDate: date.addingTimeInterval(60))
    try writeBank(progress: 60, saveCount: 5, marker: 78,
                  to: bankFilePath(3), under: fixture.local,
                  modificationDate: date.addingTimeInterval(60))
    let fault = MutationFault(target: .replacedEven)
    do {
        _ = try await engine(for: fixture, mutationHook: { try fault($0) }).sync()
    } catch {}

    let blocked = try await engine(for: fixture).sync(mode: .uploadOnly)
    check(blocked.uploaded == 0 && blocked.downloaded == 0,
          "upload-only returns immediately rather than mutating a pending local target")
    check(data(bankFilePath(2), under: fixture.cloud) == slotTwoCloudBefore,
          "the later slot is not processed while one global journal is pending")
    let stateObject = try JSONSerialization.jsonObject(
        with: Data(contentsOf: fixture.state)) as? [String: Any]
    let intent = stateObject?["pairMutationIntent"] as? [String: Any]
    check(intent?["evenPath"] as? String == bankFilePath(0),
          "no later slot can overwrite the first durable journal")
}

private func interruptedResolutionSurfacesExactlyOnce() async throws {
    print("an interrupted automatic resolution is journaled and surfaced exactly once")
    let fixture = try Fixture()
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    try writeBank(progress: 80, saveCount: 6, marker: 81,
                  to: bankFilePath(0), under: fixture.local, modificationDate: date)
    try writeBank(progress: 70, saveCount: 5, marker: 82,
                  to: bankFilePath(1), under: fixture.local, modificationDate: date)
    try writeBank(progress: 40, saveCount: 4, marker: 83,
                  to: bankFilePath(0), under: fixture.cloud, modificationDate: date)
    try writeBank(progress: 30, saveCount: 3, marker: 84,
                  to: bankFilePath(1), under: fixture.cloud, modificationDate: date)
    let fault = MutationFault(target: .replacedEven)
    do {
        _ = try await engine(for: fixture, mutationHook: { try fault($0) }).sync()
    } catch {}
    let stateObject = try JSONSerialization.jsonObject(
        with: Data(contentsOf: fixture.state)) as? [String: Any]
    let intent = stateObject?["pairMutationIntent"] as? [String: Any]
    check(intent?["resolution"] != nil,
          "the exact automatic resolution survives interruption in the journal")

    let expected = SaveResolution(relativePath: bankFilePath(0), winner: .local,
                                  basis: .completionPercentage(80))
    let recovery = try await engine(for: fixture).sync()
    check(recovery.resolutions == [expected],
          "successful recovery surfaces the journaled resolution")
    let next = try await engine(for: fixture).sync()
    check(next.resolutions.isEmpty,
          "the resolution is cleared atomically and cannot surface twice")
}

private func localJournalFinishesBeforeAccountReset() async throws {
    print("an old-account local-target journal finishes before new-account baselines reset")
    let fixture = try Fixture()
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    try writeBank(progress: 40, saveCount: 4, marker: 91,
                  to: bankFilePath(0), under: fixture.local, modificationDate: date)
    try writeBank(progress: 30, saveCount: 3, marker: 92,
                  to: bankFilePath(1), under: fixture.local, modificationDate: date)
    _ = try await fixture.engine.sync()
    try writeBank(progress: 80, saveCount: 6, marker: 93,
                  to: bankFilePath(0), under: fixture.cloud,
                  modificationDate: date.addingTimeInterval(60))
    try writeBank(progress: 70, saveCount: 5, marker: 94,
                  to: bankFilePath(1), under: fixture.cloud,
                  modificationDate: date.addingTimeInterval(60))
    let fault = MutationFault(target: .replacedEven)
    do {
        _ = try await engine(for: fixture, mutationHook: { try fault($0) }).sync()
    } catch {}

    _ = try await engine(for: fixture, accountIdentifier: "account-b").sync()
    check(loaderSelectedCompletion(evenIndex: 0, under: fixture.local) == 80,
          "account switch completes the embedded old-account generation locally")
    let stateObject = try JSONSerialization.jsonObject(
        with: Data(contentsOf: fixture.state)) as? [String: Any]
    check(stateObject?["pairMutationIntent"] == nil,
          "the old-account local journal clears before syncing the new account")
    let accountData = stateObject?["cloudAccountIdentifier"] as? String
    check(accountData == Data("account-b".utf8).base64EncodedString(),
          "the resulting baselines belong only to the new account")
}

private func malformedEmbeddedPairIsRejectedBeforeMutation() async throws {
    print("decoded pair journals validate embedded bank sizes and hashes before mutation")
    let fixture = try Fixture()
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    try writeBank(progress: 40, saveCount: 4, marker: 101,
                  to: bankFilePath(0), under: fixture.local, modificationDate: date)
    try writeBank(progress: 30, saveCount: 3, marker: 102,
                  to: bankFilePath(1), under: fixture.local, modificationDate: date)
    _ = try await fixture.engine.sync()
    try writeBank(progress: 80, saveCount: 6, marker: 103,
                  to: bankFilePath(0), under: fixture.cloud,
                  modificationDate: date.addingTimeInterval(60))
    try writeBank(progress: 70, saveCount: 5, marker: 104,
                  to: bankFilePath(1), under: fixture.cloud,
                  modificationDate: date.addingTimeInterval(60))
    let preparedFault = OneShotPreparedFault()
    do {
        _ = try await engine(for: fixture,
                             afterPairIntentCommitted: { try preparedFault.fire() }).sync()
    } catch {}
    let localEvenBefore = data(bankFilePath(0), under: fixture.local)
    let localOddBefore = data(bankFilePath(1), under: fixture.local)
    var stateObject = try JSONSerialization.jsonObject(
        with: Data(contentsOf: fixture.state)) as! [String: Any]
    var intent = stateObject["pairMutationIntent"] as! [String: Any]
    var sourceEven = intent["sourceEven"] as! [String: Any]
    sourceEven["data"] = Data([1, 2, 3]).base64EncodedString()
    intent["sourceEven"] = sourceEven
    stateObject["pairMutationIntent"] = intent
    try JSONSerialization.data(withJSONObject: stateObject, options: [.sortedKeys])
        .write(to: fixture.state, options: .atomic)

    var rejected = false
    do {
        _ = try await engine(for: fixture, cloudAvailable: false).sync()
    } catch {
        rejected = true
    }
    check(rejected, "a malformed embedded member is rejected during journal decode validation")
    check(data(bankFilePath(0), under: fixture.local) == localEvenBefore
            && data(bankFilePath(1), under: fixture.local) == localOddBefore,
          "malformed journal data cannot mutate either canonical local bank")
}

private func operationsAreFIFOExclusiveAcrossAwaitPoints() async throws {
    print("top-level save operations remain FIFO-exclusive across actor await points")
    let gate = OperationGate()
    let fixture = try Fixture(operationAwaitHook: { await gate.pauseFirstEntry() })
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    try writeBank(progress: 40, saveCount: 4, marker: 111,
                  to: bankFilePath(0), under: fixture.local, modificationDate: date)
    let first = Task { try await fixture.engine.sync() }
    await gate.waitUntilEntered()
    let exportRoot = fixture.root.appending(path: "exclusive-export",
                                            directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: exportRoot,
                                            withIntermediateDirectories: true)
    let second = Task { try await fixture.engine.exportSaves(to: exportRoot) }
    try await Task.sleep(for: .milliseconds(20))
    let entriesWhileBlocked = await gate.entries()
    check(entriesWhileBlocked == 1,
          "a second operation cannot cross its await hook while the first owns the lease")
    await gate.release()
    _ = try await first.value
    _ = try await second.value
    let finalEntries = await gate.entries()
    check(finalEntries == 2,
          "the queued operation enters only after the first releases the FIFO lease")
}

private func archiveFailureLeavesCanonicalPairsUntouched() async throws {
    print("archive failure stops before either canonical pair is mutated")
    let fault = MutationFault(target: .archived)
    let fixture = try Fixture(mutationHook: { try fault($0) })
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    try writeBank(progress: 80, saveCount: 6, marker: 1,
                  to: bankFilePath(0), under: fixture.local, modificationDate: date)
    try writeBank(progress: 70, saveCount: 5, marker: 2,
                  to: bankFilePath(1), under: fixture.local, modificationDate: date)
    try writeBank(progress: 60, saveCount: 6, marker: 3,
                  to: bankFilePath(0), under: fixture.cloud, modificationDate: date)
    try writeBank(progress: 50, saveCount: 5, marker: 4,
                  to: bankFilePath(1), under: fixture.cloud, modificationDate: date)
    let localEven = data(bankFilePath(0), under: fixture.local)
    let localOdd = data(bankFilePath(1), under: fixture.local)
    let cloudEven = data(bankFilePath(0), under: fixture.cloud)
    let cloudOdd = data(bankFilePath(1), under: fixture.cloud)

    var rejected = false
    do {
        _ = try await fixture.engine.sync()
    } catch InjectedFailure.mutation(.archived) {
        rejected = true
    } catch {}
    check(rejected, "the injected archive failure reaches the caller")
    check(data(bankFilePath(0), under: fixture.local) == localEven
            && data(bankFilePath(1), under: fixture.local) == localOdd,
          "archive failure preserves both local canonical members")
    check(data(bankFilePath(0), under: fixture.cloud) == cloudEven
            && data(bankFilePath(1), under: fixture.cloud) == cloudOdd,
          "archive failure preserves both cloud canonical members")
}

private struct LegacySyncState: Encodable {
    let baselineHashes: [String: String]
    let conflicts: [String: String] = [:]
    let cloudAccountIdentifier: Data?
}

private func hash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func legacyPerBankBaselineMigratesToPairIdentity() async throws {
    print("legacy per-bank baselines migrate without inventing a conflict")
    let fixture = try Fixture()
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let oldEven = jak1Bank(progress: 40, saveCount: 4, marker: 1)
    let oldOdd = jak1Bank(progress: 30, saveCount: 3, marker: 2)
    for root in [fixture.local, fixture.cloud] {
        let evenURL = file(bankFilePath(0), under: root)
        let oddURL = file(bankFilePath(1), under: root)
        try FileManager.default.createDirectory(at: evenURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try oldEven.write(to: evenURL, options: .atomic)
        try oldOdd.write(to: oddURL, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: date],
                                              ofItemAtPath: evenURL.path)
        try FileManager.default.setAttributes([.modificationDate: date],
                                              ofItemAtPath: oddURL.path)
    }
    let legacy = LegacySyncState(
        baselineHashes: [bankFilePath(0): hash(oldEven), bankFilePath(1): hash(oldOdd)],
        cloudAccountIdentifier: Data("account-a".utf8))
    try FileManager.default.createDirectory(at: fixture.state.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try JSONEncoder().encode(legacy).write(to: fixture.state, options: .atomic)

    try writeBank(progress: 80, saveCount: 6, marker: 3,
                  to: bankFilePath(0), under: fixture.local,
                  modificationDate: date.addingTimeInterval(60))
    try writeBank(progress: 70, saveCount: 5, marker: 4,
                  to: bankFilePath(1), under: fixture.local,
                  modificationDate: date.addingTimeInterval(60))
    let newEven = data(bankFilePath(0), under: fixture.local)
    let newOdd = data(bankFilePath(1), under: fixture.local)

    let outcome = try await fixture.engine.sync()
    check(outcome.resolutions.isEmpty, "the unchanged legacy cloud pair is recognized as baseline")
    check(data(bankFilePath(0), under: fixture.cloud) == newEven
            && data(bankFilePath(1), under: fixture.cloud) == newOdd,
          "the changed local pair uploads atomically against the legacy baseline")
    let stateObject = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.state))
        as? [String: Any]
    let pairBaselines = stateObject?["slotBaselineHashes"] as? [String: String]
    check(pairBaselines?[bankFilePath(0)] != nil,
          "the next successful sync persists the pair-level baseline")
}

private func desktopLayoutImportsAndExportsWithoutReformatting() async throws {
    print("manual import and export preserve the desktop OpenGOAL layout")
    let fixture = try Fixture()
    let selectedImportRoot = fixture.root.appending(path: "selected-import",
                                                     directoryHint: .isDirectory)
    let desktopSaves = selectedImportRoot.appending(path: "OpenGOAL/jak1/saves",
                                                     directoryHint: .isDirectory)
    let bank = jak1Bank(progress: 63, saveCount: 4, marker: 9)
    let bankURL = file(bankPath, under: desktopSaves)
    try FileManager.default.createDirectory(at: bankURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try bank.write(to: bankURL)
    let staleOddBank = jak1Bank(progress: 12, saveCount: 3, marker: 4)
    let staleOddURL = file(bankFilePath(1), under: fixture.local)
    try FileManager.default.createDirectory(at: staleOddURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try staleOddBank.write(to: staleOddURL)

    let imported = try await fixture.engine.importSaves(from: desktopSaves)
    check(imported.fileCount == 1, "one raw bank imports")
    check(data(under: fixture.local) == bank, "import keeps the raw memcard bytes and path")
    check(data(bankFilePath(1), under: fixture.local) == nil,
          "import preserves the selected pair's missing odd member")
    check(regularFiles(under: fixture.localConflicts).contains {
        (try? Data(contentsOf: $0)) == staleOddBank
    }, "the replaced odd member remains recoverable")

    let selectedExportRoot = fixture.root.appending(path: "selected-export",
                                                     directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: selectedExportRoot,
                                            withIntermediateDirectories: true)
    let exported = try await fixture.engine.exportSaves(to: selectedExportRoot)
    check(exported.fileCount == 1, "one raw bank exports")
    check(exported.destination.flatMap { data(under: $0) } == bank,
          "export produces OpenGOAL/jak1/saves/BASCUS-.../bank0.bin unchanged")
}

private func manualImportRejectsCorruptBankFolders() async throws {
    print("manual import rejects folders without a valid Jak 1 bank")
    let fixture = try Fixture()
    let selectedImportRoot = fixture.root.appending(path: "corrupt-import/OpenGOAL/jak1/saves",
                                                     directoryHint: .isDirectory)
    var corruptBank = jak1Bank(progress: 99, saveCount: 2, marker: 7)
    corruptBank[0x500] ^= 1
    let bankURL = file(bankPath, under: selectedImportRoot)
    try FileManager.default.createDirectory(at: bankURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try corruptBank.write(to: bankURL)

    var rejected = false
    do {
        _ = try await fixture.engine.importSaves(from: selectedImportRoot)
    } catch {
        rejected = true
    }
    check(rejected, "the corrupt-only folder is rejected")
    check(!FileManager.default.fileExists(atPath: fixture.local.path),
          "rejected import does not populate the gameplay save root")
}

private func manualImportRejectsLoneOddBank() async throws {
    print("manual import rejects a valid odd bank without its required even peer")
    let fixture = try Fixture()
    let selectedImportRoot = fixture.root.appending(path: "odd-only-import/OpenGOAL/jak1/saves",
                                                     directoryHint: .isDirectory)
    let oddURL = file(bankFilePath(1), under: selectedImportRoot)
    try FileManager.default.createDirectory(at: oddURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try jak1Bank(progress: 88, saveCount: 5, marker: 8).write(to: oddURL)

    var rejected = false
    do {
        _ = try await fixture.engine.importSaves(from: selectedImportRoot)
    } catch {
        rejected = true
    }
    check(rejected, "the runtime-unloadable odd-only folder is rejected")
    check(!FileManager.default.fileExists(atPath: fixture.local.path),
          "the lone odd bank never enters the gameplay save root")
}

private func exactSlotDirectoryImports() async throws {
    print("manual import accepts the exact Jak 1 slot directory")
    let fixture = try Fixture()
    let slot = fixture.root.appending(path: "exact-slot/\(memcardDirectory)",
                                      directoryHint: .isDirectory)
    let bank = jak1Bank(progress: 48, saveCount: 4, marker: 5)
    try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
    try bank.write(to: slot.appending(path: "bank0.bin"), options: .atomic)

    let result = try await fixture.engine.importSaves(from: slot)
    check(result.fileCount == 1, "the direct slot selection imports one bank")
    check(data(under: fixture.local) == bank,
          "the direct slot maps to the exact desktop-compatible relative path")
}

private func interruptedManualImportRecoversFromJournal() async throws {
    print("manual import uses the same durable pair mutation journal")
    let fault = MutationFault(target: .replacedEven)
    let fixture = try Fixture(mutationHook: { try fault($0) })
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    try writeBank(progress: 30, saveCount: 4, marker: 1,
                  to: bankFilePath(0), under: fixture.local, modificationDate: date)
    try writeBank(progress: 20, saveCount: 3, marker: 2,
                  to: bankFilePath(1), under: fixture.local, modificationDate: date)
    let slot = fixture.root.appending(path: "interrupted-import/\(memcardDirectory)",
                                      directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
    let importedEven = jak1Bank(progress: 80, saveCount: 6, marker: 3)
    let importedOdd = jak1Bank(progress: 70, saveCount: 5, marker: 4)
    try importedEven.write(to: slot.appending(path: "bank0.bin"), options: .atomic)
    try importedOdd.write(to: slot.appending(path: "bank1.bin"), options: .atomic)

    var interrupted = false
    do {
        _ = try await fixture.engine.importSaves(from: slot)
    } catch InjectedFailure.mutation(.replacedEven) {
        interrupted = true
    } catch {}
    check(interrupted, "the import interruption is observed after its journaled even write")
    check(data(bankFilePath(1), under: fixture.local) == nil,
          "the interrupted import remains at the safe missing-odd phase")

    _ = try await engine(for: fixture, cloudAvailable: false).sync(mode: .bidirectional)
    check(data(bankFilePath(0), under: fixture.local) == importedEven
            && data(bankFilePath(1), under: fixture.local) == importedOdd,
          "offline recovery finishes the embedded imported pair")
    let finalState = try JSONSerialization.jsonObject(
        with: Data(contentsOf: fixture.state)) as? [String: Any]
    check(finalState?["pairMutationIntent"] == nil,
          "successful import recovery clears its durable intent")
}

private func broadAndNestedImportsAreRejected() async throws {
    print("manual import rejects broad roots and recursively nested save layouts")
    let broadFixture = try Fixture()
    let broad = broadFixture.root.appending(path: "broad-selection", directoryHint: .isDirectory)
    let nestedRoot = broad.appending(path: "OpenGOAL/jak1/saves", directoryHint: .isDirectory)
    let broadBank = file(bankPath, under: nestedRoot)
    try FileManager.default.createDirectory(at: broadBank.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try jak1Bank(progress: 20, saveCount: 2, marker: 1).write(to: broadBank)
    var broadRejected = false
    do {
        _ = try await broadFixture.engine.importSaves(from: broad)
    } catch {
        broadRejected = true
    }
    check(broadRejected, "a parent containing a nested saves tree is too broad")
    check(!FileManager.default.fileExists(atPath: broadFixture.local.path),
          "broad selection cannot copy an unrelated recursive file")

    let nestedFixture = try Fixture()
    let exactRoot = nestedFixture.root.appending(
        path: "nested-selection/OpenGOAL/jak1/saves", directoryHint: .isDirectory)
    let nestedSlot = exactRoot.appending(path: memcardDirectory, directoryHint: .isDirectory)
    let directBank = nestedSlot.appending(path: "bank0.bin", directoryHint: .notDirectory)
    let recursiveBank = nestedSlot.appending(path: "backup/bank1.bin", directoryHint: .notDirectory)
    try FileManager.default.createDirectory(at: directBank.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: recursiveBank.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try jak1Bank(progress: 30, saveCount: 2, marker: 2).write(to: directBank)
    try jak1Bank(progress: 25, saveCount: 1, marker: 3).write(to: recursiveBank)
    var nestedRejected = false
    do {
        _ = try await nestedFixture.engine.importSaves(from: exactRoot)
    } catch {
        nestedRejected = true
    }
    check(nestedRejected, "banks nested below the one allowed slot level are rejected")
    check(!FileManager.default.fileExists(atPath: nestedFixture.local.path),
          "nested rejection happens before loading or copying banks")

    let nestedSavesFixture = try Fixture()
    let outerSaves = nestedSavesFixture.root.appending(
        path: "nested-saves/OpenGOAL/jak1/saves", directoryHint: .isDirectory)
    let innerBank = outerSaves.appending(
        path: "saves/\(memcardDirectory)/bank0.bin", directoryHint: .notDirectory)
    try FileManager.default.createDirectory(at: innerBank.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try jak1Bank(progress: 35, saveCount: 2, marker: 4).write(to: innerBank)
    var nestedSavesRejected = false
    do {
        _ = try await nestedSavesFixture.engine.importSaves(from: outerSaves)
    } catch {
        nestedSavesRejected = true
    }
    check(nestedSavesRejected, "an extra nested saves directory is never searched recursively")
}

private func importCountAndByteBoundsAreEnforced() async throws {
    print("manual import bounds file count, per-file bytes, and aggregate bytes")
    let countFixture = try Fixture()
    let countRoot = countFixture.root.appending(
        path: "count-bound/OpenGOAL/jak1/saves/\(memcardDirectory)",
        directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: countRoot, withIntermediateDirectories: true)
    for index in 0..<8 {
        try jak1Bank(progress: Float(index), saveCount: UInt32(index + 1),
                     marker: UInt8(index)).write(
            to: countRoot.appending(path: "bank\(index).bin"), options: .atomic)
    }
    try Data(repeating: 0, count: 0x10800).write(
        to: countRoot.appending(path: "ninth.bin"), options: .atomic)
    var countRejected = false
    do {
        _ = try await countFixture.engine.importSaves(from: countRoot)
    } catch {
        countRejected = true
    }
    check(countRejected, "more than eight direct files are rejected before loading")

    let sizeFixture = try Fixture()
    let sizeRoot = sizeFixture.root.appending(
        path: "size-bound/OpenGOAL/jak1/saves/\(memcardDirectory)",
        directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: sizeRoot, withIntermediateDirectories: true)
    try Data(repeating: 0, count: 0x10801).write(
        to: sizeRoot.appending(path: "bank0.bin"), options: .atomic)
    var sizeRejected = false
    do {
        _ = try await sizeFixture.engine.importSaves(from: sizeRoot)
    } catch {
        sizeRejected = true
    }
    check(sizeRejected, "a bank exceeding the exact raw-bank byte bound is rejected")

    let changingFixture = try Fixture(fileSettleDelay: .milliseconds(50))
    let changingRoot = changingFixture.root.appending(
        path: "changing-size/OpenGOAL/jak1/saves/\(memcardDirectory)",
        directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: changingRoot,
                                            withIntermediateDirectories: true)
    let changingBank = changingRoot.appending(path: "bank0.bin", directoryHint: .notDirectory)
    try jak1Bank(progress: 50, saveCount: 4, marker: 7)
        .write(to: changingBank, options: .atomic)
    let writer = Task {
        try await Task.sleep(for: .milliseconds(10))
        try Data(repeating: 0, count: 0x10801).write(to: changingBank, options: .atomic)
    }
    var changingSizeRejected = false
    do {
        _ = try await changingFixture.engine.importSaves(from: changingRoot)
    } catch {
        changingSizeRejected = true
    }
    try await writer.value
    check(changingSizeRejected,
          "a bank replaced with a larger file after preflight is bounded and rejected")
    check(!FileManager.default.fileExists(atPath: changingFixture.local.path),
          "the post-preflight size race cannot populate gameplay storage")

    let aggregateFixture = try Fixture()
    let aggregateRoot = aggregateFixture.root.appending(
        path: "aggregate-bound/OpenGOAL/jak1/saves/\(memcardDirectory)",
        directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: aggregateRoot,
                                            withIntermediateDirectories: true)
    for index in 0..<8 {
        try jak1Bank(progress: Float(index * 10), saveCount: UInt32(index + 1),
                     marker: UInt8(index + 10)).write(
            to: aggregateRoot.appending(path: "bank\(index).bin"), options: .atomic)
    }
    let aggregateResult = try await aggregateFixture.engine.importSaves(from: aggregateRoot)
    check(aggregateResult.fileCount == 8,
          "eight exact-size banks at the aggregate limit are accepted")
}

@main
private struct SaveSyncCheck {
    static func main() async {
        do {
            try await unavailableKeepsLocalSaves()
            try await localOnlyUploadsDesktopLayout()
            try await cloudOnlyDownloadsBeforeGameplay()
            try await changedSideWinsAgainstBaseline()
            try await initialDivergenceUsesNewestDateAndPreservesBoth()
            try await twoSidedChangeAutomaticallyResolves()
            try await completionPercentageBeatsModificationDate()
            try await equalProgressFallsBackToNewestDate()
            try await validBankBeatsNewerCorruptBank()
            try await pairedBanksResolveAsOneSlot()
            try await pairResolutionRemovesLoserOnlyPeerAfterArchiving()
            try await loaderSaveCountTieSelectsOddBank()
            try await equalDatesKeepLocalAuthorityWithoutHashOrdering()
            try await missingSideIsRestored()
            try await accountSwitchCannotReuseAnOldBaseline()
            try await changingFileIsReadAgainBeforeUpload()
            try await newerSaveDuringCloudWorkGetsANextSync()
            try await uploadOnlyKeepsActiveLocalAuthority()
            try await cloudToLocalCASPreservesConcurrentLocalWrite()
            try await localToCloudCASPreservesConcurrentCloudWrite()
            try await pairSourceCASRejectsRacesInBothDirections()
            try await ordinarySourceCASRejectsRacesInBothDirections()
            try await interruptedPairMutationRecoversWithoutHybrid()
            try await mutationCrashWindowsRecoverFromExactNextPhase()
            try await stateWriteFailuresAreRecoverableAtEveryJournalPhase()
            try await preparedDriftCancelsAndPreparedImportDoesNotBlock()
            try await targetContentionBetweenPhasesIsRejected()
            try await committedSourceChangeRemainsNextGeneration()
            try await legitimateOneBankDivergenceIsSurfaced()
            try await unavailableRecoveryHonorsTargetDirectionAndMode()
            try await pendingLocalIntentBlocksEveryOtherSlot()
            try await interruptedResolutionSurfacesExactlyOnce()
            try await localJournalFinishesBeforeAccountReset()
            try await malformedEmbeddedPairIsRejectedBeforeMutation()
            try await operationsAreFIFOExclusiveAcrossAwaitPoints()
            try await archiveFailureLeavesCanonicalPairsUntouched()
            try await legacyPerBankBaselineMigratesToPairIdentity()
            try await desktopLayoutImportsAndExportsWithoutReformatting()
            try await manualImportRejectsCorruptBankFolders()
            try await manualImportRejectsLoneOddBank()
            try await exactSlotDirectoryImports()
            try await interruptedManualImportRecoversFromJournal()
            try await broadAndNestedImportsAreRejected()
            try await importCountAndByteBoundsAreEnforced()
        } catch {
            print("  FAIL unexpected error: \(error)")
            failures += 1
        }

        if failures == 0 {
            print("save sync checks passed")
        } else {
            print("save sync checks failed: \(failures)")
            Foundation.exit(1)
        }
    }
}
