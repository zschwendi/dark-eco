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

private func section(_ source: String, from start: String, to end: String) -> String {
    guard let lower = source.range(of: start),
          let upper = source.range(of: end, range: lower.upperBound..<source.endIndex) else {
        return ""
    }
    return String(source[lower.lowerBound..<upper.lowerBound])
}

private func ordered(_ source: String, _ values: [String]) -> Bool {
    var lower = source.startIndex
    for value in values {
        guard let range = source.range(of: value, range: lower..<source.endIndex) else {
            return false
        }
        lower = range.upperBound
    }
    return true
}

guard CommandLine.arguments.count == 2 else {
    fputs("usage: native-runtime-router-source-check <repository-root>\n", stderr)
    exit(2)
}

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let header = try String(contentsOf: root.appendingPathComponent(
    "GOALPad/Native/GOALPadRuntimeBridge.h"), encoding: .utf8)
let runtime = try String(contentsOf: root.appendingPathComponent(
    "GOALPad/Native/GOALPadRuntimeBridge.mm"), encoding: .utf8)
let surface = try String(contentsOf: root.appendingPathComponent(
    "GOALPad/Native/GOALPadRenderSurface.mm"), encoding: .utf8)
let privateHeader = try String(contentsOf: root.appendingPathComponent(
    "GOALPad/Native/GOALPadRuntimeRouterPrivate.h"), encoding: .utf8)

check(header.contains("GOALPadGameIdentifierJak1 = 0") &&
      header.contains("GOALPadGameIdentifierJak2 = 1"),
      "the public game identifier has stable Jak 1 and Jak II values")
check(header.contains("+ (BOOL)selectGame:(GOALPadGameIdentifier)gameIdentifier") &&
      header.contains("+ (BOOL)isGameCodeLinkedForGame:(GOALPadGameIdentifier)gameIdentifier"),
      "the public bridge exposes selection and title-aware AOT availability")
check(privateHeader.contains("TARGET_OS_IOS && __has_include") &&
      privateHeader.contains("<GOALPadJak2Runtime/GOALPadJak2Runtime.h>"),
      "the Jak II façade is compile-time gated to an available iOS framework")
check(runtime.contains("static std::atomic<int32_t> gActiveGameIdentifier") &&
      runtime.contains("std::memory_order_acquire") &&
      runtime.contains("std::memory_order_release"),
      "the active identifier is published and consumed atomically")

let selection = section(runtime, from: "+ (BOOL)selectGame:", to: "+ (GOALPadGameIdentifier)activeGameIdentifier")
check(selection.contains("goalpad::kernel_is_running()") &&
      selection.contains("[GOALPadJak2RuntimeBridge isKernelRunning]"),
      "selection checks both kernels before changing titles")
check(ordered(selection, ["goalpadDetachActiveBackendPreservingConfiguration",
                          "gActiveGameIdentifier.store",
                          "goalpadReplayConfigurationForActiveGame"]),
      "selection detaches the old surface before publish and replays after publish")

let audioPull = section(runtime, from: "int32_t GOALPadAudioPull", to: "#endif\n}")
check(audioPull.contains("GOALPadIsJak2Active()") &&
      audioPull.contains("GOALPadJak2AudioPull(out, frames)") &&
      !audioPull.contains("[") && !audioPull.contains("alloc") && !audioPull.contains("mutex"),
      "audio pull uses only the atomic route and direct C façades")
check(runtime.contains("GOALPadJak2InputSetState(port, state)") &&
      runtime.contains("GOALPadJak2InputSetDisconnected(port)") &&
      runtime.contains("GOALPadJak2InputSetRumbleEnabled(port, enabled)"),
      "controller calls forward to uniquely prefixed Jak II entry points")
check(runtime.contains("GOALPadKernelStatusFromJak2") &&
      runtime.contains("GOALPadGameBootStatusFromJak2") &&
      runtime.contains("[GOALPadJak2RuntimeBridge runFrameAtPresentationTime"),
      "runtime status, boot, and frame calls route through the Jak II façade")

check(surface.contains("_detailedFrameStatsEnabled") &&
      surface.contains("goalpadReplayConfigurationForActiveGame") &&
      surface.contains("[self attachLayer:_layer]") &&
      surface.contains("[self setDrawableSize:_drawableSize]") &&
      surface.contains("[self setInternalResolutionScale:_internalScale]") &&
      surface.contains("[self setHorizontalPlusEnabled:_horizontalPlusEnabled]") &&
      surface.contains("[self setDetailedFrameStatsEnabled:_detailedFrameStatsEnabled]"),
      "surface configuration is cached and replayed across title selection")
check(surface.contains("[[GOALPadJak2RenderSurface shared] attachLayer:nil]") &&
      surface.contains("goalpad::metal_host_attach_layer(nil)"),
      "switching explicitly detaches the previously active backend surface")
check(surface.contains("return [[GOALPadJak2RenderSurface shared] beginFrameAtTime:presentationTime]") &&
      surface.contains("return [[GOALPadJak2RenderSurface shared] endFrame]"),
      "ordinary Jak II render frames forward to the framework surface")
check(surface.contains("Jak II stereoscopic rendering is unavailable.") &&
      surface.contains("return GOALPadStereoFrameReservationFailed") &&
      surface.contains("return GOALPadStereoFrameCompletionFailed"),
      "Jak II stereo rendering fails closed")

if failures == 0 {
    print("native runtime router source checks passed")
} else {
    print("native runtime router source checks failed: \(failures)")
    exit(1)
}
