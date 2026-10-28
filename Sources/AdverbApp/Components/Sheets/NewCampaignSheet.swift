//
//  NewCampaignSheet.swift
//  Adverb
//
//  WHAT: The brief for a month: when it starts and how long, where the audience is, which platforms,
//        which days to post, how long the assets run, what to feature and why, and whether an
//        ElevenLabs voice narrates each asset (the key asked for here when there is none). Creates a
//        draft and starts planning it.
//

import AdverbCore
import AdverbRuntime
import SwiftUI

struct NewCampaignSheet: View {
    let slug: String
    let selection: DeskSelection
    @State private var name = ""
    @State private var start = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var length = 30
    @State private var timeZone = TimeZone.current.identifier
    @State private var audience = ""
    @State private var platforms: Set<Platform> = [.instagramReels, .tiktok, .linkedin, .x]
    @State private var postDays: Set<Weekday> = Set(Weekday.all)
    @State private var durations: Set<Int> = [15, 30]
    @State private var apps = ""
    @State private var goals = ""
    @State private var notes = ""
    @State private var creating = false
    @State private var voiceOn = false
    @State private var voice: VoiceSelection?
    @State private var voiceModel = VoiceSelection.defaultModel
    @State private var hasVoiceKey = false
    @State private var voiceKeyDraft = ""
    @State private var pickingVoice = false

    static let zones = ["America/New_York", "America/Chicago", "America/Denver", "America/Los_Angeles", "Europe/London", "Europe/Paris",
                        "Europe/Berlin", "Asia/Kolkata", "Asia/Singapore", "Asia/Tokyo", "Australia/Sydney"]

    var project: Project? { AdverbRuntimeRoot.shared.projects.state.project(slug) }

    var brief: CampaignBrief {
        let zone = TimeZone(identifier: timeZone) ?? .current
        return CampaignBrief(startDate: CalendarDate.string(start, in: zone), lengthDays: length, timeZone: timeZone,
                             audienceRegion: audience, platforms: Platform.allCases.filter(platforms.contains), postDays: Weekday.all.filter(postDays.contains),
                             durations: [15, 30].filter(durations.contains), apps: apps.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                             goals: goals, notes: notes, voiceOver: voiceOn ? voice : nil)
    }

    var root: AdverbRuntimeRoot { AdverbRuntimeRoot.shared }

