import Foundation
import OSLog

nonisolated private let touchLog = Logger(subsystem: "com.zephyrstudiosllc.eco",
                                          category: "Touch")

/// The PS2 buttons the on-screen controls drive.
enum TouchButton: CaseIterable, Hashable, Sendable {
    case cross, square, circle, crouch, start, select, stats
    case up, down, left, right
    case triangle, leftShoulder, rightShoulder

    var bit: GOALPadButton {
        switch self {
        case .cross: .cross
        case .square: .square
        case .circle: .circle
        case .crouch: .L1
        case .start: .start
        case .select: .select
        case .stats: [.L2, .R2]
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .triangle: .triangle
        case .leftShoulder: .L1
        case .rightShoulder: .R1
        }
    }

    var glyph: String {
        switch self {
        case .cross: "✕"
        case .square: "□"
        case .circle: "○"
        case .crouch: "↓"
        case .start: "START"
        case .select: "SELECT"
        case .stats: "STATS"
        case .up: "↑"
        case .down: "↓"
        case .left: "←"
        case .right: "→"
        case .triangle: "△"
        case .leftShoulder: "L1"
        case .rightShoulder: "R1"
        }
    }
}

enum TouchControlStyle: String, CaseIterable, Sendable {
    case modern
    case classic
}

/// The read-only progress state that Swift uses to expose only screen-proven touch semantics.
struct NativeProgressMenuSnapshot: Equatable {
    let available: Bool
    let screenRawValue: Int
    let optionIndex: Int
    let selectedOption: Bool
    let inTransition: Bool

    static let unavailable = NativeProgressMenuSnapshot(
        available: false, screenRawValue: -2, optionIndex: -1,
        selectedOption: false, inTransition: false)

    init(available: Bool, screenRawValue: Int, optionIndex: Int,
         selectedOption: Bool, inTransition: Bool) {
        self.available = available
        self.screenRawValue = screenRawValue
        self.optionIndex = optionIndex
        self.selectedOption = selectedOption
        self.inTransition = inTransition
    }

    init(_ snapshot: GOALPadProgressMenuSnapshot) {
        available = snapshot.available.boolValue
        screenRawValue = snapshot.screen.rawValue
        optionIndex = Int(snapshot.optionIndex)
        selectedOption = snapshot.selectedOption.boolValue
        inTransition = snapshot.inTransition.boolValue
    }
}

/// The authoritative warp-gate interaction state published by GOAL and checked by the native
/// bridge. Invalid bridge reads remain distinct from a valid unavailable publication so a
/// transient seqlock read cannot accidentally release an already captured destination screen.
struct NativeWarpGateTouchSnapshot: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case unavailable
        case circleUseAvailable
        case destinationListActive
        case transitioning
    }

    let valid: Bool
    let state: State
    let selectedSlot: Int32
    let permittedMask: UInt32
    let selectionMoving: Bool
    let sequence: UInt32

    static let invalid = NativeWarpGateTouchSnapshot(
        valid: false, state: .unavailable, selectedSlot: -1,
        permittedMask: 0, selectionMoving: false, sequence: 0)

    init(valid: Bool, state: State, selectedSlot: Int32, permittedMask: UInt32,
         selectionMoving: Bool, sequence: UInt32) {
        self.valid = valid
        self.state = state
        self.selectedSlot = selectedSlot
        self.permittedMask = permittedMask
        self.selectionMoving = selectionMoving
        self.sequence = sequence
    }

    init(_ snapshot: GOALPadWarpGateTouchSnapshot) {
        let mappedState: State? = switch snapshot.state {
        case .unavailable: .unavailable
        case .circleUseAvailable: .circleUseAvailable
        case .destinationListActive: .destinationListActive
        case .transitioning: .transitioning
        @unknown default: nil
        }
        guard snapshot.valid.boolValue, let mappedState else {
            self = .invalid
            return
        }
        self.init(valid: true,
                  state: mappedState,
                  selectedSlot: snapshot.selectedSlot,
                  permittedMask: snapshot.permittedMask,
                  selectionMoving: snapshot.selectionMoving.boolValue,
                  sequence: snapshot.sequence)
    }

    static func circleUseAvailable(sequence: UInt32) -> Self {
        Self(valid: true, state: .circleUseAvailable, selectedSlot: -1,
             permittedMask: 0, selectionMoving: false, sequence: sequence)
    }

    static func destinationListActive(selectedSlot: Int32, permittedMask: UInt32,
                                      selectionMoving: Bool, sequence: UInt32) -> Self {
        Self(valid: true, state: .destinationListActive, selectedSlot: selectedSlot,
             permittedMask: permittedMask, selectionMoving: selectionMoving,
             sequence: sequence)
    }

    static func transitioning(sequence: UInt32) -> Self {
        Self(valid: true, state: .transitioning, selectedSlot: -1,
             permittedMask: 0, selectionMoving: false, sequence: sequence)
    }

    static func validUnavailable(sequence: UInt32) -> Self {
        Self(valid: true, state: .unavailable, selectedSlot: -1,
             permittedMask: 0, selectionMoving: false, sequence: sequence)
    }

    var isStructurallyValid: Bool {
        guard valid, sequence & 1 == 0 else { return false }
        return switch state {
        case .unavailable, .circleUseAvailable, .transitioning:
            selectedSlot == -1 && permittedMask == 0 && !selectionMoving
        case .destinationListActive:
            if (0...4).contains(selectedSlot), permittedMask & ~0x1f == 0 {
                permittedMask & (UInt32(1) << UInt32(selectedSlot)) != 0
            } else {
                false
            }
        }
    }
}

/// GOAL publishes this only while the central `process-taskable` spooled-animation Triangle
/// query is both explicitly skippable and undecided. Native freshness validation makes a stopped
/// heartbeat invalid without changing the stable owner/availability generation each frame.
struct NativeCutsceneSkipTouchSnapshot: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case unavailable
        case triangleQueryAvailable
    }

    let valid: Bool
    let state: State
    let sequence: UInt32

    static let invalid = NativeCutsceneSkipTouchSnapshot(
        valid: false, state: .unavailable, sequence: 0)

    init(valid: Bool, state: State, sequence: UInt32) {
        self.valid = valid
        self.state = state
        self.sequence = sequence
    }

    init(_ snapshot: GOALPadCutsceneSkipTouchSnapshot) {
        let mappedState: State? = switch snapshot.state {
        case .unavailable: .unavailable
        case .triangleQueryAvailable: .triangleQueryAvailable
        @unknown default: nil
        }
        guard snapshot.valid.boolValue, let mappedState else {
            self = .invalid
            return
        }
        self.init(valid: true, state: mappedState, sequence: snapshot.sequence)
    }

    static func triangleQueryAvailable(sequence: UInt32) -> Self {
        Self(valid: true, state: .triangleQueryAvailable, sequence: sequence)
    }

    static func validUnavailable(sequence: UInt32) -> Self {
        Self(valid: true, state: .unavailable, sequence: sequence)
    }

    var isStructurallyValid: Bool {
        valid && sequence & 1 == 0
    }
}

