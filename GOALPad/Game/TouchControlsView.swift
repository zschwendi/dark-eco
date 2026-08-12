#if os(iOS)
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// The frozen Build 96 gameplay controls plus the later native-menu touch layer.
struct TouchControlsView: View {
    let controls: TouchControls
    let lookAroundState: GOALPadLookAroundState
    /// Active physical input hides the artwork until the screen is touched again.
    let isSuppressed: Bool
    let gameMode: GOALPadGameMode
    let titleStartState: GOALPadTitleStartState
    let runReadiness: GameplayRunReadiness
    let progressMenuSnapshot: NativeProgressMenuSnapshot
    let warpGateTouchSnapshot: NativeWarpGateTouchSnapshot
    let cutsceneSkipTouchSnapshot: NativeCutsceneSkipTouchSnapshot
    let facePromptTouchSnapshot: NativeFacePromptTouchSnapshot
    let reclaimTouchInput: () -> Bool
    let openSettings: () -> Void

    fileprivate static let space = "GOALPadTouchControls"
    private var usesCompactSessionChrome: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private var pillSize: CGSize {
        usesCompactSessionChrome
            ? ModernTouchChromeLayout.compactPillSize
            : ModernTouchChromeLayout.pillSize
    }

    #if canImport(UIKit)
    @State private var chromeHaptics = TouchHapticDriver()
    #endif

    @discardableResult
    nonisolated static func requestTouchRecovery(
        isSuppressed: Bool,
        reclaim: () -> Bool
    ) -> Bool {
        guard isSuppressed else { return false }
        return reclaim()
    }

    /// Orders optional chrome recovery before the same UIKit-owned touches enter gameplay.
    nonisolated static func forwardGameplayTouchBatch<T>(
        _ touches: [T],
        isSuppressed: Bool,
        reclaim: () -> Bool,
        began: (T) -> Void
    ) {
        _ = requestTouchRecovery(isSuppressed: isSuppressed, reclaim: reclaim)
        for touch in touches { began(touch) }
    }

    private var nativeMenuActions: [NativeMenuTouchAction] {
        NativeMenuTouchAction.available(
            in: gameMode, progress: progressMenuSnapshot, titleStartState: titleStartState)
    }

    private var sessionControl: NativeSessionControlPresentation? {
        NativeSessionControlPresentation.reduce(mode: gameMode,
                                                titleStartState: titleStartState,
                                                progress: progressMenuSnapshot,
                                                runReadiness: runReadiness)
    }

    private var nativeMenuControlsAreVisible: Bool {
        TouchControls.nativeMenuControlsAreVisible(mode: gameMode,
                                                   progress: progressMenuSnapshot)
    }

    private var capturesNativeMenuInput: Bool {
        TouchControls.capturesNativeMenuInput(mode: gameMode)
    }

    private var capturesWarpGateTouchInput: Bool {
        controls.capturesWarpGateTouchInput
    }

    private var warpGateActions: [NativeWarpGateTouchAction] {
        NativeWarpGateTouchAction.available(in: gameMode, snapshot: warpGateTouchSnapshot)
    }

    private var warpGateTouchControlsAreVisible: Bool {
        TouchControls.warpGateTouchControlsAreVisible(mode: gameMode,
                                                      snapshot: warpGateTouchSnapshot)
    }

    private var cutsceneSkipAvailable: Bool {
        TouchControls.cutsceneSkipIsAvailable(in: gameMode,
                                              snapshot: cutsceneSkipTouchSnapshot)
    }

    private var facePromptActions: [NativeFacePromptTouchAction] {
        NativeFacePromptTouchAction.available(
            in: gameMode,
            snapshot: facePromptTouchSnapshot,
            warpGateControlsVisible: warpGateTouchControlsAreVisible,
            warpGateCapturesInput: capturesWarpGateTouchInput,
            cutsceneSkipAvailable: cutsceneSkipAvailable)
    }

    private var isAwaitingTitleStart: Bool {
        sessionControl?.action == .start && gameMode == .gameplay
    }

    private var hasScreenTouches: Bool { !controls.touches.isEmpty }

    private var activeGameplayChromeIsAvailable: Bool {
        gameMode == .gameplay && runReadiness == .active && !isAwaitingTitleStart
    }

    private var gameplayChromeIsVisible: Bool {
        TouchControls.gameplayChromeIsVisible(
            mode: gameMode,
            runReadiness: runReadiness,
            isAwaitingTitleStart: isAwaitingTitleStart,
            isEngaged: controls.isEngaged,
            isSuppressed: isSuppressed,
            hasTouches: hasScreenTouches)
    }

    private var ordinaryGameplayChromeIsVisible: Bool {
        gameplayChromeIsVisible && facePromptActions.isEmpty
    }

    private var titleStartChromeIsVisible: Bool {
        TouchControls.titleStartChromeIsVisible(
            mode: gameMode,
            isAwaitingTitleStart: isAwaitingTitleStart,
            isSuppressed: isSuppressed,
            hasTouches: hasScreenTouches)
    }

