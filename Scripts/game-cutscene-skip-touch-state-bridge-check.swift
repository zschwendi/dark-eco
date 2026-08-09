import Foundation

func inspect(_ snapshot: GOALPadCutsceneSkipTouchSnapshot) {
    let _: ObjCBool = snapshot.valid
    let _: UInt32 = snapshot.sequence
    let _: Int = snapshot.state.rawValue
}

let states: [GOALPadCutsceneSkipTouchState] = [
    .unavailable,
    .triangleQueryAvailable,
    .creditsTriangleAvailable,
]
let snapshot: GOALPadCutsceneSkipTouchSnapshot =
    GOALPadRuntimeBridge.cutsceneSkipTouchSnapshot
inspect(snapshot)
precondition(states.map(\.rawValue) == [0, 1, 2])
