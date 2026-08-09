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
