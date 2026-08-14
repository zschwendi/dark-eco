import CoreGraphics
import Foundation

private var failures = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("  ok   \(message)")
    } else {
        print("  FAIL \(message)")
        failures += 1
    }
}

private func approximatelyEqual(_ lhs: CGSize?, _ rhs: CGSize) -> Bool {
    guard let lhs else { return false }
    return abs(lhs.width - rhs.width) < 0.001
        && abs(lhs.height - rhs.height) < 0.001
}

@main
private enum VisionWindowGeometryCheck {
    static func main() {
        check(approximatelyEqual(
            VisionWindowGeometry.fourByThreeSize(containedIn: CGSize(width: 1280, height: 720)),
            CGSize(width: 960, height: 720)
        ), "a wide window trims its width without growing")
        check(approximatelyEqual(
            VisionWindowGeometry.fourByThreeSize(containedIn: CGSize(width: 800, height: 900)),
            CGSize(width: 800, height: 600)
        ), "a tall window trims its height without growing")
        check(approximatelyEqual(
            VisionWindowGeometry.fourByThreeSize(containedIn: CGSize(width: 1024, height: 768)),
            CGSize(width: 1024, height: 768)
        ), "an existing 4:3 window is unchanged")
        check(VisionWindowGeometry.fourByThreeSize(containedIn: .zero) == nil
              && VisionWindowGeometry.fourByThreeSize(
                containedIn: CGSize(width: -CGFloat.infinity, height: 10)) == nil
              && VisionWindowGeometry.fourByThreeSize(
                containedIn: CGSize(width: 10, height: CGFloat.nan)) == nil,
              "invalid window sizes do not produce geometry requests")

        var state = VisionWindowGeometryState()
        let freeformSize = CGSize(width: 1280, height: 720)
        let lock = state.request(locksToFourByThree: true, currentSize: freeformSize)
        check(lock == .init(mode: .fourByThree, size: CGSize(width: 960, height: 720)),
              "turning Fit off requests a uniform contained 4:3 window")
        check(state.request(locksToFourByThree: true, currentSize: freeformSize) == nil,
              "a pending request suppresses duplicates")
        if let lock { state.complete(lock, succeeded: true) }
        check(state.request(locksToFourByThree: true,
                            currentSize: CGSize(width: 960, height: 720)) == nil,
              "an applied 4:3 mode suppresses duplicate requests")

        let unlock = state.request(locksToFourByThree: false,
                                   currentSize: CGSize(width: 960, height: 720))
        check(unlock == .init(mode: .freeform, size: freeformSize),
              "turning Fit on restores the prior freeform size")
        if let unlock { state.complete(unlock, succeeded: true) }
        check(state.appliedMode == .freeform && state.pendingMode == nil,
              "the state records a completed freeform restoration")

        var failedState = VisionWindowGeometryState()
        let failed = failedState.request(locksToFourByThree: true,
                                         currentSize: CGSize(width: 1200, height: 800))
        if let failed { failedState.complete(failed, succeeded: false) }
        check(failedState.appliedMode == .freeform && failedState.pendingMode == nil,
              "a failed request leaves the prior freeform mode applied")

        if failures == 0 {
            print("vision window geometry checks passed")
        } else {
            print("vision window geometry checks failed: \(failures)")
            Foundation.exit(1)
        }
    }
}
