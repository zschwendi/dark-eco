import Foundation
import simd

struct SpatialAttackGesture: OptionSet, Equatable, Sendable {
    let rawValue: UInt8

    static let punch = Self(rawValue: 1 << 0)
    static let spin = Self(rawValue: 1 << 1)
    static let jump = Self(rawValue: 1 << 2)
}

struct SpatialSampleTimestampGate: Sendable {
    private var lastAcceptedTimestamp: TimeInterval?

    mutating func accepts(_ timestamp: TimeInterval) -> Bool {
        guard timestamp.isFinite else { return false }
        if let lastAcceptedTimestamp, timestamp <= lastAcceptedTimestamp { return false }
        lastAcceptedTimestamp = timestamp
        return true
    }
}

/// Expresses each measured world-space accessory delta in the current reference rotation basis.
/// With the headset as reference, integrating those deltas gives the recognizer stable
/// head-relative axes without turning head motion itself into controller motion. With the
/// accessory's own aim pose as reference, the axes follow the controller's pointing ray.
struct SpatialAccessoryMotionProjector: Sendable {
    private var previousWorldPosition: SIMD3<Float>?
    private var integratedReferenceAxesPosition: SIMD3<Float> = .zero

    mutating func update(originFromAccessory: simd_float4x4,
                         originFromReference: simd_float4x4) -> SIMD3<Float>? {
        guard spatialMatrixIsFinite(originFromAccessory),
              spatialMatrixIsFinite(originFromReference) else {
            reset()
            return nil
        }
        let accessoryTranslation = originFromAccessory.columns.3
        let worldPosition = SIMD3(accessoryTranslation.x,
                                  accessoryTranslation.y,
                                  accessoryTranslation.z)
        guard let previousWorldPosition else {
            self.previousWorldPosition = worldPosition
            return integratedReferenceAxesPosition
        }
        self.previousWorldPosition = worldPosition

        let referenceX = originFromReference.columns.0
        let referenceY = originFromReference.columns.1
        let referenceZ = originFromReference.columns.2
        let worldFromReferenceRotation = simd_float3x3(
            SIMD3(referenceX.x, referenceX.y, referenceX.z),
            SIMD3(referenceY.x, referenceY.y, referenceY.z),
            SIMD3(referenceZ.x, referenceZ.y, referenceZ.z))
        let determinant = simd_determinant(worldFromReferenceRotation)
        guard determinant.isFinite, abs(determinant) > 0.5 else {
            reset()
            return nil
        }
        let referenceAxesDelta = simd_inverse(worldFromReferenceRotation)
            * (worldPosition - previousWorldPosition)
        guard referenceAxesDelta.x.isFinite, referenceAxesDelta.y.isFinite,
              referenceAxesDelta.z.isFinite else {
            reset()
            return nil
        }
        integratedReferenceAxesPosition += referenceAxesDelta
        return integratedReferenceAxesPosition
    }

    mutating func reset() {
        previousWorldPosition = nil
        integratedReferenceAxesPosition = .zero
    }
}

/// A pure recognizer for experimental PS VR2 Sense attacks. Positions are accumulated accessory
/// movement in headset axes: +X is right, +Y is up, and -Z is forward.
struct SpatialAttackGestureRecognizer: Sendable {
    struct Configuration: Equatable, Sendable {
        var maximumSampleGap: TimeInterval = 0.12
        var attackCooldown: TimeInterval = 0.35

        var jabWindow: TimeInterval = 0.24
        var jabMinimumDistance: Float = 0.10
        var jabMinimumSpeed: Float = 0.65
        var jabMaximumCrossAxisRatio: Float = 0.55
        var jabRetractionToRearm: Float = 0.055

        /// One gentle sideways-and-back motion: a 25-30 mm leg at about 0.12-0.15 m/s each way,
        /// with a pause of up to about 0.2 s at the turn, clears these floors. Each leg's speed is
        /// measured over its own movement, so the pause never counts against the return. Tracking
        /// jitter, idle drift, sways under about 0.09 m/s, and twitches under 22 mm do not.
        var shakeStrokeWindow: TimeInterval = 0.28
        var shakeReversalWindow: TimeInterval = 0.55
        var shakeMinimumStrokeDistance: Float = 0.022
        var shakeMinimumSpeed: Float = 0.12
        var shakeMaximumCrossAxisRatio: Float = 0.65
        /// The return must cover this share of the outward leg, so a long reach that only bounces
        /// back a little is not "sideways and back".
        var shakeMinimumReturnFraction: Float = 0.5

