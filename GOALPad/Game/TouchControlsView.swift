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
    let progressMenuSnapshot: NativeProgressMenuSnapshot
    let warpGateTouchSnapshot: NativeWarpGateTouchSnapshot
    let cutsceneSkipTouchSnapshot: NativeCutsceneSkipTouchSnapshot
    let reclaimTouchInput: () -> Bool

    fileprivate static let space = "GOALPadTouchControls"
    private static let pillWidth: CGFloat = 82

    #if canImport(UIKit)
    @State private var titleStartHaptics = TouchHapticDriver()
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

    private var isNativeMenuOpen: Bool {
        switch gameMode {
        case .pause, .progress, .menu: true
        case .unknown, .gameplay: false
        @unknown default: false
        }
    }

    private var nativeMenuActions: [NativeMenuTouchAction] {
        NativeMenuTouchAction.available(
            in: gameMode, progress: progressMenuSnapshot, titleStartState: titleStartState)
    }

    private var sessionControl: NativeSessionControlPresentation? {
        NativeSessionControlPresentation.reduce(mode: gameMode,
                                                titleStartState: titleStartState,
                                                progress: progressMenuSnapshot)
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

    private var isVisible: Bool {
        TouchControls.artworkIsVisible(isEngaged: controls.isEngaged,
                                       isSuppressed: isSuppressed,
                                       hasTouches: !controls.touches.isEmpty,
                                       isNativeMenuOpen: isNativeMenuOpen,
                                       isAwaitingTitleStart: sessionControl?.action == .start
                                           && gameMode == .gameplay)
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

                    artwork(in: proxy)
                        .allowsHitTesting(false)
                        .opacity(isVisible ? 1 : 0)
                        .animation(.easeOut(duration: 0.16), value: isVisible)

                    if titleStartTouchTargetIsVisible {
                        titleStartTouchTarget
                    }
                }

                if capturesNativeMenuInput {
                    NativeMenuTouchControls(controls: controls,
                                            actions: nativeMenuActions,
                                            isVisible: nativeMenuControlsAreVisible,
                                            reclaimTouchInput: reclaimTouchInput)
                        .padding(.horizontal, 20)
                        .padding(.bottom, max(20, proxy.safeAreaInsets.bottom))
                }

                if !capturesNativeMenuInput
                    && (capturesWarpGateTouchInput || !warpGateActions.isEmpty) {
                    NativeWarpGateTouchControls(controls: controls,
                                                snapshot: warpGateTouchSnapshot,
                                                actions: warpGateActions,
                                                capturesInput: capturesWarpGateTouchInput,
                                                isVisible: warpGateTouchControlsAreVisible,
                                                reclaimTouchInput: reclaimTouchInput)
                        .padding(.horizontal, 20)
                        .padding(.bottom, max(20, proxy.safeAreaInsets.bottom))
                }
            }
        }
        .coordinateSpace(.named(Self.space))
        .ignoresSafeArea()
    }

    private func artwork(in proxy: GeometryProxy) -> some View {
        let safeAreaInsets = TouchSafeAreaInsets(top: proxy.safeAreaInsets.top,
                                                 leading: proxy.safeAreaInsets.leading,
                                                 bottom: proxy.safeAreaInsets.bottom,
                                                 trailing: proxy.safeAreaInsets.trailing)
        let layout = ModernTouchLayout(size: proxy.size, safeAreaInsets: safeAreaInsets)
        let bottomInset = ModernTouchLayout.legacyRightStickEdge(for: proxy.size)

        return ZStack {
            if let stick = controls.stick {
                MovementStickArtwork(touch: stick)
            }

            ForEach(controls.gestures) { gesture in
                GestureRose(gesture: gesture)
            }

            HStack(spacing: 20) {
                pill(.select)
                pill(.start)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 30)

            RightStickControl(controls: controls)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, layout.rightStickSpacer)
                .padding(.bottom, bottomInset)
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

    /// The title prompt is an app-owned semantic action. Keep its visible Build 96 pill, but do
    /// not depend on an asynchronously cached artwork frame to decide whether Start was touched.
    private var titleStartTouchTargetIsVisible: Bool {
        gameMode == .gameplay && sessionControl == NativeSessionControlPresentation(
            action: .start, isEnabled: true)
    }

    private var titleStartTouchTarget: some View {
        HStack(spacing: 20) {
            Color.clear
                .frame(width: Self.pillWidth, height: 42)
                .allowsHitTesting(false)
            Button { performTitleStart() } label: {
                Color.clear
                    .frame(width: Self.pillWidth + 20, height: 66)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .contentShape(Capsule())
            .accessibilityLabel("Start")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 18)
    }

    private func performTitleStart() {
        _ = reclaimTouchInput()
        controls.performNativeMenuAction(.start)
        #if canImport(UIKit)
        titleStartHaptics.play(controls.consumeHapticEvents())
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
    let isVisible: Bool
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
                .allowsHitTesting(isVisible)
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
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .animation(.easeOut(duration: 0.16), value: isVisible)
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
    let isVisible: Bool
    let reclaimTouchInput: () -> Bool

    #if canImport(UIKit)
    @State private var haptics = TouchHapticDriver()
    #endif

    private var directionalActions: Set<NativeMenuTouchAction> {
        Set(actions.filter { [.up, .down, .left, .right].contains($0) })
    }

    private var commandActions: [NativeMenuTouchAction] {
        actions.filter { !directionalActions.contains($0) }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 24) {
            if !directionalActions.isEmpty {
                directionPad
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 12) {
                ForEach(commandActions, id: \.self) { action in
                    menuButton(action, width: 148)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .animation(.easeOut(duration: 0.16), value: isVisible)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Game menu controls")
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onEnded { performSwipe($0.translation) }
        )
    }

    private var directionPad: some View {
        VStack(spacing: 8) {
            if directionalActions.contains(.up) {
                menuButton(.up)
            }
            HStack(spacing: 8) {
                if directionalActions.contains(.left) { menuButton(.left) }
                if directionalActions.contains(.down) { menuButton(.down) }
                if directionalActions.contains(.right) { menuButton(.right) }
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
            HStack(spacing: 8) {
                Image(systemName: action.systemImage)
                if !directionalActions.contains(action) {
                    Text(action.label)
                }
            }
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .frame(width: width, height: 60)
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

/// Face-button gestures remain available in open space without producing camera axes.
private struct GestureRose: View {
    let gesture: TouchControls.Tracked

    private static let reach = TouchControls.swipeDistance + 24

    var body: some View {
        ZStack {
            chip(.cross, isLit: gesture.swiped == .cross || gesture.jumpTriggered)
                .position(x: gesture.origin.x, y: gesture.origin.y - Self.reach)
            chip(.square, isLit: gesture.swiped == .square)
                .position(x: gesture.origin.x - Self.reach, y: gesture.origin.y)
            chip(.circle, isLit: gesture.swiped == .circle)
                .position(x: gesture.origin.x + Self.reach, y: gesture.origin.y)
            chip(.crouch, isLit: gesture.swiped == .crouch)
                .position(x: gesture.origin.x, y: gesture.origin.y + Self.reach)
        }
    }

    private func chip(_ button: TouchButton, isLit: Bool) -> some View {
        Text(button.glyph)
            .font(.system(size: 20, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(isLit ? 1 : 0.7))
            .frame(width: 46, height: 46)
            .background(Circle().fill(.black.opacity(isLit ? 0.7 : 0.3)))
            .overlay(Circle().strokeBorder(.white.opacity(isLit ? 0.9 : 0.3), lineWidth: 1.5))
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
        view.controls = controls
        view.lookAroundState = lookAroundState
        view.isSuppressed = isSuppressed
        view.reclaimTouchInput = reclaimTouchInput
        return view
    }

    func updateUIView(_ view: TouchSurfaceView, context: Context) {
        view.controls = controls
        view.lookAroundState = lookAroundState
        view.isSuppressed = isSuppressed
        view.reclaimTouchInput = reclaimTouchInput
    }
}

private final class TouchSurfaceView: UIView {
    var controls: TouchControls?
    var lookAroundState = GOALPadLookAroundState.unknown
    var isSuppressed = false
    var reclaimTouchInput: (() -> Bool)?
    private let haptics = TouchHapticDriver()
    private let pinchRecognizer = UIPinchGestureRecognizer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        pinchRecognizer.addTarget(self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinchRecognizer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Keep one gameplay touch owner. A competing zero-distance SwiftUI gesture can starve this
        // raw multitouch path; recovery belongs here, before the same touches are mapped.
        TouchControlsView.forwardGameplayTouchBatch(
            Array(touches), isSuppressed: isSuppressed,
            reclaim: { reclaimTouchInput?() ?? false }) { touch in
            controls?.began(ObjectIdentifier(touch), at: touch.location(in: self),
                            in: bounds.size, at: touch.timestamp)
        }
        flushHaptics()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            controls?.moved(ObjectIdentifier(touch), to: touch.location(in: self))
        }
        flushHaptics()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            controls?.ended(ObjectIdentifier(touch), at: touch.timestamp)
        }
        flushHaptics()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            controls?.cancelled(ObjectIdentifier(touch))
        }
        flushHaptics()
    }

    @objc private func handlePinch(_ pinch: UIPinchGestureRecognizer) {
        switch pinch.state {
        case .began:
            controls?.pinchBegan()
            controls?.pinchChanged(scale: pinch.scale, lookAroundState: lookAroundState)
        case .changed:
            controls?.pinchChanged(scale: pinch.scale, lookAroundState: lookAroundState)
        case .ended:
            controls?.pinchEnded()
        case .cancelled, .failed:
            controls?.pinchCancelled()
        case .possible:
            break
        @unknown default:
            controls?.pinchCancelled()
        }
        flushHaptics()
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