    private var rightStickArtworkIsAvailable: Bool {
        activeGameplayChromeIsAvailable && !cutsceneSkipAvailable && facePromptActions.isEmpty
    }

    private var ecoSettingsIsVisible: Bool {
        NativeEcoSettingsPresentation.isVisible(
            mode: gameMode,
            progress: progressMenuSnapshot,
            runReadiness: runReadiness)
    }

    /// Triangle belongs to SKIP while the authored cutscene query owns it.
    private var zoomIsAvailable: Bool {
        activeGameplayChromeIsAvailable && !cutsceneSkipAvailable && facePromptActions.isEmpty
    }

    var body: some View {
        GeometryReader { proxy in
            let safeAreaInsets = TouchSafeAreaInsets(
                top: proxy.safeAreaInsets.top,
                leading: proxy.safeAreaInsets.leading,
                bottom: proxy.safeAreaInsets.bottom,
                trailing: proxy.safeAreaInsets.trailing)
            let layout = ModernTouchLayout(size: proxy.size,
                                           safeAreaInsets: safeAreaInsets,
                                           customization: controls.layoutCustomization,
                                           usesCompactSessionChrome: usesCompactSessionChrome)
            let reservesCapturedSessionRow = ecoSettingsIsVisible || sessionControl != nil

            ZStack {
                if !capturesNativeMenuInput && !capturesWarpGateTouchInput {
                    #if canImport(UIKit)
                    TouchSurface(controls: controls,
                                 lookAroundState: lookAroundState,
                                 isSuppressed: isSuppressed,
                                 safeAreaInsets: safeAreaInsets,
                                 reclaimTouchInput: reclaimTouchInput)

                    SwipeTrailArtwork(touches: controls.gestures)
                        .allowsHitTesting(false)
                    #endif

                    if isAwaitingTitleStart {
                        titleStartArtwork(frame: layout.selectPillFrame)
                            .allowsHitTesting(false)
                    }

                    ordinaryGameplayChrome(layout: layout)
                        .opacity(ordinaryGameplayChromeIsVisible ? 1 : 0)
                        .animation(.easeOut(duration: 0.16),
                                   value: ordinaryGameplayChromeIsVisible)

                    if titleStartTouchTargetIsVisible {
                        titleStartTouchTarget(frame: layout.selectPillFrame)
                    }
                }

                if capturesNativeMenuInput {
                    NativeMenuTouchControls(controls: controls,
                                            actions: nativeMenuActions,
                                            isInteractive: nativeMenuControlsAreVisible,
                                            showsChrome: nativeMenuControlsAreVisible
                                                && !isSuppressed,
                                            isPortrait: proxy.size.height > proxy.size.width,
                                            reclaimTouchInput: reclaimTouchInput)
                        .padding(.horizontal, 20)
                        .padding(.bottom, reservesCapturedSessionRow
                            ? layout.menuControlsBottomInset
                            : max(20, proxy.safeAreaInsets.bottom))

                    capturedMenuChrome(in: proxy, layout: layout)
                }

                if !capturesNativeMenuInput
                    && (capturesWarpGateTouchInput || !warpGateActions.isEmpty) {
                    NativeWarpGateTouchControls(controls: controls,
                                                snapshot: warpGateTouchSnapshot,
                                                actions: warpGateActions,
                                                capturesInput: capturesWarpGateTouchInput,
                                                isInteractive: warpGateTouchControlsAreVisible,
                                                showsChrome: warpGateTouchControlsAreVisible
                                                    && !isSuppressed,
                                                reclaimTouchInput: reclaimTouchInput)
                        .padding(.horizontal, 20)
                        .padding(.bottom, capturesWarpGateTouchInput
                            ? max(20, proxy.safeAreaInsets.bottom)
                            : layout.warpPromptBottomInset)
                }

                if !facePromptActions.isEmpty {
                    NativeFacePromptTouchControls(controls: controls,
                                                  snapshot: facePromptTouchSnapshot,
                                                  actions: facePromptActions,
                                                  isInteractive: true,
                                                  showsChrome: gameplayChromeIsVisible,
                                                  reclaimTouchInput: reclaimTouchInput)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .bottomTrailing)
                        .padding(.horizontal, 20)
                        .padding(.bottom, max(20, proxy.safeAreaInsets.bottom))
                }
            }
        }
        .coordinateSpace(.named(Self.space))
        .ignoresSafeArea()
    }

    private func titleStartArtwork(frame: CGRect) -> some View {
        return pill(.start)
            .position(x: frame.midX, y: frame.midY)
            .opacity(titleStartChromeIsVisible ? 1 : 0)
            .animation(.easeOut(duration: 0.16), value: titleStartChromeIsVisible)
    }

    /// Every eligible gameplay ornament shares this one idle-opacity transition.
    private func ordinaryGameplayChrome(layout: ModernTouchLayout) -> some View {
        return ZStack {
            MovementStickArtwork(touch: controls.stick,
                                 restingOrigin: CGPoint(x: layout.movementArtworkFrame.midX,
                                                        y: layout.movementArtworkFrame.midY),
                                 followsTouchOrigin: controls.dynamicLeftStick,
                                 radius: layout.movementRadius,
                                 knobSize: layout.movementKnobSize)
                .opacity(controls.dynamicLeftStick && controls.stick == nil ? 0 : 1)
                .allowsHitTesting(false)

            if activeGameplayChromeIsAvailable {
                pill(.stats)
                    .position(x: layout.statsPillFrame.midX, y: layout.statsPillFrame.midY)
                    .allowsHitTesting(false)
                pill(.start)
                    .position(x: layout.startPillFrame.midX, y: layout.startPillFrame.midY)
                    .allowsHitTesting(false)
            }

            RightStickControl(controls: controls,
                              radius: layout.rightStickRadius,
                              knobSize: layout.rightStickKnobSize)
                .position(x: layout.rightStickArtworkFrame.midX,
                          y: layout.rightStickArtworkFrame.midY)
                .opacity(rightStickArtworkIsAvailable ? 1 : 0)
                .allowsHitTesting(false)

            zoomButton(frame: layout.zoomFrame)
                .opacity(zoomIsAvailable ? 1 : 0)
                .allowsHitTesting(zoomIsAvailable)
        }
    }

    private func pill(_ button: TouchButton) -> some View {
        let isDown = controls.isPillDown(button)
        let label = usesCompactSessionChrome && button == .stats && !cutsceneSkipAvailable
            ? "SELECT"
            : TouchControls.artworkLabel(for: button,
                                         sessionAction: sessionControl?.action,
                                         cutsceneSkipAvailable: cutsceneSkipAvailable)
        return Text(label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(.white.opacity(isDown ? 1 : 0.8))
            .frame(width: pillSize.width, height: pillSize.height)
            .background(Capsule().fill(.black.opacity(isDown ? 0.72 : 0.42)))
            .overlay(Capsule().strokeBorder(.white.opacity(isDown ? 0.9 : 0.35), lineWidth: 1))
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(Self.space)).insetBy(dx: -10, dy: -12)
            } action: {
                controls.setPillFrame(button, $0)
            }
    }

    private var zoomSystemImage: String {
        lookAroundState == .firstPerson
            ? "arrow.down.right.and.arrow.up.left"
            : "arrow.up.left.and.arrow.down.right"
    }

    private var zoomAccessibilityLabel: String {
        lookAroundState == .firstPerson ? "Zoom Out" : "Zoom In"
    }

    private func zoomButton(frame: CGRect) -> some View {
        return Button { performZoomToggle() } label: {
            Image(systemName: zoomSystemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(lookAroundState == .unknown ? 0.45 : 0.82))
                .frame(width: frame.width, height: frame.height)
                .background(Circle().fill(.black.opacity(0.42)))
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(lookAroundState == .unknown)
        .position(x: frame.midX, y: frame.midY)
        .accessibilityLabel(zoomAccessibilityLabel)
    }

    private func capturedMenuChrome(in proxy: GeometryProxy,
                                    layout: ModernTouchLayout) -> some View {
        return ZStack {
            if ecoSettingsIsVisible {
                Button { openSettings() } label: {
                    if usesCompactSessionChrome {
                        capturedPillLabel("SETTINGS", isEnabled: true)
                    } else {
                        settingsIconLabel
                    }
                }
                .buttonStyle(.plain)
                .position(x: layout.settingsButtonFrame.midX,
                          y: layout.settingsButtonFrame.midY)
                .accessibilityLabel("Settings")
            }

            if let sessionControl {
                Button { performSessionControl(sessionControl) } label: {
                    capturedPillLabel(sessionControl.action.label.uppercased(),
                                      isEnabled: sessionControl.isEnabled)
                }
                .buttonStyle(.plain)
                .disabled(!sessionControl.isEnabled)
                .position(x: ecoSettingsIsVisible ? layout.startPillFrame.midX
                                                  : layout.selectPillFrame.midX,
                          y: layout.startPillFrame.midY)
                .accessibilityLabel(sessionControl.action.label)
            }
        }
        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        .opacity(isSuppressed ? 0 : 1)
        .animation(.easeOut(duration: 0.16), value: isSuppressed)
    }

    private func capturedPillLabel(_ label: String, isEnabled: Bool) -> some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(.white.opacity(isEnabled ? 0.8 : 0.42))
            .frame(width: pillSize.width, height: pillSize.height)
            .background(Capsule().fill(.black.opacity(0.42)))
            .overlay(Capsule().strokeBorder(.white.opacity(isEnabled ? 0.35 : 0.18),
                                            lineWidth: 1))
            .contentShape(Capsule())
    }

    private var settingsIconLabel: some View {
        Image(systemName: "gearshape")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white.opacity(0.8))
            .frame(width: 42, height: 42)
            .background(Circle().fill(.black.opacity(0.42)))
            .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
            .contentShape(Circle())
    }

    /// The title prompt is an app-owned semantic action. Keep its visible Build 96 pill, but do
    /// not depend on an asynchronously cached artwork frame to decide whether Start was touched.
    private var titleStartTouchTargetIsVisible: Bool {
        gameMode == .gameplay && sessionControl == NativeSessionControlPresentation(
            action: .start, isEnabled: true)
    }

    private func titleStartTouchTarget(frame: CGRect) -> some View {
        Button { performTitleStart() } label: {
            Color.clear
                .frame(width: pillSize.width + 20, height: pillSize.height + 24)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .accessibilityLabel("Start")
        .position(x: frame.midX, y: frame.midY)
    }

    private func performTitleStart() {
        _ = reclaimTouchInput()
        controls.performNativeMenuAction(.start)
        playChromeFeedback()
    }

    private func performZoomToggle() {
        _ = reclaimTouchInput()
        guard controls.performZoomToggle(lookAroundState: lookAroundState) else { return }
        playChromeFeedback()
    }

    private func performSessionControl(_ presentation: NativeSessionControlPresentation) {
        _ = reclaimTouchInput()
        controls.performNativeMenuAction(presentation.action)
        playChromeFeedback()
    }

    private func playChromeFeedback() {
        #if canImport(UIKit)
        chromeHaptics.play(controls.consumeHapticEvents())
        #else
        _ = controls.consumeHapticEvents()
        #endif
    }

}