        static let experimental = Self()
    }

    struct Sample: Equatable, Sendable {
        let timestamp: TimeInterval
        let position: SIMD3<Float>
        let isTracked: Bool
    }

    private struct ShakeStroke: Sendable {
        var direction: Float
        /// Lateral position where the outward leg began.
        var start: Float
        var extreme: Sample
        var qualifiedAt: TimeInterval
        /// Candidate starts for the return since the extreme, so a pause at the turn never counts.
        var returnStarts: [Sample]
    }

    private let configuration: Configuration
    private var recentJabSamples: [Sample] = []
    private var lastSample: Sample?
    private var lastAttackTime = -TimeInterval.infinity
    private var jabTriggerForward: Float?
    /// Candidate starts for the first shake stroke, so time spent still before it never counts.
    private var recentShakeSamples: [Sample] = []
    private var shakeStroke: ShakeStroke?

    init(configuration: Configuration = .experimental) {
        self.configuration = configuration
    }

    mutating func update(_ sample: Sample) -> SpatialAttackGesture {
        guard sample.isTracked, sample.timestamp.isFinite,
              sample.position.x.isFinite, sample.position.y.isFinite,
              sample.position.z.isFinite else {
            reset()
            return []
        }
        if let lastSample {
            let elapsed = sample.timestamp - lastSample.timestamp
            guard elapsed > 0, elapsed <= configuration.maximumSampleGap else {
                resetMotion(keepingCooldown: true)
                seed(with: sample)
                return []
            }
        } else {
            seed(with: sample)
            return []
        }

        defer { lastSample = sample }
        rearmJabIfRetracted(sample)
        guard sample.timestamp - lastAttackTime >= configuration.attackCooldown else {
            trimJabHistory(at: sample.timestamp)
            return []
        }

        if recognizeJab(sample) {
            lastAttackTime = sample.timestamp
            jabTriggerForward = forwardPosition(sample)
            resetShake(at: sample)
            return .punch
        }
        if recognizeShake(sample) {
            lastAttackTime = sample.timestamp
            recentJabSamples = [sample]
            return .spin
        }
        return []
    }

    mutating func reset() {
        resetMotion(keepingCooldown: false)
    }

    private mutating func seed(with sample: Sample) {
        lastSample = sample
        recentJabSamples = [sample]
        recentShakeSamples = [sample]
        shakeStroke = nil
    }

    private mutating func resetMotion(keepingCooldown: Bool) {
        recentJabSamples.removeAll(keepingCapacity: true)
        lastSample = nil
        jabTriggerForward = nil
        recentShakeSamples.removeAll(keepingCapacity: true)
        shakeStroke = nil
        if !keepingCooldown { lastAttackTime = -TimeInterval.infinity }
    }

    private mutating func rearmJabIfRetracted(_ sample: Sample) {
        guard let jabTriggerForward,
              sample.timestamp - lastAttackTime >= configuration.attackCooldown,
              forwardPosition(sample) <= jabTriggerForward - configuration.jabRetractionToRearm
        else { return }
        self.jabTriggerForward = nil
        recentJabSamples = [sample]
    }

    private mutating func trimJabHistory(at timestamp: TimeInterval) {
        recentJabSamples.removeAll {
            timestamp - $0.timestamp > configuration.jabWindow
        }
    }

    private mutating func recognizeJab(_ sample: Sample) -> Bool {
        trimJabHistory(at: sample.timestamp)
        defer { recentJabSamples.append(sample) }
        guard jabTriggerForward == nil, let previous = lastSample else { return false }

        let stepDuration = sample.timestamp - previous.timestamp
        let stepForward = forwardPosition(sample) - forwardPosition(previous)
        guard stepForward > 0,
              stepForward / Float(stepDuration) >= configuration.jabMinimumSpeed else {
            return false
        }

        guard let origin = recentJabSamples.min(by: {
            forwardPosition($0) < forwardPosition($1)
        }) else { return false }
        let duration = sample.timestamp - origin.timestamp
        let forward = forwardPosition(sample) - forwardPosition(origin)
        guard duration > 0, duration <= configuration.jabWindow,
              forward >= configuration.jabMinimumDistance,
              forward / Float(duration) >= configuration.jabMinimumSpeed else { return false }

        let crossAxis = hypotf(sample.position.x - origin.position.x,
                               sample.position.y - origin.position.y)
        return crossAxis <= forward * configuration.jabMaximumCrossAxisRatio
    }

