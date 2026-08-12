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
let importer = source(at: root + "/GOALPad/Data/GameDataImporter.swift")
let session = source(at: root + "/GOALPad/Game/GameSession.swift")
let library = source(at: root + "/GOALPad/Library/GameLibraryView.swift")
let libraryModel = source(at: root + "/GOALPad/Library/GameLibrary.swift")
let presentation = source(at: root + "/GOALPad/Data/GameDataImportPresentation.swift")
let gameData = source(at: root + "/GOALPad/Data/GameData.swift")
let theme = source(at: root + "/GOALPad/UI/DarkEcoTheme.swift")
let content = source(at: root + "/GOALPad/ContentView.swift")

check(view.contains("GameDataImportPresentation.acceptedSources(")
        && view.contains("rawISOAvailable: canImportRawISO")
        && view.contains("return [.folder, rawISOType, .zip] +")
        && view.contains("sevenZipType")
        && view.contains("return [.folder]"),
      "the import copy and picker both follow the actual raw-ISO capability gate")
check(view.contains("ForEach(GameDataImportPresentation.acceptedSources(")
        && view.contains("Text(\"•\")")
        && presentation.contains("\"ISO\"")
        && presentation.contains("\"ZIP or 7z with exactly one ISO\"")
        && presentation.contains("\"Prepared game data folder\""),
      "supported sources render as separate bullets in the published order")
check(view.contains("ProgressView(value: progress.overallProgress)")
        && view.contains("progress.overallPercent")
        && view.contains("progress.phase.playerLabel")
        && !view.contains("progress.currentFile")
        && !view.contains("progress.filesCopied")
        && view.contains("GameDataImportPresentation.backgroundGuidance")
        && view.contains("GameDataImportPresentation.cancellationGuidance(")
        && view.contains("if progress.phase != .activatingCandidate"),
      "one aggregate progress bar keeps player-facing status, foreground safety, and cancellation boundaries")
check(view.contains("case .failed(let failure)")
        && view.contains("failure.recoveryMessage")
        && view.contains("case .cancelling:")
        && view.contains("Cancelling import…")
        && view.contains("case .cancelled:")
        && view.contains("Text(\"Import canceled\")")
        && !view.contains("cancelledRecovery")
        && importer.contains("if Task.isCancelled || error is CancellationError")
        && view.contains("case .failure(let error):"),
      "cancelled imports suppress late errors while real failures remain visible")
check(!view.contains("setupInstructions") && !view.contains("missingList("),
      "the prior long setup wall and archive inventory are removed")
check(view.contains("Text(\"Choose a compatible source from a copy you own.\")")
        && view.contains(".foregroundStyle(.secondary)")
        && !view.contains("Label(\"Add game data\"")
        && view.contains("Supported sources")
        && view.contains("Choose game data…")
        && !view.contains("private candidate")
        && !view.contains("Prepared \\(copied) file(s)")
        && !view.contains("Game data stays on this device.")
        && !view.contains("A ZIP must contain exactly one ISO.")
        && !view.contains("Dark Eco checks your selection before it uses it."),
      "setup keeps the short subtext and status while removing redundant copy")
check(view.contains("session.dataReport.status == .ready")
        && view.contains("GameDataImportPresentation.completedStorageGuidance")
        && view.contains(".font(.body)"),
      "complete setup shows ordinary source-cleanup guidance below the imported size")
check(view.contains("if !isImportComplete")
        && view.contains("if isImportComplete")
        && view.contains("completionActions")
        && gameData.contains("return \"Import Complete (\\(size))\"")
        && view.contains("Text(\"Play Now\")")
        && view.contains(".frame(height: 88)")
        && view.contains(".tint(DarkEcoTheme.accent)")
        && view.contains(".frame(maxWidth: .infinity, alignment: .center)")
        && !view.contains("ProgressView(value: 1)")
        && !view.contains("100% complete"),
      "completed setup collapses to the imported size and centered double-height Play Now action")
