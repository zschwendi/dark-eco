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

/// Jak II's separate source-proven save-flow meaning, independent of Jak 1 screen numbers.
struct NativeJak2ProgressMenuSemanticSnapshot: Equatable {
    enum Phase: Equatable {
        case unavailable
        case selectSaveTitle
        case noMemoryCard
        case createGame
        case creating
        case saving
        case existingSaveOverwrite
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
    case confirm, back, cancel, start, pause, resume
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

    /// Exact `progress-screen` values from Jak 1's checked PC enum.
    private enum ShippingPCScreen {
        static let quit = 34
        static let quitTitle = 58
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
        titleStartState: GOALPadTitleStartState = .unknown
    ) -> [Self] {
        return switch mode {
        case .pause:
            []
        case .menu:
            [.up, .down, .left, .right, .back, .confirm]
        case .progress:
            progressActions(for: progress)
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
        runReadiness: GameplayRunReadiness = .active
    ) -> Bool {
        if let session = NativeSessionControlPresentation.reduce(
            mode: mode, titleStartState: titleStartState, progress: progress,
            runReadiness: runReadiness),
           action == session.action {
            return session.isEnabled
        }
        return available(in: mode, progress: progress,
                         titleStartState: titleStartState).contains(action)
    }

    nonisolated private static func progressActions(
        for snapshot: NativeProgressMenuSnapshot
    ) -> [Self] {
        if snapshot.jak2Semantic.available {
            return jak2ProgressActions(for: snapshot.jak2Semantic)
        }
        guard snapshot.available, !snapshot.inTransition else { return [] }

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

        switch snapshot.phase {
        case .selectSaveTitle:
            guard (0...4).contains(snapshot.optionIndex),
                  snapshot.actionMask == (up | down | confirm) else { return [] }
            return [.up, .down, .confirm]
        case .noMemoryCard:
            guard snapshot.optionIndex == 0,
                  snapshot.actionMask == confirm else { return [] }
            return [.confirm]
        case .createGame:
            guard snapshot.optionIndex == 0,
                  snapshot.actionMask == (left | right | confirm) else { return [] }
            return [.left, .right, .confirm]
        case .existingSaveOverwrite:
            guard snapshot.optionIndex == 0,
                  snapshot.actionMask == (left | right | confirm) else { return [] }
            return [.left, .right, .confirm]
        case .creating, .saving:
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
        runReadiness: GameplayRunReadiness = .active
    ) -> Self? {
        switch mode {
        case .gameplay:
            switch titleStartState {
            case .awaiting: return Self(action: .start, isEnabled: true)
            case .notAwaiting, .unknown, .titleSequence:
                return runReadiness == .active
                    ? Self(action: .pause, isEnabled: true)
                    : Self(action: .start, isEnabled: false)
            @unknown default:
                return Self(action: .start, isEnabled: false)
            }
        case .pause, .menu:
            return Self(action: .resume, isEnabled: true)
        case .progress:
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
    static let horizontalInset: CGFloat = 16
    static let iconColumnWidth: CGFloat = 20
    static let iconTextSpacing: CGFloat = 10
}

/// A discrete, app-owned touch action that may receive device feedback.
/// These are intentionally separate from native game/controller rumble.
enum TouchHapticEvent: Equatable {
    case button(TouchButton)
    case gesture(TouchButton)
    case stickEngaged
}

/// Preserves the accepted two-pill centres while adding an independent circular zoom control.
struct ModernTouchChromeLayout: Equatable, Sendable {
    nonisolated static let pillSize = CGSize(width: 82, height: 42)
    nonisolated static let pillSpacing: CGFloat = 20
    nonisolated static let zoomDiameter: CGFloat = 42
    nonisolated static let zoomGap: CGFloat = pillSpacing
    nonisolated static let bottomInset: CGFloat = 30

    let zoomFrame: CGRect
    let statsFrame: CGRect
    let startFrame: CGRect
    let centeredSessionFrame: CGRect

    init(size: CGSize) {
        let width = max(0, size.width)
        let height = max(0, size.height)
        let pairWidth = Self.pillSize.width * 2 + Self.pillSpacing
        let stats = CGRect(x: (width - pairWidth) / 2,
                           y: height - Self.bottomInset - Self.pillSize.height,
                           width: Self.pillSize.width, height: Self.pillSize.height)
        statsFrame = stats
        startFrame = stats.offsetBy(dx: Self.pillSize.width + Self.pillSpacing, dy: 0)
        centeredSessionFrame = CGRect(x: (width - Self.pillSize.width) / 2,
                                      y: stats.minY,
                                      width: Self.pillSize.width,
                                      height: Self.pillSize.height)
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
    let movementArtworkFrame: CGRect
    let movementHitFrame: CGRect?
    let actionGestureFrame: CGRect
    let actionGestureHitFrame: CGRect?
    let rightStickArtworkFrame: CGRect
    let rightStickHitFrame: CGRect
    let selectPillFrame: CGRect
    let statsPillFrame: CGRect
    let startPillFrame: CGRect

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
        safeBounds = safe

        let legacyEdge = Self.legacyRightStickEdge(for: bounds.size)
        let targetSpacer = min(Self.rightStickSpacerCap,
                               max(legacyEdge, safe.width * 0.24))
        rightStickSpacer = min(targetSpacer,
                                max(0, safe.width - TouchControls.rightStickRadius * 2))

        let pillOffset = Self.pillSize.width + Self.pillSpacing
        let pillY = bounds.maxY - 30 - Self.pillSize.height / 2
        let defaultSelectPillFrame = Self.frame(
            centre: CGPoint(x: bounds.midX - pillOffset, y: pillY), size: Self.pillSize)
        let defaultStatsPillFrame = Self.frame(
            centre: CGPoint(x: bounds.midX, y: pillY), size: Self.pillSize)
        let defaultStartPillFrame = Self.frame(
            centre: CGPoint(x: bounds.midX + pillOffset, y: pillY), size: Self.pillSize)
        selectPillFrame = Self.resolvedFrame(defaultSelectPillFrame, id: .modernSelect,
                                             customization: customization, safeBounds: safe)
        statsPillFrame = Self.resolvedFrame(defaultStatsPillFrame, id: .modernStats,
                                            customization: customization, safeBounds: safe)
        startPillFrame = Self.resolvedFrame(defaultStartPillFrame, id: .modernStart,
                                            customization: customization, safeBounds: safe)

        let movementCentre = CGPoint(x: safe.minX + Self.movementVisualRadius,
                                     y: safe.maxY - Self.movementVisualRadius)
        let defaultMovementFrame = Self.frame(centre: movementCentre,
                                              diameter: Self.movementVisualRadius * 2)
        movementArtworkFrame = Self.resolvedFrame(defaultMovementFrame, id: .modernMovement,
                                                  customization: customization, safeBounds: safe)
        if customization.position(for: .modernMovement) != nil {
            let diameter = min(safe.width, safe.height,
                               TouchControls.movementRadius * 2
                                   * customization.scale(for: .modernMovement))
            let requested = Self.frame(centre: movementArtworkFrame.centre, diameter: diameter)
            movementHitFrame = TouchLayoutGeometry.minimumHitFrame(for: requested, in: safe)
        } else {
            movementHitFrame = nil
        }

        let defaultGestureFrame = Self.frame(
            centre: CGPoint(x: safe.minX + safe.width * 0.75, y: safe.midY),
            diameter: 176)
        actionGestureFrame = Self.resolvedFrame(defaultGestureFrame, id: .modernActions,
                                                customization: customization, safeBounds: safe)
        actionGestureHitFrame = customization.position(for: .modernActions) == nil
            ? nil
            : TouchLayoutGeometry.minimumHitFrame(for: actionGestureFrame, in: safe)

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
        let defaultRightStickFrame = Self.frame(centre: CGPoint(x: centreX, y: centreY),
                                                diameter: radius * 2)
        rightStickArtworkFrame = Self.resolvedFrame(defaultRightStickFrame, id: .modernCamera,
                                                    customization: customization, safeBounds: safe)
        rightStickHitFrame = customization.hasCustomGeometry(for: .modernCamera)
            ? TouchLayoutGeometry.minimumHitFrame(for: rightStickArtworkFrame, in: safe)
            : rightStickArtworkFrame.insetBy(dx: -Self.rightStickHitSlop,
                                              dy: -Self.rightStickHitSlop)
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
    nonisolated static let movementRadius: CGFloat = 90
    nonisolated static let rightStickRadius: CGFloat = 38
    nonisolated static let rightStickDeadzone: CGFloat = 12
    nonisolated static let rollJumpDistance: CGFloat = 44
    nonisolated static let swipeDistance: CGFloat = 44
    nonisolated static let nativeMenuSwipeDistance: CGFloat = 44
    nonisolated static let nativeWarpSwipeDistance: CGFloat = 44

    /// Frames a recognised one-shot press remains down, followed by a guaranteed release gap.
    nonisolated static let holdFrames = 6
    nonisolated static let releaseFrames = 2
    /// App-owned gameplay artwork idles away together after the last screen interaction.
    nonisolated static let gameplayChromeFadeOutDelay: TimeInterval = 3

    /// Strong movement pushes also step list-style menus through the D-pad.
    nonisolated static let dpadPress: CGFloat = 0.55
    nonisolated static let dpadRelease: CGFloat = 0.35
    nonisolated static let dpadRepeatDelay = 26
    nonisolated static let dpadRepeatInterval = 10

    private(set) var style: TouchControlStyle
    private(set) var layoutCustomization = TouchLayoutCustomization.standard
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

    struct Tracked: Identifiable {
        let id: ObjectIdentifier
        let role: Role
        /// A dynamic movement origin, fixed right-stick centre, or gesture/pill landing point.
        let origin: CGPoint
        var point: CGPoint
        var travelled: CGFloat = 0
        var swiped: TouchButton? = nil
        var crouchPeakY: CGFloat? = nil
        var acceleratorPeakY: CGFloat? = nil
        var speederBrakeTriggered = false
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
    var hasActiveGameplayGesture: Bool { !gestures.isEmpty }
    var isCrouching: Bool {
        gestures.contains { $0.swiped == .crouch }
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
    @ObservationIgnored private var pulses: [TouchButton: Pulse] = [:]
    @ObservationIgnored private var facePromptPulses: [TouchButton: Pulse] = [:]
    @ObservationIgnored private var facePromptHapticEvents: [TouchHapticEvent] = []
    @ObservationIgnored private var fadeToken = 0
    @ObservationIgnored private var dpad = DirectionRepeat()

    init(style: TouchControlStyle = .modern) {
        self.style = style
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

    func setLayoutCustomization(_ customization: TouchLayoutCustomization) {
        guard customization != layoutCustomization else { return }
        reset()
        layoutCustomization = customization
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

    /// Owner/availability generation changes and stale native reads cancel a pending SKIP tap.
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
    func performNativeMenuAction(_ action: NativeMenuTouchAction) {
        guard NativeMenuTouchAction.isEnabled(action, in: nativeMenuMode,
                                              progress: progressMenuSnapshot,
                                              titleStartState: titleStartState,
                                              runReadiness: runReadiness)
        else { return }
        noteScreenInteraction()
        press(action.button)
        enqueueHaptic(.button(action.button))
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
        facePromptPulses[action.button, default: Pulse()].press()
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
    private func build96Role(for point: CGPoint, in size: CGSize) -> Role? {
        for (button, frame) in pillFrames where frame.contains(point) {
            if !contextualFacePromptOwnsGameplayActions { return pillRole(for: button) }
        }
        if !contextualFacePromptOwnsGameplayActions,
           rightStick == nil, rightStickFrame.contains(point) { return .rightStick }
        if stick == nil, point.x < size.width / 2 { return .movement }
        if !contextualFacePromptOwnsGameplayActions, point.x >= size.width / 2 {
            return .gesture
        }
        return nil
    }

    // MARK: - Touches

    func began(_ id: ObjectIdentifier, at point: CGPoint, in size: CGSize,
               safeAreaInsets: TouchSafeAreaInsets = .zero, at _: TimeInterval) {
        guard !capturesNativeTouchInput else { return }
        _ = safeAreaInsets
        guard let role = build96Role(for: point, in: size) else { return }
        let origin: CGPoint
        let radius: CGFloat
        let deadzone: CGFloat
        switch role {
        case .movement:
            origin = point
            radius = Self.movementRadius
            deadzone = 0
        case .rightStick:
            origin = rightStickFrame.centre
            radius = Self.rightStickRadius
            deadzone = Self.rightStickDeadzone
        case .gesture:
            origin = point
            radius = 0
            deadzone = 0
        case .pill, .skip:
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
        noteScreenInteraction()
    }

    func moved(_ id: ObjectIdentifier, to point: CGPoint) {
        guard var touch = touches[id] else { return }
        touch.point = point
        touch.travelled = max(touch.travelled, Self.distance(touch.origin, point))
        if (touch.role == .movement || touch.role == .rightStick),
           !touch.stickHapticTriggered,
           Self.distance(.zero, Self.radialDeflection(from: touch.origin, to: point,
                                                      radius: touch.radius,
                                                      deadzone: touch.deadzone)) >= 0.5 {
            touch.stickHapticTriggered = true
            enqueueHaptic(.stickEngaged)
        } else if touch.role == .gesture, touch.swiped == nil,
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
            if speederState == .riding, !touch.speederBrakeTriggered,
               point.y - peak >= Self.rollJumpDistance {
                touch.speederBrakeTriggered = true
                enqueueHaptic(.gesture(.crouch))
                touchLog.debug("speeder brake")
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

    /// UIKit's event-wide live set repairs a missed end/cancel before stale ownership can reject
    /// a later finger for the same movement or camera role.
    func reconcileActiveTouches(_ activeIdentifiers: Set<ObjectIdentifier>) {
        let staleIdentifiers = touches.keys.filter { !activeIdentifiers.contains($0) }
        for id in staleIdentifiers { cancelled(id) }
    }

    /// Jak's zoom is a Triangle toggle. The live camera mode supplies the truthful next direction.
    @discardableResult
    func performZoomToggle(lookAroundState: GOALPadLookAroundState) -> Bool {
        guard !capturesNativeTouchInput, !contextualFacePromptOwnsGameplayActions else {
            return false
        }
        switch lookAroundState {
        case .normal, .firstPerson:
            noteScreenInteraction()
            press(.triangle)
            enqueueHaptic(.gesture(.triangle))
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
        pulses.removeAll()
        facePromptPulses.removeAll()
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
        let camera = rightStick.map {
            Self.radialDeflection(from: $0.origin, to: $0.point,
                                  radius: $0.radius, deadzone: $0.deadzone)
        } ?? .zero
        if let direction = dpad.advance(push: movement) { press(direction) }

        var state = TouchPadState()
        for button in TouchButton.allCases {
            var pulse = pulses[button] ?? Pulse()
            if pulse.advance() { state.buttons.insert(button.bit) }
            pulses[button] = pulse
            var facePromptPulse = facePromptPulses[button] ?? Pulse()
            if facePromptPulse.advance() { state.buttons.insert(button.bit) }
            facePromptPulses[button] = facePromptPulse
        }
        if isCrouching { state.buttons.insert(TouchButton.crouch.bit) }
        if speederState == .riding,
           gestures.contains(where: { $0.swiped == .cross && $0.speederBrakeTriggered }) {
            state.buttons.formUnion([TouchButton.leftShoulder.bit,
                                     TouchButton.rightShoulder.bit])
        }

        (state.leftX, state.leftY) = Self.axes(movement)
        (state.rightX, state.rightY) = Self.axes(camera)
        return state
    }

    // MARK: - Mapping

    /// The three face-button gestures plus held crouch on the downward direction.
    private static func swipeDirection(from origin: CGPoint,
                                       to point: CGPoint) -> TouchGestureDirection? {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        guard dx != 0 || dy != 0 else { return nil }
        if abs(dy) > abs(dx) { return dy < 0 ? .up : .down }
        return dx < 0 ? .left : .right
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

    nonisolated static func stickDeflection(from origin: CGPoint, to point: CGPoint,
                                            radius: CGFloat, deadzone: CGFloat) -> CGPoint {
        radialDeflection(from: origin, to: point, radius: radius, deadzone: deadzone)
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
                                         cutsceneSkipAvailable: Bool = false) -> String {
        if button == .stats, cutsceneSkipAvailable { return "SKIP" }
        guard button == .start else { return button.glyph }
        return (sessionAction?.label ?? button.glyph).uppercased()
    }

    nonisolated static func cutsceneSkipIsAvailable(
        in mode: GOALPadGameMode,
        snapshot: NativeCutsceneSkipTouchSnapshot
    ) -> Bool {
        mode == .gameplay && snapshot.isStructurallyValid
            && snapshot.state == .triangleQueryAvailable
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
                                                         progress: NativeProgressMenuSnapshot = .unavailable) -> Bool {
        return !NativeMenuTouchAction.available(in: mode, progress: progress).isEmpty
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

    private func cancelFacePromptInput() {
        facePromptPulses.removeAll()
        facePromptHapticEvents.removeAll()
    }

    private func cancelOrdinaryGameplayCommandInput() {
        touches = touches.filter { $0.value.role == .movement }
        pulses.removeAll()
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
