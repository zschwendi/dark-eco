import Foundation
import ImageIO
import Observation

/// Fits the complete three-title shelf inside the launcher proposal without scrolling.
nonisolated struct GameLibraryShelfLayout: Equatable, Sendable {
    static let titleCount = 3
    static let coverAspectRatio: CGFloat = 2 / 3
    static let maximumCoverWidth: CGFloat = 210
    static let regularPortraitMaximumCoverWidth: CGFloat = 250
    static let compactSpacing: CGFloat = 8
    static let compactOuterPadding: CGFloat = 12
    static let regularVerticalPadding: CGFloat = 24
    static let regularMinimumGutter: CGFloat = 24
    static let cardHorizontalInset: CGFloat = 6
    static let cardBottomInset: CGFloat = 20
    static let cardFooterHeight: CGFloat = 108

    let coverSize: CGSize
    let spacing: CGFloat
    let outerPadding: CGFloat
    let gutter: CGFloat
    let usesFlexibleGutters: Bool
    private let containerWidth: CGFloat

    init(containerSize: CGSize) {
        self.init(containerSize: containerSize, usesRegularWidth: containerSize.width >= 700)
    }

    init(containerSize: CGSize, usesRegularWidth: Bool) {
        let width = max(0, containerSize.width)
        let height = max(0, containerSize.height)
        containerWidth = width
        let regular = usesRegularWidth
        usesFlexibleGutters = regular
        spacing = regular ? 0 : Self.compactSpacing
        outerPadding = regular ? 0 : min(Self.compactOuterPadding, width / 2)
        gutter = regular ? Self.regularMinimumGutter : Self.compactSpacing

        let horizontalChrome: CGFloat
        let verticalPadding: CGFloat
        if regular {
            horizontalChrome = gutter * CGFloat(Self.titleCount + 1)
                + Self.cardHorizontalInset * 2 * CGFloat(Self.titleCount)
            verticalPadding = Self.regularVerticalPadding
        } else {
            horizontalChrome = outerPadding * 2
                + spacing * CGFloat(Self.titleCount - 1)
                + Self.cardHorizontalInset * 2 * CGFloat(Self.titleCount)
            verticalPadding = outerPadding
        }
        let widthBound = max(0, (width - horizontalChrome) / CGFloat(Self.titleCount))
        let availableCoverHeight = max(0, height - verticalPadding * 2 - Self.cardFooterHeight)
        let heightBound = availableCoverHeight * Self.coverAspectRatio
        let coverWidth = regular
            ? min(widthBound, heightBound)
            : min(Self.maximumCoverWidth, widthBound, heightBound)
        coverSize = CGSize(width: coverWidth,
                           height: coverWidth / Self.coverAspectRatio)
    }

    var cardWidth: CGFloat {
        coverSize.width + Self.cardHorizontalInset * 2
    }

    var shelfWidth: CGFloat {
        if usesFlexibleGutters {
            return containerWidth
        }
        return cardWidth * CGFloat(Self.titleCount) + spacing * CGFloat(Self.titleCount - 1)
    }

    var shelfHeight: CGFloat {
        coverSize.height + Self.cardFooterHeight
    }
}

/// Gives compact landscape phones readable artwork-left cards, scrolling only when three cards
/// cannot fit at the minimum width needed for their title and status details.
nonisolated struct GameLibraryCompactLandscapeLayout: Equatable, Sendable {
    static let titleCount = GameLibraryShelfLayout.titleCount
    static let spacing: CGFloat = 12
    static let outerPadding: CGFloat = 12
    static let minimumCardWidth: CGFloat = 360
    static let maximumCardWidth: CGFloat = 420
    static let minimumCoverHeight: CGFloat = 180
    static let maximumCoverHeight: CGFloat = 280
    static let verticalReserve: CGFloat = 72
    static let artworkDetailsSpacing: CGFloat = 12

    let cardWidth: CGFloat
    let coverSize: CGSize
    let shelfWidth: CGFloat
    let usesHorizontalScroll: Bool

    init(containerSize: CGSize) {
        let width = max(0, containerSize.width)
        let height = max(0, containerSize.height)
        let availableWidth = max(0, width - Self.outerPadding * 2)
        let naturalCardWidth = max(
            0,
            (availableWidth - Self.spacing * CGFloat(Self.titleCount - 1))
                / CGFloat(Self.titleCount)
        )
        cardWidth = min(Self.maximumCardWidth,
                        max(Self.minimumCardWidth, naturalCardWidth))
        usesHorizontalScroll = naturalCardWidth < Self.minimumCardWidth
        shelfWidth = cardWidth * CGFloat(Self.titleCount)
            + Self.spacing * CGFloat(Self.titleCount - 1)

        let coverHeight = min(Self.maximumCoverHeight,
                              max(Self.minimumCoverHeight,
                                  height - Self.verticalReserve))
        coverSize = CGSize(width: coverHeight * GameLibraryShelfLayout.coverAspectRatio,
                           height: coverHeight)
    }

    var detailsWidth: CGFloat {
        cardWidth - coverSize.width - Self.artworkDetailsSpacing
            - GameLibraryShelfLayout.cardHorizontalInset * 2
    }
}

