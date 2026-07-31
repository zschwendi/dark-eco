//
//  ContentView.swift
//  GOALPad
//
//  Created by Zach on 7/30/26.
//

import SwiftUI

/// Owns the lifetime of the process-wide GOAL kernel session.
@MainActor
@Observable
final class KernelSession {
    private(set) var status: GOALPadKernelStatus?

    var isRunning: Bool { status?.isRunning ?? false }

    func start() {
        guard status?.isRunning != true else { return }
        status = GOALPadRuntimeBridge.startKernel()
    }

    func stop() {
        GOALPadRuntimeBridge.stopKernel()
        status = nil
    }
}

struct ContentView: View {
    @State private var session = KernelSession()

    var body: some View {
        ZStack(alignment: .topLeading) {
            MetalSurfaceView()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    if let status = session.status {
                        readout(for: status)
                    } else {
                        Text("No kernel session.")
                    }
                }
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.white)
                .padding()
                .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
                .padding()
            }
        }
        .onAppear { session.start() }
    }

    private var header: some View {
        HStack {
            Text("OpenGOAL Jak 1 kernel")
                .font(.headline)
            Spacer()
            Button(session.isRunning ? "Shut down" : "Start") {
                if session.isRunning {
                    session.stop()
                } else {
                    session.start()
                }
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func readout(for status: GOALPadKernelStatus) -> some View {
        Text(status.message)
            .foregroundStyle(status.isRunning ? .green : .red)

        if status.isRunning {
            section("EE main memory", [
                ("base", String(format: "%p", UInt(status.mainMemoryAddress))),
                ("size", String(format: "#x%x (%.0f MiB)", status.mainMemorySize,
                                Double(status.mainMemorySize) / 1_048_576)),
                ("PROT_EXEC granted", status.isMainMemoryExecutable ? "yes" : "NO"),
            ])

            section("Kernel heaps", [
                ("global base", goalPointer(status.globalHeapBaseOffset)),
                ("global current", goalPointer(status.globalHeapCurrentOffset)),
                ("global top base", goalPointer(status.globalHeapTopBaseOffset)),
                ("global used", "\(status.globalHeapUsedBytes) bytes"),
                ("debug base", goalPointer(status.debugHeapBaseOffset)),
            ])

            section("Symbol table", [
                ("table", goalPointer(status.symbolTableOffset)),
                ("s7", goalPointer(status.s7Offset)),
                ("last symbol", goalPointer(status.lastSymbolOffset)),
                ("hashed symbols", "\(status.symbolCount)"),
            ])

            Text("Bootstrapped types (read out of the live heap)")
                .font(.system(.footnote, design: .monospaced).weight(.semibold))
            ForEach(status.types, id: \.symbolName) { type in
                Text("  \(type.typeName) : \(type.parentName)  " +
                     "\(goalPointer(type.typeOffset))  size \(type.allocatedSize)  " +
                     "methods \(type.methodCount)")
            }

            Text("Architecture: \(status.architecture)")
            Text("Storage: \(status.storagePath)")
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ rows: [(String, String)]) -> some View {
        Text(title)
            .font(.system(.footnote, design: .monospaced).weight(.semibold))
        ForEach(rows, id: \.0) { row in
            Text("  \(row.0): \(row.1)")
        }
    }

    private func goalPointer(_ offset: UInt32) -> String {
        String(format: "#x%08x", offset)
    }
}

#Preview {
    ContentView()
}
