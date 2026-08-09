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
        return requestPreparationIfNeeded()
    }

    mutating func requestPreparationIfNeeded() -> Action {
        guard phase == .active, !frameLoopEnabled else { return .none }
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

    mutating func resetForStoppedSession() {
        generation &+= 1
        preparationGeneration = nil
        frameLoopEnabled = phase == .active
    }

    private mutating func beginPreparationIfNeeded() -> Action {
        guard preparationGeneration == nil else { return .none }
        preparationGeneration = generation
        return .prepareForeground(generation: generation)
    }
}

nonisolated enum GameplayStartupPhase: Equatable, Sendable {
    case idle
    case waitingForForegroundPreparation
    case checkingSaves
    case booting

    var isPreparing: Bool {
        switch self {
        case .waitingForForegroundPreparation, .checkingSaves: true
        case .idle, .booting: false
        }
    }
}

nonisolated struct GameplayStartupState: Equatable, Sendable {
    private(set) var phase: GameplayStartupPhase = .idle
    private(set) var generation: UInt64 = 0

    mutating func begin(hasForegroundPreparation: Bool) -> UInt64? {
        guard phase == .idle else { return nil }
        generation &+= 1
        phase = hasForegroundPreparation ? .waitingForForegroundPreparation : .checkingSaves
        return generation
    }

    func owns(generation: UInt64) -> Bool {
        phase != .idle && self.generation == generation
    }

    mutating func move(to phase: GameplayStartupPhase, generation: UInt64) {
        guard owns(generation: generation) else { return }
        self.phase = phase
    }

    mutating func reset() {
        generation &+= 1
        phase = .idle
    }
}

nonisolated enum GameplayStartupReadinessOutcome: Equatable, Sendable {
    case ready
    case saveRecoveryFailed
    case sceneInactive
}

@MainActor
enum GameplayStartupReadiness {
    static func resolve(
        currentForegroundPreparation: () -> Task<Void, Never>?,
        foregroundPreparationSucceeded: () -> Bool,
        isSceneActive: () -> Bool,
        syncBeforeGameplay: () async -> Bool,
        setPhase: (GameplayStartupPhase) -> Void
    ) async -> GameplayStartupReadinessOutcome {
        var waitedForForegroundPreparation = false
        while let task = currentForegroundPreparation() {
            waitedForForegroundPreparation = true
            setPhase(.waitingForForegroundPreparation)
            await task.value
        }

        guard isSceneActive() else { return .sceneInactive }
        if waitedForForegroundPreparation {
            return foregroundPreparationSucceeded() ? .ready : .saveRecoveryFailed
        }

        setPhase(.checkingSaves)
        let savesReady = await syncBeforeGameplay()
        guard isSceneActive() else { return .sceneInactive }
        return savesReady ? .ready : .saveRecoveryFailed
    }
}

nonisolated struct ControlsGuideSuspensionState: Equatable, Sendable {
    private(set) var blocksGameplay = false

    mutating func present() -> Bool {
        guard !blocksGameplay else { return false }
        blocksGameplay = true
        return true
    }

    mutating func dismiss() -> Bool {
        guard blocksGameplay else { return false }
        blocksGameplay = false
        return true
    }

    mutating func reset() {
        blocksGameplay = false
    }
}
