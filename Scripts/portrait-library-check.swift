import Foundation

private func source(at path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

private func declaration(in source: String, startingWith start: String, endingWith end: String) throws -> String {
    guard let lower = source.range(of: start),
          let upper = source.range(of: end, range: lower.upperBound..<source.endIndex)
    else {
        throw CocoaError(.fileReadCorruptFile)
    }
    return String(source[lower.lowerBound..<upper.lowerBound])
}

private func run(_ executable: String, arguments: [String]) throws -> String {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = output
    try process.run()
    process.waitUntilExit()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let text = String(decoding: data, as: UTF8.self)
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "portrait-library-check", code: Int(process.terminationStatus),
                      userInfo: [NSLocalizedDescriptionKey: text])
    }
    return text
}

guard CommandLine.arguments.count == 2 else {
    print("usage: swift Scripts/portrait-library-check.swift <repository-root>")
    Foundation.exit(2)
}

do {
    let root = CommandLine.arguments[1]
    let content = try source(at: root + "/GOALPad/ContentView.swift")
    let library = try source(at: root + "/GOALPad/Library/GameLibrary.swift")
    let libraryView = try source(at: root + "/GOALPad/Library/GameLibraryView.swift")
    let layout = try declaration(in: content,
                                 startingWith: "nonisolated enum GameplaySurfaceLayout",
                                 endingWith: "\n\nstruct ContentView")
    let gameplaySurface = try declaration(in: content,
                                          startingWith: "private struct GameplaySurface",
                                          endingWith: "\n\n/// The game's own startup")
    let titles = try declaration(in: library,
                                 startingWith: "nonisolated enum GameLibraryTitle",
                                 endingWith: "\n\nnonisolated enum GameLibraryState")
    guard !titles.contains("jakX"), !titles.contains("Jak X") else {
        throw NSError(domain: "portrait-library-check", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Jak X remains in GameLibraryTitle"])
    }
    let tile = try declaration(in: libraryView,
                               startingWith: "private struct GameLibraryTile",
                               endingWith: "\n\nprivate struct FallbackGameArtwork")
    guard tile.contains("Button(action: activate)")
            && tile.contains(".disabled(state == .planned)")
            && !tile.contains(".accessibilityElement(children: .combine)")
            && tile.contains(".frame(minWidth: 44, minHeight: 44)")
            && tile.contains(".contentShape(Rectangle())")
    else {
        throw NSError(domain: "portrait-library-check", code: 2,
                      userInfo: [NSLocalizedDescriptionKey:
                        "library tile or artwork menu lost its semantic touch target"])
    }
    print("  ok   library tile and artwork menu remain independent semantic touch targets")
    guard gameplaySurface.contains("if frame.origin == .zero, frame.size == proxy.size"),
          let fullSurfaceBranch = gameplaySurface.range(of: "if frame.origin == .zero, frame.size == proxy.size"),
          let portraitBranch = gameplaySurface.range(of: "} else {", range: fullSurfaceBranch.upperBound..<gameplaySurface.endIndex),
          !gameplaySurface[fullSurfaceBranch.upperBound..<portraitBranch.lowerBound].contains(".frame(width:")
    else {
        throw NSError(domain: "portrait-library-check", code: 3,
                      userInfo: [NSLocalizedDescriptionKey:
                        "landscape no longer preserves the unconstrained edge-to-edge surface"])
    }
    print("  ok   landscape preserves the unconstrained edge-to-edge renderer surface")
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "goalpad-portrait-library-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let program = """
    import Foundation
    import CoreGraphics

    \(layout)

    \(titles)

    func check(_ condition: Bool, _ message: String) {
        if !condition {
            fatalError("FAIL \\(message)")
        }
        print("  ok   \\(message)")
    }

    func approximatelyEqual(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) < 0.001
    }

    func checkPortrait(_ size: CGSize,
                       _ insets: GameplaySurfaceLayout.SafeAreaInsets,
                       _ name: String) {
        let frame = GameplaySurfaceLayout.frame(in: size, safeAreaInsets: insets)
        check(approximatelyEqual(frame.minX, insets.leading)
              && approximatelyEqual(frame.minY, insets.top),
              "\\(name) starts at the safe-content top")
        check(frame.maxX <= size.width - insets.trailing + 0.001
              && frame.maxY <= size.height - insets.bottom + 0.001,
              "\\(name) stays inside safe-content bounds")
        check(approximatelyEqual(frame.height, frame.width * 3 / 4),
              "\\(name) keeps the renderer's Classic 4:3 host aspect")
    }

    let iphone = GameplaySurfaceLayout.frame(
        in: CGSize(width: 393, height: 852),
        safeAreaInsets: .init(top: 59, leading: 0, bottom: 34, trailing: 0)
    )
    check(approximatelyEqual(iphone.minY, 59), "portrait iPhone renderer is top-aligned")
    check(approximatelyEqual(iphone.height, 294.75), "portrait iPhone leaves remaining space below")
    checkPortrait(CGSize(width: 393, height: 852), .init(top: 59, leading: 0, bottom: 34, trailing: 0), "portrait iPhone")
    checkPortrait(CGSize(width: 834, height: 1194), .init(top: 24, leading: 0, bottom: 20, trailing: 0), "portrait iPad")

    let landscape = GameplaySurfaceLayout.frame(
        in: CGSize(width: 1194, height: 834),
        safeAreaInsets: .init(top: 0, leading: 24, bottom: 21, trailing: 24)
    )
    check(landscape == CGRect(x: 0, y: 0, width: 1194, height: 834),
          "landscape keeps the full existing renderer surface")

    check(GameLibraryTitle.allCases == [.jak1, .jak2, .jak3],
          "the deterministic launcher catalog contains only Jak 1, Jak II, and Jak 3")
    print("portrait and library checks passed")
    """

    let sourceURL = directory.appending(path: "portrait-library-check.swift", directoryHint: .notDirectory)
    let executableURL = directory.appending(path: "portrait-library-check", directoryHint: .notDirectory)
    let moduleCacheURL = directory.appending(path: "module-cache", directoryHint: .isDirectory)
    try program.write(to: sourceURL, atomically: true, encoding: .utf8)
    try FileManager.default.createDirectory(at: moduleCacheURL, withIntermediateDirectories: true)
    let sdk = try run("/usr/bin/xcrun", arguments: ["--sdk", "macosx", "--show-sdk-path"])
        .trimmingCharacters(in: .whitespacesAndNewlines)
    _ = try run("/usr/bin/xcrun", arguments: ["swiftc", "-sdk", sdk,
                                                  "-module-cache-path", moduleCacheURL.path,
                                                  sourceURL.path, "-o", executableURL.path])
    print(try run(executableURL.path, arguments: []), terminator: "")
} catch {
    print("portrait and library checks failed: \(error.localizedDescription)")
    Foundation.exit(1)
}
