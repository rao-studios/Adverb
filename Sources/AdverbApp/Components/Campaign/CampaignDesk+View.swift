//
//  CampaignDesk+View.swift
//  Adverb
//

import AdverbAgents
import AdverbCore
import AdverbRuntime
import SwiftUI

extension CampaignDesk {
    var view: some View {
        let campaign = campaigns.state.campaign(campaignID)
        let runs = generation.state.runs(for: campaignID)
        return Group {
            if let campaign {
                VStack(spacing: 0) {
                    CampaignHeader(project: project, campaign: campaign, busy: generation.state.isBusy(campaign.id),
                                   pendingLive: $pendingLive, pendingRemove: $pendingRemove, selection: selection)
                    Rectangle().fill(Color.adverbBorder).frame(height: 1)
                    HStack(spacing: 0) {
                        if campaign.isPlanned {
                            ScrollView {
                                VStack(alignment: .leading, spacing: .layer5) {
                                    if let plan = campaign.plan { PlanSummary(plan: plan, brief: campaign.brief) }
                                    ForEach(CalendarLayout.months(for: campaign)) { month in
                                        MonthGridView(month: month, campaign: campaign, slug: project.slug,
                                                      runs: generation.state.runs, selection: selection)
                                    }
                                }
                                .padding(.layer5)
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            UnplannedView(campaign: campaign, run: runs.first { $0.kind == "Plan" }) { root.plan(project.slug, campaign.id) }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        if let index = selection.dayIndex, let day = campaign.day(index) {
                            Rectangle().fill(Color.adverbBorder).frame(width: 1)
                            DayPane(project: project, campaign: campaign, day: day,
                                    run: generation.state.dayRun(campaign.id, index),
                                    selection: selection)
                                .frame(width: AdverbLayout.dayPane)
                                .id("\(campaign.id)-\(index)")
                        }
                    }
                    if selection.showRuns, !runs.isEmpty {
                        RunsStrip(runs: runs, model: AdverbRuntimeRoot.shared.settings.model)
                    }
                }
            } else {
                EmptyState(title: "This campaign *is gone.*", message: "It was removed, or its drive is not here.")
            }
        }
        .onReceive(changed) { _ in tick &+= 1 }
        .confirmationDialog(pendingLive.map { "“\($0)” is live." } ?? "", isPresented: Binding(get: { pendingLive != nil }, set: { if !$0 { pendingLive = nil } }),
                            titleVisibility: .visible) {
            Button("Archive it and go live") {
                pendingLive = nil
                Task { _ = await root.setState(project.slug, campaignID, to: .live, archivingOthers: true) }
            }
            Button("Cancel", role: .cancel) { pendingLive = nil }
        } message: {
            Text("A project runs one live campaign at a time.")
        }
        .confirmationDialog("Remove this campaign?", isPresented: $pendingRemove, titleVisibility: .visible) {
            Button("Remove campaign and its assets", role: .destructive) {
                pendingRemove = false
                selection.campaignID = nil
                Task { await root.removeCampaign(project.slug, campaignID) }
            }
            Button("Cancel", role: .cancel) { pendingRemove = false }
        } message: {
            Text("Its folder on the drive, with every video and caption file, is deleted. The project and its context folder stay.")
        }
    }
}
