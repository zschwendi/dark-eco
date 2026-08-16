import SwiftUI
import UniformTypeIdentifiers

/// Imports player-supplied data for the compile-selected title without bundling or downloading
/// game content.
struct GameDataSetupView: View {
    private static let rawISOType = UTType(filenameExtension: "iso", conformingTo: .data)
    private static let sevenZipType = UTType(filenameExtension: "7z", conformingTo: .archive)

    @Bindable var session: GameSession
    @State private var isChoosingSource = false
    @State private var selectionError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: isImportComplete ? 32 : 18) {
                if showsSourceSelection {
                    header
                    dataStatus
                    importFlow
                } else if isImportComplete {
                    dataStatus
                }
                if isImportComplete {
                    completionActions
                } else {
                    importState
                }
                if let error = selectionError ?? session.startupError {
                    messagePanel("Needs attention", message: error, color: DarkEcoTheme.danger)
                }
            }
            .padding(24)
            .padding(.top, isImportComplete ? 16 : 0)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .safeAreaPadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            DarkEcoLauncherBackground()
                .ignoresSafeArea()
        }
        .task { _ = await session.refreshDataReport() }
        .fileImporter(isPresented: $isChoosingSource,
                      allowedContentTypes: importContentTypes,
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let source = urls.first else {
                    #if GOALPAD_JAK2
                    selectionError = "No source was selected. Choose compatible "
                        + "\(GameDataProfile.active.displayName) data and try again."
                    #else
                    selectionError = "No source was selected. Choose one compatible source and try again."
                    #endif
                    return
                }
                selectionError = nil
                session.importer.start(from: source) {
                    session.saveSync.gameDataImportDidFinish()
                    await session.refreshDataReport()
                }
            case .failure:
                #if GOALPAD_JAK2
                selectionError = "Dark Eco could not open that source. Choose another compatible "
                    + "\(GameDataProfile.active.displayName) source and try again."
                #else
                selectionError = "Dark Eco could not open that source. Choose another compatible source and try again."
                #endif
            }
        }
    }

    private var header: some View {
        #if GOALPAD_JAK2
        Text(GameLibraryOfferCopy.importMessage(
            for: GameLibraryTitle.active,
            canImportRawMedia: canImportRawISO
        ))
        #else
        Text(GameLibraryOfferCopy.jak1ImportMessage())
        #endif
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var dataStatus: some View {
        DarkEcoPanel {
            VStack(alignment: .leading, spacing: 7) {
                Label(session.dataReport.summary, systemImage: statusIcon)
                    .font(.headline)
                    .foregroundStyle(statusColor)
                if session.dataReport.status == .ready {
                    Text(GameDataImportPresentation.completedStorageGuidance)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.84))
                }
            }
        }
    }

    private var importFlow: some View {
        DarkEcoPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("Supported sources")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(GameDataImportPresentation.acceptedSources(
                        rawISOAvailable: canImportRawISO
                    ), id: \.self) { source in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text(source)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var importState: some View {
        switch session.importer.state {
        case .scanning:
            importProgress(GameDataImportProgress(phase: .scanning))
        case .copying(let progress):
            importProgress(progress)
        case .cancelling:
            DarkEcoPanel {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(DarkEcoTheme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cancelling import…")
                            .font(.headline)
                        Text("Dark Eco is waiting for preparation to stop safely. Retry will be available when cancellation finishes.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
            }
        case .failed(let failure):
            VStack(alignment: .leading, spacing: 12) {
                messagePanel("Import failed", message: failure.recoveryMessage, color: DarkEcoTheme.danger)
                actions
            }
        case .cancelled:
            VStack(alignment: .leading, spacing: 12) {
                DarkEcoPanel {
                    Text("Import canceled")
                        .font(.headline)
                        .foregroundStyle(DarkEcoTheme.warning)
                }
                actions
            }
        case .finished:
            actions
        case .idle:
            actions
        }
    }

    private func importProgress(_ progress: GameDataImportProgress) -> some View {
        DarkEcoPanel {
            VStack(alignment: .leading, spacing: 12) {
                Label(progress.phase.playerLabel, systemImage: "bolt.circle.fill")
                    .font(.headline)
                    .foregroundStyle(DarkEcoTheme.accentGlow)
                ProgressView(value: progress.overallProgress)
                    .tint(DarkEcoTheme.accent)
                    .accessibilityLabel("Game data import progress")
                    .accessibilityValue("\(progress.overallPercent)% complete · \(progress.phase.playerLabel)")
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(DarkEcoTheme.accent)
                        .accessibilityHidden(true)
                    Text("\(progress.overallPercent)% complete")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.78))
                }

                Text(GameDataImportPresentation.backgroundGuidance)
                    .font(.footnote)
                    .foregroundStyle(DarkEcoTheme.warning)

                if progress.phase != .activatingCandidate {
                    Button(role: .destructive) {
                        session.importer.cancel()
                    } label: {
                        Text("Cancel import")
                            .foregroundStyle(DarkEcoTheme.danger)
                    }
                    .buttonStyle(.bordered)
                    .tint(.gray)
                }
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let startupMessage {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(DarkEcoTheme.accent)
                    Text(startupMessage)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.84))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(startupMessage)
            }

            Button("Choose game data…") {
                selectionError = nil
                isChoosingSource = true
            }
            .buttonStyle(.borderedProminent)
            .tint(DarkEcoTheme.accent)
            .disabled(!session.importer.canStart || session.isRefreshingDataReport)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { recheckButton; playButton }
                VStack(alignment: .leading, spacing: 12) { recheckButton; playButton }
            }
        }
    }

    private var completionActions: some View {
        VStack(spacing: 16) {
            if let startupMessage {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(DarkEcoTheme.accent)
                    Text(startupMessage)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.84))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(startupMessage)
            }

            Button {
                Task { await session.start() }
            } label: {
                Text("Play Now")
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 88)
            }
            .buttonStyle(.borderedProminent)
            .tint(DarkEcoTheme.accent)
            .frame(maxWidth: 360)
            .disabled(session.isRefreshingDataReport || session.startupPhase.isPreparing)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var recheckButton: some View {
                Button {
                    Task { await session.refreshDataReport() }
                } label: {
                    if session.isRefreshingDataReport {
                        ProgressView()
                            .controlSize(.small)
                        Text("Rechecking…")
                    } else {
                        Text("Recheck")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(session.isRefreshingDataReport)
    }

    private var playButton: some View {
        Button("Play Now") { Task { await session.start() } }
            .buttonStyle(.bordered)
            #if GOALPAD_JAK2
            .disabled(!session.dataReport.canLaunchRuntime || session.isRefreshingDataReport
                || session.startupPhase.isPreparing)
            #else
            .disabled(!session.dataReport.canBoot || session.isRefreshingDataReport
                || session.startupPhase.isPreparing)
            #endif
    }

    private var startupMessage: String? {
        switch session.startupPhase {
        case .waitingForForegroundPreparation:
            "Finishing the current save check before gameplay…"
        case .checkingSaves:
            "Checking saves before gameplay…"
        case .idle, .booting:
            nil
        }
    }

    private func messagePanel(_ title: String, message: String, color: Color) -> some View {
        DarkEcoPanel {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(color)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.84))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var importContentTypes: [UTType] {
        if canImportRawISO, let rawISOType = Self.rawISOType {
            return [.folder, rawISOType, .zip] + (Self.sevenZipType.map { [$0] } ?? [])
        }
        return [.folder]
    }

    private var canImportRawISO: Bool {
        GameDataProfile.active.supportsRawMediaPreparation
            && RawISOCandidateProducer.isAvailable(for: .active)
    }

    private var isImportComplete: Bool {
        session.dataReport.status == .ready
    }

    private var showsSourceSelection: Bool {
        guard !isImportComplete else { return false }
        return switch session.importer.state {
        case .scanning, .copying, .cancelling: false
        case .idle, .finished, .cancelled, .failed: true
        }
    }

    private var statusIcon: String {
        switch session.dataReport.status {
        case .checking: "arrow.triangle.2.circlepath"
        case .empty: "tray"
        case .incomplete: "exclamationmark.triangle"
        case .ready: "checkmark.circle"
        }
    }

    private var statusColor: Color {
        switch session.dataReport.status {
        case .checking: return DarkEcoTheme.accentGlow
        case .empty: return .white.opacity(0.72)
        case .incomplete: return DarkEcoTheme.warning
        case .ready: return DarkEcoTheme.success
        }
    }
}
