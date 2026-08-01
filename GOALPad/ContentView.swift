import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = GameSession()
    @State private var showDiagnostics = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            GameSurfaceView { session.tick() }

            if session.isRunning {
                if showDiagnostics {
                    DiagnosticsOverlay(session: session)
                        .frame(maxWidth: 620, alignment: .leading)
                        .padding()
                }
                Button(showDiagnostics ? "Hide" : "Info") { showDiagnostics.toggle() }
                    .buttonStyle(.bordered)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            } else if session.isBooting {
                BootingView()
            } else {
                GameDataSetupView(session: session)
            }
        }
        .task { await session.prepare() }
        .onChange(of: scenePhase) { _, phase in session.scenePhaseChanged(to: phase) }
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
            Text("GOALPad")
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
                ("989snd", boot.isSoundInstalled ? "\(boot.soundSampleRate) Hz" : "NOT running"),
                ("dispatcher frames", "\(session.framesRun)"),
                ("DMA chains built", "\(chain.chains)"),
                ("last chain payload", "\(chain.lastPayloadBytes) bytes, "
                    + "\(chain.lastTextureUploads) texture uploads"),
                ("largest chain payload", "\(chain.largestPayloadBytes) bytes"),
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
                ("frames presented", "\(session.framesPresented)"),
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

    @ViewBuilder
    private var kernel: some View {
        if let status = session.kernel {
            section("GOAL kernel", [
                ("state", status.isRunning ? "live" : "down"),
                ("architecture", status.architecture),
                ("EE main memory", String(format: "%p, #x%x", UInt(status.mainMemoryAddress),
                                          status.mainMemorySize)),
                ("PROT_EXEC granted", status.isMainMemoryExecutable ? "yes" : "NO"),
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
