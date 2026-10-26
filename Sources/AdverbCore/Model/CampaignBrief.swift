//
//  CampaignBrief.swift
//  AdverbCore
//
//  WHAT: What the person asks for: when the month starts, where the audience is, which platforms,
//        which days to post, how long the assets run, what to feature.
//

import Foundation

public struct CampaignBrief: Codable, Sendable, Equatable, Hashable {
    /// The first day, as a calendar date in `timeZone` ("2026-11-02").
    public var startDate: String
    public var lengthDays: Int
    /// IANA zone the post times are in ("America/New_York").
    public var timeZone: String
    /// Who the posts are for and where they are, in the person's words.
    public var audienceRegion: String
    public var platforms: [Platform]
    /// Which weekdays get a post; all seven is a daily campaign.
    public var postDays: [Weekday]
    public var durations: [Int]
    /// The Rao apps to feature (names).
    public var apps: [String]
    public var goals: String
    public var notes: String

    public init(startDate: String, lengthDays: Int = 30, timeZone: String = TimeZone.current.identifier,
                audienceRegion: String = "", platforms: [Platform] = [.instagramReels, .tiktok, .linkedin, .x],
                postDays: [Weekday] = Weekday.all, durations: [Int] = [15, 30], apps: [String] = [],
                goals: String = "", notes: String = "") {
        self.startDate = startDate; self.lengthDays = lengthDays; self.timeZone = timeZone
        self.audienceRegion = audienceRegion; self.platforms = platforms; self.postDays = postDays
        self.durations = durations; self.apps = apps; self.goals = goals; self.notes = notes
    }

    public var zone: TimeZone { TimeZone(identifier: timeZone) ?? .current }

    public var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    public var start: Date? { CalendarDate.date(startDate, in: zone) }

    /// Every calendar date in the window, as "yyyy-MM-dd".
    public var windowDates: [String] {
        guard let start else { return [] }
        let calendar = self.calendar
        return (0..<max(lengthDays, 0)).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start).map { CalendarDate.string($0, in: zone) }
        }
    }

    /// The dates in the window that get a post.
    public var postDates: [String] {
        let calendar = self.calendar
        let days = Set(postDays.map(\.rawValue))
        return windowDates.filter { date in
            guard let d = CalendarDate.date(date, in: zone) else { return false }
            return days.contains(calendar.component(.weekday, from: d))
        }
    }
}

/// "yyyy-MM-dd" in a zone, both ways.
public enum CalendarDate {
    public static func formatter(_ zone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    public static func date(_ string: String, in zone: TimeZone) -> Date? { formatter(zone).date(from: string) }
    public static func string(_ date: Date, in zone: TimeZone) -> String { formatter(zone).string(from: date) }

    /// The absolute instant of `date` at `time` ("09:30") in `zone`: DST-correct.
    public static func instant(date: String, time: String, in zone: TimeZone) -> Date? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]),
              let day = self.date(date, in: zone) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
    }
}
