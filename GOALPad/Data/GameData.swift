import Foundation
import OSLog

/// The exact prepared-data files required by one app-selected game profile.
nonisolated struct GameDataManifest: Equatable, Sendable {
    let bootArchives: [String]
    let levelArchives: [String]
    let levelGeometry: [String]
    let audioExtensions: [String]

    /// The no-dialogue base-retail Jak 1 install consumed by the playable Eco target.
    static let jak1 = GameDataManifest(
        bootArchives: ["KERNEL.CGO", "GAME.CGO"],
        levelArchives: [
            "BEA.DGO", "CIT.DGO", "DAR.DGO", "DEM.DGO", "FIC.DGO", "FIN.DGO", "INT.DGO",
            "JUB.DGO", "JUN.DGO", "LAV.DGO", "MAI.DGO", "MIS.DGO", "OGR.DGO", "ROB.DGO",
            "ROL.DGO", "SNO.DGO", "SUB.DGO", "SUN.DGO", "SWA.DGO", "TIT.DGO", "TRA.DGO",
            "VI1.DGO", "VI2.DGO", "VI3.DGO",
        ],
        levelGeometry: [
            "GAME.fr3", "beach.fr3", "citadel.fr3", "darkcave.fr3", "demo.fr3",
            "finalboss.fr3", "firecanyon.fr3", "intro.fr3", "jungle.fr3", "jungleb.fr3",
            "lavatube.fr3", "maincave.fr3", "misty.fr3", "ogre.fr3", "robocave.fr3",
            "rolling.fr3", "snow.fr3", "sunken.fr3", "sunkenb.fr3", "swamp.fr3", "title.fr3",
            "training.fr3", "village1.fr3", "village2.fr3", "village3.fr3",
        ],
        audioExtensions: ["SBK", "MUS"]
    )

    /// Only the files proven necessary for the existing Jak II kernel/GAME bootstrap frontier.
    /// This is deliberately not a full retail-data or gameplay-ready manifest.
    static let jak2Bootstrap = GameDataManifest(
        bootArchives: ["KERNEL.CGO", "GAME.CGO"],
        levelArchives: [],
        levelGeometry: ["GAME.fr3"],
        audioExtensions: ["SBK", "MUS"]
    )
}

/// A single-game data/import contract. The public Eco target remains Jak 1 unless a future target
/// explicitly defines `GOALPAD_JAK2`; this source change does not add that target or its runtime.
nonisolated struct GameDataProfile: Equatable, Sendable {
    nonisolated enum Identifier: String, Sendable {
        case jak1
        case jak2
    }

    nonisolated enum Readiness: Sendable {
        case gameplay
        case bootstrapOnly
    }

    let identifier: Identifier
    let displayName: String
    let gameDirectoryName: String
    let preparedDirectoryName: String
    let manifest: GameDataManifest
    let readiness: Readiness
    let supportsRawMediaPreparation: Bool
    let supportsRuntimeLaunch: Bool

    var preparedFolderName: String { "out/\(preparedDirectoryName)" }

    static let jak1 = GameDataProfile(
        identifier: .jak1,
        displayName: "Jak 1",
        gameDirectoryName: "Jak1",
        preparedDirectoryName: "jak1",
        manifest: .jak1,
        readiness: .gameplay,
        supportsRawMediaPreparation: true,
        supportsRuntimeLaunch: true
    )

    static let jak2 = GameDataProfile(
        identifier: .jak2,
        displayName: "Jak II",
        gameDirectoryName: "Jak2",
        preparedDirectoryName: "jak2",
        manifest: .jak2Bootstrap,
        readiness: .bootstrapOnly,
        supportsRawMediaPreparation: false,
        supportsRuntimeLaunch: false
    )

    #if GOALPAD_JAK2
    static let active = jak2
    #else
    static let active = jak1
    #endif
}

