import Foundation

guard CommandLine.arguments.count == 2 else {
    print("usage: swift Scripts/jak2-native-preparation-backend-check.swift <repository-root>")
    Foundation.exit(2)
}

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

func source(_ path: String) throws -> String {
    try String(contentsOf: root.appending(path: path), encoding: .utf8)
}

let adapter = try source("GOALPad/Data/Jak2NativePreparationBackend.swift")
let backend = try source("GOALPad/Data/GameDataNativePreparationBackend.swift")
let importer = try source("GOALPad/Data/GameDataImporter.swift")
let producer = try source("GOALPad/Data/RawISOCandidateProducer.swift")

var failures = 0

func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  ok   \(message)")
    } else {
        print("  FAIL \(message)")
        failures += 1
    }
}

check(!adapter.contains("GOALPAD_JAK2")
        && adapter.contains("#if (os(iOS) || os(visionOS)) && canImport(GOALPadJak2Runtime)")
        && !adapter.contains("#if os(iOS) && canImport(GOALPadJak2Runtime)")
        && adapter.contains("import GOALPadJak2Runtime")
        && adapter.contains("#else"),
      "Dark Eco uses the isolated Jak II framework composer")
check(adapter.contains("profileIdentifier: .jak2")
        && adapter.contains("nativeErrorDomain: appJak2GameDataPreparationErrorDomain")
        && adapter.contains("appJak2GameDataPreparationIsAvailable()"),
      "the production backend is bound to Jak II and its selected native error domain")
check(adapter.contains("AppJak2GameDataPreparationJob(")
        && adapter.contains("AppJak2GameDataPreparationProgress")
        && adapter.contains("AppJak2GameDataPreparationSummary")
        && adapter.contains("summary.archivesWritten")
        && adapter.contains("summary.flatFilesWritten")
        && adapter.contains("summary.fr3FilesWritten"),
      "the adapter consumes the framework job, progress, and summary contract")
check(adapter.contains("isAvailable: { false }")
        && adapter.contains("prepare: { _, _, _, _ in 0 }"),
      "the Jak II backend fails closed when the framework cannot be imported")
check(importer.contains("nativePreparationBackend: GameDataNativePreparationBackend? = nil")
        && importer.contains("productionNativePreparationBackend(for: profile)")
        && importer.contains("case .jak1: .appJak1Composer")
        && importer.contains("case .jak2: .appJak2Composer"),
      "the importer selects its production backend from the explicit profile")
check(backend.contains("let nativeErrorDomain: String?")
        && backend.contains("func ownsNativeFailure(")
        && producer.contains("nativePreparationBackend.ownsNativeFailure(failure)"),
      "native cancellation and error mapping use the selected backend's domain")
check(!adapter.contains("GameDataProfile.active")
        && !importer.contains("GameDataProfile.active"),
      "the adapter and importer do not consult compile-selected profile state")

if failures == 0 {
    print("Jak II native preparation backend source checks passed")
} else {
    print("Jak II native preparation backend source checks failed")
    Foundation.exit(1)
}
