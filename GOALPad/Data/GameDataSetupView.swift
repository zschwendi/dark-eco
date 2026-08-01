import SwiftUI
import UniformTypeIdentifiers

/// What the player sees until their own game data is in place, and the two ways of getting it
/// there. GOALPad ships with no game data and never downloads any.
struct GameDataSetupView: View {
    @Bindable var session: GameSession
    @State private var isChoosingFolder = false

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
        .fileImporter(isPresented: $isChoosingFolder,
                      allowedContentTypes: [.folder],
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
            Text("Jak and Daxter: The Precursor Legacy")
                .font(.title2.weight(.semibold))
            Text("GOALPad plays your own copy. No game data ships with this app.")
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
            Text("""
            Extract Jak 1 with the OpenGOAL tools on a computer. That produces an `out/jak1` \
            directory holding `iso/` and `fr3/` — about 1.5 GB.

            1. Connect the iPad and open it in Finder, or open the Files app on the iPad.
            2. Find GOALPad under On My iPad / the device's Files section.
            3. Copy the whole `iso` and `fr3` directories into GOALPad's `Jak1` folder.

            Or use Import below to copy them in from an external drive or iCloud Drive. That reads \
            the folder you pick and writes a second copy into the app, so it needs the free space \
            twice over — the Files route does not.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)
            Text(GameDataLayout.gameDirectory.path)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch session.importer.state {
        case .copying(let progress):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: progress.fraction)
                Text("\(progress.filesCopied) / \(progress.filesTotal)  \(progress.currentFile)")
                    .font(.system(.caption, design: .monospaced))
                Button("Cancel", role: .destructive) { session.importer.cancel() }
            }
        case .scanning:
            ProgressView("Scanning…")
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text(message).foregroundStyle(.red).font(.callout)
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
            Button("Import from a folder…") { isChoosingFolder = true }
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
