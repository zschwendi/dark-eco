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
previous.mathCameraObjectOffset = 0x0800
previous.mathCameraTypeOffset = 0x0804
previous.masterObjectOffset = 0x1000
previous.masterTypeOffset = 0x1004
previous.combinerObjectOffset = 0x2000
previous.combinerTypeOffset = 0x2004
previous.slave0PpointerOffset = 0x3000
previous.slave0ObjectOffset = 0x4000
previous.slave0TypeOffset = 0x4004
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
event.reasonMask = UInt8((1 << 0) | (1 << 1) | (1 << 2) | (1 << 3))
event.hostTickID = 200
event.chainOrdinal = 1
event.previous = previous
event.current = current

var stats = GOALPadRendererStats()
stats.renderCameraAlternations = 2
stats.lastRenderCameraAlternationOlderFrameID = 98
stats.lastRenderCameraAlternationPreviousFrameID = 99
stats.lastRenderCameraAlternationCurrentFrameID = 100
stats.lastRenderCameraAlternationPacketFingerprint = 0x1234
stats.lastRenderCameraAlternationLiveMismatchQwords = 0x0101
stats.lastRenderCameraAlternationPacketMismatchQwords = 0x2020
stats.cameraCorrectionEventsTotal = 1
stats.lastCameraCorrectionEvent = event

var tailInfo = GOALPadCameraCorrectionTailInfo()
tailInfo.valid = true
tailInfo.complete = true
tailInfo.frameCount = 18
tailInfo.triggerEngineFrameID = 99
tailInfo.triggerOrientationDegrees = 16

var tailFrame = GOALPadCameraCorrectionTailFrame()
tailFrame.valid = true
tailFrame.hostTickID = 200
tailFrame.chainOrdinal = 3
tailFrame.renderCameraFingerprint = 0x5678
tailFrame.camera = current

func inspectTailSnapshot(_ snapshot: GOALPadCameraCorrectionTailSnapshot) {
    _ = snapshot.info
    _ = snapshot.frame(at: 0)
}

precondition(stats.cameraCorrectionEventsTotal == 1)
precondition(stats.renderCameraAlternations == 2)
precondition(stats.lastRenderCameraAlternationOlderFrameID == 98)
precondition(stats.lastRenderCameraAlternationPacketFingerprint == 0x1234)
precondition(stats.lastRenderCameraAlternationLiveMismatchQwords == 0x0101)
precondition(stats.lastRenderCameraAlternationPacketMismatchQwords == 0x2020)
precondition(stats.lastCameraCorrectionEvent.valid.boolValue)
precondition(stats.lastCameraCorrectionEvent.reasonMask == 15)
precondition(stats.lastCameraCorrectionEvent.previous.slave0.losState == 0)
precondition(stats.lastCameraCorrectionEvent.previous.mathCameraObjectOffset == 0x0800)
precondition(stats.lastCameraCorrectionEvent.previous.mathCameraTypeOffset == 0x0804)
precondition(stats.lastCameraCorrectionEvent.previous.masterObjectOffset == 0x1000)
precondition(stats.lastCameraCorrectionEvent.previous.masterTypeOffset == 0x1004)
precondition(stats.lastCameraCorrectionEvent.previous.combinerObjectOffset == 0x2000)
precondition(stats.lastCameraCorrectionEvent.previous.combinerTypeOffset == 0x2004)
precondition(stats.lastCameraCorrectionEvent.previous.slave0PpointerOffset == 0x3000)
precondition(stats.lastCameraCorrectionEvent.previous.slave0ObjectOffset == 0x4000)
precondition(stats.lastCameraCorrectionEvent.previous.slave0TypeOffset == 0x4004)
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
precondition(tailInfo.valid.boolValue && tailInfo.complete.boolValue)
precondition(tailInfo.frameCount == 18 && tailInfo.triggerOrientationDegrees == 16)
precondition(tailFrame.valid.boolValue && tailFrame.hostTickID == 200)
precondition(tailFrame.renderCameraFingerprint == 0x5678)
precondition(tailFrame.camera.engineFrameID == 101)
precondition(tailFrame.camera.masterObjectOffset == 0x1000)

print("camera correction diagnostics bridge check passed")
