import OSLog
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

nonisolated private let sessionLog = Logger(subsystem: "com.zephyrstudiosllc.GOALPad",
                                            category: "Session")

/// Owns everything with a lifetime: the GOAL kernel session, the controller, the audio device, and
/// the frame loop that ties them together.
///
/// One frame is: read the controller and push it at the engine, run one `kernel-dispatcher` frame,
/// present, then read the vibration request back out. Nothing is drawn yet - the Metal renderer is
/// not part of this build and the surface says so - but the frame itself is the game's own.
@MainActor
@Observable
final class GameSession {
    let input = ControllerInput()
    let audio = AudioOutput()
    let settings = RenderSettings()
    let importer = GameDataImporter()

    private(set) var dataReport = GameDataReport()
    private(set) var kernel: GOALPadKernelStatus?
    private(set) var boot: GOALPadGameBootStatus?
    private(set) var isBooting = false
    private(set) var isRunning = false
    private(set) var framesRun: UInt64 = 0
    private(set) var framesPresented: UInt64 = 0
    private(set) var memoryWarnings = 0
    private(set) var startupError: String?

    var frameChain: GOALPadFrameChainStats { GOALPadRuntimeBridge.frameChainStats }

    /// Booting runs the game's own startup - two DGO archives and `play` - which takes seconds and
    /// must not block the frame loop or the UI.
    private let bootQueue = DispatchQueue(label: "com.zephyrstudiosllc.GOALPad.boot",
                                          qos: .userInitiated)
    private var observers: [NSObjectProtocol] = []
    /// The frame loop only runs while the scene is on screen: asking a backgrounded app's layer
    /// for a drawable blocks until it comes back.
    private var isForeground = true

    var geometry: GOALPadSurfaceGeometry { GOALPadRenderSurface.shared.geometry() }

    // MARK: - Lifetime

    func prepare() async {
        sessionLog.notice("prepare")
        observeSystem()
        try? GameDataLayout.prepare()
        await refreshDataReport()
        // Data that can boot means there is nothing to set up, so go straight to the game.
        if dataReport.canBoot {
            start()
        }
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
        setIdleTimerDisabled(true)
        sessionLog.notice("Session started: \(status.message)")
    }

    func shutdown() {
        guard isRunning || kernel != nil else { return }
        input.stopRumble()
        input.stopWatching()
        audio.stop()
        GOALPadRuntimeBridge.stopKernel()
        kernel = nil
        boot = nil
        isRunning = false
        framesRun = 0
        setIdleTimerDisabled(false)
        sessionLog.notice("Session shut down")
    }

    // MARK: - The frame loop

    func tick() {
        guard isRunning, isForeground else { return }
        input.pushFrame()

        // The GOAL kernel's own frame: every process and state, then the overlord's vblank work.
        if GOALPadRuntimeBridge.runFrame() {
            framesRun = GOALPadRuntimeBridge.framesRun
            if framesRun % 600 == 0 { logRunningState() }
        }

        if GOALPadRenderSurface.shared.renderFrame() {
            framesPresented = GOALPadRenderSurface.shared.framesPresented
        }
        input.applyRumble()
    }

    /// The same numbers the on-screen readout shows, every ten seconds, so a run can be checked
    /// from the log alone.
    private func logRunningState() {
        let chain = frameChain
        sessionLog.notice("""
            frame \(self.framesRun): \(self.framesPresented) presented, \
            audio \(self.audio.framesProduced)/\(self.audio.framesRequested) frames at \
            \(self.audio.sampleRate) Hz peak \(self.audio.peakAmplitude), \
            DMA chain \(chain.lastPayloadBytes) bytes \
            (largest \(chain.largestPayloadBytes)), pad reads \
            \(GOALPadInputReadCount(ControllerInput.primaryPort))
            """)
    }

    // MARK: - App lifecycle

    func scenePhaseChanged(to phase: ScenePhase) {
        switch phase {
        case .active:
            isForeground = true
            guard isRunning else { return }
            audio.resumeIfSuspended()
            setIdleTimerDisabled(true)
        case .inactive:
            isForeground = false
            // A transient state - the app switcher, a notification. Give up the audio device but
            // keep the session, so returning is instant.
            audio.suspend()
            input.stopRumble()
        case .background:
            isForeground = false
            audio.suspend()
            input.stopRumble()
            setIdleTimerDisabled(false)
        @unknown default:
            break
        }
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
