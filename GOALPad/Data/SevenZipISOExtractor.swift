import Foundation
import OSLog
import PLzmaSDK

nonisolated private let sevenZipImportLog = Logger(
    subsystem: "com.zephyrstudiosllc.eco",
    category: "SevenZipImport"
)

/// Reads one ISO from an app-private 7z snapshot and streams it to the existing raw-ISO path.
nonisolated struct SevenZipISOExtractor: Sendable {
    func extractISO(
        from archiveURL: URL,
        to destinationURL: URL,
        limits: ZIPISOExtractor.Limits,
        report: @escaping @Sendable (GameDataImportProgress) async -> Void
    ) async throws {
        let reporter = SevenZipProgressReporter(report: report)
        do {
            let input = try InStream(path: PLzmaSDK.Path(archiveURL.path))
            let decoder = try Decoder(stream: input, fileType: .sevenZ, delegate: reporter)

            try await withTaskCancellationHandler {
                try await Task.detached {
                    guard try decoder.open() else {
                        throw Self.failure(
                            .invalidDiscImage,
                            "The 7z archive could not be opened. It may be incomplete or damaged."
                        )
                    }
                    try Task.checkCancellation()
                    await report(GameDataImportProgress(phase: .scanning))

                    let count = try decoder.count()
                    guard UInt64(count) <= UInt64(limits.maximumEntries) else {
                        throw Self.failure(
                            .unsupportedArchive,
                            "The 7z archive contains too many entries to inspect safely."
                        )
                    }

                    var selected: Item?
                    var fileCount = 0
                    for index in 0..<count {
                        if index.isMultiple(of: 128) {
                            try Task.checkCancellation()
                        }
                        let item = try decoder.item(at: index)
                        let path = try item.path().description
                        try Self.validatePath(path)
                        guard !item.encrypted else {
                            throw Self.failure(
                                .unsupportedArchive,
                                "Encrypted 7z archives are not supported."
                            )
                        }
                        guard !item.isDir else { continue }
                        fileCount += 1
                        guard fileCount == 1 else {
                            throw Self.failure(
                                .unsupportedArchive,
                                "The 7z archive contains more than one file. Choose an archive with exactly one ISO."
                            )
                        }
                        if Self.isISOName(path) {
                            selected = item
                        }
                    }

                    guard fileCount == 1, let selected else {
                        throw Self.failure(
                            .unsupportedArchive,
                            "The 7z archive does not contain an ISO. Choose an archive with exactly one ISO."
                        )
                    }
                    try Self.validateExpansion(
                        item: selected,
                        archiveURL: archiveURL,
                        destinationURL: destinationURL,
                        limits: limits
                    )

                    let total = Int64(selected.size)
                    reporter.setTotal(total)
                    await report(GameDataImportProgress(
                        phase: .preparingCandidate,
                        filesTotal: 1,
                        bytesTotal: total
                    ))
                    try Task.checkCancellation()

                    var succeeded = false
                    defer {
                        if !succeeded {
                            try? FileManager.default.removeItem(at: destinationURL)
                        }
                    }
                    let extracted: Bool = try {
                        let output = try OutStream(path: PLzmaSDK.Path(destinationURL.path))
                        let selection = try ItemOutStreamArray(capacity: 1)
                        try selection.add(item: selected, stream: output)
                        return try decoder.extract(itemsToStreams: selection)
                    }()
                    try Task.checkCancellation()
                    guard extracted else {
                        throw Self.failure(
                            .invalidDiscImage,
                            "The 7z ISO could not be extracted completely."
                        )
                    }

                    let values = try destinationURL.resourceValues(forKeys: [
                        .fileSizeKey,
                        .isRegularFileKey,
                        .isSymbolicLinkKey,
                    ])
                    guard values.isRegularFile == true,
                          values.isSymbolicLink != true,
                          values.fileSize.flatMap({ $0 >= 0 ? UInt64($0) : nil }) == selected.size
                    else {
                        throw Self.failure(
                            .invalidDiscImage,
                            "The extracted 7z ISO size does not match the archive."
                        )
                    }
                    succeeded = true
                    await report(GameDataImportProgress(
                        phase: .preparingCandidate,
                        filesCopied: 1,
                        filesTotal: 1,
                        bytesCopied: total,
                        bytesTotal: total
                    ))
                }.value
            } onCancel: {
                try? decoder.abort()
            }
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: destinationURL)
            throw CancellationError()
        } catch let failure as GameDataImportFailure {
            try? FileManager.default.removeItem(at: destinationURL)
            throw failure
        } catch let exception as PLzmaSDK.Exception {
            try? FileManager.default.removeItem(at: destinationURL)
            if Task.isCancelled {
                throw CancellationError()
            }
            sevenZipImportLog.error(
                "7z decoder failed code=\(String(describing: exception.code), privacy: .public)"
            )
            throw Self.failure(
                exception.code == .io ? .sourceUnavailable : .invalidDiscImage,
                "The 7z archive could not be read or extracted. It may be incomplete, damaged, or use unsupported compression."
            )
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            if Task.isCancelled {
                throw CancellationError()
            }
            let cocoa = error as NSError
            sevenZipImportLog.error(
                "7z import failed domain=\(cocoa.domain, privacy: .public) code=\(cocoa.code)"
            )
            throw Self.failure(
                .invalidDiscImage,
                "The 7z archive could not be read or extracted. It may be incomplete or damaged."
            )
        }
    }

    private static func validateExpansion(
        item: Item,
        archiveURL: URL,
        destinationURL: URL,
        limits: ZIPISOExtractor.Limits
    ) throws {
        guard item.size > 0, item.size <= limits.maximumISOBytes else {
            throw failure(.insufficientStorage, "The archived ISO is too large to prepare safely.")
        }

        let archiveBytes = (try? archiveURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
            .flatMap { $0 > 0 ? UInt64($0) : nil }
        let compressedBytes = item.packSize > 0 ? item.packSize : archiveBytes
        if let compressedBytes {
            let (maximumExpandedBytes, overflow) = compressedBytes.multipliedReportingOverflow(
                by: limits.maximumCompressionRatio
            )
            guard overflow || item.size <= maximumExpandedBytes else {
                throw failure(
                    .unsupportedArchive,
                    "The 7z archive expands by an unreasonable amount and was rejected."
                )
            }
        }

        let parent = destinationURL.deletingLastPathComponent()
        let values = try? parent.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ])
        let available = values?.volumeAvailableCapacityForImportantUsage
            .flatMap { $0 > 0 ? UInt64($0) : nil }
            ?? values?.volumeAvailableCapacity.flatMap { $0 > 0 ? UInt64($0) : nil }
        let (required, overflow) = item.size.addingReportingOverflow(
            limits.minimumFreeSpaceAfterExtraction
        )
        guard !overflow, available.map({ $0 >= required }) != false else {
            throw failure(
                .insufficientStorage,
                "There is not enough free space to extract and prepare this ISO."
            )
        }
    }

    private static func validatePath(_ path: String) throws {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
        guard !normalized.isEmpty,
              !normalized.hasPrefix("/"),
              !normalized.contains("\0"),
              !components.contains(".."),
              !(normalized.count >= 2 && normalized[normalized.index(after: normalized.startIndex)] == ":")
        else {
            throw failure(.unsupportedArchive, "The 7z archive contains an unsafe path.")
        }
    }

    private static func isISOName(_ path: String) -> Bool {
        URL(fileURLWithPath: path).pathExtension.caseInsensitiveCompare("iso") == .orderedSame
    }

    private static func failure(
        _ code: GameDataImportFailure.Code,
        _ message: String
    ) -> GameDataImportFailure {
        GameDataImportFailure(code: code, message: message, candidatePreserved: false)
    }
}

nonisolated private final class SevenZipProgressReporter: DecoderDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let report: @Sendable (GameDataImportProgress) async -> Void
    private var total: Int64 = 0
    private var lastPercent = -1

    init(report: @escaping @Sendable (GameDataImportProgress) async -> Void) {
        self.report = report
    }

    func setTotal(_ value: Int64) {
        lock.withLock {
            total = value
            lastPercent = -1
        }
    }

    func decoder(decoder _: Decoder, path _: String, progress: Double) {
        let update: (Int64, Int64)? = lock.withLock {
            guard total > 0 else { return nil }
            let fraction = min(1, max(0, progress))
            let percent = Int((fraction * 100).rounded(.down))
            guard percent > lastPercent else { return nil }
            lastPercent = percent
            return (Int64(fraction * Double(total)), total)
        }
        guard let update else { return }
        Task {
            await report(GameDataImportProgress(
                phase: .preparingCandidate,
                filesCopied: update.0 == update.1 ? 1 : 0,
                filesTotal: 1,
                bytesCopied: update.0,
                bytesTotal: update.1
            ))
        }
    }
}
