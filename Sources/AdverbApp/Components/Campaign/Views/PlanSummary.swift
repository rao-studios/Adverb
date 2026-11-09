//
//  PlanSummary.swift
//  Adverb
//
//  WHAT: What the planner said about the month: the summary, the arc (one wrapping row a phase),
//        what it was careful about and what it read. The card folds away, and so does each section.
//

import AdverbAgents
import AdverbCore
import SwiftUI

struct PlanSummary: View {
    let plan: CampaignPlan
    let brief: CampaignBrief
    @AppStorage("plan.summary.open") private var open = true
    @AppStorage("plan.arc.open") private var arcOpen = true
    @AppStorage("plan.cautions.open") private var cautionsOpen = false
    @AppStorage("plan.sources.open") private var sourcesOpen = false

    /// One phase of the arc as the planner writes it: "Premise (Nov 4–7): what Ambient is. …".
    struct Phase: Equatable {
        var title: String
        var when: String?
        var detail: String

        init(_ text: String) {
            let text = text.trimmingCharacters(in: .whitespaces)
            guard let colon = text.firstIndex(of: ":"), text.distance(from: text.startIndex, to: colon) <= 48 else {
                self.init(title: text, when: nil, detail: ""); return
            }
            var head = String(text[..<colon]).trimmingCharacters(in: .whitespaces)
            var when: String?
            if head.hasSuffix(")"), let open = head.lastIndex(of: "(") {
                when = String(head[head.index(after: open)..<head.index(before: head.endIndex)]).trimmingCharacters(in: .whitespaces)
                head = String(head[..<open]).trimmingCharacters(in: .whitespaces)
            }
            let rest = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            self.init(title: head, when: when?.isEmpty == true ? nil : when, detail: rest.prefix(1).uppercased() + rest.dropFirst())
        }

        init(title: String, when: String?, detail: String) { self.title = title; self.when = when; self.detail = detail }
    }

    var body: some View {
        AdverbCard(padding: .layer4) {
            VStack(alignment: .leading, spacing: .layer3) {
                Button { open.toggle() } label: {
                    HStack(spacing: .layer2) {
                        SectionLabel("The month")
                        Spacer(minLength: .layer2)
                        Text("\(brief.postDates.count) posts · \(brief.timeZone) · \(plan.model)").adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                            .lineLimit(1).truncationMode(.middle)
                        Chevron(open: open)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if open {
                    Text(plan.summary).adverbType(.reading).foregroundStyle(Color.adverbInkSoft).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if !plan.arc.isEmpty {
                        Fold(title: "The arc", count: "\(plan.arc.count) phases", open: $arcOpen) {
                            ForEach(Array(plan.arc.enumerated()), id: \.offset) { i, text in
                                PhaseRow(phase: Phase(text), finale: i == plan.arc.count - 1)
                            }
                        }
                    }
                    if !plan.cautions.isEmpty {
                        Fold(title: "Careful about", count: "\(plan.cautions.count)", open: $cautionsOpen) {
                            ForEach(plan.cautions, id: \.self) { Bullet(text: $0) }
                        }
                    }
                    if !plan.sources.isEmpty {
                        Fold(title: "Read", count: "\(plan.sources.count) sources", open: $sourcesOpen) {
                            ForEach(plan.sources, id: \.self) { Bullet(text: $0) }
                        }
                    }
                }
            }
        }
    }
}

/// A section of the summary that opens and closes under its label.
private struct Fold<Content: View>: View {
    let title: String
    let count: String
    @Binding var open: Bool
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: .layer2) {
            Rectangle().fill(Color.adverbBorder).frame(height: 1)
            Button { open.toggle() } label: {
                HStack(spacing: .layer2) {
                    Chevron(open: open, opened: "chevron.down", closed: "chevron.right")
                    SectionLabel(title)
                    Text(count).adverbType(.caption).foregroundStyle(Color.adverbInkMuted)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title), \(count)")
            .accessibilityValue(open ? "Open" : "Closed")
            if open {
                VStack(alignment: .leading, spacing: .layer2) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// A phase of the arc: when, in a column; what, wrapping beside it.
private struct PhaseRow: View {
    let phase: PlanSummary.Phase
    let finale: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: .layer3) {
            Text((phase.when ?? "").uppercased()).adverbType(.badge).foregroundStyle(Color.adverbInkMuted)
                .frame(width: AdverbLayout.dateColumn, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: .hairline) {
                HStack(spacing: .snug) {
                    Text(phase.title).adverbType(.labelStrong).foregroundStyle(Color.adverbInk)
                    if finale { RoundedRectangle(cornerRadius: AdverbRadius.hairline).fill(Color.adverbBrush).frame(width: 14, height: 7) }
                }
                if !phase.detail.isEmpty {
                    Text(phase.detail).adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .textSelection(.enabled)
    }
}

private struct Bullet: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: .snug) {
            Text("·").adverbType(.caption).foregroundStyle(Color.adverbInkMuted)
            Text(text).adverbType(.caption).foregroundStyle(Color.adverbInkDim).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The card's chevron points up when open; a section's points right when closed.
private struct Chevron: View {
    let open: Bool
    var opened = "chevron.up"
    var closed = "chevron.down"

    var body: some View {
        Image(systemName: open ? opened : closed)
            .font(.adverbGlyph(AdverbGlyph.caption)).foregroundStyle(Color.adverbInkMuted)
            .frame(width: AdverbGlyph.body)
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
                           message: "\(campaign.brief.postDates.count) posting dates from \(campaign.brief.windowDates.first ?? ""). The writer on this Mac reads the project and plans one asset a day: what it shows, its caption, where it goes and when.")
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
