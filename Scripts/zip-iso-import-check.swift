// Synthetic checks for the local streaming ZIP-to-ISO import boundary.
// No retail game data is read or written.

import Foundation
import zlib

@MainActor private var failures = 0

@MainActor private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("  ok   \(message)")
    } else {
        print("  FAIL \(message)")
        failures += 1
    }
}

private enum FixtureError: Error {
    case compression
}

private struct ArchiveEntry {
    let name: String
    let contents: Data
    var method: UInt16 = 0
    var flags: UInt16 = 0
    var checksumOverride: UInt32?
    var declaredSizeOverride: UInt32?
    var localMethodOverride: UInt16?
}

private struct CentralZIP64Fields: OptionSet {
    let rawValue: UInt8

    static let uncompressedSize = Self(rawValue: 1 << 0)
    static let compressedSize = Self(rawValue: 1 << 1)
    static let localHeaderOffset = Self(rawValue: 1 << 2)
    static let diskStart = Self(rawValue: 1 << 3)
    static let all: Self = [
        .uncompressedSize,
        .compressedSize,
        .localHeaderOffset,
        .diskStart,
    ]
}

private struct ZIP64ArchiveEntry {
    let entry: ArchiveEntry
    var centralFields: CentralZIP64Fields = .all
    var localZIP64Sizes = true
    var diskStartValue: UInt32 = 0
    var centralExtraOverride: Data?
    var localExtraOverride: Data?
}

private struct ZIP64EndSentinels: OptionSet {
    let rawValue: UInt8

    static let diskNumber = Self(rawValue: 1 << 0)
    static let directoryDisk = Self(rawValue: 1 << 1)
    static let entriesOnDisk = Self(rawValue: 1 << 2)
    static let totalEntries = Self(rawValue: 1 << 3)
    static let directorySize = Self(rawValue: 1 << 4)
    static let directoryOffset = Self(rawValue: 1 << 5)
}

private struct ZIP64EndOptions {
    var legacySentinels: ZIP64EndSentinels = [.directoryOffset]
    var locatorDisk: UInt32 = 0
    var locatorRecordOffsetOverride: UInt64?
    var totalDisks: UInt32 = 1
    var recordSizeOverride: UInt64?
    var diskNumber: UInt32 = 0
    var directoryDisk: UInt32 = 0
    var entriesOnDiskOverride: UInt64?
    var totalEntriesOverride: UInt64?
    var directorySizeOverride: UInt64?
    var directoryOffsetOverride: UInt64?
}

private extension Data {
    mutating func appendLE16(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func appendLE32(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 24))
    }

    mutating func appendLE64(_ value: UInt64) {
        appendLE32(UInt32(truncatingIfNeeded: value))
        appendLE32(UInt32(truncatingIfNeeded: value >> 32))
    }
}

private func checksum(_ data: Data) -> UInt32 {
    let value = data.withUnsafeBytes { bytes in
        crc32(0, bytes.bindMemory(to: Bytef.self).baseAddress, uInt(data.count))
    }
    return UInt32(truncatingIfNeeded: value)
}

private func rawDeflate(_ data: Data) throws -> Data {
    var stream = z_stream()
    let status = deflateInit2_(
        &stream,
        Z_DEFAULT_COMPRESSION,
        Z_DEFLATED,
        -MAX_WBITS,
        8,
        Z_DEFAULT_STRATEGY,
        ZLIB_VERSION,
        Int32(MemoryLayout<z_stream>.size)
    )
    guard status == Z_OK else { throw FixtureError.compression }
    defer { deflateEnd(&stream) }

    var result = Data()
    try data.withUnsafeBytes { input in
        stream.next_in = UnsafeMutablePointer<Bytef>(
            mutating: input.bindMemory(to: Bytef.self).baseAddress
        )
        stream.avail_in = uInt(data.count)
        var finished = false
        while !finished {
            var output = [UInt8](repeating: 0, count: 16 * 1_024)
            let capacity = output.count
            let step = output.withUnsafeMutableBytes { bytes -> Int32 in
                stream.next_out = bytes.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(capacity)
                return deflate(&stream, Z_FINISH)
            }
            guard step == Z_OK || step == Z_STREAM_END else {
                throw FixtureError.compression
            }
            result.append(contentsOf: output.prefix(capacity - Int(stream.avail_out)))
            finished = step == Z_STREAM_END
        }
    }
    return result
}

private func makeArchive(
    _ entries: [ArchiveEntry],
    diskNumber: UInt16 = 0,
    forceZIP64Marker: Bool = false
) throws -> Data {
    struct DirectoryRecord {
        let entry: ArchiveEntry
        let name: Data
        let payload: Data
        let checksum: UInt32
        let declaredSize: UInt32
        let localOffset: UInt32
    }

    var archive = Data()
    var records: [DirectoryRecord] = []
    for entry in entries {
        let name = Data(entry.name.utf8)
        let payload = entry.method == 8 ? try rawDeflate(entry.contents) : entry.contents
        let crc = entry.checksumOverride ?? checksum(entry.contents)
        let declaredSize = entry.declaredSizeOverride ?? UInt32(entry.contents.count)
        let localOffset = UInt32(archive.count)

        archive.appendLE32(0x0403_4b50)
        archive.appendLE16(20)
        archive.appendLE16(entry.flags)
        archive.appendLE16(entry.localMethodOverride ?? entry.method)
        archive.appendLE16(0)
        archive.appendLE16(0)
        let usesDescriptor = entry.flags & 0x0008 != 0
        archive.appendLE32(usesDescriptor ? 0 : crc)
        archive.appendLE32(usesDescriptor ? 0 : UInt32(payload.count))
        archive.appendLE32(usesDescriptor ? 0 : declaredSize)
        archive.appendLE16(UInt16(name.count))
        archive.appendLE16(0)
        archive.append(name)
        archive.append(payload)
        if usesDescriptor {
            archive.appendLE32(0x0807_4b50)
            archive.appendLE32(crc)
            archive.appendLE32(UInt32(payload.count))
            archive.appendLE32(declaredSize)
        }

        records.append(DirectoryRecord(
            entry: entry,
            name: name,
            payload: payload,
            checksum: crc,
            declaredSize: declaredSize,
            localOffset: localOffset
        ))
    }

    let directoryOffset = UInt32(archive.count)
    for record in records {
        archive.appendLE32(0x0201_4b50)
        archive.appendLE16(20)
        archive.appendLE16(20)
        archive.appendLE16(record.entry.flags)
        archive.appendLE16(record.entry.method)
        archive.appendLE16(0)
        archive.appendLE16(0)
        archive.appendLE32(record.checksum)
        archive.appendLE32(UInt32(record.payload.count))
        archive.appendLE32(record.declaredSize)
        archive.appendLE16(UInt16(record.name.count))
        archive.appendLE16(0)
        archive.appendLE16(0)
        archive.appendLE16(0)
        archive.appendLE16(0)
        archive.appendLE32(0)
        archive.appendLE32(record.localOffset)
        archive.append(record.name)
    }
    let directorySize = UInt32(archive.count) - directoryOffset

    archive.appendLE32(0x0605_4b50)
    archive.appendLE16(diskNumber)
    archive.appendLE16(diskNumber)
    let count = forceZIP64Marker ? UInt16.max : UInt16(records.count)
    archive.appendLE16(count)
    archive.appendLE16(count)
    archive.appendLE32(directorySize)
    archive.appendLE32(directoryOffset)
    archive.appendLE16(0)
    return archive
}

