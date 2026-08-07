import SwiftUI

nonisolated enum GameplaySurfaceLayout {
    struct SafeAreaInsets: Equatable, Sendable {
        let top: CGFloat
        let leading: CGFloat
        let bottom: CGFloat
        let trailing: CGFloat
    }

    /// Uses a 4:3 host surface in portrait so the renderer's existing Classic and Fit to Screen
    /// geometry continues to choose the presentation. Landscape keeps its full existing surface.
    static func frame(in container: CGSize, safeAreaInsets: SafeAreaInsets) -> CGRect {
        let width = max(container.width, 0)
        let height = max(container.height, 0)
        guard height > width else {
            return CGRect(origin: .zero, size: CGSize(width: width, height: height))
        }

        let top = min(max(safeAreaInsets.top, 0), height)
        let bottom = min(max(safeAreaInsets.bottom, 0), height - top)
        let leading = min(max(safeAreaInsets.leading, 0), width)
        let trailing = min(max(safeAreaInsets.trailing, 0), width - leading)
        let contentWidth = width - leading - trailing
        let contentHeight = height - top - bottom
        let rendererHeight = min(contentWidth * 3 / 4, contentHeight)

        return CGRect(x: leading, y: top, width: contentWidth, height: rendererHeight)
    }
}

private enum SettingsSheetEntry: Hashable {
    case titles
    case jak1
}

private struct SettingsSheetPresentation: Identifiable {
    let id: Int
    let entry: SettingsSheetEntry
}

struct ContentView: View {
    private enum LauncherDestination {
        case library
        case gameSetup
    }

    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var gameCenter: GameCenterService
    @State private var session = GameSession()
    @State private var artworkStore = GameArtworkStore()
    @State private var launcherDestination = LauncherDestination.library
    @State private var settingsPresentation: SettingsSheetPresentation?
    @State private var nextSettingsPresentationID = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            GameplaySurface(session: session)

            if session.isRunning {
                #if os(iOS)
                TouchControlsView(controls: session.touch,
                                  lookAroundState: session.lookAroundState,
                                  isSuppressed: session.input.isDriving,
                                  gameMode: session.gameMode,
                                  titleStartState: session.titleStartState,
                                  runReadiness: session.runReadiness,
                                  progressMenuSnapshot: session.progressMenuSnapshot,
                                  warpGateTouchSnapshot: session.warpGateTouchSnapshot,
                                  cutsceneSkipTouchSnapshot: session.cutsceneSkipTouchSnapshot,
                                  facePromptTouchSnapshot: session.facePromptTouchSnapshot,
                                  reclaimTouchInput: session.input.reclaimTouchInput,
                                  openSettings: { presentSettings(.jak1) })
                #endif

                if session.isNativeMenuOpen
                    && session.presentationSettings.developerLogsEnabled {
                    DiagnosticsOverlay(session: session)
                        .frame(maxWidth: 620, alignment: .leading)
                        .padding()
                }
            } else if session.isBooting {
                BootingView()
            } else {
                switch launcherDestination {
                case .library:
                    GameLibraryView(
                        session: session,
                        artworkStore: artworkStore,
                        openJak1Setup: { launcherDestination = .gameSetup },
                        openSettings: { presentSettings(.titles) }
                    )
                case .gameSetup:
                    NavigationStack {
                        GameDataSetupView(session: session)
                            .navigationTitle("Game Setup")
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button {
                                        launcherDestination = .library
                                    } label: {
                                        Label("Library", systemImage: "chevron.left")
                                    }
                                }
                                ToolbarItem(placement: .primaryAction) {
                                    Button { presentSettings(.titles) } label: {
                                        Image(systemName: "gearshape")
                                    }
                                    .accessibilityLabel("Settings")
                                }
                            }
                    }
                    .preferredColorScheme(.dark)
                    .tint(DarkEcoTheme.accent)
                }
            }
        }
        .task { await session.prepare() }
        .onChange(of: scenePhase) { _, phase in session.scenePhaseChanged(to: phase) }
        .onChange(of: session.isRunning, initial: true) { _, isRunning in
            gameCenter.setGameplayActive(isRunning)
        }
        .onChange(of: session.presentationSettings.graphicsFillWidth, initial: true) {
            _, enabled in
            session.settings.horizontalPlusEnabled = enabled
        }
        .onChange(of: session.presentationSettings.primaryInputSource, initial: true) {
            _, source in
            session.input.setPrimarySource(source)
        }
        .onChange(of: session.presentationSettings.jak1InputBindings, initial: true) {
            _, bindings in
            session.input.setBindings(bindings)
        }
        .onChange(of: session.isNativeMenuOpen) { _, isOpen in
            if session.isRunning && !isOpen { settingsPresentation = nil }
        }
        .sheet(item: $settingsPresentation) { presentation in
            SettingsSheetView(initialEntry: presentation.entry,
                              sync: session.saveSync,
                              settings: session.presentationSettings,
                              input: session.input)
                .id(presentation.id)
                .frame(minWidth: 360, minHeight: 360)
        }
    }

    private func presentSettings(_ entry: SettingsSheetEntry) {
        nextSettingsPresentationID += 1
        settingsPresentation = SettingsSheetPresentation(id: nextSettingsPresentationID, entry: entry)
    }
}

