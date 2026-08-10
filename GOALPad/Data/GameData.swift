import Foundation
import OSLog

/// Where the player's own prepared Jak 1 data lives on the device, and whether what is there can
/// actually boot the game.
///
/// No game data ships with GOALPad and none is ever downloaded. The player extracts their own
/// legally obtained copy with the OpenGOAL tools and puts the resulting `iso/` and `fr3/`
/// directories here. The directory is inside `Documents/` so `UIFileSharingEnabled` exposes it to
/// Finder and the Files app, which is how ~1.5 GB gets onto an iPad without the app copying it
/// twice.
nonisolated enum GameDataLayout {
    static let gameDirectoryName = "Jak1"
    static let isoDirectoryName = "iso"
    static let fr3DirectoryName = "fr3"

    static var documentsDirectory: URL {
        // Documents always exists for an iOS app; a failure here means the container is broken.
        (try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                      appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Documents")
    }

    static var gameDirectory: URL {
        documentsDirectory.appending(path: gameDirectoryName, directoryHint: .isDirectory)
    }

    static var isoDirectory: URL {
        gameDirectory.appending(path: isoDirectoryName, directoryHint: .isDirectory)
    }

    static var fr3Directory: URL {
        gameDirectory.appending(path: fr3DirectoryName, directoryHint: .isDirectory)
    }

    /// Create the layout so it is visible in Files before the player has copied anything in, and
    /// keep 1.5 GB of re-creatable data out of iCloud and iTunes backups.
    static func prepare() throws {
        let manager = FileManager.default
        for directory in [gameDirectory, isoDirectory, fr3Directory] {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        var directory = gameDirectory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
    }
}

/// What the game needs to find. These are the archive names the OpenGOAL Jak 1 extraction produces
/// in `$OUT/iso` and `$OUT/fr3`; the runtime opens them by these exact names.
nonisolated enum GameDataManifest {
    /// The two archives the boot path loads before anything else exists.
    static let bootArchives = ["KERNEL.CGO", "GAME.CGO"]

    /// Retail DGOs loaded by normal title/gameplay. The repository example `TSZ.DGO` is not part
    /// of the no-dialogue `jak1-base-retail` install profile.
    static let levelArchives = [
        "BEA.DGO", "CIT.DGO", "DAR.DGO", "DEM.DGO", "FIC.DGO", "FIN.DGO", "INT.DGO", "JUB.DGO",
        "JUN.DGO", "LAV.DGO", "MAI.DGO", "MIS.DGO", "OGR.DGO", "ROB.DGO", "ROL.DGO", "SNO.DGO",
        "SUB.DGO", "SUN.DGO", "SWA.DGO", "TIT.DGO", "TRA.DGO", "VI1.DGO", "VI2.DGO",
        "VI3.DGO",
    ]

    /// Extracted level geometry and textures for the renderer, plus the shared `GAME.fr3`.
    static let levelGeometry = [
        "GAME.fr3", "beach.fr3", "citadel.fr3", "darkcave.fr3", "demo.fr3", "finalboss.fr3",
        "firecanyon.fr3", "intro.fr3", "jungle.fr3", "jungleb.fr3", "lavatube.fr3", "maincave.fr3",
        "misty.fr3", "ogre.fr3", "robocave.fr3", "rolling.fr3", "snow.fr3", "sunken.fr3",
        "sunkenb.fr3", "swamp.fr3", "title.fr3", "training.fr3", "village1.fr3", "village2.fr3",
        "village3.fr3",
    ]

    /// Sound banks and music, which the sound RPC loads out of `iso/`.
    static let audioExtensions = ["SBK", "MUS"]
}

/// The result of looking at what is actually on disk. Nothing here guesses: every count and every
/// name comes from the file system.
nonisolated struct GameDataReport: Sendable {
    nonisolated enum Status: Equatable, Sendable {
        /// The app has not finished its first inspection of the local install yet.
        case checking
        /// Neither `iso/` nor `fr3/` has anything in it.
        case empty
        /// Something is there, but the game cannot boot from it.
        case incomplete
        /// Everything the manifest names is present.
        case ready
    }

    var status: Status = .checking
    var missingBootArchives: [String] = []
    var missingLevelArchives: [String] = []
    var missingLevelGeometry: [String] = []
    var isoFileCount = 0
    var fr3FileCount = 0
    var audioBankCount = 0
    var totalBytes: Int64 = 0

    var canBoot: Bool {
        switch status {
        case .checking, .empty:
            false
        case .incomplete, .ready:
            missingBootArchives.isEmpty
        }
    }

    var summary: String {
        switch status {
        case .checking:
            return "Checking local game data."
        case .empty:
            return "No game data yet."
        case .incomplete where !canBoot:
            return "Cannot boot: \(missingBootArchives.joined(separator: ", ")) missing from iso/."
        case .incomplete:
            let missing = missingLevelArchives.count + missingLevelGeometry.count
            return "Boot data is present, but \(missing) level file(s) are missing."
        case .ready:
            return "Complete: \(isoFileCount) files in iso/, \(fr3FileCount) in fr3/, "
                + ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file) + "."
        }
    }
}

/// Keeps external Files or Finder transfers visible when the launcher returns to the foreground
/// without racing an active game startup or session.
nonisolated enum GameDataRefreshPolicy {
    nonisolated static func shouldRefreshOnActivation(
        isRunning: Bool,
        isBooting: Bool,
        isPreparingGameplay: Bool
    ) -> Bool {
        !isRunning && !isBooting && !isPreparingGameplay
    }
}

@MainActor
enum GameSessionPreparation {
    static func run(
        refreshDataReport: @MainActor @Sendable () async -> Void,
        prepareSettings: @MainActor @Sendable () async -> Void,
        prepareSaves: @MainActor @Sendable () async -> Void
    ) async {
        await refreshDataReport()
        async let settingsPreparation: Void = prepareSettings()
        await prepareSaves()
        await settingsPreparation
    }
}

/// Reads the layout and reports on it. Off the main actor: it stats a few hundred files.
nonisolated enum GameDataInspector {
    private static let log = Logger(subsystem: "com.zephyrstudiosllc.eco", category: "GameData")

    nonisolated static func inspect() -> GameDataReport {
        inspect(gameDirectory: GameDataLayout.gameDirectory)
    }

    nonisolated static func inspect(gameDirectory: URL) -> GameDataReport {
        var report = GameDataReport()

        let isoDirectory = gameDirectory.appending(
            path: GameDataLayout.isoDirectoryName, directoryHint: .isDirectory)
        let fr3Directory = gameDirectory.appending(
            path: GameDataLayout.fr3DirectoryName, directoryHint: .isDirectory)

        let iso = names(in: isoDirectory)
        let fr3 = names(in: fr3Directory)
        report.isoFileCount = iso.count
        report.fr3FileCount = fr3.count
        report.audioBankCount = iso.filter {
            GameDataManifest.audioExtensions.contains(($0 as NSString).pathExtension.uppercased())
        }.count

        report.missingBootArchives = GameDataManifest.bootArchives.filter { !iso.contains($0) }
        report.missingLevelArchives = GameDataManifest.levelArchives.filter { !iso.contains($0) }
        report.missingLevelGeometry = GameDataManifest.levelGeometry.filter { !fr3.contains($0) }

        if iso.isEmpty && fr3.isEmpty {
            report.status = .empty
        } else if report.missingBootArchives.isEmpty && report.missingLevelArchives.isEmpty
            && report.missingLevelGeometry.isEmpty
        {
            report.status = .ready
        } else {
            report.status = .incomplete
        }

        report.totalBytes = size(of: isoDirectory) + size(of: fr3Directory)

        log.notice("Game data at \(gameDirectory.path, privacy: .public): \(report.summary, privacy: .public)")
        return report
    }

    nonisolated private static func names(in directory: URL) -> Set<String> {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        return Set((contents ?? []).map(\.lastPathComponent))
    }

    nonisolated private static func size(of directory: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.fileSizeKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        else {
            return 0
        }
        return contents.reduce(0) { total, url in
            total + Int64((try? url.resourceValues(forKeys: keys).fileSize) ?? 0)
        }
    }
}
