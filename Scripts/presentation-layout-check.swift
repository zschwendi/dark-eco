import Foundation

// Deterministic Fit to Screen full-display geometry and iOS surface-framing checks.

func source(at path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

func declaration(in text: String, startingWith start: String,
                 endingWith end: String) throws -> String {
    guard let lower = text.range(of: start),
          let upper = text.range(of: end, range: lower.lowerBound..<text.endIndex) else {
        throw NSError(domain: "presentation-layout-check", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "missing \(start)"])
    }
    return String(text[lower.lowerBound..<upper.lowerBound])
}

func require(_ condition: Bool, _ message: String) throws {
    guard condition else {
        throw NSError(domain: "presentation-layout-check", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: message])
    }
    print("  ok   \(message)")
}

guard CommandLine.arguments.count == 2 else {
    print("usage: swift Scripts/presentation-layout-check.swift <repository-root>")
    Foundation.exit(2)
}

do {
    let root = CommandLine.arguments[1]
    let content = try source(at: root + "/GOALPad/ContentView.swift")
    let surfaceView = try source(at: root + "/GOALPad/Game/GameSurfaceView.swift")
    let layout = try declaration(in: content,
                                 startingWith: "nonisolated enum GameplaySurfaceLayout",
                                 endingWith: "\n\nprivate struct SettingsSheetPresentation")
    let gameplaySurface = try declaration(in: content,
                                          startingWith: "private struct GameplaySurface",
                                          endingWith: "\n\n/// The game's own startup")

    guard let iOSPath = gameplaySurface.range(of: "#if os(iOS)\n        GeometryReader"),
          let otherPath = gameplaySurface.range(of: "#else\n        GeometryReader") else {
        throw NSError(domain: "presentation-layout-check", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "missing iOS/other surface paths"])
    }
    let iOSSurface = gameplaySurface[iOSPath.upperBound..<otherPath.lowerBound]
    try require(!iOSSurface.contains("if frame.origin == .zero") && !iOSSurface.contains(".id(")
                    && !iOSSurface.contains("ignoresSafeArea")
                    && iOSSurface.contains("displaySize(safeSize: proxy.size")
                    && iOSSurface.contains("safeLocalRect("),
                "iOS game surface keeps one identity and measures the safe area")
    try require(iOSSurface.contains("framedGameSurface(ignoring: Self.surfaceIgnoresSafeAreaEdges(")
                    && gameplaySurface.contains("frame.size == displaySize ? .all : []")
                    && gameplaySurface.contains("ignoresSafeAreaEdges: surfaceIgnoresSafeAreaEdges")
                    && surfaceView.contains("var ignoresSafeAreaEdges: Edge.Set = .all")
                    && surfaceView.contains(".ignoresSafeArea(.all, edges: ignoresSafeAreaEdges)"),
                "inset iOS frames stop the surface ignoring safe edges; other callers keep .all")
    try require(gameplaySurface[otherPath.upperBound...]
                    .contains("if frame.origin == .zero, frame.size == proxy.size"),
                "macOS and visionOS keep the original surface path")
    try require(gameplaySurface.contains("#if os(iOS)\n        // The surface has no touch handling")
                    && gameplaySurface.contains(".allowsHitTesting(false)"),
                "iOS game surface cannot take touches from the touch layer")
    try require(content.contains("fitToScreen: usesPortraitFitToScreen")
                    && content.contains("private var usesPortraitFitToScreen: Bool { false }"),
                "portrait Fit to Screen is iOS-only")
    try require(layout.contains("guard height > width, !fitToScreen else")
                    && !layout.contains("fittedWidth"),
                "Fit to Screen returns the full display rather than a capped 3:4 picture")
    try require(content.contains("@State private var isAutomaticLaptopPosture = false")
                    && content.contains("DuoPostureObserver(onChange: { isLaptop in isAutomaticLaptopPosture = isLaptop })")
                    && content.contains("session.isRunning && isAutomaticLaptopPosture")
                    && content.contains("private var usesAutomaticLaptopLayout: Bool { false }")
                    && !content.contains("AppStorage(\"deviceLaptopLayout")
                    && !content.contains("DevicePresentationPreferences")
                    && !content.contains("CoreMotion"),
                "laptop presentation is automatic, running-only, unpersisted and detector-owned")
    try require(content.contains(".onChange(of: usesEffectiveFitToScreen, initial: true)")
                    && content.contains("session.settings.horizontalPlusEnabled = enabled")
                    && !content.contains("presentationSettings.setGraphicsFillWidth")
                    && !content.contains("presentationSettings.graphicsFillWidth = "),
                "native Fit follows the effective policy without rewriting the saved setting")
    try require(gameplaySurface.contains("laptopLayout: laptopLayout")
                    && gameplaySurface.contains("if laptopLayout { return [.top, .horizontal] }"),
                "the laptop picture reaches top/side chrome on the same stable surface path")
    try require(content.contains(".contentShape(Rectangle())")
                    && content.contains("ignoresSafeAreaEdges: placement.ignoresSafeArea")
                    && content.contains("laptopLayout: usesAutomaticLaptopLayout)"),
                "one framed, clipped touch container uses the same laptop mode as the picture")
    try require(content.contains(".frame(width: frame.width, height: frame.height)\n"
                        + "                        // Inside the framed touch region")
                    && content.contains(".overlay(alignment: .topLeading) {")
                    && content.contains("#if !os(visionOS) && !os(iOS)\n                if session.isNativeMenuOpen"),
                "iOS diagnostics live in the framed touch region; root diagnostics are Mac-only")

    let directory = FileManager.default.temporaryDirectory
        .appending(path: "goalpad-presentation-layout-\(UUID().uuidString)",
                   directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let program = """
    import Foundation
    import CoreGraphics

    \(layout)

    func check(_ condition: Bool, _ message: String) {
        if !condition { fatalError("FAIL \\(message)") }
        print("  ok   \\(message)")
    }

    func near(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool { abs(lhs - rhs) < 0.001 }

    func inside(_ rect: CGRect, _ size: CGSize, _ insets: GameplaySurfaceLayout.SafeAreaInsets) -> Bool {
        rect.minX >= insets.leading - 0.001 && rect.minY >= insets.top - 0.001
            && rect.maxX <= size.width - insets.trailing + 0.001
            && rect.maxY <= size.height - insets.bottom + 0.001
    }

    let phone = CGSize(width: 393, height: 852)
    let phoneInsets = GameplaySurfaceLayout.SafeAreaInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
    let off = GameplaySurfaceLayout.frame(in: phone, safeAreaInsets: phoneInsets)
    check(off == CGRect(x: 0, y: 59, width: 393, height: 294.75),
          "portrait Fit to Screen off keeps the 4:3 top band")
    check(inside(off, phone, phoneInsets), "portrait Fit to Screen off stays inside the safe area")
    check(GameplaySurfaceLayout.frame(in: phone, safeAreaInsets: phoneInsets, fitToScreen: true)
            == CGRect(origin: .zero, size: phone),
          "phone portrait Fit to Screen fills the full display under system chrome")

    let tall = CGSize(width: 834, height: 1000)
    let tallInsets = GameplaySurfaceLayout.SafeAreaInsets(top: 24, leading: 10, bottom: 20, trailing: 10)
    check(GameplaySurfaceLayout.frame(in: tall, safeAreaInsets: tallInsets, fitToScreen: true)
            == CGRect(origin: .zero, size: tall),
          "near-square portrait Fit to Screen fills the full display")

    let landscape = CGSize(width: 1194, height: 834)
    let landscapeInsets = GameplaySurfaceLayout.SafeAreaInsets(top: 0, leading: 24, bottom: 21, trailing: 24)
    for fitToScreen in [false, true] {
        check(GameplaySurfaceLayout.frame(in: landscape, safeAreaInsets: landscapeInsets,
                                          fitToScreen: fitToScreen)
                == CGRect(origin: .zero, size: landscape),
              "landscape keeps the full surface (Fit to Screen \\(fitToScreen))")
    }

    // A safe-area-respecting reader measures 380x759 inside asymmetric insets.
    let asymmetric = GameplaySurfaceLayout.SafeAreaInsets(top: 47, leading: 11, bottom: 29, trailing: 5)
    let safeSize = CGSize(width: 380, height: 759)
    let display = GameplaySurfaceLayout.displaySize(safeSize: safeSize, safeAreaInsets: asymmetric)
    check(display == CGSize(width: 396, height: 835), "display size adds measured asymmetric insets")
    let displayFit = GameplaySurfaceLayout.frame(in: display, safeAreaInsets: asymmetric, fitToScreen: true)
    check(displayFit == CGRect(origin: .zero, size: display),
          "asymmetric portrait Fit to Screen fills the full display")
    let local = GameplaySurfaceLayout.safeLocalRect(displayFit, safeAreaInsets: asymmetric)
    check(near(local.minX, -11) && near(local.minY, -47)
            && near(local.maxX, safeSize.width + 5) && near(local.maxY, safeSize.height + 29),
          "safe-local portrait Fit to Screen extends past every safe edge to the full bounds")

    // A trailing sidebar inset in portrait: Fit to Screen still runs beneath it.
    let sidebar = GameplaySurfaceLayout.SafeAreaInsets(top: 24, leading: 0, bottom: 20, trailing: 320)
    let sidebarSafe = CGSize(width: 514, height: 1150)
    let sidebarDisplay = GameplaySurfaceLayout.displaySize(safeSize: sidebarSafe, safeAreaInsets: sidebar)
    let sidebarFit = GameplaySurfaceLayout.frame(in: sidebarDisplay, safeAreaInsets: sidebar,
                                                 fitToScreen: true)
    let sidebarLocal = GameplaySurfaceLayout.safeLocalRect(sidebarFit, safeAreaInsets: sidebar)
    check(sidebarFit == CGRect(origin: .zero, size: sidebarDisplay)
            && near(sidebarLocal.minY, -24) && near(sidebarLocal.maxX, sidebarSafe.width + 320)
            && near(sidebarLocal.maxY, sidebarSafe.height + 20),
          "portrait Fit to Screen extends beneath a trailing sidebar and the bottom inset")
    let sidebarOff = GameplaySurfaceLayout.frame(in: sidebarDisplay, safeAreaInsets: sidebar)
    check(sidebarOff == CGRect(x: 0, y: 24, width: 514, height: 385.5),
          "sidebar portrait Fit to Screen off keeps the safe 4:3 top band")
    let displayOff = GameplaySurfaceLayout.frame(in: display, safeAreaInsets: asymmetric)
    check(near(displayOff.width, 380) && near(displayOff.height, 285) && near(displayOff.minY, 47),
          "asymmetric Fit to Screen off keeps the 4:3 top band")
    let wide = GameplaySurfaceLayout.displaySize(safeSize: CGSize(width: 819, height: 372),
                                                 safeAreaInsets: .init(top: 0, leading: 47,
                                                                       bottom: 21, trailing: 0))
    let wideFrame = GameplaySurfaceLayout.frame(in: wide, safeAreaInsets: .init(top: 0, leading: 47,
                                                                                bottom: 21, trailing: 0),
                                                fitToScreen: true)
    check(wideFrame == CGRect(origin: .zero, size: wide)
            && GameplaySurfaceLayout.safeLocalRect(wideFrame, safeAreaInsets: .init(
                top: 0, leading: 47, bottom: 21, trailing: 0)).minX == -47,
          "measured landscape stays full-display and extends past the safe leading edge")
    let landscapeSidebar = GameplaySurfaceLayout.SafeAreaInsets(top: 24, leading: 0, bottom: 20, trailing: 320)
    let landscapeSafe = CGSize(width: 874, height: 790)
    let landscapeDisplay = GameplaySurfaceLayout.displaySize(safeSize: landscapeSafe,
                                                             safeAreaInsets: landscapeSidebar)
    for fitToScreen in [false, true] {
        let frame = GameplaySurfaceLayout.frame(in: landscapeDisplay, safeAreaInsets: landscapeSidebar,
                                                fitToScreen: fitToScreen)
        let local = GameplaySurfaceLayout.safeLocalRect(frame, safeAreaInsets: landscapeSidebar)
        check(frame == CGRect(origin: .zero, size: landscapeDisplay) && near(local.minY, -24)
                && near(local.maxX, landscapeSafe.width + 320)
                && near(local.maxY, landscapeSafe.height + 20),
              "landscape extends beneath a trailing sidebar (Fit to Screen \\(fitToScreen))")
    }

    check(!GameplaySurfaceLayout.effectiveFitToScreen(savedFitToScreen: false, automaticLaptopActive: false)
            && GameplaySurfaceLayout.effectiveFitToScreen(savedFitToScreen: false, automaticLaptopActive: true)
            && GameplaySurfaceLayout.effectiveFitToScreen(savedFitToScreen: true, automaticLaptopActive: false)
            && GameplaySurfaceLayout.effectiveFitToScreen(savedFitToScreen: true, automaticLaptopActive: true),
          "effective native Fit is saved Fit or the automatic laptop posture")

    // Laptop posture: the picture fills the entire upper half; controls stay in the safe lower half.
    let laptopSafe = CGSize(width: 380, height: 759)
    let laptopDisplay = GameplaySurfaceLayout.displaySize(safeSize: laptopSafe, safeAreaInsets: asymmetric)
    for fitToScreen in [false, true] {
        check(GameplaySurfaceLayout.frame(in: laptopDisplay, safeAreaInsets: asymmetric,
                                          fitToScreen: fitToScreen, laptopLayout: true)
                == CGRect(x: 0, y: 0, width: 396, height: 417.5),
              "laptop picture fills the full upper half without aspect fit (Fit to Screen \\(fitToScreen))")
    }
    let laptopPicture = GameplaySurfaceLayout.frame(in: laptopDisplay, safeAreaInsets: asymmetric,
                                                    laptopLayout: true)
    let laptopPictureLocal = GameplaySurfaceLayout.safeLocalRect(laptopPicture, safeAreaInsets: asymmetric)
    check(near(laptopPictureLocal.minX, -11) && near(laptopPictureLocal.minY, -47)
            && near(laptopPictureLocal.maxX, laptopSafe.width + 5),
          "safe-local laptop picture reaches beneath the top and side insets")
    let laptopControls = GameplaySurfaceLayout.touchControlsPlacement(
        in: laptopDisplay, safeAreaInsets: asymmetric, laptopLayout: true)
    check(laptopControls.frame == CGRect(x: 11, y: 417.5, width: 380, height: 388.5)
            && !laptopControls.ignoresSafeArea
            && laptopControls.safeAreaInsets == .init(top: 0, leading: 0, bottom: 0, trailing: 0),
          "laptop controls take the safe lower half with zero local insets")
    check(laptopControls.frame.minY >= laptopPicture.maxY
            && !laptopControls.frame.intersects(laptopPicture)
            && inside(laptopControls.frame, laptopDisplay, asymmetric),
          "laptop controls are disjoint from the picture and inside every lower safe edge")
    let laptopControlsLocal = GameplaySurfaceLayout.safeLocalRect(laptopControls.frame,
                                                                  safeAreaInsets: asymmetric)
    check(laptopControlsLocal == CGRect(x: 0, y: 370.5, width: 380, height: 388.5)
            && near(laptopControlsLocal.maxY, laptopSafe.height),
          "safe-local laptop controls end at the measured safe bottom")
    let ordinaryControls = GameplaySurfaceLayout.touchControlsPlacement(
        in: laptopDisplay, safeAreaInsets: asymmetric, laptopLayout: false)
    check(ordinaryControls == .init(frame: CGRect(origin: .zero, size: laptopDisplay),
                                    safeAreaInsets: nil, ignoresSafeArea: true),
          "ordinary controls keep the full-display safe-area-ignoring layer")
    """
    let programURL = directory.appending(path: "main.swift")
    try program.write(to: programURL, atomically: true, encoding: .utf8)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swift", programURL.path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { Foundation.exit(process.terminationStatus) }
    print("presentation layout check passed")
} catch {
    print("FAIL \(error.localizedDescription)")
    Foundation.exit(1)
}
