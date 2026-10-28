//
//  DayPane.swift
//  Adverb
//
//  WHAT: One posting day, beside the calendar: the asset playing (portrait or landscape, captions
//        on), when to post and why, the post itself to copy, marking it posted, the accessibility
//        files, the music, the voice-over and its languages, and what in the asset is illustrative.
//  IN:   the day (from CampaignService), its run (GenerationService)
//  OUT:  AdverbRuntimeRoot (build, setStatus, editDay, revert, confirmEnglish, languages), the
//        music sheet, the voice sheet
//

import AdverbAgents
import AdverbCore
import AdverbRuntime
import SwiftUI

struct DayPane: View {
    let project: Project
    let campaign: Campaign
    let day: CampaignDay
    let run: RunProgress?
    let selection: DeskSelection

    var root: AdverbRuntimeRoot { AdverbRuntimeRoot.shared }
    var paths: CampaignPaths? { root.paths(project.slug, campaign.id) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.adverbBorder).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: .layer4) {
                    if let run, run.phase == .running { RunCard(run: run) }
                    if let problem = day.problem, run?.phase != .running {
                        AdverbCard { VStack(alignment: .leading, spacing: .layer2) {
                            Label("The last build stopped", systemImage: "exclamationmark.triangle").adverbType(.labelStrong).foregroundStyle(Color.adverbWarning)
                            Text(problem).adverbType(.caption).foregroundStyle(Color.adverbInkDim).textSelection(.enabled)
                        } }
                    }
                    if let asset = day.asset, let paths {
                        PlayerCard(asset: asset, paths: paths, selection: selection)
                    } else {
                        ScenesCard(day: day) { root.build(project.slug, campaign.id, day: day.index) }
                    }
                    WhenCard(day: day, zone: campaign.brief.timeZone)
                    PostCard(day: day) { edited in
                        Task { await root.editDay(project.slug, campaign.id, day: day.index) { d in d.caption = edited.caption; d.hashtags = edited.hashtags } }
                    }
                    StatusCard(day: day) { status, platform in
                        Task { await root.setStatus(project.slug, campaign.id, day: day.index, status, platform: platform) }
                    }
                    if let asset = day.asset, let paths {
                        AccessibilityCard(asset: asset, paths: paths, platforms: day.targets.map(\.platform))
                        MusicCard(asset: asset, busy: run?.phase == .running,
                                  choose: { selection.sheet = .music(slug: project.slug, campaign: campaign.id, day: day.index) },
                                  revert: { Task { await root.revert(project.slug, campaign.id, day: day.index) } })
                        VoiceCard(asset: asset, paths: paths, busy: run?.phase == .running,
                                  choose: { selection.sheet = .voice(slug: project.slug, campaign: campaign.id, day: day.index) },
                                  confirm: { Task { await root.confirmEnglish(project.slug, campaign.id, day: day.index) } },
                                  generate: { languages in root.languages(project.slug, campaign.id, day: day.index, languages) })
                        NotesCard(notes: asset.notes, reviewed: asset.reviewed)
                        FilesCard(asset: asset, paths: paths, stem: day.stem)
                    }
                }
                .padding(.layer4)
            }
        }
        .background(Color.adverbPage)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: .layer2) {
            VStack(alignment: .leading, spacing: .hairline) {
                Kicker(text: "\(weekday) \(day.date) · \(day.postTimeLocal)")
                Headline(text: day.topic.headline.isEmpty ? day.topic.title : day.topic.headline, role: .title).lineLimit(2)
            }
            Spacer()
            Menu {
                Button(day.asset == nil ? "Build this day" : "Rebuild this day") { root.build(project.slug, campaign.id, day: day.index) }
                if day.asset != nil {
                    Button("Cut to a song…") { selection.sheet = .music(slug: project.slug, campaign: campaign.id, day: day.index) }
                    Button(day.asset?.voiceOver == nil ? "Add a voice-over…" : "Another voice…") {
                        selection.sheet = .voice(slug: project.slug, campaign: campaign.id, day: day.index)
                    }
                }
                Divider()
                Button("Close") { selection.dayIndex = nil }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).fixedSize()
            Button { selection.dayIndex = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(Color.adverbInkDim).help("Close").keyboardShortcut(.cancelAction)
        }
        .padding(.layer4)
    }

    private var weekday: String {
        guard let date = CalendarDate.date(day.date, in: campaign.brief.zone) else { return "" }
        let f = DateFormatter(); f.timeZone = campaign.brief.zone; f.dateFormat = "EEEE"
        return f.string(from: date)
    }
}