/// The four destination commands retain their existing one-row presentation on ordinary wide
/// layouts and switch to a two-column grid before their semantic labels would clip.
struct NativeWarpGateTouchLayout: Equatable, Sendable {
    enum Arrangement: Equatable, Sendable {
        case wideRow
        case compactGrid
    }

    static let destinationActionCount = 4
    static let wideButtonMinimumWidth: CGFloat = 104
    static let wideSpacing: CGFloat = 12
    static let compactSpacing: CGFloat = 8
    static let buttonMinimumHeight: CGFloat = 60
    static let minimumTargetDimension: CGFloat = 44

    let arrangement: Arrangement
    let columnCount: Int
    let buttonWidth: CGFloat

    init(availableWidth: CGFloat, actionCount: Int) {
        let boundedWidth = max(0, availableWidth)
        let wideRequiredWidth = CGFloat(actionCount) * Self.wideButtonMinimumWidth
            + CGFloat(max(0, actionCount - 1)) * Self.wideSpacing
        if actionCount == Self.destinationActionCount && boundedWidth < wideRequiredWidth {
            arrangement = .compactGrid
            columnCount = 2
            buttonWidth = max(
                Self.minimumTargetDimension,
                (boundedWidth - Self.compactSpacing) / CGFloat(columnCount))
        } else {
            arrangement = .wideRow
            columnCount = max(1, actionCount)
            buttonWidth = actionCount == 1
                ? max(168, Self.minimumTargetDimension)
                : Self.wideButtonMinimumWidth
        }
    }
}

/// Warp actions remain distinct from native-menu actions because Jak consumes different face
/// buttons for Warp and Back than the Progress and debug menus do.
enum NativeWarpGateTouchAction: CaseIterable, Hashable, Sendable {
    case useWarpGate
    case previous
    case next
    case warp
    case back

    var button: TouchButton {
        switch self {
        case .useWarpGate, .warp: .circle
        case .previous: .left
        case .next: .right
        case .back: .triangle
        }
    }

    var label: String {
        switch self {
        case .useWarpGate: "Use Warp Gate"
        case .previous: "Previous"
        case .next: "Next"
        case .warp: "Warp"
        case .back: "Back"
        }
    }

    var systemImage: String {
        switch self {
        case .useWarpGate: "circle"
        case .previous: "chevron.left"
        case .next: "chevron.right"
        case .warp: "arrow.right.circle.fill"
        case .back: "xmark"
        }
    }

    nonisolated static func available(
        in mode: GOALPadGameMode,
        snapshot: NativeWarpGateTouchSnapshot
    ) -> [Self] {
        guard mode == .gameplay, snapshot.isStructurallyValid else { return [] }
        switch snapshot.state {
        case .unavailable, .transitioning:
            return []
        case .circleUseAvailable:
            return [.useWarpGate]
        case .destinationListActive:
            var actions: [Self] = snapshot.selectionMoving ? [] : [.previous, .next]
            actions.append(contentsOf: [.warp, .back])
            return actions
        }
    }
}

/// Touch-friendly actions whose meanings are authoritative for the current native game state.
enum NativeMenuTouchAction: CaseIterable, Hashable, Sendable {
    case up, down, left, right
    case confirm, back, cancel, resume
    case fuelCells, precursorOrbs, scoutFlies, settings

    /// Boxed-array lengths installed by Jak 1's shipping PC `init-game-options` override.
    private enum ShippingPCOptionCount {
        static let settingsWithoutSecrets = 8
        static let settingsWithSecrets = 9
        static let gameSettings = 10
        static let graphicSettings = 5
        static let soundSettings = 4
        static let title = 6
        static let settingsTitle = 4
    }

    var button: TouchButton {
        switch self {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .confirm: .cross
        case .back: .square
        case .cancel: .square
        case .resume: .start
        case .fuelCells: .square
        case .precursorOrbs: .cross
        case .scoutFlies: .triangle
        case .settings: .circle
        }
    }

    var label: String {
        switch self {
        case .up: "Up"
        case .down: "Down"
        case .left: "Left"
        case .right: "Right"
        case .confirm: "Confirm"
        case .back: "Back"
        case .cancel: "Cancel"
        case .resume: "Resume"
        case .fuelCells: "Fuel Cells"
        case .precursorOrbs: "Precursor Orbs"
        case .scoutFlies: "Scout Flies"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .up: "chevron.up"
        case .down: "chevron.down"
        case .left: "chevron.left"
        case .right: "chevron.right"
        case .confirm: "checkmark"
        case .back: "arrow.uturn.backward"
        case .cancel: "xmark"
        case .resume: "play.fill"
        case .fuelCells: "battery.100percent"
        case .precursorOrbs: "circle.grid.2x2.fill"
        case .scoutFlies: "triangle.fill"
        case .settings: "gearshape.fill"
        }
    }

    nonisolated static func available(
        in mode: GOALPadGameMode,
        progress: NativeProgressMenuSnapshot = .unavailable
    ) -> [Self] {
        switch mode {
        case .pause:
            [.resume]
        case .menu:
            [.up, .down, .left, .right, .back, .confirm, .resume]
        case .progress:
            progressActions(for: progress)
        case .unknown, .gameplay:
            []
        @unknown default:
            []
        }
    }

    nonisolated private static func progressActions(
        for snapshot: NativeProgressMenuSnapshot
    ) -> [Self] {
        guard snapshot.available, !snapshot.inTransition else { return [] }

        switch snapshot.screenRawValue {
        case 0, 1, 2:
            guard !snapshot.selectedOption else { return [] }
            return [.fuelCells, .precursorOrbs, .scoutFlies, .settings]
        case 3:
            // The snapshot does not expose whether secrets are unlocked, so accept the larger of
            // the two authoritative shipping arrays while still rejecting every later index.
            return commonOptions(for: snapshot,
                                 optionCount: ShippingPCOptionCount.settingsWithSecrets)
        case 4:
            return commonOptions(for: snapshot,
                                 optionCount: ShippingPCOptionCount.gameSettings)
        case 5:
            return commonOptions(for: snapshot,
                                 optionCount: ShippingPCOptionCount.graphicSettings)
        case 6:
            return commonOptions(for: snapshot,
                                 optionCount: ShippingPCOptionCount.soundSettings)
        case 27:
            return commonOptions(for: snapshot,
                                 optionCount: ShippingPCOptionCount.title)
        case 28:
            return commonOptions(for: snapshot,
                                 optionCount: ShippingPCOptionCount.settingsTitle)
        case 16, 17:
            return fileOptions(for: snapshot, optionCount: 5)
        case 18:
            return fileOptions(for: snapshot, optionCount: 6)
        default:
            return []
        }
    }

