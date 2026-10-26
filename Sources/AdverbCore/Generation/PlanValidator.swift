//
//  PlanValidator.swift
//  AdverbCore
//
//  WHAT: The plan Claude wrote, checked against the brief, then turned into campaign days: one
//        per posting date, in order, inside the window, on platforms the brief allows, with times
//        that parse, unique topic slugs, lengths the brief allows. What is wrong goes back to Claude
//        once, as a list.
//

import Foundation

public enum PlanValidator {
    public static func problems(_ plan: PlanResponse, brief: CampaignBrief) -> [String] {
        var out: [String] = []
        let expected = brief.postDates
        let dates = plan.days.map(\.date)
        if plan.days.count != expected.count {
            out.append("The plan has \(plan.days.count) days; the brief has \(expected.count) posting dates (\(expected.first ?? "")…\(expected.last ?? "")).")
        }
        let missing = Set(expected).subtracting(dates).sorted()
        if !missing.isEmpty { out.append("No post on: \(missing.prefix(10).joined(separator: ", ")).") }
        let extra = Set(dates).subtracting(expected).sorted()
        if !extra.isEmpty { out.append("Posts on dates that are not posting dates: \(extra.prefix(10).joined(separator: ", ")).") }
        if Set(dates).count != dates.count { out.append("Two posts share a date; post once a day.") }
        if dates != dates.sorted() { out.append("Days are not in date order.") }
        let allowed = Set(brief.platforms.map(\.rawValue))
        var slugs = Set<String>()
        for day in plan.days {
            if !allowed.contains(day.platform) { out.append("Day \(day.index) is on \(day.platform), which the brief does not use.") }
            for p in day.cross_post where !allowed.contains(p) { out.append("Day \(day.index) cross-posts to \(p), which the brief does not use.") }
            if CalendarDate.instant(date: day.date, time: day.post_time_local, in: brief.zone) == nil {
                out.append("Day \(day.index): post_time_local \"\(day.post_time_local)\" is not HH:MM.")
            }
            if !Slug.isTopicSlug(day.topic_slug) { out.append("Day \(day.index): topic_slug \"\(day.topic_slug)\" must be lowercase kebab-case, at most 24 characters.") }
            if !slugs.insert(day.topic_slug).inserted { out.append("Day \(day.index): topic_slug \"\(day.topic_slug)\" is used twice.") }
            if !brief.durations.contains(day.duration) { out.append("Day \(day.index) is \(day.duration) s; the brief allows \(brief.durations.map(String.init).joined(separator: " or ")) s.") }
            if day.scenes.isEmpty { out.append("Day \(day.index) has no scenes.") }
            if let platform = Platform(rawValue: day.platform),
               PlatformLimits.length(caption: day.caption, hashtags: day.hashtags) > PlatformLimits.captionMax(platform) {
                out.append("Day \(day.index): caption and hashtags run past \(platform.title)'s \(PlatformLimits.captionMax(platform)) characters.")
            }
            if day.time_reason.trimmingCharacters(in: .whitespaces).isEmpty { out.append("Day \(day.index) has no time_reason.") }
        }
        return out
    }

    /// The plan as campaign days (call after `problems` is empty).
    public static func days(_ plan: PlanResponse, brief: CampaignBrief) -> [CampaignDay] {
        plan.days.sorted { $0.date < $1.date }.enumerated().map { offset, day in
            let primary = Platform(rawValue: day.platform) ?? brief.platforms.first ?? .instagramReels
            var targets = [PostTarget(platform: primary)]
            for p in day.cross_post.compactMap(Platform.init(rawValue:)) where !targets.contains(where: { $0.platform == p }) {
                targets.append(PostTarget(platform: p))
            }
            let scenes = day.scenes.map { SceneBeat(at: $0.at, until: $0.until, recipe: $0.recipe, what: $0.what) }
            return CampaignDay(index: offset + 1, date: day.date,
                               postAt: CalendarDate.instant(date: day.date, time: day.post_time_local, in: brief.zone) ?? Date(),
                               postTimeLocal: day.post_time_local, timeReason: day.time_reason, targets: targets,
                               topic: TopicBrief(slug: day.topic_slug, title: day.title, duration: day.duration, kicker: day.kicker,
                                                 headline: day.headline, scenes: scenes, recipes: day.recipes),
                               caption: day.caption, hashtags: day.hashtags.map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 },
                               hook: day.hook, cta: day.cta)
        }
    }
}
