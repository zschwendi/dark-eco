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

var raw = GOALPadTargetControlVector4()
raw.x = 1
raw.y = 2
raw.z = 3
raw.w = 4

var facing = GOALPadTargetControlFacing()
facing.valid = true
facing.x = 0.6
facing.z = 0.8

var basis = GOALPadTargetControlBasis()
basis.valid = true
basis.axis0X = 1
basis.axis1Y = 1
basis.axis2Z = 1

var deformation = GOALPadTargetControlDeformation()
deformation.valid = true
deformation.axisNormX = 0.5
deformation.axisNormY = 1
deformation.axisNormZ = 2
deformation.aspect = 4
deformation.normalizedAbsDeterminant = 0.75

var observation = GOALPadTargetControlObservation()
observation.valid = true
observation.hostTickID = 102
observation.chainOrdinal = 4
observation.engineFrameID = 802
observation.probeBoneSlot = 6
observation.producerSerial = 5
observation.sourceBase = 0x2600
observation.cameraHash = 0x3000
observation.targetStateID = 0x4000
observation.targetAttackID = 9
observation.button0Abs = 0x8000
observation.button0Rel = 0x8000
observation.leftX = 0x80
observation.leftY = 0x40
observation.stickDirection = 0.5
observation.stickSpeed = 0.75
observation.padMagnitude = 1
observation.rawDirTarg = raw
observation.rawQuatForControl = raw
observation.rawRenderQuat = raw
observation.rawTurnToTarget = raw
observation.intentForward = facing
observation.desiredForward = facing
observation.controlForward = facing
observation.renderForward = facing
observation.rootForward = facing
observation.cameraBasis = basis
observation.inputRootDeformation = deformation
observation.outputDeformation = deformation
observation.inputRootTranslationX = 10
observation.inputRootTranslationY = 20
observation.inputRootTranslationZ = 30

var telemetry = GOALPadTargetControlTelemetry()
telemetry.captureAttemptsTotal = 10
telemetry.validObservationsTotal = 8
telemetry.lastCaptureStage = 10
telemetry.lastCaptureResult = 1
telemetry.lastObservation = observation

precondition(telemetry.captureAttemptsTotal == 10)
precondition(telemetry.validObservationsTotal == 8)
precondition(telemetry.lastCaptureStage == 10)
precondition(telemetry.lastCaptureResult == 1)
precondition(telemetry.lastObservation.valid.boolValue)
precondition(telemetry.lastObservation.engineFrameID == 802)
precondition(telemetry.lastObservation.probeBoneSlot == 6)
precondition(telemetry.lastObservation.button0Rel == 0x8000)
precondition(telemetry.lastObservation.rawDirTarg.w == 4)
precondition(telemetry.lastObservation.intentForward.z == 0.8)
precondition(telemetry.lastObservation.cameraBasis.axis2Z == 1)
precondition(telemetry.lastObservation.inputRootDeformation.aspect == 4)
precondition(telemetry.lastObservation.outputDeformation.normalizedAbsDeterminant == 0.75)
precondition(telemetry.lastObservation.inputRootTranslationZ == 30)

print("target control diagnostics bridge check passed")
