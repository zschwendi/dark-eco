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
    let supportViews = try source(at: root + "/GOALPad/Support/EcoSupportViews.swift")
    let gameplayLayout = try declaration(in: content,
                                         startingWith: "nonisolated enum GameplaySurfaceLayout",
                                         endingWith: "\n\nprivate enum SettingsSheetEntry")
    let gameplaySurface = try declaration(in: content,
                                          startingWith: "private struct GameplaySurface",
                                          endingWith: "\n\n/// The game's own startup")
    let settingsSheet = try declaration(in: content,
                                        startingWith: "private struct SettingsSheetView",
                                        endingWith: "\n\nprivate struct SettingsTitleListView")
    let shelfLayout = try declaration(in: library,
                                      startingWith: "nonisolated struct GameLibraryShelfLayout",
                                      endingWith: "\n\nnonisolated enum GameLibraryTitle")
    let titles = try declaration(in: library,
                                 startingWith: "nonisolated enum GameLibraryTitle",
                                 endingWith: "\n\nnonisolated enum GameLibraryState")
    let libraryState = try declaration(in: library,
                                       startingWith: "nonisolated enum GameLibraryState",
                                       endingWith: "\n\nnonisolated enum GameLibraryCardAction")
    let cardAction = try declaration(in: library,
                                     startingWith: "nonisolated enum GameLibraryCardAction",
                                     endingWith: "\n\nnonisolated enum GameLibraryOfferCopy")
    let offerCopy = try declaration(in: library,
                                    startingWith: "nonisolated enum GameLibraryOfferCopy",
                                    endingWith: "\n\nnonisolated enum GameArtworkStorage")
    guard !titles.contains("jakX"), !titles.contains("Jak X") else {
        throw NSError(domain: "portrait-library-check", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Jak X remains in GameLibraryTitle"])
    }
    let tile = try declaration(in: libraryView,
                               startingWith: "private struct GameLibraryTile",
                               endingWith: "\n\nprivate struct FallbackGameArtwork")
    let libraryScreen = try declaration(in: libraryView,
                                        startingWith: "struct GameLibraryView",
                                        endingWith: "\n\nprivate struct GameLibraryTile")
    let about = try declaration(in: supportViews,
                                startingWith: "struct EcoAboutView",
                                endingWith: "\n\nprivate struct EcoContactView")
    guard let cardButton = tile.range(of: "Button(action: activate)"),
          let cardButtonStyle = tile.range(of: ".buttonStyle(.plain)",
                                           range: cardButton.upperBound..<tile.endIndex)
    else {
        throw NSError(domain: "portrait-library-check", code: 2,
                      userInfo: [NSLocalizedDescriptionKey:
                        "library tile lost its semantic launch button"])
    }
    let cardLabel = tile[cardButton.lowerBound..<cardButtonStyle.lowerBound]
    guard cardLabel.contains(".padding(GameLibraryShelfLayout.cardHorizontalInset)")
            && cardLabel.contains(".frame(width: coverSize.width")
            && cardLabel.contains(".background(DarkEcoTheme.surface")
            && cardLabel.contains(".contentShape(RoundedRectangle")
            && !cardLabel.contains("artworkMenu")
            && !tile.contains(".disabled(state == .planned)")
            && tile.contains(".opacity(state == .planned ? 0.48 : 1)")
            && tile.contains("private func activate() {\n        open()")
            && tile.contains(".scaledToFit()")
            && !tile.contains(".scaledToFill()")
            && tile.contains(".frame(width: coverSize.width, height: coverSize.height)")
            && tile.contains("Text(title.shelfName)")
            && tile.contains(".lineLimit(coverSize.width < 120 ? 4 : 2)")
            && tile.contains(".minimumScaleFactor(0.78)")
            && tile.contains(".allowsTightening(true)")
            && !tile.contains(".accessibilityElement(children: .combine)")
            && tile.contains(".frame(minWidth: 44, minHeight: 44)")
            && tile.contains(".contentShape(Rectangle())")
            && tile[cardButtonStyle.upperBound...].contains("artworkMenu")
    else {
        throw NSError(domain: "portrait-library-check", code: 2,
                      userInfo: [NSLocalizedDescriptionKey:
                        "full-card launch target or independent artwork menu regressed"])
    }
    print("  ok   ready and unavailable cards remain full semantic targets beside artwork options")
    guard let settingsMenuLabel = libraryScreen.range(
              of: "Label(\"Settings\", systemImage: \"gearshape\")"),
          let aboutMenuLabel = libraryScreen.range(
              of: "Label(\"About\", systemImage: \"info.circle\")"),
          settingsMenuLabel.lowerBound < aboutMenuLabel.lowerBound,
          libraryScreen.contains("GeometryReader { proxy in")
            && libraryScreen.contains("usesRegularWidth: (horizontalSizeClass ?? .regular) == .regular")
            && libraryScreen.contains("HStack(alignment: .top, spacing: layout.spacing)")
            && libraryScreen.contains("if layout.usesFlexibleGutters")
            && libraryScreen.contains("Spacer(minLength: layout.gutter)")
            && !libraryScreen.contains("LazyVGrid")
            && !libraryScreen.contains("GridItem")
            && !libraryScreen.contains("Import Game")
            && !libraryScreen.contains("ToolbarItem(placement: .primaryAction)")
            && libraryScreen.contains("EcoAboutView(tipStore: tipStore)")
            && libraryScreen.contains(".tint(DarkEcoTheme.accent)")
            && about.contains("SupportPage(title: \"About\")")
            && supportViews.contains(".tint(DarkEcoTheme.accent)")
            && about.contains("Eco is built on the open-source OpenGOAL project")
            && about.contains("SupportRow(title: \"Contact\"")
            && about.contains("SupportRow(title: \"Donate\"")
            && about.contains("Button(\"Done\")")
            && settingsSheet.contains(".tint(DarkEcoTheme.accent)")
            && settingsSheet.contains(".background(DarkEcoTheme.background)")
    else {
        throw NSError(domain: "portrait-library-check", code: 3,
                      userInfo: [NSLocalizedDescriptionKey:
                        "launcher shelf, adaptive gutters, menu ordering, or About destination regressed"])
    }
    print("  ok   launcher menu is Settings then a unified About destination")
    guard libraryScreen.contains("if session.startupPhase.isPreparing")
            && libraryScreen.contains("return .preparing(nil)")
            && libraryScreen.contains(".onChange(of: session.startupError, initial: true)")
            && libraryScreen.contains("title: Text(\"Couldn't Start Game\")")
            && libraryScreen.contains("action: session.clearStartupError")
    else {
        throw NSError(domain: "portrait-library-check", code: 3,
                      userInfo: [NSLocalizedDescriptionKey:
                        "launcher startup progress or visible failure reporting regressed"])
    }
    print("  ok   launcher exposes startup preparation and failures")
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

    \(gameplayLayout)

    \(shelfLayout)

    \(titles)

    \(libraryState)

    \(cardAction)

    \(offerCopy)

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

    func checkShelf(_ size: CGSize, usesRegularWidth: Bool, _ name: String) {
        let shelf = GameLibraryShelfLayout(containerSize: size, usesRegularWidth: usesRegularWidth)
        check(shelf.coverSize.width > 0 && shelf.coverSize.height > 0,
              "\\(name) produces a visible cover frame")
        check(approximatelyEqual(shelf.coverSize.width / shelf.coverSize.height,
                                 GameLibraryShelfLayout.coverAspectRatio),
              "\\(name) preserves the portrait cover aspect")
        check(shelf.shelfWidth + shelf.outerPadding * 2 <= size.width + 0.001,
              "\\(name) fits all three covers across without scrolling")
        let verticalPadding = shelf.usesFlexibleGutters
            ? GameLibraryShelfLayout.regularVerticalPadding
            : shelf.outerPadding
        check(shelf.shelfHeight + verticalPadding * 2 <= size.height + 0.001,
              "\\(name) fits every complete cover vertically")
    }

    func checkCompactShelf(_ size: CGSize, _ name: String) {
        let shelf = GameLibraryShelfLayout(containerSize: size, usesRegularWidth: false)
        let widthBound = (size.width - GameLibraryShelfLayout.compactOuterPadding * 2
            - GameLibraryShelfLayout.compactSpacing
                * CGFloat(GameLibraryShelfLayout.titleCount - 1)
            - GameLibraryShelfLayout.cardHorizontalInset * 2
                * CGFloat(GameLibraryShelfLayout.titleCount))
            / CGFloat(GameLibraryShelfLayout.titleCount)
        check(!shelf.usesFlexibleGutters,
              "\\(name) preserves the compact shelf behavior")
        check(approximatelyEqual(shelf.coverSize.width, widthBound),
              "\\(name) preserves its existing compact cover geometry")
        check(shelf.coverSize.width <= GameLibraryShelfLayout.maximumCoverWidth,
              "\\(name) keeps the compact cover cap")
    }

    func checkRegularShelf(_ size: CGSize, _ name: String) {
        let shelf = GameLibraryShelfLayout(containerSize: size, usesRegularWidth: true)
        check(shelf.usesFlexibleGutters,
              "\\(name) uses flexible gutters around every cover")
        check(approximatelyEqual(shelf.shelfWidth, size.width),
              "\\(name) expands the shelf across the available width")
        let availableGutter = (shelf.shelfWidth
            - shelf.cardWidth * CGFloat(GameLibraryShelfLayout.titleCount))
            / CGFloat(GameLibraryShelfLayout.titleCount + 1)
        check(availableGutter >= shelf.gutter - 0.001,
              "\\(name) leaves a flexible gutter on both sides of every cover")
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

    checkShelf(CGSize(width: 320, height: 440), usesRegularWidth: false, "compact portrait iPhone")
    checkShelf(CGSize(width: 393, height: 700), usesRegularWidth: false, "modern portrait iPhone")
    checkShelf(CGSize(width: 852, height: 280), usesRegularWidth: false, "landscape iPhone")
    checkShelf(CGSize(width: 834, height: 1_000), usesRegularWidth: true, "portrait iPad")
    checkShelf(CGSize(width: 1_194, height: 650), usesRegularWidth: true, "landscape iPad")
    checkCompactShelf(CGSize(width: 393, height: 700), "modern portrait iPhone")
    checkRegularShelf(CGSize(width: 834, height: 1_000), "portrait iPad")
    checkRegularShelf(CGSize(width: 1_194, height: 650), "landscape iPad")
    check(GameLibraryShelfLayout(containerSize: CGSize(width: 834, height: 1_000), usesRegularWidth: true)
            .coverSize.width > GameLibraryShelfLayout.maximumCoverWidth,
          "portrait iPad covers grow beyond the compact phone cap")
    check(GameLibraryShelfLayout(containerSize: CGSize(width: 1_194, height: 650), usesRegularWidth: true)
            .coverSize.width > GameLibraryShelfLayout.maximumCoverWidth,
          "landscape iPad covers grow beyond the compact phone cap")

    check(GameLibraryTitle.allCases == [.jak1, .jak2, .jak3],
          "the deterministic launcher catalog contains only Jak 1, Jak II, and Jak 3")
    check(GameLibraryTitle.jak1.shelfName == "Jak and Daxter: The Precursor Legacy"
          && GameLibraryTitle.jak1.shelfName == GameLibraryTitle.jak1.name,
          "the first game uses its full canonical title instead of numbered shorthand")
    check(GameLibraryCardAction.resolve(title: .jak1, state: .ready) == .start,
          "installed Jak 1 starts from its full card")
    check(GameLibraryCardAction.resolve(title: .jak1, state: .preparing(nil))
          == .openJak1Setup,
          "an active Jak 1 import reopens its existing progress flow")
    check(GameLibraryCardAction.resolve(title: .jak1, state: .notImported)
          == .offerJak1Import,
          "missing Jak 1 data presents the supported import offer")
    check(GameLibraryCardAction.resolve(title: .jak2, state: .ready)
          == .showUnsupported(.jak2)
          && GameLibraryCardAction.resolve(title: .jak3, state: .planned)
          == .showUnsupported(.jak3),
          "Jak II and Jak 3 fail closed even if a future state is misclassified")

    let rawOffer = GameLibraryOfferCopy.jak1ImportMessage(canImportRawISO: true)
    let preparedOffer = GameLibraryOfferCopy.jak1ImportMessage(canImportRawISO: false)
    check(rawOffer.contains("legally own") && rawOffer.contains(".iso")
          && rawOffer.contains(".zip") && rawOffer.contains("exactly one .iso"),
          "Jak 1 raw-source offer states ownership and exact accepted formats")
    check(preparedOffer.contains("legally own") && preparedOffer.contains("out/jak1")
          && !preparedOffer.contains(".zip") && !preparedOffer.contains("supported .iso"),
          "prepared-only Jak 1 offer does not advertise unavailable importers")
    check(GameLibraryOfferCopy.unsupportedMessage(for: .jak2).contains("Jak II")
          && GameLibraryOfferCopy.unsupportedMessage(for: .jak3).contains("Jak 3"),
          "unsupported offers remain title-specific")
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
