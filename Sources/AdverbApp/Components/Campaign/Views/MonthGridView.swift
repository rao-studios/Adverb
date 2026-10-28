//
//  MonthGridView.swift
//  Adverb
//
//  WHAT: One month of the campaign as a calendar: weekday heads, then a cell per date; posting days
//        carry their asset's thumbnail, platform, time and status.
//

import AdverbAgents
import AdverbCore
import SwiftUI

struct MonthGridView: View {
    let month: MonthGrid
    let campaign: Campaign
    let slug: String
    let runs: [String: RunProgress]
    let selection: DeskSelection

    private let columns = Array(repeating: GridItem(.flexible(), spacing: .layer2), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: .layer2) {
            Headline(text: month.title, role: .title)
            LazyVGrid(columns: columns, spacing: .layer2) {
                ForEach(Weekday.all, id: \.rawValue) { day in
                    Text(day.short.uppercased()).adverbType(.badge).foregroundStyle(Color.adverbInkMuted).frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(month.cells) { cell in
                    if cell.date == nil {
                        Color.clear.frame(height: AdverbLayout.calendarCellHeight)
                    } else {
                        let day = cell.dayIndex.flatMap { campaign.day($0) }
                        let run = day.flatMap { RunKey.dayRun(in: runs, campaign.id, $0.index) }
                        DayCell(cell: cell, day: day, run: run?.phase == .running ? run : nil,
                                root: AdverbCellRoot(slug: slug, campaignID: campaign.id),
                                selected: day != nil && selection.dayIndex == day?.index) {
                            if let day { selection.dayIndex = selection.dayIndex == day.index ? nil : day.index }
                        }
                    }
                }
            }
        }
    }
}

/// Where a cell finds its files.
struct AdverbCellRoot { let slug: String; let campaignID: UUID }
