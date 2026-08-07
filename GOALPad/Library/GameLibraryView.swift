import SwiftUI
import UniformTypeIdentifiers

private enum GameLibraryAlert: Identifiable {
    case importJak1
    case unsupported(GameLibraryTitle)
    case artwork(String)

    var id: String {
        switch self {
        case .importJak1: "import-jak1"
        case .unsupported(let title): "unsupported-\(title.id)"
        case .artwork: "artwork"
        }
    }
}

struct GameLibraryView: View {
    @Bindable var session: GameSession
    @Bindable var artworkStore: GameArtworkStore
    let openJak1Setup: () -> Void
    let openSettings: () -> Void

    @State private var artworkTitle: GameLibraryTitle?
    @State private var isChoosingArtwork = false
    @State private var presentedAlert: GameLibraryAlert?
    @State private var isShowingCredits = false

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let layout = GameLibraryShelfLayout(containerSize: proxy.size)
                HStack(alignment: .top, spacing: layout.spacing) {
                    ForEach(GameLibraryTitle.allCases) { title in
                        GameLibraryTile(
                            title: title,
                            state: state(for: title),
                            progress: progress(for: title),
                            coverSize: layout.coverSize,
                            artworkURL: artworkStore.artworkURL(for: title),
                            artworkRevision: artworkStore.revision,
                            open: { open(title) },
                            chooseArtwork: { chooseArtwork(for: title) },
                            removeArtwork: { artworkStore.removeArtwork(for: title) }
                        )
                    }
                }
                .frame(width: layout.shelfWidth, height: layout.shelfHeight, alignment: .top)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .background {
                LinearGradient(
                    colors: [Color.black, DarkEcoTheme.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Menu {
                        Button(action: openSettings) {
                            Label("Settings", systemImage: "gearshape")
                        }
                        Button { isShowingCredits = true } label: {
                            Label("Credits", systemImage: "person.3")
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                    .accessibilityLabel("Main menu")
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(DarkEcoTheme.accent)
        .sheet(isPresented: $isShowingCredits) {
            NavigationStack {
                CreditsView()
            }
            .preferredColorScheme(.dark)
            .tint(DarkEcoTheme.accent)
        }
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
        .alert(item: $presentedAlert) { alert in
            switch alert {
            case .importJak1:
                Alert(
                    title: Text("Set Up Jak 1"),
                    message: Text(GameLibraryOfferCopy.jak1ImportMessage(
                        canImportRawISO: RawISOCandidateProducer.isAvailable())),
                    primaryButton: .default(Text("Continue"), action: openJak1Setup),
                    secondaryButton: .cancel()
                )
            case .unsupported(let title):
                Alert(
                    title: Text("\(title.shelfName) Isn’t Supported Yet"),
                    message: Text(GameLibraryOfferCopy.unsupportedMessage(for: title)),
                    dismissButton: .default(Text("OK"))
                )
            case .artwork(let message):
                Alert(
                    title: Text("Artwork Could Not Be Changed"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private func state(for title: GameLibraryTitle) -> GameLibraryState {
        guard title == .jak1 else { return .planned }
        switch session.importer.state {
        case .scanning:
            return .preparing(nil)
        case .copying(let progress):
            return .preparing(progress.fraction)
        case .idle, .finished, .failed, .cancelled:
            break
        }

        switch session.dataReport.status {
        case .empty:
            return .notImported
        case .incomplete:
            return .needsAttention
        case .ready:
            return GOALPadRuntimeBridge.isGameCodeLinked ? .ready : .needsAttention
        }
    }

    private func progress(for title: GameLibraryTitle) -> GameDataImporter.Progress? {
        guard title == .jak1,
              case .copying(let progress) = session.importer.state else { return nil }
        return progress
    }

    private func open(_ title: GameLibraryTitle) {
        switch GameLibraryCardAction.resolve(title: title, state: state(for: title)) {
        case .start:
            Task { await session.start() }
        case .openJak1Setup:
            openJak1Setup()
        case .offerJak1Import:
            presentedAlert = .importJak1
        case .showUnsupported(let title):
            presentedAlert = .unsupported(title)
        }
    }

    private func chooseArtwork(for title: GameLibraryTitle) {
        artworkTitle = title
        isChoosingArtwork = true
    }
}

private struct CreditsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            DarkEcoPanel {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Eco")
                            .font(.largeTitle.bold())
                        Text("Native OpenGOAL Runtime")
                            .font(.headline)
                            .foregroundStyle(DarkEcoTheme.accentGlow)
                    }

                    Text("Built on the open-source OpenGOAL project and the work of its contributors.")
                    Text("Eco is an unofficial community project and is not affiliated with Sony Interactive Entertainment, Naughty Dog, or the OpenGOAL team.")
                        .foregroundStyle(.secondary)
                    Text("Game data is not included. Players provide compatible data from copies they legally own.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background {
            LinearGradient(colors: [Color.black, DarkEcoTheme.background],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
        .navigationTitle("Credits")
        .tint(DarkEcoTheme.accent)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

private struct GameLibraryTile: View {
    let title: GameLibraryTitle
    let state: GameLibraryState
    let progress: GameDataImporter.Progress?
    let coverSize: CGSize
    let artworkURL: URL?
    let artworkRevision: Int
    let open: () -> Void
    let chooseArtwork: () -> Void
    let removeArtwork: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: activate) {
                VStack(alignment: .leading, spacing: 8) {
                    artwork

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title.shelfName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Label(stateLabel, systemImage: stateSymbol)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(stateColor)
                        if case .preparing(let fraction) = state, let fraction {
                            ProgressView(value: fraction)
                                .tint(DarkEcoTheme.accent)
                        }
                        if let progress {
                            Text("\(progress.filesCopied) of \(progress.filesTotal) files")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(GameLibraryShelfLayout.cardHorizontalInset)
                .frame(width: coverSize.width
                    + GameLibraryShelfLayout.cardHorizontalInset * 2,
                       alignment: .leading)
                .background(DarkEcoTheme.surface.opacity(0.9),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(DarkEcoTheme.accent.opacity(0.42), lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .opacity(state == .planned ? 0.48 : 1)
            .accessibilityLabel("\(title.name), \(stateLabel)")
            .accessibilityHint(accessibilityHint)

            artworkMenu
        }
        .contextMenu {
            artworkActions
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
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(10)
        .accessibilityLabel("Artwork options for \(title.name)")
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
        case .preparing: "Preparing"
        case .ready: "Ready"
        case .needsAttention: "Needs Attention"
        case .planned: "Not Supported"
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
        case .notImported, .preparing, .needsAttention: "Opens game setup"
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
            Circle()
                .fill(.black.opacity(0.38))
                .frame(width: 190, height: 190)
                .offset(x: 80, y: -55)
            Circle()
                .stroke(DarkEcoTheme.accent.opacity(0.18), lineWidth: 2)
                .frame(width: 150, height: 150)
                .offset(x: -90, y: 70)
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(
                    LinearGradient(colors: [.white.opacity(0.34), .clear,
                                            DarkEcoTheme.accentGlow.opacity(0.48)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 2
                )
                .padding(11)
            VStack(spacing: 8) {
                Text(title.fallbackMark)
                    .font(.system(size: 62, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [.white, DarkEcoTheme.accentGlow],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .minimumScaleFactor(0.5)
                    .shadow(color: DarkEcoTheme.accent.opacity(0.55), radius: 12)
                Text("ECO")
                    .font(.caption2.weight(.bold))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.72))
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
