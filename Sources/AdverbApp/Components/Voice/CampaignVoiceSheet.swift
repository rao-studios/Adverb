//
//  CampaignVoiceSheet.swift
//  Adverb
//
//  WHAT: Voice-over for a whole campaign, after it was made: on or off for its builds from now on,
//        the voice (heard before it is chosen), and the days already built silent, narrated at once
//        if the person wants.
//  OUT:  AdverbRuntimeRoot (setCampaignVoice, voiceBuiltDays, stopPreview)
//

import AdverbCore
import AdverbRuntime
import SwiftUI

struct CampaignVoiceSheet: View {
    let slug: String
    let campaignID: UUID
    let selection: DeskSelection
    @State private var on = false
    @State private var chosen: VoiceSelection?
    @State private var model = VoiceSelection.defaultModel
    @State private var hasKey = false
    @State private var keyDraft = ""
    @State private var voiceBuilt = true
    @State private var saving = false

    var root: AdverbRuntimeRoot { AdverbRuntimeRoot.shared }
    var campaign: Campaign? { root.campaigns.state.campaign(campaignID) }
    var silent: Int { campaign?.silentBuiltDays.count ?? 0 }

    var body: some View {
        SheetFrame(kicker: "Voice-over · \(campaign?.name ?? "")", title: "Give the month *a voice.*", width: AdverbLayout.sheetWidth + 60) {
            FormRow(label: "Voice-over", hint: "Every build from now on is narrated: Claude writes each day's lines and the voice speaks them over both videos.") {
                Toggle("Narrate this campaign with an ElevenLabs voice", isOn: $on).adverbType(.label)
            }
            if on {
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
                        VoicePicker(selectedID: chosen?.voiceID, height: AdverbLayout.voiceList.regular) { v in
                            chosen = VoiceSelection(voiceID: v.id, voiceName: v.name, modelID: model)
                        }
                    }
                    if silent > 0 {
                        Toggle("Also narrate the \(silent) \(silent == 1 ? "day" : "days") already built", isOn: $voiceBuilt).adverbType(.label)
                        Text("Each is timed so its text arrives with the words; where a line needs more room the page is rendered again at the voice's pace, with no Claude build. ElevenLabs bills each character spoken.")
                            .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                    }
                }
                Text("Days already narrated keep their voice; change one with Another voice… on the day.")
                    .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
            } else if campaign?.isNarrated == true {
                Text("Turning it off keeps new builds silent. Days already narrated keep their voice-over and languages.")
                    .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
            }
        } actions: {
            Button("Cancel") { root.stopPreview(); selection.sheet = nil }.buttonStyle(.adverbQuiet).keyboardShortcut(.cancelAction)
            if saving { ProgressView().controlSize(.small) }
            Button(saveTitle) { save() }
                .buttonStyle(.adverbGold).keyboardShortcut(.defaultAction)
                .disabled(saving || (on && (!hasKey || chosen == nil)))
        }
        .onAppear {
            hasKey = root.hasVoiceKey
            on = campaign?.brief.voiceOver != nil || root.settings.voiceOverDefault
            chosen = campaign?.brief.voiceOver ?? root.settings.voiceSelection
            model = chosen?.modelID ?? root.settings.voiceModel
        }
        .onChange(of: model) { _, m in chosen?.modelID = m }
    }

    private var saveTitle: String {
        guard on else { return "Save" }
        return silent > 0 && voiceBuilt ? "Save and narrate \(silent) \(silent == 1 ? "day" : "days")" : "Save"
    }

    private func save() {
        let selection = on ? chosen : nil
        let narrateBuilt = on && voiceBuilt && silent > 0
        root.stopPreview()
        saving = true
        Task {
            if let campaign = await root.setCampaignVoice(slug, campaignID, selection) {
                if narrateBuilt { root.voiceBuiltDays(slug, campaign) }
                self.selection.sheet = nil
            }
            saving = false
        }
    }
}
