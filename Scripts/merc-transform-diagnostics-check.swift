import Foundation

var first = GOALPadMercTransformEvent()
first.hostTickID = 100
first.chainOrdinal = 2
first.issueMask = 1
first.boneSlot = 6
first.modelNameHash = 0xe1
first.previousFrameID = 60
first.currentFrameID = 61
first.previousMatrixHash = 0xa0
first.currentMatrixHash = 0xb0
first.previousAxisNormX = 1
first.previousAxisNormY = 1
first.previousAxisNormZ = 1
first.currentAxisNormX = 3
first.currentAxisNormY = 3
first.currentAxisNormZ = 3
first.previousScale = 1
first.currentScale = 3
first.previousAspect = 1
first.currentAspect = 1
first.previousSourceBase = 0x1600
first.currentSourceBase = 0x2600

var last = GOALPadMercTransformEvent()
last.hostTickID = 101
last.chainOrdinal = 3
last.issueMask = 1
last.boneSlot = 6
last.modelNameHash = 0xe1
last.previousFrameID = 61
last.currentFrameID = 62
last.previousMatrixHash = 0xb0
last.currentMatrixHash = 0xa0
last.previousAxisNormX = 3
last.previousAxisNormY = 3
last.previousAxisNormZ = 3
last.currentAxisNormX = 1
last.currentAxisNormY = 1
last.currentAxisNormZ = 1
last.previousScale = 3
last.currentScale = 1
last.previousAspect = 1
last.currentAspect = 1
last.previousSourceBase = 0x2600
last.currentSourceBase = 0x1600

var stats = GOALPadRendererStats()
stats.mercEicharTransformDiscontinuities = 1
stats.mercEicharTransformDiscontinuitiesTotal = 2
stats.firstMercEicharTransformDiscontinuity = first
stats.lastMercEicharTransformDiscontinuity = last

precondition(stats.mercEicharTransformDiscontinuities == 1)
precondition(stats.mercEicharTransformDiscontinuitiesTotal == 2)
precondition(stats.firstMercEicharTransformDiscontinuity.previousMatrixHash
    == stats.lastMercEicharTransformDiscontinuity.currentMatrixHash)
precondition(stats.firstMercEicharTransformDiscontinuity.currentMatrixHash
    == stats.lastMercEicharTransformDiscontinuity.previousMatrixHash)
precondition(stats.firstMercEicharTransformDiscontinuity.previousScale
    == stats.lastMercEicharTransformDiscontinuity.currentScale)
precondition(stats.firstMercEicharTransformDiscontinuity.currentScale
    == stats.lastMercEicharTransformDiscontinuity.previousScale)
precondition(stats.firstMercEicharTransformDiscontinuity.previousSourceBase
    == stats.lastMercEicharTransformDiscontinuity.currentSourceBase)
precondition(stats.firstMercEicharTransformDiscontinuity.currentSourceBase
    == stats.lastMercEicharTransformDiscontinuity.previousSourceBase)

print("merc transform diagnostics bridge check passed")
