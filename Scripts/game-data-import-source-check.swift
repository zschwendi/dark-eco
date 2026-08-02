import Foundation

@MainActor private var failures = 0

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
        check("/proof/source.zip", expected: .unsupportedArchive, "ZIP is rejected explicitly")
        check("/proof/source.7z", expected: .unsupportedArchive,
              "other archives are rejected explicitly")

        if failures == 0 {
            print("game data import source checks passed")
        } else {
            print("game data import source checks failed: \(failures)")
            Foundation.exit(1)
        }
    }
}
