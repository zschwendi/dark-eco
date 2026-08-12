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

private func source(_ root: String, _ relativePath: String) -> String {
    let path = root + "/" + relativePath
    guard let value = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("  FAIL could not read \(relativePath)")
        Foundation.exit(1)
    }
    return value
}

private func section(_ source: String, from start: String, to end: String) -> String {
    guard let lower = source.range(of: start),
          let upper = source.range(of: end, range: lower.upperBound..<source.endIndex) else {
        print("  FAIL could not isolate source section from \(start) to \(end)")
        failures += 1
        return ""
    }
    return String(source[lower.lowerBound..<upper.lowerBound])
}

private func occursInOrder(_ needles: [String], in source: String) -> Bool {
    var lower = source.startIndex
    for needle in needles {
        guard let match = source.range(of: needle, range: lower..<source.endIndex) else {
            return false
        }
        lower = match.upperBound
    }
    return true
}

guard CommandLine.arguments.count == 2 else {
    print("usage: swift Scripts/promotion-frame-rate-check.swift <repository-root>")
    Foundation.exit(2)
}

let root = CommandLine.arguments[1]
let plist = source(root, "GOALPad-Info.plist")
let surface = source(root, "GOALPad/Game/GameSurfaceView.swift")
let content = source(root, "GOALPad/ContentView.swift")
let session = source(root, "GOALPad/Game/GameSession.swift")
let bridgeHeader = source(root, "GOALPad/Native/GOALPadRuntimeBridge.h")
let bridge = source(root, "GOALPad/Native/GOALPadRuntimeBridge.mm")
let boot = source(root, "GOALPad/Native/GOALPadGameBoot.cpp")
let display = source(root, "OpenGOAL/goal_src/jak1/engine/gfx/hw/display.gc")
let drawable = source(root, "OpenGOAL/goal_src/jak1/engine/draw/drawable.gc")
let pad = source(root, "OpenGOAL/goal_src/jak1/engine/ps2/pad.gc")
let eye = source(root, "OpenGOAL/goal_src/jak1/engine/gfx/foreground/eye.gc")
let touch = source(root, "GOALPad/Game/TouchControls.swift")
let pcKernel = source(root, "OpenGOAL/goal_src/jak1/pc/pckernel-common.gc")
let progress = source(root, "OpenGOAL/goal_src/jak1/pc/progress-pc.gc")
let speedruns = source(root, "OpenGOAL/goal_src/jak1/pc/features/speedruns.gc")
let debugMenu = source(root, "OpenGOAL/goal_src/jak1/pc/debug/default-menu-pc.gc")

check(plist.contains("<key>CADisableMinimumFrameDurationOnPhone</key>")
        && plist.contains("<true/>"),
      "iPhone opts into display rates above 60 Hz")
check(surface.contains("window?.screen.maximumFramesPerSecond")
        && surface.contains("minimum: 60, maximum: maximum, preferred: maximum")
        && surface.contains("onFrame?(link.targetTimestamp)"),
      "the iOS display link requests adaptive ProMotion cadence and uses its presentation target")
check(session.contains("let bootTargetFrameRate = presentationSettings.graphicsHighFrameRate ? 120 : 60")
        && session.contains("bootGame(targetFrameRate: bootTargetFrameRate)")
        && session.contains("self.bootFinished(boot, targetFrameRate: bootTargetFrameRate)")
        && session.contains("targetFrameRate = bootFrameRate\n        isRunning = true")
        && session.contains("func setHighFrameRateEnabled(_ enabled: Bool)")
        && session.contains("guard isRunning else { return }")
        && session.contains("GOALPadRuntimeBridge.setTargetFrameRate(requestedFrameRate)")
        && content.contains(".onChange(of: session.presentationSettings.graphicsHighFrameRate")
        && content.contains("session.setHighFrameRateEnabled(enabled)"),
      "the persisted 60/120 Hz choice applies at boot and live without accelerating the launcher")
check(content.components(separatedBy: "targetFrameRate: session.targetFrameRate").count == 3,
      "conventional and stereo-capable surfaces receive the session target")
check(bridgeHeader.contains("NS_SWIFT_NAME(bootGame(targetFrameRate:))")
        && bridgeHeader.contains("+ (BOOL)setTargetFrameRate:(NSInteger)targetFrameRate;")
        && bridge.contains("goalpad::boot_game(static_cast<int>(targetFrameRate))")
        && bridge.contains("goalpad::set_target_frame_rate(static_cast<int>(targetFrameRate))"),
      "boot and live preferences cross the narrow Objective-C++ bridge")
check(boot.contains("g_display_clock.advance(target_presentation_time, g_target_frame_rate)")
        && boot.contains("g_sound_frame_clock.advance(display_time_ratio, g_target_frame_rate)")
        && boot.contains("goalpad-set-target-frame-rate")
        && boot.contains("bool set_target_frame_rate(int target_frame_rate) noexcept")
        && boot.contains("g_display_clock.reset();\n    g_sound_frame_clock.reset();")
        && boot.contains("s64 app_pc_get_active_display_refresh_rate() {\n  return g_target_frame_rate;\n}")
        && boot.contains("void reset_frame_timing() noexcept {\n#if TARGET_OS_IOS || TARGET_OS_VISION\n  g_display_clock.reset();\n#endif"),
      "native timing drives gameplay cadence and resets both clocks on a live domain change")
check(drawable.contains("(defun goalpad-set-target-frame-rate")
        && drawable.contains("(set-frame-rate! *pc-settings* rate #t)")
        && drawable.contains("*host-game-scaled-time-remainder*")
        && drawable.contains("*host-non-movie-scaled-time-remainder*")
        && drawable.contains("*host-real-integral-time-remainder*"),
      "GOAL selects custom 120 Hz timing and carries fractional frame counters")