/// Where the player's own prepared data for the active single-game profile lives on the device.
///
/// No game data ships with GOALPad and none is ever downloaded. The player extracts their own
/// legally obtained copy with the OpenGOAL tools and puts the resulting `iso/` and `fr3/`
/// directories here. The directory is inside `Documents/` so `UIFileSharingEnabled` exposes it to
/// Finder and the Files app, which is how ~1.5 GB gets onto an iPad without the app copying it
/// twice.
nonisolated enum GameDataLayout {
    static let isoDirectoryName = "iso"
    static let fr3DirectoryName = "fr3"

    static var gameDirectoryName: String { GameDataProfile.active.gameDirectoryName }

    static var documentsDirectory: URL {
        // Documents always exists for an iOS app; a failure here means the container is broken.
        (try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                      appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Documents")
    }

    static var gameDirectory: URL {
        gameDirectory(for: .active, in: documentsDirectory)
    }

    static var isoDirectory: URL {
        isoDirectory(for: .active, in: documentsDirectory)
    }

    static var fr3Directory: URL {
        fr3Directory(for: .active, in: documentsDirectory)
    }

    static func gameDirectory(for profile: GameDataProfile, in documentsDirectory: URL) -> URL {
        documentsDirectory.appending(path: profile.gameDirectoryName, directoryHint: .isDirectory)
    }

    static func isoDirectory(for profile: GameDataProfile, in documentsDirectory: URL) -> URL {
        gameDirectory(for: profile, in: documentsDirectory)
            .appending(path: isoDirectoryName, directoryHint: .isDirectory)
    }

    static func fr3Directory(for profile: GameDataProfile, in documentsDirectory: URL) -> URL {
        gameDirectory(for: profile, in: documentsDirectory)
            .appending(path: fr3DirectoryName, directoryHint: .isDirectory)
    }

    /// Create the layout so it is visible in Files before the player has copied anything in, and
    /// keep 1.5 GB of re-creatable data out of iCloud and iTunes backups.
    static func prepare(profile: GameDataProfile = .active) throws {
        let manager = FileManager.default
        let gameDirectory = gameDirectory(for: profile, in: documentsDirectory)
        let isoDirectory = gameDirectory.appending(
            path: isoDirectoryName, directoryHint: .isDirectory)
        let fr3Directory = gameDirectory.appending(
            path: fr3DirectoryName, directoryHint: .isDirectory)
        for directory in [gameDirectory, isoDirectory, fr3Directory] {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        var directory = gameDirectory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
    }
}

/// The result of looking at what is actually on disk. Nothing here guesses: every count and every
/// name comes from the file system.
nonisolated struct GameDataReport: Sendable {
    nonisolated enum Status: Sendable {
        /// Neither `iso/` nor `fr3/` has anything in it.
        case empty
        /// Something is there, but the game cannot boot from it.
        case incomplete
        /// Everything the selected profile manifest names is present. For Jak II this means only
        /// the explicitly labeled bootstrap contract, not a gameplay-ready installation.
        case ready
    }

    let profile: GameDataProfile
    var status: Status = .empty
    var missingBootArchives: [String] = []
    var missingLevelArchives: [String] = []
    var missingLevelGeometry: [String] = []
    var isoFileCount = 0
    var fr3FileCount = 0
    var audioBankCount = 0
    var totalBytes: Int64 = 0

    init(profile: GameDataProfile = .active) {
        self.profile = profile
    }

    var canBoot: Bool { missingBootArchives.isEmpty }

    var summary: String {
        switch status {
        case .empty:
            return profile.readiness == .gameplay
                ? "No game data yet."
                : "No Jak II bootstrap data yet."
        case .incomplete where !canBoot:
            return "Cannot boot: \(missingBootArchives.joined(separator: ", ")) missing from iso/."
        case .incomplete:
            let missing = missingLevelArchives.count + missingLevelGeometry.count
            return profile.readiness == .gameplay
                ? "Boot data is present, but \(missing) level file(s) are missing."
                : "Boot archives are present, but \(missing) required bootstrap file(s) are missing."
        case .ready:
            let counts = "\(isoFileCount) files in iso/, \(fr3FileCount) in fr3/, "
                + ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file) + "."
            return profile.readiness == .gameplay
                ? "Complete: " + counts
                : "Bootstrap-ready only: " + counts
                    + " Native Jak II gameplay is not available in this build."
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

/// Reads the layout and reports on it. Off the main actor: it stats a few hundred files.
nonisolated enum GameDataInspector {
    private static let log = Logger(subsystem: "com.zephyrstudiosllc.eco", category: "GameData")

    nonisolated static func inspect() -> GameDataReport {
        inspect(
            gameDirectory: GameDataLayout.gameDirectory(for: .active,
                                                        in: GameDataLayout.documentsDirectory),
            profile: .active
        )
    }

    nonisolated static func inspect(
        gameDirectory: URL,
        profile: GameDataProfile = .active
    ) -> GameDataReport {
        var report = GameDataReport(profile: profile)
        let manifest = profile.manifest

        let isoDirectory = gameDirectory.appending(
            path: GameDataLayout.isoDirectoryName, directoryHint: .isDirectory)
        let fr3Directory = gameDirectory.appending(
            path: GameDataLayout.fr3DirectoryName, directoryHint: .isDirectory)

        let iso = names(in: isoDirectory)
        let fr3 = names(in: fr3Directory)
        report.isoFileCount = iso.count
        report.fr3FileCount = fr3.count
        report.audioBankCount = iso.filter {
            manifest.audioExtensions.contains(($0 as NSString).pathExtension.uppercased())
        }.count

        report.missingBootArchives = manifest.bootArchives.filter { !iso.contains($0) }
        report.missingLevelArchives = manifest.levelArchives.filter { !iso.contains($0) }
        report.missingLevelGeometry = manifest.levelGeometry.filter { !fr3.contains($0) }

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
