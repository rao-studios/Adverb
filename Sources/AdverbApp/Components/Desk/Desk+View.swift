//
//  Desk+View.swift
//  Adverb
//

import AdverbCore
import AdverbRuntime
import SwiftUI

extension Desk {
    var view: some View {
        let project = projects.state.project(selection.projectSlug) ?? (selection.projectSlug == nil ? projects.state.projects.first : nil)
        let campaign = campaigns.state.campaign(selection.campaignID)
        return VStack(spacing: 0) {
            Group {
                if let project, let campaign {
                    CampaignDesk(project: project, campaignID: campaign.id, selection: selection)
                } else if let project {
                    ProjectOverview(project: project, campaigns: campaigns.state.campaigns(project.slug), selection: selection)
                } else {
                    EmptyState(title: "Choose a *project.*", message: "Projects are on the left. Add one with the + to start a campaign.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let problem = config.state.problem {
                NoticeBar(text: problem, tint: .adverbError) { AdverbRuntimeRoot.shared.config.set(.problem(nil)) }
            } else if let notice = config.state.notice {
                NoticeBar(text: notice, tint: .adverbInkDim) { AdverbRuntimeRoot.shared.config.set(.notice(nil)) }
            }
        }
        .background(Color.adverbPaper)
        .onReceive(changed) { _ in tick &+= 1 }
        .onAppear {
            if selection.projectSlug == nil, let first = projects.state.projects.first { selection.select(project: first.slug) }
        }
    }
}
