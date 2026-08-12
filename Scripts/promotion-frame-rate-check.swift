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

check(plist.contains("<key>CADisableMinimumFrameDurationOnPhone</key>")
        && plist.contains("<true/>"),
      "iPhone opts into display rates above 60 Hz")
check(surface.contains("window?.screen.maximumFramesPerSecond")
        && surface.contains("minimum: 60, maximum: maximum, preferred: maximum")
        && surface.contains("onFrame?(link.targetTimestamp)"),
      "the iOS display link requests adaptive ProMotion cadence and uses its presentation target")
check(session.contains("targetFrameRate = presentationSettings.graphicsHighFrameRate ? 120 : 60")
        && session.contains("let bootTargetFrameRate = targetFrameRate")
        && session.contains("bootGame(targetFrameRate: bootTargetFrameRate)"),
      "one immutable 60/120 Hz target is captured for each gameplay boot")
check(content.components(separatedBy: "targetFrameRate: session.targetFrameRate").count == 3,
      "conventional and stereo-capable surfaces receive the session target")
check(bridgeHeader.contains("NS_SWIFT_NAME(bootGame(targetFrameRate:))")
        && bridge.contains("goalpad::boot_game(static_cast<int>(targetFrameRate))"),
      "the Swift preference crosses the narrow Objective-C++ bridge")
check(boot.contains("g_display_clock.advance(target_presentation_time, g_target_frame_rate)")
        && boot.contains("g_sound_frame_clock.advance(display_time_ratio, g_target_frame_rate)")
        && boot.contains("goalpad-set-target-frame-rate")
        && boot.contains("void reset_frame_timing() noexcept {\n#if TARGET_OS_IOS || TARGET_OS_VISION\n  g_display_clock.reset();\n#endif"),
      "native timing drives gameplay cadence while preserving the 60 Hz sound clock")
check(drawable.contains("(defun goalpad-set-target-frame-rate")
        && drawable.contains("(set-frame-rate! *pc-settings* rate #t)")
        && drawable.contains("*host-game-scaled-time-remainder*")
        && drawable.contains("*host-non-movie-scaled-time-remainder*")
        && drawable.contains("*host-real-integral-time-remainder*"),
      "GOAL selects custom 120 Hz timing and carries fractional frame counters")
check(display.contains("(if (> *host-display-time-ratio* 0.0)")
        && display.contains("(* DISPLAY_FPS_RATIO *host-display-time-ratio*)")
        && display.contains("DISPLAY_FPS_RATIO))")
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

guard failures == 0 else {
    print("promotion frame-rate checks failed: \(failures)")
    Foundation.exit(1)
}
print("promotion frame-rate checks passed")
