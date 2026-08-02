// Deterministic host checks for iCloud save mirroring and conflict handling.
//
// These use synthetic temporary directories and never access an iCloud account or game data.

import Foundation

private let memcardDirectory = "BASCUS-97124AYBABTU!"
private let bankPath = memcardDirectory + "/bank0.bin"
private var failures = 0
private var modificationTick: TimeInterval = 1_800_000_000

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("  ok   \(message)")
    } else {
        print("  FAIL \(message)")
        failures += 1
    }
}

private final class Fixture {
    let root: URL
    let local: URL
    let localConflicts: URL
    let cloud: URL
    let cloudConflicts: URL
    let state: URL
    let engine: SaveSyncEngine

    init(cloudAvailable: Bool = true, accountIdentifier: String = "account-a",
         fileSettleDelay: Duration = .milliseconds(1)) throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "goalpad-save-sync-\(UUID().uuidString)", directoryHint: .isDirectory)
        local = root.appending(path: "local/OpenGOAL/jak1/saves", directoryHint: .isDirectory)
        localConflicts = root.appending(path: "local/GOALPad/SaveConflicts",
                                        directoryHint: .isDirectory)
        cloud = root.appending(path: "cloud/Documents/OpenGOAL/jak1/saves",
                               directoryHint: .isDirectory)
        cloudConflicts = root.appending(path: "cloud/Documents/GOALPad/SaveConflicts",
                                        directoryHint: .isDirectory)
        state = root.appending(path: "local/GOALPad/SaveSync/state-v1.json",
                               directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let locations = CloudSaveLocations(
            savesRoot: cloud,
            conflictsRoot: cloudConflicts,
            accountIdentifier: Data(accountIdentifier.utf8))
        engine = SaveSyncEngine(configuration: .init(
            localRoot: local,
            localConflictsRoot: localConflicts,
            stateFile: state,
            cloudLocations: { cloudAvailable ? locations : nil },
            coordinateCloudAccess: false,
            fileSettleDelay: fileSettleDelay))
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }
}

private func file(_ relativePath: String, under root: URL) -> URL {
    root.appending(path: relativePath, directoryHint: .notDirectory)
}

private func write(_ text: String, to relativePath: String = bankPath, under root: URL) throws {
    let url = file(relativePath, under: root)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url, options: .atomic)
    modificationTick += 1
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970:
                                                                      modificationTick)],
                                          ofItemAtPath: url.path)
}

private func read(_ relativePath: String = bankPath, under root: URL) -> String? {
    guard let data = try? Data(contentsOf: file(relativePath, under: root)) else { return nil }
    return String(decoding: data, as: UTF8.self)
}

