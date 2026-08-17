import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

private enum GameLibraryAlert: Identifiable {
    case importGameData(GameLibraryTitle)
    case unsupported(GameLibraryTitle)
    case artwork(String)
    case startup(String)

    var id: String {
        switch self {
        case .importGameData(let title): "import-\(title.id)"
        case .unsupported(let title): "unsupported-\(title.id)"
        case .artwork: "artwork"
        case .startup: "startup"
        }
    }
}

struct GameLibraryView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Bindable var session: GameSession
    @Bindable var artworkStore: GameArtworkStore
    let openGameSetup: (GameLibraryTitle) -> Void
    let openSettings: () -> Void

    @State private var artworkTitle: GameLibraryTitle?
    @State private var isChoosingArtwork = false
    @State private var presentedAlert: GameLibraryAlert?

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let isPortrait = proxy.size.height > proxy.size.width
                if isPortrait, horizontalSizeClass == .regular {
                    fittedPortraitLibrary(containerSize: proxy.size)
                } else if !isPortrait, isPhone || horizontalSizeClass == .compact {
                    compactLandscapeLibrary(containerSize: proxy.size)
                } else if isPortrait {
                    scrollingLibrary(containerWidth: proxy.size.width)
                } else {
                    wideLibrary(containerSize: proxy.size)
                }
            }
            .background {
                DarkEcoLauncherBackground()
                    .ignoresSafeArea()
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Menu {
                        Button(action: openSettings) {
                            Label("Settings", systemImage: "gearshape")
                        }
                    } label: { mainMenuLabel }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Main menu")
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(DarkEcoTheme.accent)
        .fileImporter(
            isPresented: $isChoosingArtwork,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            guard let title = artworkTitle else { return }
            artworkTitle = nil
            if case .success(let urls) = result, let source = urls.first {
                Task { await artworkStore.importArtwork(from: source, for: title) }
            }
        }
        .onChange(of: artworkStore.errorMessage) { _, message in
            guard let message else { return }
            presentedAlert = .artwork(message)
            artworkStore.errorMessage = nil
        }
        .onChange(of: session.startupError, initial: true) { _, message in
            guard let message else { return }
            presentedAlert = .startup(message)
        }
        .alert(item: $presentedAlert) { alert in
            switch alert {
            case .importGameData(let title):
                Alert(
                    title: Text("Set Up Game Data"),
                    message: Text(GameLibraryOfferCopy.importMessage(
                        for: title,
                        canImportRawMedia: GameDataProfile.profile(for: title)?
                            .supportsRawMediaPreparation == true
                    )),
                    primaryButton: .default(
                        Text("Continue"),
                        action: { openGameSetup(title) }
                    ),
                    secondaryButton: .cancel()
                )
            case .unsupported(let title):
                Alert(
                    title: Text("Title Isn't Available Yet"),
                    message: Text(GameLibraryOfferCopy.unsupportedMessage(for: title)),
                    dismissButton: .default(Text("OK"))
                )
            case .artwork(let message):
                Alert(
                    title: Text("Artwork Could Not Be Changed"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            case .startup(let message):
                Alert(
                    title: Text("Couldn't Start Game"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"), action: session.clearStartupError)
                )
            }
        }
    }

    private func scrollingLibrary(containerWidth: CGFloat) -> some View {
        let layout = GameLibraryGridLayout(containerWidth: containerWidth)
        return ScrollView {
            VStack(alignment: .center, spacing: GameLibraryGridLayout.spacing) {
                ForEach(GameLibraryTitle.allCases) { title in
                    tile(title, coverSize: layout.coverSize)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, GameLibraryGridLayout.outerPadding)
            .padding(.top, 12)
        }
        .scrollIndicators(.hidden)
    }

    private func wideLibrary(containerSize: CGSize) -> some View {
        let layout = GameLibraryShelfLayout(containerSize: containerSize,
                                            usesRegularWidth: true)
        return HStack(alignment: .top, spacing: layout.spacing) {
            Spacer(minLength: layout.gutter)
            ForEach(GameLibraryTitle.allCases) { title in
                tile(title, coverSize: layout.coverSize)
                Spacer(minLength: layout.gutter)
            }
        }
        .frame(width: layout.shelfWidth, height: layout.shelfHeight, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func fittedPortraitLibrary(containerSize: CGSize) -> some View {
        let spacing = GameLibraryGridLayout.spacing
        let outerPadding = GameLibraryGridLayout.outerPadding
        let availableWidth = max(0, containerSize.width - outerPadding * 2 - spacing)
        let availableHeight = max(0, containerSize.height - outerPadding * 2 - spacing)
        let coverWidth = min(
            GameLibraryShelfLayout.regularPortraitMaximumCoverWidth,
            max(0, availableWidth / 2
                - GameLibraryShelfLayout.cardHorizontalInset * 2),
            max(0, availableHeight / 2 - GameLibraryShelfLayout.cardFooterHeight)
                * GameLibraryShelfLayout.coverAspectRatio
        )
        let coverSize = CGSize(width: coverWidth,
                               height: coverWidth / GameLibraryShelfLayout.coverAspectRatio)
        let titles = GameLibraryTitle.allCases
        return VStack(spacing: spacing) {
            HStack(spacing: 0) {
                Spacer(minLength: outerPadding)
                tile(titles[0], coverSize: coverSize)
                Spacer(minLength: spacing)
                tile(titles[1], coverSize: coverSize)
                Spacer(minLength: outerPadding)
            }
            HStack(spacing: 0) {
                Spacer(minLength: outerPadding)
                tile(titles[2], coverSize: coverSize)
                Spacer(minLength: spacing)
                Color.clear
                    .frame(width: coverWidth
                        + GameLibraryShelfLayout.cardHorizontalInset * 2)
                Spacer(minLength: outerPadding)
            }
        }
        .padding(.vertical, outerPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func compactLandscapeLibrary(containerSize: CGSize) -> some View {
        let layout = GameLibraryCompactLandscapeLayout(containerSize: containerSize)
        let cards = HStack(alignment: .center,
                           spacing: GameLibraryCompactLandscapeLayout.spacing) {
            ForEach(GameLibraryTitle.allCases) { title in
                tile(title, coverSize: layout.coverSize, usesHorizontalCard: true,
                     cardWidth: layout.cardWidth)
            }
        }
        .frame(width: layout.shelfWidth, alignment: .leading)

        if layout.usesHorizontalScroll {
            ScrollView(.horizontal) {
                cards
                    .padding(.horizontal, GameLibraryCompactLandscapeLayout.outerPadding)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            cards
                .padding(.horizontal, GameLibraryCompactLandscapeLayout.outerPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func tile(_ title: GameLibraryTitle,
                      coverSize: CGSize,
                      usesHorizontalCard: Bool = false,
                      cardWidth: CGFloat? = nil) -> some View {
        let displayTitle = GameLibraryPresentation.displayTitle(
            for: title,
            isValidatedAndLinked: isGameDataValidatedAndLinked(for: title)
        )
        return GameLibraryTile(
            title: title,
            displayTitle: displayTitle,
            state: state(for: title),
            progress: progress(for: title),
            coverSize: coverSize,
            usesHorizontalCard: usesHorizontalCard,
            cardWidth: cardWidth,
            artworkURL: artworkStore.artworkURL(for: title),
            artworkRevision: artworkStore.revision,
            open: { open(title) },
            chooseArtwork: { chooseArtwork(for: title) },
            removeArtwork: { artworkStore.removeArtwork(for: title) }
        )
    }

    private func isGameDataValidatedAndLinked(for title: GameLibraryTitle) -> Bool {
        guard let profile = GameDataProfile.profile(for: title) else { return false }
        return title == session.importer.profile.title
            && session.dataReport.status == .ready
            && GOALPadRuntimeBridge.isGameCodeLinked(
                for: profile.identifier.nativeGameIdentifier)
    }

    private var isPhone: Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
#else
        false
#endif
    }

    @ViewBuilder
    private var mainMenuLabel: some View {
        DarkEcoMenuLabel()
    }

    private func state(for title: GameLibraryTitle) -> GameLibraryState {
        guard GameDataProfile.profile(for: title) != nil else { return .planned }
        guard title == session.importer.profile.title else { return .notImported }
        switch session.importer.state {
        case .scanning:
            return .preparing(.importing(nil))
        case .copying(let progress):
            return .preparing(.importing(progress.overallProgress))
        case .cancelling:
            return .preparing(.cancellingImport)
        case .idle, .finished, .failed, .cancelled:
            break
        }
        if session.isRefreshingDataReport || session.dataReport.status == .checking {
            return .preparing(.checkingLocalData)
        }
        switch session.startupPhase {
        case .waitingForForegroundPreparation:
            return .preparing(.finishingSaveCheck)
        case .checkingSaves:
            return .preparing(.checkingSaves)
        case .idle, .booting:
            break
        }
        switch session.dataReport.status {
        case .checking:
            return .preparing(.checkingLocalData)
        case .empty:
            return .notImported
        case .incomplete:
            return .needsAttention
        case .ready:
            guard let profile = GameDataProfile.profile(for: title) else {
                return .needsAttention
            }
            return GOALPadRuntimeBridge.isGameCodeLinked(
                for: profile.identifier.nativeGameIdentifier) ? .ready : .needsAttention
        }
    }

    private func progress(for title: GameLibraryTitle) -> GameDataImporter.Progress? {
        guard title == session.importer.profile.title,
              case .copying(let progress) = session.importer.state else { return nil }
        return progress
    }

    private func open(_ title: GameLibraryTitle) {
        switch GameLibraryCardAction.resolve(
            title: title,
            state: state(for: title),
            supportsRuntimeLaunch: GameDataProfile.profile(for: title)?
                .supportsRuntimeLaunch == true
        ) {
        case .start(let title):
            if title == session.importer.profile.title {
                Task { await session.start() }
            } else {
                openGameSetup(title)
            }
        case .openSetup(let title):
            openGameSetup(title)
        case .verifyData(let title):
            Task {
                guard let profile = GameDataProfile.profile(for: title) else {
                    presentedAlert = .unsupported(title)
                    return
                }
                let report: GameDataReport
                if title == session.importer.profile.title {
                    report = await session.refreshDataReport()
                } else {
                    report = await Task.detached {
                        GameDataInspector.inspect(
                            gameDirectory: GameDataLayout.gameDirectory(
                                for: profile,
                                in: GameDataLayout.documentsDirectory
                            ),
                            profile: profile
                        )
                    }.value
                }
                if report.status == .ready {
                    if title == session.importer.profile.title {
                        await session.start()
                    } else {
                        openGameSetup(title)
                    }
                } else {
                    presentedAlert = .importGameData(title)
                }
            }
        case .showUnsupported(let title):
            presentedAlert = .unsupported(title)
        }
    }

    private func chooseArtwork(for title: GameLibraryTitle) {
        artworkTitle = title
        isChoosingArtwork = true
    }
}

private struct DarkEcoMenuLabel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let shimmerDuration: TimeInterval = 2.6
    private let labelFont: Font = .caption.weight(.semibold)

    var body: some View {
        TimelineView(.animation) { timeline in
            Text("Dark Eco")
                .font(labelFont)
                .foregroundStyle(labelForegroundStyle(at: timeline.date))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(DarkEcoTheme.surface.opacity(0.9), in: Capsule())
                .shadow(color: DarkEcoTheme.accent.opacity(0.32), radius: 6)
        }
    }

    private func shimmerLocation(at date: Date) -> CGFloat {
        guard !reduceMotion else { return 1 }
        let wrapped = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: shimmerDuration)
        return CGFloat(wrapped / shimmerDuration * 4 - 2)
    }

    private func labelForegroundStyle(at date: Date) -> LinearGradient {
        let highlightLocation = shimmerLocation(at: date)
        guard !reduceMotion else {
            return LinearGradient(
                colors: [DarkEcoTheme.accent, DarkEcoTheme.accent],
                startPoint: .leading,
                endPoint: .trailing
            )
        }

        return LinearGradient(
            colors: [DarkEcoTheme.accent, DarkEcoTheme.accent, .white.opacity(0.85), DarkEcoTheme.accent, DarkEcoTheme.accent],
            startPoint: UnitPoint(x: highlightLocation - 1, y: 0.5),
            endPoint: UnitPoint(x: highlightLocation + 1, y: 0.5)
        )
    }
}

private struct GameLibraryTile: View {
    let title: GameLibraryTitle
    let displayTitle: String
    let state: GameLibraryState
    let progress: GameDataImporter.Progress?
    let coverSize: CGSize
    let usesHorizontalCard: Bool
    let cardWidth: CGFloat?
    let artworkURL: URL?
    let artworkRevision: Int
    let open: () -> Void
    let chooseArtwork: () -> Void
    let removeArtwork: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            activationSurface
                .opacity(state == .planned ? 0.48 : 1)
                .accessibilityLabel("\(displayTitle), \(stateLabel)")
                .accessibilityHint(accessibilityHint)

            artworkMenu
        }
        .contextMenu {
            artworkActions
        }
    }

    @ViewBuilder
    private var activationSurface: some View {
        #if os(visionOS)
        tileSurface
            .contentShape([.interaction, .hoverEffect],
                          RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onTapGesture(perform: activate)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                activate()
            }
            .hoverEffect { effect, isActive, _ in
                effect.scaleEffect(isActive ? 1.025 : 1)
            }
        #else
        Button(action: activate) {
            tileSurface
        }
        .buttonStyle(.plain)
        #endif
    }

    private var tileSurface: some View {
        Group {
            if usesHorizontalCard {
                HStack(alignment: .center, spacing: 8) {
                    artwork
                    details
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    artwork
                    details
                }
            }
        }
        .padding(.horizontal, GameLibraryShelfLayout.cardHorizontalInset)
        .padding(.top, GameLibraryShelfLayout.cardHorizontalInset)
        .padding(.bottom, usesHorizontalCard
            ? GameLibraryShelfLayout.cardHorizontalInset
            : GameLibraryShelfLayout.cardBottomInset)
        .frame(width: cardWidth ?? coverSize.width
            + GameLibraryShelfLayout.cardHorizontalInset * 2,
               alignment: usesHorizontalCard ? .center : .leading)
        .background(DarkEcoTheme.surface.opacity(0.9),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(DarkEcoTheme.accent.opacity(0.42), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(usesHorizontalCard ? 4 : (coverSize.width < 120 ? 4 : 2))
                .minimumScaleFactor(0.78)
                .allowsTightening(true)
            stateStatus
            if case .preparing(let preparation) = state {
                if let fraction = preparation.fraction {
                    ProgressView(value: fraction)
                        .tint(DarkEcoTheme.accent)
                }
            }
            if let progress, progress.fraction != nil {
                Text("\(progress.filesCopied) of \(progress.filesTotal) files")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var stateStatus: some View {
        if case .preparing(let preparation) = state, preparation.fraction == nil {
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.small)
                    .tint(DarkEcoTheme.accent)
                Text(stateLabel)
                    .foregroundStyle(stateColor)
            }
            .font(.caption.weight(.medium))
        } else {
            Label(stateLabel, systemImage: stateSymbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(stateColor)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        Group {
            if let artworkURL,
               let image = GameArtworkStorage.thumbnail(at: artworkURL) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .id(artworkRevision)
            } else {
                FallbackGameArtwork(title: title)
            }
        }
        .frame(width: coverSize.width, height: coverSize.height)
        .background(Color.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(DarkEcoTheme.accent.opacity(0.5), lineWidth: 1)
        }
    }

    private var artworkMenu: some View {
        Menu {
            artworkActions
        } label: {
            Image(systemName: "ellipsis")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(10)
                .background(.black.opacity(0.55), in: Circle())
                .frame(minWidth: 44, minHeight: 44)
                #if os(visionOS)
                .contentShape([.interaction, .hoverEffect], Rectangle())
                #else
                .contentShape(Rectangle())
                #endif
        }
        .buttonStyle(.plain)
        .padding(10)
        .accessibilityLabel("Artwork options for \(displayTitle)")
    }

    @ViewBuilder
    private var artworkActions: some View {
        Button(action: chooseArtwork) {
            Label("Change Artwork…", systemImage: "photo")
        }
        if artworkURL != nil {
            Button(role: .destructive, action: removeArtwork) {
                Label("Use Default Artwork", systemImage: "arrow.uturn.backward")
            }
        }
    }

    private var stateLabel: String {
        switch state {
        case .notImported: "Not Imported"
        case .preparing(let preparation): preparation.label
        case .ready: "Ready"
        case .needsAttention: "Needs Attention"
        case .planned: title.availabilityLabel
        }
    }

    private var stateSymbol: String {
        switch state {
        case .notImported: "tray"
        case .preparing: "arrow.triangle.2.circlepath"
        case .ready: "play.fill"
        case .needsAttention: "exclamationmark.triangle"
        case .planned: "hourglass"
        }
    }

    private var stateColor: Color {
        switch state {
        case .notImported: .secondary
        case .planned: DarkEcoTheme.accent
        case .preparing: DarkEcoTheme.accentGlow
        case .ready: DarkEcoTheme.success
        case .needsAttention: DarkEcoTheme.warning
        }
    }

    private var accessibilityHint: String {
        switch state {
        case .ready: "Starts the game"
        case .preparing(.importing): "Opens game setup and import progress"
        case .preparing(.cancellingImport): "Opens game setup and cancellation status"
        case .preparing(.checkingLocalData):
            "Finishes checking this device before starting or showing setup"
        case .preparing(.finishingSaveCheck), .preparing(.checkingSaves):
            "Game will start after the save check"
        case .notImported, .needsAttention: "Checks again before offering game setup"
        case .planned: "Shows current support status"
        }
    }

    private func activate() {
        open()
    }
}

private struct FallbackGameArtwork: View {
    let title: GameLibraryTitle

    var body: some View {
        ZStack {
            LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 8) {
                Text(title.fallbackMark)
                    .font(.system(size: 62, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [.white, DarkEcoTheme.accentGlow],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .minimumScaleFactor(0.5)
                    .shadow(color: DarkEcoTheme.accent.opacity(0.55), radius: 12)
            }
        }
        .clipped()
    }

    private var palette: [Color] {
        switch title {
        case .jak1:
            [Color.black, DarkEcoTheme.background, DarkEcoTheme.accent.opacity(0.72)]
        case .jak2:
            [Color.black, DarkEcoTheme.surface, Color(red: 0.24, green: 0.1, blue: 0.36)]
        case .jak3:
            [Color.black, DarkEcoTheme.background,
             DarkEcoTheme.accentGlow.opacity(0.48)]
        }
    }
}
