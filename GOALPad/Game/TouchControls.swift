import Foundation
import OSLog

nonisolated private let touchLog = Logger(subsystem: "com.zephyrstudiosllc.eco",
                                          category: "Touch")

/// The PS2 buttons the on-screen controls drive.
enum TouchButton: Int, CaseIterable, Hashable, Sendable {
    case cross, square, circle, crouch, start, select, stats
    case up, down, left, right
    case triangle, leftShoulder, rightShoulder, rightStickPress

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
        case .rightStickPress: .R3
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
        case .rightStickPress: "R3"
        }
    }
}

enum TouchControlStyle: String, CaseIterable, Sendable {
    case modern
    case classic
}

/// The game-specific semantics layered over the shared raw touch surface.
enum TouchGameTitle: Equatable, Sendable {
    case jak1
    case jak2
}

/// Jak II maps its four gun mods directly to the physical D-pad.
enum Jak2WeaponTouchAction: CaseIterable, Equatable, Hashable, Sendable {
    case scatterGun
    case peaceMaker
    case blaster
    case vulcanFury

    enum Tint: Equatable, Sendable {
        case red
        case dark
        case yellow
        case blue

        struct RGB: Equatable, Sendable {
            let red: Double
            let green: Double
            let blue: Double
        }

        var rgb: RGB {
            switch self {
            case .red: RGB(red: 0.65, green: 0, blue: 0)
            case .dark: RGB(red: 0.6875, green: 0.6, blue: 0.78125)
            case .yellow: RGB(red: 1, green: 0.75, blue: 0.125)
            case .blue: RGB(red: 0.4375, green: 0.8125, blue: 1)
            }
        }
    }

    var button: TouchButton {
        switch self {
        case .scatterGun: .up
        case .peaceMaker: .right
        case .blaster: .down
        case .vulcanFury: .left
        }
    }

    var tint: Tint {
        switch self {
        case .scatterGun: .red
        case .peaceMaker: .dark
        case .blaster: .yellow
        case .vulcanFury: .blue
        }
    }

    var weaponName: String {
        switch self {
        case .scatterGun: "Scatter Gun"
        case .peaceMaker: "Peace Maker"
        case .blaster: "Blaster"
        case .vulcanFury: "Vulcan Fury"
        }
    }
}

extension TouchLayoutAction {
    var touchButton: TouchButton? {
        switch self {
        case .movementStick, .cameraStick: nil
        case .cross: .cross
        case .square: .square
        case .circle: .circle
        case .crouch: .crouch
        case .triangle: .triangle
        case .dpadUp: .up
        case .dpadDown: .down
        case .dpadLeft: .left
        case .dpadRight: .right
        case .select: .select
        case .stats: .stats
        case .start: .start
        case .leftShoulder: .leftShoulder
        case .rightShoulder: .rightShoulder
        }
    }
}

/// Jak II's source-proven progress/save-flow meaning, independent of Jak 1 screen numbers.
struct NativeJak2ProgressMenuSemanticSnapshot: Equatable {
    enum Phase: Equatable {
        case unavailable
        case selectSaveTitle
        case noMemoryCard
        case createGame
        case creating
        case saving
        case existingSaveOverwrite
        case saveIconInformation
        case selectLoad
        case selectSave
        case loading
    }

    let available: Bool
    let phase: Phase
    let optionIndex: Int
    let actionMask: UInt32

    static let unavailable = NativeJak2ProgressMenuSemanticSnapshot(
        available: false, phase: .unavailable, optionIndex: -1, actionMask: 0)

    init(available: Bool, phase: Phase, optionIndex: Int, actionMask: UInt32) {
        self.available = available
        self.phase = phase
        self.optionIndex = optionIndex
        self.actionMask = actionMask
    }

    init(_ snapshot: GOALPadJak2ProgressMenuSemanticSnapshot) {
        let semanticPhase: Phase = switch snapshot.phase {
        case .selectSaveTitle: .selectSaveTitle
        case .noMemoryCard: .noMemoryCard
        case .createGame: .createGame
        case .creating: .creating
        case .saving: .saving
        case .existingSaveOverwrite: .existingSaveOverwrite
        case .saveIconInformation: .saveIconInformation
        case .selectLoad: .selectLoad
        case .selectSave: .selectSave
        case .loading: .loading
        case .unavailable: .unavailable
        @unknown default: .unavailable
        }
        self.init(available: snapshot.available.boolValue, phase: semanticPhase,
                  optionIndex: Int(snapshot.optionIndex), actionMask: snapshot.actionMask)
    }
}

/// The read-only progress state that Swift uses to expose only screen-proven touch semantics.
struct NativeProgressMenuSnapshot: Equatable {
    let available: Bool
    let screenRawValue: Int
    let optionIndex: Int
    let selectedOption: Bool
    let inTransition: Bool
    let navigationAvailable: Bool
    let startingScreenRawValue: Int
    let canExitWithStart: Bool
    let canGoBack: Bool
    let jak2Semantic: NativeJak2ProgressMenuSemanticSnapshot

    static let unavailable = NativeProgressMenuSnapshot(
        available: false, screenRawValue: -2, optionIndex: -1,
        selectedOption: false, inTransition: false, navigationAvailable: false,
        startingScreenRawValue: -2, canExitWithStart: false, canGoBack: false,
        jak2Semantic: .unavailable)

    init(available: Bool, screenRawValue: Int, optionIndex: Int,
         selectedOption: Bool, inTransition: Bool,
         navigationAvailable: Bool = false, startingScreenRawValue: Int = -2,
         canExitWithStart: Bool = false, canGoBack: Bool = false,
         jak2Semantic: NativeJak2ProgressMenuSemanticSnapshot = .unavailable) {
        self.available = available
        self.screenRawValue = screenRawValue
        self.optionIndex = optionIndex
        self.selectedOption = selectedOption
        self.inTransition = inTransition
        self.navigationAvailable = navigationAvailable
        self.startingScreenRawValue = startingScreenRawValue
        self.canExitWithStart = canExitWithStart
        self.canGoBack = canGoBack
        self.jak2Semantic = jak2Semantic
    }

    init(_ snapshot: GOALPadProgressMenuSnapshot,
         jak2Semantic: NativeJak2ProgressMenuSemanticSnapshot = .unavailable) {
        available = snapshot.available.boolValue
        screenRawValue = snapshot.screen.rawValue
        optionIndex = Int(snapshot.optionIndex)
        selectedOption = snapshot.selectedOption.boolValue
        inTransition = snapshot.inTransition.boolValue
        navigationAvailable = snapshot.navigationAvailable.boolValue
        startingScreenRawValue = snapshot.startingScreen.rawValue
        canExitWithStart = snapshot.canExitWithStart.boolValue
        canGoBack = snapshot.canGoBack.boolValue
        self.jak2Semantic = jak2Semantic
    }
}

