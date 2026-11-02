import Foundation
import UniformTypeIdentifiers

@MainActor private var failures = 0

@MainActor private func expect(_ condition: Bool, _ message: String) {
    if condition {
        print("  ok   \(message)")
    } else {
        print("  FAIL \(message)")
        failures += 1
    }
}

/// The document picker enables an item when its declared type conforms to an allowed type.
private func pickerEnables(_ type: UTType, rawMediaAvailable: Bool) -> Bool {
    GameDataImportSource.pickerContentTypes(rawMediaAvailable: rawMediaAvailable)
        .contains { type.conforms(to: $0) }
}

@MainActor private func checkPickerContentTypes() {
    let providerTypes: [(String, UTType?)] = [
        ("ISO by extension", UTType(filenameExtension: "iso")),
        ("ZIP", .zip),
        ("7z by extension", UTType(filenameExtension: "7z")),
        ("generic provider data", .data),
        ("parent PKWARE ZIP", UTType("com.pkware.zip-archive")),
        ("generic disk image", .diskImage),
        ("MIME-derived ISO", UTType(mimeType: "application/x-iso9660-image")),
        ("MIME-derived CD image", UTType(mimeType: "application/x-cd-image")),
        ("octet-stream", UTType(mimeType: "application/octet-stream")),
        ("undeclared extension", UTType(filenameExtension: "goalpad-undeclared")),
    ]
    for (name, type) in providerTypes {
        guard let type else {
            expect(false, "\(name) resolves to a type")
            continue
        }
        expect(pickerEnables(type, rawMediaAvailable: true),
               "\(name) (\(type.identifier)) is selectable when disc preparation is available")
        expect(!pickerEnables(type, rawMediaAvailable: false),
               "\(name) (\(type.identifier)) stays dimmed without disc preparation")
    }
    expect(pickerEnables(.folder, rawMediaAvailable: true)
            && pickerEnables(.folder, rawMediaAvailable: false),
           "prepared folders are selectable in both modes")
    expect(GameDataImportSource.pickerContentTypes(rawMediaAvailable: false) == [.folder],
           "without disc preparation the picker offers prepared folders only")
}

private func makeFixture(_ entries: [String], directories: [String] = []) throws -> URL {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appending(
        path: "goalpad-local-media-\(UUID().uuidString)", directoryHint: .isDirectory)
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    for directory in directories {
        try manager.createDirectory(at: root.appending(path: directory, directoryHint: .isDirectory),
                                    withIntermediateDirectories: true)
    }
    for name in entries {
        try Data("synthetic".utf8).write(to: root.appending(path: name))
    }
    return root
}

private func listing(_ root: URL, rawMediaAvailable: Bool = true,
                     examined: Int = GameDataImportSource.localMediaExaminedItemLimit,
                     matches: Int = GameDataImportSource.localMediaMatchLimit)
    -> GameDataLocalMediaListing? {
    try? GameDataImportSource.localMediaListing(in: root, rawMediaAvailable: rawMediaAvailable,
                                                examinedItemLimit: examined, matchLimit: matches)
}

