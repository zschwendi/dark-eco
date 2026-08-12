import Foundation

func inspect(_ snapshot: GOALPadGameFrameStateSnapshot) {
    let _: ObjCBool = snapshot.exitToLibraryRequested
    let _: UInt64 = snapshot.framesRun
    let _: GOALPadGameMode = snapshot.gameMode
    let _: GOALPadProgressMenuSnapshot = snapshot.progressMenu
    let _: GOALPadTitleStartState = snapshot.titleStartState
    let _: GOALPadWarpGateTouchSnapshot = snapshot.warpGateTouch
    let _: GOALPadCutsceneSkipTouchSnapshot = snapshot.cutsceneSkipTouch
    let _: GOALPadFacePromptTouchSnapshot = snapshot.facePromptTouch
    let _: GOALPadLookAroundState = snapshot.lookAroundState
    let _: GOALPadSpeederState = snapshot.speederState
}

let snapshot: GOALPadGameFrameStateSnapshot = GOALPadRuntimeBridge.gameFrameStateSnapshot
inspect(snapshot)
