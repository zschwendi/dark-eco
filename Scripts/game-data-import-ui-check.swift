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

private func occursInOrder(_ needles: [String], in source: String) -> Bool {
    var lower = source.startIndex
    for needle in needles {
        guard let match = source.range(of: needle, range: lower..<source.endIndex) else {
            return false
        }
        lower = match.upperBound
    }
    return true
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
let launcherBackground = source(at: root + "/GOALPad/UI/DarkEcoLauncherBackground.swift")
let content = source(at: root + "/GOALPad/ContentView.swift")
let debugImporter = source(at: root + "/Configuration/GOALPad-Importer-Debug.xcconfig")
let releaseImporter = source(at: root + "/Configuration/GOALPad-Importer-Release.xcconfig")

for (name, configuration) in [("Debug", debugImporter), ("Release", releaseImporter)] {
    check(configuration.contains("GOALPAD_HAS_JAK1_IMPORT_COMPOSER[sdk=iphoneos*] = 1")
            && configuration.contains("GOALPAD_JAK1_SOURCE_OBJECT_PACK_PHASE_INPUT = $(GOALPAD_JAK1_SOURCE_OBJECT_PACK_ROOT)")
            && configuration.contains("OTHER_LDFLAGS[sdk=iphoneos*] = $(inherited) \"$(GOALPAD_JAK1_IMPORT_ARCHIVE)\""),
          "\(name) iPhone and iPad builds include selectable ISO/archive preparation")
}

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
        && occursInOrder([
            "ProgressView(value: progress.overallProgress)",
            "HStack(spacing: 8)",
            "ProgressView()",
            ".controlSize(.small)",
            ".tint(DarkEcoTheme.accent)",
            ".accessibilityHidden(true)",
            "Text(\"\\(progress.overallPercent)% complete\")",
        ], in: view)
        && !view.contains("progress.currentFile")
        && !view.contains("progress.filesCopied")
        && view.contains("GameDataImportPresentation.backgroundGuidance")
        && !view.contains("cancellationGuidance")
        && !presentation.contains("cancellationGuidance")
        && view.contains("if progress.phase != .activatingCandidate")
        && view.contains("Button(role: .destructive)")
        && view.contains("importer.cancel()")
        && view.contains(".foregroundStyle(DarkEcoTheme.danger)")
        && view.contains(".tint(.gray)"),
      "one aggregate bar keeps a purple activity spinner beside percent and a gray, red-text Cancel button")
check(view.contains("case .failed(let failure)")
        && view.contains("failure.recoveryMessage")
        && view.contains("case .cancelling:")
        && view.contains("Cancelling import…")
        && view.contains("case .cancelled:")
        && view.contains("Text(\"Import canceled\")")
        && !view.contains("cancelledRecovery")
        && importer.contains("if Task.isCancelled || error is CancellationError")
        && view.contains("case .failure:"),
      "cancelled imports suppress late errors while real failures remain visible")
check(!view.contains("setupInstructions") && !view.contains("missingList("),
      "the prior long setup wall and archive inventory are removed")
