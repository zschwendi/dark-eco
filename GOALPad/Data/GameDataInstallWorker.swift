import Darwin
import Foundation
import OSLog
import zlib

nonisolated private let installLog = Logger(subsystem: "com.zephyrstudiosllc.eco",
                                            category: "GameDataInstall")

/// Progress shared by prepared-folder, raw-disc, and zipped-disc imports.
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

/// Streams one ordinary ZIP member to private staging before handing it to the raw-ISO producer.
/// The temporary image is a sibling of the candidate so it can never enter the activated install.
nonisolated struct ZIPISOCandidateProducer: GameDataCandidateProducing {
    private let downstream: any GameDataCandidateProducing
    private let extractor: ZIPISOExtractor

    init(
        downstream: any GameDataCandidateProducing,
        extractor: ZIPISOExtractor = ZIPISOExtractor()
    ) {
        self.downstream = downstream
        self.extractor = extractor
    }

    func prepareCandidate(
        from source: URL,
        activeDirectory: URL,
        candidateDirectory: URL,
        report: @escaping @Sendable (GameDataImportProgress) async -> Void
    ) async throws -> GameDataImportResult {
        let temporaryISO = candidateDirectory.deletingLastPathComponent().appending(
            path: "\(UUID().uuidString).extracted.iso"
        )
        defer { try? FileManager.default.removeItem(at: temporaryISO) }

        try await extractor.extractISO(
            from: source,
            to: temporaryISO,
            report: report
        )
        try Task.checkCancellation()
        return try await downstream.prepareCandidate(
            from: temporaryISO,
            activeDirectory: activeDirectory,
            candidateDirectory: candidateDirectory,
            report: report
        )
    }
}