/// App-session presentation derived from Jak's exact title target states.
nonisolated enum GameplayRunReadiness: Equatable, Sendable {
    case preRun
    case titlePrompt
    case titleMenu
    case active

    nonisolated static func advance(
        _ current: Self,
        mode: GOALPadGameMode,
        titleStartState: GOALPadTitleStartState,
        progress: NativeProgressMenuSnapshot
    ) -> Self {
        if mode == .gameplay, titleStartState == .awaiting { return .titlePrompt }
        if mode == .gameplay, titleStartState == .titleOpening { return .titlePrompt }
        if mode == .gameplay, titleStartState == .titleSequence { return .titlePrompt }
        if mode == .gameplay, titleStartState == .notAwaiting { return .active }
        if current == .titlePrompt, mode == .progress { return .titleMenu }
        if mode == .progress, progress.available,
           progress.startingScreenRawValue == 27 { return .titleMenu }
        return current
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

/// GOAL publishes this only while a source-audited Triangle skip is available: either the central
/// `process-taskable` spooled-animation query or the gated end-credits loop. Native freshness
/// validation makes a stopped heartbeat invalid without changing the stable owner/state generation.
struct NativeCutsceneSkipTouchSnapshot: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case unavailable
        case triangleQueryAvailable
        case creditsTriangleAvailable
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
        case .creditsTriangleAvailable: .creditsTriangleAvailable
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

    static func creditsTriangleAvailable(sequence: UInt32) -> Self {
        Self(valid: true, state: .creditsTriangleAvailable, sequence: sequence)
    }

    static func validUnavailable(sequence: UInt32) -> Self {
        Self(valid: true, state: .unavailable, sequence: sequence)
    }

    var isStructurallyValid: Bool {
        valid && sequence & 1 == 0
    }
}

/// A freshness-checked set of ordinary face buttons requested by the active GOAL interaction.
/// Only the four public pad bits are accepted; unknown or in-progress publications fail closed.
struct NativeFacePromptTouchSnapshot: Equatable, Sendable {
    static let triangleMask: UInt32 = 1 << 12
    static let circleMask: UInt32 = 1 << 13
    static let crossMask: UInt32 = 1 << 14
    static let squareMask: UInt32 = 1 << 15
    static let supportedMask = triangleMask | circleMask | crossMask | squareMask

    let valid: Bool
    let requestedButtons: UInt32
    let sequence: UInt32

    static let invalid = NativeFacePromptTouchSnapshot(
        valid: false, requestedButtons: 0, sequence: 0)

    init(valid: Bool, requestedButtons: UInt32, sequence: UInt32) {
        self.valid = valid
        self.requestedButtons = requestedButtons
        self.sequence = sequence
    }

    init(_ snapshot: GOALPadFacePromptTouchSnapshot) {
        let candidate = Self(valid: snapshot.valid.boolValue,
                             requestedButtons: snapshot.requestedButtons,
                             sequence: snapshot.sequence)
        self = candidate.isStructurallyValid ? candidate : .invalid
    }

    var isStructurallyValid: Bool {
        valid && sequence & 1 == 0 && requestedButtons != 0
            && requestedButtons & ~Self.supportedMask == 0
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

/// The visual order is stable and deliberately independent from the native bit order.
enum NativeFacePromptTouchAction: CaseIterable, Hashable, Sendable {
    case cross
    case square
    case triangle
    case circle

    var button: TouchButton {
        switch self {
        case .cross: .cross
        case .square: .square
        case .triangle: .triangle
        case .circle: .circle
        }
    }

    var requestedMask: UInt32 {
        switch self {
        case .cross: NativeFacePromptTouchSnapshot.crossMask
        case .square: NativeFacePromptTouchSnapshot.squareMask
        case .triangle: NativeFacePromptTouchSnapshot.triangleMask
        case .circle: NativeFacePromptTouchSnapshot.circleMask
        }
    }

    var glyph: String {
        switch self {
        case .cross: "×"
        case .square: "□"
        case .triangle: "△"
        case .circle: "○"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .cross: "Cross button"
        case .square: "Square button"
        case .triangle: "Triangle button"
        case .circle: "Circle button"
        }
    }

    nonisolated static func available(
        in mode: GOALPadGameMode,
        snapshot: NativeFacePromptTouchSnapshot,
        warpGateControlsVisible: Bool,
        warpGateCapturesInput: Bool,
        cutsceneSkipAvailable: Bool
    ) -> [Self] {
        guard mode == .gameplay, snapshot.isStructurallyValid,
              !warpGateControlsVisible, !warpGateCapturesInput else { return [] }
        return allCases.filter { action in
            snapshot.requestedButtons & action.requestedMask != 0
                && !(cutsceneSkipAvailable && action == .triangle)
        }
    }
}

/// Touch-friendly actions whose meanings are authoritative for the current native game state.
enum NativeMenuTouchAction: CaseIterable, Hashable, Sendable {
    case up, down, left, right
    case confirm, back, cancel, jak2Back, start, pause, resume
    case fuelCells, precursorOrbs, scoutFlies, settings

    /// Boxed-array lengths installed by Jak 1's shipping PC `init-game-options` override.
    private enum ShippingPCOptionCount {
        static let settingsWithoutSecrets = 8
        static let settingsWithSecrets = 9
        static let gameSettings = 10
        static let graphicSettings = 4
        static let soundSettings = 4
        static let title = 6
        static let settingsTitle = 4
    }

    /// Exact `progress-screen` values from Jak 1's checked PC enum.
    private enum ShippingPCScreen {
        static let memoryCardDataExists = 11
        static let quit = 34
        static let quitTitle = 58

        /// Screens mapped to OpenGOAL's one-row `*ok-options*` array and handled by
        /// `respond-memcard` with the ordinary Cross button.
        static func isConfirmOnlyNotice(_ screen: Int) -> Bool {
            switch screen {
            case 7, 8, 9, 19, 20, 21, 22, 24, 25, 26, 29, 32, 33, 61:
                true
            default:
                false
            }
        }
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
        case .jak2Back: .triangle
        case .start, .pause, .resume: .start
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
        case .jak2Back: "Back"
        case .start: "Start"
        case .pause: "Pause"
        case .resume: "Resume"
        case .fuelCells: "Cells"
        case .precursorOrbs: "Orbs"
        case .scoutFlies: "Flies"
        case .settings: "Options"
        }
    }

    var systemImage: String {
        switch self {
        case .up: "chevron.up"
        case .down: "chevron.down"
        case .left: "chevron.left"
        case .right: "chevron.right"
        case .confirm: "xmark"
        case .back, .cancel: "circle"
        case .jak2Back: "triangle"
        case .start: "play.fill"
        case .pause: "pause.fill"
        case .resume: "play.fill"
        case .fuelCells: "square"
        case .precursorOrbs: "xmark"
        case .scoutFlies: "triangle"
        case .settings: "circle"
        }
    }

    nonisolated static func available(
        in mode: GOALPadGameMode,
        progress: NativeProgressMenuSnapshot = .unavailable,
        titleStartState: GOALPadTitleStartState = .unknown,
        gameTitle: TouchGameTitle = .jak1,
        runReadiness: GameplayRunReadiness = .active
    ) -> [Self] {
        return switch mode {
        case .pause:
            gameTitle == .jak2
                ? [.up, .down, .left, .right, .jak2Back, .confirm]
                : []
        case .menu:
            [.up, .down, .left, .right, .back, .confirm]
        case .progress:
            if gameTitle == .jak2, runReadiness == .active,
               !progress.available, !progress.jak2Semantic.available {
                [.up, .down, .left, .right, .jak2Back, .confirm]
            } else {
                progressActions(for: progress)
            }
        case .unknown, .gameplay:
            []
        @unknown default:
            []
        }
    }

    nonisolated static func isEnabled(
        _ action: Self,
        in mode: GOALPadGameMode,
        progress: NativeProgressMenuSnapshot,
        titleStartState: GOALPadTitleStartState,
        runReadiness: GameplayRunReadiness = .active,
        gameTitle: TouchGameTitle = .jak1
    ) -> Bool {
        if let session = NativeSessionControlPresentation.reduce(
            mode: mode, titleStartState: titleStartState, progress: progress,
            runReadiness: runReadiness, gameTitle: gameTitle),
           action == session.action {
            return session.isEnabled
        }
        return available(in: mode, progress: progress,
                         titleStartState: titleStartState,
                         gameTitle: gameTitle,
                         runReadiness: runReadiness).contains(action)
    }

    nonisolated private static func progressActions(
        for snapshot: NativeProgressMenuSnapshot
    ) -> [Self] {
        if snapshot.jak2Semantic.available {
            return jak2ProgressActions(for: snapshot.jak2Semantic)
        }
        guard snapshot.available, !snapshot.inTransition else { return [] }

        if ShippingPCScreen.isConfirmOnlyNotice(snapshot.screenRawValue) {
            guard snapshot.optionIndex == 0, !snapshot.selectedOption else { return [] }
            return [.confirm]
        }

        var actions: [Self]
        switch snapshot.screenRawValue {
        case 0:
            guard !snapshot.selectedOption else { return [] }
            actions = [.up, .down, .left, .right,
                       .precursorOrbs, .fuelCells, .scoutFlies, .settings]
        case 1, 2:
            guard !snapshot.selectedOption else { return [] }
            actions = [.up, .down, .precursorOrbs, .fuelCells, .scoutFlies, .settings]
        case 3:
            // The snapshot does not expose whether secrets are unlocked, so accept the larger of
            // the two authoritative shipping arrays while still rejecting every later index.
            actions = commonOptions(
                for: snapshot, optionCount: ShippingPCOptionCount.settingsWithSecrets)
        case 4:
            actions = commonOptions(for: snapshot,
                                    optionCount: ShippingPCOptionCount.gameSettings)
        case 5:
            actions = commonOptions(for: snapshot,
                                    optionCount: ShippingPCOptionCount.graphicSettings)
        case 6:
            actions = commonOptions(for: snapshot,
                                    optionCount: ShippingPCOptionCount.soundSettings)
        case 27:
            actions = commonOptions(for: snapshot,
                                    optionCount: ShippingPCOptionCount.title)
        case 28:
            actions = commonOptions(for: snapshot,
                                    optionCount: ShippingPCOptionCount.settingsTitle)
        case ShippingPCScreen.memoryCardDataExists:
            guard snapshot.optionIndex == 0, !snapshot.selectedOption else { return [] }
            // The one-row yes/no responder selects Yes with Left, No with Right, then
            // `respond-memcard` confirms the current choice with Cross.
            return [.left, .right, .confirm]
        case ShippingPCScreen.quit, ShippingPCScreen.quitTitle:
            guard snapshot.optionIndex == 0 else { return [] }
            // The one-row yes/no responder selects No with Right, then exits on Confirm.
            // Jak's can-go-back responder excludes both quit screens, so Square would be inert.
            return [.left, .right, .confirm]
        case 16, 17:
            actions = fileOptions(for: snapshot, optionCount: 5)
        case 18:
            actions = fileOptions(for: snapshot, optionCount: 6)
        default:
            actions = []
        }
        let isStatsScreen = (0...2).contains(snapshot.screenRawValue)
        if snapshot.canGoBack, !isStatsScreen, !snapshot.selectedOption,
           !actions.contains(.back) {
            actions.insert(.back, at: max(0, actions.count - 1))
        }
        return actions
    }

    nonisolated private static func jak2ProgressActions(
        for snapshot: NativeJak2ProgressMenuSemanticSnapshot
    ) -> [Self] {
        let up = UInt32(1 << 0)
        let down = UInt32(1 << 1)
        let left = UInt32(1 << 2)
        let right = UInt32(1 << 3)
        let confirm = UInt32(1 << 4)
        let back = UInt32(1 << 5)

        switch snapshot.phase {
        case .selectSaveTitle:
            guard (0...4).contains(snapshot.optionIndex),
                  snapshot.actionMask == (up | down | confirm | back) else { return [] }
            return [.up, .down, .jak2Back, .confirm]
        case .selectLoad, .selectSave:
            guard (0...3).contains(snapshot.optionIndex),
                  snapshot.actionMask == (up | down | confirm | back) else { return [] }
            return [.up, .down, .jak2Back, .confirm]
        case .noMemoryCard:
            guard snapshot.optionIndex == 0,
                  snapshot.actionMask == confirm else { return [] }
            return [.confirm]
        case .createGame, .existingSaveOverwrite:
            guard snapshot.optionIndex == 0,
                  snapshot.actionMask == (left | right | confirm | back) else { return [] }
            return [.left, .right, .jak2Back, .confirm]
        case .saveIconInformation:
            guard snapshot.optionIndex == 0,
                  snapshot.actionMask == confirm else { return [] }
            return [.confirm]
        case .creating, .saving, .loading:
            guard snapshot.optionIndex == 0, snapshot.actionMask == 0 else { return [] }
            return []
        case .unavailable:
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

nonisolated struct NativeSessionControlPresentation: Equatable, Sendable {
    let action: NativeMenuTouchAction
    let isEnabled: Bool

    static func reduce(
        mode: GOALPadGameMode,
        titleStartState: GOALPadTitleStartState,
        progress: NativeProgressMenuSnapshot,
        runReadiness: GameplayRunReadiness = .active,
        gameTitle: TouchGameTitle = .jak1
    ) -> Self? {
        switch mode {
        case .gameplay:
            switch titleStartState {
            case .awaiting: return Self(action: .start, isEnabled: true)
            case .titleOpening: return Self(action: .start, isEnabled: false)
            case .notAwaiting, .unknown:
                return runReadiness == .active
                    ? Self(action: .pause, isEnabled: true)
                    : nil
            case .titleSequence:
                return nil
            @unknown default:
                return nil
            }
        case .pause, .menu:
            return Self(action: .resume, isEnabled: true)
        case .progress:
            if gameTitle == .jak2, runReadiness == .active,
               !progress.available, !progress.jak2Semantic.available {
                return Self(action: .resume, isEnabled: true)
            }
            guard progress.navigationAvailable else { return nil }
            let action: NativeMenuTouchAction = runReadiness == .active
                && progress.startingScreenRawValue != 27 ? .resume : .start
            return Self(action: action, isEnabled: progress.canExitWithStart)
        case .unknown:
            return nil
        @unknown default:
            return nil
        }
    }
}

/// App-owned settings appears only after the native session has crossed the initial title gate.
nonisolated enum NativeEcoSettingsPresentation {
    static func isVisible(
        mode: GOALPadGameMode,
        progress: NativeProgressMenuSnapshot,
        runReadiness: GameplayRunReadiness
    ) -> Bool {
        guard runReadiness == .active || runReadiness == .titleMenu else { return false }
        return switch mode {
        case .pause, .menu:
            true
        case .progress:
            progress.available && !progress.inTransition
        case .unknown, .gameplay:
            false
        @unknown default:
            false
        }
    }
}

/// A fixed content grid keeps every right-stack command aligned across title and pause menus.
nonisolated struct NativeMenuCommandLayout: Equatable, Sendable {
    static let width: CGFloat = 148
    static let height: CGFloat = 60
    static let directionSpacing: CGFloat = 8
    static let portraitGroupSpacing: CGFloat = 12
    static let horizontalInset: CGFloat = 16
    static let iconColumnWidth: CGFloat = 20
    static let iconTextSpacing: CGFloat = 10

    static let directionPadHeight = height * 2 + directionSpacing
}

/// A discrete, app-owned touch action that may receive device feedback.
/// These are intentionally separate from native game/controller rumble.
enum TouchHapticEvent: Equatable {
    case button(TouchButton)
    case gesture(TouchButton)
}

/// Lays out the app-owned session pills and an independent circular zoom control.
struct ModernTouchChromeLayout: Equatable, Sendable {
    nonisolated static let pillSize = CGSize(width: 118, height: 42)
    nonisolated static let pillSpacing: CGFloat = 20
    nonisolated static let settingsDiameter: CGFloat = 42
    nonisolated static let zoomDiameter: CGFloat = 42
    nonisolated static let zoomGap: CGFloat = pillSpacing
    nonisolated static let bottomInset: CGFloat = 30
    nonisolated static let compactPillSize = CGSize(width: 92, height: 38)
    nonisolated static let compactPillSpacing: CGFloat = 8
    nonisolated static let compactBottomInset: CGFloat = 16

    let zoomFrame: CGRect
    let statsFrame: CGRect
    let startFrame: CGRect
    let settingsFrame: CGRect
    let centeredSessionFrame: CGRect

    init(size: CGSize, compact: Bool = false) {
        let width = max(0, size.width)
        let height = max(0, size.height)
        let pillSize = compact ? Self.compactPillSize : Self.pillSize
        let pillSpacing = compact ? Self.compactPillSpacing : Self.pillSpacing
        let bottomInset = compact ? Self.compactBottomInset : Self.bottomInset
        let pairWidth = pillSize.width * 2 + pillSpacing
        let stats = CGRect(x: (width - pairWidth) / 2,
                           y: height - bottomInset - pillSize.height,
                           width: pillSize.width, height: pillSize.height)
        statsFrame = stats
        startFrame = stats.offsetBy(dx: pillSize.width + pillSpacing, dy: 0)
        settingsFrame = compact
            ? stats
            : CGRect(x: startFrame.minX - Self.pillSpacing - Self.settingsDiameter,
                     y: startFrame.midY - Self.settingsDiameter / 2,
                     width: Self.settingsDiameter, height: Self.settingsDiameter)
        centeredSessionFrame = CGRect(x: (width - pillSize.width) / 2,
                                      y: stats.minY,
                                      width: pillSize.width,
                                      height: pillSize.height)
        zoomFrame = CGRect(x: stats.minX - Self.zoomGap - Self.zoomDiameter,
                           y: stats.midY - Self.zoomDiameter / 2,
                           width: Self.zoomDiameter, height: Self.zoomDiameter)
    }
}

/// Deterministic Modern artwork geometry. Input radii remain owned by TouchControls.
struct ModernTouchLayout: Sendable {
    static let visualOrder = TouchLayoutControlID.visualOrder(for: .modern)
    static let pillControls = visualOrder.filter {
        switch $0 {
        case .modernSelect, .modernStats, .modernStart: true
        default: false
        }
    }
    static let movementKnobSize: CGFloat = TouchStickSize.small.knobDiameter
    static let movementVisualRadius = TouchStickSize.small.ringDiameter / 2
    static let movementEdgePadding: CGFloat = 95
    static let movementCaptureExtent: CGFloat = 300
    static let rightStickHitSlop: CGFloat = 16
    static let rightStickSpacerCap: CGFloat = 200
    static let portraitStackGap: CGFloat = 4

    private static let pillHitInsets = CGSize(width: 10, height: 12)
    private static let controlGap: CGFloat = 8

    let safeBounds: CGRect
    let rightStickSpacer: CGFloat
    let movementRadius: CGFloat
    let movementKnobSize: CGFloat
    let rightStickRadius: CGFloat
    let rightStickKnobSize: CGFloat
    let movementArtworkFrame: CGRect
    let movementCaptureFrame: CGRect
    let movementHitFrame: CGRect?
    let actionGestureFrame: CGRect
    let actionGestureHitFrame: CGRect?
    let rightStickArtworkFrame: CGRect
    let rightStickHitFrame: CGRect
    let selectPillFrame: CGRect
    let statsPillFrame: CGRect
    let startPillFrame: CGRect
    let settingsButtonFrame: CGRect
    let zoomFrame: CGRect
    let menuControlsBottomInset: CGFloat
    let warpPromptBottomInset: CGFloat

    init(size: CGSize, safeAreaInsets: TouchSafeAreaInsets = .zero,
         customization: TouchLayoutCustomization = .standard,
         usesCompactSessionChrome: Bool = false) {
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

        let movementSize = customization.stickSize(for: .modernMovement)
        let movementStickRadius = movementSize.ringDiameter / 2
        movementRadius = movementStickRadius
        movementKnobSize = movementSize.knobDiameter
        let cameraSize = customization.stickSize(for: .modernCamera)
        let cameraStickRadius = cameraSize.ringDiameter / 2
        rightStickRadius = cameraStickRadius
        rightStickKnobSize = cameraSize.knobDiameter

        let legacyEdge = Self.legacyRightStickEdge(for: bounds.size)
        let targetSpacer = min(Self.rightStickSpacerCap,
                               max(legacyEdge, safe.width * 0.24))
        rightStickSpacer = min(targetSpacer,
                                max(0, safe.width - cameraStickRadius * 2))

        let isPortrait = bounds.height > bounds.width
        let chromeBounds = isPortrait ? safe : bounds
        let chrome = ModernTouchChromeLayout(size: chromeBounds.size,
                                             compact: usesCompactSessionChrome)
        let chromeOffset = chromeBounds.origin
        let defaultSelectPillFrame = chrome.centeredSessionFrame.offsetBy(
            dx: chromeOffset.x, dy: chromeOffset.y)
        let defaultStatsPillFrame = chrome.statsFrame.offsetBy(
            dx: chromeOffset.x, dy: chromeOffset.y)
        let defaultStartPillFrame = chrome.startFrame.offsetBy(
            dx: chromeOffset.x, dy: chromeOffset.y)
        selectPillFrame = Self.resolvedFrame(defaultSelectPillFrame, id: .modernSelect,
                                             customization: customization, safeBounds: safe)
        statsPillFrame = Self.resolvedFrame(defaultStatsPillFrame, id: .modernStats,
                                            customization: customization, safeBounds: safe)
        startPillFrame = Self.resolvedFrame(defaultStartPillFrame, id: .modernStart,
                                            customization: customization, safeBounds: safe)
        settingsButtonFrame = usesCompactSessionChrome
            ? statsPillFrame
            : chrome.settingsFrame.offsetBy(
                dx: chromeOffset.x + startPillFrame.minX - defaultStartPillFrame.minX,
                dy: chromeOffset.y + startPillFrame.minY - defaultStartPillFrame.minY)

        let pillHitFrames = [selectPillFrame, statsPillFrame, startPillFrame].map {
            $0.insetBy(dx: -Self.pillHitInsets.width, dy: -Self.pillHitInsets.height)
        }
        let pillHitTop = pillHitFrames.map(\.minY).min() ?? safe.maxY
        menuControlsBottomInset = isPortrait
            ? max(0, bounds.maxY - (pillHitTop - Self.portraitStackGap))
            : max(20, bottom)
        let portraitStickCentreY = pillHitFrames.map(\.minY).min()
            .map { $0 - Self.controlGap - movementStickRadius }
            ?? safe.maxY - movementStickRadius
        let movementDiameter = movementStickRadius * 2
        let leadingPadding = min(Self.movementEdgePadding,
                                 max(0, safe.width - movementDiameter))
        let bottomPadding = min(Self.movementEdgePadding,
                                max(0, safe.height - movementDiameter))
        let movementCentre = CGPoint(
            x: safe.minX + leadingPadding + movementStickRadius,
            y: isPortrait
                ? portraitStickCentreY
                : safe.maxY - bottomPadding - movementStickRadius)
        let defaultMovementFrame = Self.frame(centre: movementCentre,
                                              diameter: movementDiameter)
        movementArtworkFrame = Self.resolvedFrame(defaultMovementFrame, id: .modernMovement,
                                                  customization: customization, safeBounds: safe)
        let captureMaxX = min(safe.maxX, bounds.midX)
        let captureWidth = min(Self.movementCaptureExtent,
                               max(0, captureMaxX - safe.minX))
        let captureHeight = min(Self.movementCaptureExtent, safe.height)
        if customization.position(for: .modernMovement) != nil {
            let requested = Self.frame(centre: movementArtworkFrame.centre,
                                       size: CGSize(width: captureWidth,
                                                    height: captureHeight))
            movementCaptureFrame = Self.clampedFrame(requested, in: safe)
            movementHitFrame = movementCaptureFrame
        } else {
            movementCaptureFrame = CGRect(x: safe.minX,
                                          y: safe.maxY - captureHeight,
                                          width: captureWidth,
                                          height: captureHeight)
            movementHitFrame = nil
        }

        let radius = cameraStickRadius
        let renderedRightEdge = isPortrait ? safe.maxX : bounds.maxX
        let candidateCentreX = renderedRightEdge - radius - rightStickSpacer
        let rightHitRadius = radius + Self.rightStickHitSlop
        let portraitMinimumCentreX = defaultMovementFrame.maxX
            + Self.controlGap + rightHitRadius
        let centreX = min(safe.maxX - rightHitRadius,
                          max(safe.minX + rightHitRadius,
                              isPortrait ? max(candidateCentreX, portraitMinimumCentreX)
                                         : candidateCentreX))
        let lowestCentreY = isPortrait
            ? pillHitTop - Self.portraitStackGap - rightHitRadius
            : bounds.maxY - radius - legacyEdge
        let candidateHitFrame = Self.frame(centre: CGPoint(x: centreX, y: lowestCentreY),
                                           diameter: radius * 2)
            .insetBy(dx: -Self.rightStickHitSlop, dy: -Self.rightStickHitSlop)
        let overlapsPillHorizontally = pillHitFrames.contains {
            $0.minX < candidateHitFrame.maxX && candidateHitFrame.minX < $0.maxX
        }
        let clearCentreY = pillHitFrames.map(\.minY).min()
            .map { $0 - radius - Self.rightStickHitSlop - Self.controlGap }
            ?? lowestCentreY
        let centreY = isPortrait
            ? max(safe.minY + rightHitRadius, lowestCentreY)
            : max(safe.minY + radius,
                  overlapsPillHorizontally ? min(lowestCentreY, clearCentreY) : lowestCentreY)
        let defaultRightStickFrame = Self.frame(centre: CGPoint(x: centreX, y: centreY),
                                                diameter: radius * 2)
        rightStickArtworkFrame = Self.resolvedFrame(defaultRightStickFrame, id: .modernCamera,
                                                    customization: customization, safeBounds: safe)
        rightStickHitFrame = customization.hasCustomGeometry(for: .modernCamera)
            ? TouchLayoutGeometry.minimumHitFrame(for: rightStickArtworkFrame, in: safe)
            : rightStickArtworkFrame.insetBy(dx: -Self.rightStickHitSlop,
                                              dy: -Self.rightStickHitSlop)

        let defaultGestureFrame = isPortrait
            ? CGRect(x: safe.midX,
                     y: safe.minY,
                     width: safe.maxX - safe.midX,
                     height: max(0, rightStickHitFrame.minY
                                    - Self.portraitStackGap - safe.minY))
            : Self.frame(centre: CGPoint(x: safe.minX + safe.width * 0.75, y: safe.midY),
                         diameter: 176)
        actionGestureFrame = Self.resolvedFrame(defaultGestureFrame, id: .modernActions,
                                                customization: customization, safeBounds: safe)
        actionGestureHitFrame = customization.position(for: .modernActions) == nil
            ? nil
            : TouchLayoutGeometry.minimumHitFrame(for: actionGestureFrame, in: safe)
        warpPromptBottomInset = isPortrait
            ? max(0, bounds.maxY - actionGestureFrame.maxY)
            : max(20, bottom)

        let defaultZoomFrame = chrome.zoomFrame.offsetBy(dx: chromeOffset.x, dy: chromeOffset.y)
        if isPortrait, defaultZoomFrame.minX < safe.minX {
            zoomFrame = Self.frame(
                centre: CGPoint(x: safe.minX + ModernTouchChromeLayout.zoomDiameter / 2,
                                y: defaultMovementFrame.minY
                                    - Self.controlGap
                                    - ModernTouchChromeLayout.zoomDiameter / 2),
                diameter: ModernTouchChromeLayout.zoomDiameter)
        } else {
            zoomFrame = defaultZoomFrame
        }
    }

    static func legacyRightStickEdge(for size: CGSize) -> CGFloat {
        max(28, min(max(0, size.width), max(0, size.height)) * 0.06)
    }

    func frame(for control: TouchLayoutControlID) -> CGRect? {
        switch control {
        case .modernMovement: movementArtworkFrame
        case .modernCamera: rightStickArtworkFrame
        case .modernActions: actionGestureFrame
        case .modernSelect: selectPillFrame
        case .modernStats: statsPillFrame
        case .modernStart: startPillFrame
        default: nil
        }
    }

    func hitFrame(for control: TouchLayoutControlID) -> CGRect? {
        switch control {
        case .modernMovement: movementHitFrame
        case .modernCamera: rightStickHitFrame
        case .modernActions: actionGestureHitFrame
        case .modernSelect:
            customHitFrame(selectPillFrame)
        case .modernStats:
            customHitFrame(statsPillFrame)
        case .modernStart:
            customHitFrame(startPillFrame)
        default: nil
        }
    }

    private func customHitFrame(_ frame: CGRect) -> CGRect {
        TouchLayoutGeometry.minimumHitFrame(for: frame, in: safeBounds)
    }

    private static func resolvedFrame(_ frame: CGRect,
                                      id: TouchLayoutControlID,
                                      customization: TouchLayoutCustomization,
                                      safeBounds: CGRect) -> CGRect {
        guard customization.hasCustomGeometry(for: id) else { return frame }
        return TouchLayoutGeometry.visualFrame(default: frame, control: id,
                                               customization: customization,
                                               safeBounds: safeBounds)
    }

    private static func frame(centre: CGPoint, diameter: CGFloat) -> CGRect {
        frame(centre: centre, size: CGSize(width: diameter, height: diameter))
    }

    private static func frame(centre: CGPoint, size: CGSize) -> CGRect {
        CGRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2,
               width: size.width, height: size.height)
    }

    private static func clampedFrame(_ frame: CGRect, in bounds: CGRect) -> CGRect {
        let fitted = CGSize(width: min(frame.width, bounds.width),
                            height: min(frame.height, bounds.height))
        let centre = CGPoint(
            x: min(max(bounds.minX + fitted.width / 2, frame.midX),
                   bounds.maxX - fitted.width / 2),
            y: min(max(bounds.minY + fitted.height / 2, frame.midY),
                   bounds.maxY - fitted.height / 2))
        return self.frame(centre: centre, size: fitted)
    }
}

/// Mirrors the fixed right-stick frame across the safe-area centre so both controls obey the
/// same inward offset, radius, and vertical-placement rules.
struct Jak2WeaponWheelLayout: Equatable, Sendable {
    let frame: CGRect

    init(modernLayout: ModernTouchLayout) {
        let safe = modernLayout.safeBounds
        let camera = modernLayout.rightStickArtworkFrame
        let diameter = min(camera.width, camera.height, safe.width, safe.height)
        let reflectedCentre = CGPoint(
            x: safe.midX - (camera.midX - safe.midX),
            y: camera.midY)
        var candidate = CGRect(x: reflectedCentre.x - diameter / 2,
                               y: reflectedCentre.y - diameter / 2,
                               width: diameter,
                               height: diameter)
        let movementClearance = modernLayout.movementArtworkFrame.insetBy(dx: -8, dy: -8)
        if candidate.intersects(movementClearance) {
            candidate.origin.y = movementClearance.minY - candidate.height
        }
        let maximumX = max(safe.minX, safe.maxX - candidate.width)
        let maximumY = max(safe.minY, safe.maxY - candidate.height)
        frame = CGRect(x: min(max(candidate.minX, safe.minX), maximumX),
                       y: min(max(candidate.minY, safe.minY), maximumY),
                       width: candidate.width,
                       height: candidate.height)
    }
}

/// Keeps Jak II's holdable R1 beside the camera stick without overlapping its larger hit target.
struct Jak2TraversalTouchLayout: Equatable, Sendable {
    nonisolated static let shoulderDiameter: CGFloat = 44
    nonisolated static let cameraGap: CGFloat = 28

    let rightShoulderFrame: CGRect

    init(modernLayout: ModernTouchLayout) {
        let safe = modernLayout.safeBounds
        let camera = modernLayout.rightStickArtworkFrame
        let diameter = min(Self.shoulderDiameter, safe.width, safe.height)
        let requested = CGRect(
            x: camera.minX - Self.cameraGap - diameter,
            y: camera.midY - diameter / 2,
            width: diameter,
            height: diameter)
        let maximumX = max(safe.minX, safe.maxX - diameter)
        let maximumY = max(safe.minY, safe.maxY - diameter)
        rightShoulderFrame = CGRect(
            x: min(max(requested.minX, safe.minX), maximumX),
            y: min(max(requested.minY, safe.minY), maximumY),
            width: diameter,
            height: diameter)
    }
}

/// Deterministic Classic artwork and app-owned touch targets.
struct ClassicTouchLayout {
    static let minimumButtonHitSize = CGSize(width: 44, height: 44)
    static let visualOrder = TouchLayoutControlID.visualOrder(for: .classic)
    static let buttons: [TouchButton] = visualOrder.compactMap(sourceButton(for:))

    nonisolated static func usesPillArtwork(for button: TouchButton) -> Bool {
        switch button {
        case .select, .stats, .start, .leftShoulder, .rightShoulder:
            true
        default:
            false
        }
    }

    let safeBounds: CGRect
    let stickRadius: CGFloat
    let leftStickRadius: CGFloat
    let rightStickRadius: CGFloat
    let leftStickFrame: CGRect
    let rightStickFrame: CGRect
    /// Artwork geometry. This remains independent from the larger touch targets below.
    let buttonFrames: [TouchButton: CGRect]
    /// Touch geometry for fixed Classic buttons, kept within `safeBounds`.
    let buttonHitFrames: [TouchButton: CGRect]

    init(size: CGSize, safeAreaInsets: TouchSafeAreaInsets = .zero,
         customization: TouchLayoutCustomization = .standard) {
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

        let defaultLeftStickFrame = Self.frame(centre: leftStickCentre, diameter: stickRadius * 2)
        let defaultRightStickFrame = Self.frame(centre: rightStickCentre, diameter: stickRadius * 2)
        leftStickFrame = Self.resolvedFrame(defaultLeftStickFrame, id: .classicMovement,
                                            customization: customization,
                                            safeBounds: boundedSafeBounds)
        rightStickFrame = Self.resolvedFrame(defaultRightStickFrame, id: .classicCamera,
                                             customization: customization,
                                             safeBounds: boundedSafeBounds)
        leftStickRadius = leftStickFrame.width / 2
        rightStickRadius = rightStickFrame.width / 2

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
        let resolvedFrames = Dictionary(uniqueKeysWithValues: frames.map { button, frame in
            let id = Self.controlID(for: button)
            return (button, Self.resolvedFrame(frame, id: id, customization: customization,
                                               safeBounds: boundedSafeBounds))
        })
        buttonFrames = resolvedFrames
        buttonHitFrames = resolvedFrames.mapValues {
            TouchLayoutGeometry.minimumHitFrame(for: $0, in: boundedSafeBounds)
        }
    }

    func frame(for button: TouchButton) -> CGRect? {
        buttonFrames[button]
    }

    func hitFrame(for button: TouchButton) -> CGRect? {
        buttonHitFrames[button]
    }

    func frame(for control: TouchLayoutControlID) -> CGRect? {
        switch control {
        case .classicMovement: return leftStickFrame
        case .classicCamera: return rightStickFrame
        default:
            guard let button = Self.sourceButton(for: control) else { return nil }
            return frame(for: button)
        }
    }

    func hitFrame(for control: TouchLayoutControlID) -> CGRect? {
        switch control {
        case .classicMovement:
            return TouchLayoutGeometry.minimumHitFrame(for: leftStickFrame, in: safeBounds)
        case .classicCamera:
            return TouchLayoutGeometry.minimumHitFrame(for: rightStickFrame, in: safeBounds)
        default:
            guard let button = Self.sourceButton(for: control) else { return nil }
            return hitFrame(for: button)
        }
    }

    static func controlID(for button: TouchButton) -> TouchLayoutControlID {
        switch button {
        case .up: .classicDpadUp
        case .down: .classicDpadDown
        case .left: .classicDpadLeft
        case .right: .classicDpadRight
        case .select: .classicSelect
        case .stats: .classicStats
        case .start: .classicStart
        case .leftShoulder: .classicLeftShoulder
        case .rightShoulder: .classicRightShoulder
        case .rightStickPress: .classicCamera
        case .triangle: .classicTriangle
        case .square: .classicSquare
        case .circle: .classicCircle
        case .cross: .classicCross
        case .crouch: .classicLeftShoulder
        }
    }

    static func sourceButton(for control: TouchLayoutControlID) -> TouchButton? {
        guard control.profile == .classic else { return nil }
        return control.defaultAction?.touchButton
    }

    private static func resolvedFrame(_ frame: CGRect,
                                      id: TouchLayoutControlID,
                                      customization: TouchLayoutCustomization,
                                      safeBounds: CGRect) -> CGRect {
        guard customization.hasCustomGeometry(for: id) else { return frame }
        return TouchLayoutGeometry.visualFrame(default: frame, control: id,
                                               customization: customization,
                                               safeBounds: safeBounds)
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

/// The frozen Build 96 on-screen gameplay controls plus the later native-menu input reducer.
@MainActor
@Observable
final class TouchControls {
    nonisolated static let movementRadius: CGFloat = TouchStickSize.small.ringDiameter / 2
    nonisolated static let movementDeadzone: CGFloat = 4
    nonisolated static let movementResponseExponent: CGFloat = 1.25
    nonisolated static let rightStickRadius: CGFloat = TouchStickSize.small.ringDiameter / 2
    nonisolated static let rightStickDeadzone: CGFloat = 12
    nonisolated static let rollJumpDistance: CGFloat = 44
    nonisolated static let swipeDistance: CGFloat = 44
    nonisolated static let tapDistance: CGFloat = 12
    nonisolated static let nativeMenuSwipeDistance: CGFloat = 44
    nonisolated static let nativeWarpSwipeDistance: CGFloat = 44

    /// Frames a recognised one-shot press remains down, followed by a guaranteed release gap.
    nonisolated static let holdFrames = 2
    nonisolated static let releaseFrames = 1
    /// App-owned gameplay artwork idles away together after the last screen interaction.
    nonisolated static let gameplayChromeFadeOutDelay: TimeInterval = 3

    /// Strong movement pushes also step list-style menus through the D-pad.
    nonisolated static let dpadPress: CGFloat = 0.55
    nonisolated static let dpadRelease: CGFloat = 0.35
    nonisolated static let dpadRepeatDelay = 26
    nonisolated static let dpadRepeatInterval = 10

    private(set) var style: TouchControlStyle
    private(set) var gameTitle: TouchGameTitle
    private(set) var layoutCustomization = TouchLayoutCustomization.standard
    private(set) var dynamicLeftStick = false
    private(set) var nativeMenuMode: GOALPadGameMode = .unknown
    private(set) var progressMenuSnapshot: NativeProgressMenuSnapshot = .unavailable
    private(set) var titleStartState: GOALPadTitleStartState = .unknown
    private(set) var runReadiness: GameplayRunReadiness = .preRun
    private(set) var warpGateTouchSnapshot: NativeWarpGateTouchSnapshot = .invalid
    private(set) var cutsceneSkipTouchSnapshot: NativeCutsceneSkipTouchSnapshot = .invalid
    private(set) var facePromptTouchSnapshot: NativeFacePromptTouchSnapshot = .invalid
    private(set) var speederState: GOALPadSpeederState = .unknown
    @ObservationIgnored private var retainsWarpGateTouchCapture = false

    enum Role: Equatable {
        case movement
        case rightStick
        case gesture
        case pill(TouchButton)
        case skip(NativeCutsceneSkipTouchSnapshot)
    }

    struct SwipeTrailSegment {
        let start: CGPoint
        var end: CGPoint
        let direction: TouchGestureDirection
    }

    struct Tracked: Identifiable {
        let id: ObjectIdentifier
        let role: Role
        /// A per-contact movement origin, fixed right-stick centre, or gesture/pill landing point.
        let origin: CGPoint
        var point: CGPoint
        var travelled: CGFloat = 0
        var swiped: TouchButton? = nil
        var trailSegments: [SwipeTrailSegment] = []
        var trailCandidateDirection: TouchGestureDirection? = nil
        var trailCandidateStart: CGPoint? = nil
        var crouchPeakY: CGFloat? = nil
        var acceleratorPeakY: CGFloat? = nil
        var speederBrakeTriggered = false
        var jumpTriggered = false
        var punchTriggered = false
        var jumpComboTriggered = false
        let radius: CGFloat
        let deadzone: CGFloat
        let responseExponent: CGFloat
    }

    private(set) var touches: [ObjectIdentifier: Tracked] = [:]
    private(set) var isEngaged = false
    private(set) var surfaceSafeAreaInsets = TouchSafeAreaInsets.zero
    @ObservationIgnored private var hapticEvents: [TouchHapticEvent] = []

    var stick: Tracked? { touches.values.first { $0.role == .movement } }
    var rightStick: Tracked? { touches.values.first { $0.role == .rightStick } }
    var gestures: [Tracked] { touches.values.filter { $0.role == .gesture } }
    var hasActiveGameplayGesture: Bool { !gestures.isEmpty }
    var isCrouching: Bool {
        touches.values.contains { $0.role == .gesture && $0.swiped == .crouch }
    }

    func isPillDown(_ button: TouchButton) -> Bool {
        touches.values.contains {
            switch $0.role {
            case .pill(let pressed): pressed == button
            case .skip: button == .stats
            case .movement, .rightStick, .gesture: false
            }
        }
    }

    @ObservationIgnored private var rightStickFrame = CGRect.zero
    @ObservationIgnored private var pillFrames: [TouchButton: CGRect] = [:]
    @ObservationIgnored private var pulses = TouchControls.emptyPulses()
    @ObservationIgnored private var facePromptPulses = TouchControls.emptyPulses()
    @ObservationIgnored private var facePromptHapticEvents: [TouchHapticEvent] = []
    @ObservationIgnored private var fadeToken = 0
    @ObservationIgnored private var dpad = DirectionRepeat()

    init(style: TouchControlStyle = .modern, gameTitle: TouchGameTitle = .jak1) {
        self.style = style
        self.gameTitle = gameTitle
    }

    var capturesNativeMenuInput: Bool {
        Self.capturesNativeMenuInput(mode: nativeMenuMode)
    }

    var capturesNativeTouchInput: Bool {
        capturesNativeMenuInput || capturesWarpGateTouchInput
    }

    var capturesWarpGateTouchInput: Bool {
        Self.capturesWarpGateTouchInput(
            mode: nativeMenuMode,
            snapshot: warpGateTouchSnapshot,
            retainingAfterInvalidRead: retainsWarpGateTouchCapture)
    }

    var contextualFacePromptOwnsGameplayActions: Bool {
        Self.contextualFacePromptOwnsGameplayActions(
            mode: nativeMenuMode,
            runReadiness: runReadiness,
            snapshot: facePromptTouchSnapshot,
            warpGateControlsVisible: Self.warpGateTouchControlsAreVisible(
                mode: nativeMenuMode, snapshot: warpGateTouchSnapshot),
            warpGateCapturesInput: capturesWarpGateTouchInput,
            cutsceneSkipAvailable: Self.cutsceneSkipIsAvailable(
                in: nativeMenuMode, snapshot: cutsceneSkipTouchSnapshot))
    }

    func setStyle(_ style: TouchControlStyle) {
        guard style != self.style else { return }
        reset()
        self.style = style
    }

    func setGameTitle(_ gameTitle: TouchGameTitle) {
        guard gameTitle != self.gameTitle else { return }
        reset()
        self.gameTitle = gameTitle
    }

    func setLayoutCustomization(_ customization: TouchLayoutCustomization) {
        guard customization != layoutCustomization else { return }
        reset()
        layoutCustomization = customization
    }

    func setDynamicLeftStick(_ enabled: Bool) {
        guard enabled != dynamicLeftStick else { return }
        reset()
        dynamicLeftStick = enabled
    }

    /// Compatibility entry point for callers that only have the master-mode classification.
    func setNativeMenuMode(_ mode: GOALPadGameMode) {
        setNativeMenuState(mode, progress: .unavailable, titleStartState: .unknown)
    }

    /// Applies the read-only native menu snapshot. Any semantic transition cancels carried input
    /// before another frame reaches the engine, including progress screen and selection changes.
    func setNativeMenuState(_ mode: GOALPadGameMode,
                            progress: NativeProgressMenuSnapshot,
                            titleStartState: GOALPadTitleStartState = .unknown,
                            runReadiness: GameplayRunReadiness = .active) {
        guard mode != nativeMenuMode || progress != progressMenuSnapshot
                || titleStartState != self.titleStartState
                || runReadiness != self.runReadiness else { return }
        let entersActiveGameplay = mode == .gameplay && runReadiness == .active
            && (nativeMenuMode != .gameplay || self.runReadiness != .active)
        let capturedInput = capturesNativeTouchInput
        nativeMenuMode = mode
        progressMenuSnapshot = progress
        self.titleStartState = titleStartState
        self.runReadiness = runReadiness
        if mode != .gameplay { cancelFacePromptInput() }
        if capturedInput || capturesNativeTouchInput { reset() }
        if contextualFacePromptOwnsGameplayActions {
            cancelOrdinaryGameplayCommandInput()
        }
        if entersActiveGameplay { noteScreenInteraction() }
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
        restoreGameplayChromeAfterInterruption()
    }

    /// Owner/state generation changes and stale native reads cancel a pending SKIP tap.
    func setCutsceneSkipTouchSnapshot(_ snapshot: NativeCutsceneSkipTouchSnapshot) {
        guard snapshot != cutsceneSkipTouchSnapshot else { return }
        cutsceneSkipTouchSnapshot = snapshot
        cancelFacePromptInput()
        let pending = touches.compactMap { id, touch -> ObjectIdentifier? in
            if case .skip = touch.role { return id }
            return nil
        }
        for id in pending { touches.removeValue(forKey: id) }
        if !pending.isEmpty { fadeWhenIdle() }
    }

    /// A semantic or generation change invalidates prompt-owned pulses without disturbing raw
    /// gameplay touches that continue beneath this non-capturing control layer.
    func setFacePromptTouchSnapshot(_ snapshot: NativeFacePromptTouchSnapshot) {
        guard snapshot != facePromptTouchSnapshot else { return }
        facePromptTouchSnapshot = snapshot
        cancelFacePromptInput()
        if contextualFacePromptOwnsGameplayActions {
            cancelOrdinaryGameplayCommandInput()
            noteScreenInteraction()
        }
    }

    /// The native target-state reader is authoritative. Leaving a racer state drops only the
    /// contextual shoulder chord; the original upward Cross gesture remains held until lift.
    func setSpeederState(_ state: GOALPadSpeederState) {
        guard state != speederState else { return }
        speederState = state
        if state != .riding {
            for id in touches.keys {
                touches[id]?.speederBrakeTriggered = false
            }
        }
    }

    /// Emits one ordinary pad pulse. Availability is mode-gated so a stale SwiftUI action cannot
    /// send menu input after the game has returned to gameplay or moved into progress.
    func performNativeMenuAction(_ action: NativeMenuTouchAction,
                                 emitsHaptic: Bool = true) {
        guard NativeMenuTouchAction.isEnabled(action, in: nativeMenuMode,
                                              progress: progressMenuSnapshot,
                                              titleStartState: titleStartState,
                                              runReadiness: runReadiness,
                                              gameTitle: gameTitle)
        else { return }
        noteScreenInteraction()
        press(action.button)
        if emitsHaptic { enqueueHaptic(.button(action.button)) }
    }

    /// Emits the same ordinary D-pad bit as Jak II's physical weapon selector.
    @discardableResult
    func performJak2WeaponSelection(_ action: Jak2WeaponTouchAction) -> Bool {
        guard Self.jak2WeaponWheelIsVisible(
            gameTitle: gameTitle,
            mode: nativeMenuMode,
            runReadiness: runReadiness,
            isAwaitingTitleStart: titleStartState == .awaiting
                || titleStartState == .titleOpening
                || titleStartState == .titleSequence),
              !capturesNativeTouchInput else { return false }
        noteScreenInteraction()
        press(action.button)
        enqueueHaptic(.button(action.button))
        return true
    }

    /// The compact STATS pill mirrors the physical L2+R2 chord while the native pause owner has
    /// captured raw gameplay touches. Progress screens keep it visible but inert.
    func performCapturedStats() {
        guard nativeMenuMode == .pause else { return }
        noteScreenInteraction()
        press(.stats)
        enqueueHaptic(.button(.stats))
    }

    /// Converts one completed, predominantly vertical list swipe into one ordinary D-pad pulse.
    @discardableResult
    func performNativeMenuVerticalSwipe(translation: CGSize) -> Bool {
        let actions = NativeMenuTouchAction.available(in: nativeMenuMode,
                                                      progress: progressMenuSnapshot,
                                                      gameTitle: gameTitle,
                                                      runReadiness: runReadiness)
        guard abs(translation.height) >= Self.nativeMenuSwipeDistance,
              abs(translation.height) > abs(translation.width) else { return false }
        let action: NativeMenuTouchAction = translation.height < 0 ? .up : .down
        guard actions.contains(action) else { return false }
        performNativeMenuAction(action, emitsHaptic: false)
        return true
    }

    /// Emits only when the view's full source snapshot, including its sequence, is still current.
    func performNativeWarpGateAction(_ action: NativeWarpGateTouchAction,
                                     for expectedSnapshot: NativeWarpGateTouchSnapshot) {
        guard expectedSnapshot == warpGateTouchSnapshot,
              NativeWarpGateTouchAction.available(in: nativeMenuMode,
                                                  snapshot: warpGateTouchSnapshot).contains(action)
        else { return }
        noteScreenInteraction()
        press(action.button)
        enqueueHaptic(.button(action.button))
    }

    /// A completed tap emits the ordinary Triangle edge only if its full GOAL generation remains
    /// current and gameplay mode has not changed since touch-down.
    func performCutsceneSkip(for expectedSnapshot: NativeCutsceneSkipTouchSnapshot) {
        guard expectedSnapshot == cutsceneSkipTouchSnapshot,
              Self.cutsceneSkipIsAvailable(in: nativeMenuMode,
                                           snapshot: cutsceneSkipTouchSnapshot)
        else { return }
        noteScreenInteraction()
        press(.triangle)
        enqueueHaptic(.button(.triangle))
    }

    /// Emits one exact ordinary face-button pulse only while the complete source snapshot and
    /// every higher-priority semantic owner remain current.
    func performFacePromptAction(_ action: NativeFacePromptTouchAction,
                                 for expectedSnapshot: NativeFacePromptTouchSnapshot) {
        let warpVisible = Self.warpGateTouchControlsAreVisible(
            mode: nativeMenuMode, snapshot: warpGateTouchSnapshot)
        let cutsceneAvailable = Self.cutsceneSkipIsAvailable(
            in: nativeMenuMode, snapshot: cutsceneSkipTouchSnapshot)
        guard expectedSnapshot == facePromptTouchSnapshot,
              NativeFacePromptTouchAction.available(
                in: nativeMenuMode,
                snapshot: facePromptTouchSnapshot,
                warpGateControlsVisible: warpVisible,
                warpGateCapturesInput: capturesWarpGateTouchInput,
                cutsceneSkipAvailable: cutsceneAvailable).contains(action)
        else { return }
        noteScreenInteraction()
        facePromptPulses[action.button.rawValue].press()
        facePromptHapticEvents.append(.button(action.button))
    }

    /// The destination responder is Left/Right-driven. A completed horizontal swipe maps to
    /// exactly one of those source semantics; vertical or diagonal intent remains inert.
    @discardableResult
    func performNativeWarpGateSwipe(translation: CGSize,
                                    for expectedSnapshot: NativeWarpGateTouchSnapshot) -> Bool {
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

    /// Build 96 owns ordinary gameplay hit testing independently from compatibility settings.
    private func build96Role(for point: CGPoint, in size: CGSize,
                             safeAreaInsets: TouchSafeAreaInsets) -> Role? {
        for (button, frame) in pillFrames where frame.contains(point) {
            if !contextualFacePromptOwnsGameplayActions { return pillRole(for: button) }
        }
        if !contextualFacePromptOwnsGameplayActions,
           rightStick == nil, rightStickFrame.contains(point) { return .rightStick }
        if stick == nil {
            if dynamicLeftStick, point.x < size.width / 2 { return .movement }
            if !dynamicLeftStick {
                let layout = ModernTouchLayout(size: size, safeAreaInsets: safeAreaInsets,
                                               customization: layoutCustomization)
                if layout.movementCaptureFrame.contains(point) { return .movement }
            }
        }
        if !contextualFacePromptOwnsGameplayActions, point.x >= size.width / 2 {
            if size.height > size.width {
                let layout = ModernTouchLayout(size: size, safeAreaInsets: safeAreaInsets)
                guard layout.actionGestureFrame.contains(point) else { return nil }
            }
            return .gesture
        }
        return nil
    }

    // MARK: - Touches

    func began(_ id: ObjectIdentifier, at point: CGPoint, in size: CGSize,
               safeAreaInsets: TouchSafeAreaInsets = .zero, at _: TimeInterval) {
        guard !capturesNativeTouchInput else { return }
        guard let role = build96Role(for: point, in: size,
                                     safeAreaInsets: safeAreaInsets) else { return }
        let layout = ModernTouchLayout(size: size, safeAreaInsets: safeAreaInsets,
                                       customization: layoutCustomization)
        let origin: CGPoint
        let radius: CGFloat
        let deadzone: CGFloat
        let responseExponent: CGFloat
        switch role {
        case .movement:
            origin = point
            radius = layout.movementRadius
            deadzone = dynamicLeftStick ? 0 : Self.movementDeadzone
            responseExponent = dynamicLeftStick ? 1 : Self.movementResponseExponent
        case .rightStick:
            origin = rightStickFrame.centre
            radius = layout.rightStickRadius
            deadzone = Self.rightStickDeadzone * layout.rightStickRadius
                / (TouchStickSize.small.ringDiameter / 2)
            responseExponent = 1
        case .gesture:
            origin = point
            radius = 0
            deadzone = 0
            responseExponent = 1
        case .pill, .skip:
            origin = point
            radius = 0
            deadzone = 0
            responseExponent = 1
        }
        touches[id] = Tracked(id: id, role: role, origin: origin, point: point,
                              radius: radius, deadzone: deadzone,
                              responseExponent: responseExponent)
        if case .pill(let button) = role {
            press(button)
            enqueueHaptic(.button(button))
        }
        noteScreenInteraction()
    }

    func moved(_ id: ObjectIdentifier, to point: CGPoint) {
        guard var touch = touches[id] else { return }
        if touch.role == .gesture {
            Self.updateSwipeTrail(&touch, to: point)
        }
        touch.point = point
        touch.travelled = max(touch.travelled, Self.distance(touch.origin, point))
        if touch.role == .gesture, touch.swiped == nil,
           touch.travelled >= Self.swipeDistance,
           let direction = Self.swipeDirection(from: touch.origin, to: point) {
            let button: TouchButton = switch direction {
            case .up: .cross
            case .left: .square
            case .right: .circle
            case .down: .crouch
            }
            touch.swiped = button
            enqueueHaptic(.gesture(button))
            if button == .crouch {
                touch.crouchPeakY = point.y
                touchLog.debug("crouch")
            } else if button == .cross {
                touch.acceleratorPeakY = point.y
                press(button)
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
        } else if touch.role == .gesture, touch.swiped == .cross {
            let peak = min(touch.acceleratorPeakY ?? point.y, point.y)
            touch.acceleratorPeakY = peak
            let horizontal = point.x - touch.origin.x
            if !touch.jumpComboTriggered, abs(horizontal) >= Self.swipeDistance {
                let action: TouchButton = horizontal < 0 ? .square : .circle
                touch.jumpComboTriggered = true
                press(action)
                enqueueHaptic(.gesture(action))
                touchLog.debug("jump combo \(action == .square ? "punch" : "spin")")
            }
            if speederState == .riding, !touch.speederBrakeTriggered,
               point.y - peak >= Self.rollJumpDistance {
                touch.speederBrakeTriggered = true
                enqueueHaptic(.gesture(.crouch))
                touchLog.debug("speeder brake")
            }
        }
        touches[id] = touch
    }

    private static func updateSwipeTrail(_ touch: inout Tracked,
                                         to point: CGPoint) {
        let previousPoint = touch.point
        let stepDistance = distance(previousPoint, point)
        guard stepDistance >= 1.5 else { return }

        guard !touch.trailSegments.isEmpty else {
            guard distance(touch.origin, point) >= 4,
                  let direction = swipeDirection(from: touch.origin, to: point) else { return }
            touch.trailSegments = [
                SwipeTrailSegment(start: touch.origin, end: point, direction: direction)
            ]
            return
        }

        guard let direction = swipeDirection(from: previousPoint, to: point),
              let activeDirection = touch.trailSegments.last?.direction else { return }
        if direction == activeDirection {
            touch.trailCandidateDirection = nil
            touch.trailCandidateStart = nil
            touch.trailSegments[touch.trailSegments.count - 1].end = point
            return
        }

        if touch.trailCandidateDirection != direction {
            touch.trailCandidateDirection = direction
            touch.trailCandidateStart = previousPoint
        }
        guard let turnPoint = touch.trailCandidateStart,
              distance(turnPoint, point) >= 12 else { return }

        touch.trailSegments[touch.trailSegments.count - 1].end = turnPoint
        touch.trailSegments.append(
            SwipeTrailSegment(start: turnPoint, end: point, direction: direction)
        )
        if touch.trailSegments.count > 2 {
            touch.trailSegments.removeFirst(touch.trailSegments.count - 2)
        }
        touch.trailCandidateDirection = nil
        touch.trailCandidateStart = nil
    }

    func ended(_ id: ObjectIdentifier, at _: TimeInterval,
               lookAroundState: GOALPadLookAroundState = .unknown) {
        guard let touch = touches.removeValue(forKey: id) else { return }
        if case .skip(let expectedSnapshot) = touch.role {
            performCutsceneSkip(for: expectedSnapshot)
        } else if touch.role == .gesture, touch.swiped == nil,
                  touch.travelled <= Self.tapDistance,
                  let button = Self.cameraRegionTapButton(
                    gameTitle: gameTitle, lookAroundState: lookAroundState) {
            press(button)
            enqueueHaptic(.gesture(button))
            if gameTitle == .jak1 {
                touchLog.debug("first-person fire")
            } else {
                touchLog.debug("camera-region action \(button.glyph)")
            }
        }
        fadeWhenIdle()
    }

    func cancelled(_ id: ObjectIdentifier) {
        guard touches.removeValue(forKey: id) != nil else { return }
        fadeWhenIdle()
    }

    /// UIKit's event-wide live set repairs a missed end/cancel before stale ownership can reject
    /// a later finger for the same movement or camera role.
    func reconcileActiveTouches(_ activeIdentifiers: Set<ObjectIdentifier>) {
        let staleIdentifiers = touches.keys.filter { !activeIdentifiers.contains($0) }
        for id in staleIdentifiers { cancelled(id) }
    }

    /// The live camera mode supplies the truthful next direction while each title keeps its
    /// native look-around toggle: Triangle in Jak 1 and R3 in Jak II.
    @discardableResult
    func performZoomToggle(lookAroundState: GOALPadLookAroundState) -> Bool {
        guard !capturesNativeTouchInput, !contextualFacePromptOwnsGameplayActions else {
            return false
        }
        switch lookAroundState {
        case .normal, .firstPerson:
            let button: TouchButton = gameTitle == .jak2 ? .rightStickPress : .triangle
            noteScreenInteraction()
            press(button)
            enqueueHaptic(.gesture(button))
            return true
        case .unknown:
            return false
        @unknown default:
            return false
        }
    }

    /// UIKit may not deliver individual cancellations during a lifecycle transition.
    func reset() {
        touches.removeAll()
        pulses = Self.emptyPulses()
        facePromptPulses = Self.emptyPulses()
        dpad = DirectionRepeat()
        hapticEvents.removeAll()
        facePromptHapticEvents.removeAll()
        fadeToken += 1
        isEngaged = false
    }

    /// Input cancellation must not make ordinary active-gameplay chrome undiscoverable.
    func restoreGameplayChromeAfterInterruption() {
        guard nativeMenuMode == .gameplay,
              runReadiness == .active,
              titleStartState == .notAwaiting,
              !capturesNativeTouchInput else { return }
        noteScreenInteraction()
    }

    /// Returns and clears touch-owned feedback actions without affecting game input state.
    func consumeHapticEvents() -> [TouchHapticEvent] {
        defer {
            hapticEvents.removeAll()
            facePromptHapticEvents.removeAll()
        }
        return hapticEvents + facePromptHapticEvents
    }

    private func role(for point: CGPoint, in size: CGSize,
                      classicLayout: ClassicTouchLayout?,
                      modernLayout: ModernTouchLayout?) -> Role? {
        if let layout = classicLayout {
            for control in TouchLayoutControlID.hitTestOrder(for: .classic) {
                switch control {
                case .classicCamera:
                    if rightStick == nil,
                       layout.hitFrame(for: control)?.contains(point) == true {
                        return .rightStick
                    }
                case .classicMovement:
                    if stick == nil,
                       layout.hitFrame(for: control)?.contains(point) == true {
                        return .movement
                    }
                default:
                    guard let sourceButton = ClassicTouchLayout.sourceButton(for: control),
                          layout.hitFrame(for: sourceButton)?.contains(point) == true,
                          let button = layoutCustomization.action(for: control)?.touchButton else {
                        continue
                    }
                    return pillRole(for: button)
                }
            }
            return nil
        }
        let cameraFrame = layoutCustomization.hasCustomGeometry(for: .modernCamera)
            ? modernLayout?.rightStickHitFrame ?? rightStickFrame
            : rightStickFrame
        let pinnedMovement = modernLayout?.movementHitFrame
        let pinnedActions = modernLayout?.actionGestureHitFrame
        for control in TouchLayoutControlID.hitTestOrder(for: .modern) {
            switch control {
            case .modernCamera:
                if rightStick == nil, cameraFrame.contains(point) { return .rightStick }
            case .modernSelect, .modernStats, .modernStart:
                guard let sourceButton = control.defaultAction?.touchButton,
                      let registeredFrame = pillFrames[sourceButton],
                      let output = layoutCustomization.action(for: control)?.touchButton else {
                    continue
                }
                let frame = layoutCustomization.hasCustomGeometry(for: control)
                    ? modernLayout?.hitFrame(for: control) ?? registeredFrame
                    : registeredFrame
                if frame.contains(point) { return pillRole(for: output) }
            case .modernActions:
                if pinnedActions?.contains(point) == true
                    || (pinnedActions == nil && point.x >= size.width / 2) {
                    return .gesture
                }
            case .modernMovement:
                if stick == nil,
                   pinnedMovement?.contains(point) == true
                    || (pinnedMovement == nil && point.x < size.width / 2) {
                    return .movement
                }
            default:
                break
            }
        }
        return nil
    }

    private func pillRole(for button: TouchButton) -> Role {
        if button == .stats,
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
                if pulses[button.rawValue].advance() {
                    state.buttons.insert(Self.inputBit(for: button, gameTitle: gameTitle))
                }
            }
            return state
        }

        var isCrouchingThisFrame = false
        var hasSpeederBrakeThisFrame = false
        for touch in touches.values {
            switch touch.role {
            case .pill(let button):
                pulses[button.rawValue].sustain()
            case .gesture:
                isCrouchingThisFrame = isCrouchingThisFrame || touch.swiped == .crouch
                hasSpeederBrakeThisFrame = hasSpeederBrakeThisFrame
                    || (touch.swiped == .cross && touch.speederBrakeTriggered)
                if let button = touch.swiped, button != .crouch {
                    pulses[button.rawValue].sustain()
                }
            case .movement, .rightStick, .skip:
                break
            }
        }

        let movement = stick.map {
            Self.radialDeflection(from: $0.origin, to: $0.point,
                                  radius: $0.radius, deadzone: $0.deadzone,
                                  responseExponent: $0.responseExponent)
        } ?? .zero
        let camera = rightStick.map {
            Self.radialDeflection(from: $0.origin, to: $0.point,
                                  radius: $0.radius, deadzone: $0.deadzone)
        } ?? .zero
        if let direction = dpad.advance(push: movement) { press(direction) }

        var state = TouchPadState()
        for button in TouchButton.allCases {
            if pulses[button.rawValue].advance() {
                state.buttons.insert(Self.inputBit(for: button, gameTitle: gameTitle))
            }
            if facePromptPulses[button.rawValue].advance() { state.buttons.insert(button.bit) }
        }
        if isCrouchingThisFrame { state.buttons.insert(TouchButton.crouch.bit) }
        if speederState == .riding, hasSpeederBrakeThisFrame {
            state.buttons.formUnion([TouchButton.leftShoulder.bit,
                                     TouchButton.rightShoulder.bit])
        }

        (state.leftX, state.leftY) = Self.axes(movement)
        (state.rightX, state.rightY) = Self.axes(camera)
        return state
    }

    // MARK: - Mapping

    /// The three face-button gestures plus held crouch on the downward direction.
    nonisolated static func swipeDirection(from origin: CGPoint,
                                           to point: CGPoint) -> TouchGestureDirection? {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        guard dx != 0 || dy != 0 else { return nil }
        if abs(dy) > abs(dx) { return dy < 0 ? .up : .down }
        return dx < 0 ? .left : .right
    }

    nonisolated static func movementDeflection(from origin: CGPoint, to point: CGPoint) -> CGPoint {
        radialDeflection(from: origin, to: point, radius: movementRadius,
                         deadzone: movementDeadzone,
                         responseExponent: movementResponseExponent)
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

    nonisolated static func stickDeflection(from origin: CGPoint, to point: CGPoint,
                                            radius: CGFloat, deadzone: CGFloat,
                                            responseExponent: CGFloat = 1) -> CGPoint {
        radialDeflection(from: origin, to: point, radius: radius, deadzone: deadzone,
                         responseExponent: responseExponent)
    }

    nonisolated static func gestureArtworkIsLit(button: TouchButton,
                                                swiped: TouchButton?,
                                                jumpTriggered: Bool,
                                                punchTriggered: Bool) -> Bool {
        swiped == button || (jumpTriggered && button == .cross)
            || (punchTriggered && button == .square)
    }

    nonisolated static func artworkIsVisible(isEngaged: Bool, isSuppressed: Bool,
                                             hasTouches: Bool,
                                             isNativeMenuOpen: Bool,
                                             isAwaitingTitleStart: Bool = false) -> Bool {
        (isEngaged || isNativeMenuOpen || isAwaitingTitleStart)
            && (!isSuppressed || hasTouches)
    }

    nonisolated static func gameplayChromeIsVisible(
        mode: GOALPadGameMode,
        runReadiness: GameplayRunReadiness,
        isAwaitingTitleStart: Bool,
        isEngaged: Bool,
        isSuppressed: Bool,
        hasTouches: Bool
    ) -> Bool {
        mode == .gameplay && runReadiness == .active && !isAwaitingTitleStart
            && isEngaged && (!isSuppressed || hasTouches)
    }

    nonisolated static func titleStartChromeIsVisible(
        mode: GOALPadGameMode,
        isAwaitingTitleStart: Bool,
        isSuppressed: Bool,
        hasTouches: Bool
    ) -> Bool {
        mode == .gameplay && isAwaitingTitleStart && (!isSuppressed || hasTouches)
    }

    nonisolated static func rightStickArtworkIsVisible(
        mode: GOALPadGameMode,
        runReadiness: GameplayRunReadiness,
        isAwaitingTitleStart: Bool,
        cutsceneSkipAvailable: Bool,
        isEngaged: Bool,
        isSuppressed: Bool,
        hasTouches: Bool,
        contextualFacePromptOwnsGameplayActions: Bool = false
    ) -> Bool {
        gameplayChromeIsVisible(
            mode: mode,
            runReadiness: runReadiness,
            isAwaitingTitleStart: isAwaitingTitleStart,
            isEngaged: isEngaged,
            isSuppressed: isSuppressed,
            hasTouches: hasTouches)
            && !cutsceneSkipAvailable && !contextualFacePromptOwnsGameplayActions
    }

    nonisolated static func artworkLabel(for button: TouchButton,
                                         sessionAction: NativeMenuTouchAction?,
                                         cutsceneSkipAvailable: Bool = false,
                                         gameTitle: TouchGameTitle = .jak1) -> String {
        if button == .stats, cutsceneSkipAvailable { return "SKIP" }
        if button == .stats, gameTitle == .jak2 { return "R2" }
        guard button == .start else { return button.glyph }
        return (sessionAction?.label ?? button.glyph).uppercased()
    }

    nonisolated static func inputBit(for button: TouchButton,
                                     gameTitle: TouchGameTitle) -> GOALPadButton {
        if button == .stats, gameTitle == .jak2 { return .R2 }
        return button.bit
    }

    nonisolated static func cameraRegionTapButton(
        gameTitle: TouchGameTitle,
        lookAroundState: GOALPadLookAroundState
    ) -> TouchButton? {
        switch gameTitle {
        case .jak1:
            lookAroundState == .firstPerson ? .square : nil
        case .jak2:
            .rightShoulder
        }
    }

    nonisolated static func jak2WeaponWheelIsVisible(
        gameTitle: TouchGameTitle,
        mode: GOALPadGameMode,
        runReadiness: GameplayRunReadiness,
        isAwaitingTitleStart: Bool
    ) -> Bool {
        gameTitle == .jak2 && mode == .gameplay && runReadiness == .active
            && !isAwaitingTitleStart
    }

    nonisolated static func cutsceneSkipIsAvailable(
        in mode: GOALPadGameMode,
        snapshot: NativeCutsceneSkipTouchSnapshot
    ) -> Bool {
        guard mode == .gameplay, snapshot.isStructurallyValid else { return false }
        return switch snapshot.state {
        case .triangleQueryAvailable, .creditsTriangleAvailable: true
        case .unavailable: false
        }
    }

    nonisolated static func contextualFacePromptOwnsGameplayActions(
        mode: GOALPadGameMode,
        runReadiness: GameplayRunReadiness,
        snapshot: NativeFacePromptTouchSnapshot,
        warpGateControlsVisible: Bool,
        warpGateCapturesInput: Bool,
        cutsceneSkipAvailable: Bool
    ) -> Bool {
        guard runReadiness == .active else { return false }
        return !NativeFacePromptTouchAction.available(
            in: mode,
            snapshot: snapshot,
            warpGateControlsVisible: warpGateControlsVisible,
            warpGateCapturesInput: warpGateCapturesInput,
            cutsceneSkipAvailable: cutsceneSkipAvailable).isEmpty
    }

    nonisolated static func nativeMenuControlsAreVisible(mode: GOALPadGameMode,
                                                         progress: NativeProgressMenuSnapshot = .unavailable,
                                                         gameTitle: TouchGameTitle = .jak1,
                                                         runReadiness: GameplayRunReadiness = .active) -> Bool {
        return !NativeMenuTouchAction.available(
            in: mode, progress: progress, gameTitle: gameTitle,
            runReadiness: runReadiness).isEmpty
    }

    nonisolated static func warpGateTouchControlsAreVisible(
        mode: GOALPadGameMode,
        snapshot: NativeWarpGateTouchSnapshot
    ) -> Bool {
        !NativeWarpGateTouchAction.available(in: mode, snapshot: snapshot).isEmpty
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
                                                     deadzone: CGFloat = 0,
                                                     responseExponent: CGFloat = 1) -> CGPoint {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > deadzone else { return .zero }
        let normalized = (min(length, radius) - deadzone) / (radius - deadzone)
        let response = CGFloat(pow(Double(normalized), Double(responseExponent)))
        let scale = response / length
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
        pulses[button.rawValue].press()
    }

    private func enqueueHaptic(_ event: TouchHapticEvent) {
        hapticEvents.append(event)
    }

    private func cancelFacePromptInput() {
        facePromptPulses = Self.emptyPulses()
        facePromptHapticEvents.removeAll()
    }

    private func cancelOrdinaryGameplayCommandInput() {
        touches = touches.filter { $0.value.role == .movement }
        pulses = Self.emptyPulses()
        hapticEvents.removeAll()
        fadeWhenIdle()
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
            } else if holdRemaining > 0 {
                // Give a distinct second tap its release edge now instead of queueing it behind
                // the first pulse's remaining hold window.
                holdRemaining = 0
                gapRemaining = max(gapRemaining, TouchControls.releaseFrames)
                queued += 1
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

    private static func emptyPulses() -> [Pulse] {
        Array(repeating: Pulse(), count: TouchButton.allCases.count)
    }

    // MARK: - Visibility

    /// Records either a raw UIKit touch or an app-owned semantic touch action.
    func noteScreenInteraction() {
        engage()
        if touches.isEmpty { fadeWhenIdle() }
    }

    private func engage() {
        fadeToken += 1
        isEngaged = true
    }

    private func fadeWhenIdle() {
        guard touches.isEmpty else { return }
        fadeToken += 1
        let token = fadeToken
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.gameplayChromeFadeOutDelay))
            guard let self, token == fadeToken, touches.isEmpty else { return }
            isEngaged = false
        }
    }
}

private extension CGRect {
    var centre: CGPoint { CGPoint(x: midX, y: midY) }
}
