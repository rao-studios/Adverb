import Foundation
@testable import AdverbCore

enum Fixture {
    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    static func url(_ name: String) -> URL { folder.appendingPathComponent(name) }
    static func text(_ name: String) -> String { (try? String(contentsOf: url(name), encoding: .utf8)) ?? "" }

    /// A fresh temporary folder, removed by the caller (or left for the OS).
    static func temp(_ label: String = "adverb-tests") -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(label)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

func samplePlan(dates: [String], platform: String = "instagram_reels", time: String = "09:30") -> PlanResponse {
    PlanResponse(summary: "A month", arc: ["Premise", "Features", "Finale"], sources: ["README.md"], cautions: [],
                 days: dates.enumerated().map { i, d in
                     PlanResponse.Day(index: i + 1, date: d, post_time_local: time, time_reason: "Morning scroll.", platform: platform,
                                      cross_post: ["tiktok"], topic_slug: "topic-\(i + 1)", title: "Topic \(i + 1)", duration: 15,
                                      kicker: "Ambient, explained", headline: "Highlight *a line.*", hook: "Hook",
                                      scenes: [.init(at: 0, until: 6, recipe: "Desktop highlight", what: "A line is highlighted.")],
                                      recipes: ["Desktop highlight"], caption: "Caption \(i + 1)", hashtags: ["#ambient", "reading"], cta: "Try it")
                 })
}

func sampleBrief(start: String = "2026-11-01", days: Int = 7, postDays: [Weekday] = Weekday.all) -> CampaignBrief {
    CampaignBrief(startDate: start, lengthDays: days, timeZone: "America/New_York", audienceRegion: "US readers",
                  platforms: [.instagramReels, .tiktok, .linkedin], postDays: postDays, durations: [15, 30])
}
