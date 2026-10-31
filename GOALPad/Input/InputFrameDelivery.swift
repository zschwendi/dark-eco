/// Holds the pad frame handed to the engine until a GOAL frame actually reads it.
///
/// A display callback can run no GOAL frame: Jak 1 skips callbacks without elapsed time, and the
/// Jak II tick can select zero dispatcher frames. Sampling input again on the next callback would
/// age touch pulses and consume mouse movement that no GOAL frame read, so the unread frame is
/// handed over again instead. At most one frame is held.
struct InputFrameDelivery<Frame> {
    private(set) var undelivered: Frame?

    /// The undelivered frame if there is one, otherwise a newly sampled frame.
    mutating func frame(sampling sample: () -> Frame) -> Frame {
        if let undelivered { return undelivered }
        let frame = sample()
        undelivered = frame
        return frame
    }

    /// Records whether at least one GOAL frame ran after the frame was handed over.
    mutating func finish(goalFrameRan: Bool) {
        if goalFrameRan { undelivered = nil }
    }

    mutating func reset() {
        undelivered = nil
    }
}
