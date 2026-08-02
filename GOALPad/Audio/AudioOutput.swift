import AVFoundation
import OSLog
import Synchronization

nonisolated private let audioLog = Logger(subsystem: "com.zephyrstudiosllc.eco",
                                          category: "Audio")

/// The audio device for the engine's mixer.
///
/// The engine has no output device of its own: `goal_sound_pull_audio` renders interleaved stereo
/// 16-bit frames whenever the host asks for them, at a fixed rate its sequencer timing is derived
/// from. This opens an `AVAudioEngine` source node at exactly that rate and lets the engine's
/// output chain resample to whatever the hardware is running at.
@MainActor
@Observable
final class AudioOutput {
    private(set) var isRunning = false
    private(set) var lastError: String?

    /// The rate the engine's mixer runs at, which is the rate the source node is opened at.
    let sampleRate = Int(GOALPadAudioSampleRate())

    /// How many stereo frames the device has asked for, and how many the engine actually produced.
    var framesRequested: Int { pull.requested.load(ordering: .relaxed) }
    var framesProduced: Int { pull.produced.load(ordering: .relaxed) }
    /// The loudest sample the engine has produced so far, of 32767. Zero means silence: the device
    /// is running and the frames are arriving, but nothing in them can be heard.
    var peakAmplitude: Int { pull.peak.load(ordering: .relaxed) }

    private let pull = EnginePull()
    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var observers: [NSObjectProtocol] = []
    private var interruptedWhileRunning = false

    func start() {
        guard !isRunning else { return }
        observeSession()

        do {
            try activateSession()
            let engine = AVAudioEngine()
            guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate),
                                             channels: 2)
            else {
                throw AudioOutputError.message("Could not describe a \(sampleRate) Hz stereo format.")
            }

            let pull = self.pull
            let node = AVAudioSourceNode(format: format) { silence, _, frameCount, buffers in
                pull.render(frameCount: frameCount, silence: silence, buffers: buffers)
            }
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            engine.prepare()
            try engine.start()

            self.engine = engine
            sourceNode = node
            isRunning = true
            lastError = nil
            audioLog.notice("Audio started at \(self.sampleRate) Hz stereo")
        } catch {
            lastError = error.localizedDescription
            audioLog.error("Audio start failed: \(error.localizedDescription, privacy: .public)")
            teardown()
        }
    }

    func stop() {
        teardown()
        deactivateSession()
        isRunning = false
    }

    /// Give up the device but keep watching the session, so the app holds no audio hardware while
    /// it is in the background and picks the device back up when it returns.
    func suspend() {
        guard isRunning else { return }
        teardown()
        deactivateSession()
        isRunning = false
        interruptedWhileRunning = true
        audioLog.notice("Audio suspended after \(self.framesRequested) frames")
    }

    func resumeIfSuspended() {
        guard interruptedWhileRunning, !isRunning else { return }
        interruptedWhileRunning = false
        audioLog.notice("Audio resuming")
        start()
    }

    private func teardown() {
        engine?.stop()
        if let engine, let sourceNode {
            engine.detach(sourceNode)
        }
        sourceNode = nil
        engine = nil
    }

    // MARK: - Session

    private func activateSession() throws {
        #if os(iOS) || os(visionOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setPreferredSampleRate(Double(sampleRate))
        try session.setPreferredIOBufferDuration(0.01)
        try session.setActive(true)
        #endif
    }

    private func deactivateSession() {
        #if os(iOS) || os(visionOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func observeSession() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default

        #if os(iOS) || os(visionOS)
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
                                            object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated { self?.handleInterruption(note) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification,
                                            object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated { self?.handleRouteChange(note) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        })
        #endif

        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        })
    }

    #if os(iOS) || os(visionOS)
    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw)
        else {
            return
        }
        switch type {
        case .began:
            audioLog.notice("Audio interrupted")
            suspend()
        case .ended:
            let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            if AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume) {
                resumeIfSuspended()
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
        else {
            return
        }
        switch reason {
        case .oldDeviceUnavailable:
            // Headphones came out. Stopping is what a player expects, and it is also what keeps
            // the game's audio off the built-in speaker in a quiet room.
            audioLog.notice("Audio route lost its old device")
            suspend()
        case .newDeviceAvailable, .routeConfigurationChange:
            resumeIfSuspended()
        default:
            break
        }
    }
    #endif

    private func rebuild() {
        guard isRunning else { return }
        audioLog.notice("Rebuilding the audio graph")
        teardown()
        isRunning = false
        start()
    }

    private enum AudioOutputError: LocalizedError {
        case message(String)

        var errorDescription: String? {
            switch self {
            case .message(let text): return text
            }
        }
    }
}

/// The render callback's side of the seam. Everything here runs on the audio device's real-time
/// thread: it allocates nothing, takes no Objective-C path, and holds no lock of its own.
nonisolated private final class EnginePull: Sendable {
    /// The device never asks for more than this in one callback; anything larger is clamped and
    /// the remainder is filled with silence rather than reading past the scratch buffer.
    private static let maxFrames = 4096

    let requested = Atomic<Int>(0)
    let produced = Atomic<Int>(0)
    /// Loudest sample the engine has produced, 0...32767. Written only by the render thread.
    let peak = Atomic<Int>(0)

    private nonisolated(unsafe) let scratch: UnsafeMutablePointer<Int16>

    init() {
        scratch = UnsafeMutablePointer<Int16>.allocate(capacity: Self.maxFrames * 2)
        scratch.initialize(repeating: 0, count: Self.maxFrames * 2)
    }

    deinit {
        scratch.deallocate()
    }

    func render(frameCount: AVAudioFrameCount,
                silence: UnsafeMutablePointer<ObjCBool>,
                buffers: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let frames = min(Int(frameCount), Self.maxFrames)
        requested.wrappingAdd(frames, ordering: .relaxed)

        let written = Int(GOALPadAudioPull(scratch, Int32(frames)))
        produced.wrappingAdd(written, ordering: .relaxed)

        let list = UnsafeMutableAudioBufferListPointer(buffers)
        if written == 0 {
            silence.pointee = true
            for buffer in list {
                memset(buffer.mData, 0, Int(buffer.mDataByteSize))
            }
            return noErr
        }

        var loudest = peak.load(ordering: .relaxed)
        for sample in 0..<(written * 2) {
            loudest = max(loudest, abs(Int(scratch[sample])))
        }
        peak.store(loudest, ordering: .relaxed)

        // The seam hands back interleaved stereo; the source node's standard format is two
        // deinterleaved float channels.
        for (channel, buffer) in list.enumerated() {
            guard let raw = buffer.mData else { continue }
            let out = raw.assumingMemoryBound(to: Float.self)
            let offset = min(channel, 1)
            for frame in 0..<Int(frameCount) {
                out[frame] = frame < written
                    ? Float(scratch[frame * 2 + offset]) / 32768
                    : 0
            }
        }
        return noErr
    }
}
