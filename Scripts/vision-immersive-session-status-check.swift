// Compiled with VisionImmersiveSessionStatus.swift by the focused runner.
import Foundation

private typealias Recorder = VisionImmersiveSessionStatusRecorder

private func readDocument(_ url: URL) throws -> Recorder.Document {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(Recorder.Document.self, from: Data(contentsOf: url))
}

@main
private enum VisionImmersiveSessionStatusCheck {
    static func main() throws {
        var failures = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            if condition() {
                print("  ok   \(message)")
            } else {
                print("  FAIL \(message)")
                failures += 1
            }
        }

        guard CommandLine.arguments.count == 2 else {
            fatalError("expected an output path")
        }
        let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let fixedTime = Date(timeIntervalSince1970: 1_798_000_000)
        let recorder = Recorder(
            outputURL: outputURL,
            maximumEventCount: 5,
            now: { fixedTime })

        recorder.record(attempt: 7, event: .opening, phase: "opening",
                        reason: "enterRequested")
        recorder.record(attempt: 7, event: .presenterStarted, phase: "opening")
        recorder.record(attempt: 7, event: .presenting, phase: "presenting",
                        reason: "firstVisibleFrame")
        recorder.record(attempt: 7, event: .failure, phase: "closing",
                        reason: VisionImmersiveCloseReason.nativeFailure.rawValue,
                        failure: "world-camera-packet-unavailable-this-frame",
                        isTerminal: true)
        recorder.record(attempt: 7, event: .presenterStopped, phase: "closing",
                        reason: VisionImmersiveCloseReason.compositorInvalidated.rawValue,
                        isTerminal: true)
        recorder.record(attempt: 7, event: .dismissalFinished, phase: "failed")
        recorder.record(attempt: 6, event: .failure, phase: "failed",
                        reason: "stale", failure: "must not overwrite", isTerminal: true)
        recorder.flush()

        var document = try readDocument(outputURL)
        check(document.schemaVersion == Recorder.schemaVersion,
              "the persisted schema version is explicit")
        check(document.attempt == 7, "a stale attempt cannot replace the current attempt")
        check(document.events.count == 5 && document.events.map(\.sequence) == [2, 3, 4, 5, 6],
              "the transition ring is ordered and bounded")
        check(document.events.map(\.event) == [
            .presenterStarted, .presenting, .failure, .presenterStopped, .dismissalFinished,
        ], "the bounded ring retains presentation, terminal, and cleanup transitions")
        check(document.terminal?.event == .failure
                && document.terminal?.sequence == 4
                && document.terminal?.reason == VisionImmersiveCloseReason.nativeFailure.rawValue
                && document.terminal?.failure
                    == "world-camera-packet-unavailable-this-frame",
              "the first terminal event survives later stop and dismissal cleanup")
        check(document.events.filter(\.isTerminal).map(\.event) == [.failure],
              "only the accepted first terminal transition is marked terminal")
        check(document.updatedAt == fixedTime, "the document records its update time")

        let hostVisibilitySequence: [VisionImmersiveSessionLifetimeEvent] = [.hostDisappeared]
        let afterHostVisibility = hostVisibilitySequence.reduce(true) { owned, event in
            owned && !event.endsPresentation
        }
        let actualStopSequence: [VisionImmersiveSessionLifetimeEvent] = [
            .hostDisappeared, .sessionStopped,
        ]
        let afterActualStop = actualStopSequence.reduce(true) { owned, event in
            owned && !event.endsPresentation
        }
        check(afterHostVisibility && !afterActualStop,
              "host disappearance retains ownership while a true session stop revokes it")

        recorder.record(attempt: 8, event: .opening, phase: "opening",
                        reason: "enterRequested")
        recorder.record(attempt: 8, event: .hostDisappeared, phase: "opening",
                        reason: VisionImmersiveSessionLifetimeEvent.hostDisappeared.rawValue)
        recorder.record(attempt: 7, event: .failure, phase: "failed",
                        reason: "lateOldAttempt", failure: "must be ignored", isTerminal: true)
        recorder.flush()
        document = try readDocument(outputURL)
        check(document.attempt == 8 && document.events.map(\.event) == [
            .opening, .hostDisappeared,
        ] && document.terminal == nil,
              "a newer attempt resets, records nonterminal host hiding, and ignores stale events")

        guard failures == 0 else {
            fatalError("immersive session status checks failed: \(failures)")
        }
        print("visionOS immersive session status checks passed")
    }
}
