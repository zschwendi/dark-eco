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
let coreHeader = source(at: root + "/GOALPad/Native/GOALPadRuntimeCore.hpp")
let core = source(at: root + "/GOALPad/Native/GOALPadRuntimeCore.cpp")
let bridgeHeader = source(at: root + "/GOALPad/Native/GOALPadRuntimeBridge.h")
let bridge = source(at: root + "/GOALPad/Native/GOALPadRuntimeBridge.mm")

let gate = section(controller,
                   from: "func syncBeforeGameplay() async -> Bool",
                   to: "func gameplayFrameCompleted()")
check(gate.contains("guard supportsManagedSaveSync else { return true }"),
      "a local-only game profile never enters the Jak 1 recovery or cloud merge engine")
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

let syncNow = section(controller, from: "func syncNow", to: "func syncBeforeGameplay")
check(occursInOrder([
    "guard supportsManagedSaveSync, isEnabled else { return }",
    "defer { gameplayReadinessDidChange?() }",
    "await drainPendingSync()",
], in: syncNow), "a completed Settings sync attempt publishes save-readiness changes")

let start = section(session, from: "func start() async", to: "private func bootFinished")
check(occursInOrder([
    "guard await saveSync.syncBeforeGameplay() else",
    "startupError = Self.saveRecoveryMessage",
    "GOALPadRuntimeBridge.startKernel",
    "savesDirectory: SaveDataLayout.localSavesDirectory.path",
], in: start), "startup rejects unsafe saves before starting the native kernel")
check(session.contains("Open Settings and retry iCloud Saves before playing."),
      "startup exposes a concise Settings recovery action")

let shutdown = section(session, from: "func shutdown()", to: "func presentTouchControlsGuide()")
check(occursInOrder([
    "foregroundPreparationTask?.cancel()",
    "foregroundPreparationTask = nil",
    "foregroundPreparationGeneration = nil",
    "lifecycle.resetForStoppedSession()",
    "GOALPadRuntimeBridge.stopKernel()",
], in: shutdown), "shutdown invalidates foreground save work before stopping the kernel")

let finishPreparation = section(session,
                                from: "private func finishForegroundPreparation",
                                to: "private func resetDisplayTiming")
check(occursInOrder([
    "guard foregroundPreparationGeneration == generation",
    "foregroundPreparationTask = nil",
    "foregroundPreparationGeneration = nil",
    "lifecycle.completePreparation",
], in: finishPreparation),
      "a cancelled or superseded foreground task cannot mutate current session ownership")

check(coreHeader.contains(
    "KernelStatus start_kernel(std::string data_directory, std::string saves_directory) noexcept;"),
      "the C++ startup contract requires an explicit saves directory")
check(bridgeHeader.contains(
    "savesDirectory:(NSString *)savesDirectory;"),
      "the Objective-C bridge exposes the saves directory to Swift")
check(bridge.contains(
    "goalpad::start_kernel(path.UTF8String ?: \"\", savePath.UTF8String ?: \"\")"),
      "the Objective-C++ bridge forwards both native paths")

let saveSetter = section(core,
                         from: "static bool set_saves_directory",
                         to: "KernelStatus start_kernel")
check(occursInOrder([
    "path.empty()",
    "goal_kernel_core_set_saves_directory(path.c_str())",
    "goal_kernel_core_saves_directory()",
    "path != accepted_path",
], in: saveSetter), "the runtime rejects empty, failed, or non-exact save paths")
let nativeStart = section(core, from: "KernelStatus start_kernel", to: "void stop_kernel")
check(occursInOrder([
    "goal_kernel_core_initialize()",
    "set_saves_directory(saves_directory, &saves_error)",
    "return failure",
    "goal_kernel_core_get_state",
], in: nativeStart), "the verified save path is installed after init and before kernel use")

let lifecycle = section(session, from: "func scenePhaseChanged", to: "private func resetDisplayTiming")
check(occursInOrder([
    "let action = lifecycle.transition(",
    "case .active:",
    "beginForegroundPreparation(generation: generation)",
    "let savesReady = await saveSync.syncBeforeGameplay()",
    "lifecycle.completePreparation(generation: generation, succeeded: savesReady)",
    "case .resumed:",
    "saveSync.setGameplayActive(kernel != nil)",
    "audio.resumeIfSuspended()",
    "case .failed:",
    "saveSync.setGameplayActive(false)",
    "audio.suspend()",
], in: lifecycle), "foreground resume stays paused and silent until save recovery is safe")
check(!lifecycle.contains("guard !isPreparingGameplay else { return }"),
      "activation cannot be dropped merely because another preparation is in flight")
check(lifecycle.components(separatedBy: "audio.suspend()").count - 1 >= 3,
      "failed, inactive, and background lifecycle routes suspend audio")

let readinessRetry = section(session,
                             from: "private func saveGameplayReadinessDidChange()",
                             to: "private func finishForegroundPreparation")
check(occursInOrder([
    "currentScenePhase == .active",
    "!lifecycle.frameLoopEnabled",
    "!isBooting",
    "!isStartingGameplay",
    "foregroundPreparationTask == nil",
    "!lifecycle.isPreparingForeground",
    "lifecycle.requestPreparationIfNeeded()",
    "beginForegroundPreparation(generation: generation)",
], in: readinessRetry),
      "Settings retry can restart only one active suspended foreground save gate")
check(!readinessRetry.contains("scenePhaseChanged"),
      "save readiness retry does not synthesize a scene transition")

if failures == 0 {
    print("save pregame gate checks passed")
} else {
    print("save pregame gate checks failed: \(failures)")
    Foundation.exit(1)
}
