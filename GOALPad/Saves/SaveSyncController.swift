import Foundation
import SwiftUI

nonisolated enum SaveDataLayout {
    static var applicationSupportDirectory: URL {
        (try? FileManager.default.url(for: .applicationSupportDirectory,
                                      in: .userDomainMask, appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appending(path: "Library/Application Support", directoryHint: .isDirectory)
    }

    /// OpenGOAL's existing desktop-compatible memcard directory. The kernel keeps using this
    /// exact local path; iCloud is never passed to native gameplay code.
    static var localSavesDirectory: URL {
        applicationSupportDirectory
            .appending(path: "OpenGOAL/jak1/saves", directoryHint: .isDirectory)
    }

    static var localConflictsDirectory: URL {
        applicationSupportDirectory
            .appending(path: "GOALPad/SaveConflicts", directoryHint: .isDirectory)
    }

    static var stateFile: URL {
        applicationSupportDirectory
            .appending(path: "GOALPad/SaveSync/state-v1.json", directoryHint: .notDirectory)
    }

    static func cloudLocations() -> CloudSaveLocations? {
        let manager = FileManager.default
        guard let identityToken = manager.ubiquityIdentityToken,
              let accountIdentifier = try? NSKeyedArchiver.archivedData(
                  withRootObject: identityToken, requiringSecureCoding: false),
              let container = manager.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        let documents = container.appending(path: "Documents", directoryHint: .isDirectory)
        return CloudSaveLocations(
            savesRoot: documents.appending(path: "OpenGOAL/jak1/saves",
                                            directoryHint: .isDirectory),
            conflictsRoot: documents.appending(path: "GOALPad/SaveConflicts",
                                                directoryHint: .isDirectory),
            accountIdentifier: accountIdentifier)
    }
}

@MainActor
@Observable
final class SaveSyncController {
    enum Status: Equatable {
        case disabled
        case waiting
        case syncing
        case unavailable
        case synced(Date, uploaded: Int, downloaded: Int)
        case conflict(Date, files: [String])
        case failed(String)
    }

    private static let enabledDefaultsKey = "iCloudSavesEnabled"

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledDefaultsKey)
            if isEnabled {
                status = .waiting
                Task { await syncNow() }
            } else {
                frameCheckTask?.cancel()
                frameCheckTask = nil
                status = .disabled
            }
        }
    }
    private(set) var status: Status

    private let defaults: UserDefaults
    private let engine: SaveSyncEngine
    private var isWorking = false
    private var frameCheckTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, engine: SaveSyncEngine? = nil) {
        self.defaults = defaults
        let enabled: Bool
        if defaults.object(forKey: Self.enabledDefaultsKey) == nil {
            enabled = true
        } else {
            enabled = defaults.bool(forKey: Self.enabledDefaultsKey)
        }
        isEnabled = enabled
        status = enabled ? .waiting : .disabled
        self.engine = engine ?? SaveSyncEngine(configuration: .init(
            localRoot: SaveDataLayout.localSavesDirectory,
            localConflictsRoot: SaveDataLayout.localConflictsDirectory,
            stateFile: SaveDataLayout.stateFile,
            cloudLocations: { SaveDataLayout.cloudLocations() },
            coordinateCloudAccess: true))
    }

    func prepare() async {
        guard isEnabled else { return }
        await syncNow()
    }

    func syncNow() async {
        guard isEnabled, !isWorking else { return }
        isWorking = true
        status = .syncing
        defer { isWorking = false }
        do {
            let outcome = try await engine.sync()
            guard isEnabled else {
                status = .disabled
                return
            }
            apply(outcome)
        } catch {
            guard isEnabled else {
                status = .disabled
                return
            }
            status = .failed(error.localizedDescription)
        }
    }

    /// Called after completed gameplay frames. The native save is synchronous, so any successful
    /// memcard write is closed before this check runs. Coalescing keeps file I/O off the hot loop.
    func gameplayFrameCompleted() {
        guard isEnabled, !isWorking, frameCheckTask == nil else { return }
        frameCheckTask = Task { [weak self] in
            guard let self else { return }
            defer { frameCheckTask = nil }
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard isEnabled, !Task.isCancelled else { return }
            do {
                if let outcome = try await engine.syncIfLocalFilesChanged() {
                    guard isEnabled else {
                        status = .disabled
                        return
                    }
                    apply(outcome)
                }
            } catch {
                guard isEnabled else {
                    status = .disabled
                    return
                }
                status = .failed(error.localizedDescription)
            }
        }
    }

    var summary: String {
        switch status {
        case .disabled: return "Off — saves stay on this device"
        case .waiting: return "Waiting to sync"
        case .syncing: return "Syncing…"
        case .unavailable: return "iCloud unavailable — using local saves"
        case .synced(_, let uploaded, let downloaded):
            if uploaded == 0 && downloaded == 0 { return "Up to date" }
            return "Synced: \(uploaded) uploaded, \(downloaded) downloaded"
        case .conflict(_, let files):
            return "Conflict: preserved both versions of \(files.count) save file(s)"
        case .failed(let message): return "Sync issue: \(message)"
        }
    }

    var lastSyncDate: Date? {
        switch status {
        case .synced(let date, _, _), .conflict(let date, _): return date
        default: return nil
        }
    }

    var conflictFiles: [String] {
        guard case .conflict(_, let files) = status else { return [] }
        return files
    }

    private func apply(_ outcome: SaveSyncOutcome) {
        guard outcome.availability == .available else {
            status = .unavailable
            return
        }
        if outcome.conflicts.isEmpty {
            status = .synced(outcome.completedAt, uploaded: outcome.uploaded,
                             downloaded: outcome.downloaded)
        } else {
            status = .conflict(outcome.completedAt, files: outcome.conflicts)
        }
    }
}

struct SaveSettingsView: View {
    @Bindable var sync: SaveSyncController

    var body: some View {
        Form {
            Section("iCloud Saves") {
                Toggle("Sync saves with iCloud", isOn: $sync.isEnabled)
                Label(sync.summary, systemImage: statusSymbol)
                    .foregroundStyle(statusColor)
                if let date = sync.lastSyncDate {
                    LabeledContent("Last sync", value: date.formatted(date: .abbreviated,
                                                                      time: .shortened))
                }
                Button("Sync Now") { Task { await sync.syncNow() } }
                    .disabled(!sync.isEnabled || sync.status == .syncing)
            }

            if !sync.conflictFiles.isEmpty {
                Section("Conflicts") {
                    Text("Eco Pro kept gameplay on the local save and preserved both versions. "
                         + "Conflict copies are stored outside the gameplay save directory.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    ForEach(sync.conflictFiles, id: \.self) {
                        Text($0).font(.system(.caption, design: .monospaced))
                    }
                }
            }
        }
        .navigationTitle("Settings")
    }

    private var statusSymbol: String {
        switch sync.status {
        case .disabled: return "icloud.slash"
        case .waiting, .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .unavailable, .failed: return "exclamationmark.icloud"
        case .synced: return "checkmark.icloud"
        case .conflict: return "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        switch sync.status {
        case .unavailable: return .secondary
        case .failed, .conflict: return .orange
        default: return .primary
        }
    }
}
