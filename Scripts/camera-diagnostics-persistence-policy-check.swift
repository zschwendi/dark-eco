import Foundation
import Darwin

private var failures = 0

private func check(_ condition: Bool, _ description: String) {
    if condition {
        print("ok   \(description)")
    } else {
        print("FAIL \(description)")
        failures += 1
    }
}

private func decision(
    forced: Bool = false,
    periodic: Bool = false,
    other: Bool = false,
    tail: UInt64 = 0,
    persisted: UInt64 = 0,
    attempted: UInt64 = 0,
    frame: UInt64 = 1_000,
    lastWrite: UInt64 = 900,
    interval: UInt64 = 120
) -> Bool {
    CameraDiagnosticsPersistencePolicy.shouldPersist(
        forced: forced,
        periodic: periodic,
        hasImmediateNonCameraEvidence: other,
        completedTailTriggerFrame: tail,
        lastPersistedTailTriggerFrame: persisted,
        lastAttemptedTailTriggerFrame: attempted,
        currentEngineFrame: frame,
        lastTailWriteEngineFrame: lastWrite,
        minimumTailFrameInterval: interval)
}

@main
private enum CameraDiagnosticsPersistencePolicyCheck {
    static func main() {
        check(!decision(), "ordinary frames do not write diagnostics")
        check(!decision(tail: 200, persisted: 200),
              "an already persisted tail does not rewrite")
        check(!decision(tail: 201, persisted: 200, attempted: 201),
              "a failed tail write is not retried every frame")
        check(decision(tail: 201), "the first completed tail persists immediately")
        check(!decision(tail: 301, persisted: 201, frame: 1_019, lastWrite: 900),
              "a replacement tail is throttled before the frame interval")
        check(decision(tail: 301, persisted: 201, frame: 1_020, lastWrite: 900),
              "a replacement tail persists after the frame interval")
        check(decision(forced: true, tail: 301, persisted: 201, attempted: 301),
              "forced lifecycle capture always persists the latest completed tail")
        check(decision(periodic: true), "periodic diagnostics still persist")
        check(decision(other: true), "non-camera diagnostic evidence still persists immediately")
        check(CameraDiagnosticsPersistencePolicy.hasUnattemptedEvidence(
            total: 1, persisted: 0, attempted: 0),
              "new weighted-skin evidence persists immediately")
        check(!CameraDiagnosticsPersistencePolicy.hasUnattemptedEvidence(
            total: 1, persisted: 0, attempted: 1),
              "a failed weighted-skin write is not retried every frame")
        check(CameraDiagnosticsPersistencePolicy.hasUnattemptedEvidence(
            total: 2, persisted: 0, attempted: 1),
              "a new weighted-skin issue category or later episode can trigger a new write")
        exit(failures == 0 ? 0 : 1)
    }
}
