import SwiftUI
import UniformTypeIdentifiers

/// Imports player-supplied Jak 1 data without bundling or downloading game content.
struct GameDataSetupView: View {
    private static let rawISOType = UTType(filenameExtension: "iso", conformingTo: .data)

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
                    Task { await session.refreshDataReport() }
                }
            case .failure(let error):
                selectionError = "Eco could not open that source: \(error.localizedDescription) Try again."
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Import \(GameLibraryTitle.jak1.name)", systemImage: "bolt.fill")
                .font(.title2.weight(.bold))
                .foregroundStyle(DarkEcoTheme.accentGlow)
            Text("Choose game data from a copy of \(GameLibraryTitle.jak1.name) that you own. Eco includes no game data and never downloads it.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.84))
        }
        .accessibilityElement(children: .combine)
    }

    private var dataStatus: some View {
        DarkEcoPanel {
            VStack(alignment: .leading, spacing: 7) {
                Label(session.dataReport.summary, systemImage: statusIcon)
                    .font(.headline)
                    .foregroundStyle(statusColor)
                Text("Game data stays on this device. iCloud Settings and iCloud Saves do not transfer it.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
    }

    private var importFlow: some View {
        DarkEcoPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("1. Choose your source")
                    .font(.headline)
                Text(GameDataImportPresentation.acceptedSources(rawISOAvailable: canImportRawISO))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.84))
                Text("2. Eco prepares and validates a private candidate before it replaces any active data.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.84))
                if canImportRawISO {
                    Text("A standard ZIP must contain exactly one ISO. Other archive formats are not accepted.")
                        .font(.footnote)
                        .foregroundStyle(DarkEcoTheme.warning)
                } else {
                    Text("This build cannot prepare raw ISO or ZIP sources. Choose a prepared folder.")
                        .font(.footnote)
                        .foregroundStyle(DarkEcoTheme.warning)
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
        case .finished(let copied, let skipped):
            VStack(alignment: .leading, spacing: 12) {
                messagePanel("Import complete", message: "Prepared \(copied) file(s); \(skipped) were already present.",
                             color: DarkEcoTheme.success)
                actions
            }
        case .idle:
            actions
        }
    }

    private func importProgress(_ progress: GameDataImportProgress) -> some View {
        DarkEcoPanel {
            VStack(alignment: .leading, spacing: 12) {
                Label(progress.phase.label, systemImage: "bolt.circle.fill")
                    .font(.headline)
                    .foregroundStyle(DarkEcoTheme.accentGlow)
                Group {
                    if let fraction = progress.fraction {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView()
                    }
                }
                .tint(DarkEcoTheme.accent)
                .accessibilityLabel("\(GameLibraryTitle.jak1.name) import progress")
                .accessibilityValue(progress.phase.label)

                if progress.filesTotal > 0 {
                    Text("\(progress.filesCopied) of \(progress.filesTotal) · \(progress.currentFile)")
                        .font(.footnote.monospaced())
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(2)
                }

                Text(GameDataImportPresentation.backgroundGuidance(phaseLabel: progress.phase.label))
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

            Button("Choose \(GameLibraryTitle.jak1.name) data…") {
                selectionError = nil
                isChoosingSource = true
            }
            .buttonStyle(.borderedProminent)
            .tint(DarkEcoTheme.accent)

            HStack(spacing: 12) {
                Button("Recheck") {
                    Task { await session.refreshDataReport() }
                }
                .buttonStyle(.bordered)

                Button("Play \(GameLibraryTitle.jak1.name)") { Task { await session.start() } }
                    .buttonStyle(.bordered)
                    .disabled(!session.dataReport.canBoot || session.startupPhase.isPreparing)
            }
        }
    }

    private var startupMessage: String? {
        switch session.startupPhase {
        case .waitingForForegroundPreparation:
            "Preparing saves before gameplay…"
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
            return [.folder, rawISOType, .zip]
        }
        return [.folder]
    }

    private var canImportRawISO: Bool {
        RawISOCandidateProducer.isAvailable()
    }

    private var statusIcon: String {
        switch session.dataReport.status {
        case .empty: "tray"
        case .incomplete: "exclamationmark.triangle"
        case .ready: "checkmark.circle"
        }
    }

    private var statusColor: Color {
        switch session.dataReport.status {
        case .empty: return .white.opacity(0.72)
        case .incomplete: return DarkEcoTheme.warning
        case .ready: return DarkEcoTheme.success
        }
    }
}
