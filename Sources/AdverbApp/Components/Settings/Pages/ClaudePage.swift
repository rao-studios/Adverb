//
//  ClaudePage.swift
//  Adverb
//

import AdverbCore
import AdverbRuntime
import SwiftUI

struct ClaudePage: View {
    let state: ConfigService.Center.State
    @Binding var keyDraft: String
    var root: AdverbRuntimeRoot { AdverbRuntimeRoot.shared }

    var body: some View {
        AdverbCard {
            VStack(alignment: .leading, spacing: .layer2) {
                SectionLabel("API key")
                if let source = state.keySource {
                    HStack {
                        Text(state.keyMasked ?? "••••").adverbType(.identifier)
                        Text("from \(source.label)").adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                        Spacer()
                        switch state.keyChecked {
                        case true?: Label("Works", systemImage: "checkmark.circle").adverbType(.caption).foregroundStyle(Color.adverbSuccess)
                        case false?: Label("Refused", systemImage: "xmark.circle").adverbType(.caption).foregroundStyle(Color.adverbError)
                        case nil: EmptyView()
                        }
                    }
                }
                HStack {
                    AdverbSecureField(placeholder: state.hasKey ? "Replace with a new key" : "sk-ant-…", text: $keyDraft)
                    Button("Save") { let k = keyDraft; Task { if await root.saveKey(k) { keyDraft = "" } } }
                        .buttonStyle(.adverb).disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                HStack {
                    Button("Test") { Task { await root.testKey() } }.buttonStyle(.adverbQuiet).disabled(!state.hasKey)
                    if state.keySource == .keychain { Button("Forget") { Task { await root.forgetKey() } }.buttonStyle(.adverbLink) }
                }
                Text("Kept in your login Keychain (nyc.rao.adverb). Test asks the API about the model, which costs nothing.")
                    .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
            }
        }
        AdverbCard {
            VStack(alignment: .leading, spacing: .layer3) {
                SectionLabel("Model")
                Picker("Model", selection: binding(\.model)) { ForEach(AdverbSettings.models, id: \.id) { Text($0.title).tag($0.id) } }
                Picker("Effort", selection: binding(\.effort)) { ForEach(AdverbSettings.efforts, id: \.self) { Text($0.capitalized).tag($0) } }
                    .pickerStyle(.segmented)
                Text("High is the default: planning a month and writing a page are hard work. Lower is faster and cheaper.")
                    .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                Toggle("Fall back to another model if a request is declined", isOn: binding(\.fallbacks))
                Toggle("Let the planner read the app's site and repository (web fetch)", isOn: binding(\.webFetch))
                Toggle("Review each asset's stills before rendering, and fix what is off", isOn: binding(\.reviewPass))
                Stepper("Write \(state.settings.buildConcurrency) days at a time", value: binding(\.buildConcurrency), in: 1...2)
                Text("Renders always take turns; two days at a time lets Claude write the next page while the last one renders.")
                    .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
            }
            .adverbType(.label)
        }
        AdverbCard {
            VStack(alignment: .leading, spacing: .layer2) {
                SectionLabel("The skill")
                FieldRow(label: "Using", value: state.settings.skillPath ?? "The copy built into Adverb (rao-motion-assets)")
                HStack {
                    Button("Use a SKILL.md…") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
                        panel.directoryURL = URL(fileURLWithPath: "/Volumes/T9/rao/marketing/rao-motion-assets")
                        if panel.runModal() == .OK, let url = panel.url { root.update { $0.skillPath = url.path } }
                    }.buttonStyle(.adverbQuiet)
                    if state.settings.skillPath != nil { Button("Use the built-in copy") { root.update { $0.skillPath = nil } }.buttonStyle(.adverbLink) }
                }
                Text("The skill is the system prompt for every plan and every page. Point at the T9's copy while you edit it.")
                    .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
            }
        }
    }

    private func binding<T>(_ path: WritableKeyPath<AdverbSettings, T>) -> Binding<T> {
        Binding(get: { state.settings[keyPath: path] }, set: { value in root.update { $0[keyPath: path] = value } })
    }
}
