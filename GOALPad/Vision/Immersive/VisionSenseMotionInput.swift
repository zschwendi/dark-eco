#if os(visionOS) && GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE
import ARKit
import Foundation
import GameController
import OSLog
import simd
import Spatial

nonisolated private let senseInputLog = Logger(subsystem: "com.zephyrstudiosllc.eco",
                                               category: "SenseInput")

struct VisionSenseControllerSample {
    var snapshot = Jak1ControllerSnapshot()
    var physicalLeftX: Float = 0
    var physicalLeftY: Float = 0
    var physicalRightX: Float = 0
    var physicalRightY: Float = 0
    var hasLeftStick = false
    var hasRightStick = false
}

/// Owns only accessory tracking. In the immersive space, the compositor's existing
/// WorldTrackingProvider supplies the timestamped device transform so this object never starts a
/// competing head-tracking provider. In the ordinary window, where Apple supports accessory
/// anchors for the focused app but the app has no headset pose, each controller's aim pose
/// supplies its own gesture axes.
@MainActor
final class VisionSenseMotionInput {
    private struct TrackedController {
        let controller: GCController
        let accessory: Accessory
        var chirality: Accessory.Chirality
    }

    private var watching = false
    private var motionEnabled = false
    private var generation: UInt64 = 0
    private var observers: [NSObjectProtocol] = []
    private var discoveryTask: Task<Void, Never>?
    private var trackingTask: Task<Void, Never>?
    private var session: ARKitSession?
    private var provider: AccessoryTrackingProvider?
    private var trackedControllers: [TrackedController] = []
    private var router = SpatialAttackMotionRouter()

    var hasConnectedControllers: Bool {
        GCController.controllers().contains {
            $0.productCategory == GCProductCategorySpatialController
        }
    }

    func startWatching() {
        guard !watching else { return }
        watching = true
        installObservers()
        reloadControllers()
    }

    func stopWatching() {
        guard watching else { return }
        watching = false
        motionEnabled = false
        generation &+= 1
        removeObservers()
        discoveryTask?.cancel()
        discoveryTask = nil
        stopMotionTracking()
        trackedControllers.removeAll()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != motionEnabled else { return }
        motionEnabled = enabled
        if enabled {
            startMotionTracking()
        } else {
            stopMotionTracking()
        }
    }

    /// Immersive route: one measured accessory pose per compositor frame, in headset axes.
    func updateReference(originFromDevice: simd_float4x4?, timestamp: TimeInterval) {
        guard motionEnabled, let provider else {
            router.reset()
            return
        }
        router.update(originFromDevice: originFromDevice, clock: timestamp,
                      poses: poseSamples(provider.latestAnchors, includingAim: false))
    }

    /// Returns this game frame's attacks once. The ordinary-window route samples the latest
    /// measured anchors here against `now`; the immersive route only drains what the compositor's
    /// head-referenced updates produced. Suppressed frames sample nothing and clear every partial
    /// gesture.
    func consumeAttacks(allowed: Bool, reference: SpatialGestureReference,
                        now: TimeInterval) -> SpatialAttackGesture {
        if allowed, reference == .accessoryAim {
            if motionEnabled, let provider {
                router.updateAccessoryAim(
                    clock: now, poses: poseSamples(provider.latestAnchors, includingAim: true))
            } else {
                router.reset()
            }
        }
        return router.consume(allowed: allowed, reference: reference, now: now)
    }

    func controllerSample() -> VisionSenseControllerSample? {
        guard watching, !trackedControllers.isEmpty else { return nil }
        var result = VisionSenseControllerSample()
        var contributed = false
        for tracked in trackedControllers {
            let state = tracked.controller.input.capture()
            switch tracked.chirality {
            case .left:
                contributed = true
                Self.mergeButton(.buttonX, named: .a, from: state, into: &result.snapshot)
                Self.mergeButton(.buttonY, named: .b, from: state, into: &result.snapshot)
                Self.mergeButton(.leftShoulder, named: .grip,
                                 from: state, into: &result.snapshot)
                Self.mergeButton(.leftTrigger, named: .trigger,
                                 from: state, into: &result.snapshot)
                Self.mergeButton(.leftThumbstickButton, named: .thumbstickButton,
                                 from: state, into: &result.snapshot)
                Self.mergeButton(.options, named: .menu, from: state, into: &result.snapshot)
                if let stick = state.dpads[.thumbstick] {
                    result.physicalLeftX = stick.xAxis.value
                    result.physicalLeftY = stick.yAxis.value
                    result.hasLeftStick = true
                }
            case .right:
                contributed = true
                Self.mergeButton(.buttonA, named: .a, from: state, into: &result.snapshot)
                Self.mergeButton(.buttonB, named: .b, from: state, into: &result.snapshot)
                Self.mergeButton(.rightShoulder, named: .grip,
                                 from: state, into: &result.snapshot)
                Self.mergeButton(.rightTrigger, named: .trigger,
                                 from: state, into: &result.snapshot)
                Self.mergeButton(.rightThumbstickButton, named: .thumbstickButton,
                                 from: state, into: &result.snapshot)
                Self.mergeButton(.menu, named: .menu, from: state, into: &result.snapshot)
                if let stick = state.dpads[.thumbstick] {
                    result.physicalRightX = stick.xAxis.value
                    result.physicalRightY = stick.yAxis.value
                    result.hasRightStick = true
                }
            case .unspecified:
                break
            @unknown default:
                break
            }
        }
        return contributed ? result : nil
    }

