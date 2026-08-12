import Foundation

nonisolated struct GameplaySaveGenerationState {
    private(set) var observed: UInt64 = 0

    mutating func reset() {
        observed = 0
    }

    mutating func observe(_ generation: UInt64) -> Bool {
        guard generation != observed else { return false }
        observed = generation
        return true
    }
}
