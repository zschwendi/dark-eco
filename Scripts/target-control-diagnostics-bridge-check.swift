import Foundation

var first = GOALPadTargetControlEvent()
first.hostTickID = 100
first.chainOrdinal = 2
first.issueMask = 1
first.engineFrameID = 800
first.producerSerial = 3
first.sourceBase = 0x1600
first.targetStateID = 0x2000
first.previousTargetAttackID = 7
first.currentTargetAttackID = 7
first.button0Abs = 0x8000
first.button0Rel = 0
first.leftX = 0x40
first.leftY = 0xc0
first.stickDirection = 0.25
first.stickSpeed = 0.75
first.padMagnitude = 1
first.intentForwardX = 0
first.intentForwardZ = 1
first.desiredForwardX = 0.5
first.desiredForwardZ = 0.5
first.controlForwardX = 0
first.controlForwardZ = -1
first.renderForwardX = 0
first.renderForwardZ = -1
first.rootForwardX = 0
first.rootForwardZ = 1
first.intentControlDot = -1
first.controlRenderDot = 1
first.renderRootDot = -1

var last = first
last.hostTickID = 101
last.chainOrdinal = 3
last.issueMask = 3
last.engineFrameID = 801
last.previousTargetAttackID = 7
last.currentTargetAttackID = 8
last.button0Rel = 0x8000

var stats = GOALPadRendererStats()
stats.mercEicharTargetControlEvents = 1
stats.mercEicharTargetControlEventsTotal = 2
stats.mercEicharTargetControlDivergences = 1
stats.mercEicharTargetControlDivergencesTotal = 2
stats.mercEicharTargetControlAttackBoundaries = 1
stats.mercEicharTargetControlAttackBoundariesTotal = 1
stats.firstMercEicharTargetControlEvent = first
stats.lastMercEicharTargetControlEvent = last

precondition(stats.mercEicharTargetControlEvents == 1)
precondition(stats.mercEicharTargetControlEventsTotal == 2)
precondition(stats.mercEicharTargetControlDivergencesTotal == 2)
precondition(stats.mercEicharTargetControlAttackBoundariesTotal == 1)
precondition(stats.firstMercEicharTargetControlEvent.issueMask == 1)
precondition(stats.firstMercEicharTargetControlEvent.engineFrameID == 800)
precondition(stats.firstMercEicharTargetControlEvent.targetStateID == 0x2000)
precondition(stats.firstMercEicharTargetControlEvent.leftY == 0xc0)
precondition(stats.firstMercEicharTargetControlEvent.intentForwardZ == 1)
precondition(stats.firstMercEicharTargetControlEvent.intentControlDot == -1)
precondition(stats.lastMercEicharTargetControlEvent.issueMask == 3)
precondition(stats.lastMercEicharTargetControlEvent.currentTargetAttackID == 8)
precondition(stats.lastMercEicharTargetControlEvent.button0Rel == 0x8000)
precondition(stats.lastMercEicharTargetControlEvent.hostTickID == 101)

print("target control diagnostics bridge check passed")