    nonisolated private static func commonOptions(
        for snapshot: NativeProgressMenuSnapshot,
        optionCount: Int
    ) -> [Self] {
        guard (0..<optionCount).contains(snapshot.optionIndex) else { return [] }
        if snapshot.selectedOption {
            return [.left, .right, .cancel, .confirm]
        }
        return [.up, .down, .confirm]
    }

    nonisolated private static func fileOptions(
        for snapshot: NativeProgressMenuSnapshot,
        optionCount: Int
    ) -> [Self] {
        guard (0..<optionCount).contains(snapshot.optionIndex) else { return [] }
        if snapshot.selectedOption {
            return [.cancel, .confirm]
        }
        return [.up, .down, .back, .confirm]
    }
}

/// A discrete, app-owned touch action that may receive device feedback.
/// These are intentionally separate from native game/controller rumble.
enum TouchHapticEvent: Equatable {
    case button(TouchButton)
    case gesture(TouchButton)
    case stickEngaged
}

struct TouchSafeAreaInsets: Equatable, Sendable {
    var top: CGFloat = 0
    var leading: CGFloat = 0
    var bottom: CGFloat = 0
    var trailing: CGFloat = 0

    static let zero = TouchSafeAreaInsets()
}

/// Deterministic Modern artwork geometry. Input radii remain owned by TouchControls.
struct ModernTouchLayout: Sendable {
    static let movementKnobSize: CGFloat = 66
    static let movementVisualRadius: CGFloat = 54
    static let rightStickHitSlop: CGFloat = 16
    static let rightStickSpacerCap: CGFloat = 200

    private static let pillSize = CGSize(width: 82, height: 42)
    private static let pillSpacing: CGFloat = 10
    private static let pillHitInsets = CGSize(width: 10, height: 12)
    private static let controlGap: CGFloat = 8

    let safeBounds: CGRect
    let rightStickSpacer: CGFloat
    let rightStickArtworkFrame: CGRect
    let rightStickHitFrame: CGRect
    let selectPillFrame: CGRect
    let statsPillFrame: CGRect
    let startPillFrame: CGRect

    init(size: CGSize, safeAreaInsets: TouchSafeAreaInsets = .zero) {
        let bounds = CGRect(origin: .zero,
                            size: CGSize(width: max(0, size.width), height: max(0, size.height)))
        let leading = min(max(0, safeAreaInsets.leading), bounds.width)
        let trailing = min(max(0, safeAreaInsets.trailing), bounds.width - leading)
        let top = min(max(0, safeAreaInsets.top), bounds.height)
        let bottom = min(max(0, safeAreaInsets.bottom), bounds.height - top)
        let safe = CGRect(x: leading, y: top,
                          width: bounds.width - leading - trailing,
                          height: bounds.height - top - bottom)
        safeBounds = safe

        let legacyEdge = Self.legacyRightStickEdge(for: bounds.size)
        let targetSpacer = min(Self.rightStickSpacerCap,
                               max(legacyEdge, safe.width * 0.24))
        rightStickSpacer = min(targetSpacer,
                                max(0, safe.width - TouchControls.rightStickRadius * 2))

        let pillOffset = Self.pillSize.width + Self.pillSpacing
        let pillY = bounds.maxY - 30 - Self.pillSize.height / 2
        selectPillFrame = Self.frame(centre: CGPoint(x: bounds.midX - pillOffset, y: pillY),
                                     size: Self.pillSize)
        statsPillFrame = Self.frame(centre: CGPoint(x: bounds.midX, y: pillY),
                                    size: Self.pillSize)
        startPillFrame = Self.frame(centre: CGPoint(x: bounds.midX + pillOffset, y: pillY),
                                    size: Self.pillSize)

        let radius = TouchControls.rightStickRadius
        let centreX = max(safe.minX + radius, safe.maxX - radius - rightStickSpacer)
        let lowestCentreY = safe.maxY - radius - legacyEdge
        let candidateHitFrame = Self.frame(centre: CGPoint(x: centreX, y: lowestCentreY),
                                           diameter: radius * 2)
            .insetBy(dx: -Self.rightStickHitSlop, dy: -Self.rightStickHitSlop)
        let pillHitFrames = [selectPillFrame, statsPillFrame, startPillFrame].map {
            $0.insetBy(dx: -Self.pillHitInsets.width, dy: -Self.pillHitInsets.height)
        }
        let overlapsPillHorizontally = pillHitFrames.contains {
            $0.minX < candidateHitFrame.maxX && candidateHitFrame.minX < $0.maxX
        }
        let clearCentreY = pillHitFrames.map(\.minY).min()
            .map { $0 - radius - Self.rightStickHitSlop - Self.controlGap }
            ?? lowestCentreY
        let centreY = max(safe.minY + radius,
                          overlapsPillHorizontally ? min(lowestCentreY, clearCentreY) : lowestCentreY)
        rightStickArtworkFrame = Self.frame(centre: CGPoint(x: centreX, y: centreY),
                                            diameter: radius * 2)
        rightStickHitFrame = rightStickArtworkFrame.insetBy(dx: -Self.rightStickHitSlop,
                                                             dy: -Self.rightStickHitSlop)
    }

    static func legacyRightStickEdge(for size: CGSize) -> CGFloat {
        max(28, min(max(0, size.width), max(0, size.height)) * 0.06)
    }

    private static func frame(centre: CGPoint, diameter: CGFloat) -> CGRect {
        frame(centre: centre, size: CGSize(width: diameter, height: diameter))
    }

    private static func frame(centre: CGPoint, size: CGSize) -> CGRect {
        CGRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2,
               width: size.width, height: size.height)
    }
}

/// Deterministic Classic artwork and app-owned touch targets.
struct ClassicTouchLayout {
    static let minimumButtonHitSize = CGSize(width: 44, height: 44)
    static let buttons: [TouchButton] = [
        .up, .down, .left, .right,
        .select, .stats, .start,
        .leftShoulder, .rightShoulder,
        .triangle, .square, .circle, .cross,
    ]

    let safeBounds: CGRect
    let stickRadius: CGFloat
    let leftStickFrame: CGRect
    let rightStickFrame: CGRect
    /// Artwork geometry. This remains independent from the larger touch targets below.
    let buttonFrames: [TouchButton: CGRect]
    /// Touch geometry for fixed Classic buttons, kept within `safeBounds`.
    let buttonHitFrames: [TouchButton: CGRect]

