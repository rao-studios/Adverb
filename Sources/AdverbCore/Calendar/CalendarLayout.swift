//
//  CalendarLayout.swift
//  AdverbCore
//
//  WHAT: A campaign's days laid out as month grids (weeks of seven, Sunday first, blanks before
//        the first and after the last), for the calendar view. Pure, so the grid math is tested.
//

import Foundation

public struct CalendarCell: Sendable, Equatable, Identifiable, Hashable {
    /// "yyyy-MM-dd", nil for a blank.
    public var date: String?
    public var dayOfMonth: Int?
    public var dayIndex: Int?
    public var inWindow: Bool
    public var id: String

    public init(date: String?, dayOfMonth: Int?, dayIndex: Int?, inWindow: Bool, id: String) {
        self.date = date; self.dayOfMonth = dayOfMonth; self.dayIndex = dayIndex; self.inWindow = inWindow; self.id = id
    }
}

public struct MonthGrid: Sendable, Equatable, Identifiable, Hashable {
    /// "2026-11"
    public var month: String
    public var title: String
    public var cells: [CalendarCell]
    public var id: String { month }
}

public enum CalendarLayout {
    public static func months(for campaign: Campaign) -> [MonthGrid] {
        let brief = campaign.brief
        let zone = brief.zone
        var calendar = brief.calendar
        calendar.firstWeekday = 1
        let window = brief.windowDates
        guard let first = window.first.flatMap({ CalendarDate.date($0, in: zone) }),
              let last = window.last.flatMap({ CalendarDate.date($0, in: zone) }) else { return [] }
        let byDate = Dictionary(campaign.days.map { ($0.date, $0.index) }, uniquingKeysWith: { a, _ in a })
        let inWindow = Set(window)
        let title = DateFormatter()
        title.calendar = calendar; title.timeZone = zone; title.locale = Locale(identifier: "en_US_POSIX"); title.dateFormat = "MMMM yyyy"
        var grids: [MonthGrid] = []
        var monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: first))!
        while monthStart <= last {
            let range = calendar.range(of: .day, in: .month, for: monthStart)!
            let lead = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
            let key = String(CalendarDate.string(monthStart, in: zone).prefix(7))
            var cells = (0..<lead).map { CalendarCell(date: nil, dayOfMonth: nil, dayIndex: nil, inWindow: false, id: "\(key)-lead-\($0)") }
            for day in range {
                let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart)!
                let s = CalendarDate.string(date, in: zone)
                cells.append(CalendarCell(date: s, dayOfMonth: day, dayIndex: byDate[s], inWindow: inWindow.contains(s), id: s))
            }
            let trail = (7 - cells.count % 7) % 7
            cells += (0..<trail).map { CalendarCell(date: nil, dayOfMonth: nil, dayIndex: nil, inWindow: false, id: "\(key)-trail-\($0)") }
            grids.append(MonthGrid(month: key, title: title.string(from: monthStart), cells: cells))
            monthStart = calendar.date(byAdding: .month, value: 1, to: monthStart)!
        }
        return grids
    }
}
