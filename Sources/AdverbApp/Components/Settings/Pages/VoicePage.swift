//
//  VoicePage.swift
//  Adverb
//
//  WHAT: Settings › Voice: the ElevenLabs key and what is left of the month's characters, whether
//        new campaigns are narrated, the voice and model they start with, and the languages to make
//        once a day's English is confirmed.
//

import AdverbCore
import AdverbRuntime
import SwiftUI

struct VoicePage: View {
    let state: ConfigService.Center.State
    @Binding var keyDraft: String
    var root: AdverbRuntimeRoot { AdverbRuntimeRoot.shared }

    /// "12,340 of 100,000 characters used this period, resets Nov 12".
    static func quotaLine(_ q: VoiceQuota) -> String {
        var line = "\(q.used.formatted()) of \(q.limit.formatted()) characters used this period"
        if let reset = q.resetsAt { line += ", resets \(reset.formatted(.dateTime.month(.abbreviated).day()))" }
        if let tier = q.tier, !tier.isEmpty { line += " · \(tier.capitalized) plan" }
        return line
    }

    var body: some View {
        AdverbCard {
            VStack(alignment: .leading, spacing: .layer2) {
                SectionLabel("ElevenLabs key")
                if let source = state.voiceKeySource {
                    HStack {
                        Text(state.voiceKeyMasked ?? "••••").adverbType(.identifier)
                        Text("from \(source.label(env: KeyResolver.elevenLabsEnv))").adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                        Spacer()
                        switch state.voiceKeyChecked {
                        case true?: Label("Works", systemImage: "checkmark.circle").adverbType(.caption).foregroundStyle(Color.adverbSuccess)
                        case false?: Label("Refused", systemImage: "xmark.circle").adverbType(.caption).foregroundStyle(Color.adverbError)
                        case nil: EmptyView()
                        }
                    }
                    if let quota = state.voiceQuota { Text(Self.quotaLine(quota)).adverbType(.caption).foregroundStyle(Color.adverbInkSoft) }
                }
                HStack {
                    AdverbSecureField(placeholder: state.hasVoiceKey ? "Replace with a new key" : "ElevenLabs API key", text: $keyDraft)
                    Button("Save") { let k = keyDraft; Task { if await root.saveVoiceKey(k) { keyDraft = "" } } }
                        .buttonStyle(.adverb).disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                HStack {
                    Button("Test") { Task { await root.testVoiceKey() } }.buttonStyle(.adverbQuiet).disabled(!state.hasVoiceKey)
                    if state.voiceKeySource == .keychain { Button("Forget") { Task { await root.forgetVoiceKey() } }.buttonStyle(.adverbLink) }
                }
                Text("Optional: without it, assets stay silent as before. Kept in your login Keychain (nyc.rao.adverb, ELEVENLABS_API_KEY); ELEVENLABS_API_KEY in the environment works too. Test reads your subscription, which costs nothing.")
                    .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
            }
        }
        AdverbCard {
            VStack(alignment: .leading, spacing: .layer3) {
                SectionLabel("Narration")
                Toggle("Narrate new campaigns by default", isOn: binding(\.voiceOverDefault))
                Picker("Model", selection: binding(\.voiceModel)) { ForEach(AdverbSettings.voiceModels, id: \.id) { Text($0.title).tag($0.id) } }
                FieldRow(label: "Default voice", value: state.settings.voiceName ?? "Not chosen yet", mono: false)
                if state.hasVoiceKey {
                    VoicePicker(selectedID: state.settings.voiceID) { v in root.update { $0.voiceID = v.id; $0.voiceName = v.name } }
                } else {
                    Text("Add a key above to list and hear the voices.").adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                }
                Text("Claude writes a short narration for each asset, timed to its text. The page plays at the voice's pace, so each line's words appear on screen as it is said; with a song, the lines land on the beat. The captions carry what it says. ElevenLabs bills each character spoken.")
                    .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
            }
            .adverbType(.label)
        }
        AdverbCard {
            VStack(alignment: .leading, spacing: .layer3) {
                SectionLabel("Languages")
                LanguageChips(selected: state.settings.voiceLanguages) { languages in root.update { $0.voiceLanguages = languages } }
                Text(state.settings.voiceLanguages.isEmpty
                     ? "None chosen. After you confirm a day's English, these are the languages Generate makes; the choice is kept."
                     : "\(state.settings.voiceLanguages.map(\.title).joined(separator: ", ")). Kept for every day: after you confirm a day's English, Generate makes these.")
                    .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
            }
        }
    }

    private func binding<T>(_ path: WritableKeyPath<AdverbSettings, T>) -> Binding<T> {
        Binding(get: { state.settings[keyPath: path] }, set: { value in root.update { $0[keyPath: path] = value } })
    }
}