    init(size: CGSize, safeAreaInsets: TouchSafeAreaInsets = .zero) {
        let bounds = CGRect(origin: .zero,
                            size: CGSize(width: max(0, size.width), height: max(0, size.height)))
        let leading = min(max(0, safeAreaInsets.leading), bounds.width)
        let trailing = min(max(0, safeAreaInsets.trailing), bounds.width - leading)
        let top = min(max(0, safeAreaInsets.top), bounds.height)
        let bottom = min(max(0, safeAreaInsets.bottom), bounds.height - top)
        let safe = CGRect(x: leading, y: top,
                          width: bounds.width - leading - trailing,
                          height: bounds.height - top - bottom)
        let padding = min(18, max(0, min(safe.width, safe.height) * 0.025))
        let boundedSafeBounds = safe.insetBy(dx: padding, dy: padding)
        safeBounds = boundedSafeBounds

        let scale = min(1, max(0.5, min(safeBounds.width / 560, safeBounds.height / 240)))
        let buttonDiameter = 44 * scale
        let buttonRadius = buttonDiameter / 2
        let buttonGap = 12 * scale
        let clusterStep = buttonDiameter + buttonGap
        stickRadius = 56 * scale

        let clusterInset = clusterStep + buttonRadius
        let leftCluster = CGPoint(x: safeBounds.minX + clusterInset,
                                  y: safeBounds.maxY - clusterInset - 8 * scale)
        let rightCluster = CGPoint(x: safeBounds.maxX - clusterInset,
                                   y: leftCluster.y)
        let stickInset = clusterInset + clusterStep + buttonRadius + buttonGap + stickRadius
        let stickY = safeBounds.maxY - stickRadius - 8 * scale
        let leftStickCentre = CGPoint(x: safeBounds.minX + stickInset, y: stickY)
        let rightStickCentre = CGPoint(x: safeBounds.maxX - stickInset, y: stickY)

        leftStickFrame = Self.frame(centre: leftStickCentre, diameter: stickRadius * 2)
        rightStickFrame = Self.frame(centre: rightStickCentre, diameter: stickRadius * 2)

        var frames: [TouchButton: CGRect] = [:]
        frames[.up] = Self.frame(centre: CGPoint(x: leftCluster.x,
                                                 y: leftCluster.y - clusterStep),
                                         diameter: buttonDiameter)
        frames[.down] = Self.frame(centre: CGPoint(x: leftCluster.x,
                                                   y: leftCluster.y + clusterStep),
                                           diameter: buttonDiameter)
        frames[.left] = Self.frame(centre: CGPoint(x: leftCluster.x - clusterStep,
                                                   y: leftCluster.y),
                                           diameter: buttonDiameter)
        frames[.right] = Self.frame(centre: CGPoint(x: leftCluster.x + clusterStep,
                                                    y: leftCluster.y),
                                            diameter: buttonDiameter)
        frames[.triangle] = Self.frame(centre: CGPoint(x: rightCluster.x,
                                                       y: rightCluster.y - clusterStep),
                                               diameter: buttonDiameter)
        frames[.cross] = Self.frame(centre: CGPoint(x: rightCluster.x,
                                                    y: rightCluster.y + clusterStep),
                                            diameter: buttonDiameter)
        frames[.square] = Self.frame(centre: CGPoint(x: rightCluster.x - clusterStep,
                                                     y: rightCluster.y),
                                             diameter: buttonDiameter)
        frames[.circle] = Self.frame(centre: CGPoint(x: rightCluster.x + clusterStep,
                                                     y: rightCluster.y),
                                             diameter: buttonDiameter)

        let shoulderSize = CGSize(width: 82 * scale, height: 34 * scale)
        let shoulderY = leftCluster.y - clusterStep - buttonRadius - buttonGap
            - shoulderSize.height / 2
        frames[.leftShoulder] = Self.frame(
            centre: CGPoint(x: (leftCluster.x + leftStickCentre.x) / 2, y: shoulderY),
            size: shoulderSize)
        frames[.rightShoulder] = Self.frame(
            centre: CGPoint(x: (rightCluster.x + rightStickCentre.x) / 2, y: shoulderY),
            size: shoulderSize)

        let pillSize = CGSize(width: 68 * scale, height: 30 * scale)
        let centreGap = rightStickFrame.minX - leftStickFrame.maxX
        let centrePillsAreSideBySide = centreGap >= pillSize.width * 3 + buttonGap * 2
        if centrePillsAreSideBySide {
            let offset = pillSize.width + buttonGap
            frames[.select] = Self.frame(centre: CGPoint(x: safeBounds.midX - offset, y: stickY),
                                         size: pillSize)
            frames[.stats] = Self.frame(centre: CGPoint(x: safeBounds.midX, y: stickY),
                                        size: pillSize)
            frames[.start] = Self.frame(centre: CGPoint(x: safeBounds.midX + offset, y: stickY),
                                        size: pillSize)
        } else {
            let minimumStep = Self.minimumButtonHitSize.height
            let stackHeight = minimumStep * 3
            let stackTop = min(max(safeBounds.minY, shoulderY - stackHeight / 2),
                               max(safeBounds.minY, safeBounds.maxY - stackHeight))
            frames[.select] = Self.frame(
                centre: CGPoint(x: safeBounds.midX, y: stackTop + minimumStep / 2),
                size: pillSize)
            frames[.stats] = Self.frame(
                centre: CGPoint(x: safeBounds.midX, y: stackTop + minimumStep * 1.5),
                size: pillSize)
            frames[.start] = Self.frame(
                centre: CGPoint(x: safeBounds.midX, y: stackTop + minimumStep * 2.5),
                                        size: pillSize)
        }
        buttonFrames = frames
        buttonHitFrames = frames.mapValues { Self.minimumHitFrame(for: $0,
                                                                  boundedTo: boundedSafeBounds) }
    }

    func frame(for button: TouchButton) -> CGRect? {
        buttonFrames[button]
    }

    func hitFrame(for button: TouchButton) -> CGRect? {
        buttonHitFrames[button]
    }

    private static func minimumHitFrame(for visualFrame: CGRect, boundedTo safeBounds: CGRect) -> CGRect {
        let size = CGSize(width: min(safeBounds.width,
                                    max(minimumButtonHitSize.width, visualFrame.width)),
                          height: min(safeBounds.height,
                                      max(minimumButtonHitSize.height, visualFrame.height)))
        let origin = CGPoint(
            x: min(max(safeBounds.minX, visualFrame.midX - size.width / 2),
                   safeBounds.maxX - size.width),
            y: min(max(safeBounds.minY, visualFrame.midY - size.height / 2),
                   safeBounds.maxY - size.height)
        )
        return CGRect(origin: origin, size: size)
    }

    private static func frame(centre: CGPoint, diameter: CGFloat) -> CGRect {
        frame(centre: centre, size: CGSize(width: diameter, height: diameter))
    }

    private static func frame(centre: CGPoint, size: CGSize) -> CGRect {
        CGRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2,
               width: size.width, height: size.height)
    }
}