private struct NativeFacePromptTouchControls: View {
    let controls: TouchControls
    let snapshot: NativeFacePromptTouchSnapshot
    let actions: [NativeFacePromptTouchAction]
    let isInteractive: Bool
    let showsChrome: Bool
    let reclaimTouchInput: () -> Bool

    #if canImport(UIKit)
    @State private var haptics = TouchHapticDriver()
    #endif

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            ForEach(actions, id: \.self) { action in
                Button { perform(action) } label: {
                    Text(action.glyph)
                        .font(.system(size: 27, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: NativeMenuCommandLayout.width,
                               height: NativeMenuCommandLayout.height)
                        .background(.black.opacity(0.68),
                                    in: RoundedRectangle(cornerRadius: 16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(.white.opacity(0.55), lineWidth: 1.5)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(action.accessibilityLabel)
            }
        }
        .opacity(showsChrome ? 1 : 0)
        .allowsHitTesting(isInteractive)
        .animation(.easeOut(duration: 0.16), value: showsChrome)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Contextual face buttons")
    }

    private func perform(_ action: NativeFacePromptTouchAction) {
        _ = reclaimTouchInput()
        controls.performFacePromptAction(action, for: snapshot)
        #if canImport(UIKit)
        haptics.play(controls.consumeHapticEvents())
        #else
        _ = controls.consumeHapticEvents()
        #endif
    }
}

private struct NativeWarpGateTouchControls: View {
    let controls: TouchControls
    let snapshot: NativeWarpGateTouchSnapshot
    let actions: [NativeWarpGateTouchAction]
    let capturesInput: Bool
    let isInteractive: Bool
    let showsChrome: Bool
    let reclaimTouchInput: () -> Bool

    #if canImport(UIKit)
    @State private var haptics = TouchHapticDriver()
    #endif

    var body: some View {
        Group {
            if capturesInput {
                ZStack {
                    Color.clear
                        .contentShape(Rectangle())
                        .allowsHitTesting(true)
                    controlsRow
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12)
                        .onEnded { performSwipe($0.translation) }
                )
                .allowsHitTesting(isInteractive)
            } else {
                controlsRow
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Warp Gate controls")
    }

    private var controlsRow: some View {
        GeometryReader { proxy in
            let layout = NativeWarpGateTouchLayout(availableWidth: proxy.size.width,
                                                   actionCount: actions.count)
            Group {
                if layout.arrangement == .compactGrid {
                    LazyVGrid(columns: Array(
                        repeating: GridItem(.fixed(layout.buttonWidth),
                                            spacing: NativeWarpGateTouchLayout.compactSpacing),
                        count: layout.columnCount),
                        alignment: .trailing,
                        spacing: NativeWarpGateTouchLayout.compactSpacing) {
                        ForEach(actions, id: \.self) { action in
                            actionButton(action, width: layout.buttonWidth, compact: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    HStack(spacing: NativeWarpGateTouchLayout.wideSpacing) {
                        Spacer(minLength: 0)
                        ForEach(actions, id: \.self) { action in
                            actionButton(action, width: layout.buttonWidth, compact: false)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .opacity(showsChrome ? 1 : 0)
        .allowsHitTesting(isInteractive)
        .animation(.easeOut(duration: 0.16), value: showsChrome)
    }

    private func actionButton(_ action: NativeWarpGateTouchAction,
                              width: CGFloat,
                              compact: Bool) -> some View {
        Button { perform(action) } label: {
            Group {
                if compact {
                    VStack(spacing: 3) {
                        Image(systemName: action.systemImage)
                        Text(action.label)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                } else {
                    Label(action.label, systemImage: action.systemImage)
                }
            }
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .frame(width: width)
            .frame(minHeight: NativeWarpGateTouchLayout.buttonMinimumHeight)
            .foregroundStyle(.white)
            .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.55), lineWidth: 1.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.label)
    }

    private func perform(_ action: NativeWarpGateTouchAction) {
        _ = reclaimTouchInput()
        controls.performNativeWarpGateAction(action, for: snapshot)
        playFeedback()
    }

    private func performSwipe(_ translation: CGSize) {
        _ = reclaimTouchInput()
        guard controls.performNativeWarpGateSwipe(translation: translation,
                                                  for: snapshot) else { return }
        playFeedback()
    }

    private func playFeedback() {
        #if canImport(UIKit)
        haptics.play(controls.consumeHapticEvents())
        #else
        _ = controls.consumeHapticEvents()
        #endif
    }
}

private struct NativeMenuTouchControls: View {
    let controls: TouchControls
    let actions: [NativeMenuTouchAction]
    let isInteractive: Bool
    let showsChrome: Bool
    let isPortrait: Bool
    let reclaimTouchInput: () -> Bool

    #if canImport(UIKit)
    @State private var haptics = TouchHapticDriver()
    #endif

    private static let dpadActions: Set<NativeMenuTouchAction> = [.up, .down, .left, .right]

    private var availableDirectionalActions: Set<NativeMenuTouchAction> {
        Set(actions.filter(Self.dpadActions.contains))
    }

    private var commandActions: [NativeMenuTouchAction] {
        actions.filter { !Self.dpadActions.contains($0) }
    }

    var body: some View {
        Group {
            if isPortrait {
                VStack(alignment: .trailing,
                       spacing: NativeMenuCommandLayout.portraitGroupSpacing) {
                    if !commandActions.isEmpty {
                        commandStack
                    }
                    if !availableDirectionalActions.isEmpty {
                        directionPad
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                landscapeControls
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .opacity(showsChrome ? 1 : 0)
        .allowsHitTesting(isInteractive)
        .animation(.easeOut(duration: 0.16), value: showsChrome)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Game menu controls")
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onEnded { performSwipe($0.translation) }
        )
    }

    private var landscapeControls: some View {
        HStack(alignment: .bottom, spacing: 24) {
            if !availableDirectionalActions.isEmpty {
                directionPad
            }

            Spacer(minLength: 0)
            commandStack
        }
    }

    private var commandStack: some View {
        VStack(alignment: .trailing, spacing: 12) {
            ForEach(commandActions, id: \.self) { action in
                menuButton(action, width: NativeMenuCommandLayout.width)
            }
        }
    }

    private var directionPad: some View {
        VStack(spacing: NativeMenuCommandLayout.directionSpacing) {
            menuButton(.up)
            HStack(spacing: NativeMenuCommandLayout.directionSpacing) {
                menuButton(.left)
                menuButton(.down)
                menuButton(.right)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Menu navigation")
    }

    private func menuButton(_ action: NativeMenuTouchAction,
                            width: CGFloat = 60) -> some View {
        let isEnabled = NativeMenuTouchAction.isEnabled(
            action, in: controls.nativeMenuMode, progress: controls.progressMenuSnapshot,
            titleStartState: controls.titleStartState)
        return Button { perform(action) } label: {
            Group {
                if Self.dpadActions.contains(action) {
                    Image(systemName: action.systemImage)
                        .frame(width: width, height: NativeMenuCommandLayout.height)
                } else {
                    HStack(spacing: NativeMenuCommandLayout.iconTextSpacing) {
                        Image(systemName: action.systemImage)
                            .frame(width: NativeMenuCommandLayout.iconColumnWidth,
                                   alignment: .center)
                        Text(action.label)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, NativeMenuCommandLayout.horizontalInset)
                    .frame(width: width, height: NativeMenuCommandLayout.height,
                           alignment: .leading)
                }
            }
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(isEnabled ? 0.8 : 0.42))
            .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(isEnabled ? 0.35 : 0.18), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(action.label)
    }

    private func perform(_ action: NativeMenuTouchAction) {
        _ = reclaimTouchInput()
        controls.performNativeMenuAction(action)
        playFeedback()
    }

    private func performSwipe(_ translation: CGSize) {
        _ = reclaimTouchInput()
        guard controls.performNativeMenuVerticalSwipe(translation: translation) else { return }
        playFeedback()
    }

    private func playFeedback() {
        #if canImport(UIKit)
        haptics.play(controls.consumeHapticEvents())
        #else
        _ = controls.consumeHapticEvents()
        #endif
    }
}

private struct ClassicButtonControl: View {
    let button: TouchButton
    let label: String
    let isDown: Bool
    let frame: CGRect

    private var isWide: Bool {
        ClassicTouchLayout.usesPillArtwork(for: button)
    }

    var body: some View {
        Text(label)
            .font(.system(size: min(16, frame.height * 0.42), weight: .semibold,
                          design: .rounded))
            .tracking(isWide ? 0.8 : 0)
            .foregroundStyle(.white.opacity(isDown ? 1 : 0.82))
            .frame(width: frame.width, height: frame.height)
            .background {
                if isWide {
                    Capsule().fill(.black.opacity(isDown ? 0.74 : 0.42))
                } else {
                    Circle().fill(.black.opacity(isDown ? 0.74 : 0.42))
                }
            }
            .overlay {
                if isWide {
                    Capsule().strokeBorder(.white.opacity(isDown ? 0.92 : 0.38), lineWidth: 1.5)
                } else {
                    Circle().strokeBorder(.white.opacity(isDown ? 0.92 : 0.38), lineWidth: 1.5)
                }
            }
            .position(x: frame.midX, y: frame.midY)
    }
}

private struct ClassicStickControl: View {
    enum Side {
        case left
        case right
    }

    let controls: TouchControls
    let side: Side
    let frame: CGRect
    let radius: CGFloat

    private var touch: TouchControls.Tracked? {
        side == .left ? controls.stick : controls.rightStick
    }

    private var label: String {
        side == .left ? "L" : "R"
    }

    private var knobSize: CGFloat {
        frame.width * 0.48
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.25))
                .overlay(Circle().strokeBorder(.white.opacity(0.38), lineWidth: 2))
            Circle()
                .fill(.white.opacity(touch == nil ? 0.48 : 0.68))
                .overlay(Circle().strokeBorder(.white.opacity(0.86), lineWidth: 1.5))
                .frame(width: knobSize, height: knobSize)
                .overlay {
                    Text(label)
                        .font(.system(size: max(10, knobSize * 0.28), weight: .bold,
                                      design: .rounded))
                        .foregroundStyle(.black.opacity(0.7))
                }
                .offset(knobOffset)
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
    }

    private var knobOffset: CGSize {
        guard let touch else { return .zero }
        let push = TouchControls.classicStickDeflection(from: touch.origin, to: touch.point,
                                                        radius: radius)
        let travel = radius - knobSize / 2
        return CGSize(width: push.x * travel, height: push.y * travel)
    }
}

/// The movement ring stays at its padded default unless Dynamic Left Stick is enabled.
private struct MovementStickArtwork: View {
    let touch: TouchControls.Tracked?
    let restingOrigin: CGPoint
    let followsTouchOrigin: Bool
    let radius: CGFloat
    let knobSize: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.22))
                .overlay(Circle().strokeBorder(.white.opacity(0.32), lineWidth: 2))
            Circle()
                .fill(.white.opacity(0.56))
                .overlay(Circle().strokeBorder(.white.opacity(0.86), lineWidth: 1.5))
                .frame(width: knobSize, height: knobSize)
                .overlay {
                    Text("L")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.82))
                }
                .offset(knobOffset)
        }
        .frame(width: radius * 2, height: radius * 2)
        .position(followsTouchOrigin ? touch?.origin ?? restingOrigin : restingOrigin)
    }

    private var knobOffset: CGSize {
        guard let touch else { return .zero }
        let push = TouchControls.stickDeflection(from: touch.origin, to: touch.point,
                                                 radius: touch.radius,
                                                 deadzone: touch.deadzone,
                                                 responseExponent: touch.responseExponent)
        let travel = radius - knobSize / 2
        return CGSize(width: push.x * travel, height: push.y * travel)
    }
}

private struct RightStickControl: View {
    let controls: TouchControls
    let radius: CGFloat
    let knobSize: CGFloat

    private var isDown: Bool { controls.rightStick != nil }

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(isDown ? 0.72 : 0.42))
                .overlay(Circle().strokeBorder(.white.opacity(isDown ? 0.9 : 0.35),
                                               lineWidth: 1))
            Circle()
                .fill(.white.opacity(isDown ? 0.96 : 0.8))
                .overlay(Circle().strokeBorder(.white.opacity(isDown ? 1 : 0.7), lineWidth: 1))
                .frame(width: knobSize, height: knobSize)
                .overlay {
                    Text("R")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(isDown ? 0.82 : 0.68))
                }
                .offset(knobOffset)
        }
        .frame(width: radius * 2, height: radius * 2)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(TouchControlsView.space)).insetBy(dx: -16, dy: -16)
        } action: {
            controls.setRightStickFrame($0)
        }
    }

    private var knobOffset: CGSize {
        guard let touch = controls.rightStick else { return .zero }
        let push = TouchControls.stickDeflection(from: touch.origin, to: touch.point,
                                                 radius: touch.radius,
                                                 deadzone: touch.deadzone)
        let travel = radius - knobSize / 2
        return CGSize(width: push.x * travel, height: push.y * travel)
    }
}

private struct SwipeTrailArtwork: View {
    let touches: [TouchControls.Tracked]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: touches.isEmpty)) { timeline in
            Canvas { context, _ in
                let phase = timeline.date.timeIntervalSinceReferenceDate
                for touch in touches {
                    draw(touch, phase: phase, in: &context)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(_ touch: TouchControls.Tracked,
                      phase: TimeInterval,
                      in context: inout GraphicsContext) {
        for (index, segment) in touch.trailSegments.enumerated() {
            let isCurrent = index == touch.trailSegments.count - 1
            draw(segment, isCurrent: isCurrent, phase: phase, in: &context)
        }

        let endpointColor = touch.trailSegments.last.map { trailColor(for: $0.direction) }
            ?? .white
        let outerRect = CGRect(x: touch.point.x - 15, y: touch.point.y - 15,
                               width: 30, height: 30)
        let innerRect = outerRect.insetBy(dx: 5, dy: 5)
        context.fill(Path(ellipseIn: outerRect), with: .color(.black.opacity(0.28)))
        context.stroke(Path(ellipseIn: outerRect),
                       with: .color(endpointColor.opacity(0.9)), lineWidth: 3)
        context.stroke(Path(ellipseIn: innerRect),
                       with: .color(.white.opacity(0.72)), lineWidth: 1.5)
    }

    private func draw(_ segment: TouchControls.SwipeTrailSegment,
                      isCurrent: Bool,
                      phase: TimeInterval,
                      in context: inout GraphicsContext) {
        let fullDX = segment.end.x - segment.start.x
        let fullDY = segment.end.y - segment.start.y
        let fullLength = (fullDX * fullDX + fullDY * fullDY).squareRoot()
        guard fullLength >= 4 else { return }

        let start = isCurrent
            ? segment.start
            : CGPoint(x: segment.start.x + fullDX * 0.5,
                      y: segment.start.y + fullDY * 0.5)
        let dx = segment.end.x - start.x
        let dy = segment.end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        let color = trailColor(for: segment.direction)
        let opacity: CGFloat = isCurrent ? 1 : 0.5
        var line = Path()
        line.move(to: start)
        line.addLine(to: segment.end)
        context.stroke(line, with: .color(color.opacity(0.24 * opacity)),
                       style: StrokeStyle(lineWidth: 16, lineCap: .round))
        context.stroke(
            line,
            with: .linearGradient(
                Gradient(colors: [color.opacity(0.12 * opacity),
                                  color.opacity(0.95 * opacity)]),
                startPoint: start,
                endPoint: segment.end),
            style: StrokeStyle(lineWidth: 6, lineCap: .round))

        let unitX = dx / length
        let unitY = dy / length
        let normalX = -unitY
        let normalY = unitX
        let sparkleCount = isCurrent ? 8 : 4
        for index in 0..<sparkleCount {
            let rawFraction = phase * 0.78 + Double(index) / Double(sparkleCount)
            let fraction = CGFloat(rawFraction - floor(rawFraction))
            let side = CGFloat((index % 3) - 1) * 3.5
            let centre = CGPoint(
                x: start.x + dx * fraction + normalX * side,
                y: start.y + dy * fraction + normalY * side)
            let pulse = CGFloat(0.72 + 0.28 * sin(phase * 7 + Double(index)))
            let radius = (index.isMultiple(of: 3) ? 4.8 : 3.1) * pulse
            context.fill(sparklePath(at: centre, radius: radius),
                         with: .color(.white.opacity(
                            (segment.direction == .down ? 0.96 : 0.84) * opacity)))
        }
    }

    private func trailColor(for direction: TouchGestureDirection) -> Color {
        switch direction {
        case .left: Color(red: 1.0, green: 0.18, blue: 0.58)
        case .right: Color(red: 1.0, green: 0.42, blue: 0.08)
        case .up: Color(red: 0.12, green: 0.50, blue: 1.0)
        case .down: Color(red: 0.48, green: 0.51, blue: 0.57)
        }
    }

    private func sparklePath(at centre: CGPoint, radius: CGFloat) -> Path {
        let inner = radius * 0.24
        var path = Path()
        path.move(to: CGPoint(x: centre.x, y: centre.y - radius))
        path.addLine(to: CGPoint(x: centre.x + inner, y: centre.y - inner))
        path.addLine(to: CGPoint(x: centre.x + radius, y: centre.y))
        path.addLine(to: CGPoint(x: centre.x + inner, y: centre.y + inner))
        path.addLine(to: CGPoint(x: centre.x, y: centre.y + radius))
        path.addLine(to: CGPoint(x: centre.x - inner, y: centre.y + inner))
        path.addLine(to: CGPoint(x: centre.x - radius, y: centre.y))
        path.addLine(to: CGPoint(x: centre.x - inner, y: centre.y - inner))
        path.closeSubpath()
        return path
    }
}

#if canImport(UIKit)

/// The one view that sees raw multitouch and hands each finger to the state machine by identity.
private struct TouchSurface: UIViewRepresentable {
    let controls: TouchControls
    let lookAroundState: GOALPadLookAroundState
    let isSuppressed: Bool
    let safeAreaInsets: TouchSafeAreaInsets
    let reclaimTouchInput: () -> Bool

    func makeUIView(context: Context) -> TouchSurfaceView {
        let view = TouchSurfaceView()
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        view.setControls(controls)
        view.lookAroundState = lookAroundState
        view.isSuppressed = isSuppressed
        view.surfaceSafeAreaInsets = safeAreaInsets
        view.reclaimTouchInput = reclaimTouchInput
        return view
    }

    func updateUIView(_ view: TouchSurfaceView, context: Context) {
        view.setControls(controls)
        view.lookAroundState = lookAroundState
        view.isSuppressed = isSuppressed
        view.surfaceSafeAreaInsets = safeAreaInsets
        view.reclaimTouchInput = reclaimTouchInput
    }

    static func dismantleUIView(_ view: TouchSurfaceView, coordinator: ()) {
        view.detach()
    }
}

private final class TouchSurfaceView: UIView {
    private(set) var controls: TouchControls?
    var lookAroundState: GOALPadLookAroundState = .unknown
    var isSuppressed = false
    var surfaceSafeAreaInsets = TouchSafeAreaInsets.zero
    var reclaimTouchInput: (() -> Bool)?
    private let haptics = TouchHapticDriver()
    private var activeTouchIdentifiers: Set<ObjectIdentifier> = []

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { cancelAllTouches() }
    }

    func setControls(_ controls: TouchControls) {
        guard self.controls !== controls else { return }
        cancelAllTouches()
        self.controls = controls
    }

    func detach() {
        cancelAllTouches()
        controls = nil
        reclaimTouchInput = nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Keep one gameplay touch owner. A competing zero-distance SwiftUI gesture can starve this
        // raw multitouch path; recovery belongs here, before the same touches are mapped.
        reconcileTouchOwnership(with: event, updating: touches)
        TouchControlsView.forwardGameplayTouchBatch(
            Array(touches), isSuppressed: isSuppressed,
            reclaim: { reclaimTouchInput?() ?? false }) { touch in
            controls?.began(ObjectIdentifier(touch), at: touch.location(in: self),
                            in: bounds.size, safeAreaInsets: surfaceSafeAreaInsets,
                            at: touch.timestamp)
        }
        flushHaptics()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        reconcileTouchOwnership(with: event, updating: touches)
        for touch in touches {
            controls?.moved(ObjectIdentifier(touch), to: touch.location(in: self))
        }
        flushHaptics()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            controls?.ended(ObjectIdentifier(touch), at: touch.timestamp,
                            lookAroundState: lookAroundState)
        }
        reconcileTouchOwnership(with: event, updating: touches)
        flushHaptics()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            controls?.cancelled(ObjectIdentifier(touch))
        }
        reconcileTouchOwnership(with: event, updating: touches)
        flushHaptics()
    }

