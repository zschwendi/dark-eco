//
//  ContentView.swift
//  GOALPad
//
//  Created by Zach on 7/30/26.
//

import SwiftUI

struct ContentView: View {
    private let runtimeStatus = GOALPadRuntimeBridge.initializeRuntime()

    var body: some View {
        ZStack(alignment: .topLeading) {
            MetalSurfaceView()

            VStack(alignment: .leading, spacing: 6) {
                Text("GOALPad native boot")
                    .font(.headline)
                Text(runtimeStatus.message)
                Text("Architecture: \(runtimeStatus.architecture)")
                Text("AOT result: \(runtimeStatus.workloadResult)")
            }
            .font(.system(.subheadline, design: .monospaced))
            .foregroundStyle(runtimeStatus.isWorkloadVerified ? .green : .red)
            .padding()
            .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
            .padding()
        }
    }
}

#Preview {
    ContentView()
}