check(library.contains("title: Text(\"Set Up \\(GameLibraryTitle.jak1.name)\")")
        && libraryModel.contains("Provide game data from a copy of")
        && !libraryModel.contains("This build accepts"),
      "the library entry keeps the exact setup title and ownership sentence only")
check(!content.contains("ToolbarItem(placement: .primaryAction)"),
      "Game Setup has no Settings toolbar action")
check(view.contains("DarkEcoPanel") && view.contains("DarkEcoTheme.background")
        && theme.contains("accessibilityReduceTransparency")
        && !theme.contains(".animation("),
      "the import uses centralized Dark Eco surfaces without motion effects")
check(view.contains("Finishing the current save check before gameplay…")
        && view.contains("Checking saves before gameplay…")
        && view.contains("ProgressView()")
        && view.contains("!session.dataReport.canBoot || session.isRefreshingDataReport")
        && view.contains("|| session.startupPhase.isPreparing"),
      "Play exposes save preparation and disables duplicate launch requests")
check(library.contains(".preparing(.checkingLocalData)")
        && library.contains(".preparing(.finishingSaveCheck)")
        && library.contains(".preparing(.checkingSaves)")
        && library.contains("if case .preparing(let preparation) = state, preparation.fraction == nil")
        && library.contains("ProgressView()")
        && library.contains("Text(stateLabel)")
        && library.contains(".tint(DarkEcoTheme.accent)")
        && libraryModel.contains("case .checkingLocalData: \"Checking Local Data\"")
        && libraryModel.contains("case .cancellingImport: \"Cancelling Import\"")
        && libraryModel.contains("case .finishingSaveCheck: \"Finishing Save Check\"")
        && libraryModel.contains("case .checkingSaves: \"Checking Saves\"")
        && libraryModel.contains("case .preparing(.importing), .preparing(.cancellingImport):")
        && libraryModel.contains("case .preparing(.finishingSaveCheck), .preparing(.checkingSaves):")
        && library.contains("let report = await session.refreshDataReport()")
        && library.contains("if report.status == .ready")
        && session.contains("while true {")
        && session.contains("if generation == dataReportRefreshGeneration")
        && session.contains("guard let latestRefreshTask = dataReportRefreshTask else")
        && session.contains("refreshTask = latestRefreshTask")
        && view.contains(".task { _ = await session.refreshDataReport() }"),
      "launcher uses one inline purple spinner for indeterminate local and save work")
check(view.contains("session.importer.start(from: source) {\n                    await session.refreshDataReport()")
        && importer.contains("onFinish: @escaping @MainActor () async -> Void")
        && importer.contains("await onFinish()\n                state = .finished")
        && importer.contains("state = .cancelling\n        task?.cancel()")
        && importer.contains("if Task.isCancelled || error is CancellationError")
        && importer.contains("state = .cancelled")
        && importer.contains("idleTimerAssertions.setDisabled(active, for: .gameDataImport)")
        && session.contains("DeviceIdleTimerAssertions.shared.setDisabled(disabled, for: .gameplay)")
        && view.contains("if session.isRefreshingDataReport")
        && view.contains("Text(\"Rechecking…\")")
        && view.contains(".disabled(session.isRefreshingDataReport)")
        && view.contains(".disabled(!session.importer.canStart || session.isRefreshingDataReport)")
        && view.contains("!session.dataReport.canBoot || session.isRefreshingDataReport"),
      "import completion awaits launcher readiness and Recheck exposes its active work")
check(theme.contains("static let background") && theme.contains("static let accent")
        && theme.contains("static let warning") && theme.contains("struct DarkEcoPanel"),
      "the reusable theme exposes surface, accent, warning, and panel seams")

if failures == 0 {
    print("game data import UI checks passed")
} else {
    print("game data import UI checks failed")
    Foundation.exit(1)
}