/// A larger scrolling library for portrait compact-width phones.
nonisolated struct GameLibraryGridLayout: Equatable, Sendable {
    static let spacing: CGFloat = 16
    static let outerPadding: CGFloat = 16
    static let maximumCardWidth: CGFloat = 320
    static let minimumCardWidth: CGFloat = 250

    let columnCount: Int
    let coverSize: CGSize

    init(containerWidth: CGFloat) {
        let width = max(0, containerWidth)
        let usableWidth = max(0, width - Self.outerPadding * 2)
        let twoColumnWidth = (usableWidth - Self.spacing) / 2
        columnCount = twoColumnWidth >= Self.minimumCardWidth ? 2 : 1
        let cardWidth = min(Self.maximumCardWidth,
                            (usableWidth - Self.spacing * CGFloat(columnCount - 1))
                                / CGFloat(columnCount))
        let coverWidth = max(0, cardWidth - GameLibraryShelfLayout.cardHorizontalInset * 2)
        coverSize = CGSize(width: coverWidth,
                           height: coverWidth / GameLibraryShelfLayout.coverAspectRatio)
    }
}

nonisolated enum GameLibraryTitle: String, CaseIterable, Equatable, Identifiable, Sendable {
    case jak1
    case jak2
    case jak3

    var id: String { rawValue }

    static var active: GameLibraryTitle {
        #if GOALPAD_JAK2
        .jak2
        #else
        .jak1
        #endif
    }

    var name: String {
        switch self {
        case .jak1: "Jak and Daxter: The Precursor Legacy"
        case .jak2: "Jak II"
        case .jak3: "Jak 3"
        }
    }

    var shelfName: String {
        name
    }

    var availabilityLabel: String {
        switch self {
        case .jak1: "Available"
        case .jak2:
            #if GOALPAD_JAK2
            "Experimental"
            #else
            "Coming Soon"
            #endif
        case .jak3: "Planned"
        }
    }

    var fallbackMark: String {
        switch self {
        case .jak1: "I"
        case .jak2: "II"
        case .jak3: "III"
        }
    }
}

nonisolated enum GameLibraryPresentation {
    static func displayTitle(for title: GameLibraryTitle,
                             isValidatedAndLinked: Bool) -> String {
        if title == .active {
            return isValidatedAndLinked ? title.shelfName : "Set Up Game Data"
        }
        return "Future Title"
    }
}

nonisolated enum GameLibraryState: Equatable {
    case notImported
    case preparing(GameLibraryPreparation)
    case ready
    case needsAttention
    case planned
}

nonisolated enum GameLibraryPreparation: Equatable {
    case checkingLocalData
    case importing(Double?)
    case cancellingImport
    case finishingSaveCheck
    case checkingSaves

    var label: String {
        switch self {
        case .checkingLocalData: "Checking Local Data"
        case .importing: "Importing Data"
        case .cancellingImport: "Cancelling Import"
        case .finishingSaveCheck: "Finishing Save Check"
        case .checkingSaves: "Checking Saves"
        }
    }

    var fraction: Double? {
        guard case .importing(let fraction) = self else { return nil }
        return fraction
    }
}

