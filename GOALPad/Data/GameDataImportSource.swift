import Foundation
import UniformTypeIdentifiers

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
