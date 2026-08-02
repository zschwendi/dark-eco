import Foundation
import OSLog

nonisolated private let importLog = Logger(subsystem: "com.zephyrstudiosllc.eco",
                                           category: "Import")

/// Copies a player-selected `iso/` and `fr3/` into the app's own game directory.
///
/// This is the second way to get data onto the device. The first, and the one that avoids a second
/// copy of 1.5 GB, is to drop the two directories straight into GOALPad's Documents folder from
/// Finder or the Files app. This path exists for data that lives somewhere the app cannot be given
/// directly - an external drive, iCloud Drive, another app's container.
///
/// It only ever reads from the source and writes into the app's own directory. Nothing is fetched
/// from the network and nothing is uploaded.
@MainActor
@Observable
final class GameDataImporter {
    nonisolated struct Progress: Sendable {
        var filesCopied = 0
        var filesTotal = 0
        var bytesCopied: Int64 = 0
        var bytesTotal: Int64 = 0
        var currentFile = ""

        var fraction: Double {
            bytesTotal > 0 ? Double(bytesCopied) / Double(bytesTotal) : 0
        }
    }

    nonisolated enum State: Sendable {
        case idle
        case scanning
        case copying(Progress)
        case finished(filesCopied: Int, filesSkipped: Int)
        case failed(String)
    }

    private(set) var state: State = .idle
    private var task: Task<Void, Never>?

    var isRunning: Bool {
        switch state {
        case .scanning, .copying: return true
        default: return false
        }
    }

    /// `source` may be the directory that holds `iso/` and `fr3/` (an OpenGOAL `out/jak1`), or
    /// either of those two directories on its own.
    func start(from source: URL, onFinish: @escaping @MainActor () -> Void) {
        guard !isRunning else { return }
        state = .scanning
        task = Task { [self] in
            let result = await Self.copy(from: source) { progress in
                Task { @MainActor in self.state = .copying(progress) }
            }
            guard !Task.isCancelled else { return }
            state = result
            onFinish()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        state = .idle
    }

    func reset() {
        state = .idle
    }

    // MARK: - The copy itself

    @concurrent
    private nonisolated static func copy(
        from source: URL,
        report: @escaping @Sendable (Progress) -> Void
    ) async -> State {
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }

        let pairs: [(from: URL, to: URL)]
        switch source.lastPathComponent.lowercased() {
        case GameDataLayout.isoDirectoryName:
            pairs = [(source, GameDataLayout.isoDirectory)]
        case GameDataLayout.fr3DirectoryName:
            pairs = [(source, GameDataLayout.fr3Directory)]
        default:
            pairs = [
                (source.appending(path: GameDataLayout.isoDirectoryName), GameDataLayout.isoDirectory),
                (source.appending(path: GameDataLayout.fr3DirectoryName), GameDataLayout.fr3Directory),
            ]
        }

        var work: [(from: URL, to: URL, size: Int64)] = []
        for pair in pairs {
            for file in files(in: pair.from) {
                work.append((file.url, pair.to.appending(path: file.url.lastPathComponent),
                             file.size))
            }
        }

        guard !work.isEmpty else {
            return .failed("No iso/ or fr3/ files were found in \(source.lastPathComponent).")
        }

        do {
            try GameDataLayout.prepare()
        } catch {
            return .failed("Could not prepare the game directory: \(error.localizedDescription)")
        }

        var progress = Progress(filesTotal: work.count, bytesTotal: work.reduce(0) { $0 + $1.size })
        var skipped = 0
        let manager = FileManager.default

        for item in work {
            if Task.isCancelled {
                return .failed("Import cancelled.")
            }
            progress.currentFile = item.from.lastPathComponent

            let existing = (try? item.to.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                .map(Int64.init)
            if existing == item.size {
                skipped += 1
            } else {
                do {
                    if existing != nil {
                        try manager.removeItem(at: item.to)
                    }
                    try manager.copyItem(at: item.from, to: item.to)
                } catch {
                    return .failed("Copying \(item.from.lastPathComponent) failed: "
                        + error.localizedDescription)
                }
            }

            progress.filesCopied += 1
            progress.bytesCopied += item.size
            report(progress)
        }

        importLog.notice("Imported \(progress.filesCopied - skipped) file(s), skipped \(skipped) already present")
        return .finished(filesCopied: progress.filesCopied - skipped, filesSkipped: skipped)
    }

    private nonisolated static func files(in directory: URL) -> [(url: URL, size: Int64)] {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        else {
            return []
        }
        return contents.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true
            else {
                return nil
            }
            return (url, Int64(values.fileSize ?? 0))
        }
    }
}