check(display.contains("(if (> *host-display-time-ratio* 0.0)")
        && display.contains("(* DISPLAY_FPS_RATIO *host-display-time-ratio*)")
        && display.contains("DISPLAY_FPS_RATIO))")
        && display.contains("(= (-> *pc-settings* target-fps) 120)")
        && display.contains("5.0")
        && eye.contains("(if (> *host-display-time-ratio* 0.0)")
        && eye.contains("(-> *display* old-real-integral-frame-counter)")
        && eye.contains("(-> *display* real-integral-frame-counter)")
        && eye.contains("                                   -1)\n                                 -1)"),
      "host-managed per-callback fixes and eye timers follow adaptive fallback cadence")
check(pad.contains("(defun service-cpads ((history-steps int))")
        && pad.contains("((and (= (-> *pc-settings* target-fps) 120)")
        && pad.contains("(> *host-display-time-ratio* 0.0)")
        && pad.contains("(dotimes (virtual-step history-steps)"),
      "controller recent-press history ages by virtual frames at adaptive refresh factors")
check(drawable.contains("(min (if (and (= (-> *pc-settings* target-fps) 120)")
        && drawable.contains("> *host-display-time-ratio* 0.0))")
        && drawable.contains("                               5\n                               4)"),
      "24 Hz adaptive fallback preserves five target frames of controller history")

let managedGraphics = section(progress,
                              from: "(define *graphic-options-managed-display*",
                              to: "(define *sound-options-pc*")
let graphicsPointerSetup = section(progress,
                                   from: ";; our options!",
                                   to: ";; input options")
check(!managedGraphics.contains("(game-option-type frame-rate)")
        && !managedGraphics.contains("(text-id frame-rate)")
        && !graphicsPointerSetup.contains("*graphic-options-managed-display*")
        && touch.contains("static let graphicSettings = 4"),
      "the managed-display graphics menu exposes no legacy frame-rate row or pointer")
check(managedGraphics.contains("(text-id game-resolution)")
        && managedGraphics.contains("(text-id aspect-ratio)")
        && managedGraphics.contains("(text-id ps2-options)")
        && managedGraphics.contains("(text-id back)"),
      "removing frame rate preserves the remaining managed-display graphics rows")

let frameRateSetter = section(pcKernel,
                              from: "(defmethod set-frame-rate!",
                              to: "(defmethod commit-to-file")
check(frameRateSetter.contains(
        "(let ((effective-rate (if (pc-host-manages-display?) (pc-get-active-display-refresh-rate) rate)))")
        && frameRateSetter.contains("(pc-set-frame-rate effective-rate)")
        && frameRateSetter.contains("(set! (-> obj target-fps) effective-rate)")
        && frameRateSetter.contains("(case effective-rate")
        && frameRateSetter.contains("effective-rate))"),
      "the central frame-rate writer retains the active host refresh on managed displays")
check(frameRateSetter.contains("(pc-host-manages-display?)")
        && frameRateSetter.contains("(pc-get-active-display-refresh-rate) rate"),
      "ordinary desktop keeps the requested frame rate when the host does not manage display")
check(speedruns.contains("(set-frame-rate! *pc-settings* 60 #t)")
        && !speedruns.contains("(set! (-> *pc-settings* target-fps)")
        && debugMenu.contains("(set-frame-rate! *pc-settings* fps #t)")
        && !debugMenu.contains("(set! (-> *pc-settings* target-fps)"),
      "speedrun and debug late writers remain routed through managed-host authority")
check(progress.contains("(set-frame-rate! *pc-settings* 60 #t)")
        && progress.contains("(set-frame-rate! *pc-settings* 100 #t)")
        && progress.contains("(set-frame-rate! *pc-settings* 150 #t)"),
      "the unchanged desktop progress row still routes all legacy choices through the setter")

let sceneLifecycle = section(session,
                             from: "func scenePhaseChanged",
                             to: "private func beginForegroundPreparation")
check(occursInOrder([
    "case .inactive:",
    "touch.reset()",
    "resetDisplayTiming()",
    "audio.suspend()",
    "case .background:",
    "touch.reset()",
    "resetDisplayTiming()",
    "audio.suspend()",
], in: sceneLifecycle),
      "inactive and background stop input, reset display cadence, then suspend audio")
let displayTimingReset = section(session,
                                 from: "private func resetDisplayTiming()",
                                 to: "private func observeSystem()")
check(occursInOrder([
    "if isRunning {",
    "GOALPadRuntimeBridge.resetFrameTiming()",
    "previousDisplayCallback = nil",
    "displayIntervals.removeAll(keepingCapacity: true)",
    "displaySampleCount = 0",
], in: displayTimingReset),
      "lifecycle reset reaches native cadence before clearing diagnostic samples")
let nativeTimingReset = section(boot,
                                from: "void reset_frame_timing() noexcept",
                                to: "CameraFrameIdentity current_camera_frame_identity")
check(nativeTimingReset.contains("g_display_clock.reset();")
        && !nativeTimingReset.contains("g_sound_frame_clock.reset();")
        && boot.contains("g_display_clock.reset();\n    g_sound_frame_clock.reset();"),
      "suspension keeps earned sound debt while a new boot resets both timing clocks")

guard failures == 0 else {
    print("promotion frame-rate checks failed: \(failures)")
    Foundation.exit(1)
}
print("promotion frame-rate checks passed")
