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
currentSlave.viewFlat = GOALPadCameraCorrectionVector(x: 4, y: 3, z: 2, w: 1)

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

var event = GOALPadCameraCorrectionEvent()
event.valid = true
event.reasonMask = UInt8((1 << 0) | (1 << 1))
event.hostTickID = 200
event.chainOrdinal = 1
event.previous = previous
event.current = current

var stats = GOALPadRendererStats()
stats.cameraCorrectionEventsTotal = 1
stats.lastCameraCorrectionEvent = event

precondition(stats.cameraCorrectionEventsTotal == 1)
precondition(stats.lastCameraCorrectionEvent.valid.boolValue)
precondition(stats.lastCameraCorrectionEvent.reasonMask == 3)
precondition(stats.lastCameraCorrectionEvent.previous.slave0.losState == 0)
precondition(stats.lastCameraCorrectionEvent.current.slave0.losState == 1)
precondition(stats.lastCameraCorrectionEvent.current.slave0.lineOfSightEnabled.boolValue)
precondition(stats.lastCameraCorrectionEvent.current.slave0.movementBlocked.boolValue)
precondition(stats.lastCameraCorrectionEvent.previous.slave0.viewFlat.x
    != stats.lastCameraCorrectionEvent.current.slave0.viewFlat.x)
precondition(stats.lastCameraCorrectionEvent.current.beingAttacked.boolValue)
precondition(stats.lastCameraCorrectionEvent.current.combinerInterpolation == 0.5)

print("camera correction diagnostics bridge check passed")
