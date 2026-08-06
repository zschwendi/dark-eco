import Foundation

func inspect(_ snapshot: GOALPadProgressMenuSnapshot) {
    let _: ObjCBool = snapshot.available
    let _: Int = snapshot.screen.rawValue
    let _: Int32 = snapshot.optionIndex
    let _: ObjCBool = snapshot.selectedOption
    let _: ObjCBool = snapshot.inTransition
    let _: ObjCBool = snapshot.navigationAvailable
    let _: Int = snapshot.startingScreen.rawValue
    let _: ObjCBool = snapshot.canExitWithStart
    let _: ObjCBool = snapshot.canGoBack
}

let snapshot: GOALPadProgressMenuSnapshot = GOALPadRuntimeBridge.progressMenuSnapshot
inspect(snapshot)
let _: GOALPadTitleStartState = GOALPadRuntimeBridge.titleStartState
