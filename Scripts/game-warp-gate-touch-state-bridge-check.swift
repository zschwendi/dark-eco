import Foundation

func inspect(_ snapshot: GOALPadWarpGateTouchSnapshot) {
    let _: ObjCBool = snapshot.valid
    let _: UInt32 = snapshot.sequence
    let _: Int = snapshot.state.rawValue
    let _: Int32 = snapshot.selectedSlot
    let _: UInt32 = snapshot.permittedMask
    let _: ObjCBool = snapshot.selectionMoving
}

let states: [GOALPadWarpGateTouchState] = [
    .unavailable,
    .circleUseAvailable,
    .destinationListActive,
    .transitioning,
]
let snapshot: GOALPadWarpGateTouchSnapshot = GOALPadRuntimeBridge.warpGateTouchSnapshot
inspect(snapshot)
precondition(states.map(\.rawValue) == [0, 1, 2, 3])