private struct SettingsSheetView: View {
    private enum Destination: Hashable {
        case jak1
    }

    @Environment(\.dismiss) private var dismiss
    @Bindable var sync: SaveSyncController
    @Bindable var settings: PresentationSettings
    @Bindable var input: ControllerInput
    @State private var path: [Destination]

    init(initialEntry: SettingsSheetEntry,
         sync: SaveSyncController,
         settings: PresentationSettings,
         input: ControllerInput) {
        self.sync = sync
        self.settings = settings
        self.input = input
        _path = State(initialValue: initialEntry == .jak1 ? [.jak1] : [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            SettingsTitleListView(openJak1: { path.append(.jak1) })
                .navigationDestination(for: Destination.self) { destination in
                    switch destination {
                    case .jak1:
                        SaveSettingsView(sync: sync, settings: settings, input: input)
                    }
                }
        }
        .tint(DarkEcoTheme.accent)
        .background(DarkEcoTheme.background)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

private struct SettingsTitleListView: View {
    let openJak1: () -> Void

    var body: some View {
        List {
            Section("Available") {
                Button(action: openJak1) {
                    LabeledContent("Jak 1 Settings", value: "Available")
                }
            }

            Section("Planned") {
                SettingsTitleStatusRow(title: "Jak II")
                SettingsTitleStatusRow(title: "Jak 3")
            }
        }
        .navigationTitle("Settings")
    }
}

private struct SettingsTitleStatusRow: View {
    let title: String

    var body: some View {
        LabeledContent(title, value: "Planned")
            .foregroundStyle(.secondary)
            .accessibilityLabel("\(title) Settings, Planned")
    }
}

private struct GameplaySurface: View {
    let session: GameSession

    var body: some View {
        GeometryReader { proxy in
            let frame = GameplaySurfaceLayout.frame(
                in: proxy.size,
                safeAreaInsets: .init(
                    top: proxy.safeAreaInsets.top,
                    leading: proxy.safeAreaInsets.leading,
                    bottom: proxy.safeAreaInsets.bottom,
                    trailing: proxy.safeAreaInsets.trailing
                )
            )

            if frame.origin == .zero, frame.size == proxy.size {
                // Preserve Build 93's exact edge-to-edge surface in landscape. Constraining an
                // ignoresSafeArea view to the GeometryReader's safe-area proposal reintroduced
                // thin bars even though the calculated frame itself covered the proposal.
                GameSurfaceView { session.tick(targetPresentationTime: $0) }
            } else {
                GameSurfaceView { session.tick(targetPresentationTime: $0) }
                    .frame(width: frame.width, height: frame.height)
                    .clipped()
                    .position(x: frame.midX, y: frame.midY)
            }
        }
    }
}

/// The game's own startup: two DGO archives and `play`, which take seconds.
private struct BootingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Booting Jak 1")
                .font(.system(.headline, design: .monospaced))
            Text("KERNEL.CGO, GAME.CGO, then the title level")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The live state of every piece of the shell. This is a readout, not a fixture: every number is
/// read back out of the running kernel, the surface, the controller, or the audio device.
private struct DiagnosticsOverlay: View {
    @Bindable var session: GameSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header
                seams
                game
                renderer
                surface
                controller
                audio
                kernel
            }
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(.white)
            .padding()
            .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var header: some View {
        HStack {
            Text(GOALPadBuildIdentity.displayText)
                .font(.headline)
            Spacer()
            Button("Shut down") { session.shutdown() }
                .buttonStyle(.bordered)
        }
    }

    private var seams: some View {
        section("Engine seams in this build", [
            ("game data", flag(GOALPadRuntimeBridge.isDataSeamLinked)),
            ("controller", flag(GOALPadRuntimeBridge.isInputSeamLinked)),
            ("audio", flag(GOALPadRuntimeBridge.isAudioSeamLinked)),
            ("Jak 1 GOAL code", flag(GOALPadRuntimeBridge.isGameCodeLinked)),
            ("renderer", flag(GOALPadRenderSurface.shared.isRendererLinked)),
        ])
    }

    /// The game itself: what booted out of the player's own archives and what the frames are doing.
    @ViewBuilder
    private var game: some View {
        if let boot = session.boot {
            let chain = session.frameChain
            section("Jak 1", [
                ("KERNEL.CGO", "\(boot.kernelObjects) objects"),
                ("GAME.CGO", "\(boot.gameObjects) objects: \(boot.codeObjects) code, "
                    + "\(boot.dataObjects) data"),
                ("GOAL kernel version", "\(boot.kernelVersion >> 0x13).\((boot.kernelVersion >> 3) & 0xffff)"),
                ("boot took", String(format: "%.1f s", boot.duration)),
                ("global heap after boot", "\(boot.globalHeapUsedBytes) bytes"),
                ("symbols after boot", "\(boot.symbolCount)"),
                ("989snd", boot.isSoundInstalled ? "\(boot.soundSampleRate) Hz" : "NOT running"),
                ("dispatcher frames", "\(session.framesRun)"),
            ] + (boot.isRendererInstalled ? [] : [
                // Only measured when the renderer did not start; otherwise it owns the chain and
                // the renderer section below reports it.
                ("DMA chains built", "\(chain.chains)"),
                ("last chain payload", "\(chain.lastPayloadBytes) bytes, "
                    + "\(chain.lastTextureUploads) texture uploads"),
                ("largest chain payload", "\(chain.largestPayloadBytes) bytes"),
            ]))
        }
    }

    private func mercTransformIdentity(_ event: GOALPadMercTransformEvent) -> String {
        guard event.issueMask != 0 else { return "-" }
        return "issue/slot \(event.issueMask)/\(event.boneSlot), frames "
            + "\(event.previousFrameID)->\(event.currentFrameID), tick/chain "
            + "\(event.hostTickID)/\(event.chainOrdinal), model "
            + String(event.modelNameHash, radix: 16) + ", matrices "
            + String(event.previousMatrixHash, radix: 16) + "->"
            + String(event.currentMatrixHash, radix: 16)
    }

    private func mercTransformShape(_ event: GOALPadMercTransformEvent) -> String {
        guard event.issueMask != 0 else { return "-" }
        return String(
            format: "scale %.6g->%.6g, aspect %.6g->%.6g, axes "
                + "[%.6g,%.6g,%.6g]->[%.6g,%.6g,%.6g], source %llx->%llx",
            event.previousScale,
            event.currentScale,
            event.previousAspect,
            event.currentAspect,
            event.previousAxisNormX,
            event.previousAxisNormY,
            event.previousAxisNormZ,
            event.currentAxisNormX,
            event.currentAxisNormY,
            event.currentAxisNormZ,
            event.previousSourceBase,
            event.currentSourceBase)
    }

    /// The Metal renderer: what the game handed it, and what it read off the player's own disc.
    @ViewBuilder
    private var renderer: some View {
        if GOALPadRenderSurface.shared.isRendererLinked {
            let stats = GOALPadRenderSurface.shared.stats
            let wanted = GOALPadRenderSurface.shared.levelsWanted
            let loaded = GOALPadRenderSurface.shared.levelsLoaded
            let oneChainTicks = stats.framesArmed
                - stats.framesWithoutChain
                - stats.framesWithMultipleChains
            section("Metal renderer", [
                ("DMA chains", "\(stats.chainsSent) sent, \(stats.chainsRendered) encoded, "
                    + "\(stats.chainsDropped) dropped"),
                ("tick chains 0/1/>1", "\(stats.framesWithoutChain)/\(oneChainTicks)/"
                    + "\(stats.framesWithMultipleChains) (max \(stats.maxChainsPerFrame))"),
                ("drawables", "\(stats.drawablesAcquired) scheduled, \(stats.drawableMisses) missed, "
                    + "\(stats.latePresentSubmissions) submitted late"),
                ("camera provenance", "frame \(stats.lastEngineFrameID), tick/chain "
                    + "\(stats.lastHostTickID)/\(stats.lastChainOrdinal), "
                    + "\(stats.lastCameraPackets) packets, hash "
                    + String(stats.lastCameraFingerprint, radix: 16)),
                ("camera alternation", "\(stats.producerCameraAlternations) total; frames "
                    + "\(stats.lastCameraAlternationOlderFrameID)/"
                    + "\(stats.lastCameraAlternationPreviousFrameID)/"
                    + "\(stats.lastCameraAlternationCurrentFrameID), tick/chain "
                    + "\(stats.lastCameraAlternationHostTickID)/"
                    + "\(stats.lastCameraAlternationChainOrdinal)"),
                ("alternation fingerprints", String(
                    stats.lastCameraAlternationOlderFingerprint, radix: 16)
                    + "/" + String(stats.lastCameraAlternationPreviousFingerprint, radix: 16)
                    + "/" + String(stats.lastCameraAlternationCurrentFingerprint, radix: 16)
                    + " producer, "
                    + String(stats.lastCameraAlternationPacketFingerprint, radix: 16)
                    + " packet; subset qwords \(stats.lastCameraAlternationLiveMismatchQwords)/"
                    + "\(stats.lastCameraAlternationPacketMismatchQwords), full qwords "
                    + "\(stats.lastCameraAlternationRenderLiveMismatchQwords)/"
                    + "\(stats.lastCameraAlternationRenderPacketMismatchQwords)"),
                ("alternation distance", String(
                    format: "%.6f / %.6f / %.6f older-prev/prev-current/older-current",
                    stats.lastCameraOlderToPreviousDistance,
                    stats.lastCameraPreviousToCurrentDistance,
                    stats.lastCameraOlderToCurrentDistance)),
                ("camera mismatches", "\(stats.liveCameraMismatches) live / "
                    + "\(stats.packetCameraMismatches) packet total; last qwords "
                    + "\(stats.lastLiveCameraMismatchQwords)/"
                    + "\(stats.lastPacketCameraMismatchQwords)"),
                ("presentation identity", "submit/present/drop \(stats.lastSubmissionID)/"
                    + "\(stats.lastPresentedSubmissionID)/\(stats.lastDroppedSubmissionID), "
                    + "drawable \(stats.lastDrawableID)/"
                    + "\(stats.lastPresentedDrawableID), reversed "
                    + "\(stats.presentationOrderMismatches)"),
                ("presented frame", "\(stats.lastPresentedEngineFrameID), tick/chain "
                    + "\(stats.lastPresentedHostTickID)/\(stats.lastPresentedChainOrdinal), "
                    + "\(stats.presentationsCompleted)/\(stats.presentationDrops)/"
                    + "\(stats.submissions) completed/dropped/submitted"),
                ("last frame", "\(stats.lastDrawCalls) draws, \(stats.lastTriangles) triangles"),
                ("last merc", "\(stats.mercModels) models, \(stats.mercDraws) draws, "
                    + "\(stats.mercBoneVectors) bone vectors"),
                ("merc missing bones", "current \(stats.mercMissingBoneSlots) slots / "
                    + "\(stats.mercModelsWithMissingBoneSlots) models; total "
                    + "\(stats.mercMissingBoneSlotsTotal) / "
                    + "\(stats.mercModelsWithMissingBoneSlotsTotal); last "
                    + "\(stats.lastMercMissingBoneSlots) / "
                    + "\(stats.lastMercModelsWithMissingBoneSlots) at frame/tick/chain "
                    + "\(stats.lastMercMissingBoneEngineFrameID)/"
                    + "\(stats.lastMercMissingBoneHostTickID)/"
                    + "\(stats.lastMercMissingBoneChainOrdinal)"),
                ("merc palette health", "current \(stats.mercNonfiniteBoneMatrices)/"
                    + "\(stats.mercDegenerateBoneMatrices)/"
                    + "\(stats.mercIncoherentBoneSources)/"
                    + "\(stats.mercModelsWithPaletteHealthIssues) "
                    + "nonfinite/degenerate/source/models; total "
                    + "\(stats.mercNonfiniteBoneMatricesTotal)/"
                    + "\(stats.mercDegenerateBoneMatricesTotal)/"
                    + "\(stats.mercIncoherentBoneSourcesTotal)/"
                    + "\(stats.mercModelsWithPaletteHealthIssuesTotal)"),
                ("merc palette event", "issue/slot \(stats.lastMercPaletteHealthIssueMask)/"
                    + "\(stats.lastMercPaletteHealthBoneSlot), frame/tick/chain "
                    + "\(stats.lastMercPaletteHealthEngineFrameID)/"
                    + "\(stats.lastMercPaletteHealthHostTickID)/"
                    + "\(stats.lastMercPaletteHealthChainOrdinal), model/matrix "
                    + String(stats.lastMercPaletteHealthModelNameHash, radix: 16)
                    + "/" + String(stats.lastMercPaletteHealthMatrixHash, radix: 16)),
                ("merc transform events", "current \(stats.mercEicharTransformDiscontinuities), "
                    + "total \(stats.mercEicharTransformDiscontinuitiesTotal)"),
                ("merc transform first", mercTransformIdentity(
                    stats.firstMercEicharTransformDiscontinuity)),
                ("merc first shape", mercTransformShape(
                    stats.firstMercEicharTransformDiscontinuity)),
                ("merc transform last", mercTransformIdentity(
                    stats.lastMercEicharTransformDiscontinuity)),
                ("merc last shape", mercTransformShape(
                    stats.lastMercEicharTransformDiscontinuity)),
                ("merc rejects total", "\(stats.mercBadBonePointers) bone pointers, "
                    + "\(stats.mercBadDrawRanges) draw ranges total"),
                ("texture uploads", "\(stats.textureUploads)"),
                ("levels wanted", wanted.isEmpty ? "-" : wanted),
                ("level art loaded", loaded.isEmpty ? "-" : loaded),
                ("level art failures", "\(stats.levelFailures)"),
            ])
        }
    }

    private var surface: some View {
        let geometry = session.geometry
        return VStack(alignment: .leading, spacing: 4) {
            section("Presentation surface", [
                ("drawable", "\(geometry.drawableWidth)x\(geometry.drawableHeight)"),
                ("internal", "\(geometry.internalWidth)x\(geometry.internalHeight)"),
                ("draw region", "\(geometry.drawRegionWidth)x\(geometry.drawRegionHeight)"),
                ("ticks with drawable", "\(session.framesPresented)"),
                ("display cadence", String(format: "%.2f / %.2f / %.2f ms mean/p95/max (%d)",
                                            session.displayMeanMilliseconds,
                                            session.displayP95Milliseconds,
                                            session.displayMaxMilliseconds,
                                            session.displaySampleCount)),
                ("display fast/slow", "\(session.displayFastCallbacks)/"
                    + "\(session.displaySlowCallbacks) below 12 / at least 24 ms"),
                ("memory warnings", "\(session.memoryWarnings)"),
            ])
            let scale = Binding(get: { session.settings.internalResolutionScale },
                                set: { session.settings.internalResolutionScale = $0 })
            Picker("Internal resolution", selection: scale) {
                ForEach(RenderSettings.availableScales, id: \.self) { scale in
                    Text("\(scale)x  \(session.settings.label(for: scale))").tag(scale)
                }
            }
            .pickerStyle(.menu)
            if !GOALPadRenderSurface.shared.lastError.isEmpty {
                Text(GOALPadRenderSurface.shared.lastError).foregroundStyle(.red)
            }
        }
    }

    private var controller: some View {
        section("Controller", [
            ("device", session.input.controllerName ?? "none connected"),
            ("DualSense", flag(session.input.isDualSense)),
            ("held", buttonNames(session.input.buttons)),
            ("left stick", "\(session.input.leftStick.x), \(session.input.leftStick.y)"),
            ("right stick", "\(session.input.rightStick.x), \(session.input.rightStick.y)"),
            ("rumble", "large \(session.input.rumble.large), small \(session.input.rumble.small)"),
            ("reads by GOAL", "\(GOALPadInputReadCount(ControllerInput.primaryPort))"),
        ])
    }

    private var audio: some View {
        section("Audio", [
            ("device", session.audio.isRunning ? "running" : "stopped"),
            ("rate", "\(session.audio.sampleRate) Hz stereo"),
            ("frames asked for", "\(session.audio.framesRequested)"),
            ("frames produced", "\(session.audio.framesProduced)"),
            ("peak sample", "\(session.audio.peakAmplitude) of 32767"),
            ("error", session.audio.lastError ?? "none"),
        ])
    }

    /// What `start_kernel` found, before any game data was loaded. The live heap and symbol counts
    /// are in the Jak 1 section above.
    @ViewBuilder
    private var kernel: some View {
        if let status = session.kernel {
            section("GOAL kernel at startup", [
                ("state", status.isRunning ? "live" : "down"),
                ("architecture", status.architecture),
                ("EE main memory", String(format: "%p, #x%x", UInt(status.mainMemoryAddress),
                                          status.mainMemorySize)),
                ("EE arena executable", status.isMainMemoryExecutable ? "yes" : "NO"),
                ("s7", String(format: "#x%08x", status.s7Offset)),
                ("hashed symbols", "\(status.symbolCount)"),
                ("global heap used", "\(status.globalHeapUsedBytes) bytes"),
                ("data directory", status.isDataDirectoryAccepted ? status.dataDirectory
                    : "NOT connected"),
            ])
            Text(status.message)
                .foregroundStyle(status.isRunning ? .green : .red)
        }
    }

    private func section(_ title: String, _ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(.footnote, design: .monospaced).weight(.semibold))
            ForEach(rows, id: \.0) { row in
                Text("  \(row.0): \(row.1)")
            }
        }
    }

    private func flag(_ value: Bool) -> String {
        value ? "linked" : "not in this build"
    }

    private func buttonNames(_ buttons: GOALPadButton) -> String {
        let names: [(GOALPadButton, String)] = [
            (.cross, "X"), (.circle, "O"), (.square, "[]"), (.triangle, "/\\"),
            (.up, "up"), (.down, "down"), (.left, "left"), (.right, "right"),
            (.L1, "L1"), (.R1, "R1"), (.L2, "L2"), (.R2, "R2"),
            (.L3, "L3"), (.R3, "R3"), (.start, "start"), (.select, "select"),
        ]
        let held = names.filter { buttons.contains($0.0) }.map(\.1)
        return held.isEmpty ? "-" : held.joined(separator: " ")
    }
}
