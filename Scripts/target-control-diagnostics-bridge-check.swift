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
stats.jak1TieEnvmapSecondPassEnabled = false
stats.jak1TieEnvmapTextureSamplingEnabled = false
stats.tieEnvmapSecondPassDraws = 0
stats.tieEnvmapSecondPassDrawsTotal = 17
stats.jak1ShadowOutputEnabled = false
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
precondition(!stats.jak1TieEnvmapSecondPassEnabled.boolValue)
precondition(!stats.jak1TieEnvmapTextureSamplingEnabled.boolValue)
precondition(stats.tieEnvmapSecondPassDraws == 0)
precondition(stats.tieEnvmapSecondPassDrawsTotal == 17)
precondition(!stats.jak1ShadowOutputEnabled.boolValue)

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

var rootAnchor = GOALPadTargetControlRootAnchor()
rootAnchor.valid = true
rootAnchor.deformation = deformation
rootAnchor.scaleX = 1.25
rootAnchor.scaleY = 2.5
rootAnchor.scaleZ = 5
rootAnchor.scaleWBits = 0x80000000

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
observation.rootAnchor1 = rootAnchor
observation.rootAnchor2 = rootAnchor
observation.rootAnchor3 = rootAnchor
observation.node3ParentScaleCancellationSelected = true
observation.inputRootTranslationX = 10
observation.inputRootTranslationY = 20
observation.inputRootTranslationZ = 30

var telemetry = GOALPadTargetControlTelemetry()
telemetry.captureAttemptsTotal = 10
telemetry.validObservationsTotal = 8
telemetry.lastCaptureStage = 10
telemetry.lastCaptureResult = 1
telemetry.lastObservation = observation
telemetry.postFlagSamplesTotal = 12
telemetry.hiddenSamplesTotal = 3
telemetry.hiddenTransitionsTotal = 4
telemetry.postFlagSerialGapsTotal = 2
telemetry.unframedPostFlagSamplesTotal = 6

var postFlag = GOALPadTargetPostFlagObservation()
postFlag.valid = true
postFlag.hostTickID = 103
postFlag.chainOrdinal = 5
postFlag.engineFrameID = 803
postFlag.sampleSerial = 11
postFlag.targetAddress = 0x7000
postFlag.rawDrawStatus = 0x82
postFlag.targetAttackID = 10
postFlag.hidden = true
telemetry.lastPostFlagSample = postFlag
telemetry.lastHiddenPostFlagSample = postFlag

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
precondition(telemetry.lastObservation.rootAnchor1.scaleX == 1.25)
precondition(telemetry.lastObservation.rootAnchor2.scaleWBits == 0x80000000)
precondition(telemetry.lastObservation.rootAnchor3.deformation.aspect == 4)
precondition(telemetry.lastObservation.node3ParentScaleCancellationSelected.boolValue)
precondition(telemetry.lastObservation.inputRootTranslationZ == 30)
precondition(telemetry.postFlagSamplesTotal == 12)
precondition(telemetry.hiddenSamplesTotal == 3)
precondition(telemetry.hiddenTransitionsTotal == 4)
precondition(telemetry.postFlagSerialGapsTotal == 2)
precondition(telemetry.unframedPostFlagSamplesTotal == 6)
precondition(telemetry.lastPostFlagSample.sampleSerial == 11)
precondition(telemetry.lastPostFlagSample.rawDrawStatus == 0x82)
precondition(telemetry.lastPostFlagSample.targetAttackID == 10)
precondition(telemetry.lastHiddenPostFlagSample.hidden.boolValue)

precondition(CommandLine.arguments.count == 4)
let gameSessionSource = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
let schemaV7Tokens = [
    "\"goalpad_camera_provenance\", \"v=7\"",
    "_sample_serial=",
    "target_post_flag_samples_total=",
    "target_hidden_samples_total=",
    "target_hidden_transitions_total=",
    "target_post_flag_serial_gaps_total=",
    "target_unframed_post_flag_samples_total=",
    "_root1",
    "_root2",
    "_root3",
    "_node3_parent_scale_cancellation_selected=",
    "jak1_tie_envmap_second_pass_enabled=",
    "jak1_tie_envmap_texture_sampling_enabled=",
    "tie_envmap_second_pass_draws=",
    "tie_envmap_second_pass_draws_total=",
    "jak1_shadow_output_enabled=",
    "render_alternations=",
    "camera_tail_complete=",
    "camera_tail_trigger_degrees=",
    "_identity=",
    "_math_camera_object=",
    "_math_camera_type=",
    "_slave0_ppointer=",
    "_slave0_object=",
    "_slave0_type=",
    "merc_eichar_weighted_profiled_base_draws=",
    "merc_eichar_weighted_affected_vertices=",
    "merc_eichar_weighted_profile_capacity_drops=",
    "merc_eichar_weighted_maximum_axis_ratio=",
    "merc_eichar_weighted_coverage=",
    "merc_eichar_repeated_packets_conflicting_palette=",
    "merc_eichar_repeated_base_draws_conflicting_palette=",
    "merc_eichar_trace_capacity_drops=",
    "merc_eichar_bound_palette_hash_mismatches=",
    "merc_eichar_weighted_skin_evidence_total=",
    "merc_eichar_weighted_issue_mask=",
    "last_merc_eichar_weighted_skin_engine_frame=",
]
for token in schemaV7Tokens {
    precondition(gameSessionSource.contains(token), "missing schema-v7 token: \(token)")
}
precondition(!gameSessionSource.contains("\"v=6\""))
precondition(gameSessionSource.contains("CameraDiagnosticsPersistencePolicy.shouldPersist"))
precondition(!gameSessionSource.contains("alternationNotPersisted"))
precondition(!gameSessionSource.contains("correctionNotPersisted"))
precondition(gameSessionSource.contains(
    "hiddenTransitionNotPersisted && hiddenTransitionNotAttempted"))
precondition(gameSessionSource.contains("weightedSkinNotAttempted"))
precondition(gameSessionSource.contains("lastAttemptedMercWeightedSkinEvidenceTotal"))

let metalHostSource = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
for token in [
    "constexpr bool kJak1TieEnvmapSecondPassEnabled = true;",
    "constexpr bool kJak1TieEnvmapTextureSamplingEnabled = false;",
    "constexpr bool kJak1ShadowOutputEnabled = false;",
    "set_jak1_tie_envmap_texture_sampling_enabled(",
    "jak1_tie_envmap_texture_sampling_enabled =",
] {
    precondition(metalHostSource.contains(token), "missing CP80 host token: \(token)")
}

let renderSurfaceSource = try String(contentsOfFile: CommandLine.arguments[3], encoding: .utf8)
precondition(renderSurfaceSource.contains("core.jak1_tie_envmap_texture_sampling_enabled"),
             "missing CP80 render-surface telemetry bridge")

print("target control diagnostics bridge check passed")
