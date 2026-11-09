//
//  VoiceSheet.swift
//  Adverb
//
//  WHAT: A voice for one built day: the voices on this Mac to hear and choose from (or where to get
//        one). Narrating replaces the day's English voice-over (and asks for it to be confirmed again
//        before its languages are made).
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
    @State private var hasVoice = false

    var root: AdverbRuntimeRoot { AdverbRuntimeRoot.shared }
    var campaign: Campaign? { root.campaigns.state.campaign(campaignID) }
    var day: CampaignDay? { campaign?.day(dayIndex) }
    var current: VoiceOver? { day?.asset?.voiceOver }

    var body: some View {
        SheetFrame(kicker: "Voice-over · \(day?.date ?? "") · \(day?.topic.title ?? "")", title: current == nil ? "Give it *a voice.*" : "Another *voice.*",
                   width: AdverbLayout.sheetWidth + 60) {
            if !hasVoice {
                NoVoiceRow(selection: selection)
            } else {
                FormRow(label: "Voice", hint: "Press play to hear one; choose it to use it.") {
                    VoicePicker(selectedPack: chosen?.packID, selectedID: chosen?.voiceID, height: AdverbLayout.voiceList.tall) { v in
                        chosen = VoiceSelection(voiceID: v.id, voiceName: v.name, packID: v.packID)
                    }
                }
                Text(current == nil
                     ? "The writer writes the lines for this day's page, timed to its scenes; the voice speaks each as its text arrives, and the captions carry what it says. Where a line needs more room, the page is rendered again at the voice's pace (no page is written again)."
                     : "This replaces the day's English voice-over and keeps its words, timed again to the new voice; confirm it again before making its languages, which are recorded again in the new voice.")
                    .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
            }
        } actions: {
            Button("Cancel") { root.stopPreview(); selection.sheet = nil }.buttonStyle(.adverbQuiet).keyboardShortcut(.cancelAction)
            Button(current == nil ? "Narrate this day" : "Narrate again") { narrate() }
                .buttonStyle(.adverbGold).keyboardShortcut(.defaultAction).disabled(!hasVoice || chosen == nil)
        }
        .onAppear {
            hasVoice = root.hasVoice
            chosen = current?.selection ?? campaign?.brief.voiceOver ?? root.settings.voiceSelection
        }
    }

    private func narrate() {
        guard let chosen else { return }
        root.stopPreview()
        root.update { $0.voiceID = chosen.voiceID; $0.voiceName = chosen.voiceName; $0.voicePack = chosen.packID }
        root.voice(slug, campaignID, day: dayIndex, selection: chosen)
        selection.sheet = nil
    }
}

/// No voice is on this Mac yet: where to get one.
struct NoVoiceRow: View {
    let selection: DeskSelection

    var body: some View {
        FormRow(label: "Voice", hint: "A voice pack is downloaded once (from Rao Studios) and speaks every voice-over on this Mac.") {
            HStack(spacing: .layer2) {
                Text("No voice is on this Mac yet.").adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                Button("Download the voice") {
                    for spec in ModelCatalog.speech { AdverbRuntimeRoot.shared.downloadModel(spec) }
                }.buttonStyle(.adverbQuiet)
            }
        }
    }
}
