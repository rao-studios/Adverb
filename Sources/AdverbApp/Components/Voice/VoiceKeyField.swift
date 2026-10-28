//
//  VoiceKeyField.swift
//  Adverb
//
//  WHAT: The ElevenLabs key, asked for where it is needed: in the new campaign sheet and the voice
//        sheet, the same onboarding as Settings › Voice.
//  OUT:  AdverbRuntimeRoot.saveVoiceKey
//

import AdverbRuntime
import SwiftUI

struct VoiceKeyField: View {
    @Binding var draft: String
    var onSaved: () -> Void = {}
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: .layer1) {
            HStack(spacing: .layer2) {
                AdverbSecureField(placeholder: "ElevenLabs API key", text: $draft).onSubmit(save)
                if saving { ProgressView().controlSize(.small) }
                Button("Save key", action: save).buttonStyle(.adverb)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || saving)
            }
            Text("From elevenlabs.io › Developers › API keys. Kept in your login Keychain beside your Claude key; change it any time in Settings › Voice.")
                .adverbType(.fine).foregroundStyle(Color.adverbInkMuted)
        }
    }

    private func save() {
        let key = draft
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        saving = true
        Task {
            if await AdverbRuntimeRoot.shared.saveVoiceKey(key) { draft = ""; onSaved() }
            saving = false
        }
    }
}
