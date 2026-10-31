nonisolated struct PresentationOwnershipState<Owner: Hashable & Sendable>: Equatable, Sendable {
    private(set) var owner: Owner?
    private var registrationOrder: [Owner] = []
    private var activeOwners: Set<Owner> = []

    mutating func register(_ candidate: Owner) {
        guard !registrationOrder.contains(candidate) else { return }
        registrationOrder.append(candidate)
    }

    mutating func activate(_ candidate: Owner) {
        register(candidate)
        activeOwners.insert(candidate)
        if owner == nil {
            owner = candidate
        }
    }

    mutating func deactivate(_ candidate: Owner) {
        activeOwners.remove(candidate)
        if owner == candidate {
            selectNextOwner()
        }
    }

    mutating func unregister(_ candidate: Owner) {
        activeOwners.remove(candidate)
        registrationOrder.removeAll { $0 == candidate }
        if owner == candidate {
            selectNextOwner()
        }
    }

    func isOwner(_ candidate: Owner) -> Bool {
        owner == candidate
    }

    private mutating func selectNextOwner() {
        owner = registrationOrder.first { activeOwners.contains($0) }
    }
}