private func zip64Extra(_ payload: Data) -> Data {
    var extra = Data()
    extra.appendLE16(0x0001)
    extra.appendLE16(UInt16(payload.count))
    extra.append(payload)
    return extra
}

private func makeZIP64Archive(
    _ entries: [ZIP64ArchiveEntry],
    end: ZIP64EndOptions = ZIP64EndOptions()
) throws -> Data {
    struct DirectoryRecord {
        let fixture: ZIP64ArchiveEntry
        let name: Data
        let payload: Data
        let checksum: UInt32
        let uncompressedSize: UInt64
        let localOffset: UInt64
    }

    var archive = Data()
    var records: [DirectoryRecord] = []
    for fixture in entries {
        let entry = fixture.entry
        let name = Data(entry.name.utf8)
        let payload = entry.method == 8 ? try rawDeflate(entry.contents) : entry.contents
        let crc = entry.checksumOverride ?? checksum(entry.contents)
        let uncompressedSize = UInt64(entry.declaredSizeOverride ?? UInt32(entry.contents.count))
        let compressedSize = UInt64(payload.count)
        let localOffset = UInt64(archive.count)

        var localZIP64Payload = Data()
        localZIP64Payload.appendLE64(uncompressedSize)
        localZIP64Payload.appendLE64(compressedSize)
        let localExtra = fixture.localExtraOverride
            ?? (fixture.localZIP64Sizes ? zip64Extra(localZIP64Payload) : Data())

        archive.appendLE32(0x0403_4b50)
        archive.appendLE16(fixture.localZIP64Sizes || !localExtra.isEmpty ? 45 : 20)
        archive.appendLE16(entry.flags)
        archive.appendLE16(entry.localMethodOverride ?? entry.method)
        archive.appendLE16(0)
        archive.appendLE16(0)
        let usesDescriptor = entry.flags & 0x0008 != 0
        archive.appendLE32(usesDescriptor ? 0 : crc)
        if fixture.localZIP64Sizes {
            archive.appendLE32(UInt32.max)
            archive.appendLE32(UInt32.max)
        } else {
            archive.appendLE32(usesDescriptor ? 0 : UInt32(payload.count))
            archive.appendLE32(usesDescriptor ? 0 : UInt32(uncompressedSize))
        }
        archive.appendLE16(UInt16(name.count))
        archive.appendLE16(UInt16(localExtra.count))
        archive.append(name)
        archive.append(localExtra)
        archive.append(payload)
        if usesDescriptor {
            archive.appendLE32(0x0807_4b50)
            archive.appendLE32(crc)
            if fixture.localZIP64Sizes {
                archive.appendLE64(compressedSize)
                archive.appendLE64(uncompressedSize)
            } else {
                archive.appendLE32(UInt32(compressedSize))
                archive.appendLE32(UInt32(uncompressedSize))
            }
        }

        records.append(DirectoryRecord(
            fixture: fixture,
            name: name,
            payload: payload,
            checksum: crc,
            uncompressedSize: uncompressedSize,
            localOffset: localOffset
        ))
    }

    let directoryOffset = UInt64(archive.count)
    for record in records {
        let fields = record.fixture.centralFields
        var payload = Data()
        if fields.contains(.uncompressedSize) {
            payload.appendLE64(record.uncompressedSize)
        }
        if fields.contains(.compressedSize) {
            payload.appendLE64(UInt64(record.payload.count))
        }
        if fields.contains(.localHeaderOffset) {
            payload.appendLE64(record.localOffset)
        }
        if fields.contains(.diskStart) {
            payload.appendLE32(record.fixture.diskStartValue)
        }
        let centralExtra = record.fixture.centralExtraOverride
            ?? (fields.isEmpty ? Data() : zip64Extra(payload))

        archive.appendLE32(0x0201_4b50)
        archive.appendLE16(45)
        archive.appendLE16(fields.isEmpty && centralExtra.isEmpty ? 20 : 45)
        archive.appendLE16(record.fixture.entry.flags)
        archive.appendLE16(record.fixture.entry.method)
        archive.appendLE16(0)
        archive.appendLE16(0)
        archive.appendLE32(record.checksum)
        archive.appendLE32(fields.contains(.compressedSize)
            ? UInt32.max : UInt32(record.payload.count))
        archive.appendLE32(fields.contains(.uncompressedSize)
            ? UInt32.max : UInt32(record.uncompressedSize))
        archive.appendLE16(UInt16(record.name.count))
        archive.appendLE16(UInt16(centralExtra.count))
        archive.appendLE16(0)
        archive.appendLE16(fields.contains(.diskStart) ? UInt16.max : 0)
        archive.appendLE16(0)
        archive.appendLE32(0)
        archive.appendLE32(fields.contains(.localHeaderOffset)
            ? UInt32.max : UInt32(record.localOffset))
        archive.append(record.name)
        archive.append(centralExtra)
    }
    let directorySize = UInt64(archive.count) - directoryOffset
    let zip64RecordOffset = UInt64(archive.count)
    let entriesOnDisk = end.entriesOnDiskOverride ?? UInt64(records.count)
    let totalEntries = end.totalEntriesOverride ?? UInt64(records.count)
    let recordedDirectorySize = end.directorySizeOverride ?? directorySize
    let recordedDirectoryOffset = end.directoryOffsetOverride ?? directoryOffset

    archive.appendLE32(0x0606_4b50)
    archive.appendLE64(end.recordSizeOverride ?? 44)
    archive.appendLE16(45)
    archive.appendLE16(45)
    archive.appendLE32(end.diskNumber)
    archive.appendLE32(end.directoryDisk)
    archive.appendLE64(entriesOnDisk)
    archive.appendLE64(totalEntries)
    archive.appendLE64(recordedDirectorySize)
    archive.appendLE64(recordedDirectoryOffset)

    archive.appendLE32(0x0706_4b50)
    archive.appendLE32(end.locatorDisk)
    archive.appendLE64(end.locatorRecordOffsetOverride ?? zip64RecordOffset)
    archive.appendLE32(end.totalDisks)

    archive.appendLE32(0x0605_4b50)
    archive.appendLE16(end.legacySentinels.contains(.diskNumber) ? UInt16.max : 0)
    archive.appendLE16(end.legacySentinels.contains(.directoryDisk) ? UInt16.max : 0)
    archive.appendLE16(end.legacySentinels.contains(.entriesOnDisk)
        ? UInt16.max : UInt16(entriesOnDisk))
    archive.appendLE16(end.legacySentinels.contains(.totalEntries)
        ? UInt16.max : UInt16(totalEntries))
    archive.appendLE32(end.legacySentinels.contains(.directorySize)
        ? UInt32.max : UInt32(recordedDirectorySize))
    archive.appendLE32(end.legacySentinels.contains(.directoryOffset)
        ? UInt32.max : UInt32(recordedDirectoryOffset))
    archive.appendLE16(0)
    return archive
}

