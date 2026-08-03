struct CameraDiagnosticsPersistencePolicy {
    static let minimumCompletedTailFrameInterval: UInt64 = 120

    static func hasUnattemptedEvidence(total: UInt64,
                                       persisted: UInt64,
                                       attempted: UInt64) -> Bool {
        total > persisted && total > attempted
    }

    static func shouldPersist(
        forced: Bool,
        periodic: Bool,
        hasImmediateNonCameraEvidence: Bool,
        completedTailTriggerFrame: UInt64,
        lastPersistedTailTriggerFrame: UInt64,
        lastAttemptedTailTriggerFrame: UInt64,
        currentEngineFrame: UInt64,
        lastTailWriteEngineFrame: UInt64,
        minimumTailFrameInterval: UInt64 = minimumCompletedTailFrameInterval
    ) -> Bool {
        if forced || periodic || hasImmediateNonCameraEvidence {
            return true
        }
        guard completedTailTriggerFrame != 0,
              completedTailTriggerFrame != lastPersistedTailTriggerFrame,
              completedTailTriggerFrame != lastAttemptedTailTriggerFrame else {
            return false
        }
        if lastPersistedTailTriggerFrame == 0 {
            return true
        }
        guard currentEngineFrame >= lastTailWriteEngineFrame else {
            return false
        }
        return currentEngineFrame - lastTailWriteEngineFrame >= minimumTailFrameInterval
    }
}