/// One frame of the on-screen pad, in the shape the engine reads: a button mask and one byte per
/// stick axis, 127 at rest and growing right and down.
struct TouchPadState: Equatable {
    var buttons: GOALPadButton = []
    var leftX = UInt8(GOALPadAnalogNeutral)
    var leftY = UInt8(GOALPadAnalogNeutral)
    var rightX = UInt8(GOALPadAnalogNeutral)
    var rightY = UInt8(GOALPadAnalogNeutral)

    static let neutral = TouchPadState()

    var isLeftDeflected: Bool {
        leftX != UInt8(GOALPadAnalogNeutral) || leftY != UInt8(GOALPadAnalogNeutral)
    }

    var isRightDeflected: Bool {
        rightX != UInt8(GOALPadAnalogNeutral) || rightY != UInt8(GOALPadAnalogNeutral)
    }
}

/// On-screen controls translated into the same state as a physical PS2-style pad.
/// Modern retains the dynamic Build 93 gestures; Classic uses fixed DualShock-like hit targets.
@MainActor
@Observable
final class TouchControls {
    nonisolated static let movementRadius: CGFloat = 90
    nonisolated static let rightStickRadius: CGFloat = 38
    nonisolated static let rightStickDeadzone: CGFloat = 12
    nonisolated static let rollJumpDistance: CGFloat = 44
    nonisolated static let swipeDistance: CGFloat = 44
    nonisolated static let nativeMenuSwipeDistance: CGFloat = 44
    nonisolated static let nativeWarpSwipeDistance: CGFloat = 44
    nonisolated static let pinchScaleDelta: CGFloat = 0.12

    /// Frames a recognised one-shot press remains down, followed by a guaranteed release gap.
    nonisolated static let holdFrames = 6
    nonisolated static let releaseFrames = 2
    nonisolated static let fadeOutDelay: TimeInterval = 0.9

    /// Strong movement pushes also step list-style menus through the D-pad.
    nonisolated static let dpadPress: CGFloat = 0.55
    nonisolated static let dpadRelease: CGFloat = 0.35
    nonisolated static let dpadRepeatDelay = 26
    nonisolated static let dpadRepeatInterval = 10

    private(set) var style: TouchControlStyle
    private(set) var nativeMenuMode: GOALPadGameMode = .unknown
    private(set) var progressMenuSnapshot: NativeProgressMenuSnapshot = .unavailable
    private(set) var warpGateTouchSnapshot: NativeWarpGateTouchSnapshot = .invalid
    private(set) var cutsceneSkipTouchSnapshot: NativeCutsceneSkipTouchSnapshot = .invalid
    @ObservationIgnored private var retainsWarpGateTouchCapture = false

    enum Role: Equatable {
        case movement
        case rightStick
        case gesture
        case pill(TouchButton)
        case skip(NativeCutsceneSkipTouchSnapshot)
    }

    struct Tracked: Identifiable {
        let id: ObjectIdentifier
        let role: Role
        /// A dynamic movement origin, fixed right-stick centre, or gesture/pill landing point.
        let origin: CGPoint
        var point: CGPoint
        var travelled: CGFloat = 0
        var swiped: TouchButton? = nil
        var crouchPeakY: CGFloat? = nil
        var jumpTriggered = false
        var punchTriggered = false
        var stickHapticTriggered = false
        let radius: CGFloat
        let deadzone: CGFloat
    }

    private(set) var touches: [ObjectIdentifier: Tracked] = [:]
    private(set) var isEngaged = false
    private(set) var surfaceSafeAreaInsets = TouchSafeAreaInsets.zero
    @ObservationIgnored private var hapticEvents: [TouchHapticEvent] = []

    var stick: Tracked? { touches.values.first { $0.role == .movement } }
    var rightStick: Tracked? { touches.values.first { $0.role == .rightStick } }
    var gestures: [Tracked] { touches.values.filter { $0.role == .gesture } }
    var isCrouching: Bool {
        gestures.contains { $0.swiped == .crouch }
    }

    func isPillDown(_ button: TouchButton) -> Bool {
        touches.values.contains {
            switch $0.role {
            case .pill(let pressed): pressed == button
            case .skip: button == .select
            case .movement, .rightStick, .gesture: false
            }
        }
    }

    @ObservationIgnored private var rightStickFrame = CGRect.zero
    @ObservationIgnored private var pillFrames: [TouchButton: CGRect] = [:]
    @ObservationIgnored private var pulses: [TouchButton: Pulse] = [:]
    @ObservationIgnored private var fadeToken = 0
    @ObservationIgnored private var dpad = DirectionRepeat()
    @ObservationIgnored private var pinchZoom = PinchZoom()

    init(style: TouchControlStyle = .modern) {
        self.style = style
    }

    var capturesNativeMenuInput: Bool {
        Self.capturesNativeMenuInput(mode: nativeMenuMode)
    }

    var capturesNativeTouchInput: Bool {
        capturesNativeMenuInput
            || capturesWarpGateTouchInput
    }

    var capturesWarpGateTouchInput: Bool {
        Self.capturesWarpGateTouchInput(
            mode: nativeMenuMode,
            snapshot: warpGateTouchSnapshot,
            retainingAfterInvalidRead: retainsWarpGateTouchCapture)
    }

    func setStyle(_ style: TouchControlStyle) {
        guard style != self.style else { return }
        reset()
        self.style = style
    }

    /// Compatibility entry point for callers that only have the master-mode classification.
    func setNativeMenuMode(_ mode: GOALPadGameMode) {
        setNativeMenuState(mode, progress: .unavailable)
    }

    /// Applies the read-only native menu snapshot. Any semantic transition cancels carried input
    /// before another frame reaches the engine, including progress screen and selection changes.
    func setNativeMenuState(_ mode: GOALPadGameMode,
                            progress: NativeProgressMenuSnapshot) {
        guard mode != nativeMenuMode || progress != progressMenuSnapshot else { return }
        let capturedInput = capturesNativeTouchInput
        let warpSemanticWasActive = nativeMenuMode == .gameplay
            && warpGateTouchSnapshot.state != .unavailable
        let skipWasActive = Self.cutsceneSkipIsAvailable(
            in: nativeMenuMode, snapshot: cutsceneSkipTouchSnapshot)
        nativeMenuMode = mode
        progressMenuSnapshot = progress
        let warpSemanticIsActive = nativeMenuMode == .gameplay
            && warpGateTouchSnapshot.state != .unavailable
        let skipIsActive = Self.cutsceneSkipIsAvailable(
            in: nativeMenuMode, snapshot: cutsceneSkipTouchSnapshot)
        if capturedInput || capturesNativeTouchInput
            || warpSemanticWasActive || warpSemanticIsActive
            || skipWasActive || skipIsActive { reset() }
    }

