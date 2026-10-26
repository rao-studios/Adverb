//
//  RenderingPage.swift
//  Adverb
//

import AdverbCore
import AdverbRuntime
import SwiftUI

struct RenderingPage: View {
    let state: ConfigService.Center.State
    var root: AdverbRuntimeRoot { AdverbRuntimeRoot.shared }

    var body: some View {
        AdverbCard {
            VStack(alignment: .leading, spacing: .layer3) {
                SectionLabel("Quality")
                Picker("Bitrate", selection: binding(\.bitrateMbps)) {
                    Text("8 Mbps").tag(8); Text("12 Mbps").tag(12); Text("16 Mbps").tag(16)
                }
                .pickerStyle(.segmented)
                Toggle("Supersample: paint each frame at twice the size, then scale down", isOn: binding(\.supersample))
                Text("Frames go from the page to H.264 losslessly (no JPEG in between) at 30 fps, with an AAC track. Supersampling smooths fine edges and grain at about twice the render time.")
                    .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
            }
            .adverbType(.label)
        }
        AdverbCard {
            VStack(alignment: .leading, spacing: .layer3) {
                SectionLabel("Renderer")
                Picker("Renderer", selection: binding(\.renderer)) { ForEach(RendererKind.allCases, id: \.self) { Text($0.title).tag($0) } }
                    .pickerStyle(.segmented)
                Text(state.settings.renderer == .native
                     ? "WebKit paints each frame; AVFoundation encodes it. Nothing to install."
                     : "Chrome paints each frame through Playwright, as the skill's render.py does, into the same encoder. Needs python3, Playwright and Chrome.")
                    .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                HStack {
                    SectionLabel("This Mac")
                    Spacer()
                    Button("Check") { Task { await root.checkToolchain() } }.buttonStyle(.adverbQuiet)
                }
                ForEach(state.toolchain) { check in
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: check.status == .ok ? "checkmark.circle" : (check.status == .optional ? "minus.circle" : "xmark.circle"))
                            .foregroundStyle(check.status == .ok ? Color.adverbSuccess : (check.status == .optional ? Color.adverbInkMuted : Color.adverbWarning))
                        VStack(alignment: .leading, spacing: .hairline) {
                            Text(check.title).adverbType(.labelStrong)
                            Text(check.detail).adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                            if let fix = check.fix {
                                HStack {
                                    Text(fix).adverbType(.codeSmall).textSelection(.enabled)
                                    Button { Panels.copy(fix) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain).help("Copy")
                                }
                            }
                        }
                    }
                }
            }
            .adverbType(.label)
        }
        .task { if state.toolchain.isEmpty { await root.checkToolchain() } }
    }

    private func binding<T>(_ path: WritableKeyPath<AdverbSettings, T>) -> Binding<T> {
        Binding(get: { state.settings[keyPath: path] }, set: { value in root.update { $0[keyPath: path] = value } })
    }
}
