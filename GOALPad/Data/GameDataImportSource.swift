import Foundation
import UniformTypeIdentifiers

/// Outcome of listing supported media placed directly in the app's own Files-visible folder.
nonisolated enum GameDataLocalMediaListing: Equatable, Sendable {
    case files([URL])
    case empty
    /// The folder holds more items or matches than the bounded scan lists; nothing is offered.
    case tooManyItems
    case unreadable
}

nonisolated enum GameDataImportSource: Equatable, Sendable {
    case preparedFolder
    case rawISO
    case archivedISO
    case unsupportedArchive

    /// The picker dims items by the type their file provider declares, which may be generic
    /// (`public.data`), MIME-derived, or a parent such as `com.pkware.zip-archive` instead of the
    /// extension's preferred type. Disc images and archives therefore stay selectable here, and
    /// `init(url:)` plus the candidate producers remain the authority on what is imported.
    static func pickerContentTypes(rawMediaAvailable: Bool) -> [UTType] {
        rawMediaAvailable ? [.folder, .data, .archive] : [.folder]
    }

    static let localMediaExaminedItemLimit = 256
    static let localMediaMatchLimit = 16

    /// Lists regular, non-hidden ISO/ZIP/7z files stored directly in `root`, so import does not
    /// depend on the system picker accepting a tap on a file. Subdirectories are never entered and
    /// symbolic links are never followed. The scan is bounded: exceeding either limit reports
    /// `.tooManyItems` instead of a partial list. The candidate producers remain the authority on
    /// what is imported. Throws only `CancellationError`.
    static func localMediaListing(
        in root: URL,
        rawMediaAvailable: Bool,
        examinedItemLimit: Int = localMediaExaminedItemLimit,
        matchLimit: Int = localMediaMatchLimit
    ) throws -> GameDataLocalMediaListing {
        guard rawMediaAvailable else { return .empty }
        guard let rootValues = try? root.resourceValues(forKeys: [.isDirectoryKey]),
              rootValues.isDirectory == true else {
            return .unreadable
        }
        var enumerationFailed = false
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in
                enumerationFailed = true
                return false
            }
        ) else {
            return .unreadable
        }
        var examined = 0
        var matches: [URL] = []
        while let child = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            examined += 1
            guard examined <= examinedItemLimit else { return .tooManyItems }
            guard let values = try? child.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
                return .unreadable
            }
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  isLocalMediaName(child.lastPathComponent) else {
                continue
            }
            matches.append(root.appending(path: child.lastPathComponent, directoryHint: .notDirectory))
            guard matches.count <= matchLimit else { return .tooManyItems }
        }
        guard !enumerationFailed else { return .unreadable }
        guard !matches.isEmpty else { return .empty }
        return .files(matches.sorted {
            let lhs = $0.lastPathComponent, rhs = $1.lastPathComponent
            let lhsKey = lhs.lowercased(), rhsKey = rhs.lowercased()
            return lhsKey == rhsKey ? lhs < rhs : lhsKey < rhsKey
        })
    }

    /// Rechecks a previously listed file immediately before import: it must still be a regular,
    /// non-symbolic-link ISO/ZIP/7z directly inside `root`. Returns a fresh URL (no cached
    /// resource values) or `nil` when the entry was removed or replaced. This does not replace
    /// producer validation of the content.
    static func revalidatedLocalMediaFile(_ file: URL, in root: URL) -> URL? {
        let name = file.lastPathComponent
        guard file.deletingLastPathComponent().standardizedFileURL.path
                == root.standardizedFileURL.path,
              isLocalMediaName(name) else {
            return nil
        }
        let fresh = root.appending(path: name, directoryHint: .notDirectory)
        guard let values = try? fresh.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true else {
            return nil
        }
        return fresh
    }

    private static func isLocalMediaName(_ name: String) -> Bool {
        guard !name.hasPrefix("."), !name.contains("/") else { return false }
        switch GameDataImportSource(url: URL(fileURLWithPath: "/" + name, isDirectory: false)) {
        case .rawISO, .archivedISO: return true
        case .preparedFolder, .unsupportedArchive: return false
        }
    }

    init(url: URL) {
        if url.hasDirectoryPath {
            self = .preparedFolder
            return
        }

        switch url.pathExtension.lowercased() {
        case "iso":
            self = .rawISO
        case "zip", "7z":
            self = .archivedISO
        case "bz2", "gz", "rar", "tar", "tgz", "xz":
            self = .unsupportedArchive
        default:
            self = .preparedFolder
        }
    }
}