    /// Any published semantic or sequence change invalidates touch-owned work from the prior
    /// snapshot, including live gameplay touches under the non-capturing use prompt.
    func setWarpGateTouchSnapshot(_ snapshot: NativeWarpGateTouchSnapshot) {
        let nextCaptureRetention: Bool
        if snapshot.isStructurallyValid {
            nextCaptureRetention = switch snapshot.state {
            case .destinationListActive, .transitioning: true
            case .unavailable, .circleUseAvailable: false
            }
        } else {
            nextCaptureRetention = retainsWarpGateTouchCapture
        }
        guard snapshot != warpGateTouchSnapshot
                || nextCaptureRetention != retainsWarpGateTouchCapture else { return }
        warpGateTouchSnapshot = snapshot
        retainsWarpGateTouchCapture = nextCaptureRetention
        reset()
    }

    /// Owner/availability generation changes and stale native reads cancel a pending SKIP tap.
    func setCutsceneSkipTouchSnapshot(_ snapshot: NativeCutsceneSkipTouchSnapshot) {
        guard snapshot != cutsceneSkipTouchSnapshot else { return }
        cutsceneSkipTouchSnapshot = snapshot
        reset()
    }

    /// Emits one ordinary pad pulse. Availability is mode-gated so a stale SwiftUI action cannot
    /// send menu input after the game has returned to gameplay or moved into progress.
    func performNativeMenuAction(_ action: NativeMenuTouchAction) {
        guard NativeMenuTouchAction.available(in: nativeMenuMode,
                                              progress: progressMenuSnapshot).contains(action)
        else { return }
        press(action.button)
        enqueueHaptic(.button(action.button))
    }

    /// Converts one completed, predominantly vertical list swipe into one ordinary D-pad pulse.
    @discardableResult
    func performNativeMenuVerticalSwipe(translation: CGSize) -> Bool {
        let actions = NativeMenuTouchAction.available(in: nativeMenuMode,
                                                      progress: progressMenuSnapshot)
        guard abs(translation.height) >= Self.nativeMenuSwipeDistance,
              abs(translation.height) > abs(translation.width) else { return false }
        let action: NativeMenuTouchAction = translation.height < 0 ? .up : .down
        guard actions.contains(action) else { return false }
        performNativeMenuAction(action)
        return true
    }

    /// Emits only when the view's full source snapshot, including its sequence, is still current.
    func performNativeWarpGateAction(_ action: NativeWarpGateTouchAction,
                                     for expectedSnapshot: NativeWarpGateTouchSnapshot,
                                     isSuppressed: Bool = false) {
        guard !isSuppressed, expectedSnapshot == warpGateTouchSnapshot,
              NativeWarpGateTouchAction.available(in: nativeMenuMode,
                                                  snapshot: warpGateTouchSnapshot).contains(action)
        else { return }
        press(action.button)
        enqueueHaptic(.button(action.button))
    }

    /// A completed tap emits the ordinary Triangle edge only if its full GOAL generation remains
    /// current and gameplay mode has not changed since touch-down.
    func performCutsceneSkip(for expectedSnapshot: NativeCutsceneSkipTouchSnapshot,
                             isSuppressed: Bool = false) {
        guard !isSuppressed, expectedSnapshot == cutsceneSkipTouchSnapshot,
              Self.cutsceneSkipIsAvailable(in: nativeMenuMode,
                                           snapshot: cutsceneSkipTouchSnapshot)
        else { return }
        press(.triangle)
        enqueueHaptic(.button(.triangle))
    }

    /// The destination responder is Left/Right-driven. A completed horizontal swipe maps to
    /// exactly one of those source semantics; vertical or diagonal intent remains inert.
    @discardableResult
    func performNativeWarpGateSwipe(translation: CGSize,
                                    for expectedSnapshot: NativeWarpGateTouchSnapshot,
                                    isSuppressed: Bool = false) -> Bool {
        guard !isSuppressed else { return false }
        guard abs(translation.width) >= Self.nativeWarpSwipeDistance,
              abs(translation.width) > abs(translation.height) else { return false }
        let action: NativeWarpGateTouchAction = translation.width < 0 ? .previous : .next
        let actions = NativeWarpGateTouchAction.available(in: nativeMenuMode,
                                                          snapshot: warpGateTouchSnapshot)
        guard expectedSnapshot == warpGateTouchSnapshot,
              actions.contains(action) else { return false }
        performNativeWarpGateAction(action, for: expectedSnapshot)
        return true
    }

    func setRightStickFrame(_ frame: CGRect) {
        rightStickFrame = frame
    }

    func setPillFrame(_ button: TouchButton, _ frame: CGRect) {
        pillFrames[button] = frame
    }

    func setSurfaceSafeAreaInsets(_ insets: TouchSafeAreaInsets) {
        guard insets != surfaceSafeAreaInsets else { return }
        surfaceSafeAreaInsets = insets
    }

    // MARK: - Touches

    func began(_ id: ObjectIdentifier, at point: CGPoint, in size: CGSize,
               safeAreaInsets: TouchSafeAreaInsets = .zero, at _: TimeInterval) {
        guard !capturesNativeTouchInput else { return }
        let layout = style == .classic
            ? ClassicTouchLayout(size: size, safeAreaInsets: safeAreaInsets)
            : nil
        guard let role = role(for: point, in: size, classicLayout: layout) else { return }
        let origin: CGPoint
        let radius: CGFloat
        let deadzone: CGFloat
        switch role {
        case .movement:
            if let layout {
                origin = layout.leftStickFrame.centre
                radius = layout.stickRadius
                deadzone = layout.stickRadius * 0.16
            } else {
                origin = point
                radius = Self.movementRadius
                deadzone = 0
            }
        case .rightStick:
            if let layout {
                origin = layout.rightStickFrame.centre
                radius = layout.stickRadius
                deadzone = layout.stickRadius * 0.16
            } else {
                origin = rightStickFrame.centre
                radius = Self.rightStickRadius
                deadzone = Self.rightStickDeadzone
            }
        case .gesture, .pill, .skip:
            origin = point
            radius = 0
            deadzone = 0
        }
        touches[id] = Tracked(id: id, role: role, origin: origin, point: point,
                              radius: radius, deadzone: deadzone)
        if case .pill(let button) = role {
            press(button)
            enqueueHaptic(.button(button))
        }
        engage()
    }

