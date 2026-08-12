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
    forceZIP64Marker: Bool = false,
    comment: Data = Data()
) throws -> Data {
    guard comment.count <= Int(UInt16.max) else { throw FixtureError.compression }
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
    archive.appendLE16(UInt16(comment.count))
    archive.append(comment)
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

    var temporaryZIPs: [URL] {
        ((try? FileManager.default.contentsOfDirectory(
            at: candidate.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )) ?? []).filter { $0.lastPathComponent.hasSuffix(".source.zip") }
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
    Set(GameDataManifest.bootArchives + GameDataManifest.levelArchives).count
        + GameDataManifest.levelGeometry.count
}

private func writeCompleteCandidate(at root: URL, payload: Data) throws {
    let iso = root.appending(path: GameDataLayout.isoDirectoryName, directoryHint: .isDirectory)
    let fr3 = root.appending(path: GameDataLayout.fr3DirectoryName, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: iso, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: fr3, withIntermediateDirectories: true)
    for name in Set(GameDataManifest.bootArchives + GameDataManifest.levelArchives) {
        try payload.write(to: iso.appending(path: name), options: .atomic)
    }
    for name in GameDataManifest.levelGeometry {
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

@MainActor private func maximumZIPCommentExtracts() async throws {
    print("maximum ZIP32 comment remains a valid archive tail")
    let fixture = try Fixture()
    let contents = Data("synthetic commented ISO".utf8)
    let comment = Data(repeating: 0x63, count: Int(UInt16.max))
    try fixture.writeArchive(try makeArchive(
        [ArchiveEntry(name: "game.iso", contents: contents)],
        comment: comment
    ))
    var limits = ZIPISOExtractor.Limits()
    limits.minimumFreeSpaceAfterExtraction = 0
    try await ZIPISOExtractor(limits: limits).extractISO(
        from: fixture.archive,
        to: fixture.output
    ) { _ in }
    let extracted = try Data(contentsOf: fixture.output)
    check(extracted == contents,
          "the full 65,535-byte ZIP comment is scanned without losing the EOCD")
}

@MainActor private func coordinatedProviderSnapshotAndShortReadsExtract() async throws {
    print("Files-provider snapshot and short reads preserve a complete ZIP")
    let fixture = try Fixture()
    let contents = Data((0..<(96 * 1_024)).map { UInt8(truncatingIfNeeded: $0) })
    let completeArchive = fixture.root.appending(path: "materialized.zip")
    try makeArchive([
        ArchiveEntry(name: "disc/game.iso", contents: contents, method: 8),
    ]).write(to: completeArchive)

    // Model a selected provider placeholder whose visible prefix has no EOCD. Coordination gives
    // the extractor the materialized snapshot instead of that incomplete selected-file view.
    try Data(repeating: 0x50, count: 128).write(to: fixture.archive)
    var limits = ZIPISOExtractor.Limits()
    limits.chunkBytes = 4 * 1_024
    limits.minimumFreeSpaceAfterExtraction = 0
    do {
        try await ZIPISOExtractor(
            limits: limits,
            materializeArchive: { source, destination in
                try FileManager.default.copyItem(at: source, to: destination)
            },
            openArchive: { url in try FileHandle(forReadingFrom: url) }
        ).extractISO(from: fixture.archive, to: fixture.output) { _ in }
        check(false, "an unmaterialized provider placeholder cannot appear complete")
    } catch let failure as GameDataImportFailure {
        check(failure.message.contains("ZIP end-of-directory record is missing"),
              "the incomplete provider view reproduces the reported EOCD failure")
    }
    let extractor = ZIPISOExtractor(
        limits: limits,
        materializeArchive: { _, destination in
            try FileManager.default.copyItem(at: completeArchive, to: destination)
        },
        readArchive: { handle, count in
            try handle.read(upToCount: min(count, 7))
        }
    )
    try await extractor.extractISO(from: fixture.archive, to: fixture.output) { _ in }
    let extracted = try Data(contentsOf: fixture.output)
    check(extracted == contents,
          "the coordinated materialized snapshot tolerates provider-style short reads")
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
        check(fixture.temporaryZIPs.isEmpty,
              "materialized ZIP is removed after downstream success or failure")
    }
}

@MainActor private func staleOwnedCleanupIsBounded() throws {
    print("stale ZIP staging cleanup is bounded and preserves ambiguous siblings")
    let fixture = try Fixture()
    let directory = fixture.candidate.deletingLastPathComponent()
    let ownedNames = [
        "00000000-0000-4000-8000-000000000000.source.zip",
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
    check(!FileManager.default.fileExists(
        atPath: directory.appending(path: ownedNames[0]).path
    ), "cleanup recognizes app-owned materialized ZIP staging")
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
    let fixture = try Fixture()
    try fixture.writeArchive(try makeArchive(
        entries,
        diskNumber: diskNumber,
        forceZIP64Marker: forceZIP64Marker
    ))
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
        "ZIP64 archive",
        entries: [ArchiveEntry(name: "game.iso", contents: bytes)],
        expectedCode: .unsupportedArchive,
        messageContains: "ZIP64",
        forceZIP64Marker: true
    )
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
            try await exactOutputBufferBoundaryExtracts()
            try await maximumZIPCommentExtracts()
            try await coordinatedProviderSnapshotAndShortReadsExtract()
            try await producerUsesSiblingAndCleansUp()
            try staleOwnedCleanupIsBounded()
            try await cancellationRemovesPartialOutput()
            try await deflateFinalChunkCancellationRemovesOutput()
            try await unsafeAndUnsupportedArchivesFailClosed()
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
