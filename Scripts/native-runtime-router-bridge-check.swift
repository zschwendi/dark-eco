import Foundation

func checkNativeRuntimeRouterAPI(_ game: GOALPadGameIdentifier) {
    _ = GOALPadRuntimeBridge.selectGame(game)
    _ = GOALPadRuntimeBridge.activeGameIdentifier
    _ = GOALPadRuntimeBridge.isGameCodeLinked(for: game)
}

checkNativeRuntimeRouterAPI(.jak1)
checkNativeRuntimeRouterAPI(.jak2)
