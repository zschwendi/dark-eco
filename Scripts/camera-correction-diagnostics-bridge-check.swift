import Foundation

var previousSlave = GOALPadCameraCorrectionSlaveFrame()
previousSlave.valid = true
previousSlave.options = UInt32(1 << 9)
previousSlave.losState = 0
previousSlave.lineOfSightEnabled = true
previousSlave.viewFlat = GOALPadCameraCorrectionVector(x: 1, y: 2, z: 3, w: 4)

var currentSlave = previousSlave
currentSlave.options |= UInt32(1 << 10)
currentSlave.losState = 1
currentSlave.movementBlocked = true
currentSlave.maxAngleOffset = 90
currentSlave.maxAngleCurrent = 45
currentSlave.viewFlat = GOALPadCameraCorrectionVector(x: 4, y: 3, z: 2, w: 1)
currentSlave.trackingInverseMatrix.axis2 =
    GOALPadCameraCorrectionVector(x: 0, y: 0, z: 1, w: 0)

var previous = GOALPadCameraCorrectionFrame()
previous.valid = true
previous.engineFrameID = 100
previous.displayTimeRatio = 1
previous.numSlaves = 1
previous.slave0 = previousSlave

var current = previous
current.engineFrameID = 101
current.displayTimeRatio = 0.75
current.beingAttacked = true
current.slave0 = currentSlave
current.combinerValid = true
current.combinerInterpolation = 0.5
current.combinerTrackingStatus = 1
current.combinerInverseCameraRotation.axis2 =
    GOALPadCameraCorrectionVector(x: -1, y: 0, z: 0, w: 0)

var event = GOALPadCameraCorrectionEvent()
event.valid = true
event.reasonMask = UInt8((1 << 0) | (1 << 1) | (1 << 2))
event.hostTickID = 200
event.chainOrdinal = 1
event.previous = previous
event.current = current

var stats = GOALPadRendererStats()
stats.cameraCorrectionEventsTotal = 1
stats.lastCameraCorrectionEvent = event

precondition(stats.cameraCorrectionEventsTotal == 1)
precondition(stats.lastCameraCorrectionEvent.valid.boolValue)
precondition(stats.lastCameraCorrectionEvent.reasonMask == 7)
precondition(stats.lastCameraCorrectionEvent.previous.slave0.losState == 0)
precondition(stats.lastCameraCorrectionEvent.current.slave0.losState == 1)
precondition(stats.lastCameraCorrectionEvent.current.slave0.lineOfSightEnabled.boolValue)
precondition(stats.lastCameraCorrectionEvent.current.slave0.movementBlocked.boolValue)
precondition(stats.lastCameraCorrectionEvent.current.slave0.maxAngleOffset == 90)
precondition(stats.lastCameraCorrectionEvent.current.slave0.maxAngleCurrent == 45)
precondition(stats.lastCameraCorrectionEvent.current.slave0.trackingInverseMatrix.axis2.z == 1)
precondition(stats.lastCameraCorrectionEvent.previous.slave0.viewFlat.x
    != stats.lastCameraCorrectionEvent.current.slave0.viewFlat.x)
precondition(stats.lastCameraCorrectionEvent.current.beingAttacked.boolValue)
precondition(stats.lastCameraCorrectionEvent.current.combinerInterpolation == 0.5)
precondition(stats.lastCameraCorrectionEvent.current.combinerInverseCameraRotation.axis2.x == -1)

print("camera correction diagnostics bridge check passed")