/// Minimal ZIP32 reader for local, bounded ISO extraction. It intentionally rejects ZIP features
/// that are unnecessary for the supported import path instead of trying to repair or guess them.
nonisolated struct ZIPISOExtractor: Sendable {
    nonisolated struct Limits: Sendable {
        var maximumEntries = 100_000
        var maximumCentralDirectoryBytes: UInt64 = 64 * 1_024 * 1_024
        var maximumISOBytes: UInt64 = UInt64(UInt32.max)
        var maximumCompressionRatio: UInt64 = 1_000
        var minimumFreeSpaceAfterExtraction: UInt64 = 256 * 1_024 * 1_024
        var chunkBytes = 1 * 1_024 * 1_024
    }

    private struct EndOfCentralDirectory: Sendable {
        let entryCount: Int
        let centralDirectoryOffset: UInt64
        let recordOffset: UInt64
    }

    private struct Entry: Sendable {
        let name: String
        let nameBytes: Data
        let flags: UInt16
        let method: UInt16
        let checksum: UInt32
        let compressedSize: UInt64
        let uncompressedSize: UInt64
        let localHeaderOffset: UInt64
    }

    private struct OutputState {
        var checksum: uLong = crc32(0, nil, 0)
        var bytesWritten: UInt64 = 0
    }

    private let limits: Limits

    init(limits: Limits = Limits()) {
        self.limits = limits
    }

    func extractISO(
        from archiveURL: URL,
        to destinationURL: URL,
        report: @escaping @Sendable (GameDataImportProgress) async -> Void
    ) async throws {
        guard limits.chunkBytes > 0 else {
            throw Self.failure(.stagingFailed, "The ZIP extraction buffer is invalid.")
        }

        let archive: FileHandle
        do {
            archive = try FileHandle(forReadingFrom: archiveURL)
        } catch {
            throw Self.failure(
                .sourceUnavailable,
                "The selected ZIP archive could not be opened: \(error.localizedDescription)"
            )
        }
        defer { try? archive.close() }

        let archiveSize: UInt64
        do {
            archiveSize = try archive.seekToEnd()
        } catch {
            throw Self.failure(
                .sourceUnavailable,
                "The selected ZIP archive could not be read: \(error.localizedDescription)"
            )
        }

        await report(GameDataImportProgress(phase: .scanning))
        try Task.checkCancellation()
        let directory = try parseEndOfCentralDirectory(
            archive: archive,
            archiveSize: archiveSize
        )
        let entry = try await findISOEntry(archive: archive, directory: directory)
        try validateExpansion(entry, destinationURL: destinationURL)
        let dataOffset = try validateLocalHeader(
            archive: archive,
            entry: entry,
            centralDirectoryOffset: directory.centralDirectoryOffset
        )

        let manager = FileManager.default
        do {
            try Data().write(to: destinationURL, options: .withoutOverwriting)
        } catch {
            throw Self.outputFailure(error)
        }

        var extractionSucceeded = false
        defer {
            if !extractionSucceeded {
                try? manager.removeItem(at: destinationURL)
            }
        }

        let output: FileHandle
        do {
            output = try FileHandle(forWritingTo: destinationURL)
        } catch {
            throw Self.failure(
                .stagingFailed,
                "Eco Pro could not open private ZIP extraction staging: \(error.localizedDescription)"
            )
        }
        defer { try? output.close() }

        var state = OutputState()
        switch entry.method {
        case 0:
            try await copyStored(
                archive: archive,
                dataOffset: dataOffset,
                entry: entry,
                output: output,
                state: &state,
                report: report
            )
        case 8:
            try await inflateDeflated(
                archive: archive,
                dataOffset: dataOffset,
                entry: entry,
                output: output,
                state: &state,
                report: report
            )
        default:
            throw Self.failure(
                .unsupportedArchive,
                "The ISO uses unsupported ZIP compression method \(entry.method)."
            )
        }

        guard state.bytesWritten == entry.uncompressedSize else {
            throw Self.failure(
                .invalidDiscImage,
                "The ZIP member size does not match its directory record."
            )
        }
        guard UInt32(truncatingIfNeeded: state.checksum) == entry.checksum else {
            throw Self.failure(
                .invalidDiscImage,
                "The ZIP member failed its CRC-32 integrity check."
            )
        }

        do {
            try output.synchronize()
        } catch {
            throw Self.outputFailure(error)
        }
        extractionSucceeded = true
    }

    private func parseEndOfCentralDirectory(
        archive: FileHandle,
        archiveSize: UInt64
    ) throws -> EndOfCentralDirectory {
        let minimumRecordBytes: UInt64 = 22
        guard archiveSize >= minimumRecordBytes else {
            throw Self.failure(.invalidDiscImage, "The selected file is not a complete ZIP archive.")
        }

        let tailSize = Int(min(archiveSize, minimumRecordBytes + UInt64(UInt16.max)))
        let tailOffset = archiveSize - UInt64(tailSize)
        let tail = try Self.readExactly(archive, offset: tailOffset, count: tailSize)

        var recordIndex: Int?
        var index = tail.count - Int(minimumRecordBytes)
        while index >= 0 {
            if Self.uint32(tail, at: index) == 0x0605_4b50 {
                let commentLength = Int(Self.uint16(tail, at: index + 20))
                if index + Int(minimumRecordBytes) + commentLength == tail.count {
                    recordIndex = index
                    break
                }
            }
            if index == 0 { break }
            index -= 1
        }
        guard let recordIndex else {
            throw Self.failure(.invalidDiscImage, "The ZIP end-of-directory record is missing.")
        }

        if recordIndex >= 20,
           Self.uint32(tail, at: recordIndex - 20) == 0x0706_4b50
        {
            throw Self.failure(
                .unsupportedArchive,
                "ZIP64 archives are not supported. Create a standard ZIP containing one ISO."
            )
        }

        let diskNumber = Self.uint16(tail, at: recordIndex + 4)
        let directoryDisk = Self.uint16(tail, at: recordIndex + 6)
        let entriesOnDisk = Self.uint16(tail, at: recordIndex + 8)
        let totalEntries = Self.uint16(tail, at: recordIndex + 10)
        let directorySize32 = Self.uint32(tail, at: recordIndex + 12)
        let directoryOffset32 = Self.uint32(tail, at: recordIndex + 16)

        if entriesOnDisk == UInt16.max || totalEntries == UInt16.max
            || directorySize32 == UInt32.max || directoryOffset32 == UInt32.max
        {
            throw Self.failure(
                .unsupportedArchive,
                "ZIP64 archives are not supported. Create a standard ZIP containing one ISO."
            )
        }
        guard diskNumber == 0, directoryDisk == 0, entriesOnDisk == totalEntries else {
            throw Self.failure(
                .unsupportedArchive,
                "Multi-disk ZIP archives are not supported. Choose one ordinary ZIP file."
            )
        }
        guard Int(totalEntries) <= limits.maximumEntries else {
            throw Self.failure(.unsupportedArchive, "The ZIP contains an unreasonable number of entries.")
        }

        let directorySize = UInt64(directorySize32)
        let directoryOffset = UInt64(directoryOffset32)
        let recordOffset = tailOffset + UInt64(recordIndex)
        guard directorySize <= limits.maximumCentralDirectoryBytes else {
            throw Self.failure(.unsupportedArchive, "The ZIP directory is unreasonably large.")
        }
        guard let directoryEnd = Self.adding(directoryOffset, directorySize),
              directoryEnd == recordOffset
        else {
            throw Self.failure(
                .invalidDiscImage,
                "The ZIP central directory has invalid bounds."
            )
        }

        return EndOfCentralDirectory(
            entryCount: Int(totalEntries),
            centralDirectoryOffset: directoryOffset,
            recordOffset: recordOffset
        )
    }

    private func findISOEntry(
        archive: FileHandle,
        directory: EndOfCentralDirectory
    ) async throws -> Entry {
        var cursor = directory.centralDirectoryOffset
        let directoryEnd = directory.recordOffset
        var selected: Entry?

        for entryIndex in 0..<directory.entryCount {
            if entryIndex.isMultiple(of: 128) {
                try Task.checkCancellation()
            }
            guard let fixedEnd = Self.adding(cursor, 46), fixedEnd <= directoryEnd else {
                throw Self.failure(.invalidDiscImage, "The ZIP central directory is truncated.")
            }
            let fixed = try Self.readExactly(archive, offset: cursor, count: 46)
            guard Self.uint32(fixed, at: 0) == 0x0201_4b50 else {
                throw Self.failure(.invalidDiscImage, "The ZIP central directory is malformed.")
            }

            let creatorSystem = UInt8(truncatingIfNeeded: Self.uint16(fixed, at: 4) >> 8)
            let flags = Self.uint16(fixed, at: 8)
            try Self.validateFlags(flags)
            let method = Self.uint16(fixed, at: 10)
            let checksum = Self.uint32(fixed, at: 16)
            let compressedSize32 = Self.uint32(fixed, at: 20)
            let uncompressedSize32 = Self.uint32(fixed, at: 24)
            let nameLength = Int(Self.uint16(fixed, at: 28))
            let extraLength = Int(Self.uint16(fixed, at: 30))
            let commentLength = Int(Self.uint16(fixed, at: 32))
            let diskStart = Self.uint16(fixed, at: 34)
            let externalAttributes = Self.uint32(fixed, at: 38)
            let localHeaderOffset32 = Self.uint32(fixed, at: 42)

            if compressedSize32 == UInt32.max || uncompressedSize32 == UInt32.max
                || localHeaderOffset32 == UInt32.max
            {
                throw Self.failure(
                    .unsupportedArchive,
                    "ZIP64 archives are not supported. Create a standard ZIP containing one ISO."
                )
            }
            guard diskStart == 0 else {
                throw Self.failure(
                    .unsupportedArchive,
                    "Multi-disk ZIP archives are not supported. Choose one ordinary ZIP file."
                )
            }

            let variableLength = nameLength + extraLength + commentLength
            guard let nextCursor = Self.adding(cursor, UInt64(46 + variableLength)),
                  nextCursor <= directoryEnd
            else {
                throw Self.failure(.invalidDiscImage, "A ZIP directory entry is truncated.")
            }
            let nameAndExtra = try Self.readExactly(
                archive,
                offset: cursor + 46,
                count: nameLength + extraLength
            )
            let nameBytes = nameAndExtra.prefix(nameLength)
            let extra = nameAndExtra.dropFirst(nameLength)
            try Self.validateExtra(Data(extra))

            let name = try Self.decodeName(Data(nameBytes), flags: flags)
            try Self.validatePath(name)
            if Self.isISOName(name) {
                guard !Self.isDirectory(
                    name,
                    externalAttributes: externalAttributes,
                    creatorSystem: creatorSystem
                ), Self.isRegularFile(
                    externalAttributes: externalAttributes,
                    creatorSystem: creatorSystem
                )
                else {
                    throw Self.failure(.invalidDiscImage, "The ZIP ISO entry is not a regular file.")
                }
                guard method == 0 || method == 8 else {
                    throw Self.failure(
                        .unsupportedArchive,
                        "The ISO uses unsupported ZIP compression method \(method)."
                    )
                }
                try Self.validateFlags(flags, method: method)
                guard selected == nil else {
                    throw Self.failure(
                        .unsupportedArchive,
                        "The ZIP contains more than one ISO. Choose an archive with exactly one ISO."
                    )
                }
                selected = Entry(
                    name: name,
                    nameBytes: Data(nameBytes),
                    flags: flags,
                    method: method,
                    checksum: checksum,
                    compressedSize: UInt64(compressedSize32),
                    uncompressedSize: UInt64(uncompressedSize32),
                    localHeaderOffset: UInt64(localHeaderOffset32)
                )
            }
            cursor = nextCursor
        }

        guard cursor == directoryEnd else {
            throw Self.failure(.invalidDiscImage, "The ZIP central directory size does not match.")
        }
        guard let selected else {
            throw Self.failure(
                .unsupportedArchive,
                "The ZIP does not contain an ISO. Choose an archive with exactly one ISO."
            )
        }
        return selected
    }

    private func validateExpansion(_ entry: Entry, destinationURL: URL) throws {
        guard entry.uncompressedSize <= limits.maximumISOBytes else {
            throw Self.failure(.insufficientStorage, "The archived ISO is too large to prepare safely.")
        }
        if entry.uncompressedSize > 0 {
            let (maximumExpandedBytes, ratioOverflow) = entry.compressedSize
                .multipliedReportingOverflow(by: limits.maximumCompressionRatio)
            guard entry.compressedSize > 0,
                  ratioOverflow || entry.uncompressedSize <= maximumExpandedBytes
            else {
                throw Self.failure(
                    .unsupportedArchive,
                    "The ZIP expands by an unreasonable amount and was rejected."
                )
            }
        }
        if entry.method == 0, entry.compressedSize != entry.uncompressedSize {
            throw Self.failure(.invalidDiscImage, "The stored ZIP member has inconsistent sizes.")
        }

        let parent = destinationURL.deletingLastPathComponent()
        let values = try? parent.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ])
        let importantCapacity = values?.volumeAvailableCapacityForImportantUsage
            .flatMap { $0 > 0 ? UInt64($0) : nil }
        let basicCapacity = values?.volumeAvailableCapacity
            .flatMap { $0 > 0 ? UInt64($0) : nil }
        let available = importantCapacity ?? basicCapacity
        guard let required = Self.adding(
            entry.uncompressedSize,
            limits.minimumFreeSpaceAfterExtraction
        ), available.map({ $0 >= required }) != false else {
            throw Self.failure(
                .insufficientStorage,
                "There is not enough free space to extract and prepare this ISO."
            )
        }
    }

    private func validateLocalHeader(
        archive: FileHandle,
        entry: Entry,
        centralDirectoryOffset: UInt64
    ) throws -> UInt64 {
        guard let fixedEnd = Self.adding(entry.localHeaderOffset, 30),
              fixedEnd <= centralDirectoryOffset
        else {
            throw Self.failure(.invalidDiscImage, "The ZIP local header has invalid bounds.")
        }
        let fixed = try Self.readExactly(archive, offset: entry.localHeaderOffset, count: 30)
        guard Self.uint32(fixed, at: 0) == 0x0403_4b50 else {
            throw Self.failure(.invalidDiscImage, "The ZIP local file header is malformed.")
        }

        let flags = Self.uint16(fixed, at: 6)
        let method = Self.uint16(fixed, at: 8)
        try Self.validateFlags(flags, method: method)
        guard flags == entry.flags, method == entry.method else {
            throw Self.failure(.invalidDiscImage, "The ZIP local and central headers disagree.")
        }
        let nameLength = Int(Self.uint16(fixed, at: 26))
        let extraLength = Int(Self.uint16(fixed, at: 28))
        guard let dataOffset = Self.adding(
            entry.localHeaderOffset,
            UInt64(30 + nameLength + extraLength)
        ), let dataEnd = Self.adding(dataOffset, entry.compressedSize),
            dataEnd <= centralDirectoryOffset
        else {
            throw Self.failure(.invalidDiscImage, "The ZIP member data has invalid bounds.")
        }

        let nameAndExtra = try Self.readExactly(
            archive,
            offset: entry.localHeaderOffset + 30,
            count: nameLength + extraLength
        )
        guard Data(nameAndExtra.prefix(nameLength)) == entry.nameBytes else {
            throw Self.failure(.invalidDiscImage, "The ZIP member name does not match its directory entry.")
        }
        try Self.validateExtra(Data(nameAndExtra.dropFirst(nameLength)))

        if flags & 0x0008 == 0 {
            guard Self.uint32(fixed, at: 14) == entry.checksum,
                  UInt64(Self.uint32(fixed, at: 18)) == entry.compressedSize,
                  UInt64(Self.uint32(fixed, at: 22)) == entry.uncompressedSize
            else {
                throw Self.failure(.invalidDiscImage, "The ZIP local file sizes or checksum disagree.")
            }
        }
        return dataOffset
    }

    private func copyStored(
        archive: FileHandle,
        dataOffset: UInt64,
        entry: Entry,
        output: FileHandle,
        state: inout OutputState,
        report: @escaping @Sendable (GameDataImportProgress) async -> Void
    ) async throws {
        var consumed: UInt64 = 0
        while consumed < entry.compressedSize {
            try Task.checkCancellation()
            let count = Int(min(UInt64(limits.chunkBytes), entry.compressedSize - consumed))
            let chunk = try Self.readExactly(archive, offset: dataOffset + consumed, count: count)
            try Self.write(chunk, output: output, expectedSize: entry.uncompressedSize, state: &state)
            consumed += UInt64(count)
            await report(Self.progress(entry: entry, bytesWritten: state.bytesWritten))
        }
    }

    private func inflateDeflated(
        archive: FileHandle,
        dataOffset: UInt64,
        entry: Entry,
        output: FileHandle,
        state: inout OutputState,
        report: @escaping @Sendable (GameDataImportProgress) async -> Void
    ) async throws {
        var stream = z_stream()
        let initialized = inflateInit2_(
            &stream,
            -MAX_WBITS,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initialized == Z_OK else {
            throw Self.failure(.preparationFailed, "The ZIP decompressor could not initialize.")
        }
        defer { inflateEnd(&stream) }

        var compressedConsumed: UInt64 = 0
        var reachedEnd = false
        var outputBuffer = [UInt8](repeating: 0, count: limits.chunkBytes)
        let outputCapacity = outputBuffer.count

        while compressedConsumed < entry.compressedSize, !reachedEnd {
            try Task.checkCancellation()
            let count = Int(min(
                UInt64(limits.chunkBytes),
                entry.compressedSize - compressedConsumed
            ))
            let input = try Self.readExactly(
                archive,
                offset: dataOffset + compressedConsumed,
                count: count
            )
            compressedConsumed += UInt64(count)

            try input.withUnsafeBytes { inputBytes in
                stream.next_in = UnsafeMutablePointer<Bytef>(
                    mutating: inputBytes.bindMemory(to: Bytef.self).baseAddress
                )
                stream.avail_in = uInt(input.count)

                while stream.avail_in > 0, !reachedEnd {
                    let status = outputBuffer.withUnsafeMutableBytes { outputBytes -> Int32 in
                        stream.next_out = outputBytes.bindMemory(to: Bytef.self).baseAddress
                        stream.avail_out = uInt(outputCapacity)
                        return inflate(&stream, Z_NO_FLUSH)
                    }
                    let produced = outputCapacity - Int(stream.avail_out)
                    if produced > 0 {
                        try Self.write(
                            Data(outputBuffer.prefix(produced)),
                            output: output,
                            expectedSize: entry.uncompressedSize,
                            state: &state
                        )
                    }

                    switch status {
                    case Z_STREAM_END:
                        reachedEnd = true
                    case Z_OK:
                        if produced == 0, stream.avail_in == 0 { break }
                    default:
                        throw Self.failure(
                            .invalidDiscImage,
                            "The ZIP member contains invalid DEFLATE data."
                        )
                    }
                }
                if reachedEnd, stream.avail_in != 0 {
                    throw Self.failure(
                        .invalidDiscImage,
                        "The ZIP member has trailing compressed data."
                    )
                }
            }
            await report(Self.progress(entry: entry, bytesWritten: state.bytesWritten))
        }

        // zlib can consume the final compressed byte while filling the output buffer exactly,
        // then report the stream end only after one more call with fresh output space.
        while compressedConsumed == entry.compressedSize, !reachedEnd {
            try Task.checkCancellation()
            stream.next_in = nil
            stream.avail_in = 0
            let status = outputBuffer.withUnsafeMutableBytes { outputBytes -> Int32 in
                stream.next_out = outputBytes.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(outputCapacity)
                return inflate(&stream, Z_NO_FLUSH)
            }
            let produced = outputCapacity - Int(stream.avail_out)
            if produced > 0 {
                try Self.write(
                    Data(outputBuffer.prefix(produced)),
                    output: output,
                    expectedSize: entry.uncompressedSize,
                    state: &state
                )
            }
            if status == Z_STREAM_END {
                reachedEnd = true
            } else if status != Z_OK || produced == 0 {
                break
            }
        }
        await report(Self.progress(entry: entry, bytesWritten: state.bytesWritten))

        guard reachedEnd, compressedConsumed == entry.compressedSize else {
            throw Self.failure(.invalidDiscImage, "The ZIP DEFLATE stream is incomplete.")
        }
    }

    private static func progress(entry: Entry, bytesWritten: UInt64) -> GameDataImportProgress {
        GameDataImportProgress(
            phase: .preparingCandidate,
            filesCopied: bytesWritten == entry.uncompressedSize ? 1 : 0,
            filesTotal: 1,
            bytesCopied: Int64(clamping: bytesWritten),
            bytesTotal: Int64(clamping: entry.uncompressedSize),
            currentFile: entry.name
        )
    }

    private static func write(
        _ data: Data,
        output: FileHandle,
        expectedSize: UInt64,
        state: inout OutputState
    ) throws {
        guard let newSize = adding(state.bytesWritten, UInt64(data.count)),
              newSize <= expectedSize
        else {
            throw failure(.invalidDiscImage, "The ZIP member expanded beyond its declared size.")
        }
        do {
            try output.write(contentsOf: data)
        } catch {
            throw outputFailure(error)
        }
        state.checksum = data.withUnsafeBytes { bytes in
            crc32(
                state.checksum,
                bytes.bindMemory(to: Bytef.self).baseAddress,
                uInt(data.count)
            )
        }
        state.bytesWritten = newSize
    }

    private static func readExactly(
        _ handle: FileHandle,
        offset: UInt64,
        count: Int
    ) throws -> Data {
        do {
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: count), data.count == count else {
                throw failure(.invalidDiscImage, "The ZIP archive is truncated.")
            }
            return data
        } catch let failure as GameDataImportFailure {
            throw failure
        } catch {
            throw failure(
                .sourceUnavailable,
                "The selected ZIP archive could not be read: \(error.localizedDescription)"
            )
        }
    }

    private static func validateFlags(_ flags: UInt16, method: UInt16? = nil) throws {
        let encryptionAndUnsupportedFeatures: UInt16 = 0x0001 | 0x0020 | 0x0040 | 0x2000
        guard flags & encryptionAndUnsupportedFeatures == 0 else {
            throw failure(
                .unsupportedArchive,
                "Encrypted or masked ZIP members are not supported."
            )
        }
        if let method {
            var supportedFlags: UInt16 = 0x0008 | 0x0800
            if method == 8 {
                supportedFlags |= 0x0002 | 0x0004
            }
            guard flags & ~supportedFlags == 0 else {
                throw failure(.unsupportedArchive, "The ISO uses unsupported ZIP options.")
            }
        }
    }

    private static func decodeName(_ bytes: Data, flags: UInt16) throws -> String {
        if flags & 0x0800 == 0, !bytes.allSatisfy({ $0 < 0x80 }) {
            throw failure(
                .unsupportedArchive,
                "The ZIP uses a legacy non-UTF-8 filename encoding that is not supported."
            )
        }
        guard let name = String(data: bytes, encoding: .utf8), !name.isEmpty else {
            throw failure(.invalidDiscImage, "A ZIP member has an invalid filename.")
        }
        return name
    }

    private static func validatePath(_ name: String) throws {
        guard !name.hasPrefix("/"), !name.hasPrefix("\\"), !name.contains("\0") else {
            throw failure(.unsupportedArchive, "The ZIP contains an unsafe absolute member path.")
        }
        let components = name.split(
            omittingEmptySubsequences: false,
            whereSeparator: { $0 == "/" || $0 == "\\" }
        )
        guard !components.contains(where: { $0 == ".." }),
              !(components.first.map({ $0.count >= 2 && $0[$0.index(after: $0.startIndex)] == ":" })
                ?? false)
        else {
            throw failure(.unsupportedArchive, "The ZIP contains an unsafe member path.")
        }
    }

    private static func isISOName(_ name: String) -> Bool {
        let lastComponent = name.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last
        return lastComponent?.lowercased().hasSuffix(".iso") == true
    }

    private static func isDirectory(
        _ name: String,
        externalAttributes: UInt32,
        creatorSystem: UInt8
    ) -> Bool {
        if name.hasSuffix("/") || name.hasSuffix("\\") || externalAttributes & 0x10 != 0 {
            return true
        }
        return (creatorSystem == 3 || creatorSystem == 19)
            && (externalAttributes >> 16) & 0xf000 == 0x4000
    }

    private static func isRegularFile(
        externalAttributes: UInt32,
        creatorSystem: UInt8
    ) -> Bool {
        guard creatorSystem == 3 || creatorSystem == 19 else { return true }
        let unixType = (externalAttributes >> 16) & 0xf000
        return unixType == 0 || unixType == 0x8000
    }

    private static func validateExtra(_ extra: Data) throws {
        var offset = 0
        while offset < extra.count {
            guard offset + 4 <= extra.count else {
                throw failure(.invalidDiscImage, "A ZIP extra field is malformed.")
            }
            let identifier = uint16(extra, at: offset)
            let length = Int(uint16(extra, at: offset + 2))
            guard offset + 4 + length <= extra.count else {
                throw failure(.invalidDiscImage, "A ZIP extra field is truncated.")
            }
            if identifier == 0x0001 {
                throw failure(
                    .unsupportedArchive,
                    "ZIP64 archives are not supported. Create a standard ZIP containing one ISO."
                )
            }
            offset += 4 + length
        }
    }

    private static func uint16(_ data: Data, at offset: Int) -> UInt16 {
        let start = data.startIndex + offset
        return UInt16(data[start]) | UInt16(data[start + 1]) << 8
    }

    private static func uint32(_ data: Data, at offset: Int) -> UInt32 {
        let start = data.startIndex + offset
        return UInt32(data[start])
            | UInt32(data[start + 1]) << 8
            | UInt32(data[start + 2]) << 16
            | UInt32(data[start + 3]) << 24
    }

    private static func adding(_ left: UInt64, _ right: UInt64) -> UInt64? {
        let (sum, overflow) = left.addingReportingOverflow(right)
        return overflow ? nil : sum
    }

    private static func failure(
        _ code: GameDataImportFailure.Code,
        _ message: String
    ) -> GameDataImportFailure {
        GameDataImportFailure(code: code, message: message, candidatePreserved: false)
    }

    private static func outputFailure(_ error: Error) -> GameDataImportFailure {
        let cocoa = error as NSError
        if (cocoa.domain == NSCocoaErrorDomain && cocoa.code == NSFileWriteOutOfSpaceError)
            || (cocoa.domain == NSPOSIXErrorDomain
                && (cocoa.code == ENOSPC || cocoa.code == EDQUOT))
        {
            return failure(.insufficientStorage, "There is not enough free space to extract the ISO.")
        }
        return failure(
            .stagingFailed,
            "Eco Pro could not write the extracted ISO: \(error.localizedDescription)"
        )
    }
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