    private mutating func recognizeShake(_ sample: Sample) -> Bool {
        if var stroke = shakeStroke {
            guard sample.timestamp - stroke.qualifiedAt <= configuration.shakeReversalWindow else {
                resetShake(at: sample)
                return false
            }
            if (sample.position.x - stroke.extreme.position.x) * stroke.direction > 0 {
                stroke.extreme = sample
                stroke.returnStarts = [sample]
                shakeStroke = stroke
                return false
            }
            let amplitude = abs(stroke.extreme.position.x - stroke.start)
            let returned = abs(sample.position.x - stroke.extreme.position.x)
            stroke.returnStarts.removeAll {
                sample.timestamp - $0.timestamp > configuration.shakeStrokeWindow
            }
            if returned >= amplitude * configuration.shakeMinimumReturnFraction,
               stroke.returnStarts.contains(where: {
                   ($0.position.x - sample.position.x) * stroke.direction > 0
                       && isShakeStroke(from: $0, to: sample)
               }) {
                resetShake(at: sample)
                return true
            }
            stroke.returnStarts.append(sample)
            shakeStroke = stroke
            return false
        }

        recentShakeSamples.removeAll {
            sample.timestamp - $0.timestamp > configuration.shakeStrokeWindow
        }
        defer { recentShakeSamples.append(sample) }
        guard let origin = recentShakeSamples.last(where: {
            isShakeStroke(from: $0, to: sample)
        }) else { return false }
        let direction: Float = sample.position.x < origin.position.x ? -1 : 1
        let start = recentShakeSamples.reduce(origin.position.x * direction) {
            min($0, $1.position.x * direction)
        } * direction
        shakeStroke = ShakeStroke(direction: direction, start: start, extreme: sample,
                                  qualifiedAt: sample.timestamp, returnStarts: [sample])
        return false
    }

    private func isShakeStroke(from origin: Sample, to sample: Sample) -> Bool {
        let distance = abs(sample.position.x - origin.position.x)
        let elapsed = sample.timestamp - origin.timestamp
        return distance >= configuration.shakeMinimumStrokeDistance && elapsed > 0
            && distance / Float(elapsed) >= configuration.shakeMinimumSpeed
            && shakeCrossAxisDistance(from: origin, to: sample)
                <= distance * configuration.shakeMaximumCrossAxisRatio
    }

    private mutating func resetShake(at sample: Sample) {
        recentShakeSamples.removeAll(keepingCapacity: true)
        recentShakeSamples.append(sample)
        shakeStroke = nil
    }

    private func forwardPosition(_ sample: Sample) -> Float {
        -sample.position.z
    }

    private func shakeCrossAxisDistance(from start: Sample, to end: Sample) -> Float {
        hypotf(end.position.y - start.position.y,
               end.position.z - start.position.z)
    }
}

struct SpatialAttackGestureBank: Sendable {
    private var recognizers: [UUID: SpatialAttackGestureRecognizer] = [:]

    mutating func update(accessoryID: UUID,
                         sample: SpatialAttackGestureRecognizer.Sample) -> SpatialAttackGesture {
        var recognizer = recognizers[accessoryID] ?? SpatialAttackGestureRecognizer()
        let attacks = recognizer.update(sample)
        recognizers[accessoryID] = recognizer
        return attacks
    }

    mutating func reset(accessoryID: UUID) {
        recognizers.removeValue(forKey: accessoryID)
    }

    mutating func retain(accessoryIDs: Set<UUID>) {
        recognizers = recognizers.filter { accessoryIDs.contains($0.key) }
    }

    mutating func reset() {
        recognizers.removeAll(keepingCapacity: true)
    }
}

/// A pure recognizer for a quick upward lift of two distinct controllers together. Heights are
/// measured accessory-origin translations in ARKit's gravity-aligned origin space (+Y up), so
/// controller pitch or roll and head pose never change which way is up.
struct SpatialPairedLiftRecognizer: Sendable {
    struct Configuration: Equatable, Sendable {
        var maximumSampleGap: TimeInterval = 0.12
        var liftWindow: TimeInterval = 0.25
        var liftMinimumRise: Float = 0.09
        var liftMinimumSpeed: Float = 0.60
        var liftMaximumHorizontalRatio: Float = 0.60
        var pairWindow: TimeInterval = 0.10
        var rearmDrop: Float = 0.05

