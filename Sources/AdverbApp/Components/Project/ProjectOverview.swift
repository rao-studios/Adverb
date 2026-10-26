//
//  ProjectOverview.swift
//  Adverb
//
//  WHAT: A project at a glance: what it is about (its context folder), how its assets end, its
//        campaigns, and a new one.
//

import AdverbCore
import AdverbRuntime
import SwiftUI

struct ProjectOverview: View {
    let project: Project
    let campaigns: [Campaign]
    let selection: DeskSelection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .layer5) {
                WindowHeader(kicker: project.app.kicker, title: project.name) {
                    Button("Manage…") { selection.sheet = .manageProject(project.slug) }.buttonStyle(.adverbQuiet)
                    Button("New campaign") { selection.sheet = .newCampaign(project.slug) }.buttonStyle(.adverb)
                }
                .padding(.horizontal, -CGFloat.layer5)
                HStack(alignment: .top, spacing: .layer4) {
                    AdverbCard {
                        VStack(alignment: .leading, spacing: .layer2) {
                            SectionLabel("Context")
                            FieldRow(label: "Reads", value: project.contextPath)
                            FieldRow(label: "Keeps assets in", value: AdverbRuntimeRoot.shared.projectFolder(project)?.path ?? "—")
                            if !project.tags.isEmpty {
                                FlowLayout { ForEach(project.tags, id: \.self) { AdverbChip(label: $0) } }
                            }
                            HStack {
                                Button("Reveal context") { Panels.reveal([project.contextURL]) }.buttonStyle(.adverbLink)
                                Button("Reveal assets") { if let u = AdverbRuntimeRoot.shared.projectFolder(project) { Panels.reveal([u]) } }.buttonStyle(.adverbLink)
                            }
                        }
                    }
                    AdverbCard {
                        VStack(alignment: .leading, spacing: .layer2) {
                            SectionLabel("Every asset ends on")
                            Headline(text: project.app.endTitle, role: .title)
                            Text(project.app.endSub).adverbType(.identifier).foregroundStyle(Color.adverbInkDim)
                            Text(project.app.endSub2).adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                            if project.app.comingSoon { AdverbBadge(text: "Coming soon", color: .adverbGold) }
                        }
                    }
                }
                SectionLabel("Campaigns")
                if campaigns.isEmpty {
                    AdverbCard {
                        VStack(alignment: .leading, spacing: .layer2) {
                            Headline(text: "No month *planned yet.*", role: .title)
                            Text("A campaign is a month of posts: one motion asset a posting day, each in portrait and landscape, with its caption, hashtags, captions file and the time to post it.")
                                .adverbType(.readingSmall).foregroundStyle(Color.adverbInkDim)
                            Button("Plan a month") { selection.sheet = .newCampaign(project.slug) }.buttonStyle(.adverbGold)
                        }
                    }
                } else {
                    VStack(spacing: .layer2) {
                        ForEach(campaigns) { campaign in
                            Button { selection.select(campaign: campaign.id, in: project.slug) } label: {
                                RowCard {
                                    HStack(spacing: .layer3) {
                                        VStack(alignment: .leading, spacing: .hairline) {
                                            Text(campaign.name).adverbType(.heading)
                                            Text("\(campaign.brief.windowDates.first ?? "") – \(campaign.brief.windowDates.last ?? "") · \(campaign.brief.platforms.map(\.shortTitle).joined(separator: ", "))")
                                                .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                                        }
                                        Spacer()
                                        AdverbStat(value: "\(campaign.builtCount)/\(campaign.days.count)", label: "built")
                                        AdverbStat(value: "\(campaign.postedCount)", label: "posted")
                                        AdverbBadge(text: campaign.state.title, color: campaign.state == .live ? .adverbGold : .adverbInkDim, filled: campaign.state == .live)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.layer5)
            .padding(.top, .layer4)
        }
    }
}
