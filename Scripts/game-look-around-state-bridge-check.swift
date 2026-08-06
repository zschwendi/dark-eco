import Foundation

let states: [GOALPadLookAroundState] = [.unknown, .normal, .firstPerson]
precondition(states.map(\.rawValue) == [0, 1, 2])
print("game look-around bridge checks passed")
