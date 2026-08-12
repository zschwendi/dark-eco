import Foundation

nonisolated enum GameDataImportSource: Equatable, Sendable {
    case preparedFolder
    case rawISO
    case archivedISO
    case unsupportedArchive

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