private final class Fixture: @unchecked Sendable {
    let root: URL
    let archive: URL
    let output: URL
    let candidate: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "goalpad-zip-iso-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        archive = root.appending(path: "source.zip")
        output = root.appending(path: "output.iso")
        candidate = root.appending(path: "Attempts/attempt.candidate", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: candidate.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func writeArchive(_ data: Data) throws {
        try data.write(to: archive)
    }

    var temporaryISOs: [URL] {
        ((try? FileManager.default.contentsOfDirectory(
            at: candidate.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )) ?? []).filter { $0.lastPathComponent.hasSuffix(".extracted.iso") }
    }
}

private actor DownstreamRecorder {
    private(set) var receivedContents: Data?
    private(set) var sourceWasCandidateSibling = false

    func record(source: URL, candidate: URL) throws {
        receivedContents = try Data(contentsOf: source)
        sourceWasCandidateSibling = source.deletingLastPathComponent()
            == candidate.deletingLastPathComponent()
            && !source.path.hasPrefix(candidate.path + "/")
    }

    func snapshot() -> (Data?, Bool) {
        (receivedContents, sourceWasCandidateSibling)
    }
}

private struct RecordingProducer: GameDataCandidateProducing {
    let recorder: DownstreamRecorder
    var fail = false

    func prepareCandidate(
        from source: URL,
        activeDirectory _: URL,
        candidateDirectory: URL,
        report _: @escaping @Sendable (GameDataImportProgress) async -> Void
    ) async throws -> GameDataImportResult {
        try await recorder.record(source: source, candidate: candidateDirectory)
        if fail {
            throw GameDataImportFailure(
                code: .preparationFailed,
                message: "synthetic downstream failure",
                candidatePreserved: false
            )
        }
        return GameDataImportResult(filesCopied: 7, filesSkipped: 0)
    }
}

private final class PipelineFixture: @unchecked Sendable {
    let root: URL
    let active: URL
    let staging: URL
    let worker: GameDataInstallWorker

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "goalpad-iso-pipeline-\(UUID().uuidString)",
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