        static let experimental = Self()
    }

    enum Event: Equatable, Sendable {
        case none
        case jump
        /// A participant's motion became discontinuous; every partial lift was discarded.
        case interrupted
    }

    private struct Sample: Sendable {
        let timestamp: TimeInterval
        let position: SIMD3<Float>
    }

    private struct Track: Sendable {
        var recent: [Sample]
        var liftStartedAt: TimeInterval?
        /// While set, this controller already spent its lift and must lower by `rearmDrop`.
        var spentPeak: Float?
    }

    private let configuration: Configuration
    private var tracks: [UUID: Track] = [:]

    init(configuration: Configuration = .experimental) {
        self.configuration = configuration
    }

    mutating func update(accessoryID: UUID, timestamp: TimeInterval,
                         originFromAccessory: simd_float4x4) -> Event {
        let translation = originFromAccessory.columns.3
        let sample = Sample(timestamp: timestamp,
                            position: SIMD3(translation.x, translation.y, translation.z))
        guard timestamp.isFinite, spatialMatrixIsFinite(originFromAccessory) else {
            reset()
            return .interrupted
        }
        guard var track = tracks[accessoryID], let previous = track.recent.last else {
            tracks[accessoryID] = Track(recent: [sample])
            return .none
        }
        let elapsed = timestamp - previous.timestamp
        guard elapsed > 0, elapsed <= configuration.maximumSampleGap else {
            reset()
            tracks[accessoryID] = Track(recent: [sample])
            return .interrupted
        }
        defer { tracks[accessoryID] = track }

        if let peak = track.spentPeak {
            track = sample.position.y <= peak - configuration.rearmDrop
                ? Track(recent: [sample])
                : Track(recent: [sample], spentPeak: max(peak, sample.position.y))
            return .none
        }
        track.recent.removeAll { timestamp - $0.timestamp > configuration.liftWindow }
        track.recent.append(sample)
        if let start = track.liftStartedAt, timestamp - start > configuration.pairWindow {
            track = Track(recent: [sample], spentPeak: highest(track.recent))
            return .none
        }
        if track.liftStartedAt == nil, isLifting(track.recent, previous: previous, to: sample) {
            track.liftStartedAt = timestamp
        }
        guard let start = track.liftStartedAt,
              let partnerID = tracks.first(where: { id, other in
                  guard id != accessoryID, other.spentPeak == nil,
                        let otherStart = other.liftStartedAt else { return false }
                  return abs(start - otherStart) <= configuration.pairWindow
              })?.key,
              let partner = tracks[partnerID] else { return .none }
        track = Track(recent: [sample], spentPeak: highest(track.recent))
        tracks[partnerID] = Track(recent: Array(partner.recent.suffix(1)),
                                  spentPeak: highest(partner.recent))
        return .jump
    }

    func tracksAccessory(outside accessoryIDs: Set<UUID>) -> Bool {
        tracks.keys.contains { !accessoryIDs.contains($0) }
    }

    mutating func reset() {
        tracks.removeAll(keepingCapacity: true)
    }

    private func isLifting(_ recent: [Sample], previous: Sample, to sample: Sample) -> Bool {
        let stepRise = sample.position.y - previous.position.y
        guard stepRise / Float(sample.timestamp - previous.timestamp)
                >= configuration.liftMinimumSpeed,
              let origin = recent.min(by: { $0.position.y < $1.position.y }) else { return false }
        let rise = sample.position.y - origin.position.y
        let duration = sample.timestamp - origin.timestamp
        guard duration > 0, rise >= configuration.liftMinimumRise,
              rise / Float(duration) >= configuration.liftMinimumSpeed else { return false }
        let horizontal = hypotf(sample.position.x - origin.position.x,
                                sample.position.z - origin.position.z)
        return horizontal <= rise * configuration.liftMaximumHorizontalRatio
    }

    private func highest(_ samples: [Sample]) -> Float {
        samples.map(\.position.y).max() ?? -.infinity
    }
}

/// The measured pose that supplies jab and shake axes. Exactly one reference owns recognition at
/// a time; changing it discards every partial gesture so one physical motion cannot emit twice.
enum SpatialGestureReference: Equatable, Sendable {
    /// The immersive compositor's timestamped headset pose.
    case head
    /// Each controller's own aim pose: -Z along its pointing ray and +X to its right. The ordinary
    /// window has no headset pose, so a jab is a thrust along the controller's pointing ray.
    case accessoryAim
}

