//
//  CampaignHeader.swift
//  Adverb
//
//  WHAT: The campaign's bar: its name and window, its state (draft → live → archived), whether it
//        is narrated (and the built days still silent, to narrate), and plan, build, export, reveal.
//

import AdverbCore
import AdverbRuntime
import SwiftUI

struct CampaignHeader: View {
    let project: Project
    let campaign: Campaign
    let busy: Bool
    @Binding var pendingLive: String?
    @Binding var pendingRemove: Bool
    let selection: DeskSelection

    var root: AdverbRuntimeRoot { AdverbRuntimeRoot.shared }

    var body: some View {
        WindowHeader(kicker: "\(project.name) · \(window)", title: campaign.name) {
            AdverbBadge(text: campaign.state.title, color: campaign.state == .live ? .adverbGold : .adverbInkDim, filled: campaign.state == .live)
            if let voice = campaign.brief.voiceOver {
                Button { selection.sheet = .campaignVoice(slug: project.slug, campaign: campaign.id) } label: {
                    AdverbBadge(text: "Voice · \(voice.voiceName)", color: .adverbGold)
                }
                .buttonStyle(.plain)
                .help("Every build is narrated by \(voice.voiceName). Click to change or turn it off.")
                let silent = campaign.silentBuiltDays.count
                if silent > 0 {
                    Button("Voice \(silent) built \(silent == 1 ? "day" : "days")") { root.voiceBuiltDays(project.slug, campaign) }
                        .buttonStyle(.adverbQuiet).disabled(busy)
                        .help("These days were built before the campaign was narrated: give them \(voice.voiceName)'s voice, timed to their text, without a Claude build")
                }
            }
            if busy {
                Button("Stop") { root.cancelRuns(campaign.id) }.buttonStyle(.adverbQuiet).help("Stop the runs working on this campaign")
            }
            if campaign.isPlanned {
                let missing = campaign.days.filter { $0.asset == nil }.count
                if missing > 0 {
                    Button(missing == campaign.days.count ? "Build the month" : "Build \(missing) remaining") {
                        root.buildAll(project.slug, campaign.id, onlyMissing: true)
                    }
                    .buttonStyle(.adverbGold)
                    .help("Write, render and caption every day that has no asset yet, two at a time")
                }
                stateMenu
            } else if !busy {
                Button("Plan the month") { root.plan(project.slug, campaign.id) }.buttonStyle(.adverbGold)
            }
            Menu {
                if campaign.isPlanned {
                    Button("Re-plan the month…") { root.plan(project.slug, campaign.id) }
                    Button("Rebuild every day") { root.buildAll(project.slug, campaign.id, onlyMissing: false) }
                    let confirmed = campaign.days.filter { $0.asset?.voiceOver?.isConfirmed == true }.count
                    if confirmed > 0 {
                        Button("Voice \(confirmed) confirmed \(confirmed == 1 ? "day" : "days") in your languages") { root.voiceAllConfirmed(project.slug, campaign.id) }
                            .disabled(root.settings.voiceLanguages.isEmpty)
                    }
                    Divider()
                    Button("Export captions, CSV and calendar") {
                        Task { let urls = await root.export(project.slug, campaign.id); if !urls.isEmpty { Panels.reveal(urls) } }
                    }
                }
                Button(campaign.isNarrated ? "Voice-over…" : "Turn on voice-over…") {
                    selection.sheet = .campaignVoice(slug: project.slug, campaign: campaign.id)
                }
                Divider()
                Button("Reveal in Finder") { if let p = root.paths(project.slug, campaign.id) { Panels.reveal([p.campaignFile]) } }
                Button("Open the run logs") { if let p = root.paths(project.slug, campaign.id) { Panels.reveal([p.logs]) } }
                Button(selection.showRuns ? "Hide runs" : "Show runs") { selection.showRuns.toggle() }
                Divider()
                Button("Remove campaign…", role: .destructive) { pendingRemove = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    @ViewBuilder private var stateMenu: some View {
        switch campaign.state {
        case .draft:
            Button("Go live") {
                if let other = AdverbRuntimeRoot.shared.campaigns.state.campaigns(project.slug).first(where: { $0.state == .live && $0.id != campaign.id }) {
                    pendingLive = other.name
                } else {
                    Task { _ = await root.setState(project.slug, campaign.id, to: .live) }
                }
            }
            .buttonStyle(.adverb)
            .help("Mark this the month being posted, and export its calendar and captions")
        case .live:
            Button("Archive") { Task { _ = await root.setState(project.slug, campaign.id, to: .archived) } }.buttonStyle(.adverbQuiet)
        case .archived:
            Button("Back to draft") { Task { _ = await root.setState(project.slug, campaign.id, to: .draft) } }.buttonStyle(.adverbQuiet)
        }
    }

    private var window: String {
        let dates = campaign.brief.windowDates
        return "\(dates.first ?? "") – \(dates.last ?? "")"
    }
}