private func regularFiles(under root: URL) -> [URL] {
    guard let enumerator = FileManager.default.enumerator(at: root,
                                                          includingPropertiesForKeys: [.isRegularFileKey])
    else { return [] }
    return enumerator.compactMap { item in
        guard let url = item as? URL,
              (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        else { return nil }
        return url
    }
}

private func unavailableKeepsLocalSaves() async throws {
    print("iCloud being unavailable is a local-only success")
    let fixture = try Fixture(cloudAvailable: false)
    try write("local-save", under: fixture.local)

    let outcome = try await fixture.engine.sync()
    check(outcome.availability == .unavailable, "unavailable is reported without throwing")
    check(read(under: fixture.local) == "local-save", "the gameplay save is untouched")
    check(!FileManager.default.fileExists(atPath: fixture.cloud.path),
          "no cloud directory is required")
}

private func localOnlyUploadsDesktopLayout() async throws {
    print("a local OpenGOAL memcard is mirrored without changing its layout")
    let fixture = try Fixture()
    try write("ipad-save", under: fixture.local)

    let outcome = try await fixture.engine.sync()
    check(outcome.uploaded == 1 && outcome.downloaded == 0, "one local bank uploads")
    check(read(under: fixture.cloud) == "ipad-save",
          "BASCUS-97124AYBABTU!/bank0.bin is byte-compatible in iCloud")
    check(outcome.conflicts.isEmpty, "a one-sided save is not a conflict")
}

private func cloudOnlyDownloadsBeforeGameplay() async throws {
    print("an iCloud-only memcard becomes a local gameplay save")
    let fixture = try Fixture()
    try write("ipad-cloud-save", under: fixture.cloud)

    let outcome = try await fixture.engine.sync()
    check(outcome.downloaded == 1 && outcome.uploaded == 0, "one cloud bank downloads")
    check(read(under: fixture.local) == "ipad-cloud-save", "the local OpenGOAL path receives it")
}

private func changedSideWinsAgainstBaseline() async throws {
    print("a known unchanged side can safely receive the changed side")
    let fixture = try Fixture()
    try write("baseline", under: fixture.local)
    _ = try await fixture.engine.sync()

    try write("new-local-save", under: fixture.local)
    let localOutcome = try await fixture.engine.syncIfLocalFilesChanged()
    check(localOutcome?.uploaded == 1, "a completed local write triggers an upload")
    check(read(under: fixture.cloud) == "new-local-save", "the cloud mirror advances")

    try write("new-cloud-save", under: fixture.cloud)
    let cloudOutcome = try await fixture.engine.sync()
    check(cloudOutcome.downloaded == 1, "a changed cloud bank downloads on the next sync")
    check(read(under: fixture.local) == "new-cloud-save", "the local gameplay copy advances")
}

private func initialDivergencePreservesBoth() async throws {
    print("unrelated local and cloud saves never overwrite one another")
    let fixture = try Fixture()
    try write("local-version", under: fixture.local)
    try write("cloud-version", under: fixture.cloud)

    let outcome = try await fixture.engine.sync()
    check(outcome.conflicts == [bankPath], "the divergent bank is surfaced as a conflict")
    check(read(under: fixture.local) == "local-version", "the gameplay copy stays local")
    check(read(under: fixture.cloud) == "cloud-version", "the canonical cloud copy stays intact")

    let localCopies = regularFiles(under: fixture.localConflicts)
    let cloudCopies = regularFiles(under: fixture.cloudConflicts)
    check(localCopies.count == 1, "the iCloud version has a local conflict copy")
    check(cloudCopies.count == 1, "the local version has an iCloud conflict copy")
    check(localCopies.first.flatMap { try? Data(contentsOf: $0) } == Data("cloud-version".utf8),
          "the local conflict copy contains the iCloud bytes")
    check(cloudCopies.first.flatMap { try? Data(contentsOf: $0) } == Data("local-version".utf8),
          "the iCloud conflict copy contains the local bytes")
}

private func twoSidedChangePreservesBoth() async throws {
    print("two changes after a shared baseline are also a conflict")
    let fixture = try Fixture()
    try write("baseline", under: fixture.local)
    _ = try await fixture.engine.sync()
    try write("new-local", under: fixture.local)
    try write("new-cloud", under: fixture.cloud)

    let outcome = try await fixture.engine.sync()
    check(outcome.conflicts == [bankPath], "two-sided divergence is reported")
    check(read(under: fixture.local) == "new-local", "two-sided merge does not replace local")
    check(read(under: fixture.cloud) == "new-cloud", "two-sided merge does not replace cloud")
}

private func missingSideIsRestored() async throws {
    print("a missing file is restored instead of propagating a deletion")
    let fixture = try Fixture()
    try write("save", under: fixture.local)
    _ = try await fixture.engine.sync()
    try FileManager.default.removeItem(at: file(bankPath, under: fixture.local))

    let outcome = try await fixture.engine.syncIfLocalFilesChanged()
    check(outcome?.downloaded == 1, "the surviving cloud bank is downloaded")
    check(read(under: fixture.local) == "save", "the local save is restored")
}

private func accountSwitchCannotReuseAnOldBaseline() async throws {
    print("switching iCloud accounts invalidates the old merge baseline")
    let fixture = try Fixture(accountIdentifier: "account-a")
    try write("account-a-save", under: fixture.local)
    _ = try await fixture.engine.sync()

    let accountBCloud = fixture.root.appending(path: "account-b/Documents/OpenGOAL/jak1/saves",
                                                directoryHint: .isDirectory)
    let accountBConflicts = fixture.root.appending(path: "account-b/Documents/GOALPad/SaveConflicts",
                                                    directoryHint: .isDirectory)
    try write("account-b-save", under: accountBCloud)
    let accountBLocations = CloudSaveLocations(
        savesRoot: accountBCloud,
        conflictsRoot: accountBConflicts,
        accountIdentifier: Data("account-b".utf8))
    let accountBEngine = SaveSyncEngine(configuration: .init(
        localRoot: fixture.local,
        localConflictsRoot: fixture.localConflicts,
        stateFile: fixture.state,
        cloudLocations: { accountBLocations },
        coordinateCloudAccess: false,
        fileSettleDelay: .milliseconds(1)))

    let outcome = try await accountBEngine.sync()
    check(outcome.conflicts == [bankPath], "the new account is compared without account A's baseline")
    check(read(under: fixture.local) == "account-a-save", "the local account A save stays active")
    check(read(under: accountBCloud) == "account-b-save", "the account B cloud save stays intact")
}

private func changingFileIsReadAgainBeforeUpload() async throws {
    print("a save that changes during a snapshot is read again before upload")
    let fixture = try Fixture(fileSettleDelay: .milliseconds(50))
    try write("first-write", under: fixture.local)
    let writer = Task {
        try await Task.sleep(for: .milliseconds(10))
        try write("completed-write", under: fixture.local)
    }

    let outcome = try await fixture.engine.sync()
    try await writer.value
    check(outcome.uploaded == 1, "the stable completed save uploads once")
    check(read(under: fixture.cloud) == "completed-write",
          "the first changing snapshot never reaches iCloud")
}

private func newerSaveDuringCloudWorkGetsANextSync() async throws {
    print("a save completed after its snapshot remains pending for the next sync")
    let fixture = try Fixture(fileSettleDelay: .milliseconds(50))
    try write("first-save", under: fixture.local)
    for index in 1...6 {
        try write("cloud-\(index)", to: memcardDirectory + "/bank\(index).bin",
                  under: fixture.cloud)
    }
    let writer = Task {
        try await Task.sleep(for: .milliseconds(120))
        try write("second-save", under: fixture.local)
    }

    _ = try await fixture.engine.sync()
    try await writer.value
    check(read(under: fixture.cloud) == "first-save",
          "the already snapshotted version is the first mirror")
    let followUp = try await fixture.engine.syncIfLocalFilesChanged()
    check(followUp?.uploaded == 1, "the later completed save remains detectable")
    check(read(under: fixture.cloud) == "second-save", "the next sync mirrors the later save")
}

@main
private struct SaveSyncCheck {
    static func main() async {
        do {
            try await unavailableKeepsLocalSaves()
            try await localOnlyUploadsDesktopLayout()
            try await cloudOnlyDownloadsBeforeGameplay()
            try await changedSideWinsAgainstBaseline()
            try await initialDivergencePreservesBoth()
            try await twoSidedChangePreservesBoth()
            try await missingSideIsRestored()
            try await accountSwitchCannotReuseAnOldBaseline()
            try await changingFileIsReadAgainBeforeUpload()
            try await newerSaveDuringCloudWorkGetsANextSync()
        } catch {
            print("  FAIL unexpected error: \(error)")
            failures += 1
        }

        if failures == 0 {
            print("save sync checks passed")
        } else {
            print("save sync checks failed: \(failures)")
            Foundation.exit(1)
        }
    }
}
