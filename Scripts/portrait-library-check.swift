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
    let launcherBackground = try source(at: root + "/GOALPad/UI/DarkEcoLauncherBackground.swift")
    let launcherShader = try source(at: root + "/GOALPad/UI/DarkEcoLauncherBackground.metal")
    let saveSettings = try source(at: root + "/GOALPad/Saves/SaveSyncController.swift")
    let supportViews = try source(at: root + "/GOALPad/Support/EcoSupportViews.swift")
    let gameplayLayout = try declaration(in: content,
                                         startingWith: "nonisolated enum GameplaySurfaceLayout",
                                         endingWith: "\n\nprivate struct SettingsSheetPresentation")
    let gameplaySurface = try declaration(in: content,
                                          startingWith: "private struct GameplaySurface",
                                          endingWith: "\n\n/// The game's own startup")
    let settingsSheet = try declaration(in: content,
                                        startingWith: "private struct SettingsSheetView",
                                        endingWith: "\n\nprivate struct GameplaySurface")
    let shelfLayout = try declaration(in: library,
                                      startingWith: "nonisolated struct GameLibraryShelfLayout",
                                      endingWith: "\n\n/// Gives compact landscape phones")
    let compactLandscapeLayout = try declaration(
        in: library,
        startingWith: "nonisolated struct GameLibraryCompactLandscapeLayout",
        endingWith: "\n\n/// A larger scrolling library for portrait compact-width phones.")
    let titles = try declaration(in: library,
                                 startingWith: "nonisolated enum GameLibraryTitle",
                                 endingWith: "\n\nnonisolated enum GameLibraryPresentation")
    let libraryPresentation = try declaration(
        in: library,
        startingWith: "nonisolated enum GameLibraryPresentation",
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
    let menuLabel = try declaration(in: libraryView,
                                    startingWith: "private struct DarkEcoMenuLabel",
                                    endingWith: "\n\nprivate struct GameLibraryTile")
    let about = try declaration(in: supportViews,
                                startingWith: "struct EcoAboutView",
                                endingWith: "\n\nprivate struct EcoContactView")
    let activationSurface = try declaration(
        in: tile,
        startingWith: "@ViewBuilder\n    private var activationSurface",
        endingWith: "\n\n    private var tileSurface")
    let tileSurface = try declaration(
        in: tile,
        startingWith: "private var tileSurface",
        endingWith: "\n\n    private var details")
    guard let visionBranchEnd = activationSurface.range(of: "#else"),
          let cardButton = activationSurface.range(of: "Button(action: activate)",
                                                   range: visionBranchEnd.upperBound..<activationSurface.endIndex),
          let cardButtonStyle = activationSurface.range(of: ".buttonStyle(.plain)",
                                                        range: cardButton.upperBound..<activationSurface.endIndex)
    else {
        throw NSError(domain: "portrait-library-check", code: 2,
                      userInfo: [NSLocalizedDescriptionKey:
                        "library tile lost its semantic launch button"])
    }
    let visionActivation = activationSurface[..<visionBranchEnd.lowerBound]
    guard tileSurface.contains(".padding(.horizontal, GameLibraryShelfLayout.cardHorizontalInset)")
            && tileSurface.contains(".padding(.top, GameLibraryShelfLayout.cardHorizontalInset)")
            && tileSurface.contains(".padding(.bottom, usesHorizontalCard")
            && tileSurface.contains(".frame(width: cardWidth ?? coverSize.width")
            && tileSurface.contains(".background(DarkEcoTheme.surface")
            && tileSurface.contains(".contentShape(RoundedRectangle")
            && !tileSurface.contains("artworkMenu")
            && !visionActivation.contains("Button(")
            && visionActivation.contains(".onTapGesture(perform: activate)")
            && visionActivation.contains(".accessibilityAddTraits(.isButton)")
            && visionActivation.contains(".accessibilityAction {")
            && activationSurface[cardButton.lowerBound..<cardButtonStyle.lowerBound].contains("tileSurface")
            && !tile.contains(".disabled(state == .planned)")
            && tile.contains(".opacity(state == .planned ? 0.48 : 1)")
            && tile.contains("private func activate() {\n        open()")
            && tile.contains(".scaledToFit()")
            && !tile.contains(".scaledToFill()")
            && tile.contains(".frame(width: coverSize.width, height: coverSize.height)")
            && tile.contains(".padding(.bottom, usesHorizontalCard")
            && tile.contains("GameLibraryShelfLayout.cardBottomInset")
            && tile.contains("Text(displayTitle)")
            && tile.contains(".accessibilityLabel(\"\\(displayTitle), \\(stateLabel)\")")
            && tile.contains(".accessibilityLabel(\"Artwork options for \\(displayTitle)\")")
            && !tile.contains("Text(title.shelfName)")
            && !tile.contains("\\(title.name), \\(stateLabel)")
            && !tile.contains("Artwork options for \\(title.name)")
            && tile.contains(".lineLimit(usesHorizontalCard ? 4 : (coverSize.width < 120 ? 4 : 2))")
            && tile.contains(".minimumScaleFactor(0.78)")
            && tile.contains(".allowsTightening(true)")
            && !tile.contains(".accessibilityElement(children: .combine)")
            && tile.contains(".frame(minWidth: 44, minHeight: 44)")
            && tile.contains(".contentShape([.interaction, .hoverEffect], Rectangle())")
            && tile.contains("activationSurface\n                .opacity")
            && tile.contains("\n\n            artworkMenu")
            && visionActivation.contains(".contentShape([.interaction, .hoverEffect]")
            && visionActivation.contains(".hoverEffect { effect, isActive, _ in")
            && visionActivation.contains("effect.scaleEffect(isActive ? 1.025 : 1)")
    else {
        throw NSError(domain: "portrait-library-check", code: 2,
                      userInfo: [NSLocalizedDescriptionKey:
                        "full-card launch target or independent artwork menu regressed"])
    }
    print("  ok   ready and unavailable cards retain rectangular hover targets beside artwork options")
    guard libraryScreen.contains("Label(\"Settings\", systemImage: \"gearshape\")")
            && !libraryScreen.contains("Label(\"About\", systemImage: \"info.circle\")")
            && !libraryScreen.contains("EcoAboutView(tipStore: tipStore)")
            && !libraryScreen.contains("versionFooter")
            && !libraryScreen.contains("GOALPadBuildIdentity.versionText")
            && libraryScreen.contains("GeometryReader { proxy in")
            && libraryScreen.contains("if isPortrait, horizontalSizeClass == .regular")
            && libraryScreen.contains("else if !isPortrait, isPhone || horizontalSizeClass == .compact")
            && libraryScreen.contains("fittedPortraitLibrary(containerSize: proxy.size)")
            && libraryScreen.contains("compactLandscapeLibrary(containerSize: proxy.size)")
            && libraryScreen.contains("wideLibrary(containerSize: proxy.size)")
            && libraryScreen.contains("VStack(alignment: .center, spacing: GameLibraryGridLayout.spacing)")
            && libraryScreen.contains(".frame(maxWidth: .infinity, alignment: .center)")
            && libraryScreen.contains("HStack(alignment: .top, spacing: layout.spacing)")
            && libraryScreen.contains("Spacer(minLength: layout.gutter)")
            && !libraryScreen.contains("LazyVGrid")
            && !libraryScreen.contains("GridItem")
            && !libraryScreen.contains("Import Game")
            && !libraryScreen.contains("ToolbarItem(placement: .primaryAction)")
            && libraryScreen.contains(".tint(DarkEcoTheme.accent)")
            && saveSettings.contains("EcoAboutView(tipStore: tipStore)")
            && saveSettings.contains("Label(\"About\", systemImage: \"info.circle\")")
            && saveSettings.contains("Text(GOALPadBuildIdentity.versionText)")
            && about.contains("SupportPage(title: \"About\")")
            && supportViews.contains(".tint(DarkEcoTheme.accent)")
            && about.contains("Dark Eco is an unofficial native runtime for OpenGOAL developed by Zach Schwendiman.")
            && about.contains("This app was built on the shoulders of the open-source OpenGOAL project and the work of its contributors.")
            && about.contains("Visit OpenGOAL project")
            && about.contains("SupportRow(title: \"Contact\"")
            && about.contains("SupportRow(title: \"Support Development\"")
            && about.contains("Button(\"Done\")")
            && settingsSheet.contains(".tint(DarkEcoTheme.accent)")
            && settingsSheet.contains(".background(DarkEcoTheme.background)")
    else {
        throw NSError(domain: "portrait-library-check", code: 3,
                      userInfo: [NSLocalizedDescriptionKey:
                        "launcher shelf, adaptive gutters, or Settings About destination regressed"])
    }
    print("  ok   launcher menu opens Settings, whose bottom rows own About and version")
    guard libraryScreen.contains("DarkEcoLauncherBackground()")
            && launcherBackground.contains("@Environment(\\.accessibilityReduceMotion)")
            && launcherBackground.contains("minimumInterval: 1.0 / 30.0")
            && launcherBackground.contains("paused: reduceMotion")
            && launcherBackground.contains("guard !reduceMotion else { return 0 }")
            && launcherBackground.contains(".allowsHitTesting(false)")
            && launcherBackground.contains(".accessibilityHidden(true)")
            && launcherShader.contains("[[ stitchable ]] half4 darkEcoLauncherBackground")
            && launcherShader.contains("float2 warped = domain")
            && launcherShader.contains("float wavyEnergy = max")
            && launcherShader.contains("float hotVein = smoothstep")
            && launcherShader.contains("float vatGradient = clamp")
            && launcherShader.contains("return half4(half3(color), sourceColor.a)")
    else {
        throw NSError(domain: "portrait-library-check", code: 3,
                      userInfo: [NSLocalizedDescriptionKey:
                        "Dark Eco liquid shader, accessibility fallback, or launcher wiring regressed"])
    }
    print("  ok   launcher uses a bounded noninteractive Dark Eco liquid shader with Reduce Motion support")
    guard libraryScreen.contains("ToolbarItem(placement: .principal)")
            && libraryScreen.contains("} label: { mainMenuLabel }")
            && libraryScreen.contains(".menuStyle(.button)")
            && libraryScreen.contains(".buttonStyle(.plain)")
            && libraryScreen.contains(".accessibilityLabel(\"Main menu\")")
            && !libraryScreen.contains("#if os(visionOS)\n            .overlay(alignment: .top)")
            && !libraryScreen.contains("private var menuPlacement")
            && menuLabel.contains("Text(\"Dark Eco\")")
            && menuLabel.contains("DarkEcoTheme.accent")
            && menuLabel.contains("@Environment(\\.accessibilityReduceMotion)")
            && menuLabel.contains("private let shimmerDuration: TimeInterval = 2.6")
            && menuLabel.contains("TimelineView(.animation)")
            && menuLabel.contains("wrapped / shimmerDuration * 4 - 2")
    else {
        throw NSError(domain: "portrait-library-check", code: 3,
                      userInfo: [NSLocalizedDescriptionKey:
                        "cross-platform Dark Eco toolbar menu or shimmer regressed"])
    }
    print("  ok   iPhone, iPad, and visionOS share one centered Dark Eco toolbar menu without a second system pill")
    guard libraryScreen.contains("GameLibraryCompactLandscapeLayout(containerSize: containerSize)")
            && libraryScreen.contains("if layout.usesHorizontalScroll")
            && libraryScreen.contains("ScrollView(.horizontal)")
            && libraryScreen.contains(".frame(width: layout.shelfWidth")
            && tile.contains("HStack(alignment: .center, spacing: 8) {\n                    artwork\n                    details")
            && tile.contains(".frame(maxWidth: .infinity, alignment: .leading)")
            && libraryView.contains("Text(title.fallbackMark)")
            && libraryScreen.contains("GameLibraryShelfLayout.regularPortraitMaximumCoverWidth")
            && !libraryView.contains(".stroke(DarkEcoTheme.accent.opacity(0.18), lineWidth: 2)")
            && !libraryView.contains(".fill(.black.opacity(0.38))")
            && !libraryView.contains("RoundedRectangle(cornerRadius: 30, style: .continuous)")
            && !libraryView.contains("Text(\"DARK ECO\")")
    else {
        throw NSError(domain: "portrait-library-check", code: 3,
                      userInfo: [NSLocalizedDescriptionKey:
                        "compact phone card geometry, artwork order, or placeholder copy regressed"])
    }
    print("  ok   compact portrait centers cards, landscape uses readable artwork-left cards, and placeholders keep only numerals")
    print("  ok   empty artwork drops its decorative spheres and inner outline while vertical cards use extra footer room and wider iPad portrait art")
    guard libraryScreen.contains("case .waitingForForegroundPreparation:")
            && libraryScreen.contains("return .preparing(.finishingSaveCheck)")
            && libraryScreen.contains("case .checkingSaves:")
            && libraryScreen.contains("return .preparing(.checkingSaves)")
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
    guard content.contains("#if os(iOS)\n                TouchControlsView")
            && !content.contains("#if os(visionOS)\n                TouchControlsView") else {
        throw NSError(domain: "portrait-library-check", code: 3,
                      userInfo: [NSLocalizedDescriptionKey:
                        "visionOS gained a gameplay touch-control overlay behind library cards"])
    }
    print("  ok   visionOS has no gameplay touch-control overlay behind library cards")
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "goalpad-portrait-library-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let program = """
    import Foundation
    import CoreGraphics

    \(gameplayLayout)

    \(shelfLayout)

    \(compactLandscapeLayout)

    \(titles)

    \(libraryPresentation)

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

    func checkCompactLandscape(_ size: CGSize, _ name: String) {
        let layout = GameLibraryCompactLandscapeLayout(containerSize: size)
        check(layout.cardWidth >= GameLibraryCompactLandscapeLayout.minimumCardWidth,
              "\\(name) keeps each card wide enough for readable details")
        check(layout.detailsWidth >= 140,
              "\\(name) reserves a readable details column beside artwork")
        check(layout.coverSize.width > 160,
              "\\(name) uses materially larger landscape artwork")
        check(layout.shelfWidth
                == layout.cardWidth * CGFloat(GameLibraryCompactLandscapeLayout.titleCount)
                    + GameLibraryCompactLandscapeLayout.spacing
                        * CGFloat(GameLibraryCompactLandscapeLayout.titleCount - 1),
              "\\(name) computes the complete three-card shelf width")
        let naturalCardWidth = (max(0, size.width
            - GameLibraryCompactLandscapeLayout.outerPadding * 2)
            - GameLibraryCompactLandscapeLayout.spacing
                * CGFloat(GameLibraryCompactLandscapeLayout.titleCount - 1))
            / CGFloat(GameLibraryCompactLandscapeLayout.titleCount)
        check(layout.usesHorizontalScroll
                == (naturalCardWidth < GameLibraryCompactLandscapeLayout.minimumCardWidth),
              "\\(name) scrolls only when three readable cards cannot fit")
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
    checkCompactLandscape(CGSize(width: 852, height: 390), "landscape iPhone")
    check(!GameLibraryCompactLandscapeLayout(containerSize: CGSize(width: 1_200, height: 390))
            .usesHorizontalScroll,
          "wide compact landscape fits three readable cards without scrolling")
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
    check(GameLibraryCardAction.resolve(title: .jak1, state: .preparing(.importing(nil)))
          == .openJak1Setup,
          "an active Jak 1 import reopens its existing progress flow")
    check(GameLibraryCardAction.resolve(
            title: .jak1, state: .preparing(.finishingSaveCheck)) == .start
          && GameLibraryCardAction.resolve(
            title: .jak1, state: .preparing(.checkingSaves)) == .start,
          "save preparation remains a coalesced Play request instead of opening import")
    check(GameLibraryCardAction.resolve(
            title: .jak1, state: .preparing(.checkingLocalData)) == .verifyJak1Data,
          "a tap during the local-data check retains verification instead of offering reimport")
    check(GameLibraryCardAction.resolve(title: .jak1, state: .notImported)
          == .verifyJak1Data,
          "apparently missing Jak 1 data is rechecked before the supported import offer")
    check(GameLibraryCardAction.resolve(title: .jak2, state: .ready)
          == .showUnsupported(.jak2)
          && GameLibraryCardAction.resolve(title: .jak3, state: .planned)
          == .showUnsupported(.jak3),
          "Jak II and Jak 3 fail closed even if a future state is misclassified")

    let emptyTitles = GameLibraryTitle.allCases.map {
        GameLibraryPresentation.displayTitle(for: $0, isValidatedAndLinked: false)
    }
    check(emptyTitles == ["Set Up Game Data", "Future Title", "Future Title"],
          "the empty Library uses only neutral shipping titles")
    check(GameLibraryPresentation.displayTitle(for: .jak1, isValidatedAndLinked: true)
            == GameLibraryTitle.jak1.name,
          "validated and linked game data reveals the canonical first title")
    check(GameLibraryPresentation.displayTitle(for: .jak2, isValidatedAndLinked: true)
            == "Future Title"
          && GameLibraryPresentation.displayTitle(for: .jak3, isValidatedAndLinked: true)
            == "Future Title",
          "planned titles remain neutral even if future state is misclassified")

    let offer = GameLibraryOfferCopy.jak1ImportMessage()
    check(offer == "Provide compatible game data from a copy you legally own.",
          "setup offer uses the generic ownership sentence")
    check(GameLibraryOfferCopy.unsupportedMessage(for: .jak2)
            == "Support for this future title is coming soon."
          && GameLibraryOfferCopy.unsupportedMessage(for: .jak3)
            == "Support for this future title is planned.",
          "unsupported offers remain truthful without revealing planned titles")
    check(GameLibraryTitle.jak2.availabilityLabel == "Coming Soon"
          && GameLibraryTitle.jak3.availabilityLabel == "Planned"
          && GameLibraryOfferCopy.unsupportedMessage(for: .jak2).contains("coming soon")
          && GameLibraryOfferCopy.unsupportedMessage(for: .jak3).contains("planned"),
          "follow-on title availability uses the same truthful copy everywhere")
    let emptyPresentationText = (emptyTitles + [
        "Not Imported",
        GameLibraryTitle.jak2.availabilityLabel,
        GameLibraryTitle.jak3.availabilityLabel,
        offer,
        GameLibraryOfferCopy.unsupportedMessage(for: .jak1),
        GameLibraryOfferCopy.unsupportedMessage(for: .jak2),
        GameLibraryOfferCopy.unsupportedMessage(for: .jak3),
    ]).joined(separator: " ")
    let prohibited = ["Jak", "Daxter", "Precursor", "Jak II", "Jak 3"]
    check(prohibited.allSatisfy { !emptyPresentationText.localizedCaseInsensitiveContains($0) },
          "empty Library titles, statuses, setup copy, and alerts contain no prohibited names")
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
