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
    do {
        return try String(contentsOfFile: path, encoding: .utf8)
    } catch {
        print("  FAIL could not read \(path): \(error.localizedDescription)")
        Foundation.exit(1)
    }
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
    print("usage: swift Scripts/save-pregame-gate-check.swift <repository-root>")
    Foundation.exit(2)
}

let root = CommandLine.arguments[1]
let controller = source(at: root + "/GOALPad/Saves/SaveSyncController.swift")
let session = source(at: root + "/GOALPad/Game/GameSession.swift")

let gate = section(controller,
                   from: "func syncBeforeGameplay() async -> Bool",
                   to: "func gameplayFrameCompleted()")
check(occursInOrder([
    "setGameplayActive(false)",
    "if isEnabled",
    "await syncNow(mode: .bidirectional)",
    "engine.hasUnsafePendingLocalMutation()",
    "guard !hasUnsafeLocalMutation",
    "return false",
    "return true",
], in: gate), "pregame syncs when enabled, then gates only unsafe local recovery")
check(gate.components(separatedBy: "return false").count - 1 >= 2,
      "pregame rejects both an unsafe journal and an unreadable recovery state")
check(!gate.contains("case .unavailable") && !gate.contains("status == .unavailable"),
      "ordinary iCloud unavailability is not a gameplay rejection")

let start = section(session, from: "func start() async", to: "private func bootFinished")
check(occursInOrder([
    "guard await saveSync.syncBeforeGameplay() else",
    "startupError = Self.saveRecoveryMessage",
    "GOALPadRuntimeBridge.startKernel",
], in: start), "startup rejects unsafe saves before starting the native kernel")
check(session.contains("Open Settings and retry iCloud Saves before playing."),
      "startup exposes a concise Settings recovery action")

let lifecycle = section(session, from: "func scenePhaseChanged", to: "private func resetDisplayTiming")
check(occursInOrder([
    "case .active:",
    "isForeground = false",
    "if isBooting",
    "let savesReady = await saveSync.syncBeforeGameplay()",
    "guard currentScenePhase == .active else { return }",
    "guard savesReady else",
    "audio.suspend()",
    "saveSync.setGameplayActive(kernel != nil)",
    "isForeground = true",
    "audio.resumeIfSuspended()",
], in: lifecycle), "foreground resume stays paused and silent until save recovery is safe")
check(lifecycle.components(separatedBy: "audio.suspend()").count - 1 >= 3,
      "failed, inactive, and background lifecycle routes suspend audio")

if failures == 0 {
    print("save pregame gate checks passed")
} else {
    print("save pregame gate checks failed: \(failures)")
    Foundation.exit(1)
}
