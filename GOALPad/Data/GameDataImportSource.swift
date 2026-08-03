import Foundation

nonisolated enum GameDataImportSource: Equatable, Sendable {
    case preparedFolder
    case rawISO
    case zippedISO
    case unsupportedArchive

    init(url: URL) {
        if url.hasDirectoryPath {
            self = .preparedFolder
            return
        }

        switch url.pathExtension.lowercased() {
        case "iso":
            self = .rawISO
        case "zip":
            self = .zippedISO
        case "7z", "bz2", "gz", "rar", "tar", "tgz", "xz":
            self = .unsupportedArchive
        default:
            self = .preparedFolder
        }
    }
}
