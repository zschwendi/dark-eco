struct ControllerMenuStickSample: Equatable, Sendable {
    let x: Float
    let y: Float

    fileprivate var magnitudeSquared: Float { x * x + y * y }
}

/// Converts a physical left stick into one held PS2 D-pad direction while a native menu owns
/// input. The held result is returned on every poll so the game's existing pad repeat policy stays
/// authoritative; this reducer does not queue or synthesize timed button edges.
struct ControllerMenuNavigation: Sendable {
    enum Direction: Equatable, Sendable {
        case up
        case down
        case left
        case right
    }

    struct Configuration: Equatable, Sendable {
        var pressThreshold: Float = 0.55
        var releaseThreshold: Float = 0.35

        static let standard = Self()
    }

    private let configuration: Configuration
    private(set) var heldDirection: Direction?

    init(configuration: Configuration = .standard) {
        precondition(configuration.pressThreshold > configuration.releaseThreshold)
        precondition(configuration.releaseThreshold >= 0)
        self.configuration = configuration
    }

    mutating func update(primary: ControllerMenuStickSample?,
                         fallback: ControllerMenuStickSample?,
                         enabled: Bool) -> Direction? {
        guard enabled, let sample = Self.preferred(primary: primary, fallback: fallback) else {
            reset()
            return nil
        }
        guard sample.x.isFinite, sample.y.isFinite else {
            reset()
            return nil
        }

        let pressed = Self.direction(of: sample, beyond: configuration.pressThreshold)
        if let heldDirection {
            if let pressed, pressed != heldDirection {
                self.heldDirection = pressed
            } else if Self.component(of: sample, along: heldDirection)
                        < configuration.releaseThreshold {
                self.heldDirection = pressed
            }
        } else {
            heldDirection = pressed
        }
        return heldDirection
    }

    mutating func reset() {
        heldDirection = nil
    }

    private static func preferred(primary: ControllerMenuStickSample?,
                                  fallback: ControllerMenuStickSample?)
        -> ControllerMenuStickSample? {
        switch (primary, fallback) {
        case (.none, .none): nil
        case (.some(let sample), .none), (.none, .some(let sample)): sample
        case (.some(let primary), .some(let fallback)):
            fallback.magnitudeSquared > primary.magnitudeSquared ? fallback : primary
        }
    }

    /// Ties deliberately choose the vertical axis, matching the established touch D-pad reducer.
    private static func direction(of sample: ControllerMenuStickSample,
                                  beyond threshold: Float) -> Direction? {
        let horizontal = abs(sample.x) > abs(sample.y)
        let along = horizontal ? sample.x : sample.y
        guard abs(along) >= threshold else { return nil }
        if horizontal { return along < 0 ? .left : .right }
        return along < 0 ? .down : .up
    }

    private static func component(of sample: ControllerMenuStickSample,
                                  along direction: Direction) -> Float {
        switch direction {
        case .up: sample.y
        case .down: -sample.y
        case .left: -sample.x
        case .right: sample.x
        }
    }
}
