//
//  VoiceSheet.swift
//  Adverb
//
//  WHAT: A voice for one built day: the key if there is none, the model, the voices to hear and
//        choose from. Narrating replaces the day's English voice-over (and asks for it to be
//        confirmed again before its languages are made).
//  OUT:  AdverbRuntimeRoot (voice, update, stopPreview)
//

import AdverbCore
import AdverbRuntime
import SwiftUI

struct VoiceSheet: View {
    let slug: String
    let campaignID: UUID
    let dayIndex: Int
    let selection: DeskSelection
    @State private var chosen: VoiceSelection?
    @State private var model = VoiceSelection.defaultModel
    @State private var hasKey = false
    @State private var keyDraft = ""

    var root: AdverbRuntimeRoot { AdverbRuntimeRoot.shared }
    var campaign: Campaign? { root.campaigns.state.campaign(campaignID) }
    var day: CampaignDay? { campaign?.day(dayIndex) }
    var current: VoiceOver? { day?.asset?.voiceOver }

    var body: some View {
        SheetFrame(kicker: "Voice-over · \(day?.date ?? "") · \(day?.topic.title ?? "")", title: current == nil ? "Give it *a voice.*" : "Another *voice.*",
                   width: AdverbLayout.sheetWidth + 60) {
            if !hasKey {
                FormRow(label: "ElevenLabs key", hint: "Needed once. The voices are listed and heard with it.") {
                    VoiceKeyField(draft: $keyDraft) { hasKey = root.hasVoiceKey }
                }
            } else {
                FormRow(label: "Model") {
                    Picker("", selection: $model) { ForEach(AdverbSettings.voiceModels, id: \.id) { Text($0.title).tag($0.id) } }
                        .labelsHidden().fixedSize()
                }
                FormRow(label: "Voice", hint: "Press play to hear one; choose it to use it.") {
                    VoicePicker(selectedID: chosen?.voiceID, height: AdverbLayout.voiceList.tall) { v in
                        chosen = VoiceSelection(voiceID: v.id, voiceName: v.name, modelID: model)
                    }
                }
                Text(current == nil
                     ? "Claude writes the lines for this day's page, timed to its scenes; the voice speaks them over both videos, and the captions carry what it says. The frames are not rendered again."
                     : "This replaces the day's English voice-over and keeps its words; confirm it again before making its languages, which are recorded again in the new voice.")
                    .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
            }
        } actions: {
            Button("Cancel") { root.stopPreview(); selection.sheet = nil }.buttonStyle(.adverbQuiet).keyboardShortcut(.cancelAction)
            Button(current == nil ? "Narrate this day" : "Narrate again") { narrate() }
                .buttonStyle(.adverbGold).keyboardShortcut(.defaultAction).disabled(!hasKey || chosen == nil)
        }
        .onAppear {
            hasKey = root.hasVoiceKey
            chosen = current?.selection ?? campaign?.brief.voiceOver ?? root.settings.voiceSelection
            model = chosen?.modelID ?? root.settings.voiceModel
        }
        .onChange(of: model) { _, m in chosen?.modelID = m }
    }

    private func narrate() {
        guard let chosen else { return }
        root.stopPreview()
        root.update { $0.voiceID = chosen.voiceID; $0.voiceName = chosen.voiceName; $0.voiceModel = chosen.modelID }
        root.voice(slug, campaignID, day: dayIndex, selection: chosen)
        selection.sheet = nil
    }
}