@MainActor private func checkLocalMediaListing() {
    let manager = FileManager.default
    do {
        let root = try makeFixture(
            ["a.iso", "B.ZIP", "c.7z", "D.ISO", "e.rar", "notes.txt", ".hidden.iso", "jak1/nested.iso"],
            directories: ["jak1", "folder.iso"])
        defer { try? manager.removeItem(at: root) }
        try manager.createSymbolicLink(at: root.appending(path: "link.iso"),
                                       withDestinationURL: root.appending(path: "a.iso"))
        try manager.createSymbolicLink(at: root.appending(path: "dirlink.iso"),
                                       withDestinationURL: root.appending(path: "jak1"))
        guard case .files(let files)? = listing(root) else {
            expect(false, "a populated folder lists files")
            return
        }
        expect(files.map(\.lastPathComponent) == ["a.iso", "B.ZIP", "c.7z", "D.ISO"],
               "only direct regular ISO/ZIP/7z files (any case) are listed; nested, hidden, "
               + "directory, symlink, and unsupported entries are excluded")
        expect(files.map { GameDataImportSource(url: $0) } == [.rawISO, .archivedISO, .archivedISO, .rawISO],
               "listed files route to the existing raw and archived ISO producers")
        expect(listing(root, rawMediaAvailable: false) == .empty,
               "nothing is listed without disc preparation")
        expect(listing(root, examined: 5) == .tooManyItems,
               "exceeding the examined-item limit lists nothing instead of a partial set")
        expect(listing(root, matches: 3) == .tooManyItems,
               "exceeding the match limit lists nothing instead of a partial set")

        let a = root.appending(path: "a.iso")
        expect(GameDataImportSource.revalidatedLocalMediaFile(a, in: root) != nil,
               "an unchanged listed file revalidates")
        expect(GameDataImportSource.revalidatedLocalMediaFile(
                root.appending(path: "jak1/nested.iso"), in: root) == nil,
               "a nested file never revalidates as a direct child")
        expect(GameDataImportSource.revalidatedLocalMediaFile(
                root.appending(path: "e.rar"), in: root) == nil,
               "an unsupported format never revalidates")
        try manager.removeItem(at: a)
        expect(GameDataImportSource.revalidatedLocalMediaFile(a, in: root) == nil,
               "a removed file fails revalidation")
        try manager.createSymbolicLink(at: a, withDestinationURL: root.appending(path: "c.7z"))
        expect(GameDataImportSource.revalidatedLocalMediaFile(a, in: root) == nil,
               "a file replaced by a symbolic link fails revalidation")
        try manager.removeItem(at: a)
        try manager.createDirectory(at: a, withIntermediateDirectories: false)
        expect(GameDataImportSource.revalidatedLocalMediaFile(a, in: root) == nil,
               "a file replaced by a directory fails revalidation")

        let empty = try makeFixture(["notes.txt"], directories: ["jak1"])
        defer { try? manager.removeItem(at: empty) }
        expect(listing(empty) == .empty, "a folder without supported files reports empty")
        expect(listing(empty.appending(path: "missing", directoryHint: .isDirectory)) == .unreadable,
               "a missing folder is reported as unreadable, not empty")
        expect(listing(empty.appending(path: "notes.txt")) == .unreadable,
               "a non-directory root is reported as unreadable")
    } catch {
        expect(false, "local media fixtures are created: \(error)")
    }
}

@MainActor private func check(_ path: String, isDirectory: Bool = false,
                              expected: GameDataImportSource, _ message: String) {
    let source = URL(fileURLWithPath: path, isDirectory: isDirectory)
    if GameDataImportSource(url: source) == expected {
        print("  ok   \(message)")
    } else {
        print("  FAIL \(message)")
        failures += 1
    }
}

@main
private struct GameDataImportSourceCheck {
    @MainActor static func main() {
        check("/proof/source.iso", expected: .rawISO,
              "a lowercase ISO uses native preparation")
        check("/proof/source.ISO", expected: .rawISO, "ISO matching is case-insensitive")
        check("/proof/prepared", isDirectory: true, expected: .preparedFolder,
              "a prepared folder keeps the existing producer")
        check("/proof/prepared.iso", isDirectory: true, expected: .preparedFolder,
              "a folder name that ends in ISO remains a folder")
        check("/proof/source.zip", expected: .archivedISO, "ZIP uses local ISO extraction")
        check("/proof/source.ZIP", expected: .archivedISO, "ZIP matching is case-insensitive")
        check("/proof/source.7z", expected: .archivedISO, "7z uses local ISO extraction")
        check("/proof/source.7Z", expected: .archivedISO, "7z matching is case-insensitive")
        check("/proof/source.rar", expected: .unsupportedArchive,
              "unsupported archives are rejected explicitly")
        checkPickerContentTypes()
        checkLocalMediaListing()

        if failures == 0 {
            print("game data import source checks passed")
        } else {
            print("game data import source checks failed: \(failures)")
            Foundation.exit(1)
        }
    }
}
