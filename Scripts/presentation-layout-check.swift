import Foundation

// Deterministic Fit to Screen portrait geometry and iOS surface-framing checks.

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
    let fit = GameplaySurfaceLayout.frame(in: phone, safeAreaInsets: phoneInsets, fitToScreen: true)
    check(near(fit.width * 4, fit.height * 3), "portrait Fit to Screen is exactly 3:4")
    check(near(fit.width, 393) && near(fit.minY, 59), "phone 3:4 uses the full safe width at the safe top")
    check(inside(fit, phone, phoneInsets), "phone 3:4 stays inside the safe area")

    let tall = CGSize(width: 834, height: 1000)
    let tallInsets = GameplaySurfaceLayout.SafeAreaInsets(top: 24, leading: 10, bottom: 20, trailing: 10)
    let tallFit = GameplaySurfaceLayout.frame(in: tall, safeAreaInsets: tallInsets, fitToScreen: true)
    check(near(tallFit.width * 4, tallFit.height * 3) && near(tallFit.height, 956),
          "near-square portrait fits the largest 3:4 by safe height")
    check(near(tallFit.midX, 417) && inside(tallFit, tall, tallInsets),
          "height-limited 3:4 is centred inside the safe area")

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
    check(near(displayFit.minX, 11) && near(displayFit.minY, 47)
            && near(displayFit.width, 380) && near(displayFit.height, 380 * 4 / 3),
          "asymmetric 3:4 starts at the safe origin with the full safe width")
    let local = GameplaySurfaceLayout.safeLocalRect(displayFit, safeAreaInsets: asymmetric)
    check(near(local.minX, 0) && near(local.minY, 0)
            && local.maxX <= safeSize.width + 0.001 && local.maxY <= safeSize.height + 0.001,
          "safe-local coordinates place the 3:4 picture inside the measured reader")
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
