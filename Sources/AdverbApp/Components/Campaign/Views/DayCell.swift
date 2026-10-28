//
//  DayCell.swift
//  Adverb
//
//  WHAT: A date in the calendar. Outside the window: a faint number. A day without a post: blank.
//        A posting day: the asset's still (or its title, before it is built), the platform, the
//        time, the status, a ♪ when it has music, a spinner while a run works on it, a mark when
//        its last build stopped.
//

import AdverbAgents
import AdverbCore
import AdverbRuntime
import SwiftUI

struct DayCell: View {
    let cell: CalendarCell
    let day: CampaignDay?
    let run: RunProgress?
    let root: AdverbCellRoot
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: AdverbRadius.cell, style: .continuous)
                    .fill(day == nil ? Color.adverbFillTrace : Color.adverbPearl)
                if let day { content(day) }
                Text(cell.dayOfMonth.map(String.init) ?? "")
                    .adverbType(.captionStrong)
                    .foregroundStyle(cell.inWindow ? (day == nil ? Color.adverbInkMuted : Color.adverbInk) : Color.adverbInkFaint)
                    .padding(.snug)
                    .background(day?.asset != nil ? Capsule().fill(Color.adverbPearl.opacity(0.85)) : nil)
                    .padding(.layer1)
            }
            .frame(height: AdverbLayout.calendarCellHeight)
            .clipShape(RoundedRectangle(cornerRadius: AdverbRadius.cell, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AdverbRadius.cell, style: .continuous)
                .strokeBorder(selected ? Color.adverbGold : (hovering && day != nil ? Color.adverbInkFaint : Color.adverbBorder), lineWidth: selected ? 2 : 1))
            .shadow(color: day == nil ? .clear : Color.adverbShadow, radius: selected ? 8 : 3, y: 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(day == nil)
        .onHover { hovering = $0 }
        .help(day.map { "\($0.topic.title) · \($0.postTimeLocal) · \($0.targets.map(\.platform.title).joined(separator: ", "))" } ?? "")
    }

    @ViewBuilder private func content(_ day: CampaignDay) -> some View {
        let orientation = day.targets.first?.orientation ?? .portrait
        ZStack(alignment: .bottomLeading) {
            if let still = thumbnail(day, orientation) {
                // An overlay on clear, so the filled image takes the cell's size and never sets it.
                Color.clear.overlay(alignment: .top) { Image(nsImage: still).resizable().aspectRatio(contentMode: .fill) }.clipped()
                LinearGradient(colors: [.clear, Color.adverbInk.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            } else {
                // Under the date, clear of the footer row.
                Text(day.topic.title).adverbType(.caption).foregroundStyle(Color.adverbInkSoft).lineLimit(3)
                    .padding(.horizontal, .layer2)
                    .padding(.top, .layer6)
                    .padding(.bottom, .layer5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            HStack(spacing: .layer1) {
                Image(systemName: day.primary.symbol).font(.adverbGlyph(AdverbGlyph.small, weight: .semibold))
                Text(day.postTimeLocal).adverbType(.badge).lineLimit(1).fixedSize()
                Spacer(minLength: 0)
                if day.asset?.music != nil { Text("♪").adverbType(.captionStrong) }
                if let vo = day.asset?.voiceOver {
                    Image(systemName: "waveform").font(.adverbGlyph(AdverbGlyph.small, weight: .semibold))
                    if !vo.freshLanguages.isEmpty { Text("+\(vo.freshLanguages.count)").adverbType(.badge).fixedSize() }
                }
                if day.problem != nil, run == nil { Image(systemName: "exclamationmark.triangle.fill").font(.adverbGlyph(AdverbGlyph.small)).foregroundStyle(Color.adverbWarning) }
                statusMark(day)
            }
            .foregroundStyle(day.asset != nil ? Color.adverbPearl : Color.adverbInkDim)
            .padding(.snug)
        }
        .overlay {
            if let run {
                ZStack {
                    Color.adverbPage.opacity(0.75)
                    VStack(spacing: .layer1) {
                        ProgressView(value: run.progress).progressViewStyle(.circular).controlSize(.small)
                        Text(run.step).adverbType(.fine).foregroundStyle(Color.adverbInkDim).lineLimit(1)
                    }
                    .padding(.layer1)
                }
            }
        }
    }

    @ViewBuilder private func statusMark(_ day: CampaignDay) -> some View {
        switch day.status {
        case .posted: Image(systemName: "checkmark.circle.fill").font(.adverbGlyph(AdverbGlyph.caption)).foregroundStyle(Color.adverbGoldHi)
        case .skipped: Image(systemName: "minus.circle").font(.adverbGlyph(AdverbGlyph.caption))
        case .rendered: StatusDot(color: .adverbGoldHi)
        case .planned: StatusDot(color: .adverbInkMuted, hollow: true)
        }
    }

    private func thumbnail(_ day: CampaignDay, _ orientation: Orientation) -> NSImage? {
        guard let asset = day.asset, let paths = AdverbRuntimeRoot.shared.paths(root.slug, root.campaignID) else { return nil }
        // The first still (18 %): the headline is up and the visual has arrived.
        let still = asset.stills(orientation).first
        return still.flatMap { ThumbnailCache.image(paths.url($0.path)) }
    }
}