    var attemptEntries: [URL] {
        let attempts = staging.appending(path: "Attempts", directoryHint: .isDirectory)
        return (try? FileManager.default.contentsOfDirectory(
            at: attempts,
            includingPropertiesForKeys: nil
        )) ?? []
    }
}

private actor ActivePayloadRecorder {
    private let active: URL
    private var values: [String: Data] = [:]

    init(active: URL) {
        self.active = active
    }

    func observe(_ progress: GameDataImportProgress) {
        guard progress.phase == .validatingCandidate || progress.phase == .activatingCandidate,
              let payload = try? Data(contentsOf: active.appending(path: "iso/GAME.CGO"))
        else { return }
        values[progress.phase.rawValue] = payload
    }

    func snapshot() -> [String: Data] {
        values
    }
}

/// Models the native composer's ownership contract without accepting a fake retail fingerprint:
/// it consumes one ISO file and writes a complete, fresh candidate directly.
private struct SyntheticComposerProducer: GameDataCandidateProducing {
    func prepareCandidate(
        from source: URL,
        activeDirectory _: URL,
        candidateDirectory: URL,
        report _: @escaping @Sendable (GameDataImportProgress) async -> Void
    ) async throws -> GameDataImportResult {
        let payload = try Data(contentsOf: source)
        try writeCompleteCandidate(at: candidateDirectory, payload: payload)
        return GameDataImportResult(filesCopied: preparedFileCount, filesSkipped: 0)
    }
}

private var preparedFileCount: Int {
    let manifest = GameDataProfile.jak1.manifest
    return Set(manifest.bootArchives + manifest.levelArchives).count
        + manifest.levelGeometry.count
}

private func writeCompleteCandidate(at root: URL, payload: Data) throws {
    let iso = root.appending(path: GameDataLayout.isoDirectoryName, directoryHint: .isDirectory)
    let fr3 = root.appending(path: GameDataLayout.fr3DirectoryName, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: iso, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: fr3, withIntermediateDirectories: true)
    let manifest = GameDataProfile.jak1.manifest
    for name in Set(manifest.bootArchives + manifest.levelArchives) {
        try payload.write(to: iso.appending(path: name), options: .atomic)
    }
    for name in manifest.levelGeometry {
        try payload.write(to: fr3.appending(path: name), options: .atomic)
    }
}

@MainActor private func verifyInstallPipeline(
    label: String,
    source: URL,
    expectedSource: GameDataImportSource,
    expectedPayload: Data,
    fixture: PipelineFixture,
    producer: any GameDataCandidateProducing
) async throws {
    print("\(label) reaches validation and atomic activation")
    let oldPayload = Data("previous active install".utf8)
    try writeCompleteCandidate(at: fixture.active, payload: oldPayload)
    let recorder = ActivePayloadRecorder(active: fixture.active)

    check(GameDataImportSource(url: source) == expectedSource,
          "\(label) selection chooses the expected import route")
    let result = try await fixture.worker.install(from: source, using: producer) { progress in
        await recorder.observe(progress)
    }

    let observed = await recorder.snapshot()
    check(observed[GameDataImportProgress.Phase.validatingCandidate.rawValue] == oldPayload,
          "\(label) leaves the prior install active during candidate validation")
    check(observed[GameDataImportProgress.Phase.activatingCandidate.rawValue] == oldPayload,
          "\(label) leaves the prior install active at the activation boundary")
    check(GameDataInspector.inspect(gameDirectory: fixture.active).status == .ready,
          "\(label) activates a manifest-complete candidate")
    let activePayload = try Data(contentsOf: fixture.active.appending(path: "iso/GAME.CGO"))
    check(activePayload == expectedPayload,
          "\(label) atomically switches to the newly composed bytes")
    check(result.filesCopied == preparedFileCount,
          "\(label) preserves the downstream composer summary")
    check(fixture.attemptEntries.isEmpty,
          "\(label) leaves neither a candidate nor a temporary ISO in staging")
}

@MainActor private func rawAndZippedSourcesReachAtomicActivation() async throws {
    let rawFixture = try PipelineFixture()
    let rawPayload = Data("synthetic raw ISO bytes".utf8)
    let rawSource = rawFixture.root.appending(path: "selected.ISO")
    try rawPayload.write(to: rawSource)
    try await verifyInstallPipeline(
        label: "raw ISO",
        source: rawSource,
        expectedSource: .rawISO,
        expectedPayload: rawPayload,
        fixture: rawFixture,
        producer: SyntheticComposerProducer()
    )

    let zipFixture = try PipelineFixture()
    let zippedPayload = Data("synthetic ZIP-contained ISO bytes".utf8)
    let zipSource = zipFixture.root.appending(path: "selected.ZIP")
    try makeArchive([
        ArchiveEntry(name: "disc/game.iso", contents: zippedPayload, method: 8),
    ]).write(to: zipSource)
    var limits = ZIPISOExtractor.Limits()
    limits.minimumFreeSpaceAfterExtraction = 0
    try await verifyInstallPipeline(
        label: "zipped ISO",
        source: zipSource,
        expectedSource: .zippedISO,
        expectedPayload: zippedPayload,
        fixture: zipFixture,
        producer: ZIPISOCandidateProducer(
            downstream: SyntheticComposerProducer(),
            extractor: ZIPISOExtractor(limits: limits)
        )
    )
}

@MainActor private func storedAndDeflatedMembersExtract() async throws {
    print("stored and raw-DEFLATE ISO members stream and verify")
    for (method, flags): (UInt16, UInt16) in [(0, 0), (8, 0), (8, 0x0008)] {
        let fixture = try Fixture()
        let contents = Data((0..<(192 * 1_024)).map { UInt8(truncatingIfNeeded: $0) })
        try fixture.writeArchive(try makeArchive([
            ArchiveEntry(
                name: "disc/game.iso",
                contents: contents,
                method: method,
                flags: flags
            ),
        ]))
        var limits = ZIPISOExtractor.Limits()
        limits.chunkBytes = 4 * 1_024
        limits.minimumFreeSpaceAfterExtraction = 0
        try await ZIPISOExtractor(limits: limits).extractISO(
            from: fixture.archive,
            to: fixture.output
        ) { _ in }

        let extracted = try Data(contentsOf: fixture.output)
        check(extracted == contents,
              "method \(method), flags \(flags) reproduces the complete ISO bytes")
    }
}

@MainActor private func zip64StoredAndDeflatedMembersExtract() async throws {
    print("ZIP64 stored and raw-DEFLATE ISO members stream and verify")
    for (method, flags): (UInt16, UInt16) in [(0, 0), (8, 0), (8, 0x0008)] {
        let fixture = try Fixture()
        let contents = Data((0..<(96 * 1_024)).map { UInt8(truncatingIfNeeded: $0) })
        try fixture.writeArchive(try makeZIP64Archive([
            ZIP64ArchiveEntry(entry: ArchiveEntry(
                name: "disc/game.iso",
                contents: contents,
                method: method,
                flags: flags
            )),
        ]))
        var limits = ZIPISOExtractor.Limits()
        limits.chunkBytes = 4 * 1_024
        limits.minimumFreeSpaceAfterExtraction = 0
        try await ZIPISOExtractor(limits: limits).extractISO(
            from: fixture.archive,
            to: fixture.output
        ) { _ in }

        let extracted = try Data(contentsOf: fixture.output)
        check(extracted == contents,
              "ZIP64 method \(method), flags \(flags) reproduces the complete ISO bytes")
    }
    do {
        let fixture = try Fixture()
        let contents = Data(repeating: 0x6a, count: 48 * 1_024)
        var entry = ZIP64ArchiveEntry(entry: ArchiveEntry(
            name: "game.iso",
            contents: contents,
            method: 8,
            flags: 0x0008
        ))
        entry.localZIP64Sizes = false
        try fixture.writeArchive(try makeZIP64Archive([entry]))
        var limits = ZIPISOExtractor.Limits()
        limits.minimumFreeSpaceAfterExtraction = 0
        try await ZIPISOExtractor(limits: limits).extractISO(
            from: fixture.archive,
            to: fixture.output
        ) { _ in }
        let extracted = try Data(contentsOf: fixture.output)
        check(extracted == contents,
              "a ZIP64 data descriptor can use zeroed local size fields")
    }
    check(ZIPISOExtractor.Limits().maximumISOBytes == 4_410_671_104,
          "the default ISO ceiling is exactly the supported Jak II image size")
}

@MainActor private func mixedZIP32AndZIP64RecordsExtract() async throws {
    print("mixed ZIP32 and ZIP64 metadata resolves only marked fields")
    let contents = Data("mixed ZIP metadata fixture".utf8)

    do {
        let fixture = try Fixture()
        var entry = ZIP64ArchiveEntry(
            entry: ArchiveEntry(name: "game.iso", contents: contents, method: 8)
        )
        entry.centralFields = [.uncompressedSize]
        try fixture.writeArchive(try makeZIP64Archive([entry]))
        var limits = ZIPISOExtractor.Limits()
        limits.minimumFreeSpaceAfterExtraction = 0
        try await ZIPISOExtractor(limits: limits).extractISO(
            from: fixture.archive,
            to: fixture.output
        ) { _ in }
        let extracted = try Data(contentsOf: fixture.output)
        check(extracted == contents,
              "a selective central ZIP64 field preserves ZIP32 compressed size and offset")
    }

    do {
        let fixture = try Fixture()
        var entry = ZIP64ArchiveEntry(
            entry: ArchiveEntry(name: "game.iso", contents: contents)
        )
        entry.centralFields = []
        entry.localZIP64Sizes = false
        var end = ZIP64EndOptions()
        end.legacySentinels = []
        try fixture.writeArchive(try makeZIP64Archive([entry], end: end))
        var limits = ZIPISOExtractor.Limits()
        limits.minimumFreeSpaceAfterExtraction = 0
        try await ZIPISOExtractor(limits: limits).extractISO(
            from: fixture.archive,
            to: fixture.output
        ) { _ in }
        let extracted = try Data(contentsOf: fixture.output)
        check(extracted == contents,
              "a ZIP64 container can retain an entirely ZIP32 ISO entry")
    }
}

@MainActor private func exactOutputBufferBoundaryExtracts() async throws {
    print("raw DEFLATE accepts an ISO exactly matching the output buffer")
    let fixture = try Fixture()
    let contents = Data((0..<(4 * 1_024)).map { UInt8(truncatingIfNeeded: $0) })
    try fixture.writeArchive(try makeArchive([
        ArchiveEntry(name: "game.iso", contents: contents, method: 8),
    ]))
    var limits = ZIPISOExtractor.Limits()
    limits.chunkBytes = contents.count
    limits.minimumFreeSpaceAfterExtraction = 0
    try await ZIPISOExtractor(limits: limits).extractISO(
        from: fixture.archive,
        to: fixture.output
    ) { _ in }
    let extracted = try Data(contentsOf: fixture.output)
    check(extracted == contents, "exact output-buffer boundary preserves every byte")
}

@MainActor private func producerUsesSiblingAndCleansUp() async throws {
    print("candidate producer reuses downstream ISO preparation and always cleans staging")
    let contents = Data("synthetic iso".utf8)
    for fail in [false, true] {
        let fixture = try Fixture()
        try fixture.writeArchive(try makeArchive([
            ArchiveEntry(name: "game.iso", contents: contents, method: 8),
        ]))
        let recorder = DownstreamRecorder()
        let producer = ZIPISOCandidateProducer(
            downstream: RecordingProducer(recorder: recorder, fail: fail),
            extractor: ZIPISOExtractor(limits: {
                var value = ZIPISOExtractor.Limits()
                value.minimumFreeSpaceAfterExtraction = 0
                return value
            }())
        )

        do {
            let result = try await producer.prepareCandidate(
                from: fixture.archive,
                activeDirectory: fixture.root.appending(path: "active"),
                candidateDirectory: fixture.candidate
            ) { _ in }
            check(!fail && result.filesCopied == 7, "successful downstream result is preserved")
        } catch let failure as GameDataImportFailure {
            check(fail && failure.message == "synthetic downstream failure",
                  "downstream failures remain typed and unchanged")
        }

        let snapshot = await recorder.snapshot()
        check(snapshot.0 == contents,
              "the existing raw-ISO boundary receives extracted bytes")
        check(snapshot.1,
              "temporary ISO is a sibling rather than candidate content")
        check(fixture.temporaryISOs.isEmpty,
              "temporary ISO is removed after downstream success or failure")
    }
}

@MainActor private func staleOwnedCleanupIsBounded() throws {
    print("stale ZIP staging cleanup is bounded and preserves ambiguous siblings")
    let fixture = try Fixture()
    let directory = fixture.candidate.deletingLastPathComponent()
    let ownedNames = [
        "11111111-1111-4111-8111-111111111111.extracted.iso",
        "22222222-2222-4222-8222-222222222222.extracted.iso",
        "33333333-3333-4333-8333-333333333333.extracted.iso",
    ]
    let ownedURLs = ownedNames.map { directory.appending(path: $0) }
    for url in ownedURLs {
        try Data("stale".utf8).write(to: url)
    }

    let unrelated = [
        directory.appending(path: "not-a-uuid.extracted.iso"),
        directory.appending(path: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.extracted.iso"),
        directory.appending(path: "keep.txt"),
    ]
    for url in unrelated {
        try Data("keep".utf8).write(to: url)
    }
    try FileManager.default.createDirectory(
        at: fixture.candidate,
        withIntermediateDirectories: true
    )
    let ownedLookingDirectory = directory.appending(
        path: "44444444-4444-4444-8444-444444444444.extracted.iso",
        directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(
        at: ownedLookingDirectory,
        withIntermediateDirectories: false
    )

    ZIPISOStagingCleaner(maximumRemovals: 2).removeStaleOwnedFiles(in: directory)

    let removedOwnedCount = ownedURLs.filter {
        !FileManager.default.fileExists(atPath: $0.path)
    }.count
    check(removedOwnedCount == 2, "cleanup removes at most its bounded app-owned limit")
    check(unrelated.allSatisfy { FileManager.default.fileExists(atPath: $0.path) },
          "ambiguous and unrelated files are preserved")
    check(FileManager.default.fileExists(atPath: fixture.candidate.path),
          "candidate directories are preserved")
    check(FileManager.default.fileExists(atPath: ownedLookingDirectory.path),
          "an owned-looking directory is preserved")
}

@MainActor private func cancellationRemovesPartialOutput() async throws {
    print("cancellation removes partially extracted ISO staging")
    let fixture = try Fixture()
    let contents = Data(repeating: 0x5a, count: 192 * 1_024)
    try fixture.writeArchive(try makeArchive([
        ArchiveEntry(name: "game.iso", contents: contents),
    ]))
    var limits = ZIPISOExtractor.Limits()
    limits.chunkBytes = 4 * 1_024
    limits.minimumFreeSpaceAfterExtraction = 0

    let operation = Task {
        try await ZIPISOExtractor(limits: limits).extractISO(
            from: fixture.archive,
            to: fixture.output
        ) { progress in
            if progress.bytesCopied >= 8 * 1_024 {
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
    }
    do {
        try await operation.value
        check(false, "cancelled extraction does not complete")
    } catch is CancellationError {
        check(true, "cancellation stays distinct")
    }
    check(!FileManager.default.fileExists(atPath: fixture.output.path),
          "cancelled extraction leaves no partial ISO")
}

@MainActor private func deflateFinalChunkCancellationRemovesOutput() async throws {
    print("raw DEFLATE cancellation at final progress cannot return success")
    let fixture = try Fixture()
    let contents = Data(repeating: 0, count: 256 * 1_024)
    try fixture.writeArchive(try makeArchive([
        ArchiveEntry(name: "game.iso", contents: contents, method: 8),
    ]))
    var limits = ZIPISOExtractor.Limits()
    limits.chunkBytes = 1 * 1_024
    limits.minimumFreeSpaceAfterExtraction = 0

    let operation = Task {
        try await ZIPISOExtractor(limits: limits).extractISO(
            from: fixture.archive,
            to: fixture.output
        ) { progress in
            if progress.phase == .preparingCandidate,
               progress.bytesTotal > 0,
               progress.bytesCopied == progress.bytesTotal
            {
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
    }
    do {
        try await operation.value
        check(false, "final-chunk DEFLATE cancellation does not complete")
    } catch is CancellationError {
        check(true, "final-chunk DEFLATE cancellation stays distinct")
    }
    check(!FileManager.default.fileExists(atPath: fixture.output.path),
          "final-chunk DEFLATE cancellation removes the completed temporary ISO")
}

@MainActor private func expectFailure(
    _ label: String,
    entries: [ArchiveEntry],
    expectedCode: GameDataImportFailure.Code,
    messageContains: String,
    diskNumber: UInt16 = 0,
    forceZIP64Marker: Bool = false,
    configure: (inout ZIPISOExtractor.Limits) -> Void = { _ in }
) async throws {
    try await expectArchiveFailure(
        label,
        archive: try makeArchive(
            entries,
            diskNumber: diskNumber,
            forceZIP64Marker: forceZIP64Marker
        ),
        expectedCode: expectedCode,
        messageContains: messageContains,
        configure: configure
    )
}

@MainActor private func expectArchiveFailure(
    _ label: String,
    archive archiveData: Data,
    expectedCode: GameDataImportFailure.Code,
    messageContains: String,
    configure: (inout ZIPISOExtractor.Limits) -> Void = { _ in }
) async throws {
    let fixture = try Fixture()
    try fixture.writeArchive(archiveData)
    var limits = ZIPISOExtractor.Limits()
    limits.minimumFreeSpaceAfterExtraction = 0
    configure(&limits)
    do {
        try await ZIPISOExtractor(limits: limits).extractISO(
            from: fixture.archive,
            to: fixture.output
        ) { _ in }
        check(false, label)
    } catch let failure as GameDataImportFailure {
        check(failure.code == expectedCode, "\(label) has typed failure \(expectedCode.rawValue)")
        check(failure.message.localizedCaseInsensitiveContains(messageContains),
              "\(label) explains \(messageContains)")
        check(!FileManager.default.fileExists(atPath: fixture.output.path),
              "\(label) leaves no partial ISO")
    }
}

@MainActor private func unsafeAndUnsupportedArchivesFailClosed() async throws {
    print("unsafe, ambiguous, and unsupported archives fail closed")
    let bytes = Data("fixture".utf8)
    try await expectFailure(
        "multiple ISO members",
        entries: [
            ArchiveEntry(name: "one.iso", contents: bytes),
            ArchiveEntry(name: "two.ISO", contents: bytes),
        ],
        expectedCode: .unsupportedArchive,
        messageContains: "more than one ISO"
    )
    try await expectFailure(
        "missing ISO member",
        entries: [ArchiveEntry(name: "readme.txt", contents: bytes)],
        expectedCode: .unsupportedArchive,
        messageContains: "does not contain an ISO"
    )
    try await expectFailure(
        "path traversal",
        entries: [
            ArchiveEntry(name: "../readme.txt", contents: bytes),
            ArchiveEntry(name: "game.iso", contents: bytes),
        ],
        expectedCode: .unsupportedArchive,
        messageContains: "unsafe member path"
    )
    try await expectFailure(
        "encrypted member",
        entries: [ArchiveEntry(name: "game.iso", contents: bytes, flags: 0x0001)],
        expectedCode: .unsupportedArchive,
        messageContains: "Encrypted"
    )
    try await expectFailure(
        "unsupported compression",
        entries: [ArchiveEntry(name: "game.iso", contents: bytes, method: 12)],
        expectedCode: .unsupportedArchive,
        messageContains: "compression method 12"
    )
    try await expectFailure(
        "local and central header disagreement",
        entries: [ArchiveEntry(
            name: "game.iso",
            contents: bytes,
            method: 0,
            localMethodOverride: 8
        )],
        expectedCode: .invalidDiscImage,
        messageContains: "headers disagree"
    )
    try await expectFailure(
        "multi-disk archive",
        entries: [ArchiveEntry(name: "game.iso", contents: bytes)],
        expectedCode: .unsupportedArchive,
        messageContains: "Multi-disk",
        diskNumber: 1
    )
    try await expectFailure(
        "ZIP64 sentinel without end records",
        entries: [ArchiveEntry(name: "game.iso", contents: bytes)],
        expectedCode: .invalidDiscImage,
        messageContains: "ZIP64",
        forceZIP64Marker: true
    )
}

@MainActor private func corruptZIP64MetadataFailsClosed() async throws {
    print("corrupt, overflowing, duplicate, and multi-disk ZIP64 metadata fails closed")
    let bytes = Data("ZIP64 fixture payload long enough to compress".utf8)
    let base = ArchiveEntry(name: "game.iso", contents: bytes)

    do {
        var entry = ZIP64ArchiveEntry(entry: base)
        entry.centralExtraOverride = Data()
        try await expectArchiveFailure(
            "missing central ZIP64 extra",
            archive: try makeZIP64Archive([entry]),
            expectedCode: .invalidDiscImage,
            messageContains: "missing its extra"
        )
    }

    do {
        var shortPayload = Data()
        shortPayload.appendLE64(UInt64(bytes.count))
        var entry = ZIP64ArchiveEntry(entry: base)
        entry.centralExtraOverride = zip64Extra(shortPayload)
        try await expectArchiveFailure(
            "missing central ZIP64 field",
            archive: try makeZIP64Archive([entry]),
            expectedCode: .invalidDiscImage,
            messageContains: "missing its compressed size"
        )
    }

    do {
        var malformedExtra = Data()
        malformedExtra.appendLE16(0x0001)
        malformedExtra.appendLE16(16)
        malformedExtra.appendLE64(UInt64(bytes.count))
        var entry = ZIP64ArchiveEntry(entry: base)
        entry.centralExtraOverride = malformedExtra
        try await expectArchiveFailure(
            "malformed central ZIP64 extra",
            archive: try makeZIP64Archive([entry]),
            expectedCode: .invalidDiscImage,
            messageContains: "extra field is truncated"
        )
    }

    do {
        var payload = Data()
        payload.appendLE64(UInt64(bytes.count))
        var entry = ZIP64ArchiveEntry(entry: base)
        entry.centralFields = []
        entry.localZIP64Sizes = false
        entry.centralExtraOverride = zip64Extra(payload)
        try await expectArchiveFailure(
            "unrequested central ZIP64 field",
            archive: try makeZIP64Archive([entry]),
            expectedCode: .invalidDiscImage,
            messageContains: "not requested"
        )
    }

    do {
        var payload = Data()
        payload.appendLE64(UInt64(bytes.count))
        payload.appendLE64(UInt64(bytes.count))
        payload.appendLE64(0)
        let extra = zip64Extra(payload)
        var entry = ZIP64ArchiveEntry(entry: base)
        entry.centralExtraOverride = extra + extra
        try await expectArchiveFailure(
            "duplicate central ZIP64 extra",
            archive: try makeZIP64Archive([entry]),
            expectedCode: .invalidDiscImage,
            messageContains: "duplicate ZIP64"
        )
    }

    do {
        var entry = ZIP64ArchiveEntry(entry: base)
        entry.localExtraOverride = Data()
        try await expectArchiveFailure(
            "missing local ZIP64 extra",
            archive: try makeZIP64Archive([entry]),
            expectedCode: .invalidDiscImage,
            messageContains: "missing its ZIP64"
        )
    }

    do {
        var payload = Data()
        payload.appendLE64(UInt64(bytes.count))
        payload.appendLE64(UInt64(bytes.count))
        var entry = ZIP64ArchiveEntry(entry: base)
        entry.localZIP64Sizes = false
        entry.localExtraOverride = zip64Extra(payload)
        try await expectArchiveFailure(
            "unrequested local ZIP64 sizes",
            archive: try makeZIP64Archive([entry]),
            expectedCode: .invalidDiscImage,
            messageContains: "not requested"
        )
    }

    do {
        var payload = Data()
        payload.appendLE64(UInt64(bytes.count))
        payload.appendLE64(UInt64(bytes.count))
        let extra = zip64Extra(payload)
        var entry = ZIP64ArchiveEntry(entry: base)
        entry.localExtraOverride = extra + extra
        try await expectArchiveFailure(
            "duplicate local ZIP64 extra",
            archive: try makeZIP64Archive([entry]),
            expectedCode: .invalidDiscImage,
            messageContains: "duplicate ZIP64"
        )
    }

    do {
        var payload = Data()
        payload.appendLE64(UInt64(bytes.count + 1))
        payload.appendLE64(UInt64(bytes.count))
        var entry = ZIP64ArchiveEntry(entry: base)
        entry.localExtraOverride = zip64Extra(payload)
        try await expectArchiveFailure(
            "mismatched local ZIP64 sizes",
            archive: try makeZIP64Archive([entry]),
            expectedCode: .invalidDiscImage,
            messageContains: "sizes or checksum disagree"
        )
    }

    do {
        let descriptorEntry = ArchiveEntry(
            name: "game.iso",
            contents: bytes,
            method: 8,
            flags: 0x0008
        )
        var payload = Data()
        payload.appendLE64(UInt64(bytes.count + 1))
        payload.appendLE64(UInt64(try rawDeflate(bytes).count))
        var entry = ZIP64ArchiveEntry(entry: descriptorEntry)
        entry.localExtraOverride = zip64Extra(payload)
        try await expectArchiveFailure(
            "mismatched descriptor local ZIP64 sizes",
            archive: try makeZIP64Archive([entry]),
            expectedCode: .invalidDiscImage,
            messageContains: "local ZIP64 sizes disagree"
        )
    }

    do {
        var entry = ZIP64ArchiveEntry(entry: base)
        entry.diskStartValue = 1
        try await expectArchiveFailure(
            "multi-disk ZIP64 entry",
            archive: try makeZIP64Archive([entry]),
            expectedCode: .unsupportedArchive,
            messageContains: "Multi-disk ZIP archives"
        )
    }

    do {
        var end = ZIP64EndOptions()
        end.locatorRecordOffsetOverride = UInt64.max
        try await expectArchiveFailure(
            "overflowing ZIP64 locator offset",
            archive: try makeZIP64Archive([ZIP64ArchiveEntry(entry: base)], end: end),
            expectedCode: .invalidDiscImage,
            messageContains: "invalid bounds"
        )
    }

    do {
        var end = ZIP64EndOptions()
        end.recordSizeOverride = UInt64.max
        try await expectArchiveFailure(
            "overflowing ZIP64 end-record size",
            archive: try makeZIP64Archive([ZIP64ArchiveEntry(entry: base)], end: end),
            expectedCode: .invalidDiscImage,
            messageContains: "invalid bounds"
        )
    }

    do {
        var end = ZIP64EndOptions()
        end.directoryOffsetOverride = UInt64.max
        end.directorySizeOverride = 1
        try await expectArchiveFailure(
            "overflowing ZIP64 directory bounds",
            archive: try makeZIP64Archive([ZIP64ArchiveEntry(entry: base)], end: end),
            expectedCode: .invalidDiscImage,
            messageContains: "central directory has invalid bounds"
        )
    }

    do {
        var end = ZIP64EndOptions()
        end.totalDisks = 2
        try await expectArchiveFailure(
            "multi-disk ZIP64 locator",
            archive: try makeZIP64Archive([ZIP64ArchiveEntry(entry: base)], end: end),
            expectedCode: .unsupportedArchive,
            messageContains: "Multi-disk ZIP64"
        )
    }

    do {
        var end = ZIP64EndOptions()
        end.legacySentinels = [.entriesOnDisk, .totalEntries, .directoryOffset]
        end.entriesOnDiskOverride = 2
        end.totalEntriesOverride = 2
        try await expectArchiveFailure(
            "unreasonable ZIP64 entry count",
            archive: try makeZIP64Archive([ZIP64ArchiveEntry(entry: base)], end: end),
            expectedCode: .unsupportedArchive,
            messageContains: "unreasonable number of entries"
        ) { limits in
            limits.maximumEntries = 1
        }
    }

    do {
        var end = ZIP64EndOptions()
        end.legacySentinels = [.directorySize, .directoryOffset]
        end.directorySizeOverride = 65 * 1_024 * 1_024
        try await expectArchiveFailure(
            "unreasonable ZIP64 directory size",
            archive: try makeZIP64Archive([ZIP64ArchiveEntry(entry: base)], end: end),
            expectedCode: .unsupportedArchive,
            messageContains: "directory is unreasonably large"
        )
    }
}

@MainActor private func corruptAndUnreasonableMembersFailClosed() async throws {
    print("corrupt or unreasonable ISO members fail before downstream preparation")
    let bytes = Data(repeating: 0, count: 64 * 1_024)
    try await expectFailure(
        "CRC mismatch",
        entries: [ArchiveEntry(
            name: "game.iso",
            contents: bytes,
            method: 8,
            checksumOverride: 0x1234_5678
        )],
        expectedCode: .invalidDiscImage,
        messageContains: "CRC-32"
    )
    try await expectFailure(
        "declared size mismatch",
        entries: [ArchiveEntry(
            name: "game.iso",
            contents: bytes,
            method: 8,
            declaredSizeOverride: UInt32(bytes.count - 1)
        )],
        expectedCode: .invalidDiscImage,
        messageContains: "declared size"
    )
    try await expectFailure(
        "excessive expansion ratio",
        entries: [ArchiveEntry(name: "game.iso", contents: bytes, method: 8)],
        expectedCode: .unsupportedArchive,
        messageContains: "unreasonable amount"
    ) { limits in
        limits.maximumCompressionRatio = 1
    }
    try await expectFailure(
        "oversized ISO",
        entries: [ArchiveEntry(name: "game.iso", contents: bytes)],
        expectedCode: .insufficientStorage,
        messageContains: "too large"
    ) { limits in
        limits.maximumISOBytes = UInt64(bytes.count - 1)
    }
    try await expectFailure(
        "oversized compressed member",
        entries: [ArchiveEntry(
            name: "game.iso",
            contents: bytes,
            declaredSizeOverride: UInt32(bytes.count - 1)
        )],
        expectedCode: .unsupportedArchive,
        messageContains: "member is unreasonably large"
    ) { limits in
        limits.maximumCompressionOverheadBytes = 0
        limits.maximumISOBytes = UInt64(bytes.count + 1)
    }
    try await expectFailure(
        "insufficient extraction space",
        entries: [ArchiveEntry(name: "game.iso", contents: bytes)],
        expectedCode: .insufficientStorage,
        messageContains: "free space"
    ) { limits in
        limits.minimumFreeSpaceAfterExtraction = UInt64.max
    }
}

@main
private struct ZIPISOImportCheck {
    @MainActor static func main() async {
        do {
            try await storedAndDeflatedMembersExtract()
            try await zip64StoredAndDeflatedMembersExtract()
            try await mixedZIP32AndZIP64RecordsExtract()
            try await exactOutputBufferBoundaryExtracts()
            try await producerUsesSiblingAndCleansUp()
            try staleOwnedCleanupIsBounded()
            try await cancellationRemovesPartialOutput()
            try await deflateFinalChunkCancellationRemovesOutput()
            try await unsafeAndUnsupportedArchivesFailClosed()
            try await corruptZIP64MetadataFailsClosed()
            try await corruptAndUnreasonableMembersFailClosed()
            try await rawAndZippedSourcesReachAtomicActivation()
        } catch {
            print("  FAIL unexpected error: \(error)")
            failures += 1
        }

        if failures == 0 {
            print("ZIP ISO import checks passed")
        } else {
            print("ZIP ISO import checks failed: \(failures)")
            Foundation.exit(1)
        }
    }
}
