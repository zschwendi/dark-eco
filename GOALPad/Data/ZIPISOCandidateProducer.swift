import Darwin
import Foundation
import zlib

/// Streams one ordinary ZIP member to private staging before handing it to the raw-ISO producer.
/// The temporary image is a sibling of the candidate so it can never enter the activated install.
nonisolated struct ZIPISOCandidateProducer: GameDataCandidateProducing {
    private let downstream: any GameDataCandidateProducing
    private let extractor: ZIPISOExtractor
    private let stagingCleaner: ZIPISOStagingCleaner

    init(
        downstream: any GameDataCandidateProducing,
        extractor: ZIPISOExtractor = ZIPISOExtractor(),
        stagingCleaner: ZIPISOStagingCleaner = ZIPISOStagingCleaner()
    ) {
        self.downstream = downstream
        self.extractor = extractor
        self.stagingCleaner = stagingCleaner
    }

    func prepareCandidate(
        from source: URL,
        activeDirectory: URL,
        candidateDirectory: URL,
        report: @escaping @Sendable (GameDataImportProgress) async -> Void
    ) async throws -> GameDataImportResult {
        let stagingDirectory = candidateDirectory.deletingLastPathComponent()
        stagingCleaner.removeStaleOwnedFiles(in: stagingDirectory)
        let temporaryISO = stagingDirectory.appending(
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

/// Removes only exact app-generated temporary names. The current import has not created its UUID
/// yet, so any matching pre-existing sibling belongs to an interrupted earlier attempt.
nonisolated struct ZIPISOStagingCleaner: Sendable {
    private static let suffix = ".extracted.iso"
    private let maximumRemovals: Int

    init(maximumRemovals: Int = 4) {
        self.maximumRemovals = max(0, maximumRemovals)
    }

    func removeStaleOwnedFiles(in directory: URL) {
        guard maximumRemovals > 0 else { return }
        let manager = FileManager.default
        let siblings = (try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let ownedFiles = siblings.filter { url in
            guard Self.isOwnedTemporaryISO(url.lastPathComponent),
                  let values = try? url.resourceValues(forKeys: [
                      .isRegularFileKey,
                      .isSymbolicLinkKey,
                  ])
            else {
                return false
            }
            return values.isRegularFile == true && values.isSymbolicLink != true
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        for url in ownedFiles.prefix(maximumRemovals) {
            try? manager.removeItem(at: url)
        }
    }

    private static func isOwnedTemporaryISO(_ name: String) -> Bool {
        guard name.hasSuffix(suffix) else { return false }
        let uuidString = String(name.dropLast(suffix.count))
        guard let uuid = UUID(uuidString: uuidString) else { return false }
        return uuid.uuidString == uuidString
    }
}

/// Minimal ZIP32/ZIP64 reader for local, bounded ISO extraction. It intentionally rejects ZIP
/// features that are unnecessary for the supported import path instead of repairing or guessing.
nonisolated struct ZIPISOExtractor: Sendable {
    nonisolated struct Limits: Sendable {
        var maximumEntries = 100_000
        var maximumCentralDirectoryBytes: UInt64 = 64 * 1_024 * 1_024
        var maximumISOBytes: UInt64 = 4_410_671_104
        var maximumCompressionOverheadBytes: UInt64 = 64 * 1_024 * 1_024
        var maximumCompressionRatio: UInt64 = 1_000
        var minimumFreeSpaceAfterExtraction: UInt64 = 256 * 1_024 * 1_024
        var chunkBytes = 1 * 1_024 * 1_024
    }

    private struct EndOfCentralDirectory: Sendable {
        let entryCount: Int
        let centralDirectoryOffset: UInt64
        let centralDirectoryEnd: UInt64
        let usesZIP64: Bool
    }

    private struct LegacyEndOfCentralDirectory: Sendable {
        let diskNumber: UInt16
        let directoryDisk: UInt16
        let entriesOnDisk: UInt16
        let totalEntries: UInt16
        let directorySize: UInt32
        let directoryOffset: UInt32
    }

    private struct CentralZIP64Values: Sendable {
        let compressedSize: UInt64
        let uncompressedSize: UInt64
        let localHeaderOffset: UInt64
        let diskStart: UInt32
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
            centralDirectoryOffset: directory.centralDirectoryOffset,
            archiveUsesZIP64: directory.usesZIP64
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
                "Eco could not open private ZIP extraction staging: \(error.localizedDescription)"
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
        try Task.checkCancellation()

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
        try Task.checkCancellation()
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

        guard let recordOffset = Self.adding(tailOffset, UInt64(recordIndex)) else {
            throw Self.failure(.invalidDiscImage, "The ZIP end-of-directory offset overflowed.")
        }
        let legacy = LegacyEndOfCentralDirectory(
            diskNumber: Self.uint16(tail, at: recordIndex + 4),
            directoryDisk: Self.uint16(tail, at: recordIndex + 6),
            entriesOnDisk: Self.uint16(tail, at: recordIndex + 8),
            totalEntries: Self.uint16(tail, at: recordIndex + 10),
            directorySize: Self.uint32(tail, at: recordIndex + 12),
            directoryOffset: Self.uint32(tail, at: recordIndex + 16)
        )

        let locatorOffset: UInt64? = recordOffset >= 20 ? recordOffset - 20 : nil
        let locator: Data?
        if let locatorOffset {
            let candidate = try Self.readExactly(archive, offset: locatorOffset, count: 20)
            locator = Self.uint32(candidate, at: 0) == 0x0706_4b50 ? candidate : nil
        } else {
            locator = nil
        }

        if let locator, let locatorOffset {
            return try parseZIP64End(
                archive: archive,
                archiveSize: archiveSize,
                legacy: legacy,
                locator: locator,
                locatorOffset: locatorOffset
            )
        }

        let hasSentinel = legacy.diskNumber == UInt16.max
            || legacy.directoryDisk == UInt16.max
            || legacy.entriesOnDisk == UInt16.max
            || legacy.totalEntries == UInt16.max
            || legacy.directorySize == UInt32.max
            || legacy.directoryOffset == UInt32.max
        guard !hasSentinel else {
            throw Self.failure(
                .invalidDiscImage,
                "The ZIP64 end records required by the directory are missing."
            )
        }
        guard legacy.diskNumber == 0,
              legacy.directoryDisk == 0,
              legacy.entriesOnDisk == legacy.totalEntries
        else {
            throw Self.failure(
                .unsupportedArchive,
                "Multi-disk ZIP archives are not supported. Choose one ordinary ZIP file."
            )
        }
        let entryCount = try validateEntryCount(UInt64(legacy.totalEntries))

        let directorySize = UInt64(legacy.directorySize)
        let directoryOffset = UInt64(legacy.directoryOffset)
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
            entryCount: entryCount,
            centralDirectoryOffset: directoryOffset,
            centralDirectoryEnd: recordOffset,
            usesZIP64: false
        )
    }

    private func parseZIP64End(
        archive: FileHandle,
        archiveSize: UInt64,
        legacy: LegacyEndOfCentralDirectory,
        locator: Data,
        locatorOffset: UInt64
    ) throws -> EndOfCentralDirectory {
        let locatorDisk = Self.uint32(locator, at: 4)
        let zip64RecordOffset = Self.uint64(locator, at: 8)
        let totalDisks = Self.uint32(locator, at: 16)
        guard locatorDisk == 0, totalDisks == 1 else {
            throw Self.failure(
                .unsupportedArchive,
                "Multi-disk ZIP64 archives are not supported. Choose one ordinary ZIP file."
            )
        }
        guard zip64RecordOffset < locatorOffset,
              let minimumEnd = Self.adding(zip64RecordOffset, 56),
              minimumEnd <= locatorOffset,
              minimumEnd <= archiveSize
        else {
            throw Self.failure(.invalidDiscImage, "The ZIP64 end record has invalid bounds.")
        }

        let fixed = try Self.readExactly(archive, offset: zip64RecordOffset, count: 56)
        guard Self.uint32(fixed, at: 0) == 0x0606_4b50 else {
            throw Self.failure(.invalidDiscImage, "The ZIP64 end record is missing or malformed.")
        }
        let recordSize = Self.uint64(fixed, at: 4)
        guard recordSize >= 44,
              recordSize <= limits.maximumCentralDirectoryBytes,
              let completeSize = Self.adding(recordSize, 12),
              let recordEnd = Self.adding(zip64RecordOffset, completeSize),
              recordEnd == locatorOffset
        else {
            throw Self.failure(.invalidDiscImage, "The ZIP64 end record has invalid bounds.")
        }

        let versionNeeded = Self.uint16(fixed, at: 14)
        let diskNumber = Self.uint32(fixed, at: 16)
        let directoryDisk = Self.uint32(fixed, at: 20)
        let entriesOnDisk = Self.uint64(fixed, at: 24)
        let totalEntries = Self.uint64(fixed, at: 32)
        let directorySize = Self.uint64(fixed, at: 40)
        let directoryOffset = Self.uint64(fixed, at: 48)

        guard versionNeeded >= 45 else {
            throw Self.failure(.invalidDiscImage, "The ZIP64 end record has an invalid version.")
        }
        guard diskNumber == 0, directoryDisk == 0, entriesOnDisk == totalEntries else {
            throw Self.failure(
                .unsupportedArchive,
                "Multi-disk ZIP64 archives are not supported. Choose one ordinary ZIP file."
            )
        }
        guard Self.matches(legacy.diskNumber, sentinel: UInt16.max, zip64: UInt64(diskNumber)),
              Self.matches(legacy.directoryDisk, sentinel: UInt16.max, zip64: UInt64(directoryDisk)),
              Self.matches(legacy.entriesOnDisk, sentinel: UInt16.max, zip64: entriesOnDisk),
              Self.matches(legacy.totalEntries, sentinel: UInt16.max, zip64: totalEntries),
              Self.matches(legacy.directorySize, sentinel: UInt32.max, zip64: directorySize),
              Self.matches(legacy.directoryOffset, sentinel: UInt32.max, zip64: directoryOffset)
        else {
            throw Self.failure(.invalidDiscImage, "The ZIP32 and ZIP64 end records disagree.")
        }

        let entryCount = try validateEntryCount(totalEntries)
        guard directorySize <= limits.maximumCentralDirectoryBytes else {
            throw Self.failure(.unsupportedArchive, "The ZIP directory is unreasonably large.")
        }
        guard let directoryEnd = Self.adding(directoryOffset, directorySize),
              directoryEnd == zip64RecordOffset
        else {
            throw Self.failure(.invalidDiscImage, "The ZIP64 central directory has invalid bounds.")
        }

        return EndOfCentralDirectory(
            entryCount: entryCount,
            centralDirectoryOffset: directoryOffset,
            centralDirectoryEnd: zip64RecordOffset,
            usesZIP64: true
        )
    }

    private func validateEntryCount(_ count: UInt64) throws -> Int {
        guard limits.maximumEntries >= 0,
              count <= UInt64(limits.maximumEntries),
              count <= UInt64(Int.max)
        else {
            throw Self.failure(
                .unsupportedArchive,
                "The ZIP contains an unreasonable number of entries."
            )
        }
        return Int(count)
    }

    private func findISOEntry(
        archive: FileHandle,
        directory: EndOfCentralDirectory
    ) async throws -> Entry {
        var cursor = directory.centralDirectoryOffset
        let directoryEnd = directory.centralDirectoryEnd
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
            let versionNeeded = Self.uint16(fixed, at: 6)
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

            let variableLength = nameLength + extraLength + commentLength
            guard let nextCursor = Self.adding(cursor, UInt64(46 + variableLength)),
                  nextCursor <= directoryEnd
            else {
                throw Self.failure(.invalidDiscImage, "A ZIP directory entry is truncated.")
            }
            let nameAndExtra = try Self.readExactly(
                archive,
                offset: fixedEnd,
                count: nameLength + extraLength
            )
            let nameBytes = nameAndExtra.prefix(nameLength)
            let extra = nameAndExtra.dropFirst(nameLength)
            let zip64Payload = try Self.uniqueZIP64Payload(in: Data(extra))
            let zip64Values = try Self.resolveCentralZIP64(
                compressedSize32: compressedSize32,
                uncompressedSize32: uncompressedSize32,
                localHeaderOffset32: localHeaderOffset32,
                diskStart16: diskStart,
                payload: zip64Payload
            )
            let entryUsesZIP64 = zip64Payload != nil
                || compressedSize32 == UInt32.max
                || uncompressedSize32 == UInt32.max
                || localHeaderOffset32 == UInt32.max
                || diskStart == UInt16.max
            guard !entryUsesZIP64 || directory.usesZIP64 else {
                throw Self.failure(
                    .invalidDiscImage,
                    "A ZIP64 directory entry is missing the required ZIP64 end records."
                )
            }
            if entryUsesZIP64, versionNeeded < 45 {
                throw Self.failure(
                    .invalidDiscImage,
                    "A ZIP64 directory entry has an invalid extraction version."
                )
            }
            guard zip64Values.diskStart == 0 else {
                throw Self.failure(
                    .unsupportedArchive,
                    "Multi-disk ZIP archives are not supported. Choose one ordinary ZIP file."
                )
            }

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
                    compressedSize: zip64Values.compressedSize,
                    uncompressedSize: zip64Values.uncompressedSize,
                    localHeaderOffset: zip64Values.localHeaderOffset
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
        guard let maximumCompressedSize = Self.adding(
            entry.uncompressedSize,
            limits.maximumCompressionOverheadBytes
        ), entry.compressedSize <= maximumCompressedSize else {
            throw Self.failure(.unsupportedArchive, "The archived ISO member is unreasonably large.")
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
        centralDirectoryOffset: UInt64,
        archiveUsesZIP64: Bool
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
            offset: fixedEnd,
            count: nameLength + extraLength
        )
        guard Data(nameAndExtra.prefix(nameLength)) == entry.nameBytes else {
            throw Self.failure(.invalidDiscImage, "The ZIP member name does not match its directory entry.")
        }
        let localCompressedSize32 = Self.uint32(fixed, at: 18)
        let localUncompressedSize32 = Self.uint32(fixed, at: 22)
        let zip64Payload = try Self.uniqueZIP64Payload(
            in: Data(nameAndExtra.dropFirst(nameLength))
        )
        let localUsesZIP64 = zip64Payload != nil
            || localCompressedSize32 == UInt32.max
            || localUncompressedSize32 == UInt32.max
        guard !localUsesZIP64 || archiveUsesZIP64 else {
            throw Self.failure(
                .invalidDiscImage,
                "The ZIP local header is missing the required ZIP64 end records."
            )
        }
        if localUsesZIP64, Self.uint16(fixed, at: 4) < 45 {
            throw Self.failure(
                .invalidDiscImage,
                "The ZIP local ZIP64 header has an invalid extraction version."
            )
        }
        let localSizes = try Self.resolveLocalZIP64(
            compressedSize32: localCompressedSize32,
            uncompressedSize32: localUncompressedSize32,
            payload: zip64Payload
        )

        if flags & 0x0008 == 0 {
            guard Self.uint32(fixed, at: 14) == entry.checksum,
                  localSizes.compressedSize == entry.compressedSize,
                  localSizes.uncompressedSize == entry.uncompressedSize
            else {
                throw Self.failure(.invalidDiscImage, "The ZIP local file sizes or checksum disagree.")
            }
        } else if localUsesZIP64 {
            let localChecksum = Self.uint32(fixed, at: 14)
            guard localChecksum == 0 || localChecksum == entry.checksum,
                  localSizes.compressedSize == 0
                    || localSizes.compressedSize == entry.compressedSize,
                  localSizes.uncompressedSize == 0
                    || localSizes.uncompressedSize == entry.uncompressedSize
            else {
                throw Self.failure(.invalidDiscImage, "The ZIP local ZIP64 sizes disagree.")
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
                    try Task.checkCancellation()
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
                    try Task.checkCancellation()

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
            try Task.checkCancellation()
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
        guard count >= 0, adding(offset, UInt64(count)) != nil else {
            throw failure(.invalidDiscImage, "A ZIP record offset overflowed.")
        }
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

    private static func uniqueZIP64Payload(in extra: Data) throws -> Data? {
        var offset = 0
        var zip64Payload: Data?
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
                guard zip64Payload == nil else {
                    throw failure(.invalidDiscImage, "A ZIP record has duplicate ZIP64 extra fields.")
                }
                zip64Payload = extra.subdata(in: (offset + 4)..<(offset + 4 + length))
            }
            offset += 4 + length
        }
        return zip64Payload
    }

    private static func resolveCentralZIP64(
        compressedSize32: UInt32,
        uncompressedSize32: UInt32,
        localHeaderOffset32: UInt32,
        diskStart16: UInt16,
        payload: Data?
    ) throws -> CentralZIP64Values {
        let needsUncompressedSize = uncompressedSize32 == UInt32.max
        let needsCompressedSize = compressedSize32 == UInt32.max
        let needsLocalHeaderOffset = localHeaderOffset32 == UInt32.max
        let needsDiskStart = diskStart16 == UInt16.max
        let needsZIP64 = needsUncompressedSize || needsCompressedSize
            || needsLocalHeaderOffset || needsDiskStart

        if !needsZIP64, let payload, !payload.isEmpty {
            throw failure(
                .invalidDiscImage,
                "A ZIP64 extra field contains values not requested by its directory entry."
            )
        }
        guard !needsZIP64 || payload != nil else {
            throw failure(.invalidDiscImage, "A ZIP64 directory entry is missing its extra field.")
        }

        let payload = payload ?? Data()
        var cursor = 0
        let uncompressedSize = needsUncompressedSize
            ? try consumeUInt64(payload, cursor: &cursor, field: "uncompressed size")
            : UInt64(uncompressedSize32)
        let compressedSize = needsCompressedSize
            ? try consumeUInt64(payload, cursor: &cursor, field: "compressed size")
            : UInt64(compressedSize32)
        let localHeaderOffset = needsLocalHeaderOffset
            ? try consumeUInt64(payload, cursor: &cursor, field: "local-header offset")
            : UInt64(localHeaderOffset32)
        let diskStart = needsDiskStart
            ? try consumeUInt32(payload, cursor: &cursor, field: "disk start")
            : UInt32(diskStart16)
        guard cursor == payload.count else {
            throw failure(.invalidDiscImage, "A ZIP64 directory extra field has invalid length.")
        }
        return CentralZIP64Values(
            compressedSize: compressedSize,
            uncompressedSize: uncompressedSize,
            localHeaderOffset: localHeaderOffset,
            diskStart: diskStart
        )
    }

    private static func resolveLocalZIP64(
        compressedSize32: UInt32,
        uncompressedSize32: UInt32,
        payload: Data?
    ) throws -> (compressedSize: UInt64, uncompressedSize: UInt64) {
        let compressedSentinel = compressedSize32 == UInt32.max
        let uncompressedSentinel = uncompressedSize32 == UInt32.max
        let needsZIP64 = compressedSentinel || uncompressedSentinel
        guard !needsZIP64 || (compressedSentinel && uncompressedSentinel) else {
            throw failure(
                .invalidDiscImage,
                "The ZIP local header has inconsistent ZIP64 size sentinels."
            )
        }
        if !needsZIP64, let payload, !payload.isEmpty {
            throw failure(
                .invalidDiscImage,
                "A local ZIP64 extra field contains sizes not requested by its header."
            )
        }
        guard !needsZIP64 || payload != nil else {
            throw failure(.invalidDiscImage, "The ZIP local header is missing its ZIP64 extra field.")
        }
        guard needsZIP64 else {
            return (UInt64(compressedSize32), UInt64(uncompressedSize32))
        }

        let payload = payload ?? Data()
        guard payload.count == 16 else {
            throw failure(.invalidDiscImage, "The ZIP local ZIP64 extra field has invalid length.")
        }
        return (
            compressedSize: uint64(payload, at: 8),
            uncompressedSize: uint64(payload, at: 0)
        )
    }

    private static func consumeUInt64(
        _ data: Data,
        cursor: inout Int,
        field: String
    ) throws -> UInt64 {
        guard cursor + 8 <= data.count else {
            throw failure(.invalidDiscImage, "The ZIP64 extra field is missing its \(field).")
        }
        defer { cursor += 8 }
        return uint64(data, at: cursor)
    }

    private static func consumeUInt32(
        _ data: Data,
        cursor: inout Int,
        field: String
    ) throws -> UInt32 {
        guard cursor + 4 <= data.count else {
            throw failure(.invalidDiscImage, "The ZIP64 extra field is missing its \(field).")
        }
        defer { cursor += 4 }
        return uint32(data, at: cursor)
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

    private static func uint64(_ data: Data, at offset: Int) -> UInt64 {
        UInt64(uint32(data, at: offset))
            | UInt64(uint32(data, at: offset + 4)) << 32
    }

    private static func matches(
        _ legacy: UInt16,
        sentinel: UInt16,
        zip64: UInt64
    ) -> Bool {
        legacy == sentinel || UInt64(legacy) == zip64
    }

    private static func matches(
        _ legacy: UInt32,
        sentinel: UInt32,
        zip64: UInt64
    ) -> Bool {
        legacy == sentinel || UInt64(legacy) == zip64
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
            "Eco could not write the extracted ISO: \(error.localizedDescription)"
        )
    }
}
