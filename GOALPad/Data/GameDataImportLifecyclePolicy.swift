import Foundation

nonisolated enum GameDataImportLifecyclePolicy {
    enum SceneActivity: Sendable {
        case active
        case inactive
        case background
    }

    static func shouldKeepDeviceAwake(
        scene: SceneActivity,
        gameplayRunning: Bool,
        importTaskActive: Bool
    ) -> Bool {
        scene == .active && (gameplayRunning || importTaskActive)
    }
}

nonisolated struct GameDataIdleTimerLeaseState: Sendable {
    private var activeOwners: Set<UUID> = []

    var shouldDisableIdleTimer: Bool { !activeOwners.isEmpty }

    mutating func setActive(_ active: Bool, for owner: UUID) {
        if active {
            activeOwners.insert(owner)
        } else {
            activeOwners.remove(owner)
        }
    }
}