nonisolated enum GameLibraryCardAction: Equatable {
    case start
    case openJak1Setup
    case verifyJak1Data
    case showUnsupported(GameLibraryTitle)

    static func resolve(
        title: GameLibraryTitle,
        state: GameLibraryState,
        activeTitle: GameLibraryTitle = .jak1,
        supportsRuntimeLaunch: Bool = true
    ) -> Self {
        guard title == activeTitle else { return .showUnsupported(title) }
        switch state {
        case .ready:
            return supportsRuntimeLaunch ? .start : .openJak1Setup
        case .preparing(.importing), .preparing(.cancellingImport):
            return .openJak1Setup
        case .preparing(.finishingSaveCheck), .preparing(.checkingSaves):
            return .start
        case .preparing(.checkingLocalData):
            return .verifyJak1Data
        case .notImported, .needsAttention:
            return .verifyJak1Data
        case .planned:
            return .showUnsupported(title)
        }
    }
}

nonisolated enum GameLibraryOfferCopy {
    static func jak1ImportMessage() -> String {
        "Provide compatible game data from a copy you legally own."
    }

    static func importMessage(
        for title: GameLibraryTitle,
        canImportRawMedia: Bool
    ) -> String {
        guard title != .jak1 else { return jak1ImportMessage() }
        _ = canImportRawMedia
        let ownership = "Provide compatible game data from a copy of \(title.shelfName) you legally own."
        return ownership
    }

    static func unsupportedMessage(for title: GameLibraryTitle) -> String {
        switch title {
        case .jak2:
            return "Support for this future title is coming soon."
        case .jak3:
            return "Support for this future title is planned."
        case .jak1:
            return "That game-data format is not supported in this build."
        }
    }
}

nonisolated enum GameArtworkStorage {
    static let maximumFileBytes: Int = 25 * 1_024 * 1_024
    static let maximumPixelCount: Int = 50_000_000

    static var directory: URL {
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                    in: .userDomainMask,
                                                    appropriateFor: nil,
                                                    create: true))
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appending(path: "Library/Application Support", directoryHint: .isDirectory)
        return support.appending(path: "GOALPad/Artwork", directoryHint: .isDirectory)
    }

    static func artworkURL(for title: GameLibraryTitle) -> URL {
        directory.appending(path: "\(title.rawValue).artwork", directoryHint: .notDirectory)
    }

    nonisolated static func importArtwork(from source: URL, for title: GameLibraryTitle) throws {
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }

        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        let values = try source.resourceValues(forKeys: keys)
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw ArtworkError.invalidFile
        }
        guard let fileSize = values.fileSize, fileSize > 0, fileSize <= maximumFileBytes else {
            throw ArtworkError.fileTooLarge
        }

        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging = directory.appending(
            path: ".\(title.rawValue)-\(UUID().uuidString).staging",
            directoryHint: .notDirectory
        )
        defer { try? manager.removeItem(at: staging) }

        try manager.copyItem(at: source, to: staging)
        try validateImage(at: staging)

        let destination = artworkURL(for: title)
        if manager.fileExists(atPath: destination.path) {
            _ = try manager.replaceItemAt(destination, withItemAt: staging)
        } else {
            try manager.moveItem(at: staging, to: destination)
        }
    }

    nonisolated static func removeArtwork(for title: GameLibraryTitle) throws {
        let destination = artworkURL(for: title)
        guard FileManager.default.fileExists(atPath: destination.path) else { return }
        try FileManager.default.removeItem(at: destination)
    }

    nonisolated static func thumbnail(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_600,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    nonisolated private static func validateImage(at url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0,
              width <= maximumPixelCount / height,
              width * height <= maximumPixelCount,
              thumbnail(at: url) != nil
        else {
            throw ArtworkError.invalidImage
        }
    }
}

nonisolated enum ArtworkError: LocalizedError {
    case invalidFile
    case fileTooLarge
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidFile:
            "Choose a regular image file."
        case .fileTooLarge:
            "Artwork must be no larger than 25 MB."
        case .invalidImage:
            "Dark Eco could not read that image, or its dimensions are too large."
        }
    }
}

@MainActor
@Observable
final class GameArtworkStore {
    private(set) var revision = 0
    var errorMessage: String?

    func artworkURL(for title: GameLibraryTitle) -> URL? {
        let url = GameArtworkStorage.artworkURL(for: title)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func importArtwork(from source: URL, for title: GameLibraryTitle) async {
        do {
            try await Task.detached(priority: .userInitiated) {
                try GameArtworkStorage.importArtwork(from: source, for: title)
            }.value
            revision &+= 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeArtwork(for title: GameLibraryTitle) {
        do {
            try GameArtworkStorage.removeArtwork(for: title)
            revision &+= 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
