#if GOALPAD_EXPERIMENTAL_VISION_IMMERSIVE
import Foundation

nonisolated enum VisionImmersiveCloseReason: String, Codable, Sendable {
    case userToggle
    /// The game entered native pause; it stays paused in the conventional window.
    case pauseEntered
    case sessionStopped
    case sessionInvalidForTick
    case compositorInvalidated
    case presenterStartFailed
    case presenterFailure
    case targetAllocationFailed
    case nativeFailure
    case firstVisibleTimeout
    case openCancelled
    case openFailed
}

nonisolated enum VisionImmersiveSessionLifetimeEvent: String, Codable, Sendable {
    case hostDisappeared
    case sessionStopped

    var endsPresentation: Bool {
        self == .sessionStopped
    }
}

/// A bounded, transition-only account of one immersive attempt. The first terminal event is
/// retained while later renderer and dismissal cleanup events are appended.
nonisolated final class VisionImmersiveSessionStatusRecorder: @unchecked Sendable {
    enum EventKind: String, Codable, Sendable {
        case opening
        case openFinished
        case presenterStarted
        case presenting
        case closeRequested
        case failure
        case hostDisappeared
        case presenterStopped
        case dismissalFinished
    }

    struct Event: Codable, Equatable, Sendable {
        let sequence: UInt64
        let timestamp: Date
        let event: EventKind
        let phase: String
        let reason: String?
        let failure: String?
        let isTerminal: Bool
    }

    struct Terminal: Codable, Equatable, Sendable {
        let sequence: UInt64
        let timestamp: Date
        let event: EventKind
        let phase: String
        let reason: String?
        let failure: String?
    }

    struct Document: Codable, Equatable, Sendable {
        let schemaVersion: Int
        let attempt: UInt64
        let updatedAt: Date
        let events: [Event]
        let terminal: Terminal?
    }

    static let schemaVersion = 1
    static let defaultMaximumEventCount = 24
    static let relativePath = "Library/Caches/DarkEcoDiagnostics/immersive-session-status.json"

    private let outputURL: URL?
    private let maximumEventCount: Int
    private let now: @Sendable () -> Date
    private let writerQueue = DispatchQueue(
        label: "com.zephyrstudiosllc.eco.immersive-session-status",
        qos: .utility)
    private var attempt: UInt64?
    private var nextSequence: UInt64 = 0
    private var events: [Event] = []
    private var terminal: Terminal?

    init(outputURL: URL? = VisionImmersiveSessionStatusRecorder.defaultOutputURL,
         maximumEventCount: Int = VisionImmersiveSessionStatusRecorder.defaultMaximumEventCount,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.outputURL = outputURL
        self.maximumEventCount = max(1, maximumEventCount)
        self.now = now
    }

    func record(attempt: UInt64,
                event: EventKind,
                phase: String,
                reason: String? = nil,
                failure: String? = nil,
                isTerminal: Bool = false) {
        guard attempt != 0 else { return }
        writerQueue.async { [self] in
            if let currentAttempt = self.attempt {
                guard attempt >= currentAttempt else { return }
                if attempt > currentAttempt {
                    reset(for: attempt)
                }
            } else {
                reset(for: attempt)
            }

            nextSequence &+= 1
            if nextSequence == 0 { nextSequence = 1 }
            let timestamp = now()
            let acceptsTerminal = isTerminal && terminal == nil
            let entry = Event(
                sequence: nextSequence,
                timestamp: timestamp,
                event: event,
                phase: phase,
                reason: reason,
                failure: failure,
                isTerminal: acceptsTerminal)
            events.append(entry)
            if events.count > maximumEventCount {
                events.removeFirst(events.count - maximumEventCount)
            }
            if acceptsTerminal {
                terminal = Terminal(
                    sequence: entry.sequence,
                    timestamp: entry.timestamp,
                    event: entry.event,
                    phase: entry.phase,
                    reason: entry.reason,
                    failure: entry.failure)
            }
            write(Document(
                schemaVersion: Self.schemaVersion,
                attempt: attempt,
                updatedAt: timestamp,
                events: events,
                terminal: terminal))
        }
    }

    /// Test synchronization only. Production callers enqueue transition records and continue.
    func flush() {
        writerQueue.sync {}
    }

    private func reset(for attempt: UInt64) {
        self.attempt = attempt
        nextSequence = 0
        events.removeAll(keepingCapacity: true)
        terminal = nil
    }

    private func write(_ document: Document) {
        guard let outputURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(document).write(to: outputURL, options: .atomic)
        } catch {
            // Diagnostic persistence must never alter immersive presentation.
        }
    }

    private static var defaultOutputURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "DarkEcoDiagnostics", directoryHint: .isDirectory)
            .appending(path: "immersive-session-status.json", directoryHint: .notDirectory)
    }
}
#endif
