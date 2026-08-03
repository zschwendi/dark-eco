import Foundation
import OSLog
import QuartzCore
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

nonisolated private let sessionLog = Logger(subsystem: "com.zephyrstudiosllc.eco",
                                            category: "Session")

/// Owns everything with a lifetime: the GOAL kernel session, controller and touch input, the audio
/// device, and the frame loop that ties them together.
///
/// One frame is: arm the surface, push the merged pad state, run one `kernel-dispatcher` frame,
/// finish the presentation, then read the vibration request back out. The display link is the frame
/// clock and its target time is passed through to Metal so ProMotion does not add a second cadence.
@MainActor
@Observable
final class GameSession {
    let input = ControllerInput()
    let touch = TouchControls()
    let audio = AudioOutput()
    let settings = RenderSettings()
    let importer = GameDataImporter()
    let saveSync = SaveSyncController()

    private(set) var dataReport = GameDataReport()
    private(set) var kernel: GOALPadKernelStatus?
    private(set) var boot: GOALPadGameBootStatus?
    private(set) var isBooting = false
    private(set) var isRunning = false
    private(set) var framesRun: UInt64 = 0
    private(set) var framesPresented: UInt64 = 0
    private(set) var memoryWarnings = 0
    private(set) var startupError: String?
    private(set) var displayMeanMilliseconds = 0.0
    private(set) var displayP95Milliseconds = 0.0
    private(set) var displayMaxMilliseconds = 0.0
    private(set) var displayFastCallbacks = 0
    private(set) var displaySlowCallbacks = 0
    private(set) var displaySampleCount = 0

    var frameChain: GOALPadFrameChainStats { GOALPadRuntimeBridge.frameChainStats }

    /// Booting runs the game's own startup - two DGO archives and `play` - which takes seconds and
    /// must not block the frame loop or the UI.
    private let bootQueue = DispatchQueue(label: "com.zephyrstudiosllc.eco.boot",
                                          qos: .userInitiated)
    private var observers: [NSObjectProtocol] = []
    /// The frame loop only runs while the scene is on screen: asking a backgrounded app's layer
    /// for a drawable blocks until it comes back.
    private var isForeground = true
    private var previousDisplayCallback: CFTimeInterval?
    private var displayIntervals: [Double] = []
    #if os(iOS)
    private var cameraDiagnosticsURL: URL?
    private var cameraDiagnosticsRunID: UInt64 = 0
    private var lastPersistedCameraAlternations: UInt64 = 0
    private var lastAttemptedCameraAlternations: UInt64 = 0
    private var lastPersistedCameraCorrectionEvents: UInt64 = 0
    private var lastAttemptedCameraCorrectionEvents: UInt64 = 0
    private var lastPersistedMercMissingBoneSlotsTotal: UInt64 = 0
    private var lastAttemptedMercMissingBoneSlotsTotal: UInt64 = 0
    private var lastPersistedMercModelsWithMissingBoneSlotsTotal: UInt64 = 0
    private var lastAttemptedMercModelsWithMissingBoneSlotsTotal: UInt64 = 0
    private var lastPersistedMercPaletteHealthTotal: UInt64 = 0
    private var lastAttemptedMercPaletteHealthTotal: UInt64 = 0
    private var lastPersistedMercTransformDiscontinuitiesTotal: UInt64 = 0
    private var lastAttemptedMercTransformDiscontinuitiesTotal: UInt64 = 0
    private var reportedCameraDiagnosticsWriteFailure = false
    #endif

    var geometry: GOALPadSurfaceGeometry { GOALPadRenderSurface.shared.geometry() }

    // MARK: - Lifetime

    func prepare() async {
        sessionLog.notice("prepare")
        observeSystem()
        try? GameDataLayout.prepare()
        await saveSync.prepare()
        await refreshDataReport()
    }

    func refreshDataReport() async {
        dataReport = await Task.detached { GameDataInspector.inspect() }.value
    }

