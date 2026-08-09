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
    private static let pillWidth: CGFloat = 82

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
            ZStack {
                if !capturesNativeMenuInput && !capturesWarpGateTouchInput {
                    #if canImport(UIKit)
                    TouchSurface(controls: controls,
                                 lookAroundState: lookAroundState,
                                 isSuppressed: isSuppressed,
                                 reclaimTouchInput: reclaimTouchInput)
                    #endif

                    if isAwaitingTitleStart {
                        titleStartArtwork(in: proxy)
                            .allowsHitTesting(false)
                    }

                    ordinaryGameplayChrome(in: proxy)
                        .opacity(ordinaryGameplayChromeIsVisible ? 1 : 0)
                        .animation(.easeOut(duration: 0.16),
                                   value: ordinaryGameplayChromeIsVisible)

                    if titleStartTouchTargetIsVisible {
                        titleStartTouchTarget
                    }
                }

                if capturesNativeMenuInput {
                    NativeMenuTouchControls(controls: controls,
                                            actions: nativeMenuActions,
                                            isInteractive: nativeMenuControlsAreVisible,
                                            showsChrome: nativeMenuControlsAreVisible
                                                && !isSuppressed,
                                            reclaimTouchInput: reclaimTouchInput)
                        .padding(.horizontal, 20)
                        .padding(.bottom, max(20, proxy.safeAreaInsets.bottom))

                    capturedMenuChrome(in: proxy)
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
                        .padding(.bottom, max(20, proxy.safeAreaInsets.bottom))
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

    private func titleStartArtwork(in proxy: GeometryProxy) -> some View {
        let frame = ModernTouchChromeLayout(size: proxy.size).centeredSessionFrame
        return pill(.start)
            .position(x: frame.midX, y: frame.midY)
            .opacity(titleStartChromeIsVisible ? 1 : 0)
            .animation(.easeOut(duration: 0.16), value: titleStartChromeIsVisible)
    }

    /// Every eligible gameplay ornament shares this one idle-opacity transition.
    private func ordinaryGameplayChrome(in proxy: GeometryProxy) -> some View {
        let safeAreaInsets = TouchSafeAreaInsets(top: proxy.safeAreaInsets.top,
                                                 leading: proxy.safeAreaInsets.leading,
                                                 bottom: proxy.safeAreaInsets.bottom,
                                                 trailing: proxy.safeAreaInsets.trailing)
        let layout = ModernTouchLayout(size: proxy.size, safeAreaInsets: safeAreaInsets)
        let chrome = ModernTouchChromeLayout(size: proxy.size)
        let bottomInset = ModernTouchLayout.legacyRightStickEdge(for: proxy.size)

        return ZStack {
            if let stick = controls.stick {
                MovementStickArtwork(touch: stick)
                    .allowsHitTesting(false)
            }

            if activeGameplayChromeIsAvailable {
                pill(.stats)
                    .position(x: chrome.statsFrame.midX, y: chrome.statsFrame.midY)
                    .allowsHitTesting(false)
                pill(.start)
                    .position(x: chrome.startFrame.midX, y: chrome.startFrame.midY)
                    .allowsHitTesting(false)
            }

            RightStickControl(controls: controls)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, layout.rightStickSpacer)
                .padding(.bottom, bottomInset)
                .opacity(rightStickArtworkIsAvailable ? 1 : 0)
                .allowsHitTesting(false)

            zoomButton(in: proxy)
                .opacity(zoomIsAvailable ? 1 : 0)
                .allowsHitTesting(zoomIsAvailable)
        }
    }

    private func pill(_ button: TouchButton) -> some View {
        let isDown = controls.isPillDown(button)
        return Text(TouchControls.artworkLabel(for: button,
                                               sessionAction: sessionControl?.action,
                                               cutsceneSkipAvailable: cutsceneSkipAvailable))
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(.white.opacity(isDown ? 1 : 0.8))
            .frame(width: Self.pillWidth, height: 42)
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

    private func zoomButton(in proxy: GeometryProxy) -> some View {
        let frame = ModernTouchChromeLayout(size: proxy.size).zoomFrame
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

    private func capturedMenuChrome(in proxy: GeometryProxy) -> some View {
        let chrome = ModernTouchChromeLayout(size: proxy.size)
        return ZStack {
            if ecoSettingsIsVisible {
                Button { openSettings() } label: {
                    ecoSettingsPillLabel
                }
                .buttonStyle(.plain)
                .position(x: chrome.statsFrame.midX, y: chrome.statsFrame.midY)
                .accessibilityLabel("Eco Settings")
            }

            if let sessionControl {
                Button { performSessionControl(sessionControl) } label: {
                    capturedPillLabel(sessionControl.action.label.uppercased(),
                                      isEnabled: sessionControl.isEnabled)
                }
                .buttonStyle(.plain)
                .disabled(!sessionControl.isEnabled)
                .position(x: ecoSettingsIsVisible ? chrome.startFrame.midX
                                                  : chrome.centeredSessionFrame.midX,
                          y: chrome.startFrame.midY)
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
            .frame(width: Self.pillWidth, height: 42)
            .background(Capsule().fill(.black.opacity(0.42)))
            .overlay(Capsule().strokeBorder(.white.opacity(isEnabled ? 0.35 : 0.18),
                                            lineWidth: 1))
            .contentShape(Capsule())
    }

    private var ecoSettingsPillLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "gearshape")
            Text("ECO")
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .tracking(1.4)
        .foregroundStyle(.white.opacity(0.8))
        .frame(width: Self.pillWidth, height: 42)
        .background(Capsule().fill(.black.opacity(0.42)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
        .contentShape(Capsule())
    }

    /// The title prompt is an app-owned semantic action. Keep its visible Build 96 pill, but do
    /// not depend on an asynchronously cached artwork frame to decide whether Start was touched.
    private var titleStartTouchTargetIsVisible: Bool {
        gameMode == .gameplay && sessionControl == NativeSessionControlPresentation(
            action: .start, isEnabled: true)
    }

    private var titleStartTouchTarget: some View {
        Button { performTitleStart() } label: {
            Color.clear
                .frame(width: Self.pillWidth + 20, height: 66)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .accessibilityLabel("Start")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 18)
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
        HStack(alignment: .bottom, spacing: 24) {
            if !availableDirectionalActions.isEmpty {
                directionPad
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 12) {
                ForEach(commandActions, id: \.self) { action in
                    menuButton(action, width: NativeMenuCommandLayout.width)
                }
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

    private var directionPad: some View {
        VStack(spacing: 8) {
            menuButton(.up)
            HStack(spacing: 8) {
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
            .foregroundStyle(.white)
            .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.55), lineWidth: 1.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
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

/// The movement ring appears under the first finger that lands on the left half.
private struct MovementStickArtwork: View {
    let touch: TouchControls.Tracked
    private let knobSize: CGFloat = 66

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
        .frame(width: TouchControls.movementRadius * 2,
               height: TouchControls.movementRadius * 2)
        .position(touch.origin)
    }

    private var knobOffset: CGSize {
        let push = TouchControls.movementDeflection(from: touch.origin, to: touch.point)
        let travel = TouchControls.movementRadius - knobSize / 2
        return CGSize(width: push.x * travel, height: push.y * travel)
    }
}

private struct RightStickControl: View {
    let controls: TouchControls
    private let knobSize: CGFloat = 32

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
        .frame(width: TouchControls.rightStickRadius * 2,
               height: TouchControls.rightStickRadius * 2)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(TouchControlsView.space)).insetBy(dx: -16, dy: -16)
        } action: {
            controls.setRightStickFrame($0)
        }
    }

    private var knobOffset: CGSize {
        guard let touch = controls.rightStick else { return .zero }
        let push = TouchControls.rightStickDeflection(from: touch.origin, to: touch.point)
        let travel = TouchControls.rightStickRadius - knobSize / 2
        return CGSize(width: push.x * travel, height: push.y * travel)
    }
}

#if canImport(UIKit)

/// The one view that sees raw multitouch and hands each finger to the state machine by identity.
private struct TouchSurface: UIViewRepresentable {
    let controls: TouchControls
    let lookAroundState: GOALPadLookAroundState
    let isSuppressed: Bool
    let reclaimTouchInput: () -> Bool

    func makeUIView(context: Context) -> TouchSurfaceView {
        let view = TouchSurfaceView()
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        view.setControls(controls)
        view.lookAroundState = lookAroundState
        view.isSuppressed = isSuppressed
        view.reclaimTouchInput = reclaimTouchInput
        return view
    }

    func updateUIView(_ view: TouchSurfaceView, context: Context) {
        view.setControls(controls)
        view.lookAroundState = lookAroundState
        view.isSuppressed = isSuppressed
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
                            in: bounds.size, at: touch.timestamp)
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
