import Foundation

var first = GOALPadMercTransformEvent()
first.hostTickID = 100
first.chainOrdinal = 2
first.issueMask = 1
first.boneSlot = 6
first.modelNameHash = 0xe1
first.olderFrameID = 59
first.previousFrameID = 60
first.currentFrameID = 61
first.olderMatrixHash = 0x90
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
first.olderSourceBase = 0x600
first.previousSourceBase = 0x1600
first.currentSourceBase = 0x2600
first.inputRootBone = 3
first.olderProducerSerial = 10
first.previousProducerSerial = 11
first.currentProducerSerial = 12
first.olderInputRootHash = 0x100
first.previousInputRootHash = 0x200
first.currentInputRootHash = 0x100
first.olderCameraHash = 0x300
first.previousCameraHash = 0x300
first.currentCameraHash = 0x300
first.previousBindPoseHash = 0x400
first.currentBindPoseHash = 0x400
first.inputOlderToPreviousDistance = 1
first.inputPreviousToCurrentDistance = 1
first.inputOlderToCurrentDistance = 0
first.outputOlderToPreviousDistance = 1
first.outputPreviousToCurrentDistance = 1
first.outputOlderToCurrentDistance = 0
first.previousOutputExpectedDistance = 0.125
first.currentOutputExpectedDistance = 0.25
first.cameraOlderToPreviousDistance = 0
first.cameraPreviousToCurrentDistance = 0
first.cameraOlderToCurrentDistance = 0
first.previousInputTranslationX = 1
first.previousInputTranslationY = 2
first.previousInputTranslationZ = 3
first.currentInputTranslationX = 4
first.currentInputTranslationY = 5
first.currentInputTranslationZ = 6

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

var firstProvenance = first
firstProvenance.issueMask = 4
firstProvenance.previousOutputExpectedDistance = 0.25
firstProvenance.currentOutputExpectedDistance = 0.5

var lastProvenance = last
lastProvenance.issueMask = 128
lastProvenance.previousBindPoseHash = 0x400
lastProvenance.currentBindPoseHash = 0x500
lastProvenance.previousOutputExpectedDistance = 0.5
lastProvenance.currentOutputExpectedDistance = 1.5

var firstEicharPalette = GOALPadMercPaletteHealthEvent()
firstEicharPalette.engineFrameID = 60
firstEicharPalette.hostTickID = 100
firstEicharPalette.chainOrdinal = 2
firstEicharPalette.issueMask = 1
firstEicharPalette.nonfiniteLaneMask = (1 << 3) | (1 << 20)
firstEicharPalette.boneSlot = 3
firstEicharPalette.modelNameHash = 0xe1
firstEicharPalette.matrixHash = 0x600

var lastEicharPalette = firstEicharPalette
lastEicharPalette.engineFrameID = 61
lastEicharPalette.issueMask = 4
lastEicharPalette.nonfiniteLaneMask = 0
lastEicharPalette.sourceBase = 0x1600
lastEicharPalette.expectedSourceBase = 0x2600

var stats = GOALPadRendererStats()
stats.mercEicharTransformDiscontinuities = 1
stats.mercEicharTransformDiscontinuitiesTotal = 2
stats.mercEicharProvenanceEvents = 2
stats.mercEicharProvenanceEventsTotal = 3
stats.mercEicharOutputCompositionMismatches = 1
stats.mercEicharOutputCompositionMismatchesTotal = 2
stats.mercEicharPaletteHealthIssues = 1
stats.mercEicharPaletteHealthIssuesTotal = 2
stats.lastMercPaletteHealthNonfiniteLaneMask = (1 << 3) | (1 << 20)
stats.firstMercEicharTransformDiscontinuity = first
stats.lastMercEicharTransformDiscontinuity = last
stats.firstMercEicharProvenanceEvent = firstProvenance
stats.lastMercEicharProvenanceEvent = lastProvenance
stats.firstMercEicharPaletteHealthEvent = firstEicharPalette
stats.lastMercEicharPaletteHealthEvent = lastEicharPalette

precondition(stats.mercEicharTransformDiscontinuities == 1)
precondition(stats.mercEicharTransformDiscontinuitiesTotal == 2)
precondition(stats.mercEicharProvenanceEvents == 2)
precondition(stats.mercEicharProvenanceEventsTotal == 3)
precondition(stats.mercEicharOutputCompositionMismatches == 1)
precondition(stats.mercEicharOutputCompositionMismatchesTotal == 2)
precondition(stats.mercEicharPaletteHealthIssues == 1)
precondition(stats.mercEicharPaletteHealthIssuesTotal == 2)
precondition(stats.lastMercPaletteHealthNonfiniteLaneMask == (1 << 3) | (1 << 20))
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
precondition(stats.firstMercEicharTransformDiscontinuity.olderFrameID == 59)
precondition(stats.firstMercEicharTransformDiscontinuity.olderMatrixHash == 0x90)
precondition(stats.firstMercEicharTransformDiscontinuity.olderSourceBase == 0x600)
precondition(stats.firstMercEicharTransformDiscontinuity.inputRootBone == 3)
precondition(stats.firstMercEicharTransformDiscontinuity.currentProducerSerial == 12)
precondition(stats.firstMercEicharTransformDiscontinuity.olderInputRootHash
    == stats.firstMercEicharTransformDiscontinuity.currentInputRootHash)
precondition(stats.firstMercEicharTransformDiscontinuity.olderCameraHash
    == stats.firstMercEicharTransformDiscontinuity.currentCameraHash)
precondition(stats.firstMercEicharTransformDiscontinuity.inputOlderToCurrentDistance == 0)
precondition(stats.firstMercEicharTransformDiscontinuity.outputOlderToCurrentDistance == 0)
precondition(stats.firstMercEicharTransformDiscontinuity.cameraOlderToCurrentDistance == 0)
precondition(stats.firstMercEicharTransformDiscontinuity.previousInputTranslationY == 2)
precondition(stats.firstMercEicharTransformDiscontinuity.currentInputTranslationZ == 6)
precondition(stats.firstMercEicharTransformDiscontinuity.previousBindPoseHash == 0x400)
precondition(stats.firstMercEicharTransformDiscontinuity.currentOutputExpectedDistance == 0.25)
precondition(stats.firstMercEicharProvenanceEvent.issueMask == 4)
precondition(stats.firstMercEicharProvenanceEvent.previousOutputExpectedDistance == 0.25)
precondition(stats.firstMercEicharProvenanceEvent.currentOutputExpectedDistance == 0.5)
precondition(stats.lastMercEicharProvenanceEvent.issueMask == 128)
precondition(stats.lastMercEicharProvenanceEvent.currentBindPoseHash == 0x500)
precondition(stats.lastMercEicharProvenanceEvent.currentOutputExpectedDistance == 1.5)
precondition(stats.firstMercEicharPaletteHealthEvent.issueMask == 1)
precondition(stats.firstMercEicharPaletteHealthEvent.nonfiniteLaneMask == (1 << 3) | (1 << 20))
precondition(stats.lastMercEicharPaletteHealthEvent.issueMask == 4)
precondition(stats.lastMercEicharPaletteHealthEvent.expectedSourceBase == 0x2600)

print("merc transform diagnostics bridge check passed")
