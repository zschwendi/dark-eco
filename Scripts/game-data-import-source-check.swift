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

        if failures == 0 {
            print("game data import source checks passed")
        } else {
            print("game data import source checks failed: \(failures)")
            Foundation.exit(1)
        }
    }
}
