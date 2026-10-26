//
//  ProjectSection.swift
//  Adverb
//
//  WHAT: One project in the sidebar and its campaigns.
//

import AdverbCore
import AdverbRuntime
import SwiftUI

struct ProjectSection: View {
    let project: Project
    let campaigns: [Campaign]
    let busy: (UUID) -> Bool
    let selection: DeskSelection
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: .hairline) {
            Button { selection.select(project: project.slug) } label: {
                HStack(spacing: .layer2) {
                    Circle().fill(Color.adverbLabel(project.label.rawValue)).frame(width: 8, height: 8)
                    Text(project.name).adverbType(.heading).lineLimit(1)
                    Spacer()
                    if hovering {
                        Button { selection.sheet = .newCampaign(project.slug) } label: { Image(systemName: "plus") }
                            .buttonStyle(.plain).foregroundStyle(Color.adverbInkDim).help("New campaign")
                    }
                }
                .padding(.horizontal, .layer2)
                .padding(.vertical, .snug)
                .background(RoundedRectangle(cornerRadius: AdverbRadius.control, style: .continuous)
                    .fill(selection.projectSlug == project.slug && selection.campaignID == nil ? Color.adverbFillSelected : Color.clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .contextMenu {
                Button("New Campaign…") { selection.sheet = .newCampaign(project.slug) }
                Button("Manage Project…") { selection.sheet = .manageProject(project.slug) }
                Divider()
                Button("Reveal Adverb Folder") { if let url = AdverbRuntimeRoot.shared.projectFolder(project) { Panels.reveal([url]) } }
                Button("Reveal Context Folder") { Panels.reveal([project.contextURL]) }
            }
            ForEach(campaigns) { campaign in
                CampaignRow(campaign: campaign, busy: busy(campaign.id),
                            selected: selection.campaignID == campaign.id) {
                    selection.select(campaign: campaign.id, in: project.slug)
                }
            }
        }
    }
}

struct CampaignRow: View {
    let campaign: Campaign
    let busy: Bool
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: .layer2) {
                StatusDot(color: color, hollow: campaign.state == .draft && !campaign.isPlanned, pulsing: busy)
                VStack(alignment: .leading, spacing: .hairline) {
                    Text(campaign.name).adverbType(.label).lineLimit(1)
                    Text(subtitle).adverbType(.fine).foregroundStyle(Color.adverbInkDim).lineLimit(1)
                }
                Spacer(minLength: 0)
                if campaign.state == .live { AdverbBadge(text: "Live", color: .adverbGold, filled: true) }
            }
            .padding(.leading, .layer5)
            .padding(.trailing, .layer2)
            .padding(.vertical, .snug)
            .background(RoundedRectangle(cornerRadius: AdverbRadius.control, style: .continuous)
                .fill(selected ? Color.adverbFillSelected : (hovering ? Color.adverbFillTrace : Color.clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var color: Color {
        switch campaign.state {
        case .live: .adverbGold
        case .draft: .adverbInkMuted
        case .archived: .adverbInkFaint
        }
    }

    private var subtitle: String {
        guard campaign.isPlanned else { return "\(campaign.state.title) · not planned" }
        return "\(campaign.state.title) · \(campaign.builtCount)/\(campaign.days.count) built" + (campaign.postedCount > 0 ? " · \(campaign.postedCount) posted" : "")
    }
}