    func moved(_ id: ObjectIdentifier, to point: CGPoint) {
        guard var touch = touches[id] else { return }
        touch.point = point
        touch.travelled = max(touch.travelled, Self.distance(touch.origin, point))
        if (touch.role == .movement || touch.role == .rightStick), !touch.stickHapticTriggered,
           Self.distance(.zero, Self.radialDeflection(from: touch.origin, to: point,
                                                      radius: touch.radius,
                                                      deadzone: touch.deadzone)) >= 0.5 {
            touch.stickHapticTriggered = true
            enqueueHaptic(.stickEngaged)
        } else if touch.role == .gesture, touch.swiped == nil,
                  touch.travelled >= Self.swipeDistance,
           let button = Self.swipe(from: touch.origin, to: point) {
            touch.swiped = button
            enqueueHaptic(.gesture(button))
            if button == .crouch {
                touch.crouchPeakY = point.y
                touchLog.debug("crouch")
            } else {
                press(button)
            }
        } else if touch.role == .gesture, touch.swiped == .crouch {
            let peak = max(touch.crouchPeakY ?? point.y, point.y)
            touch.crouchPeakY = peak
            let horizontal = point.x - touch.origin.x
            if !touch.punchTriggered, horizontal <= -Self.swipeDistance {
                touch.punchTriggered = true
                press(.square)
                enqueueHaptic(.gesture(.square))
                touchLog.debug("crouch punch")
            }
            if !touch.jumpTriggered, peak - point.y >= Self.rollJumpDistance {
                touch.jumpTriggered = true
                press(.cross)
                enqueueHaptic(.gesture(.cross))
                touchLog.debug("roll jump")
            }
        }
        touches[id] = touch
    }

    func ended(_ id: ObjectIdentifier, at _: TimeInterval) {
        guard let touch = touches.removeValue(forKey: id) else { return }
        if case .skip(let expectedSnapshot) = touch.role {
            performCutsceneSkip(for: expectedSnapshot)
        }
        fadeWhenIdle()
    }

    func cancelled(_ id: ObjectIdentifier) {
        guard touches.removeValue(forKey: id) != nil else { return }
        fadeWhenIdle()
    }

    func pinchBegan() {
        guard style == .modern, !capturesNativeTouchInput else {
            pinchZoom.reset()
            return
        }
        pinchZoom.begin()
    }

    func pinchChanged(scale: CGFloat, lookAroundState: GOALPadLookAroundState) {
        guard style == .modern, !capturesNativeTouchInput,
              let direction = pinchZoom.recognize(scale: scale) else { return }
        switch (direction, lookAroundState) {
        case (.zoomIn, .normal), (.zoomOut, .firstPerson):
            press(.triangle)
            enqueueHaptic(.gesture(.triangle))
        default:
            break
        }
    }

    func pinchEnded() {
        pinchZoom.reset()
    }

    func pinchCancelled() {
        pinchZoom.reset()
    }

    /// UIKit may not deliver individual cancellations during a lifecycle transition.
    func reset() {
        touches.removeAll()
        pulses.removeAll()
        dpad = DirectionRepeat()
        pinchZoom.reset()
        hapticEvents.removeAll()
        fadeToken += 1
        isEngaged = false
    }

    /// Returns and clears touch-owned feedback actions without affecting game input state.
    func consumeHapticEvents() -> [TouchHapticEvent] {
        defer { hapticEvents.removeAll() }
        return hapticEvents
    }

    private func role(for point: CGPoint, in size: CGSize,
                      classicLayout: ClassicTouchLayout?) -> Role? {
        if let layout = classicLayout {
            for button in ClassicTouchLayout.buttons
            where layout.hitFrame(for: button)?.contains(point) == true {
                return pillRole(for: button)
            }
            if stick == nil, layout.leftStickFrame.contains(point) { return .movement }
            if rightStick == nil, layout.rightStickFrame.contains(point) { return .rightStick }
            return nil
        }
        for (button, frame) in pillFrames where frame.contains(point) {
            return pillRole(for: button)
        }
        if rightStick == nil, rightStickFrame.contains(point) { return .rightStick }
        if stick == nil, point.x < size.width / 2 { return .movement }
        if point.x >= size.width / 2 { return .gesture }
        return nil
    }

    private func pillRole(for button: TouchButton) -> Role {
        if button == .select,
           Self.cutsceneSkipIsAvailable(in: nativeMenuMode,
                                        snapshot: cutsceneSkipTouchSnapshot) {
            return .skip(cutsceneSkipTouchSnapshot)
        }
        return .pill(button)
    }

    // MARK: - The frame

    /// Advances every one-shot button state machine exactly once per game frame.
    func frameState() -> TouchPadState {
        if capturesNativeTouchInput {
            var state = TouchPadState()
            for button in TouchButton.allCases {
                var pulse = pulses[button] ?? Pulse()
                if pulse.advance() { state.buttons.insert(button.bit) }
                pulses[button] = pulse
            }
            return state
        }

        for touch in touches.values {
            switch touch.role {
            case .pill(let button):
                pulses[button, default: Pulse()].sustain()
            case .gesture:
                if let button = touch.swiped, button != .crouch {
                    pulses[button, default: Pulse()].sustain()
                }
            case .movement, .rightStick, .skip:
                break
            }
        }

        let movement = stick.map {
            Self.radialDeflection(from: $0.origin, to: $0.point,
                                  radius: $0.radius, deadzone: $0.deadzone)
        } ?? .zero
        if let direction = dpad.advance(push: movement) { press(direction) }

        var state = TouchPadState()
        for button in TouchButton.allCases {
            var pulse = pulses[button] ?? Pulse()
            if pulse.advance() { state.buttons.insert(button.bit) }
            pulses[button] = pulse
        }
        if isCrouching { state.buttons.insert(TouchButton.crouch.bit) }

        (state.leftX, state.leftY) = Self.axes(movement)
        if let rightStick {
            let look = Self.radialDeflection(from: rightStick.origin, to: rightStick.point,
                                             radius: rightStick.radius,
                                             deadzone: rightStick.deadzone)
            (state.rightX, state.rightY) = Self.axes(look)
        }
        return state
    }

    // MARK: - Mapping

    /// The three face-button gestures plus held crouch on the downward direction.
    private static func swipe(from origin: CGPoint, to point: CGPoint) -> TouchButton? {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        if abs(dy) > abs(dx) { return dy < 0 ? .cross : .crouch }
        return dx < 0 ? .square : .circle
    }

    nonisolated static func movementDeflection(from origin: CGPoint, to point: CGPoint) -> CGPoint {
        radialDeflection(from: origin, to: point, radius: movementRadius)
    }

    /// Returns a continuous radial deflection after the small resting-finger deadzone.
    nonisolated static func rightStickDeflection(from origin: CGPoint,
                                                 to point: CGPoint) -> CGPoint {
        radialDeflection(from: origin, to: point, radius: rightStickRadius,
                         deadzone: rightStickDeadzone)
    }

    nonisolated static func classicStickDeflection(from origin: CGPoint, to point: CGPoint,
                                                   radius: CGFloat) -> CGPoint {
        radialDeflection(from: origin, to: point, radius: radius, deadzone: radius * 0.16)
    }

