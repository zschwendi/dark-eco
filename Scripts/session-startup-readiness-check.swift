import Foundation

@MainActor private var failures = 0

@MainActor
private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("  ok   \(message)")
    } else {
        print("  FAIL \(message)")
        failures += 1
    }
}

private actor PauseGate {
    private var isPaused = false
    private var continuation: CheckedContinuation<Void, Never>?

    func pause() async {
        isPaused = true
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilPaused() async {
        while !isPaused { await Task.yield() }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class StartupHarness {
    let gate = PauseGate()
    var state = GameplayStartupState()
    var foregroundTask: Task<Void, Never>?
    var foregroundSucceeded = false
    var sceneActive = true
    var saveSyncResult = true
    var saveSyncCalls = 0
    var bootStarts = 0
    var lastOutcome: GameplayStartupReadinessOutcome?

    func beginForegroundPreparation(succeeds: Bool) {
        foregroundTask = Task { [self] in
            await gate.pause()
            foregroundSucceeded = succeeds
            foregroundTask = nil
        }
    }

    func requestStart() async {
        guard let generation = state.begin(
            hasForegroundPreparation: foregroundTask != nil
        ) else { return }
        let outcome = await GameplayStartupReadiness.resolve(
            currentForegroundPreparation: { self.foregroundTask },
            foregroundPreparationSucceeded: { self.foregroundSucceeded },
            isSceneActive: { self.sceneActive },
            syncBeforeGameplay: {
                self.saveSyncCalls += 1
                return self.saveSyncResult
            },
            setPhase: { self.state.move(to: $0, generation: generation) }
        )
        guard state.owns(generation: generation) else { return }
        lastOutcome = outcome
        if outcome == .ready {
            bootStarts += 1
            state.move(to: .booting, generation: generation)
        } else {
            state.reset()
        }
    }
}

@MainActor
private func localDataPublishesBeforeCloudPreparation() async {
    print("local prepared-data readiness is independent of paused cloud preparation")
    let gate = PauseGate()
    var events: [String] = []
    let preparation = Task { @MainActor in
        await GameSessionPreparation.run(
            refreshDataReport: { events.append("data") },
            prepareSettings: { events.append("settings") },
            prepareSaves: {
                events.append("saves")
                await gate.pause()
                events.append("saves-finished")
            }
        )
    }

    await gate.waitUntilPaused()
    check(events.first == "data", "the local data report publishes before either cloud gate")
    check(!events.contains("saves-finished"), "cloud save preparation remains paused")
    await gate.release()
    await preparation.value
    check(events.contains("settings") && events.contains("saves-finished"),
          "both cloud preparations still complete after local readiness")
}

@MainActor
private func queuedStartSucceedsExactlyOnce() async {
    print("a Play request waits for foreground save preparation and starts exactly once")
    let harness = StartupHarness()
    harness.beginForegroundPreparation(succeeds: true)
    let first = Task { @MainActor in await harness.requestStart() }
    await harness.gate.waitUntilPaused()
    check(harness.state.phase == .waitingForForegroundPreparation,
          "the accepted Play request exposes foreground-waiting state")

    await harness.requestStart()
    check(harness.bootStarts == 0, "a duplicate tap cannot pass the in-flight request")
    await harness.gate.release()
    await first.value
    check(harness.lastOutcome == .ready && harness.bootStarts == 1,
          "successful foreground preparation continues to one boot")
    check(harness.saveSyncCalls == 0,
          "the completed foreground save gate is reused instead of running twice")
}

@MainActor
private func queuedStartFailsWithSaveRecovery() async {
    print("a failed foreground save gate rejects the retained Play request")
    let harness = StartupHarness()
    harness.beginForegroundPreparation(succeeds: false)
    let request = Task { @MainActor in await harness.requestStart() }
    await harness.gate.waitUntilPaused()
    await harness.gate.release()
    await request.value
    check(harness.lastOutcome == .saveRecoveryFailed,
          "the failed foreground gate has a distinct outcome")
    check(harness.bootStarts == 0 && harness.state.phase == .idle,
          "save recovery failure never starts the kernel and releases request ownership")
}

@MainActor
private func queuedStartFailsWhenSceneLeavesActiveState() async {
    print("a queued Play request cannot start after the scene becomes inactive")
    let harness = StartupHarness()
    harness.beginForegroundPreparation(succeeds: true)
    let request = Task { @MainActor in await harness.requestStart() }
    await harness.gate.waitUntilPaused()
    harness.sceneActive = false
    await harness.gate.release()
    await request.value
    check(harness.lastOutcome == .sceneInactive,
          "scene loss after a successful gate has a distinct outcome")
    check(harness.bootStarts == 0 && harness.state.phase == .idle,
          "backgrounding prevents kernel start and releases request ownership")
}

@MainActor
private func directStartKeepsThePregameSaveGate() async {
    print("a direct Play request retains the mandatory pregame save gate")
    let harness = StartupHarness()
    await harness.requestStart()
    check(harness.saveSyncCalls == 1, "an idle foreground request checks saves exactly once")
    check(harness.lastOutcome == .ready && harness.bootStarts == 1,
          "a successful direct save gate permits exactly one boot")
}

@main
private struct SessionStartupReadinessCheck {
    static func main() async {
        await localDataPublishesBeforeCloudPreparation()
        await queuedStartSucceedsExactlyOnce()
        await queuedStartFailsWithSaveRecovery()
        await queuedStartFailsWhenSceneLeavesActiveState()
        await directStartKeepsThePregameSaveGate()

        if failures == 0 {
            print("session startup readiness checks passed")
        } else {
            print("session startup readiness checks failed: \(failures)")
            Foundation.exit(1)
        }
    }
}
