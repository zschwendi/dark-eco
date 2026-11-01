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

private func source(_ root: String, _ path: String) -> String {
    do {
        return try String(contentsOfFile: root + "/" + path, encoding: .utf8)
    } catch {
        print("  FAIL could not read \(path): \(error.localizedDescription)")
        exit(1)
    }
}

private func section(_ source: String, from start: String, to end: String) -> String {
    guard let lower = source.range(of: start),
          let upper = source.range(of: end, range: lower.upperBound..<source.endIndex) else {
        print("  FAIL could not isolate \(start)")
        failures += 1
        return ""
    }
    return String(source[lower.lowerBound..<upper.lowerBound])
}

private func occursInOrder(_ values: [String], in source: String) -> Bool {
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
    print("usage: vision-immersive-per-eye-integration-check <repository-root>")
    exit(2)
}

let root = CommandLine.arguments[1]
let presenter = source(root, "GOALPad/Vision/Immersive/VisionImmersiveFramePresenter.swift")
let contract = source(root, "GOALPad/Vision/Immersive/VisionImmersiveFrameContract.swift")
let shader = source(root, "GOALPad/Vision/Immersive/VisionImmersivePresentation.metal")
let plan = source(root, "GOALPad/Vision/Immersive/VisionImmersivePresentationPlan.swift")
let evidence = source(root, "GOALPad/Vision/Immersive/VisionImmersiveRenderEvidence.swift")

print("Per-eye request")
check(occursInOrder([
    "let drawables = layerFrame.queryDrawables()",
    "let presentationTime = builtIn.drawable.frameTiming.presentationTime.timeInterval",
    "trackedDeviceAnchor(at: presentationTime)",
    "makeRequest(",
    "tickGame(request: requestContext.request)",
], in: presenter),
      "the request uses actual drawables and their presentation-time tracked pose")
check(presenter.contains("drawable.computeProjection(convention: .rightUpBack, viewIndex: $0)")
        && presenter.contains("deviceFromEyes: views.map(\\.transform)")
        && presenter.contains("Float(viewport.width / viewport.height)")
        && presenter.contains("binocularFrustumMatrixForDrawableTarget("),
      "two view projections, transforms, aspects, and a binocular frustum come from CompositorServices")
check(contract.contains("eyeFromOrigin\n                * entryOriginFromGameCameraMeters")
        && contract.contains("binocularCullClipFromDevice\n            * deviceFromOrigin * entryOriginFromGameCameraMeters")
        && presenter.contains("entryOriginFromGameCameraMeters = originFromDevice"),
      "one entry recenter produces per-eye third-person transforms and shared conservative culling")
check(plan.contains("SIMD4<Float>(repeating: 0.02)")
        && plan.contains("let far = max(defaultRange.x * 4, 500)")
        && plan.contains("let near = max(min(defaultRange.y * 0.5, 0.05), 0.005)"),
      "binocular culling has bounded positive tangent and depth padding")

print("Frame identity and lifecycle")
check(contract.contains("func isOpticallyCompatible(with other: Self")
        && contract.contains("relativeEyeCalibration")
        && !contract.contains("originFromDevice, other.originFromDevice"),
      "frame reuse ignores common head pose but compares optics and relative eye calibration")
check(presenter.contains("private var latestRequestPose: RetainedPose?")
        && presenter.contains("private var latestRenderedPose: RetainedPose?")
        && presenter.contains("retainedPose(for: gameFrame.request.poseIdentity)")
        && presenter.contains("drawable.deviceAnchor = renderAnchor"),
      "only current-request and latest-rendered anchors bind cached pixels to their render pose")
check(presenter.contains("case .paused:\n                reportSceneActive(false)")
        && presenter.contains("case .running:\n                reportSceneActive(true)")
        && presenter.contains("setImmersiveSceneActive(\n                    active, attempt: attempt)"),
      "layer paused/running transitions notify the coordinator without a per-frame callback")
check(presenter.contains("drawable.views.count == VisionImmersiveFrameRequest.viewCount")
        && presenter.contains("trackedDeviceAnchor(at: presentationTime)")
        && presenter.contains("fail(Self.unpresentableMapping)"),
      "unsupported view counts, mappings, and missing tracking fail back to the window")

print("Per-eye color and depth resolve")
check(presenter.contains("gameFrame.colorTextures[viewIndex]")
        && presenter.contains("gameFrame.depthTextures[viewIndex]")
        && !presenter.contains("gameFrame.colorTexture,"),
      "each compositor view binds only its corresponding native eye color and depth")
check(contract.contains("depth.pixelFormat == .depth32Float_stencil8")
        && contract.contains("depth.usage.contains(.shaderRead)")
        && shader.contains("depth2d<float> game_depth [[texture(1)]]")
        && shader.contains("float depth [[depth(any)]]"),
      "native D32S8 is sampled directly and resolved as compositor physical depth")
check(shader.contains("game_color.sample(color_sampler, in.uv).rgb * uniforms.fade")
        && shader.contains("vision_immersive_srgb_to_linear(encoded)")
        && shader.contains("max(native_depth, 1.0f / 1048576.0f)")
        && shader.contains("Exact reverse-Z zero is a valid far-sky value")
        && shader.contains("behavior at the boundary of opaque\n  // compositor reprojection is not established"),
      "the resolve preserves encoded fade/color and describes the zero-depth nudge conservatively")
check(!presenter.contains("VisionImmersiveFullViewport")
        && !presenter.contains("gameFrame.aspectRatio")
        && !presenter.contains("fixedShear")
        && !presenter.contains("screenPose"),
      "gameplay has no monoscopic image, fixed shear, or world-screen placement path")

