import Foundation

private var failures = 0

private func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  ok   \(message)")
    } else {
        print("  FAIL \(message)")
        failures += 1
    }
}

private func keepsAwake(
    _ scene: GameDataImportLifecyclePolicy.SceneActivity,
    gameplay: Bool = false,
    importing: Bool = false
) -> Bool {
    GameDataImportLifecyclePolicy.shouldKeepDeviceAwake(
        scene: scene,
        gameplayRunning: gameplay,
        importTaskActive: importing
    )
}

@main
private struct GameDataImportLifecycleCheck {
    static func main() {
        check(keepsAwake(.active, importing: true),
              "a foreground import prevents automatic device sleep")
        check(keepsAwake(.active, gameplay: true),
              "foreground gameplay keeps the existing wake behavior")
        check(!keepsAwake(.active),
              "an idle foreground library permits automatic sleep")
        check(!keepsAwake(.inactive, importing: true),
              "a transiently inactive scene releases its wake assertion")
        check(!keepsAwake(.background, gameplay: true, importing: true),
              "background always releases the idle-timer assertion")

        if failures == 0 {
            print("game data import lifecycle checks passed")
        } else {
            print("game data import lifecycle checks failed: \(failures)")
            Foundation.exit(1)
        }
    }
}