    /// Bring the session up. Refuses rather than half-starting when the data on disk cannot boot
    /// the game, or when this build has no ahead-of-time Jak 1 code to boot.
    func start() {
        guard !isRunning, !isBooting else { return }
        guard GOALPadRuntimeBridge.isGameCodeLinked else {
            startupError = "This build has no ahead-of-time Jak 1 code. "
                + "Run Scripts/generate-jak1-aot.sh and build again."
            return
        }
        guard dataReport.canBoot else {
            startupError = dataReport.summary
            return
        }

        let status = GOALPadRuntimeBridge.startKernel(
            withDataDirectory: GameDataLayout.gameDirectory.path)
        kernel = status
        guard status.isRunning else {
            startupError = status.message
            return
        }

        startupError = nil
        settings.apply()
        isBooting = true
        sessionLog.notice("Booting Jak 1")
        bootQueue.async {
            let boot = GOALPadRuntimeBridge.bootGame()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.bootFinished(boot) }
            }
        }
    }

    private func bootFinished(_ status: GOALPadGameBootStatus) {
        boot = status
        isBooting = false
        guard status.isBooted else {
            startupError = status.message
            GOALPadRuntimeBridge.stopKernel()
            kernel = nil
            return
        }

        input.startWatching()
        audio.start()
        isRunning = true
        #if os(iOS)
        startCameraDiagnostics()
        #endif
        setIdleTimerDisabled(true)
        sessionLog.notice("Session started: \(status.message)")
    }

    func shutdown() {
        guard isRunning || kernel != nil else { return }
        input.stopRumble()
        input.stopWatching()
        audio.stop()
        #if os(iOS)
        persistCameraDiagnosticsForLifecycleEvent()
        #endif
        GOALPadRuntimeBridge.stopKernel()
        kernel = nil
        boot = nil
        isRunning = false
        touch.reset()
        framesRun = 0
        framesPresented = 0
        previousDisplayCallback = nil
        displayIntervals.removeAll(keepingCapacity: true)
        displayMeanMilliseconds = 0
        displayP95Milliseconds = 0
        displayMaxMilliseconds = 0
        displayFastCallbacks = 0
        displaySlowCallbacks = 0
        displaySampleCount = 0
        setIdleTimerDisabled(false)
        sessionLog.notice("Session shut down")
    }

    // MARK: - The frame loop

    func tick(targetPresentationTime: CFTimeInterval) {
        guard isRunning, isForeground else { return }
        recordDisplayCallback()
        let surface = GOALPadRenderSurface.shared
        guard surface.beginFrame(at: targetPresentationTime) else { return }
        #if os(iOS)
        input.pushFrame(merging: touch.frameState())
        #else
        input.pushFrame()
        #endif

        // The GOAL kernel's own frame: every process and state, then the overlord's vblank work.
        // Its DMA send renders synchronously while out-of-chain Merc bones still match the chain.
        var shouldLog = false
        if GOALPadRuntimeBridge.runFrame(at: targetPresentationTime) {
            framesRun = GOALPadRuntimeBridge.framesRun
            shouldLog = framesRun % 600 == 0
            saveSync.gameplayFrameCompleted()
        }

        if surface.endFrame() {
            framesPresented += 1
        }
        let renderer = surface.stats
        #if os(iOS)
        persistCameraDiagnosticsIfNeeded(renderer, periodic: shouldLog)
        #endif
        if shouldLog { logRunningState(renderer: renderer) }
        input.applyRumble()
    }

    /// The same numbers the on-screen readout shows, every ten seconds, so a run can be checked
    /// from the log alone.
    private func logRunningState(renderer: GOALPadRendererStats) {
        let chain = frameChain
        let mercTransform = renderer.lastMercEicharTransformDiscontinuity
        let oneChainTicks = renderer.framesArmed
            - renderer.framesWithoutChain
            - renderer.framesWithMultipleChains
        sessionLog.notice("""
            frame \(self.framesRun): \(self.framesPresented) ticks with a scheduled drawable, \
            cadence \(self.displayMeanMilliseconds, format: .fixed(precision: 2))/\
            \(self.displayP95Milliseconds, format: .fixed(precision: 2))/\
            \(self.displayMaxMilliseconds, format: .fixed(precision: 2)) ms mean/p95/max over \
            \(self.displaySampleCount), fast/slow \(self.displayFastCallbacks)/\
            \(self.displaySlowCallbacks), ticks 0/1/>1 chain \
            \(renderer.framesWithoutChain)/\(oneChainTicks)/\(renderer.framesWithMultipleChains), \
            drawables \(renderer.drawablesAcquired) scheduled / \(renderer.drawableMisses) missed / \
            \(renderer.latePresentSubmissions) late, \
            camera frame/tick/chain \(renderer.lastEngineFrameID)/\(renderer.lastHostTickID)/\
            \(renderer.lastChainOrdinal), \(renderer.lastCameraPackets) packets, producer \
            alternations \(renderer.producerCameraAlternations), event frames \
            \(renderer.lastCameraAlternationOlderFrameID)/\
            \(renderer.lastCameraAlternationPreviousFrameID)/\
            \(renderer.lastCameraAlternationCurrentFrameID) at \
            \(renderer.lastCameraAlternationHostTickID)/\
            \(renderer.lastCameraAlternationChainOrdinal), fingerprints \
            \(renderer.lastCameraAlternationOlderFingerprint)/\
            \(renderer.lastCameraAlternationPreviousFingerprint)/\
            \(renderer.lastCameraAlternationCurrentFingerprint)/\
            \(renderer.lastCameraAlternationPacketFingerprint), subset/full qwords \
            \(renderer.lastCameraAlternationLiveMismatchQwords)/\
            \(renderer.lastCameraAlternationPacketMismatchQwords)/\
            \(renderer.lastCameraAlternationRenderLiveMismatchQwords)/\
            \(renderer.lastCameraAlternationRenderPacketMismatchQwords), distance \
            \(renderer.lastCameraOlderToPreviousDistance, format: .fixed(precision: 6))/\
            \(renderer.lastCameraPreviousToCurrentDistance, format: .fixed(precision: 6))/\
            \(renderer.lastCameraOlderToCurrentDistance, format: .fixed(precision: 6)), mismatches \
            \(renderer.liveCameraMismatches) live / \(renderer.packetCameraMismatches) packet, \
            present submit/completed/dropped/reversed \(renderer.submissions)/\
            \(renderer.presentationsCompleted)/\(renderer.presentationDrops)/\
            \(renderer.presentationOrderMismatches), last present/drop \
            \(renderer.lastPresentedSubmissionID)/\(renderer.lastDroppedSubmissionID), frame \
            \(renderer.lastPresentedEngineFrameID)/\(renderer.lastPresentedHostTickID)/\
            \(renderer.lastPresentedChainOrdinal), \
            merc \(renderer.mercModels) models / \(renderer.mercDraws) draws, missing bones current \
            \(renderer.mercMissingBoneSlots)/\(renderer.mercModelsWithMissingBoneSlots), total \
            \(renderer.mercMissingBoneSlotsTotal)/\
            \(renderer.mercModelsWithMissingBoneSlotsTotal), last \
            \(renderer.lastMercMissingBoneSlots)/\
            \(renderer.lastMercModelsWithMissingBoneSlots) at \
            \(renderer.lastMercMissingBoneEngineFrameID)/\
            \(renderer.lastMercMissingBoneHostTickID)/\
            \(renderer.lastMercMissingBoneChainOrdinal), \
            palette health current \(renderer.mercNonfiniteBoneMatrices)/\
            \(renderer.mercDegenerateBoneMatrices)/\
            \(renderer.mercIncoherentBoneSources)/\
            \(renderer.mercModelsWithPaletteHealthIssues) nonfinite/degenerate/source/models, \
            total \(renderer.mercNonfiniteBoneMatricesTotal)/\
            \(renderer.mercDegenerateBoneMatricesTotal)/\
            \(renderer.mercIncoherentBoneSourcesTotal)/\
            \(renderer.mercModelsWithPaletteHealthIssuesTotal), last issue/slot \
            \(renderer.lastMercPaletteHealthIssueMask)/\
            \(renderer.lastMercPaletteHealthBoneSlot) at \
            \(renderer.lastMercPaletteHealthEngineFrameID)/\
            \(renderer.lastMercPaletteHealthHostTickID)/\
            \(renderer.lastMercPaletteHealthChainOrdinal), \
            eichar transform current/total \
            \(renderer.mercEicharTransformDiscontinuities)/\
            \(renderer.mercEicharTransformDiscontinuitiesTotal), last issue/slot \
            \(mercTransform.issueMask)/\(mercTransform.boneSlot), frames \
            \(mercTransform.previousFrameID)->\(mercTransform.currentFrameID) at \
            \(mercTransform.hostTickID)/\(mercTransform.chainOrdinal), scale \
            \(mercTransform.previousScale, format: .fixed(precision: 6))->\
            \(mercTransform.currentScale, format: .fixed(precision: 6)), aspect \
            \(mercTransform.previousAspect, format: .fixed(precision: 6))->\
            \(mercTransform.currentAspect, format: .fixed(precision: 6)), rejects \
            \(renderer.mercBadBonePointers) pointers / \(renderer.mercBadDrawRanges) ranges, \
            audio \(self.audio.framesProduced)/\(self.audio.framesRequested) frames at \
            \(self.audio.sampleRate) Hz peak \(self.audio.peakAmplitude), \
            DMA chain \(chain.lastPayloadBytes) bytes \
            (largest \(chain.largestPayloadBytes)), pad reads \
            \(GOALPadInputReadCount(ControllerInput.primaryPort))
            """)
    }

    #if os(iOS)
    private func startCameraDiagnostics() {
        cameraDiagnosticsURL = nil
        cameraDiagnosticsRunID = UInt64.random(in: 1...UInt64.max)
        lastPersistedCameraAlternations = 0
        lastAttemptedCameraAlternations = 0
        lastPersistedCameraCorrectionEvents = 0
        lastAttemptedCameraCorrectionEvents = 0
        lastPersistedMercMissingBoneSlotsTotal = 0
        lastAttemptedMercMissingBoneSlotsTotal = 0
        lastPersistedMercModelsWithMissingBoneSlotsTotal = 0
        lastAttemptedMercModelsWithMissingBoneSlotsTotal = 0
        lastPersistedMercPaletteHealthTotal = 0
        lastAttemptedMercPaletteHealthTotal = 0
        lastPersistedMercTransformDiscontinuitiesTotal = 0
        lastAttemptedMercTransformDiscontinuitiesTotal = 0
        reportedCameraDiagnosticsWriteFailure = false

        guard let caches = FileManager.default.urls(for: .cachesDirectory,
                                                     in: .userDomainMask).first else {
            reportCameraDiagnosticsWriteFailure()
            return
        }
        let directory = caches.appendingPathComponent("GOALPadDiagnostics", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
            cameraDiagnosticsURL = directory
                .appendingPathComponent("camera-provenance-v1.log", isDirectory: false)
            let renderer = GOALPadRenderSurface.shared.stats
            lastAttemptedCameraAlternations = renderer.producerCameraAlternations
            lastAttemptedCameraCorrectionEvents = renderer.cameraCorrectionEventsTotal
            lastAttemptedMercMissingBoneSlotsTotal = renderer.mercMissingBoneSlotsTotal
            lastAttemptedMercModelsWithMissingBoneSlotsTotal =
                renderer.mercModelsWithMissingBoneSlotsTotal
            lastAttemptedMercPaletteHealthTotal = mercPaletteHealthTotal(renderer)
            lastAttemptedMercTransformDiscontinuitiesTotal =
                renderer.mercEicharTransformDiscontinuitiesTotal
            try writeCameraDiagnostics(renderer)
            lastPersistedCameraAlternations = renderer.producerCameraAlternations
            lastPersistedCameraCorrectionEvents = renderer.cameraCorrectionEventsTotal
            lastPersistedMercMissingBoneSlotsTotal = renderer.mercMissingBoneSlotsTotal
            lastPersistedMercModelsWithMissingBoneSlotsTotal =
                renderer.mercModelsWithMissingBoneSlotsTotal
            lastPersistedMercPaletteHealthTotal = mercPaletteHealthTotal(renderer)
            lastPersistedMercTransformDiscontinuitiesTotal =
                renderer.mercEicharTransformDiscontinuitiesTotal
        } catch {
            reportCameraDiagnosticsWriteFailure()
        }
    }

    private func persistCameraDiagnosticsIfNeeded(_ renderer: GOALPadRendererStats,
                                                   periodic: Bool,
                                                   forced: Bool = false) {
        guard cameraDiagnosticsURL != nil else { return }
        let alternationNotPersisted = renderer.producerCameraAlternations
            > lastPersistedCameraAlternations
        let alternationNotAttempted = renderer.producerCameraAlternations
            > lastAttemptedCameraAlternations
        let correctionNotPersisted = renderer.cameraCorrectionEventsTotal
            > lastPersistedCameraCorrectionEvents
        let correctionNotAttempted = renderer.cameraCorrectionEventsTotal
            > lastAttemptedCameraCorrectionEvents
        let missingSlotsNotPersisted = renderer.mercMissingBoneSlotsTotal
            > lastPersistedMercMissingBoneSlotsTotal
        let missingSlotsNotAttempted = renderer.mercMissingBoneSlotsTotal
            > lastAttemptedMercMissingBoneSlotsTotal
        let missingModelsNotPersisted = renderer.mercModelsWithMissingBoneSlotsTotal
            > lastPersistedMercModelsWithMissingBoneSlotsTotal
        let missingModelsNotAttempted = renderer.mercModelsWithMissingBoneSlotsTotal
            > lastAttemptedMercModelsWithMissingBoneSlotsTotal
        let paletteHealthTotal = mercPaletteHealthTotal(renderer)
        let paletteHealthNotPersisted = paletteHealthTotal > lastPersistedMercPaletteHealthTotal
        let paletteHealthNotAttempted = paletteHealthTotal > lastAttemptedMercPaletteHealthTotal
        let mercTransformNotPersisted = renderer.mercEicharTransformDiscontinuitiesTotal
            > lastPersistedMercTransformDiscontinuitiesTotal
        let mercTransformNotAttempted = renderer.mercEicharTransformDiscontinuitiesTotal
            > lastAttemptedMercTransformDiscontinuitiesTotal
        let mercCompletenessIncreased = (missingSlotsNotPersisted && missingSlotsNotAttempted)
            || (missingModelsNotPersisted && missingModelsNotAttempted)
        guard forced || periodic
                || (alternationNotPersisted && alternationNotAttempted)
                || (correctionNotPersisted && correctionNotAttempted)
                || mercCompletenessIncreased
                || (paletteHealthNotPersisted && paletteHealthNotAttempted)
                || (mercTransformNotPersisted && mercTransformNotAttempted) else {
            return
        }

        lastAttemptedCameraAlternations = renderer.producerCameraAlternations
        lastAttemptedCameraCorrectionEvents = renderer.cameraCorrectionEventsTotal
        lastAttemptedMercMissingBoneSlotsTotal = renderer.mercMissingBoneSlotsTotal
        lastAttemptedMercModelsWithMissingBoneSlotsTotal =
            renderer.mercModelsWithMissingBoneSlotsTotal
        lastAttemptedMercPaletteHealthTotal = paletteHealthTotal
        lastAttemptedMercTransformDiscontinuitiesTotal =
            renderer.mercEicharTransformDiscontinuitiesTotal
        do {
            try writeCameraDiagnostics(renderer)
            lastPersistedCameraAlternations = renderer.producerCameraAlternations
            lastPersistedCameraCorrectionEvents = renderer.cameraCorrectionEventsTotal
            lastPersistedMercMissingBoneSlotsTotal = renderer.mercMissingBoneSlotsTotal
            lastPersistedMercModelsWithMissingBoneSlotsTotal =
                renderer.mercModelsWithMissingBoneSlotsTotal
            lastPersistedMercPaletteHealthTotal = paletteHealthTotal
            lastPersistedMercTransformDiscontinuitiesTotal =
                renderer.mercEicharTransformDiscontinuitiesTotal
        } catch {
            reportCameraDiagnosticsWriteFailure()
        }
    }

    private func persistCameraDiagnosticsForLifecycleEvent() {
        let surface = GOALPadRenderSurface.shared
        guard isRunning, surface.isRendererLinked else { return }
        persistCameraDiagnosticsIfNeeded(surface.stats, periodic: false, forced: true)
    }

    private func mercPaletteHealthTotal(_ renderer: GOALPadRendererStats) -> UInt64 {
        renderer.mercNonfiniteBoneMatricesTotal
            + renderer.mercDegenerateBoneMatricesTotal
            + renderer.mercIncoherentBoneSourcesTotal
    }

    private func writeCameraDiagnostics(_ renderer: GOALPadRendererStats) throws {
        guard let cameraDiagnosticsURL else { return }
        let locale = Locale(identifier: "en_US_POSIX")
        func decimal(_ value: Double) -> String {
            String(format: "%.9f", locale: locale, value)
        }
        func mercTransformFields(_ prefix: String,
                                 _ event: GOALPadMercTransformEvent) -> [String] {
            [
                "\(prefix)_host_tick=\(event.hostTickID)",
                "\(prefix)_chain=\(event.chainOrdinal)",
                "\(prefix)_issue_mask=\(event.issueMask)",
                "\(prefix)_bone_slot=\(event.boneSlot)",
                "\(prefix)_model_hash=\(event.modelNameHash)",
                "\(prefix)_previous_frame=\(event.previousFrameID)",
                "\(prefix)_current_frame=\(event.currentFrameID)",
                "\(prefix)_previous_matrix_hash=\(event.previousMatrixHash)",
                "\(prefix)_current_matrix_hash=\(event.currentMatrixHash)",
                "\(prefix)_previous_axis_norm_x=\(decimal(event.previousAxisNormX))",
                "\(prefix)_previous_axis_norm_y=\(decimal(event.previousAxisNormY))",
                "\(prefix)_previous_axis_norm_z=\(decimal(event.previousAxisNormZ))",
                "\(prefix)_current_axis_norm_x=\(decimal(event.currentAxisNormX))",
                "\(prefix)_current_axis_norm_y=\(decimal(event.currentAxisNormY))",
                "\(prefix)_current_axis_norm_z=\(decimal(event.currentAxisNormZ))",
                "\(prefix)_previous_scale=\(decimal(event.previousScale))",
                "\(prefix)_current_scale=\(decimal(event.currentScale))",
                "\(prefix)_previous_aspect=\(decimal(event.previousAspect))",
                "\(prefix)_current_aspect=\(decimal(event.currentAspect))",
                "\(prefix)_previous_source_base=\(event.previousSourceBase)",
                "\(prefix)_current_source_base=\(event.currentSourceBase)",
            ]
        }
        func cameraVectorFields(_ prefix: String,
                                _ vector: GOALPadCameraCorrectionVector) -> [String] {
            [
                "\(prefix)_x=\(decimal(vector.x))",
                "\(prefix)_y=\(decimal(vector.y))",
                "\(prefix)_z=\(decimal(vector.z))",
                "\(prefix)_w=\(decimal(vector.w))",
            ]
        }
        func cameraSlaveFields(_ prefix: String,
                               _ slave: GOALPadCameraCorrectionSlaveFrame) -> [String] {
            [
                "\(prefix)_valid=\(slave.valid.boolValue ? 1 : 0)",
                "\(prefix)_options=\(slave.options)",
                "\(prefix)_los_state=\(slave.losState)",
                "\(prefix)_string_velocity_direction=\(slave.stringVelocityDirection)",
                "\(prefix)_line_of_sight=\(slave.lineOfSightEnabled.boolValue ? 1 : 0)",
                "\(prefix)_movement_blocked=\(slave.movementBlocked.boolValue ? 1 : 0)",
                "\(prefix)_minimum_distance_override="
                    + decimal(slave.minimumDistanceOverride),
            ]
                + cameraVectorFields("\(prefix)_transform", slave.transform)
                + cameraVectorFields("\(prefix)_view_flat", slave.viewFlat)
                + cameraVectorFields("\(prefix)_string_transform", slave.stringTransform)
                + cameraVectorFields("\(prefix)_desired_position", slave.desiredPosition)
        }
        func cameraFrameFields(_ prefix: String,
                               _ frame: GOALPadCameraCorrectionFrame) -> [String] {
            [
                "\(prefix)_valid=\(frame.valid.boolValue ? 1 : 0)",
                "\(prefix)_engine_frame=\(frame.engineFrameID)",
                "\(prefix)_display_ratio=\(decimal(frame.displayTimeRatio))",
                "\(prefix)_num_slaves=\(frame.numSlaves)",
                "\(prefix)_being_attacked=\(frame.beingAttacked.boolValue ? 1 : 0)",
                "\(prefix)_combiner_valid=\(frame.combinerValid.boolValue ? 1 : 0)",
                "\(prefix)_combiner_interp=\(decimal(frame.combinerInterpolation))",
                "\(prefix)_combiner_tracking=\(frame.combinerTrackingStatus)",
            ]
                + cameraVectorFields("\(prefix)_target", frame.targetPosition)
                + cameraVectorFields("\(prefix)_adjusted_target",
                                     frame.adjustedTargetPosition)
                + cameraSlaveFields("\(prefix)_slave0", frame.slave0)
                + cameraSlaveFields("\(prefix)_slave1", frame.slave1)
                + cameraVectorFields("\(prefix)_combiner_transform",
                                     frame.combinerTransform)
        }
        func cameraCorrectionFields(_ event: GOALPadCameraCorrectionEvent) -> [String] {
            [
                "camera_correction_valid=\(event.valid.boolValue ? 1 : 0)",
                "camera_correction_reason_mask=\(event.reasonMask)",
                "camera_correction_host_tick=\(event.hostTickID)",
                "camera_correction_chain=\(event.chainOrdinal)",
            ]
                + cameraFrameFields("camera_correction_older", event.older)
                + cameraFrameFields("camera_correction_previous", event.previous)
                + cameraFrameFields("camera_correction_current", event.current)
        }

        let fields = [
            "goalpad_camera_provenance", "v=1", "run=\(cameraDiagnosticsRunID)",
            "frame=\(framesRun)", "engine=\(renderer.lastEngineFrameID)",
            "tick=\(renderer.lastHostTickID)", "chain=\(renderer.lastChainOrdinal)",
            "fingerprint=\(renderer.lastCameraFingerprint)",
            "packets=\(renderer.lastCameraPackets)",
            "chains_sent=\(renderer.chainsSent)",
            "chains_rendered=\(renderer.chainsRendered)",
            "chains_dropped=\(renderer.chainsDropped)",
            "frames_armed=\(renderer.framesArmed)",
            "frames_without_chain=\(renderer.framesWithoutChain)",
            "frames_with_multiple_chains=\(renderer.framesWithMultipleChains)",
            "max_chains_per_frame=\(renderer.maxChainsPerFrame)",
            "drawables_acquired=\(renderer.drawablesAcquired)",
            "drawable_misses=\(renderer.drawableMisses)",
            "late_present_submissions=\(renderer.latePresentSubmissions)",
            "producer_alternations=\(renderer.producerCameraAlternations)",
            "camera_correction_events_total=\(renderer.cameraCorrectionEventsTotal)",
            "alternation_older_frame=\(renderer.lastCameraAlternationOlderFrameID)",
            "alternation_previous_frame=\(renderer.lastCameraAlternationPreviousFrameID)",
            "alternation_current_frame=\(renderer.lastCameraAlternationCurrentFrameID)",
            "alternation_older_fingerprint=\(renderer.lastCameraAlternationOlderFingerprint)",
            "alternation_previous_fingerprint="
                + "\(renderer.lastCameraAlternationPreviousFingerprint)",
            "alternation_current_fingerprint="
                + "\(renderer.lastCameraAlternationCurrentFingerprint)",
            "alternation_host_tick=\(renderer.lastCameraAlternationHostTickID)",
            "alternation_chain=\(renderer.lastCameraAlternationChainOrdinal)",
            "alternation_packet_fingerprint="
                + "\(renderer.lastCameraAlternationPacketFingerprint)",
            "alternation_live_mismatch_qwords="
                + "\(renderer.lastCameraAlternationLiveMismatchQwords)",
            "alternation_packet_mismatch_qwords="
                + "\(renderer.lastCameraAlternationPacketMismatchQwords)",
            "alternation_render_live_mismatch_qwords="
                + "\(renderer.lastCameraAlternationRenderLiveMismatchQwords)",
            "alternation_render_packet_mismatch_qwords="
                + "\(renderer.lastCameraAlternationRenderPacketMismatchQwords)",
            "distance_older_previous=\(decimal(renderer.lastCameraOlderToPreviousDistance))",
            "distance_previous_current=\(decimal(renderer.lastCameraPreviousToCurrentDistance))",
            "distance_older_current=\(decimal(renderer.lastCameraOlderToCurrentDistance))",
            "last_live_mismatches=\(renderer.lastLiveCameraMismatches)",
            "last_packet_mismatches=\(renderer.lastPacketCameraMismatches)",
            "last_live_mismatch_qwords=\(renderer.lastLiveCameraMismatchQwords)",
            "last_packet_mismatch_qwords=\(renderer.lastPacketCameraMismatchQwords)",
            "live_mismatches=\(renderer.liveCameraMismatches)",
            "packet_mismatches=\(renderer.packetCameraMismatches)",
            "submissions=\(renderer.submissions)",
            "presentations_completed=\(renderer.presentationsCompleted)",
            "presentation_drops=\(renderer.presentationDrops)",
            "presentation_order_mismatches=\(renderer.presentationOrderMismatches)",
            "last_submission=\(renderer.lastSubmissionID)",
            "last_presented_submission=\(renderer.lastPresentedSubmissionID)",
            "last_dropped_submission=\(renderer.lastDroppedSubmissionID)",
            "last_drawable=\(renderer.lastDrawableID)",
            "last_presented_drawable=\(renderer.lastPresentedDrawableID)",
            "last_presented_engine=\(renderer.lastPresentedEngineFrameID)",
            "last_presented_tick=\(renderer.lastPresentedHostTickID)",
            "last_presented_chain=\(renderer.lastPresentedChainOrdinal)",
            "last_requested_time=\(decimal(renderer.lastRequestedPresentationTime))",
            "last_actual_time=\(decimal(renderer.lastActualPresentationTime))",
            "merc_missing_bone_slots=\(renderer.mercMissingBoneSlots)",
            "merc_models_with_missing_bone_slots="
                + "\(renderer.mercModelsWithMissingBoneSlots)",
            "merc_missing_bone_slots_total=\(renderer.mercMissingBoneSlotsTotal)",
            "merc_models_with_missing_bone_slots_total="
                + "\(renderer.mercModelsWithMissingBoneSlotsTotal)",
            "last_merc_missing_bone_engine_frame="
                + "\(renderer.lastMercMissingBoneEngineFrameID)",
            "last_merc_missing_bone_host_tick="
                + "\(renderer.lastMercMissingBoneHostTickID)",
            "last_merc_missing_bone_chain=\(renderer.lastMercMissingBoneChainOrdinal)",
            "last_merc_missing_bone_slots=\(renderer.lastMercMissingBoneSlots)",
            "last_merc_models_with_missing_bone_slots="
                + "\(renderer.lastMercModelsWithMissingBoneSlots)",
            "merc_nonfinite_bone_matrices=\(renderer.mercNonfiniteBoneMatrices)",
            "merc_degenerate_bone_matrices=\(renderer.mercDegenerateBoneMatrices)",
            "merc_incoherent_bone_sources=\(renderer.mercIncoherentBoneSources)",
            "merc_models_with_palette_health_issues="
                + "\(renderer.mercModelsWithPaletteHealthIssues)",
            "merc_nonfinite_bone_matrices_total="
                + "\(renderer.mercNonfiniteBoneMatricesTotal)",
            "merc_degenerate_bone_matrices_total="
                + "\(renderer.mercDegenerateBoneMatricesTotal)",
            "merc_incoherent_bone_sources_total="
                + "\(renderer.mercIncoherentBoneSourcesTotal)",
            "merc_models_with_palette_health_issues_total="
                + "\(renderer.mercModelsWithPaletteHealthIssuesTotal)",
            "last_merc_palette_health_engine_frame="
                + "\(renderer.lastMercPaletteHealthEngineFrameID)",
            "last_merc_palette_health_host_tick="
                + "\(renderer.lastMercPaletteHealthHostTickID)",
            "last_merc_palette_health_chain="
                + "\(renderer.lastMercPaletteHealthChainOrdinal)",
            "last_merc_palette_health_issue_mask="
                + "\(renderer.lastMercPaletteHealthIssueMask)",
            "last_merc_palette_health_bone_slot="
                + "\(renderer.lastMercPaletteHealthBoneSlot)",
            "last_merc_palette_health_model_hash="
                + "\(renderer.lastMercPaletteHealthModelNameHash)",
            "last_merc_palette_health_matrix_hash="
                + "\(renderer.lastMercPaletteHealthMatrixHash)",
            "last_merc_palette_health_axis_norm_x="
                + "\(decimal(renderer.lastMercPaletteHealthAxisNormX))",
            "last_merc_palette_health_axis_norm_y="
                + "\(decimal(renderer.lastMercPaletteHealthAxisNormY))",
            "last_merc_palette_health_axis_norm_z="
                + "\(decimal(renderer.lastMercPaletteHealthAxisNormZ))",
            "last_merc_palette_health_normalized_abs_det="
                + "\(decimal(renderer.lastMercPaletteHealthNormalizedAbsDeterminant))",
            "last_merc_palette_health_source_address="
                + "\(renderer.lastMercPaletteHealthSourceAddress)",
            "last_merc_palette_health_source_base="
                + "\(renderer.lastMercPaletteHealthSourceBase)",
            "last_merc_palette_health_expected_source_base="
                + "\(renderer.lastMercPaletteHealthExpectedSourceBase)",
            "merc_eichar_transform_discontinuities="
                + "\(renderer.mercEicharTransformDiscontinuities)",
            "merc_eichar_transform_discontinuities_total="
                + "\(renderer.mercEicharTransformDiscontinuitiesTotal)",
        ]
            + mercTransformFields(
                "first_merc_eichar_transform",
                renderer.firstMercEicharTransformDiscontinuity)
            + mercTransformFields(
                "last_merc_eichar_transform",
                renderer.lastMercEicharTransformDiscontinuity)
            + cameraCorrectionFields(renderer.lastCameraCorrectionEvent)
        try Data((fields.joined(separator: " ") + "\n").utf8)
            .write(to: cameraDiagnosticsURL, options: .atomic)
    }

    private func reportCameraDiagnosticsWriteFailure() {
        guard !reportedCameraDiagnosticsWriteFailure else { return }
        reportedCameraDiagnosticsWriteFailure = true
        sessionLog.error("Camera diagnostics snapshot could not be written.")
    }
    #endif

    private func recordDisplayCallback() {
        let now = CACurrentMediaTime()
        if let previousDisplayCallback {
            displayIntervals.append((now - previousDisplayCallback) * 1_000)
        }
        previousDisplayCallback = now
        guard displayIntervals.count == 600 else { return }

        let sorted = displayIntervals.sorted()
        displayMeanMilliseconds = displayIntervals.reduce(0, +) / Double(displayIntervals.count)
        displayP95Milliseconds = sorted[max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)]
        displayMaxMilliseconds = sorted.last ?? 0
        displayFastCallbacks = displayIntervals.count { $0 < 12 }
        displaySlowCallbacks = displayIntervals.count { $0 >= 24 }
        displaySampleCount = displayIntervals.count
        displayIntervals.removeAll(keepingCapacity: true)
    }

    // MARK: - App lifecycle

    func scenePhaseChanged(to phase: ScenePhase) {
        switch phase {
        case .active:
            isForeground = true
            Task { await saveSync.syncNow() }
            guard isRunning else { return }
            audio.resumeIfSuspended()
            setIdleTimerDisabled(true)
        case .inactive:
            saveSync.gameplayFrameCompleted()
            #if os(iOS)
            persistCameraDiagnosticsForLifecycleEvent()
            #endif
            isForeground = false
            touch.reset()
            resetDisplayTiming()
            // A transient state - the app switcher, a notification. Give up the audio device but
            // keep the session, so returning is instant.
            audio.suspend()
            input.stopRumble()
        case .background:
            saveSync.gameplayFrameCompleted()
            #if os(iOS)
            persistCameraDiagnosticsForLifecycleEvent()
            #endif
            isForeground = false
            touch.reset()
            resetDisplayTiming()
            audio.suspend()
            input.stopRumble()
            setIdleTimerDisabled(false)
        @unknown default:
            break
        }
    }

    private func resetDisplayTiming() {
        // Boot owns the native display clock until it publishes a running session. Avoid racing
        // its background boot queue if the app changes lifecycle state during startup.
        if isRunning {
            GOALPadRuntimeBridge.resetFrameTiming()
        }
        previousDisplayCallback = nil
        displayIntervals.removeAll(keepingCapacity: true)
        displayMeanMilliseconds = 0
        displayP95Milliseconds = 0
        displayMaxMilliseconds = 0
        displayFastCallbacks = 0
        displaySlowCallbacks = 0
        displaySampleCount = 0
    }

    private func observeSystem() {
        guard observers.isEmpty else { return }
        #if canImport(UIKit)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMemoryWarning() }
        })
        observers.append(center.addObserver(forName: UIApplication.willTerminateNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                sessionLog.notice("willTerminate")
                self?.shutdown()
            }
        })
        #endif
    }

    /// The kernel's 128 MiB of EE main memory is fixed for the life of the session, so there is
    /// nothing here to give back. Record the warning and say so; dropping cached level data is the
    /// fused renderer's decision to make, not this shell's.
    private func handleMemoryWarning() {
        memoryWarnings += 1
        sessionLog.warning("Memory warning #\(self.memoryWarnings) - nothing reclaimable in the app shell")
    }

    private func setIdleTimerDisabled(_ disabled: Bool) {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }
}
