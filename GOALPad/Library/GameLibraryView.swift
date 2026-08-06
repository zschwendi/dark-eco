import SwiftUI
import UniformTypeIdentifiers

struct GameLibraryView: View {
    @Bindable var session: GameSession
    @Bindable var artworkStore: GameArtworkStore
    let importGame: () -> Void
    let openSettings: () -> Void

    @State private var artworkTitle: GameLibraryTitle?
    @State private var isChoosingArtwork = false

    private let columns = [
        GridItem(.adaptive(minimum: 330, maximum: 480), spacing: 20),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(GameLibraryTitle.allCases) { title in
                        GameLibraryTile(
                            title: title,
                            state: state(for: title),
                            progress: progress(for: title),
                            artworkURL: artworkStore.artworkURL(for: title),
                            artworkRevision: artworkStore.revision,
                            open: { open(title) },
                            chooseArtwork: { chooseArtwork(for: title) },
                            removeArtwork: { artworkStore.removeArtwork(for: title) }
                        )
                    }
                }
                .padding(24)
                .frame(maxWidth: 1_000)
                .frame(maxWidth: .infinity)
            }
            .background {
                LinearGradient(
                    colors: [Color.black, Color(red: 0.055, green: 0.035, blue: 0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Menu {
                        Button(action: importGame) {
                            Label("Import Game", systemImage: "square.and.arrow.down")
                        }
                        Button(action: openSettings) {
                            Label("Settings", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                    .accessibilityLabel("Main menu")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: openSettings) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
        .preferredColorScheme(.dark)
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
        .alert(
            "Artwork Could Not Be Changed",
            isPresented: Binding(
                get: { artworkStore.errorMessage != nil },
                set: { if !$0 { artworkStore.errorMessage = nil } }
            )
        ) {
            Button("OK") { artworkStore.errorMessage = nil }
        } message: {
            Text(artworkStore.errorMessage ?? "Unknown error")
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
        switch state(for: title) {
        case .ready:
            Task { await session.start() }
        case .notImported, .preparing, .needsAttention:
            importGame()
        case .planned:
            break
        }
    }

    private func chooseArtwork(for title: GameLibraryTitle) {
        artworkTitle = title
        isChoosingArtwork = true
    }
}

private struct GameLibraryTile: View {
    let title: GameLibraryTitle
    let state: GameLibraryState
    let progress: GameDataImporter.Progress?
    let artworkURL: URL?
    let artworkRevision: Int
    let open: () -> Void
    let chooseArtwork: () -> Void
    let removeArtwork: () -> Void

    var body: some View {
        Button(action: activate) {
            VStack(alignment: .leading, spacing: 12) {
                artwork
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(title.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Label(stateLabel, systemImage: stateSymbol)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(stateColor)
                    if case .preparing(let fraction) = state, let fraction {
                        ProgressView(value: fraction)
                            .tint(.orange)
                    }
                    if let progress {
                        Text("\(progress.filesCopied) of \(progress.filesTotal) files")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(accessibilityHint)
        .disabled(state == .planned)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(alignment: .topTrailing) { artworkMenu }
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contextMenu {
            artworkActions
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let artworkURL,
           let image = GameArtworkStorage.thumbnail(at: artworkURL) {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
                .id(artworkRevision)
        } else {
            FallbackGameArtwork(title: title)
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
        .padding(22)
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
        case .planned: "Planned"
        }
    }

    private var stateSymbol: String {
        switch state {
        case .notImported: "tray"
        case .preparing: "arrow.triangle.2.circlepath"
        case .ready: "play.fill"
        case .needsAttention: "exclamationmark.triangle"
        case .planned: "clock"
        }
    }

    private var stateColor: Color {
        switch state {
        case .notImported, .planned: .secondary
        case .preparing: .orange
        case .ready: .green
        case .needsAttention: .yellow
        }
    }

    private var accessibilityHint: String {
        switch state {
        case .ready: "Starts the game"
        case .notImported, .preparing, .needsAttention: "Opens game setup"
        case .planned: "This title is not available yet"
        }
    }

    private func activate() {
        if state != .planned { open() }
    }
}

private struct FallbackGameArtwork: View {
    let title: GameLibraryTitle

    var body: some View {
        ZStack {
            LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(.black.opacity(0.3))
                .frame(width: 190, height: 190)
                .offset(x: 80, y: -55)
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: 2)
                .frame(width: 150, height: 150)
                .offset(x: -90, y: 70)
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(
                    LinearGradient(colors: [.white.opacity(0.42), .clear, .orange.opacity(0.5)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 2
                )
                .padding(11)
            VStack(spacing: 8) {
                Text(title.fallbackMark)
                    .font(.system(size: 62, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [.white, .orange],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .shadow(color: .orange.opacity(0.55), radius: 12)
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
            [Color(red: 0.08, green: 0.02, blue: 0.12),
             Color(red: 0.22, green: 0.04, blue: 0.28),
             Color(red: 0.95, green: 0.28, blue: 0.03)]
        case .jak2:
            [Color(red: 0.02, green: 0.02, blue: 0.03),
             Color(red: 0.18, green: 0.03, blue: 0.22),
             Color(red: 0.38, green: 0.09, blue: 0.48)]
        case .jak3:
            [Color(red: 0.04, green: 0.015, blue: 0.06),
             Color(red: 0.30, green: 0.04, blue: 0.30),
             Color(red: 0.72, green: 0.18, blue: 0.06)]
        }
    }
}
