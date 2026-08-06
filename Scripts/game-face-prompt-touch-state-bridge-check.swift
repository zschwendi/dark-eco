import Foundation

func inspect(_ snapshot: GOALPadFacePromptTouchSnapshot) {
    let _: ObjCBool = snapshot.valid
    let _: UInt32 = snapshot.requestedButtons
    let _: UInt32 = snapshot.sequence
}

let snapshot: GOALPadFacePromptTouchSnapshot = GOALPadRuntimeBridge.facePromptTouchSnapshot
inspect(snapshot)

let triangle = UInt32(1 << 12)
let circle = UInt32(1 << 13)
let cross = UInt32(1 << 14)
let square = UInt32(1 << 15)
precondition(triangle | circle | cross | square == 0x0000_f000)
