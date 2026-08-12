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

private func close(_ lhs: Double, _ rhs: Double) -> Bool {
    abs(lhs - rhs) < 0.000_001
}

private func source(_ root: String, _ path: String) -> String {
    (try? String(contentsOfFile: root + "/" + path, encoding: .utf8)) ?? ""
}

@main
private struct GamePerformanceCheck {
    static func main() {
        var accumulator = FramePerformanceAccumulator()
        for value in 1...20 {
            accumulator.record(inputMilliseconds: Double(value) / 10,
                               gameMilliseconds: Double(value) / 2,
                               presentationMilliseconds: Double(value) / 4,
                               totalMilliseconds: Double(value))
        }
        let first = accumulator.drain(
            windowSeconds: 1,
            actualFramesPerSecond: 59,
            gpuMeanMilliseconds: 4,
            gpuLastMilliseconds: 5,
            gpuMaximumMilliseconds: 8,
            physicalMemoryBytes: 100,
            peakPhysicalMemoryBytes: 120,
            thermalState: "nominal",
            lowPowerModeEnabled: false,
            lastLevelLoadMilliseconds: 12
        )
        check(first.frameSamples == 20 && close(first.frameMeanMilliseconds, 10.5),
              "a one-second CPU window reports its exact sample count and mean")
        check(close(first.frameP95Milliseconds, 19) && close(first.frameMaxMilliseconds, 20),
              "the frame window reports deterministic nearest-rank p95 and max")
        check(first.hitchesOverBudget == 4 && first.severeHitches == 0,
              "60 Hz and two-frame hitch thresholds are counted separately")
        check(first.actualFramesPerSecond == 59 && first.gpuMeanMilliseconds == 4
                && first.physicalMemoryBytes == 100 && first.peakPhysicalMemoryBytes == 120,
              "presentation, GPU, memory, and power facts survive publication")
        check(accumulator.count == 0,
              "publishing drains the CPU window instead of growing per-frame state")

        for value in 0...240 {
            accumulator.record(inputMilliseconds: 0,
                               gameMilliseconds: 0,
                               presentationMilliseconds: 0,
                               totalMilliseconds: Double(value))
        }
        let bounded = accumulator.drain(
            windowSeconds: 4,
            actualFramesPerSecond: 60,
            gpuMeanMilliseconds: 0,
            gpuLastMilliseconds: 0,
            gpuMaximumMilliseconds: 0,
            physicalMemoryBytes: 0,
            peakPhysicalMemoryBytes: 0,
            thermalState: "unknown",
            lowPowerModeEnabled: true,
            lastLevelLoadMilliseconds: 0
        )
        check(bounded.frameSamples == 240 && close(bounded.frameMeanMilliseconds, 120.5)
                && close(bounded.frameP95Milliseconds, 228)
                && close(bounded.frameMaxMilliseconds, 240),
              "the fixed 240-frame ring retains the newest samples in order")

        guard CommandLine.arguments.count == 2 else {
            print("usage: game-performance-check <repository-root>")
            Foundation.exit(2)
        }
        let root = CommandLine.arguments[1]
        let session = source(root, "GOALPad/Game/GameSession.swift")
        let renderer = source(root,
                              "OpenGOAL/game/graphics/pipelines/metal/metal_renderer.mm")
        let bridge = source(root, "GOALPad/Native/GOALPadRuntimeBridge.mm")
        check(session.contains("shouldLog || shouldPublishPerformance")
                && !session.contains("let renderer = GOALPadRenderSurface.shared.stats\n        // File"),
              "the large renderer snapshot is no longer copied on every display callback")
        check(session.contains("peakPhysicalMemoryBytes = max(peakPhysicalMemoryBytes, memory)")
                && session.contains("peakPhysicalMemoryBytes: peakPhysicalMemoryBytes"),
              "lifecycle timing resets preserve the whole-session memory peak")
        check(renderer.contains("completed.GPUStartTime")
                && renderer.contains("completed.GPUEndTime")
                && renderer.contains("status == MTLCommandBufferStatusCompleted"),
              "GPU duration is accepted only from completed Metal command buffers")
        check(bridge.contains("TASK_VM_INFO") && bridge.contains("info.phys_footprint"),
              "memory telemetry uses the process physical-footprint API")

        if failures == 0 {
            print("game performance checks passed")
        } else {
            print("game performance checks failed: \(failures)")
            Foundation.exit(1)
        }
    }
}
