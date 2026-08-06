nonisolated struct GameplayLifecycleState: Equatable, Sendable {
    enum Phase: String, Equatable, Sendable {
        case active
        case inactive
        case background
    }

    enum Action: Equatable, Sendable {
        case none
        case prepareForeground(generation: UInt64)
        case resumed
        case failed
        case suspended
    }

    private(set) var phase: Phase = .active
    private(set) var generation: UInt64 = 0
    private(set) var preparationGeneration: UInt64?
    private(set) var frameLoopEnabled = true

    var isPreparingForeground: Bool { preparationGeneration != nil }

    mutating func transition(to newPhase: Phase, prepareOnActivation: Bool) -> Action {
        if phase != newPhase {
            generation &+= 1
            phase = newPhase
        }

        guard phase == .active else {
            frameLoopEnabled = false
            return .none
        }
        guard !frameLoopEnabled, prepareOnActivation else { return .none }
        return beginPreparationIfNeeded()
    }

    mutating func completePreparation(generation completedGeneration: UInt64,
                                      succeeded: Bool) -> Action {
        guard preparationGeneration == completedGeneration else { return .none }
        preparationGeneration = nil

        guard phase == .active else {
            frameLoopEnabled = false
            return .suspended
        }
        guard completedGeneration == generation else {
            return beginPreparationIfNeeded()
        }

        frameLoopEnabled = succeeded
        return succeeded ? .resumed : .failed
    }

    @discardableResult
    mutating func activateWithoutPreparation() -> Bool {
        guard phase == .active, preparationGeneration == nil else {
            frameLoopEnabled = false
            return false
        }
        frameLoopEnabled = true
        return true
    }

    private mutating func beginPreparationIfNeeded() -> Action {
        guard preparationGeneration == nil else { return .none }
        preparationGeneration = generation
        return .prepareForeground(generation: generation)
    }
}
