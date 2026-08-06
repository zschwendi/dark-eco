import Foundation

func inspect(_ snapshot: GOALPadProgressMenuSnapshot) {
    let _: ObjCBool = snapshot.available
    let _: Int = snapshot.screen.rawValue
    let _: Int32 = snapshot.optionIndex
    let _: ObjCBool = snapshot.selectedOption
    let _: ObjCBool = snapshot.inTransition
}

let snapshot: GOALPadProgressMenuSnapshot = GOALPadRuntimeBridge.progressMenuSnapshot
inspect(snapshot)