/// One measured accessory anchor, reduced to the values the router consumes.
struct SpatialAccessoryPoseSample: Sendable {
    let accessoryID: UUID
    let timestamp: TimeInterval
    let isPositionTracked: Bool
    let originFromAccessory: simd_float4x4
    /// Nil when the reference does not need it or the accessory publishes no aim location.
    let originFromAim: simd_float4x4?
}

/// Routes measured accessory poses into one-shot attacks and paired-lift jumps for a single active
/// reference. Samples must be position-tracked, finite, fresh against the caller's clock, and newer
/// than the last one consumed for that accessory; anything else clears that accessory's partial
/// gesture and every partial or pending jump.
struct SpatialAttackMotionRouter: Sendable {
    static let maximumSampleAge: TimeInterval = 0.12
    /// Enough for a native double jump; older undelivered jumps are dropped, never replayed.
    static let maximumPendingJumps = 2
    static let maximumJumpLatency: TimeInterval = 0.25
    /// Jak 1 scales jump height while Cross stays held for about 0.1 s, so each jump is a brief
    /// timed hold in consumer time rather than a one-frame tap.
    static let jumpHoldDuration: TimeInterval = 0.12

    private(set) var reference: SpatialGestureReference?
    private var lastClockTimestamp: TimeInterval?
    private var projectors: [UUID: SpatialAccessoryMotionProjector] = [:]
    private var timestampGates: [UUID: SpatialSampleTimestampGate] = [:]
    private var recognizers = SpatialAttackGestureBank()
    private var pendingAttacks: [UUID: SpatialAttackGesture] = [:]
    private var lifts = SpatialPairedLiftRecognizer()
    private var pendingJumps: [TimeInterval] = []
    private var jumpHoldDeadline: TimeInterval?
    private var jumpHeldLastFrame = false
    private var lastConsumeTime: TimeInterval?

    /// Immersive presentation: `clock` is the compositor time of `originFromDevice`.
    mutating func update(originFromDevice: simd_float4x4?, clock: TimeInterval,
                         poses: [SpatialAccessoryPoseSample]) {
        select(.head)
        guard let originFromDevice, spatialMatrixIsFinite(originFromDevice) else {
            reset()
            return
        }
        ingest(clock: clock, poses: poses) { pose in
            (pose.originFromAccessory, originFromDevice)
        }
    }

    /// Ordinary window: `clock` is the current host time in the anchors' timebase. Attack position
    /// and axes both come from the aim pose, so attacks assume no headset pose or gravity
    /// direction; the paired-lift jump uses the anchor origin's height.
    mutating func updateAccessoryAim(clock: TimeInterval, poses: [SpatialAccessoryPoseSample]) {
        select(.accessoryAim)
        ingest(clock: clock, poses: poses) { pose in
            pose.originFromAim.map { ($0, $0) }
        }
    }

    /// Returns each pending attack once. Suppressed frames and a reference that did not produce
    /// the pending motion discard all partial gestures instead of delivering them later.
    /// `.jump` stays set from its first frame until `now` reaches `jumpHoldDuration` later, and at
    /// least one released frame separates consecutive jumps. `now` is the consumer's host time;
    /// without it the latest ingest clock is used, which only advances while poses arrive.
    mutating func consume(allowed: Bool, reference: SpatialGestureReference,
                          now: TimeInterval? = nil) -> SpatialAttackGesture {
        guard allowed, self.reference == reference else {
            reset()
            jumpHeldLastFrame = false
            return []
        }
        var gestures = pendingAttacks.values.reduce(into: SpatialAttackGesture()) {
            $0.formUnion($1)
        }
        pendingAttacks.removeAll(keepingCapacity: true)
        guard let time = now ?? lastClockTimestamp, time.isFinite,
              time >= lastConsumeTime ?? -.infinity else {
            resetLifts()
            lastConsumeTime = nil
            jumpHeldLastFrame = false
            return gestures
        }
        lastConsumeTime = time
        pendingJumps.removeAll { time - $0 > Self.maximumJumpLatency }
        if let jumpHoldDeadline, time >= jumpHoldDeadline { self.jumpHoldDeadline = nil }
        if jumpHoldDeadline == nil, !jumpHeldLastFrame, !pendingJumps.isEmpty {
            pendingJumps.removeFirst()
            jumpHoldDeadline = time + Self.jumpHoldDuration
        }
        jumpHeldLastFrame = jumpHoldDeadline != nil
        if jumpHeldLastFrame { gestures.insert(.jump) }
        return gestures
    }

