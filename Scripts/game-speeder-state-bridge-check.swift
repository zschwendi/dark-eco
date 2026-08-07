import Foundation

let states: [GOALPadSpeederState] = [.unknown, .notRiding, .riding]
precondition(states.map(\.rawValue) == [0, 1, 2])
print("game speeder-state bridge checks passed")
