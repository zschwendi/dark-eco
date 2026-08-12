import SwiftUI
import UniformTypeIdentifiers

/// Imports player-supplied Jak 1 data without bundling or downloading game content.
struct GameDataSetupView: View {
    private static let rawISOType = UTType(filenameExtension: "iso", conformingTo: .data)
    private static let sevenZipType = UTType(filenameExtension: "7z", conformingTo: .archive)

    @Bindable var session: GameSession
    @State private var isChoosingSource = false
    @State private var selectionError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                dataStatus
                importFlow
                importState
                if let error = selectionError ?? session.startupError {
                    messagePanel("Needs attention", message: error, color: DarkEcoTheme.danger)
                }
            }
            .padding(24)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .safeAreaPadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DarkEcoTheme.background)
        .task { _ = await session.refreshDataReport() }
        .fileImporter(isPresented: $isChoosingSource,
                      allowedContentTypes: importContentTypes,
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let source = urls.first else {
                    selectionError = "No source was selected. Choose one source for "
                        + "\(GameLibraryTitle.jak1.name) and try again."
                    return
                }
                selectionError = nil
                session.importer.start(from: source) {
                    await session.refreshDataReport()
                }
            case .failure(let error):
                selectionError = "Dark Eco could not open that source: \(error.localizedDescription) Try again."
            }
        }
    }

    private var header: some View {
        Text("Choose a compatible source from a copy you own.")
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
                messagePanel("Import cancelled", message: GameDataImportPresentation.cancelledRecovery,
                             color: DarkEcoTheme.warning)
                actions
            }
        case .finished:
            VStack(alignment: .leading, spacing: 12) {
                DarkEcoPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Import complete")
                            .font(.headline)
                            .foregroundStyle(DarkEcoTheme.success)
                        ProgressView(value: 1)
                            .tint(DarkEcoTheme.success)
                            .accessibilityLabel("\(GameLibraryTitle.jak1.name) import progress")
                            .accessibilityValue("100% complete")
                        Text("100% complete · Your game data is ready to play.")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.84))
                    }
                }
                actions
            }
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
                if progress.fraction != nil {
                    ProgressView(value: progress.overallProgress)
                        .tint(DarkEcoTheme.accent)
                        .accessibilityLabel("\(GameLibraryTitle.jak1.name) import progress")
                        .accessibilityValue("\(progress.overallPercent)% complete · \(progress.phase.playerLabel)")
                    Text("\(progress.overallPercent)% complete")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.78))
                } else {
                    ProgressView()
                        .tint(DarkEcoTheme.accent)
                        .accessibilityLabel("\(progress.phase.playerLabel) in progress")
                }

                Text(GameDataImportPresentation.backgroundGuidance)
                    .font(.footnote)
                    .foregroundStyle(DarkEcoTheme.warning)
                Text(GameDataImportPresentation.cancellationGuidance(
                    isActivating: progress.phase == .activatingCandidate
                ))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.72))

                if progress.phase != .activatingCandidate {
                    Button("Cancel import", role: .destructive) { session.importer.cancel() }
                        .buttonStyle(.bordered)
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
        Button("Play \(GameLibraryTitle.jak1.name)") { Task { await session.start() } }
            .buttonStyle(.bordered)
            .disabled(!session.dataReport.canBoot || session.isRefreshingDataReport
                || session.startupPhase.isPreparing)
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
        RawISOCandidateProducer.isAvailable()
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
