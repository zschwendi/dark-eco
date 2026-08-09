import Foundation

private var failures = 0

private func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  ok   \(message)")
    } else {
        print("  FAIL \(message)")
        failures += 1
    }
}

private func source(at path: String) -> String {
    guard let source = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("  FAIL could not read \(path)")
        Foundation.exit(1)
    }
    return source
}

guard CommandLine.arguments.count == 2 else {
    print("usage: swift Scripts/game-data-import-ui-check.swift <repository-root>")
    Foundation.exit(2)
}

let root = CommandLine.arguments[1]
let view = source(at: root + "/GOALPad/Data/GameDataSetupView.swift")
let content = source(at: root + "/GOALPad/ContentView.swift")
let importer = source(at: root + "/GOALPad/Data/GameDataImporter.swift")
let rawProducer = source(at: root + "/GOALPad/Data/RawISOCandidateProducer.swift")
let presentation = source(at: root + "/GOALPad/Data/GameDataImportPresentation.swift")
let theme = source(at: root + "/GOALPad/UI/DarkEcoTheme.swift")

check(view.contains("GameDataImportPresentation.acceptedSources(")
        && view.contains("for: profile,")
        && view.contains("session.importer.canImportRawMedia")
        && view.contains("return [.folder, rawISOType, .zip]")
        && view.contains("return [.folder]"),
      "the import copy and picker both follow the selected profile's raw-ISO capability gate")
check(presentation.contains("ZIP archive with exactly one ISO")
        && !presentation.contains("ZIP64")
        && view.contains("if canImportRawISO {")
        && view.contains("Raw ISO and ZIP sources are unavailable for")
        && view.contains("profile.preparedFolderName"),
      "the concise ZIP note appears only when raw-media preparation is available")
check(view.contains("Label(\"Import \\(profile.displayName)\"")
        && view.contains("Button(\"Choose \\(profile.displayName) data…\"")
        && view.contains("if profile.supportsRuntimeLaunch")
        && view.contains("initial New Game path")
        && view.contains("Full-game data completeness and playability remain unverified")
        && presentation.contains("profile.readinessContractLabel")
        && presentation.contains("experimental launch contract")
        && presentation.contains("full-game completeness is not verified)"),
      "the setup shell names the bounded Jak II launch contract without overstating completeness")
check(content.contains("BootingView(gameName: session.importer.profile.displayName)")
        && content.contains("Text(\"Booting \\(gameName)\")")
        && !content.contains("Text(\"Booting Jak 1\")")
        && content.contains(".background(Color.black.ignoresSafeArea())"),
      "the runtime shell names the selected game and keeps unused portrait space black")
check(importer.contains("profile.supportsRawMediaPreparation && RawISOCandidateProducer.isAvailable(for: profile)")
        && !importer.contains("profile.supportsRawMediaPreparation && RawISOCandidateProducer.isAvailable()")
        && importer.contains("case .rawISO where canImportRawMedia:")
        && importer.contains("case .zippedISO where canImportRawMedia:")
        && importer.contains("prepared OpenGOAL \\(profile.preparedFolderName) folder"),
      "raw ISO and ZIP routing consults the selected profile's composer resources")
check(rawProducer.contains("case .sourcePackFailed, .projectResourcesFailed:")
        && rawProducer.contains("code: .appResourcesUnavailable"),
      "source-pack and project-resource verification failures stay app-resource failures")
check(view.contains("GameDataImportPresentation.backgroundGuidance(phaseLabel: progress.phase.label)")
        && view.contains("GameDataImportPresentation.cancellationGuidance(")
        && view.contains("if progress.phase != .activatingCandidate"),
      "one import component names each active phase, foreground safety, and cancellation boundary")
check(view.contains("case .failed(let failure)")
        && view.contains("failure.recoveryMessage")
        && view.contains("case .cancelled:")
        && view.contains("GameDataImportPresentation.cancelledRecovery")
        && view.contains("case .failure(let error):"),
      "importer, picker, cancellation, and recovery failures remain visible")
check(!view.contains("setupInstructions") && !view.contains("missingList("),
      "the prior long setup wall and archive inventory are removed")
check(view.contains("DarkEcoPanel") && view.contains("DarkEcoTheme.background")
        && theme.contains("accessibilityReduceTransparency")
        && !theme.contains(".animation("),
      "the import uses centralized Dark Eco surfaces without motion effects")
check(theme.contains("static let background") && theme.contains("static let accent")
        && theme.contains("static let warning") && theme.contains("struct DarkEcoPanel"),
      "the reusable theme exposes surface, accent, warning, and panel seams")

if failures == 0 {
    print("game data import UI checks passed")
} else {
    print("game data import UI checks failed")
    Foundation.exit(1)
}
