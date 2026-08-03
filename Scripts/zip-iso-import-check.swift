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
            try await producerUsesSiblingAndCleansUp()
            try await cancellationRemovesPartialOutput()
            try await unsafeAndUnsupportedArchivesFailClosed()
            try await corruptAndUnreasonableMembersFailClosed()
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
