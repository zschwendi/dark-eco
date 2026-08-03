import SwiftUI
import UniformTypeIdentifiers

/// What the player sees until their own game data is in place, and the two ways of getting it
/// there. Eco Pro ships with no game data and never downloads any.
struct GameDataSetupView: View {
    private static let rawISOType = UTType(filenameExtension: "iso", conformingTo: .data)

    @Bindable var session: GameSession
    @State private var isChoosingSource = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                title
                status
                instructions
                actions
                if let error = session.startupError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .safeAreaPadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.85))
        .fileImporter(isPresented: $isChoosingSource,
                      allowedContentTypes: importContentTypes,
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let source = urls.first {
                session.importer.start(from: source) {
                    Task { await session.refreshDataReport() }
                }
            }
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Add compatible game data")
                .font(.title2.weight(.semibold))
            Text("Eco Pro runs compatible data you provide. No game data ships with this app.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var status: some View {
        let report = session.dataReport
        VStack(alignment: .leading, spacing: 6) {
            Label(report.summary, systemImage: icon(for: report.status))
                .foregroundStyle(color(for: report.status))
            missingList("Missing from iso/ (the game cannot boot)", report.missingBootArchives)
            missingList("Missing level archives", report.missingLevelArchives)
            missingList("Missing level geometry", report.missingLevelGeometry)
        }
        .font(.system(.footnote, design: .monospaced))
    }

    @ViewBuilder
    private func missingList(_ title: String, _ names: [String]) -> some View {
        if !names.isEmpty {
            Text("\(title): \(names.joined(separator: " "))")
                .foregroundStyle(.orange)
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Getting your data onto this device")
                .font(.headline)
            Text(setupInstructions)
            .font(.callout)
            .foregroundStyle(.secondary)
            Text(importCompatibilityNote)
                .font(.callout.weight(.medium))
                .foregroundStyle(.orange)
            Text(GameDataLayout.gameDirectory.path)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
        }
    }

    private var setupInstructions: String {
        if canImportRawISO {
            return """
            Eco Pro can prepare a supported `.iso` disc image or a standard `.zip` containing one \
            `.iso` on this device, or import an existing OpenGOAL `out/jak1` folder containing \
            `iso/` and `fr3/`.

            1. Put the `.iso`, `.zip`, or prepared folder in Files, iCloud Drive, or an external drive.
            2. Choose Import game data below.
            3. Select the `.iso`, `.zip`, or prepared folder in the system picker.

            Import prepares and validates a private candidate before activation. Existing game data \
            stays playable if preparation fails, so the device needs enough free space for the source, \
            preparation work, and final data.
            """
        }

        return """
        Prepare the compatible game data with OpenGOAL on a computer. That produces an `out/jak1` \
        folder containing `iso/` and `fr3/`.

        1. Put the prepared folder in Files, iCloud Drive, or an external drive.
        2. Choose Import game data below.
        3. Select the prepared folder in the system picker.

        Import validates a private candidate before activation and leaves existing game data \
        untouched if the import fails.
        """
    }

    private var importCompatibilityNote: String {
        if canImportRawISO {
            return "Choose a supported `.iso`, a standard `.zip` containing exactly one `.iso`, "
                + "or an already prepared `out/jak1` folder. ZIP64, encrypted, multi-disk, and "
                + "non-ZIP archives are not supported. ZIP member names must use ASCII or UTF-8."
        }
        return "This build accepts an already prepared `out/jak1` folder. Raw `.iso`, `.zip`, "
            + "and other archive files are not supported in this build."
    }

    private var canImportRawISO: Bool {
        RawISOCandidateProducer.isAvailable()
    }

    @ViewBuilder
    private var actions: some View {
        switch session.importer.state {
        case .copying(let progress):
            VStack(alignment: .leading, spacing: 6) {
                if let fraction = progress.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }
                Text(progress.phase.label)
                    .font(.callout.weight(.medium))
                if progress.filesTotal > 0 {
                    Text("\(progress.filesCopied) / \(progress.filesTotal)  \(progress.currentFile)")
                        .font(.system(.caption, design: .monospaced))
                }
                if progress.phase != .activatingCandidate {
                    Button("Cancel", role: .destructive) { session.importer.cancel() }
                }
            }
        case .scanning:
            ProgressView("Scanning…")
        case .failed(let failure):
            VStack(alignment: .leading, spacing: 6) {
                Text(failure.recoveryMessage).foregroundStyle(.red).font(.callout)
                buttons
            }
        case .cancelled:
            VStack(alignment: .leading, spacing: 6) {
                Text("Import cancelled. The active game data was not changed. Staged data was kept for recovery.")
                    .foregroundStyle(.orange)
                    .font(.callout)
                buttons
            }
        case .finished(let copied, let skipped):
            VStack(alignment: .leading, spacing: 6) {
                Text("Copied \(copied) file(s); \(skipped) were already present.")
                    .font(.callout)
                buttons
            }
        case .idle:
            buttons
        }
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Button("Import game data…") { isChoosingSource = true }
                .buttonStyle(.bordered)
            Button("Recheck") {
                Task { await session.refreshDataReport() }
            }
            .buttonStyle(.bordered)
            Button("Start") { session.start() }
                .buttonStyle(.borderedProminent)
                .disabled(!session.dataReport.canBoot)
        }
    }

    private var importContentTypes: [UTType] {
        if canImportRawISO, let rawISOType = Self.rawISOType {
            return [.folder, rawISOType, .zip]
        }
        return [.folder]
    }

    private func icon(for status: GameDataReport.Status) -> String {
        switch status {
        case .empty: return "tray"
        case .incomplete: return "exclamationmark.triangle"
        case .ready: return "checkmark.circle"
        }
    }

    private func color(for status: GameDataReport.Status) -> Color {
        switch status {
        case .empty: return .secondary
        case .incomplete: return .orange
        case .ready: return .green
        }
    }
}