    var body: some View {
        SheetFrame(kicker: "New campaign · \(project?.name ?? slug)", title: "A month of *motion.*", width: AdverbLayout.sheetWidth + 60) {
            FormRow(label: "Name") { AdverbTextField(placeholder: "November", text: $name) }
            HStack(alignment: .top, spacing: .layer4) {
                FormRow(label: "Starts") { DatePicker("", selection: $start, displayedComponents: .date).labelsHidden().datePickerStyle(.field) }
                FormRow(label: "Days") { Stepper("\(length) days", value: $length, in: 7...62).adverbType(.label) }
                FormRow(label: "Time zone") {
                    Picker("", selection: $timeZone) {
                        ForEach(Array(Set(Self.zones + [TimeZone.current.identifier])).sorted(), id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().fixedSize()
                }
            }
            FormRow(label: "Audience", hint: "Who the posts are for and where: the planner chooses times for them.") {
                AdverbTextField(placeholder: "Mac readers and researchers in the US, weekday mornings", text: $audience)
            }
            FormRow(label: "Platforms", hint: "Reels, TikTok and Shorts get the portrait version; X, LinkedIn, Threads and Bluesky the landscape one.") {
                FlowLayout(spacing: .snug) {
                    ForEach(Platform.allCases) { p in
                        Button { toggle(&platforms, p) } label: { AdverbChip(label: p.shortTitle, systemImage: p.symbol, isOn: platforms.contains(p)) }.buttonStyle(.plain)
                    }
                }
            }
            HStack(alignment: .top, spacing: .layer4) {
                FormRow(label: "Post on") {
                    HStack(spacing: .layer1) {
                        ForEach(Weekday.all, id: \.self) { d in
                            Button { toggle(&postDays, d) } label: { AdverbChip(label: String(d.short.prefix(2)), isOn: postDays.contains(d)) }.buttonStyle(.plain)
                        }
                    }
                }
                FormRow(label: "Lengths") {
                    HStack(spacing: .layer1) {
                        ForEach([15, 30], id: \.self) { s in
                            Button { toggle(&durations, s) } label: { AdverbChip(label: "\(s) s", isOn: durations.contains(s)) }.buttonStyle(.plain)
                        }
                    }
                }
            }
            voiceRow
            Text("\(brief.postDates.count) posts, \(brief.windowDates.first ?? "") to \(brief.windowDates.last ?? ""). Each is a portrait and a landscape video with captions, a caption to post, hashtags, alt text and its time.\(voiceOn && voice != nil ? " Each is narrated by \(voice!.voiceName)." : "")")
                .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
            FormRow(label: "Feature", hint: "Comma separated; empty features the project's own app.") {
                AdverbTextField(placeholder: project?.app.name ?? "Ambient", text: $apps)
            }
            FormRow(label: "Goals") { AdverbTextArea(text: $goals, minHeight: 54) }
            FormRow(label: "Notes for the planner") { AdverbTextArea(text: $notes, minHeight: 54) }
        } actions: {
            Button("Cancel") { root.stopPreview(); selection.sheet = nil }.buttonStyle(.adverbQuiet).keyboardShortcut(.cancelAction)
            if creating { ProgressView().controlSize(.small) }
            Button("Create draft") { create(plan: false) }.buttonStyle(.adverbQuiet).disabled(!valid || creating)
            Button("Create and plan") { create(plan: true) }.buttonStyle(.adverbGold).keyboardShortcut(.defaultAction).disabled(!valid || creating)
        }
        .onAppear {
            if name.isEmpty {
                let f = DateFormatter(); f.dateFormat = "MMMM"
                name = f.string(from: start)
            }
            let s = root.settings
            voiceOn = s.voiceOverDefault
            voice = s.voiceSelection
            voiceModel = s.voiceModel
            hasVoiceKey = root.hasVoiceKey
        }
        .onChange(of: voiceModel) { _, model in voice?.modelID = model }
    }

    /// Voice-over: on or off, the key when there is none, the voice (heard before it is chosen).
    @ViewBuilder private var voiceRow: some View {
        FormRow(label: "Voice-over", hint: "Claude writes a short narration for each asset and an ElevenLabs voice speaks it over both videos. Other languages come after you confirm a day's English.") {
            Toggle("Narrate every asset with an ElevenLabs voice", isOn: $voiceOn).adverbType(.label)
            if voiceOn {
                if !hasVoiceKey {
                    VoiceKeyField(draft: $voiceKeyDraft) { hasVoiceKey = root.hasVoiceKey }
                } else {
                    HStack(spacing: .layer2) {
                        if let voice {
                            Image(systemName: "waveform").font(.adverbGlyph(AdverbGlyph.body)).foregroundStyle(Color.adverbGold)
                            VStack(alignment: .leading, spacing: .hairline) {
                                Text(voice.voiceName).adverbType(.labelStrong)
                                Text(AdverbSettings.voiceModels.first { $0.id == voice.modelID }?.title ?? voice.modelID)
                                    .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                            }
                            Button("Hear it") { Task { await root.previewVoice(voice.voiceID) } }.buttonStyle(.adverbLink)
                        } else {
                            Text("Choose a voice below.").adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                        }
                        Spacer()
                        if voice != nil { Button(pickingVoice ? "Done" : "Change…") { pickingVoice.toggle() }.buttonStyle(.adverbLink) }
                    }
                    if pickingVoice || voice == nil {
                        Picker("Model", selection: $voiceModel) { ForEach(AdverbSettings.voiceModels, id: \.id) { Text($0.title).tag($0.id) } }
                            .adverbType(.label)
                        VoicePicker(selectedID: voice?.voiceID, height: AdverbLayout.voiceList.compact) { v in
                            voice = VoiceSelection(voiceID: v.id, voiceName: v.name, modelID: voiceModel)
                            pickingVoice = false
                        }
                    }
                }
            }
        }
    }

    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !platforms.isEmpty && !postDays.isEmpty && !durations.isEmpty && !brief.postDates.isEmpty
            && (!voiceOn || (hasVoiceKey && voice != nil))
    }

    private func toggle<T: Hashable>(_ set: inout Set<T>, _ value: T) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    private func create(plan: Bool) {
        creating = true
        let brief = self.brief
        root.stopPreview()
        // The choice is the next campaign's default.
        let on = voiceOn, chosen = voice
        root.update { s in
            s.voiceOverDefault = on
            if let chosen { s.voiceID = chosen.voiceID; s.voiceName = chosen.voiceName; s.voiceModel = chosen.modelID }
        }
        Task {
            if let campaign = await AdverbRuntimeRoot.shared.createCampaign(slug, name: name.trimmingCharacters(in: .whitespaces), brief: brief, planNow: plan) {
                selection.select(campaign: campaign.id, in: slug)
                selection.sheet = nil
            }
            creating = false
        }
    }
}
