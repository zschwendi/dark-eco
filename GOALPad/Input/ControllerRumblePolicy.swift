import Foundation

nonisolated struct ControllerRumblePolicy: Equatable, Sendable {
    let smallMotorGain: Float
    let largeMotorSharpness: Float?
    let smallMotorSharpness: Float?
    let preservesFinitePulseTail: Bool

    static let standard = ControllerRumblePolicy(
        smallMotorGain: 1,
        largeMotorSharpness: nil,
        smallMotorSharpness: nil,
        preservesFinitePulseTail: false
    )

    static let dualSenseHandles = ControllerRumblePolicy(
        smallMotorGain: 2,
        largeMotorSharpness: 0,
        smallMotorSharpness: 1,
        preservesFinitePulseTail: true
    )

    func largeIntensity(_ value: UInt8) -> Float {
        value == 0 ? 0 : 1
    }

    func smallIntensity(_ value: UInt8) -> Float {
        min(1, Float(value) / 255 * smallMotorGain)
    }
}

nonisolated struct ControllerRumbleFrameDecision: Equatable, Sendable {
    let publishesChange: Bool
    let refreshesController: Bool

    init(previousLarge: UInt8, previousSmall: UInt8,
         nextLarge: UInt8, nextSmall: UInt8) {
        publishesChange = previousLarge != nextLarge || previousSmall != nextSmall
        refreshesController = publishesChange || nextLarge != 0 || nextSmall != 0
    }
}