    private func installObservers() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .GCControllerDidConnect,
                               object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let controller = note.object as? GCController,
                          controller.productCategory == GCProductCategorySpatialController
                    else { return }
                    self?.reloadControllers()
                }
            },
            center.addObserver(forName: .GCControllerDidDisconnect,
                               object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let controller = note.object as? GCController,
                          controller.productCategory == GCProductCategorySpatialController
                    else { return }
                    self?.reloadControllers()
                }
            },
        ]
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    private func reloadControllers() {
        generation &+= 1
        let requestedGeneration = generation
        discoveryTask?.cancel()
        stopMotionTracking()
        trackedControllers.removeAll()

        let controllers = GCController.controllers().filter {
            $0.productCategory == GCProductCategorySpatialController
        }
        guard watching, !controllers.isEmpty else { return }

        discoveryTask = Task { [weak self] in
            var loaded: [TrackedController] = []
            for controller in controllers {
                guard !Task.isCancelled else { return }
                do {
                    let accessory = try await Accessory(device: controller)
                    loaded.append(TrackedController(controller: controller,
                                                    accessory: accessory,
                                                    chirality: accessory.inherentChirality))
                } catch {
                    senseInputLog.error("Could not load a spatial controller: \(error.localizedDescription, privacy: .public)")
                }
            }
            guard let self, self.watching, self.generation == requestedGeneration,
                  !Task.isCancelled else { return }
            self.trackedControllers = loaded
            if self.motionEnabled { self.startMotionTracking() }
        }
    }

    private func startMotionTracking() {
        trackingTask?.cancel()
        session?.stop()
        session = nil
        provider = nil
        router.reset()
        guard motionEnabled, watching, !trackedControllers.isEmpty else { return }
        guard AccessoryTrackingProvider.isSupported else {
            senseInputLog.error("Accessory tracking is unavailable; Sense motion is disabled")
            return
        }
        let requestedGeneration = generation
        let accessories = trackedControllers.map(\.accessory)

        trackingTask = Task { [weak self] in
            guard let self else { return }
            let session = ARKitSession()
            let authorization = await session.requestAuthorization(
                for: AccessoryTrackingProvider.requiredAuthorizations)
            guard self.motionEnabled, self.watching,
                  self.generation == requestedGeneration,
                  !Task.isCancelled else { return }
            guard !authorization.values.contains(.denied) else {
                senseInputLog.notice("Accessory tracking was denied; ordinary Sense input remains available")
                return
            }

            let provider = AccessoryTrackingProvider(accessories: accessories)
            do {
                try await session.run([provider])
            } catch {
                senseInputLog.error("Accessory tracking did not start: \(error.localizedDescription, privacy: .public)")
                return
            }
            guard self.motionEnabled, self.watching,
                  self.generation == requestedGeneration,
                  !Task.isCancelled else {
                session.stop()
                return
            }
            self.session = session
            self.provider = provider
            senseInputLog.notice("Sense motion tracking started for \(accessories.count) controller halves")
        }
    }

    private func stopMotionTracking() {
        trackingTask?.cancel()
        trackingTask = nil
        session?.stop()
        session = nil
        provider = nil
        router.reset()
    }

    /// Measured anchors only; nothing here predicts or integrates inertial data into position.
    private func poseSamples(_ anchors: [AccessoryAnchor],
                             includingAim: Bool) -> [SpatialAccessoryPoseSample] {
        anchors.map { anchor in
            let id = anchor.accessory.id
            let isPositionTracked = anchor.trackingState == .positionOrientationTracked
            if isPositionTracked {
                updateHeldChirality(for: id, from: anchor.heldChirality)
            }
            let originFromAim: simd_float4x4? =
                includingAim && isPositionTracked && anchor.accessory.locations.contains(.aim)
                ? anchor.coordinateSpace(for: .aim, correction: .none)
                    .ancestorFromSpaceTransformFloat().matrix
                : nil
            return SpatialAccessoryPoseSample(accessoryID: id,
                                              timestamp: anchor.timestamp,
                                              isPositionTracked: isPositionTracked,
                                              originFromAccessory: anchor.originFromAnchorTransform,
                                              originFromAim: originFromAim)
        }
    }

    private func updateHeldChirality(for accessoryID: UUID,
                                     from chirality: Accessory.Chirality?) {
        guard let chirality, chirality != .unspecified,
              let index = trackedControllers.firstIndex(where: {
                  $0.accessory.id == accessoryID
              }) else { return }
        trackedControllers[index].chirality = chirality
    }

    private static func mergeButton(_ control: Jak1ControllerControl,
                                    named name: GCButtonElementName,
                                    from state: GCControllerInputState,
                                    into snapshot: inout Jak1ControllerSnapshot) {
        guard let input = state.buttons[name]?.pressedInput else { return }
        snapshot.set(control,
                     pressed: snapshot.isPressed(control) || input.isPressed,
                     value: max(snapshot.value(for: control), input.value))
    }
}
#endif
