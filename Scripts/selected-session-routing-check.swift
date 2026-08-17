import Foundation

private var failures = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("  ok   \(message)")
    } else {
        print("  FAIL \(message)")
        failures += 1
    }
}

private func source(at path: String) -> String {
    guard let value = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("  FAIL could not read \(path)")
        Foundation.exit(1)
    }
    return value
}

private func section(_ source: String, from start: String, to end: String) -> String {
    guard let lower = source.range(of: start),
          let upper = source.range(of: end, range: lower.upperBound..<source.endIndex) else {
        print("  FAIL could not isolate source section from \(start) to \(end)")
        failures += 1
        return ""
    }
    return String(source[lower.lowerBound..<upper.lowerBound])
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
    print("usage: swift Scripts/selected-session-routing-check.swift <repository-root>")
    Foundation.exit(2)
}

let root = CommandLine.arguments[1]
let session = source(at: root + "/GOALPad/Game/GameSession.swift")
let content = source(at: root + "/GOALPad/ContentView.swift")
let nativeRouting = source(at: root + "/GOALPad/Game/NativeGameRouting.swift")

let initializer = section(session, from: "init(profile: GameDataProfile)", to: "func prepare() async")
check(session.contains("let profile: GameDataProfile")
        && session.contains("let title: GameLibraryTitle")
        && occursInOrder([
            "self.profile = profile",
            "title = profile.title",
            "switch profile.identifier",
            "renderConfiguration = .jak1",
            "presentationProfile = .jak1()",
            "saveProfile = .jak1()",
            "renderConfiguration = .jak2",
            "presentationProfile = .jak2()",
            "saveProfile = .jak2()",
            "settings = RenderSettings(configuration: renderConfiguration)",
            "presentationSettings = PresentationSettings(profile: presentationProfile)",
            "importer = GameDataImporter(profile: profile)",
            "saveSync = SaveSyncController(profile: saveProfile)",
            "dataReport = GameDataReport(profile: profile)",
        ], in: initializer),
      "one immutable selected profile initializes every title-scoped session dependency")

check(session.contains("GameDataLayout.prepare(profile: profile)")
        && occursInOrder(["GameDataInspector.inspect(",
                          "gameDirectory: selectedDirectory, profile: selectedProfile"],
                         in: session)
        && session.contains("GameDataLayout.gameDirectory(\n            for: profile")
        && session.contains("localSavesDirectory = saveProfile.localSavesDirectory")
        && !session.contains("GameDataInspector.inspect()")
        && !session.contains("GameDataProfile.active")
        && !session.contains("GameLibraryTitle.active"),
      "prepare, inspection, data paths, and save paths never consult compile-selected state")

let start = section(session, from: "func start() async", to: "private func bootFinished")
check(occursInOrder([
    "profile.identifier.nativeGameIdentifier",
    "GOALPadRuntimeBridge.selectGame(nativeGameIdentifier)",
    "input.setRumbleEnabled(presentationSettings.rumbleEnabled)",
    "settings.apply()",
    "GOALPadRuntimeBridge.isGameCodeLinked(for: nativeGameIdentifier)",
    "GOALPadRuntimeBridge.startKernel(",
], in: start)
        && start.contains("withDataDirectory: gameDataDirectory.path")
        && start.contains("savesDirectory: localSavesDirectory.path")
        && nativeRouting.contains("case .jak1: .jak1")
        && nativeRouting.contains("case .jak2: .jak2")
        && !start.contains("runtime backend is not connected"),
      "each session selects its isolated runtime before title-aware AOT and kernel startup")
check(start.contains("if profile.identifier == .jak2")
        && start.contains("sessionLog.notice(\"Booting \\(self.title.name")
        && !start.contains("#if GOALPAD_JAK2"),
      "boot timing and logging follow the selected session title")

check(session.contains(".appendingPathComponent(profile.identifier.rawValue, isDirectory: true)")
        && session.contains("\"title=\\(profile.identifier.rawValue)\"")
        && session.contains("\\(self.title.name, privacy: .public) camera diagnostics"),
      "diagnostic storage, payload, and failure copy identify the selected title")

let selection = section(content,
                        from: "private func selectSession(for title: GameLibraryTitle)",
                        to: "private func selectSettingsTitle")
let launcherStart = section(content,
                            from: "private func startGame(_ title: GameLibraryTitle)",
                            to: "/// A session owns title-scoped")
let settingsPresentation = section(content,
                                   from: "private func presentSettings()",
                                   to: "private func openGameSetup")
let setupSelection = section(content,
                             from: "private func openGameSetup(_ title: GameLibraryTitle)",
                             to: "private func startGame")
let returnToLibrary = section(content,
                              from: "private func returnToLibrary()",
                              to: "#if os(visionOS)")
let retirement = section(session,
                         from: "func retireForReplacement()",
                         to: "func presentTouchControlsGuide()")
check(content.contains("@State private var session: GameSession")
        && content.contains("profile: hasJak2DebugPreview ? .jak2 : .jak1")
        && content.contains("openGameSetup: openGameSetup")
        && occursInOrder([
            "importer.cancel()",
            "shutdown()",
            "dataReportRefreshTask?.cancel()",
            "input.stopWatching()",
            "observers.forEach(NotificationCenter.default.removeObserver)",
        ], in: retirement)
        && occursInOrder([
            "GameDataProfile.profile(for: title)",
            "guard session.profile != profile",
            "settingsPresentation = nil",
            "session.retireForReplacement()",
            "session = GameSession(profile: profile)",
        ], in: selection),
      "switching titles replaces the complete title-scoped session before any destination is shown")
check(content.contains("@State private var startAfterPreparationTitle: GameLibraryTitle?")
        && occursInOrder([
            "selectSession(for: title)",
            "launcherDestination = .library",
            "startAfterPreparationTitle = title",
            "let selectedSession = session",
            "Task {",
            "guard selectedSession === session else { return }",
            "await selectedSession.start()",
        ], in: launcherStart)
        && content.contains("if startAfterPreparationTitle == selectedSession.title")
        && content.contains("await selectedSession.start()"),
      "a ready nonselected title replaces its session and starts after preparation instead of opening setup")
check(settingsPresentation.contains("startAfterPreparationTitle = nil")
        && setupSelection.contains("startAfterPreparationTitle = nil")
        && selection.contains("startAfterPreparationTitle = nil")
        && returnToLibrary.contains("startAfterPreparationTitle = nil"),
      "opening settings or setup, returning to the Library, and non-start replacement cancel deferred starts")
check(content.contains("private func selectSettingsTitle(_ title: GameLibraryTitle)")
        && content.contains("guard !session.isRunning")
        && content.contains("presentSettings()")
        && content.contains(".id(presentation.id)"),
      "settings title changes replace the owned session and refresh the sheet identity")
check(content.contains(".task(id: session.title)")
        && content.contains("let selectedSession = session")
        && content.contains("guard selectedSession === session else { return }")
        && content.contains("if selectedSession.title == .jak2")
        && content.contains("await selectedSession.start()")
        && !content.contains("#if GOALPAD_JAK2")
        && !content.contains("GameSession()"),
      "preparation and debug preview startup are session-title selected instead of target selected")

if failures == 0 {
    print("selected session routing checks passed")
} else {
    print("selected session routing checks failed: \(failures)")
    Foundation.exit(1)
}