    private func reconcileTouchOwnership(with event: UIEvent?, updating touches: Set<UITouch>) {
        var liveIdentifiers = activeTouchIdentifiers
        if let allTouches = event?.allTouches {
            liveIdentifiers = Set(allTouches.compactMap { touch -> ObjectIdentifier? in
                guard touch.view === self, Self.isActive(touch.phase) else { return nil }
                return ObjectIdentifier(touch)
            })
        }
        for touch in touches {
            let id = ObjectIdentifier(touch)
            if Self.isActive(touch.phase) {
                liveIdentifiers.insert(id)
            } else {
                liveIdentifiers.remove(id)
            }
        }
        controls?.reconcileActiveTouches(liveIdentifiers)
        activeTouchIdentifiers = liveIdentifiers
    }

    private func cancelAllTouches() {
        controls?.reconcileActiveTouches([])
        activeTouchIdentifiers.removeAll()
        _ = controls?.consumeHapticEvents()
    }

    private static func isActive(_ phase: UITouch.Phase) -> Bool {
        switch phase {
        case .began, .moved, .stationary: true
        case .ended, .cancelled, .regionEntered, .regionMoved, .regionExited: false
        @unknown default: false
        }
    }

    private func flushHaptics() {
        haptics.play(controls?.consumeHapticEvents() ?? [])
    }
}

/// Maps touch-owned actions to device feedback; iPhone/iPad feedback has no controller-side locality.
private final class TouchHapticDriver {
    private let button = UIImpactFeedbackGenerator(style: .light)
    private let gesture = UIImpactFeedbackGenerator(style: .medium)
    private let stick = UISelectionFeedbackGenerator()

    func play(_ events: [TouchHapticEvent]) {
        for event in events {
            switch event {
            case .button:
                button.impactOccurred(intensity: 0.75)
                button.prepare()
            case .gesture:
                gesture.impactOccurred(intensity: 0.9)
                gesture.prepare()
            case .stickEngaged:
                stick.selectionChanged()
                stick.prepare()
            }
        }
    }
}

#endif
#endif
