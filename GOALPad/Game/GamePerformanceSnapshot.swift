import Foundation

nonisolated struct GamePerformanceSnapshot: Equatable, Sendable {
    var windowSeconds = 0.0
    var frameSamples = 0
    var actualFramesPerSecond = 0.0
    var inputMeanMilliseconds = 0.0
    var gameMeanMilliseconds = 0.0
    var presentationMeanMilliseconds = 0.0
    var frameMeanMilliseconds = 0.0
    var frameP95Milliseconds = 0.0
    var frameMaxMilliseconds = 0.0
    var hitchesOverBudget = 0
    var severeHitches = 0
    var gpuMeanMilliseconds = 0.0
    var gpuLastMilliseconds = 0.0
    var gpuMaximumMilliseconds = 0.0
    var physicalMemoryBytes: UInt64 = 0
    var peakPhysicalMemoryBytes: UInt64 = 0
    var thermalState = "unknown"
    var lowPowerModeEnabled = false
    var lastLevelLoadMilliseconds = 0.0
}

nonisolated struct FramePerformanceAccumulator: Sendable {
    private static let capacity = 240

    private var input = [Double](repeating: 0, count: capacity)
    private var game = [Double](repeating: 0, count: capacity)
    private var presentation = [Double](repeating: 0, count: capacity)
    private var total = [Double](repeating: 0, count: capacity)
    private var nextIndex = 0
    private(set) var count = 0

    mutating func record(inputMilliseconds: Double,
                         gameMilliseconds: Double,
                         presentationMilliseconds: Double,
                         totalMilliseconds: Double) {
        input[nextIndex] = inputMilliseconds
        game[nextIndex] = gameMilliseconds
        presentation[nextIndex] = presentationMilliseconds
        total[nextIndex] = totalMilliseconds
        nextIndex = (nextIndex + 1) % Self.capacity
        count = min(count + 1, Self.capacity)
    }

    mutating func drain(windowSeconds: Double,
                        actualFramesPerSecond: Double,
                        gpuMeanMilliseconds: Double,
                        gpuLastMilliseconds: Double,
                        gpuMaximumMilliseconds: Double,
                        physicalMemoryBytes: UInt64,
                        peakPhysicalMemoryBytes: UInt64,
                        thermalState: String,
                        lowPowerModeEnabled: Bool,
                        lastLevelLoadMilliseconds: Double) -> GamePerformanceSnapshot {
        let inputSummary = summary(input)
        let gameSummary = summary(game)
        let presentationSummary = summary(presentation)
        let totalValues = values(total)
        let totalSummary = TimingSummary(values: totalValues)
        let snapshot = GamePerformanceSnapshot(
            windowSeconds: windowSeconds,
            frameSamples: count,
            actualFramesPerSecond: actualFramesPerSecond,
            inputMeanMilliseconds: inputSummary.mean,
            gameMeanMilliseconds: gameSummary.mean,
            presentationMeanMilliseconds: presentationSummary.mean,
            frameMeanMilliseconds: totalSummary.mean,
            frameP95Milliseconds: totalSummary.p95,
            frameMaxMilliseconds: totalSummary.max,
            hitchesOverBudget: totalValues.count { $0 > (1_000.0 / 60.0) },
            severeHitches: totalValues.count { $0 > (2_000.0 / 60.0) },
            gpuMeanMilliseconds: gpuMeanMilliseconds,
            gpuLastMilliseconds: gpuLastMilliseconds,
            gpuMaximumMilliseconds: gpuMaximumMilliseconds,
            physicalMemoryBytes: physicalMemoryBytes,
            peakPhysicalMemoryBytes: peakPhysicalMemoryBytes,
            thermalState: thermalState,
            lowPowerModeEnabled: lowPowerModeEnabled,
            lastLevelLoadMilliseconds: lastLevelLoadMilliseconds
        )
        nextIndex = 0
        count = 0
        return snapshot
    }

    mutating func reset() {
        nextIndex = 0
        count = 0
    }

    private func summary(_ storage: [Double]) -> TimingSummary {
        TimingSummary(values: values(storage))
    }

    private func values(_ storage: [Double]) -> [Double] {
        guard count > 0 else { return [] }
        if count < Self.capacity {
            return Array(storage[..<count])
        }
        return Array(storage[nextIndex...]) + Array(storage[..<nextIndex])
    }
}

nonisolated private struct TimingSummary {
    let mean: Double
    let p95: Double
    let max: Double

    init(values: [Double]) {
        guard !values.isEmpty else {
            mean = 0
            p95 = 0
            max = 0
            return
        }
        let sorted = values.sorted()
        mean = values.reduce(0, +) / Double(values.count)
        p95 = sorted[Swift.max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)]
        max = sorted.last ?? 0
    }
}