check(view.contains("Text(GameLibraryOfferCopy.importMessage(")
        && view.contains("for: title")
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
check(view.contains("dataReport.status == .ready")
        && view.contains("GameDataImportPresentation.completedStorageGuidance")
        && view.contains(".font(.body)"),
      "complete setup shows ordinary source-cleanup guidance below the imported size")
check(occursInOrder([
            "if showsSourceSelection {",
            "header",
            "dataStatus",
            "importFlow",
            "} else if isImportComplete {",
            "dataStatus",
            "if isImportComplete {",
            "completionActions",
            "} else {",
            "importState",
        ], in: view)
        && view.contains("private var showsSourceSelection: Bool")
        && view.contains("case .scanning, .copying, .cancelling: false")
        && view.contains("case .idle, .finished, .cancelled, .failed: true")
        && view.contains("completionActions")
        && gameData.contains("return \"Import Complete (\\(size))\"")
        && view.contains("Text(\"Play Now\")")
        && view.contains(".frame(height: 88)")
        && view.contains(".tint(DarkEcoTheme.accent)")
        && view.contains(".frame(maxWidth: .infinity, alignment: .center)")
        && view.contains("VStack(alignment: .leading, spacing: isImportComplete ? 32 : 18)")
        && view.contains(".padding(.top, isImportComplete ? 16 : 0)")
        && !view.contains("ProgressView(value: 1)")
        && !view.contains("100% complete"),
      "source guidance appears only while choosing, active import stands alone, and completion keeps its imported-size card")
check(library.contains("title: Text(\"Set Up Game Data\")")
        && library.contains("title: Text(\"Title Isn't Available Yet\")")
        && libraryModel.contains("Provide compatible game data from a copy you legally own.")
        && view.contains("Text(GameLibraryOfferCopy.importMessage(")
        && view.contains("Button(\"Play Now\")")
        && view.contains(".accessibilityLabel(\"Game data import progress\")")
        && view.contains("No source was selected. Choose compatible ")
        && view.contains("Dark Eco could not open that source. Choose another compatible ")
        && !libraryModel.contains("This build accepts"),
      "pre-import setup, play, progress, selection failures, and unsupported alerts stay generic")
check(!content.contains("ToolbarItem(placement: .primaryAction)"),
      "Game Setup has no Settings toolbar action")
check(view.contains("DarkEcoPanel")
        && view.contains("DarkEcoLauncherBackground()")
        && view.contains(".ignoresSafeArea()")
        && launcherBackground.contains("@Environment(\\.accessibilityReduceMotion)")
        && launcherBackground.contains("paused: reduceMotion")
        && theme.contains("accessibilityReduceTransparency")
        && !theme.contains(".animation("),
      "the import keeps readable Dark Eco panels over the accessible liquid backdrop")
check(view.contains("Finishing the current save check before gameplay…")
        && view.contains("Checking saves before gameplay…")
        && view.contains("ProgressView()")
        && view.contains("!dataReport.canLaunchRuntime || isRefreshingDataReport")
        && view.contains("|| session.startupPhase.isPreparing"),
      "Play exposes save preparation and disables duplicate launch requests")
check(library.contains(".preparing(.checkingLocalData)")
        && library.contains(".preparing(.finishingSaveCheck)")
        && library.contains(".preparing(.checkingSaves)")
        && library.contains(".preparing(.importing(progress.overallProgress))")
        && !library.contains(".preparing(.importing(progress.fraction))")
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
        && library.contains("report = await session.refreshDataReport()")
        && library.contains("if report.status == .ready")
        && session.contains("while true {")
        && session.contains("if generation == dataReportRefreshGeneration")
        && session.contains("guard let latestRefreshTask = dataReportRefreshTask else")
        && session.contains("refreshTask = latestRefreshTask")
        && view.contains(".task { _ = await refreshDataReport() }"),
      "launcher uses one inline purple spinner for indeterminate local and save work")
check(view.contains("importer.start(from: source)")
        && occursInOrder([
            "session.saveSync.gameDataImportDidFinish()",
            "await refreshDataReport()",
        ], in: view)
        && importer.contains("onFinish: @escaping @MainActor () async -> Void")
        && importer.contains("await onFinish()\n                state = .finished")
        && importer.contains("state = .cancelling\n        task?.cancel()")
        && importer.contains("if Task.isCancelled || error is CancellationError")
        && importer.contains("state = .cancelled")
        && importer.contains("idleTimerAssertions.setDisabled(active, for: .gameDataImport)")
        && session.contains("DeviceIdleTimerAssertions.shared.setDisabled(disabled, for: .gameplay)")
        && view.contains("if isRefreshingDataReport")
        && view.contains("Text(\"Rechecking…\")")
        && view.contains(".disabled(isRefreshingDataReport)")
        && view.contains(".disabled(!importer.canStart || isRefreshingDataReport)")
        && view.contains("!dataReport.canLaunchRuntime || isRefreshingDataReport"),
      "import completion invalidates stale save snapshots before refreshing launcher readiness")
check(importer.contains("init(\n        profile: GameDataProfile,")
        && importer.contains("self.profile = profile")
        && importer.contains("GameDataInstallWorker(configuration: .app(for: profile))")
        && importer.contains("nativePreparationBackend: GameDataNativePreparationBackend")
        && importer.contains("let nativePreparationBackend = nativePreparationBackend")
        && importer.contains("?? Self.productionNativePreparationBackend(for: profile)")
        && importer.contains("case .jak1: .appJak1Composer")
        && importer.contains("case .jak2: .appJak2Composer")
        && importer.contains("nativePreparationBackend: nativePreparationBackend")
        && importer.contains("rawISOProducer.isAvailable")
        && library.contains("let openGameSetup: (GameLibraryTitle) -> Void")
        && library.contains("let startGame: (GameLibraryTitle) -> Void")
        && library.contains("@State private var titleDataStatuses")
        && library.contains(".task(id: session.title) { await refreshTitleDataStatuses() }")
        && library.contains("dataStatus(for: title) == .ready")
        && library.contains("case .start(let title):\n            startGame(title)")
        && library.contains("case .openSetup(let title):")
        && library.contains("case .verifyData(let title):")
        && content.contains("case gameSetup(GameLibraryTitle)")
        && content.contains("openGameSetup: openGameSetup")
        && content.contains("GameDataSetupView(session: session, title: title)")
        && view.contains("GameDataProfile.profile(for: title)")
        && view.contains("GameDataImporter(profile: profile)")
        && view.contains("importer.canImportRawMedia"),
      "the clicked title and its explicit data profile flow through Library, destination, and setup")
let touchedRoutingSources = [view, importer, library, content]
check(touchedRoutingSources.allSatisfy {
        !$0.contains("GameDataProfile.active")
            && !$0.contains("GameLibraryTitle.active")
            && !$0.contains("activeTitle: .active")
            && !$0.contains("for: .active")
      },
      "touched production routing files no longer read compile-selected active title/profile state")
check(theme.contains("static let background") && theme.contains("static let accent")
        && theme.contains("static let warning") && theme.contains("struct DarkEcoPanel"),
      "the reusable theme exposes surface, accent, warning, and panel seams")

if failures == 0 {
    print("game data import UI checks passed")
} else {
    print("game data import UI checks failed")
    Foundation.exit(1)
}
