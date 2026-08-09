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
    private static let saveRecoveryMessage =
        "Save recovery needs attention. Open Settings and retry iCloud Saves before playing."
    private static let inactiveStartupMessage =
        "Eco became inactive before gameplay could start. Return to Eco and choose Play again."

    let input = ControllerInput()
    let touch = TouchControls()
    let audio = AudioOutput()
    let settings = RenderSettings()
    let presentationSettings = PresentationSettings()
    let importer = GameDataImporter()
    let saveSync = SaveSyncController()

    private(set) var dataReport = GameDataReport()
    private(set) var kernel: GOALPadKernelStatus?
    private(set) var boot: GOALPadGameBootStatus?
    private(set) var isBooting = false
    private(set) var isRunning = false
    private(set) var gameMode: GOALPadGameMode = .unknown
    private(set) var titleStartState: GOALPadTitleStartState = .unknown
    private(set) var progressMenuSnapshot: NativeProgressMenuSnapshot = .unavailable
    private(set) var runReadiness: GameplayRunReadiness = .preRun
    private(set) var warpGateTouchSnapshot: NativeWarpGateTouchSnapshot = .invalid
    private(set) var cutsceneSkipTouchSnapshot: NativeCutsceneSkipTouchSnapshot = .invalid
    private(set) var facePromptTouchSnapshot: NativeFacePromptTouchSnapshot = .invalid
    private(set) var lookAroundState: GOALPadLookAroundState = .unknown
    private(set) var speederState: GOALPadSpeederState = .unknown
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

    var isNativeMenuOpen: Bool {
        switch gameMode {
        case .pause, .progress, .menu: true
        case .unknown, .gameplay: false
        @unknown default: false
        }
    }

    /// Booting runs the game's own startup - two DGO archives and `play` - which takes seconds and
    /// must not block the frame loop or the UI.
    private let bootQueue = DispatchQueue(label: "com.zephyrstudiosllc.eco.boot",
                                          qos: .userInitiated)
    private var observers: [NSObjectProtocol] = []
    /// Only the latest active-scene generation may reopen the frame loop after its save gate.
    private var lifecycle = GameplayLifecycleState()
    private var currentScenePhase: ScenePhase = .active
    private var startupState = GameplayStartupState()
    private var foregroundPreparationTask: Task<Void, Never>?
    private var foregroundPreparationGeneration: UInt64?
    private var controlsGuideSuspension = ControlsGuideSuspensionState()
    var startupPhase: GameplayStartupPhase { startupState.phase }
    private var isStartingGameplay: Bool { startupPhase.isPreparing }
    private var isPreparingGameplay: Bool {
        isStartingGameplay || lifecycle.isPreparingForeground
    }
    private var previousDisplayCallback: CFTimeInterval?
    private var displayIntervals: [Double] = []
    #if os(iOS) || os(visionOS)
    private var cameraDiagnosticsURL: URL?
    private var cameraDiagnosticsRunID: UInt64 = 0
    private var lastPersistedCameraTailTriggerFrame: UInt64 = 0
    private var lastAttemptedCameraTailTriggerFrame: UInt64 = 0
    private var lastCameraTailWriteEngineFrame: UInt64 = 0
    private var lastPersistedMercMissingBoneSlotsTotal: UInt64 = 0
    private var lastAttemptedMercMissingBoneSlotsTotal: UInt64 = 0
    private var lastPersistedMercModelsWithMissingBoneSlotsTotal: UInt64 = 0
    private var lastAttemptedMercModelsWithMissingBoneSlotsTotal: UInt64 = 0
    private var lastPersistedMercPaletteHealthTotal: UInt64 = 0
    private var lastAttemptedMercPaletteHealthTotal: UInt64 = 0
    private var lastPersistedMercTransformDiscontinuitiesTotal: UInt64 = 0
    private var lastAttemptedMercTransformDiscontinuitiesTotal: UInt64 = 0
    private var lastPersistedMercTargetControlEventsTotal: UInt64 = 0
    private var lastAttemptedMercTargetControlEventsTotal: UInt64 = 0
    private var lastPersistedMercWeightedSkinEvidenceTotal: UInt64 = 0
    private var lastAttemptedMercWeightedSkinEvidenceTotal: UInt64 = 0
    private var lastPersistedTargetHiddenTransitionsTotal: UInt64 = 0
    private var lastAttemptedTargetHiddenTransitionsTotal: UInt64 = 0
    private var reportedCameraDiagnosticsWriteFailure = false
    #endif

    var geometry: GOALPadSurfaceGeometry { GOALPadRenderSurface.shared.geometry() }

    // MARK: - Lifetime

    init() {
        saveSync.setGameplayReadinessHandler { [weak self] in
            self?.saveGameplayReadinessDidChange()
        }
    }

    func prepare() async {
        let processID = ProcessInfo.processInfo.processIdentifier
        sessionLog.notice("""
            ========== \(GOALPadBuildIdentity.displayText, privacy: .public) | \
            PID \(processID) ==========
            """)
        observeSystem()
        input.startWatching()
        try? GameDataLayout.prepare()
        await GameSessionPreparation.run(
            refreshDataReport: { await self.refreshDataReport() },
            prepareSettings: { await self.presentationSettings.prepare() },
            prepareSaves: { await self.saveSync.prepare() }
        )
        input.setPrimarySource(presentationSettings.primaryInputSource)
        input.setBindings(presentationSettings.jak1InputBindings)
    }

    func refreshDataReport() async {
        dataReport = await Task.detached { GameDataInspector.inspect() }.value
    }

    /// Bring the session up. Refuses rather than half-starting when the data on disk cannot boot
    /// the game, or when this build has no ahead-of-time Jak 1 code to boot.
    func start() async {
        guard !isRunning, !isBooting else { return }
        guard GOALPadRuntimeBridge.isGameCodeLinked else {
            startupError = "This build has no ahead-of-time \(GameLibraryTitle.jak1.name) code. "
                + "Run Scripts/generate-jak1-aot.sh and build again."
            return
        }
        guard dataReport.canBoot else {
            startupError = dataReport.summary
            return
        }

        guard let startupGeneration = startupState.begin(
            hasForegroundPreparation: foregroundPreparationTask != nil
        ) else { return }
        startupError = nil
        defer {
            if !isBooting, startupState.owns(generation: startupGeneration) {
                startupState.reset()
            }
        }

        let readiness = await GameplayStartupReadiness.resolve(
            currentForegroundPreparation: { self.foregroundPreparationTask },
            foregroundPreparationSucceeded: { self.lifecycle.frameLoopEnabled },
            isSceneActive: { self.currentScenePhase == .active },
            syncBeforeGameplay: { await self.saveSync.syncBeforeGameplay() },
            setPhase: {
                self.startupState.move(to: $0, generation: startupGeneration)
            }
        )
        guard startupState.owns(generation: startupGeneration) else { return }
        switch readiness {
        case .ready:
            break
        case .saveRecoveryFailed:
            startupError = Self.saveRecoveryMessage
            return
        case .sceneInactive:
            startupError = Self.inactiveStartupMessage
            return
        }
        guard !isRunning, !isBooting else { return }
        audio.resumeIfSuspended()

        let status = GOALPadRuntimeBridge.startKernel(
            withDataDirectory: GameDataLayout.gameDirectory.path,
            savesDirectory: SaveDataLayout.localSavesDirectory.path)
        kernel = status
        guard status.isRunning else {
            startupError = status.message
            return
        }

        saveSync.setGameplayActive(true)
        startupError = nil
        settings.apply()
        runReadiness = .preRun
        isBooting = true
        startupState.move(to: .booting, generation: startupGeneration)
        sessionLog.notice("Booting \(GameLibraryTitle.jak1.name, privacy: .public)")
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
        startupState.reset()
        guard status.isBooted else {
            startupError = status.message
            GOALPadRuntimeBridge.stopKernel()
            kernel = nil
            saveSync.setGameplayActive(false)
            return
        }

        isRunning = true
        updateNativeMenuState(mode: GOALPadRuntimeBridge.gameMode,
                              progress: NativeProgressMenuSnapshot(
                                GOALPadRuntimeBridge.progressMenuSnapshot),
                              titleStartState: GOALPadRuntimeBridge.titleStartState)
        updateWarpGateTouchSnapshot(NativeWarpGateTouchSnapshot(
            GOALPadRuntimeBridge.warpGateTouchSnapshot))
        updateCutsceneSkipTouchSnapshot(NativeCutsceneSkipTouchSnapshot(
            GOALPadRuntimeBridge.cutsceneSkipTouchSnapshot))
        updateFacePromptTouchSnapshot(NativeFacePromptTouchSnapshot(
            GOALPadRuntimeBridge.facePromptTouchSnapshot))
        lookAroundState = GOALPadRuntimeBridge.lookAroundState
        updateSpeederState(GOALPadRuntimeBridge.speederState)
        let active = lifecycle.activateWithoutPreparation()
        saveSync.setGameplayActive(active)
        audio.start()
        #if os(iOS) || os(visionOS)
        startCameraDiagnostics()
        #endif
        setIdleTimerDisabled(active)
        sessionLog.notice("Session started: \(status.message)")
    }

    func shutdown() {
        guard isRunning || kernel != nil || startupPhase != .idle else { return }
        foregroundPreparationTask?.cancel()
        foregroundPreparationTask = nil
        foregroundPreparationGeneration = nil
        lifecycle.resetForStoppedSession()
        startupState.reset()
        controlsGuideSuspension.reset()
        input.stopRumble()
        audio.stop()
        #if os(iOS) || os(visionOS)
        persistCameraDiagnosticsForLifecycleEvent()
        #endif
        GOALPadRuntimeBridge.stopKernel()
        kernel = nil
        boot = nil
        isRunning = false
        runReadiness = .preRun
        updateNativeMenuState(mode: .unknown, progress: .unavailable,
                              titleStartState: .unknown)
        updateWarpGateTouchSnapshot(.invalid)
        updateCutsceneSkipTouchSnapshot(.invalid)
        updateFacePromptTouchSnapshot(.invalid)
        lookAroundState = .unknown
        updateSpeederState(.unknown)
        saveSync.setGameplayActive(false)
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

    func presentTouchControlsGuide() {
        guard isRunning, controlsGuideSuspension.present() else { return }
        input.stopRumble()
        touch.reset()
        resetDisplayTiming()
        audio.suspend()
        sessionLog.notice("Touch controls guide suspended gameplay")
    }

    func dismissTouchControlsGuide() {
        guard controlsGuideSuspension.dismiss() else { return }
        guard isRunning, currentScenePhase == .active, lifecycle.frameLoopEnabled else { return }
        touch.restoreGameplayChromeAfterInterruption()
        audio.resumeIfSuspended()
        sessionLog.notice("Touch controls guide resumed gameplay")
    }

    // MARK: - The frame loop

    func tick(targetPresentationTime: CFTimeInterval) {
        guard isRunning, lifecycle.frameLoopEnabled,
              !controlsGuideSuspension.blocksGameplay else { return }
        let surface = GOALPadRenderSurface.shared
        guard surface.beginFrame(at: targetPresentationTime) else { return }
        _ = runArmedTick(targetPresentationTime: targetPresentationTime) {
            surface.endFrame()
        }
    }

    #if os(visionOS)
    func tickStereo(frame: VisionWindowStereoRenderFrame) -> VisionWindowStereoFrameDisposition {
        guard isRunning, lifecycle.frameLoopEnabled,
              !controlsGuideSuspension.blocksGameplay else { return .skipped }

        let left = GOALPadStereoRenderTarget(
            viewID: frame.left.viewID,
            colorTexture: frame.left.colorTexture,
            depthTexture: frame.left.depthTexture,
            clipFromGameClip: frame.left.clipFromGameClip
        )
        let right = GOALPadStereoRenderTarget(
            viewID: frame.right.viewID,
            colorTexture: frame.right.colorTexture,
            depthTexture: frame.right.depthTexture,
            clipFromGameClip: frame.right.clipFromGameClip
        )
        let surface = GOALPadRenderSurface.shared
        guard surface.beginStereoFrame(
            at: frame.targetPresentationTime,
            size: CGSize(width: CGFloat(frame.width), height: CGFloat(frame.height)),
            left: left,
            right: right
        ) else { return .failed }

        let framePresented = runArmedTick(targetPresentationTime: frame.targetPresentationTime) {
            surface.endStereoFrame()
        }
        return framePresented ? .rendered : .skipped
    }
    #endif

    private func runArmedTick(targetPresentationTime: CFTimeInterval,
                              endFrame: () -> Bool) -> Bool {
        recordDisplayCallback()
        #if os(iOS)
        input.pushFrame(merging: touch.frameState())
        #elseif os(visionOS)
        input.pushControllerFrame()
        #else
        input.pushFrame()
        #endif

        // The GOAL kernel's own frame: every process and state, then the overlord's vblank work.
        // Its DMA send renders synchronously while out-of-chain Merc bones still match the chain.
        var shouldLog = false
        if GOALPadRuntimeBridge.runFrame(at: targetPresentationTime) {
            framesRun = GOALPadRuntimeBridge.framesRun
            let currentMode = GOALPadRuntimeBridge.gameMode
            let currentProgress = NativeProgressMenuSnapshot(
                GOALPadRuntimeBridge.progressMenuSnapshot)
            let currentTitleStartState = GOALPadRuntimeBridge.titleStartState
            if currentMode != gameMode || currentProgress != progressMenuSnapshot
                || currentTitleStartState != titleStartState {
                updateNativeMenuState(mode: currentMode, progress: currentProgress,
                                      titleStartState: currentTitleStartState)
            }
            let currentWarpGateTouchSnapshot = NativeWarpGateTouchSnapshot(
                GOALPadRuntimeBridge.warpGateTouchSnapshot)
            if currentWarpGateTouchSnapshot != warpGateTouchSnapshot {
                updateWarpGateTouchSnapshot(currentWarpGateTouchSnapshot)
            }
            let currentCutsceneSkipTouchSnapshot = NativeCutsceneSkipTouchSnapshot(
                GOALPadRuntimeBridge.cutsceneSkipTouchSnapshot)
            if currentCutsceneSkipTouchSnapshot != cutsceneSkipTouchSnapshot {
                updateCutsceneSkipTouchSnapshot(currentCutsceneSkipTouchSnapshot)
            }
            let currentFacePromptTouchSnapshot = NativeFacePromptTouchSnapshot(
                GOALPadRuntimeBridge.facePromptTouchSnapshot)
            if currentFacePromptTouchSnapshot != facePromptTouchSnapshot {
                updateFacePromptTouchSnapshot(currentFacePromptTouchSnapshot)
            }
            let currentLookAroundState = GOALPadRuntimeBridge.lookAroundState
            if currentLookAroundState != lookAroundState {
                lookAroundState = currentLookAroundState
            }
            let currentSpeederState = GOALPadRuntimeBridge.speederState
            if currentSpeederState != speederState {
                updateSpeederState(currentSpeederState)
            }
            shouldLog = framesRun % 600 == 0
            saveSync.gameplayFrameCompleted()
        }

        let framePresented = endFrame()
        if framePresented {
            framesPresented += 1
        }
        let renderer = GOALPadRenderSurface.shared.stats
        // File snapshots remain available at startup and lifecycle boundaries, never in this
        // display callback.
        if shouldLog { logRunningState(renderer: renderer) }
        input.applyRumble()
        return framePresented
    }

    private func updateNativeMenuState(mode: GOALPadGameMode,
                                       progress: NativeProgressMenuSnapshot,
                                       titleStartState: GOALPadTitleStartState) {
        runReadiness = GameplayRunReadiness.advance(
            runReadiness, mode: mode, titleStartState: titleStartState, progress: progress)
        gameMode = mode
        progressMenuSnapshot = progress
        self.titleStartState = titleStartState
        touch.setNativeMenuState(mode, progress: progress, titleStartState: titleStartState,
                                 runReadiness: runReadiness)
    }

    private func updateWarpGateTouchSnapshot(_ snapshot: NativeWarpGateTouchSnapshot) {
        warpGateTouchSnapshot = snapshot
        touch.setWarpGateTouchSnapshot(snapshot)
    }

    private func updateCutsceneSkipTouchSnapshot(_ snapshot: NativeCutsceneSkipTouchSnapshot) {
        cutsceneSkipTouchSnapshot = snapshot
        touch.setCutsceneSkipTouchSnapshot(snapshot)
    }

    private func updateFacePromptTouchSnapshot(_ snapshot: NativeFacePromptTouchSnapshot) {
        facePromptTouchSnapshot = snapshot
        touch.setFacePromptTouchSnapshot(snapshot)
    }

    private func updateSpeederState(_ state: GOALPadSpeederState) {
        speederState = state
        touch.setSpeederState(state)
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
            alternations \(renderer.producerCameraAlternations), render alternations \
            \(renderer.renderCameraAlternations), event frames \
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

    #if os(iOS) || os(visionOS)
    private func startCameraDiagnostics() {
        cameraDiagnosticsURL = nil
        cameraDiagnosticsRunID = UInt64.random(in: 1...UInt64.max)
        lastPersistedCameraTailTriggerFrame = 0
        lastAttemptedCameraTailTriggerFrame = 0
        lastCameraTailWriteEngineFrame = 0
        lastPersistedMercMissingBoneSlotsTotal = 0
        lastAttemptedMercMissingBoneSlotsTotal = 0
        lastPersistedMercModelsWithMissingBoneSlotsTotal = 0
        lastAttemptedMercModelsWithMissingBoneSlotsTotal = 0
        lastPersistedMercPaletteHealthTotal = 0
        lastAttemptedMercPaletteHealthTotal = 0
        lastPersistedMercTransformDiscontinuitiesTotal = 0
        lastAttemptedMercTransformDiscontinuitiesTotal = 0
        lastPersistedMercTargetControlEventsTotal = 0
        lastAttemptedMercTargetControlEventsTotal = 0
        lastPersistedMercWeightedSkinEvidenceTotal = 0
        lastAttemptedMercWeightedSkinEvidenceTotal = 0
        lastPersistedTargetHiddenTransitionsTotal = 0
        lastAttemptedTargetHiddenTransitionsTotal = 0
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
            let targetControl = GOALPadRenderSurface.shared.targetControlTelemetry
            lastAttemptedMercMissingBoneSlotsTotal = renderer.mercMissingBoneSlotsTotal
            lastAttemptedMercModelsWithMissingBoneSlotsTotal =
                renderer.mercModelsWithMissingBoneSlotsTotal
            lastAttemptedMercPaletteHealthTotal = mercPaletteHealthTotal(renderer)
            lastAttemptedMercTransformDiscontinuitiesTotal =
                renderer.mercEicharTransformDiscontinuitiesTotal
            lastAttemptedMercTargetControlEventsTotal =
                renderer.mercEicharTargetControlEventsTotal
            lastAttemptedMercWeightedSkinEvidenceTotal =
                renderer.mercEicharWeightedSkinEvidenceTotal
            lastAttemptedTargetHiddenTransitionsTotal = targetControl.hiddenTransitionsTotal
            let writtenTail = try writeCameraDiagnostics(renderer, targetControl: targetControl)
            if writtenTail.complete.boolValue {
                lastAttemptedCameraTailTriggerFrame = writtenTail.triggerEngineFrameID
                lastPersistedCameraTailTriggerFrame = writtenTail.triggerEngineFrameID
                lastCameraTailWriteEngineFrame = renderer.lastEngineFrameID
            }
            lastPersistedMercMissingBoneSlotsTotal = renderer.mercMissingBoneSlotsTotal
            lastPersistedMercModelsWithMissingBoneSlotsTotal =
                renderer.mercModelsWithMissingBoneSlotsTotal
            lastPersistedMercPaletteHealthTotal = mercPaletteHealthTotal(renderer)
            lastPersistedMercTransformDiscontinuitiesTotal =
                renderer.mercEicharTransformDiscontinuitiesTotal
            lastPersistedMercTargetControlEventsTotal =
                renderer.mercEicharTargetControlEventsTotal
            lastPersistedMercWeightedSkinEvidenceTotal =
                renderer.mercEicharWeightedSkinEvidenceTotal
            lastPersistedTargetHiddenTransitionsTotal = targetControl.hiddenTransitionsTotal
        } catch {
            reportCameraDiagnosticsWriteFailure()
        }
    }

    private func persistCameraDiagnosticsIfNeeded(
        _ renderer: GOALPadRendererStats,
        targetControl: GOALPadTargetControlTelemetry,
        periodic: Bool,
        forced: Bool = false
    ) {
        guard cameraDiagnosticsURL != nil else { return }
        let tailInfo = GOALPadRenderSurface.shared.cameraCorrectionTailInfo
        let completedTailTriggerFrame = tailInfo.complete.boolValue
            ? tailInfo.triggerEngineFrameID : 0
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
        let targetControlNotPersisted = renderer.mercEicharTargetControlEventsTotal
            > lastPersistedMercTargetControlEventsTotal
        let targetControlNotAttempted = renderer.mercEicharTargetControlEventsTotal
            > lastAttemptedMercTargetControlEventsTotal
        let weightedSkinNotAttempted = CameraDiagnosticsPersistencePolicy.hasUnattemptedEvidence(
            total: renderer.mercEicharWeightedSkinEvidenceTotal,
            persisted: lastPersistedMercWeightedSkinEvidenceTotal,
            attempted: lastAttemptedMercWeightedSkinEvidenceTotal)
        let hiddenTransitionNotPersisted = targetControl.hiddenTransitionsTotal
            > lastPersistedTargetHiddenTransitionsTotal
        let hiddenTransitionNotAttempted = targetControl.hiddenTransitionsTotal
            > lastAttemptedTargetHiddenTransitionsTotal
        let mercCompletenessIncreased = (missingSlotsNotPersisted && missingSlotsNotAttempted)
            || (missingModelsNotPersisted && missingModelsNotAttempted)
        let hasImmediateNonCameraEvidence = mercCompletenessIncreased
            || (paletteHealthNotPersisted && paletteHealthNotAttempted)
            || (mercTransformNotPersisted && mercTransformNotAttempted)
            || (targetControlNotPersisted && targetControlNotAttempted)
            || weightedSkinNotAttempted
            || (hiddenTransitionNotPersisted && hiddenTransitionNotAttempted)
        guard CameraDiagnosticsPersistencePolicy.shouldPersist(
            forced: forced,
            periodic: periodic,
            hasImmediateNonCameraEvidence: hasImmediateNonCameraEvidence,
            completedTailTriggerFrame: completedTailTriggerFrame,
            lastPersistedTailTriggerFrame: lastPersistedCameraTailTriggerFrame,
            lastAttemptedTailTriggerFrame: lastAttemptedCameraTailTriggerFrame,
            currentEngineFrame: renderer.lastEngineFrameID,
            lastTailWriteEngineFrame: lastCameraTailWriteEngineFrame) else {
            return
        }

        if completedTailTriggerFrame != 0 {
            lastAttemptedCameraTailTriggerFrame = completedTailTriggerFrame
        }
        lastAttemptedMercMissingBoneSlotsTotal = renderer.mercMissingBoneSlotsTotal
        lastAttemptedMercModelsWithMissingBoneSlotsTotal =
            renderer.mercModelsWithMissingBoneSlotsTotal
        lastAttemptedMercPaletteHealthTotal = paletteHealthTotal
        lastAttemptedMercTransformDiscontinuitiesTotal =
            renderer.mercEicharTransformDiscontinuitiesTotal
        lastAttemptedMercTargetControlEventsTotal =
            renderer.mercEicharTargetControlEventsTotal
        lastAttemptedMercWeightedSkinEvidenceTotal =
            renderer.mercEicharWeightedSkinEvidenceTotal
        lastAttemptedTargetHiddenTransitionsTotal = targetControl.hiddenTransitionsTotal
        do {
            let writtenTail = try writeCameraDiagnostics(renderer, targetControl: targetControl)
            if writtenTail.complete.boolValue {
                lastPersistedCameraTailTriggerFrame = writtenTail.triggerEngineFrameID
                lastCameraTailWriteEngineFrame = renderer.lastEngineFrameID
            }
            lastPersistedMercMissingBoneSlotsTotal = renderer.mercMissingBoneSlotsTotal
            lastPersistedMercModelsWithMissingBoneSlotsTotal =
                renderer.mercModelsWithMissingBoneSlotsTotal
            lastPersistedMercPaletteHealthTotal = paletteHealthTotal
            lastPersistedMercTransformDiscontinuitiesTotal =
                renderer.mercEicharTransformDiscontinuitiesTotal
            lastPersistedMercTargetControlEventsTotal =
                renderer.mercEicharTargetControlEventsTotal
            lastPersistedMercWeightedSkinEvidenceTotal =
                renderer.mercEicharWeightedSkinEvidenceTotal
            lastPersistedTargetHiddenTransitionsTotal = targetControl.hiddenTransitionsTotal
        } catch {
            reportCameraDiagnosticsWriteFailure()
        }
    }

    private func persistCameraDiagnosticsForLifecycleEvent() {
        let surface = GOALPadRenderSurface.shared
        guard isRunning, surface.isRendererLinked else { return }
        persistCameraDiagnosticsIfNeeded(surface.stats,
                                         targetControl: surface.targetControlTelemetry,
                                         periodic: false,
                                         forced: true)
    }

    private func mercPaletteHealthTotal(_ renderer: GOALPadRendererStats) -> UInt64 {
        renderer.mercNonfiniteBoneMatricesTotal
            + renderer.mercDegenerateBoneMatricesTotal
            + renderer.mercIncoherentBoneSourcesTotal
    }

    private func writeCameraDiagnostics(
        _ renderer: GOALPadRendererStats,
        targetControl: GOALPadTargetControlTelemetry
    ) throws -> GOALPadCameraCorrectionTailInfo {
        guard let cameraDiagnosticsURL else { return GOALPadCameraCorrectionTailInfo() }
        let renderSurface = GOALPadRenderSurface.shared
        let cameraTail = renderSurface.cameraCorrectionTailSnapshot
        let cameraTailInfo = cameraTail.info
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
                "\(prefix)_issue_scale=\((event.issueMask & 1) != 0 ? 1 : 0)",
                "\(prefix)_issue_aspect=\((event.issueMask & 2) != 0 ? 1 : 0)",
                "\(prefix)_issue_input_root_aba=\((event.issueMask & 4) != 0 ? 1 : 0)",
                "\(prefix)_issue_output_only_aba=\((event.issueMask & 8) != 0 ? 1 : 0)",
                "\(prefix)_issue_camera_driven_aba=\((event.issueMask & 16) != 0 ? 1 : 0)",
                "\(prefix)_issue_output_stale=\((event.issueMask & 32) != 0 ? 1 : 0)",
                "\(prefix)_issue_source_mapping=\((event.issueMask & 64) != 0 ? 1 : 0)",
                "\(prefix)_issue_output_expected=\((event.issueMask & 128) != 0 ? 1 : 0)",
                "\(prefix)_bone_slot=\(event.boneSlot)",
                "\(prefix)_model_hash=\(event.modelNameHash)",
                "\(prefix)_older_frame=\(event.olderFrameID)",
                "\(prefix)_previous_frame=\(event.previousFrameID)",
                "\(prefix)_current_frame=\(event.currentFrameID)",
                "\(prefix)_older_matrix_hash=\(event.olderMatrixHash)",
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
                "\(prefix)_older_source_base=\(event.olderSourceBase)",
                "\(prefix)_previous_source_base=\(event.previousSourceBase)",
                "\(prefix)_current_source_base=\(event.currentSourceBase)",
                "\(prefix)_input_root_bone=\(event.inputRootBone)",
                "\(prefix)_older_producer_serial=\(event.olderProducerSerial)",
                "\(prefix)_previous_producer_serial=\(event.previousProducerSerial)",
                "\(prefix)_current_producer_serial=\(event.currentProducerSerial)",
                "\(prefix)_previous_producer_output_hash=\(event.previousProducerOutputHash)",
                "\(prefix)_current_producer_output_hash=\(event.currentProducerOutputHash)",
                "\(prefix)_previous_renderer_output_hash=\(event.previousRendererOutputHash)",
                "\(prefix)_current_renderer_output_hash=\(event.currentRendererOutputHash)",
                "\(prefix)_older_input_root_hash=\(event.olderInputRootHash)",
                "\(prefix)_previous_input_root_hash=\(event.previousInputRootHash)",
                "\(prefix)_current_input_root_hash=\(event.currentInputRootHash)",
                "\(prefix)_older_camera_hash=\(event.olderCameraHash)",
                "\(prefix)_previous_camera_hash=\(event.previousCameraHash)",
                "\(prefix)_current_camera_hash=\(event.currentCameraHash)",
                "\(prefix)_previous_bind_pose_hash=\(event.previousBindPoseHash)",
                "\(prefix)_current_bind_pose_hash=\(event.currentBindPoseHash)",
                "\(prefix)_input_distance_older_previous="
                    + decimal(event.inputOlderToPreviousDistance),
                "\(prefix)_input_distance_previous_current="
                    + decimal(event.inputPreviousToCurrentDistance),
                "\(prefix)_input_distance_older_current="
                    + decimal(event.inputOlderToCurrentDistance),
                "\(prefix)_output_distance_older_previous="
                    + decimal(event.outputOlderToPreviousDistance),
                "\(prefix)_output_distance_previous_current="
                    + decimal(event.outputPreviousToCurrentDistance),
                "\(prefix)_output_distance_older_current="
                    + decimal(event.outputOlderToCurrentDistance),
                "\(prefix)_previous_output_expected_distance="
                    + decimal(event.previousOutputExpectedDistance),
                "\(prefix)_current_output_expected_distance="
                    + decimal(event.currentOutputExpectedDistance),
                "\(prefix)_camera_distance_older_previous="
                    + decimal(event.cameraOlderToPreviousDistance),
                "\(prefix)_camera_distance_previous_current="
                    + decimal(event.cameraPreviousToCurrentDistance),
                "\(prefix)_camera_distance_older_current="
                    + decimal(event.cameraOlderToCurrentDistance),
                "\(prefix)_previous_input_translation_x="
                    + decimal(event.previousInputTranslationX),
                "\(prefix)_previous_input_translation_y="
                    + decimal(event.previousInputTranslationY),
                "\(prefix)_previous_input_translation_z="
                    + decimal(event.previousInputTranslationZ),
                "\(prefix)_current_input_translation_x="
                    + decimal(event.currentInputTranslationX),
                "\(prefix)_current_input_translation_y="
                    + decimal(event.currentInputTranslationY),
                "\(prefix)_current_input_translation_z="
                    + decimal(event.currentInputTranslationZ),
            ]
        }
        func mercPaletteHealthFields(_ prefix: String,
                                     _ event: GOALPadMercPaletteHealthEvent) -> [String] {
            [
                "\(prefix)_engine_frame=\(event.engineFrameID)",
                "\(prefix)_host_tick=\(event.hostTickID)",
                "\(prefix)_chain=\(event.chainOrdinal)",
                "\(prefix)_issue_mask=\(event.issueMask)",
                "\(prefix)_issue_nonfinite=\((event.issueMask & 1) != 0 ? 1 : 0)",
                "\(prefix)_issue_degenerate=\((event.issueMask & 2) != 0 ? 1 : 0)",
                "\(prefix)_issue_source_base=\((event.issueMask & 4) != 0 ? 1 : 0)",
                "\(prefix)_nonfinite_lane_mask=\(event.nonfiniteLaneMask)",
                "\(prefix)_bone_slot=\(event.boneSlot)",
                "\(prefix)_model_hash=\(event.modelNameHash)",
                "\(prefix)_matrix_hash=\(event.matrixHash)",
                "\(prefix)_axis_norm_x=\(decimal(event.axisNormX))",
                "\(prefix)_axis_norm_y=\(decimal(event.axisNormY))",
                "\(prefix)_axis_norm_z=\(decimal(event.axisNormZ))",
                "\(prefix)_normalized_abs_det="
                    + decimal(event.normalizedAbsDeterminant),
                "\(prefix)_source_address=\(event.sourceAddress)",
                "\(prefix)_source_base=\(event.sourceBase)",
                "\(prefix)_expected_source_base=\(event.expectedSourceBase)",
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
        func cameraRotationAxesFields(
            _ prefix: String,
            _ axes: GOALPadCameraCorrectionRotationAxes
        ) -> [String] {
            cameraVectorFields("\(prefix)_axis0", axes.axis0)
                + cameraVectorFields("\(prefix)_axis1", axes.axis1)
                + cameraVectorFields("\(prefix)_axis2", axes.axis2)
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
                "\(prefix)_max_angle_offset=\(decimal(slave.maxAngleOffset))",
                "\(prefix)_max_angle_current=\(decimal(slave.maxAngleCurrent))",
            ]
                + cameraVectorFields("\(prefix)_transform", slave.transform)
                + cameraRotationAxesFields("\(prefix)_tracking_inverse_matrix",
                                           slave.trackingInverseMatrix)
                + cameraVectorFields("\(prefix)_view_flat", slave.viewFlat)
                + cameraVectorFields("\(prefix)_string_transform", slave.stringTransform)
                + cameraVectorFields("\(prefix)_desired_position", slave.desiredPosition)
        }
        func cameraFrameFields(_ prefix: String,
                               _ frame: GOALPadCameraCorrectionFrame) -> [String] {
            [
                "\(prefix)_valid=\(frame.valid.boolValue ? 1 : 0)",
                "\(prefix)_engine_frame=\(frame.engineFrameID)",
                "\(prefix)_math_camera_object=\(frame.mathCameraObjectOffset)",
                "\(prefix)_math_camera_type=\(frame.mathCameraTypeOffset)",
                "\(prefix)_master_object=\(frame.masterObjectOffset)",
                "\(prefix)_master_type=\(frame.masterTypeOffset)",
                "\(prefix)_combiner_object=\(frame.combinerObjectOffset)",
                "\(prefix)_combiner_type=\(frame.combinerTypeOffset)",
                "\(prefix)_slave0_ppointer=\(frame.slave0PpointerOffset)",
                "\(prefix)_slave0_object=\(frame.slave0ObjectOffset)",
                "\(prefix)_slave0_type=\(frame.slave0TypeOffset)",
                "\(prefix)_slave1_ppointer=\(frame.slave1PpointerOffset)",
                "\(prefix)_slave1_object=\(frame.slave1ObjectOffset)",
                "\(prefix)_slave1_type=\(frame.slave1TypeOffset)",
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
                + cameraRotationAxesFields("\(prefix)_combiner_inverse_camera_rotation",
                                           frame.combinerInverseCameraRotation)
        }
        func cameraCorrectionFields(_ event: GOALPadCameraCorrectionEvent) -> [String] {
            [
                "camera_correction_valid=\(event.valid.boolValue ? 1 : 0)",
                "camera_correction_reason_mask=\(event.reasonMask)",
                "camera_correction_reason_los_transition="
                    + "\((event.reasonMask & 1) != 0 ? 1 : 0)",
                "camera_correction_reason_producer_alternation="
                    + "\((event.reasonMask & 2) != 0 ? 1 : 0)",
                "camera_correction_reason_large_orientation_delta="
                    + "\((event.reasonMask & 4) != 0 ? 1 : 0)",
                "camera_correction_reason_render_alternation="
                    + "\((event.reasonMask & 8) != 0 ? 1 : 0)",
                "camera_correction_host_tick=\(event.hostTickID)",
                "camera_correction_chain=\(event.chainOrdinal)",
            ]
                + cameraFrameFields("camera_correction_older", event.older)
                + cameraFrameFields("camera_correction_previous", event.previous)
                + cameraFrameFields("camera_correction_current", event.current)
        }
        func compactCameraVector(_ vector: GOALPadCameraCorrectionVector) -> String {
            "\(decimal(vector.x)),\(decimal(vector.y)),\(decimal(vector.z))"
        }
        func compactCameraAxes(_ axes: GOALPadCameraCorrectionRotationAxes) -> String {
            compactCameraVector(axes.axis0) + "," + compactCameraVector(axes.axis1)
                + "," + compactCameraVector(axes.axis2)
        }
        func compactCameraSlave(_ slave: GOALPadCameraCorrectionSlaveFrame) -> String {
            [
                slave.valid.boolValue ? "1" : "0",
                String(slave.options), String(slave.losState),
                String(slave.stringVelocityDirection),
                slave.lineOfSightEnabled.boolValue ? "1" : "0",
                slave.movementBlocked.boolValue ? "1" : "0",
                decimal(slave.minimumDistanceOverride), decimal(slave.maxAngleOffset),
                decimal(slave.maxAngleCurrent), compactCameraVector(slave.transform),
                compactCameraAxes(slave.trackingInverseMatrix),
                compactCameraVector(slave.viewFlat), compactCameraVector(slave.stringTransform),
                compactCameraVector(slave.desiredPosition),
            ].joined(separator: ",")
        }
        func cameraTailFrameFields(
            _ index: UInt32,
            _ tailFrame: GOALPadCameraCorrectionTailFrame
        ) -> [String] {
            let prefix = "camera_tail_\(index)"
            let frame = tailFrame.camera
            return [
                "\(prefix)_valid=\(tailFrame.valid.boolValue ? 1 : 0)",
                "\(prefix)_frame=\(frame.engineFrameID)",
                "\(prefix)_tick=\(tailFrame.hostTickID)",
                "\(prefix)_chain=\(tailFrame.chainOrdinal)",
                "\(prefix)_render_fingerprint=\(tailFrame.renderCameraFingerprint)",
                "\(prefix)_identity=\(frame.mathCameraObjectOffset),"
                    + "\(frame.mathCameraTypeOffset),\(frame.masterObjectOffset),"
                    + "\(frame.masterTypeOffset),\(frame.combinerObjectOffset),"
                    + "\(frame.combinerTypeOffset),\(frame.slave0PpointerOffset),"
                    + "\(frame.slave0ObjectOffset),\(frame.slave0TypeOffset),"
                    + "\(frame.slave1PpointerOffset),\(frame.slave1ObjectOffset),"
                    + "\(frame.slave1TypeOffset)",
                "\(prefix)_master=\(decimal(frame.displayTimeRatio)),\(frame.numSlaves),"
                    + "\(frame.beingAttacked.boolValue ? 1 : 0),"
                    + compactCameraVector(frame.targetPosition) + ","
                    + compactCameraVector(frame.adjustedTargetPosition),
                "\(prefix)_slave0=" + compactCameraSlave(frame.slave0),
                "\(prefix)_slave1=" + compactCameraSlave(frame.slave1),
                "\(prefix)_combiner=\(frame.combinerValid.boolValue ? 1 : 0),"
                    + "\(decimal(frame.combinerInterpolation)),"
                    + "\(frame.combinerTrackingStatus),"
                    + compactCameraVector(frame.combinerTransform) + ","
                    + compactCameraAxes(frame.combinerInverseCameraRotation),
            ]
        }
        func targetControlFields(_ prefix: String,
                                 _ event: GOALPadTargetControlEvent) -> [String] {
            [
                "\(prefix)_host_tick=\(event.hostTickID)",
                "\(prefix)_chain=\(event.chainOrdinal)",
                "\(prefix)_issue_mask=\(event.issueMask)",
                "\(prefix)_issue_facing_divergence="
                    + "\((event.issueMask & 1) != 0 ? 1 : 0)",
                "\(prefix)_issue_attack_boundary="
                    + "\((event.issueMask & 2) != 0 ? 1 : 0)",
                "\(prefix)_engine_frame=\(event.engineFrameID)",
                "\(prefix)_producer_serial=\(event.producerSerial)",
                "\(prefix)_source_base=\(event.sourceBase)",
                "\(prefix)_target_state_id=\(event.targetStateID)",
                "\(prefix)_previous_target_attack_id=\(event.previousTargetAttackID)",
                "\(prefix)_current_target_attack_id=\(event.currentTargetAttackID)",
                "\(prefix)_button0_abs=\(event.button0Abs)",
                "\(prefix)_button0_rel=\(event.button0Rel)",
                "\(prefix)_left_x=\(event.leftX)",
                "\(prefix)_left_y=\(event.leftY)",
                "\(prefix)_stick_direction=\(decimal(event.stickDirection))",
                "\(prefix)_stick_speed=\(decimal(event.stickSpeed))",
                "\(prefix)_pad_magnitude=\(decimal(event.padMagnitude))",
                "\(prefix)_intent_forward_x=\(decimal(event.intentForwardX))",
                "\(prefix)_intent_forward_z=\(decimal(event.intentForwardZ))",
                "\(prefix)_desired_forward_x=\(decimal(event.desiredForwardX))",
                "\(prefix)_desired_forward_z=\(decimal(event.desiredForwardZ))",
                "\(prefix)_control_forward_x=\(decimal(event.controlForwardX))",
                "\(prefix)_control_forward_z=\(decimal(event.controlForwardZ))",
                "\(prefix)_render_forward_x=\(decimal(event.renderForwardX))",
                "\(prefix)_render_forward_z=\(decimal(event.renderForwardZ))",
                "\(prefix)_root_forward_x=\(decimal(event.rootForwardX))",
                "\(prefix)_root_forward_z=\(decimal(event.rootForwardZ))",
                "\(prefix)_intent_control_dot=\(decimal(event.intentControlDot))",
                "\(prefix)_control_render_dot=\(decimal(event.controlRenderDot))",
                "\(prefix)_render_root_dot=\(decimal(event.renderRootDot))",
            ]
        }
        func targetControlVectorFields(_ prefix: String,
                                       _ vector: GOALPadTargetControlVector4) -> [String] {
            [
                "\(prefix)_x=\(decimal(vector.x))",
                "\(prefix)_y=\(decimal(vector.y))",
                "\(prefix)_z=\(decimal(vector.z))",
                "\(prefix)_w=\(decimal(vector.w))",
            ]
        }
        func targetControlFacingFields(_ prefix: String,
                                       _ facing: GOALPadTargetControlFacing) -> [String] {
            [
                "\(prefix)_valid=\(facing.valid.boolValue ? 1 : 0)",
                "\(prefix)_x=\(decimal(facing.x))",
                "\(prefix)_z=\(decimal(facing.z))",
            ]
        }
        func targetControlBasisFields(_ prefix: String,
                                      _ basis: GOALPadTargetControlBasis) -> [String] {
            [
                "\(prefix)_valid=\(basis.valid.boolValue ? 1 : 0)",
                "\(prefix)_axis0_x=\(decimal(basis.axis0X))",
                "\(prefix)_axis0_y=\(decimal(basis.axis0Y))",
                "\(prefix)_axis0_z=\(decimal(basis.axis0Z))",
                "\(prefix)_axis1_x=\(decimal(basis.axis1X))",
                "\(prefix)_axis1_y=\(decimal(basis.axis1Y))",
                "\(prefix)_axis1_z=\(decimal(basis.axis1Z))",
                "\(prefix)_axis2_x=\(decimal(basis.axis2X))",
                "\(prefix)_axis2_y=\(decimal(basis.axis2Y))",
                "\(prefix)_axis2_z=\(decimal(basis.axis2Z))",
            ]
        }
        func targetControlDeformationFields(
            _ prefix: String,
            _ deformation: GOALPadTargetControlDeformation
        ) -> [String] {
            [
                "\(prefix)_valid=\(deformation.valid.boolValue ? 1 : 0)",
                "\(prefix)_axis_norm_x=\(decimal(deformation.axisNormX))",
                "\(prefix)_axis_norm_y=\(decimal(deformation.axisNormY))",
                "\(prefix)_axis_norm_z=\(decimal(deformation.axisNormZ))",
                "\(prefix)_aspect=\(decimal(deformation.aspect))",
                "\(prefix)_normalized_abs_det="
                    + decimal(deformation.normalizedAbsDeterminant),
            ]
        }
        func targetControlRootAnchorFields(
            _ prefix: String,
            _ anchor: GOALPadTargetControlRootAnchor
        ) -> [String] {
            [
                "\(prefix)_valid=\(anchor.valid.boolValue ? 1 : 0)",
                "\(prefix)_scale_x=\(decimal(anchor.scaleX))",
                "\(prefix)_scale_y=\(decimal(anchor.scaleY))",
                "\(prefix)_scale_z=\(decimal(anchor.scaleZ))",
                "\(prefix)_scale_w_bits=\(anchor.scaleWBits)",
            ] + targetControlDeformationFields("\(prefix)_deformation", anchor.deformation)
        }
        func targetPostFlagFields(
            _ prefix: String,
            _ observation: GOALPadTargetPostFlagObservation
        ) -> [String] {
            [
                "\(prefix)_valid=\(observation.valid.boolValue ? 1 : 0)",
                "\(prefix)_host_tick=\(observation.hostTickID)",
                "\(prefix)_chain=\(observation.chainOrdinal)",
                "\(prefix)_engine_frame=\(observation.engineFrameID)",
                "\(prefix)_sample_serial=\(observation.sampleSerial)",
                "\(prefix)_target=\(observation.targetAddress)",
                "\(prefix)_raw_draw_status=\(observation.rawDrawStatus)",
                "\(prefix)_target_attack_id=\(observation.targetAttackID)",
                "\(prefix)_hidden=\(observation.hidden.boolValue ? 1 : 0)",
            ]
        }
        func targetControlObservationFields(
            _ prefix: String,
            _ observation: GOALPadTargetControlObservation
        ) -> [String] {
            [
                "\(prefix)_valid=\(observation.valid.boolValue ? 1 : 0)",
                "\(prefix)_host_tick=\(observation.hostTickID)",
                "\(prefix)_chain=\(observation.chainOrdinal)",
                "\(prefix)_engine_frame=\(observation.engineFrameID)",
                "\(prefix)_probe_bone_slot=\(observation.probeBoneSlot)",
                "\(prefix)_producer_serial=\(observation.producerSerial)",
                "\(prefix)_source_base=\(observation.sourceBase)",
                "\(prefix)_camera_hash=\(observation.cameraHash)",
                "\(prefix)_target_state_id=\(observation.targetStateID)",
                "\(prefix)_target_attack_id=\(observation.targetAttackID)",
                "\(prefix)_button0_abs=\(observation.button0Abs)",
                "\(prefix)_button0_rel=\(observation.button0Rel)",
                "\(prefix)_left_x=\(observation.leftX)",
                "\(prefix)_left_y=\(observation.leftY)",
                "\(prefix)_stick_direction=\(decimal(observation.stickDirection))",
                "\(prefix)_stick_speed=\(decimal(observation.stickSpeed))",
                "\(prefix)_pad_magnitude=\(decimal(observation.padMagnitude))",
                "\(prefix)_input_root_translation_x="
                    + decimal(observation.inputRootTranslationX),
                "\(prefix)_input_root_translation_y="
                    + decimal(observation.inputRootTranslationY),
                "\(prefix)_input_root_translation_z="
                    + decimal(observation.inputRootTranslationZ),
                "\(prefix)_node3_parent_scale_cancellation_selected="
                    + (observation.node3ParentScaleCancellationSelected.boolValue ? "1" : "0"),
            ]
                + targetControlVectorFields("\(prefix)_raw_dir_targ",
                                            observation.rawDirTarg)
                + targetControlVectorFields("\(prefix)_raw_quat_for_control",
                                            observation.rawQuatForControl)
                + targetControlVectorFields("\(prefix)_raw_render_quat",
                                            observation.rawRenderQuat)
                + targetControlVectorFields("\(prefix)_raw_turn_to_target",
                                            observation.rawTurnToTarget)
                + targetControlFacingFields("\(prefix)_intent_forward",
                                            observation.intentForward)
                + targetControlFacingFields("\(prefix)_desired_forward",
                                            observation.desiredForward)
                + targetControlFacingFields("\(prefix)_control_forward",
                                            observation.controlForward)
                + targetControlFacingFields("\(prefix)_render_forward",
                                            observation.renderForward)
                + targetControlFacingFields("\(prefix)_root_forward",
                                            observation.rootForward)
                + targetControlBasisFields("\(prefix)_camera_basis",
                                           observation.cameraBasis)
                + targetControlDeformationFields("\(prefix)_input_root_deformation",
                                                 observation.inputRootDeformation)
                + targetControlDeformationFields("\(prefix)_output_deformation",
                                                 observation.outputDeformation)
                + targetControlRootAnchorFields("\(prefix)_root1", observation.rootAnchor1)
                + targetControlRootAnchorFields("\(prefix)_root2", observation.rootAnchor2)
                + targetControlRootAnchorFields("\(prefix)_root3", observation.rootAnchor3)
        }

        var cameraTailFields = [
            "camera_tail_valid=\(cameraTailInfo.valid.boolValue ? 1 : 0)",
            "camera_tail_complete=\(cameraTailInfo.complete.boolValue ? 1 : 0)",
            "camera_tail_count=\(cameraTailInfo.frameCount)",
            "camera_tail_trigger_frame=\(cameraTailInfo.triggerEngineFrameID)",
            "camera_tail_trigger_degrees=\(decimal(cameraTailInfo.triggerOrientationDegrees))",
        ]
        for index in 0..<cameraTailInfo.frameCount {
            cameraTailFields += cameraTailFrameFields(
                index, cameraTail.frame(at: index))
        }

        let fields = [
            "goalpad_camera_provenance", "v=7", "run=\(cameraDiagnosticsRunID)",
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
            "jak1_tie_envmap_second_pass_enabled="
                + "\(renderer.jak1TieEnvmapSecondPassEnabled.boolValue ? 1 : 0)",
            "tie_envmap_second_pass_draws=\(renderer.tieEnvmapSecondPassDraws)",
            "tie_envmap_second_pass_draws_total="
                + "\(renderer.tieEnvmapSecondPassDrawsTotal)",
            "jak1_shadow_output_enabled="
                + "\(renderer.jak1ShadowOutputEnabled.boolValue ? 1 : 0)",
            "producer_alternations=\(renderer.producerCameraAlternations)",
            "render_alternations=\(renderer.renderCameraAlternations)",
            "render_alternation_older_frame="
                + "\(renderer.lastRenderCameraAlternationOlderFrameID)",
            "render_alternation_previous_frame="
                + "\(renderer.lastRenderCameraAlternationPreviousFrameID)",
            "render_alternation_current_frame="
                + "\(renderer.lastRenderCameraAlternationCurrentFrameID)",
            "render_alternation_older_fingerprint="
                + "\(renderer.lastRenderCameraAlternationOlderFingerprint)",
            "render_alternation_previous_fingerprint="
                + "\(renderer.lastRenderCameraAlternationPreviousFingerprint)",
            "render_alternation_current_fingerprint="
                + "\(renderer.lastRenderCameraAlternationCurrentFingerprint)",
            "render_alternation_host_tick="
                + "\(renderer.lastRenderCameraAlternationHostTickID)",
            "render_alternation_chain="
                + "\(renderer.lastRenderCameraAlternationChainOrdinal)",
            "render_alternation_packet_fingerprint="
                + "\(renderer.lastRenderCameraAlternationPacketFingerprint)",
            "render_alternation_live_mismatch_qwords="
                + "\(renderer.lastRenderCameraAlternationLiveMismatchQwords)",
            "render_alternation_packet_mismatch_qwords="
                + "\(renderer.lastRenderCameraAlternationPacketMismatchQwords)",
            "render_distance_older_previous="
                + decimal(renderer.lastRenderCameraOlderToPreviousDistance),
            "render_distance_previous_current="
                + decimal(renderer.lastRenderCameraPreviousToCurrentDistance),
            "render_distance_older_current="
                + decimal(renderer.lastRenderCameraOlderToCurrentDistance),
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
            "last_merc_palette_health_nonfinite_lane_mask="
                + "\(renderer.lastMercPaletteHealthNonfiniteLaneMask)",
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
            "merc_eichar_provenance_events="
                + "\(renderer.mercEicharProvenanceEvents)",
            "merc_eichar_provenance_events_total="
                + "\(renderer.mercEicharProvenanceEventsTotal)",
            "merc_eichar_output_composition_mismatches="
                + "\(renderer.mercEicharOutputCompositionMismatches)",
            "merc_eichar_output_composition_mismatches_total="
                + "\(renderer.mercEicharOutputCompositionMismatchesTotal)",
            "merc_eichar_palette_health_issues="
                + "\(renderer.mercEicharPaletteHealthIssues)",
            "merc_eichar_palette_health_issues_total="
                + "\(renderer.mercEicharPaletteHealthIssuesTotal)",
            "merc_eichar_weighted_profiled_base_draws="
                + "\(renderer.mercEicharWeightedProfiledBaseDraws)",
            "merc_eichar_weighted_profiled_vertices="
                + "\(renderer.mercEicharWeightedProfiledVertices)",
            "merc_eichar_weighted_multi_bone_vertices="
                + "\(renderer.mercEicharWeightedMultiBoneVertices)",
            "merc_eichar_weighted_affected_vertices="
                + "\(renderer.mercEicharWeightedAffectedVertices)",
            "merc_eichar_weighted_static_multi_bone_vertices="
                + "\(renderer.mercEicharWeightedStaticMultiBoneVertices)",
            "merc_eichar_weighted_static_affected_vertices="
                + "\(renderer.mercEicharWeightedStaticAffectedVertices)",
            "merc_eichar_weighted_modified_multi_bone_vertices="
                + "\(renderer.mercEicharWeightedModifiedMultiBoneVertices)",
            "merc_eichar_weighted_modified_affected_vertices="
                + "\(renderer.mercEicharWeightedModifiedAffectedVertices)",
            "merc_eichar_weighted_tuple_groups="
                + "\(renderer.mercEicharWeightedTupleGroups)",
            "merc_eichar_weighted_affected_tuple_groups="
                + "\(renderer.mercEicharWeightedAffectedTupleGroups)",
            "merc_eichar_weighted_valid_basis_groups="
                + "\(renderer.mercEicharWeightedValidBasisGroups)",
            "merc_eichar_weighted_invalid_basis_groups="
                + "\(renderer.mercEicharWeightedInvalidBasisGroups)",
            "merc_eichar_weighted_affected_draws="
                + "\(renderer.mercEicharWeightedAffectedDraws)",
            "merc_eichar_weighted_affected_effects="
                + "\(renderer.mercEicharWeightedAffectedEffects)",
            "merc_eichar_weighted_profile_tuple_mismatches="
                + "\(renderer.mercEicharWeightedProfileTupleMismatches)",
            "merc_eichar_weighted_profile_capacity_drops="
                + "\(renderer.mercEicharWeightedProfileCapacityDrops)",
            "merc_eichar_weighted_maximum_axis_ratio="
                + "\(decimal(renderer.mercEicharWeightedMaximumAxisRatio))",
            "merc_eichar_weighted_minimum_normalized_abs_determinant="
                + "\(decimal(renderer.mercEicharWeightedMinimumNormalizedAbsDeterminant))",
            "merc_eichar_weighted_coverage=\(renderer.mercEicharWeightedCoverage)",
            "merc_eichar_packets=\(renderer.mercEicharPackets)",
            "merc_eichar_unique_source_bases=\(renderer.mercEicharUniqueSourceBases)",
            "merc_eichar_repeated_packets=\(renderer.mercEicharRepeatedPackets)",
            "merc_eichar_repeated_packets_same_palette="
                + "\(renderer.mercEicharRepeatedPacketsSamePalette)",
            "merc_eichar_repeated_packets_conflicting_palette="
                + "\(renderer.mercEicharRepeatedPacketsConflictingPalette)",
            "merc_eichar_actual_base_draws=\(renderer.mercEicharActualBaseDraws)",
            "merc_eichar_unique_base_draws=\(renderer.mercEicharUniqueBaseDraws)",
            "merc_eichar_repeated_base_draws=\(renderer.mercEicharRepeatedBaseDraws)",
            "merc_eichar_repeated_base_draws_same_palette="
                + "\(renderer.mercEicharRepeatedBaseDrawsSamePalette)",
            "merc_eichar_repeated_base_draws_conflicting_palette="
                + "\(renderer.mercEicharRepeatedBaseDrawsConflictingPalette)",
            "merc_eichar_trace_capacity_drops=\(renderer.mercEicharTraceCapacityDrops)",
            "merc_eichar_bound_palette_hash_mismatches="
                + "\(renderer.mercEicharBoundPaletteHashMismatches)",
            "merc_eichar_weighted_skin_evidence_total="
                + "\(renderer.mercEicharWeightedSkinEvidenceTotal)",
            "merc_eichar_weighted_issue_mask=\(renderer.mercEicharWeightedIssueMask)",
            "last_merc_eichar_weighted_skin_engine_frame="
                + "\(renderer.lastMercEicharWeightedSkinEngineFrameID)",
            "last_merc_eichar_weighted_skin_host_tick="
                + "\(renderer.lastMercEicharWeightedSkinHostTickID)",
            "last_merc_eichar_weighted_skin_chain="
                + "\(renderer.lastMercEicharWeightedSkinChainOrdinal)",
        ]
            + mercTransformFields(
                "first_merc_eichar_transform",
                renderer.firstMercEicharTransformDiscontinuity)
            + mercTransformFields(
                "last_merc_eichar_transform",
                renderer.lastMercEicharTransformDiscontinuity)
            + mercTransformFields(
                "first_merc_eichar_provenance",
                renderer.firstMercEicharProvenanceEvent)
            + mercTransformFields(
                "last_merc_eichar_provenance",
                renderer.lastMercEicharProvenanceEvent)
            + mercTransformFields(
                "first_merc_eichar_output_composition",
                renderer.firstMercEicharOutputCompositionMismatch)
            + mercTransformFields(
                "last_merc_eichar_output_composition",
                renderer.lastMercEicharOutputCompositionMismatch)
            + mercPaletteHealthFields(
                "first_merc_eichar_palette_health",
                renderer.firstMercEicharPaletteHealthEvent)
            + mercPaletteHealthFields(
                "last_merc_eichar_palette_health",
                renderer.lastMercEicharPaletteHealthEvent)
            + cameraCorrectionFields(renderer.lastCameraCorrectionEvent)
            + cameraTailFields
            + [
                "merc_eichar_target_control_events="
                    + "\(renderer.mercEicharTargetControlEvents)",
                "merc_eichar_target_control_events_total="
                    + "\(renderer.mercEicharTargetControlEventsTotal)",
                "merc_eichar_target_control_divergences="
                    + "\(renderer.mercEicharTargetControlDivergences)",
                "merc_eichar_target_control_divergences_total="
                    + "\(renderer.mercEicharTargetControlDivergencesTotal)",
                "merc_eichar_target_control_attack_boundaries="
                    + "\(renderer.mercEicharTargetControlAttackBoundaries)",
                "merc_eichar_target_control_attack_boundaries_total="
                    + "\(renderer.mercEicharTargetControlAttackBoundariesTotal)",
                "merc_eichar_target_control_capture_attempts_total="
                    + "\(targetControl.captureAttemptsTotal)",
                "merc_eichar_target_control_valid_observations_total="
                    + "\(targetControl.validObservationsTotal)",
                "last_merc_eichar_target_control_capture_stage="
                    + "\(targetControl.lastCaptureStage)",
                "last_merc_eichar_target_control_capture_result="
                    + "\(targetControl.lastCaptureResult)",
                "target_post_flag_samples_total=\(targetControl.postFlagSamplesTotal)",
                "target_hidden_samples_total=\(targetControl.hiddenSamplesTotal)",
                "target_hidden_transitions_total=\(targetControl.hiddenTransitionsTotal)",
                "target_post_flag_serial_gaps_total="
                    + "\(targetControl.postFlagSerialGapsTotal)",
                "target_unframed_post_flag_samples_total="
                    + "\(targetControl.unframedPostFlagSamplesTotal)",
            ]
            + targetControlFields(
                "first_merc_eichar_target_control",
                renderer.firstMercEicharTargetControlEvent)
            + targetControlFields(
                "last_merc_eichar_target_control",
                renderer.lastMercEicharTargetControlEvent)
            + targetControlObservationFields(
                "last_merc_eichar_target_control_observation",
                targetControl.lastObservation)
            + targetPostFlagFields("last_target_post_flag",
                                   targetControl.lastPostFlagSample)
            + targetPostFlagFields("last_hidden_target_post_flag",
                                   targetControl.lastHiddenPostFlagSample)
        try Data((fields.joined(separator: " ") + "\n").utf8)
            .write(to: cameraDiagnosticsURL, options: .atomic)
        return cameraTailInfo
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
        let wasPreparingGameplay = isPreparingGameplay
        currentScenePhase = phase
        let lifecyclePhase = GameplayLifecycleState.Phase(phase)
        let action = lifecycle.transition(
            to: lifecyclePhase,
            prepareOnActivation: !isBooting && !isStartingGameplay
        )
        sessionLog.notice("""
            Lifecycle \(lifecyclePhase.rawValue, privacy: .public) generation \
            \(self.lifecycle.generation), frame loop \
            \(self.lifecycle.frameLoopEnabled ? "enabled" : "suspended", privacy: .public), \
            preparation \(self.lifecycle.preparationGeneration ?? 0)
            """)
        switch phase {
        case .active:
            if GameDataRefreshPolicy.shouldRefreshOnActivation(
                isRunning: isRunning,
                isBooting: isBooting,
                isPreparingGameplay: wasPreparingGameplay
            ) {
                Task { [weak self] in await self?.refreshDataReport() }
            }
            if isBooting {
                saveSync.setGameplayActive(true)
                audio.resumeIfSuspended()
                return
            }
            touch.restoreGameplayChromeAfterInterruption()
            if isStartingGameplay {
                audio.resumeIfSuspended()
            }
            if case .prepareForeground(let generation) = action {
                beginForegroundPreparation(generation: generation)
            }
        case .inactive:
            if !isBooting { saveSync.setGameplayActive(false) }
            #if os(iOS) || os(visionOS)
            persistCameraDiagnosticsForLifecycleEvent()
            #endif
            touch.reset()
            resetDisplayTiming()
            // A transient state - the app switcher, a notification. Give up the audio device but
            // keep the session, so returning is instant.
            audio.suspend()
            input.stopRumble()
        case .background:
            if !isBooting { saveSync.setGameplayActive(false) }
            #if os(iOS) || os(visionOS)
            persistCameraDiagnosticsForLifecycleEvent()
            #endif
            touch.reset()
            resetDisplayTiming()
            audio.suspend()
            input.stopRumble()
            setIdleTimerDisabled(false)
        @unknown default:
            break
        }
    }

    private func beginForegroundPreparation(generation: UInt64) {
        guard foregroundPreparationTask == nil else { return }
        sessionLog.notice("Preparing foreground generation \(generation)")
        foregroundPreparationGeneration = generation
        foregroundPreparationTask = Task { [weak self] in
            guard let self else { return }
            let savesReady = await saveSync.syncBeforeGameplay()
            finishForegroundPreparation(generation: generation, savesReady: savesReady)
        }
    }

    private func saveGameplayReadinessDidChange() {
        guard currentScenePhase == .active,
              !lifecycle.frameLoopEnabled,
              !isBooting,
              !isStartingGameplay,
              foregroundPreparationTask == nil,
              !lifecycle.isPreparingForeground else { return }
        guard case .prepareForeground(let generation) = lifecycle.requestPreparationIfNeeded()
        else { return }
        sessionLog.notice("Save readiness changed; retrying foreground generation \(generation)")
        beginForegroundPreparation(generation: generation)
    }

    private func finishForegroundPreparation(generation: UInt64, savesReady: Bool) {
        guard foregroundPreparationGeneration == generation else {
            sessionLog.notice("Ignored cancelled foreground generation \(generation)")
            return
        }
        foregroundPreparationTask = nil
        foregroundPreparationGeneration = nil
        let action = lifecycle.completePreparation(generation: generation, succeeded: savesReady)
        switch action {
        case .prepareForeground(let nextGeneration):
            sessionLog.notice("Foreground generation \(generation) became stale; preparing \(nextGeneration)")
            beginForegroundPreparation(generation: nextGeneration)
        case .resumed:
            if startupError == Self.saveRecoveryMessage {
                startupError = nil
            }
            saveSync.setGameplayActive(kernel != nil)
            if !controlsGuideSuspension.blocksGameplay {
                audio.resumeIfSuspended()
            }
            setIdleTimerDisabled(isRunning)
            sessionLog.notice("Foreground generation \(generation) resumed")
        case .failed:
            startupError = Self.saveRecoveryMessage
            saveSync.setGameplayActive(false)
            audio.suspend()
            setIdleTimerDisabled(false)
            sessionLog.error("Foreground generation \(generation) remains suspended for save recovery")
        case .suspended:
            saveSync.setGameplayActive(false)
            sessionLog.notice("Foreground generation \(generation) completed after suspension")
        case .none:
            sessionLog.notice("Ignored stale foreground completion for generation \(generation)")
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
        sessionLog.warning("""
            Memory warning #\(self.memoryWarnings) - nothing safely reclaimable in the app shell; \
            lifecycle \(self.lifecycle.phase.rawValue, privacy: .public) generation \
            \(self.lifecycle.generation), frame loop \
            \(self.lifecycle.frameLoopEnabled ? "enabled" : "suspended", privacy: .public), \
            running \(self.isRunning), audio \(self.audio.isRunning), save work \
            \(self.saveSync.isBusy)
            """)
    }

    private func setIdleTimerDisabled(_ disabled: Bool) {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }
}

private extension GameplayLifecycleState.Phase {
    init(_ phase: ScenePhase) {
        switch phase {
        case .active: self = .active
        case .inactive: self = .inactive
        case .background: self = .background
        @unknown default: self = .inactive
        }
    }
}
