//
//  VoicePage.swift
//  Adverb
//
//  WHAT: Settings › Voice: the voice packs on this Mac (Kokoro, downloaded from Rao Studios), whether
//        new campaigns are narrated and in which voice, and the languages to make once a day's
//        English is confirmed (those a pack speaks).
//

import AdverbCore
import AdverbRuntime
import SwiftUI

struct VoicePage: View {
    let state: ConfigService.Center.State
    let models: ModelService.Center.State
    let voices: VoiceService.Center.State
    var root: AdverbRuntimeRoot { AdverbRuntimeRoot.shared }

    var body: some View {
        AdverbCard {
            VStack(alignment: .leading, spacing: .layer2) {
                SectionLabel("Voice packs")
                Text("Each voice-over is spoken on this Mac. A pack is the voice model and the voices it speaks; both speak English today, built to take more languages.")
                    .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                ForEach(ModelCatalog.speech, id: \.id) { spec in
                    ModelRow(spec: spec, state: models, canRemove: true)
                }
            }
        }
        AdverbCard {
            VStack(alignment: .leading, spacing: .layer3) {
                SectionLabel("Narration")
                Toggle("Narrate new campaigns by default", isOn: binding(\.voiceOverDefault))
                FieldRow(label: "Default voice", value: state.settings.voiceName.map { name in
                    "\(name) · \(voices.pack(state.settings.voicePack ?? "")?.title ?? "")" } ?? "Not chosen yet", mono: false)
                if voices.packs.isEmpty {
                    Text("Download a voice pack above to hear and choose the voices.").adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                } else {
                    VoicePicker(selectedPack: state.settings.voicePack, selectedID: state.settings.voiceID) { v in
                        root.update { $0.voiceID = v.id; $0.voiceName = v.name; $0.voicePack = v.packID }
                    }
                }
                Text("The writer writes a short narration for each asset, timed to its text. The page plays at the voice's pace, so each line's words appear on screen as it is said; with a song, the lines land on the beat. The captions carry what it says.")
                    .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
            }
            .adverbType(.label)
        }
        AdverbCard {
            VStack(alignment: .leading, spacing: .layer3) {
                SectionLabel("Languages")
                let speakable = Swift.Set(voices.packs.flatMap(\.languages))
                LanguageChips(selected: state.settings.voiceLanguages, speakable: speakable) { languages in root.update { $0.voiceLanguages = languages } }
                Text(speakable.subtracting([.english]).isEmpty
                     ? "No voice on this Mac speaks another language yet. When a pack for one is added, its language can be chosen here; the writer already translates."
                     : (state.settings.voiceLanguages.isEmpty
                        ? "None chosen. After you confirm a day's English, these are the languages Generate makes; the choice is kept."
                        : "\(state.settings.voiceLanguages.map(\.title).joined(separator: ", ")). Kept for every day: after you confirm a day's English, Generate makes these."))
                    .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
            }
        }
        .task { await root.loadVoices() }
    }

    private func binding<T>(_ path: WritableKeyPath<AdverbSettings, T>) -> Binding<T> {
        Binding(get: { state.settings[keyPath: path] }, set: { value in root.update { $0[keyPath: path] = value } })
    }
}
