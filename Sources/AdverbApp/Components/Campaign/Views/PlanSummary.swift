//
//  PlanSummary.swift
//  Adverb
//
//  WHAT: What the planner said about the month: the summary, the arc, what it read, what it was
//        careful about. Folds away.
//

import AdverbAgents
import AdverbCore
import SwiftUI

struct PlanSummary: View {
    let plan: CampaignPlan
    let brief: CampaignBrief
    @AppStorage("plan.summary.open") private var open = true

    var body: some View {
        AdverbCard(padding: .layer4) {
            VStack(alignment: .leading, spacing: .layer2) {
                Button { open.toggle() } label: {
                    HStack {
                        SectionLabel("The month")
                        Spacer()
                        Text("\(brief.postDates.count) posts · \(brief.timeZone) · \(plan.model)").adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                        Image(systemName: open ? "chevron.up" : "chevron.down").font(.adverbGlyph(AdverbGlyph.caption)).foregroundStyle(Color.adverbInkMuted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if open {
                    Text(plan.summary).adverbType(.reading).foregroundStyle(Color.adverbInkSoft).textSelection(.enabled)
                    FlowLayout(spacing: .snug) {
                        ForEach(Array(plan.arc.enumerated()), id: \.offset) { i, phase in
                            AdverbChip(label: phase, isOn: false, swatch: i == plan.arc.count - 1)
                        }
                    }
                    if !plan.cautions.isEmpty {
                        VStack(alignment: .leading, spacing: .hairline) {
                            SectionLabel("Careful about")
                            ForEach(plan.cautions, id: \.self) { Text("· \($0)").adverbType(.caption).foregroundStyle(Color.adverbInkDim) }
                        }
                    }
                    if !plan.sources.isEmpty {
                        Text("Read: " + plan.sources.joined(separator: " · ")).adverbType(.fine).foregroundStyle(Color.adverbInkMuted).lineLimit(2)
                    }
                }
            }
        }
    }
}

struct UnplannedView: View {
    let campaign: Campaign
    let run: RunProgress?
    let plan: () -> Void

    var body: some View {
        VStack(spacing: .layer4) {
            if let run, run.phase == .running {
                AdverbMark(size: 48)
                Headline(text: "Planning *the month.*", role: .title)
                Text(run.step).adverbType(.label).foregroundStyle(Color.adverbInkDim)
                Text(run.activity.isEmpty ? "Reading the project and the brief…" : String(run.activity.suffix(240)))
                    .adverbType(.readingSmall).foregroundStyle(Color.adverbInkMuted).multilineTextAlignment(.center)
                    .frame(maxWidth: 460, minHeight: 60, alignment: .top)
            } else {
                EmptyState(title: "Not planned *yet.*",
                           message: "\(campaign.brief.postDates.count) posting dates from \(campaign.brief.windowDates.first ?? ""). Claude reads the project and plans one asset a day: what it shows, its caption, where it goes and when.")
                    .frame(maxHeight: 280)
                if let run, run.phase == .failed, let message = run.message {
                    Text(message).adverbType(.caption).foregroundStyle(Color.adverbError).textSelection(.enabled).frame(maxWidth: 520)
                }
                Button("Plan the month", action: plan).buttonStyle(.adverbGold).keyboardShortcut(.defaultAction)
            }
        }
        .padding(.layer6)
    }
}