    mutating func reset() {
        projectors.removeAll(keepingCapacity: true)
        timestampGates.removeAll(keepingCapacity: true)
        recognizers.reset()
        pendingAttacks.removeAll(keepingCapacity: true)
        resetLifts()
        lastClockTimestamp = nil
    }

    private mutating func select(_ reference: SpatialGestureReference) {
        guard self.reference != reference else { return }
        reset()
        self.reference = reference
    }

    private mutating func reset(accessoryID: UUID) {
        projectors.removeValue(forKey: accessoryID)
        timestampGates.removeValue(forKey: accessoryID)
        recognizers.reset(accessoryID: accessoryID)
        pendingAttacks.removeValue(forKey: accessoryID)
        resetLifts()
    }

    private mutating func resetLifts() {
        lifts.reset()
        cancelJumps()
    }

    /// Ends any held jump now and drops queued ones; the next frame is always released.
    private mutating func cancelJumps() {
        pendingJumps.removeAll(keepingCapacity: true)
        jumpHoldDeadline = nil
    }

    private mutating func ingest(
        clock: TimeInterval, poses: [SpatialAccessoryPoseSample],
        frames: (SpatialAccessoryPoseSample) -> (accessory: simd_float4x4,
                                                 reference: simd_float4x4)?
    ) {
        guard clock.isFinite else {
            reset()
            return
        }
        if let lastClockTimestamp,
           clock <= lastClockTimestamp || clock - lastClockTimestamp > Self.maximumSampleAge {
            reset()
        }
        lastClockTimestamp = clock
        pendingJumps.removeAll { clock - $0 > Self.maximumJumpLatency }

        let activeIDs = Set(poses.map(\.accessoryID))
        projectors = projectors.filter { activeIDs.contains($0.key) }
        timestampGates = timestampGates.filter { activeIDs.contains($0.key) }
        pendingAttacks = pendingAttacks.filter { activeIDs.contains($0.key) }
        recognizers.retain(accessoryIDs: activeIDs)
        if lifts.tracksAccessory(outside: activeIDs) { resetLifts() }

        for pose in poses {
            let id = pose.accessoryID
            guard pose.isPositionTracked, pose.timestamp.isFinite,
                  abs(clock - pose.timestamp) <= Self.maximumSampleAge,
                  let frame = frames(pose) else {
                reset(accessoryID: id)
                continue
            }
            var timestampGate = timestampGates[id] ?? SpatialSampleTimestampGate()
            guard timestampGate.accepts(pose.timestamp) else { continue }
            timestampGates[id] = timestampGate
            var projector = projectors[id] ?? SpatialAccessoryMotionProjector()
            guard let position = projector.update(originFromAccessory: frame.accessory,
                                                  originFromReference: frame.reference) else {
                reset(accessoryID: id)
                continue
            }
            projectors[id] = projector
            pendingAttacks[id, default: []].formUnion(recognizers.update(
                accessoryID: id,
                sample: .init(timestamp: pose.timestamp, position: position, isTracked: true)))
            switch lifts.update(accessoryID: id, timestamp: pose.timestamp,
                                originFromAccessory: pose.originFromAccessory) {
            case .jump where pendingJumps.count < Self.maximumPendingJumps:
                pendingJumps.append(pose.timestamp)
            case .interrupted:
                cancelJumps()
            case .jump, .none:
                break
            }
        }
    }
}

private func spatialMatrixIsFinite(_ matrix: simd_float4x4) -> Bool {
    matrix.columns.0.x.isFinite && matrix.columns.0.y.isFinite
        && matrix.columns.0.z.isFinite && matrix.columns.0.w.isFinite
        && matrix.columns.1.x.isFinite && matrix.columns.1.y.isFinite
        && matrix.columns.1.z.isFinite && matrix.columns.1.w.isFinite
        && matrix.columns.2.x.isFinite && matrix.columns.2.y.isFinite
        && matrix.columns.2.z.isFinite && matrix.columns.2.w.isFinite
        && matrix.columns.3.x.isFinite && matrix.columns.3.y.isFinite
        && matrix.columns.3.z.isFinite && matrix.columns.3.w.isFinite
}
