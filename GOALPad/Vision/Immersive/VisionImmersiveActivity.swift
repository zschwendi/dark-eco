#if GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE
/// Reduces the window and current immersive renderer into one lifecycle phase. Frame-loop
/// ownership remains a separate concern; this value only answers whether some current scene keeps
/// the game session operational.
nonisolated struct VisionImmersiveActivity: Sendable {
    enum Phase: Equatable, Sendable {
        case active
        case inactive
        case background
    }

    private struct ImmersiveState: Sendable {
        let owner: UInt64
        var isActive: Bool
    }

    private var windowPhase: Phase
    private var immersiveState: ImmersiveState?

    init(windowPhase: Phase = .active) {
        self.windowPhase = windowPhase
    }

    var effectivePhase: Phase {
        immersiveState?.isActive == true ? .active : windowPhase
    }

    /// Starts an owner-scoped opening lease. It is tentatively active so the window becoming
    /// hidden cannot suspend native work before the new LayerRenderer reports its first state.
    mutating func begin(owner: UInt64) {
        immersiveState = ImmersiveState(owner: owner, isActive: true)
    }

    mutating func setWindowPhase(_ phase: Phase) {
        windowPhase = phase
    }

    /// A matching renderer report replaces the tentative opening state. Reports from an older
    /// attempt cannot pause or reactivate the current owner.
    mutating func setRunning(_ active: Bool, owner: UInt64) {
        guard immersiveState?.owner == owner else { return }
        immersiveState?.isActive = active
    }

    /// Ends only the matching attempt and immediately restores the raw window phase.
    mutating func end(owner: UInt64) {
        guard immersiveState?.owner == owner else { return }
        immersiveState = nil
    }
}
#endif
