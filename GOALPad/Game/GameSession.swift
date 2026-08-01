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
/// One frame is: read the controller and push it at the engine, run the engine, present, then read
/// the vibration request back out. The engine step is the piece this build does not have yet - see
/// `GOALPadRuntimeBridge.inputSeamLinked` and friends - so the loop currently drives input, the
/// presentation surface, and audio, and says so on screen rather than pretending otherwise.
@MainActor
@Observable
final class GameSession {
    let input = ControllerInput()
    let audio = AudioOutput()
    let settings = RenderSettings()
    let importer = GameDataImporter()

    private(set) var dataReport = GameDataReport()
    private(set) var kernel: GOALPadKernelStatus?
    private(set) var isRunning = false
    private(set) var framesPresented: UInt64 = 0
    private(set) var memoryWarnings = 0
    private(set) var startupError: String?

    private var observers: [NSObjectProtocol] = []
    /// The frame loop only runs while the scene is on screen: asking a backgrounded app's layer
    /// for a drawable blocks until it comes back.
    private var isForeground = true

    var geometry: GOALPadSurfaceGeometry { GOALPadRenderSurface.shared.geometry() }

    // MARK: - Lifetime

    func prepare() async {
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
    /// the game.
    func start() {
        guard !isRunning else { return }
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
        input.startWatching()
        audio.start()
        isRunning = true
        setIdleTimerDisabled(true)
        sessionLog.notice("Session started")
    }

    func shutdown() {
        guard isRunning || kernel != nil else { return }
        input.stopRumble()
        input.stopWatching()
        audio.stop()
        GOALPadRuntimeBridge.stopKernel()
        kernel = nil
        isRunning = false
        setIdleTimerDisabled(false)
        sessionLog.notice("Session shut down")
    }

    // MARK: - The frame loop

    func tick() {
        guard isRunning, isForeground else { return }
        input.pushFrame()

        // The engine step goes here: one `kernel-dispatcher` frame, then `goal_sound_frame`.

        if GOALPadRenderSurface.shared.renderFrame() {
            framesPresented = GOALPadRenderSurface.shared.framesPresented
        }
        input.applyRumble()
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
            MainActor.assumeIsolated { self?.shutdown() }
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