    nonisolated static func artworkIsVisible(isEngaged: Bool, isSuppressed: Bool,
                                             hasTouches: Bool,
                                             isNativeMenuOpen: Bool) -> Bool {
        (isEngaged || isNativeMenuOpen) && (!isSuppressed || hasTouches)
    }

    nonisolated static func artworkLabel(for button: TouchButton,
                                         isNativeMenuOpen: Bool,
                                         cutsceneSkipAvailable: Bool = false) -> String {
        if button == .select, cutsceneSkipAvailable { return "SKIP" }
        guard button == .start else { return button.glyph }
        return isNativeMenuOpen ? "RESUME" : "PAUSE"
    }

    nonisolated static func cutsceneSkipIsAvailable(
        in mode: GOALPadGameMode,
        snapshot: NativeCutsceneSkipTouchSnapshot
    ) -> Bool {
        mode == .gameplay && snapshot.isStructurallyValid
            && snapshot.state == .triangleQueryAvailable
    }

    nonisolated static func nativeMenuControlsAreVisible(mode: GOALPadGameMode,
                                                         progress: NativeProgressMenuSnapshot = .unavailable,
                                                         isSuppressed: Bool) -> Bool {
        !isSuppressed && !NativeMenuTouchAction.available(in: mode,
                                                          progress: progress).isEmpty
    }

    nonisolated static func warpGateTouchControlsAreVisible(
        mode: GOALPadGameMode,
        snapshot: NativeWarpGateTouchSnapshot,
        isSuppressed: Bool
    ) -> Bool {
        !isSuppressed
            && !NativeWarpGateTouchAction.available(in: mode, snapshot: snapshot).isEmpty
    }

    nonisolated static func capturesWarpGateTouchInput(
        mode: GOALPadGameMode,
        snapshot: NativeWarpGateTouchSnapshot,
        retainingAfterInvalidRead: Bool = false
    ) -> Bool {
        guard mode == .gameplay else { return false }
        guard snapshot.isStructurallyValid else { return retainingAfterInvalidRead }
        return switch snapshot.state {
        case .destinationListActive, .transitioning:
            true
        case .unavailable, .circleUseAvailable:
            false
        }
    }

    nonisolated static func capturesNativeMenuInput(mode: GOALPadGameMode) -> Bool {
        switch mode {
        case .pause, .progress, .menu:
            true
        case .unknown, .gameplay:
            false
        @unknown default:
            false
        }
    }

    nonisolated private static func radialDeflection(from origin: CGPoint,
                                                     to point: CGPoint,
                                                     radius: CGFloat,
                                                     deadzone: CGFloat = 0) -> CGPoint {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > deadzone else { return .zero }
        let scale = (min(length, radius) - deadzone) / (radius - deadzone) / length
        return CGPoint(x: dx * scale, y: dy * scale)
    }

    private static func axes(_ deflection: CGPoint) -> (x: UInt8, y: UInt8) {
        (byte(deflection.x), byte(deflection.y))
    }

    private static func byte(_ deflection: CGFloat) -> UInt8 {
        let scaled = CGFloat(GOALPadAnalogNeutral) + deflection * 127
        return UInt8(max(0, min(255, scaled.rounded())))
    }

    private static func distance(_ from: CGPoint, _ to: CGPoint) -> CGFloat {
        let dx = to.x - from.x
        let dy = to.y - from.y
        return (dx * dx + dy * dy).squareRoot()
    }

    // MARK: - Presses

    private func press(_ button: TouchButton) {
        pulses[button, default: Pulse()].press()
    }

    private func enqueueHaptic(_ event: TouchHapticEvent) {
        hapticEvents.append(event)
    }

    private struct PinchZoom {
        enum Direction {
            case zoomIn
            case zoomOut
        }

        private var isActive = false
        private var direction: Direction?

        mutating func begin() {
            isActive = true
            direction = nil
        }

        mutating func recognize(scale: CGFloat) -> Direction? {
            guard isActive, direction == nil else { return nil }
            let recognized: Direction
            if scale >= 1 + TouchControls.pinchScaleDelta {
                recognized = .zoomIn
            } else if scale <= 1 - TouchControls.pinchScaleDelta {
                recognized = .zoomOut
            } else {
                return nil
            }
            direction = recognized
            return recognized
        }

        mutating func reset() {
            isActive = false
            direction = nil
        }
    }

    /// Converts strong movement into one repeated dominant-axis D-pad direction for menus.
    private struct DirectionRepeat {
        private var direction: TouchButton?
        private var frames = 0
        private var nextRepeat = 0

        mutating func advance(push: CGPoint) -> TouchButton? {
            let threshold = direction == nil ? TouchControls.dpadPress : TouchControls.dpadRelease
            let pushed = Self.direction(of: push, beyond: threshold)
            guard pushed == direction else {
                direction = pushed
                frames = 0
                nextRepeat = TouchControls.dpadRepeatDelay
                return pushed
            }
            guard direction != nil else { return nil }
            frames += 1
            guard frames >= nextRepeat else { return nil }
            nextRepeat = frames + TouchControls.dpadRepeatInterval
            return direction
        }

        private static func direction(of push: CGPoint, beyond threshold: CGFloat) -> TouchButton? {
            let horizontal = abs(push.x) > abs(push.y)
            let along = horizontal ? push.x : push.y
            guard abs(along) >= threshold else { return nil }
            if horizontal { return along < 0 ? .left : .right }
            return along < 0 ? .up : .down
        }
    }

    private struct Pulse {
        var holdRemaining = 0
        var gapRemaining = 0
        var queued = 0

        mutating func press() {
            if holdRemaining == 0 && gapRemaining == 0 {
                holdRemaining = TouchControls.holdFrames
            } else {
                queued += 1
            }
        }

        mutating func sustain() {
            if holdRemaining > 0 { holdRemaining = max(holdRemaining, 2) }
        }

        mutating func advance() -> Bool {
            if holdRemaining == 0, gapRemaining == 0, queued > 0 {
                queued -= 1
                holdRemaining = TouchControls.holdFrames
            }
            if holdRemaining > 0 {
                holdRemaining -= 1
                if holdRemaining == 0 { gapRemaining = TouchControls.releaseFrames }
                return true
            }
            if gapRemaining > 0 { gapRemaining -= 1 }
            return false
        }
    }

    // MARK: - Visibility

    private func engage() {
        fadeToken += 1
        isEngaged = true
    }

    private func fadeWhenIdle() {
        guard touches.isEmpty else { return }
        fadeToken += 1
        let token = fadeToken
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.fadeOutDelay))
            guard let self, token == fadeToken, touches.isEmpty else { return }
            isEngaged = false
        }
    }
}

private extension CGRect {
    var centre: CGPoint { CGPoint(x: midX, y: midY) }
}