print("Native menu plane")
let perEyeResolve = section(presenter, from: "if let gameFrame {\n                encoder.setRenderPipelineState(pipelineState)",
                            to: "} else if let menuFrame {")
let menuResolve = section(presenter, from: "} else if let menuFrame {",
                          to: "encoder.endEncoding()")
check(perEyeResolve.contains("clipFromQuad: VisionImmersiveResolve.clipFromQuad")
        && perEyeResolve.contains("gameFrame.depthTextures[viewIndex]")
        && !perEyeResolve.contains("menu"),
      "gameplay frames still resolve native per-eye color and depth across each whole view")
check(menuResolve.contains("encoder.setRenderPipelineState(menuPipelineState)")
        && menuResolve.contains("clipFromQuad: menuClipFromQuads[viewIndex]")
        && menuResolve.contains("encoder.setFragmentTexture(menuFrame.colorTexture, index: 0)")
        && !menuResolve.contains("setFragmentTexture(menuFrame.depthTexture"),
      "a menu frame draws the conventional image on a projected plane with its own raster depth")
check(occursInOrder([
    "var menuClipFromQuads: [simd_float4x4] = []",
    "VisionImmersiveMenuPlane.size(",
    "aspectRatio: menuFrame.aspectRatio)",
    "for viewIndex in views.indices {",
    "VisionImmersiveMenuPlane.clipFromQuad(",
    "originFromDevice: renderAnchor.originFromAnchorTransform",
    "deviceFromEye: views[viewIndex].transform",
    "clipFromEye: drawable.computeProjection(",
    "convention: .rightUpBack, viewIndex: viewIndex)",
    "for pass in prepared.passes {",
], in: presenter),
      "each view's plane transform uses that drawable's actual optics before any encoder opens")
check(occursInOrder([
    "case .menuPlane(let menuFrame):",
    "menuFrame.isPresentable(on: layerRenderer.device)",
    "menuFrame.renderSerial < latestRenderedSerial",
    "if menuOriginFromPlane == nil {",
    "VisionImmersiveMenuPlane.originFromPlane(",
    "originFromDevice: anchor.originFromAnchorTransform)",
    "renderAnchor = anchor",
], in: presenter)
        && occursInOrder(["case .perEye(let gameFrame):", "menuOriginFromPlane = nil",
                          "case .menuPlane(let menuFrame):"], in: presenter),
      "the plane is placed once per menu with the same-frame tracked pose and released by gameplay")
check(shader.contains("fragment float4 vision_immersive_menu_plane_fragment(")
        && section(shader, from: "vision_immersive_menu_plane_fragment(", to: "#endif")
            .contains("vision_immersive_srgb_to_linear(encoded)")
        && !section(shader, from: "vision_immersive_menu_plane_fragment(", to: "#endif")
            .contains("[[depth(any)]]"),
      "the menu fragment preserves fade and encoding and leaves rasterized plane depth intact")

print("Bounded GPU evidence and readiness")
check(shader.contains("kernel void vision_immersive_sample_2d(")
        && shader.contains("kernel void vision_immersive_sample_2d_array(")
        && shader.contains("depth2d<float, access::sample> depth")
        && shader.contains("depth2d_array<float, access::sample> depth"),
      "explicit 2D and 2D-array kernels sample native or compositor depth directly")
check(evidence.contains("static let sampleGridSize = 8")
        && evidence.contains("options: .storageModeShared")
        && evidence.contains("nonBlackThreshold: Float = 1.0 / 1_024.0")
        && evidence.contains("nativeRenderSerial: UInt64")
        && evidence.contains("poseIdentity: UInt64")
        && evidence.contains("compositorFrameIndex: UInt64")
        && evidence.contains("let fade: Float"),
      "bounded shared-buffer aggregates record color, depth, fade, and frame identities")
check(evidence.contains("maximumInFlight = 2")
        && evidence.contains("maximumScheduled = 256")
        && evidence.contains("advancingFrameCount = 3")
        && evidence.contains("timedOutWaitingForVisibleFrame")
        && evidence.contains("timedOutCollectingAdvancingFrames")
        && evidence.contains("immersive-render-evidence.json"),
      "sampling is bounded through three advancing frames or timeout and writes aggregate-only evidence")
check(occursInOrder([
    "encoder.endEncoding()",
    "evidenceSampler.encodeIfNeeded(",
], in: presenter)
        && occursInOrder([
            "guard let encoded = encode(",
            "prepared.drawable.encodePresent(commandBuffer: commandBuffer)",
        ], in: presenter),
      "source and resolved grids are sampled after resolve and before compositor presentation")
check(presenter.contains("let evidence = evidenceSampler.complete(evidenceTicket)")
        && presenter.contains("if evidence.becameVisible,")
        && !presenter.contains("let presentedGameFrame ="),
      "readiness requires completed-GPU nonblack evidence from both resolved eyes")
check(presenter.contains("Immersive render evidence could not start:")
        && presenter.contains("Immersive render evidence sampling failed:"),
      "diagnostic pipeline startup or encoding failure returns a named presenter error")
check(!presenter.contains("makeTextureView") && !evidence.contains("makeTextureView"),
      "the evidence path directly samples D32S8 without an unsupported texture view")

if failures == 0 {
    print("visionOS per-eye integration checks passed")
} else {
    print("visionOS per-eye integration checks failed: \(failures)")
    exit(1)
}
