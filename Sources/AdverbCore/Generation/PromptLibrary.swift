//
//  PromptLibrary.swift
//  AdverbCore
//
//  WHAT: The prompts: the skill and Adverb's addendum as the system prompt, the project's digest
//        as the first user block, and the request after it.
//  PIN:  Cache order. System (skill, addendum) and the digest are identical for every request of a
//        campaign, so they sit before the breakpoints and are read from cache; everything that
//        changes (the brief, the day, the stills) comes after the last breakpoint. A timestamp
//        before a breakpoint would silently make every build pay full price.
//

import Foundation

public struct PromptLibrary: Sendable, Equatable {
    public let skill: String
    public let addendum: String

    public init(skill: String, addendum: String) { self.skill = skill; self.addendum = addendum }

    /// The bundled skill (or `skillPath`'s), and the bundled addendum.
    public static func load(skillPath: String? = nil) throws -> PromptLibrary {
        let skill = skillPath.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) } ?? KitBundle.text("Prompts/SKILL.md")
        guard let skill, let addendum = KitBundle.text("Prompts/adverb-addendum.md") else { throw KitError.bundleMissing }
        return PromptLibrary(skill: skill, addendum: addendum)
    }

    public var system: [SystemBlock] {
        [SystemBlock(skill, cache: false), SystemBlock(addendum, cache: true)]
    }

    func digestBlock(_ digest: String) -> JSONValue { .text(digest, cache: true) }

    // MARK: Plan

    public func plan(digest: String, brief: CampaignBrief, project: Project, campaignName: String) -> [ClaudeMessageParam] {
        let dates = brief.postDates
        let identity = project.app
        var lines: [String] = []
        lines.append("Plan this campaign: \"\(campaignName)\" for \(project.name).")
        lines.append("")
        lines.append("Posting dates (\(dates.count), in \(brief.timeZone)): \(dates.joined(separator: ", ")).")
        lines.append("Platforms: \(brief.platforms.map { "\($0.title) (\($0.rawValue))" }.joined(separator: ", ")).")
        lines.append("Lengths allowed: \(brief.durations.map { "\($0) s" }.joined(separator: ", ")).")
        if !brief.audienceRegion.isEmpty { lines.append("Audience: \(brief.audienceRegion).") }
        if !brief.apps.isEmpty { lines.append("Feature: \(brief.apps.joined(separator: ", ")).") }
        if !brief.goals.isEmpty { lines.append("Goals: \(brief.goals)") }
        if !brief.notes.isEmpty { lines.append("Notes: \(brief.notes)") }
        lines.append("")
        lines.append("The app: \(identity.name). Kicker default \"\(identity.kicker)\". End card: \(identity.endTitle) · \(identity.endSub) · \(identity.endSub2).")
        if identity.comingSoon { lines.append("\(identity.name) is coming soon: say so; do not describe it as shipping.") }
        if !identity.sources.isEmpty { lines.append("You may fetch: \(identity.sources.joined(separator: " , ")).") }
        lines.append("")
        lines.append("Return exactly \(dates.count) days, one per posting date above, in order, with index 1…\(dates.count).")
        return [.user([digestBlock(digest), .text(lines.joined(separator: "\n"))])]
    }

    /// The plan's problems, sent back once with the plan Claude wrote.
    public func planFix(previous: [ClaudeMessageParam], answer: String, problems: [String]) -> [ClaudeMessageParam] {
        previous + [.assistant([.text(answer)]),
                    .user("Fix these problems and return the whole plan again:\n" + problems.map { "- \($0)" }.joined(separator: "\n"))]
    }

    // MARK: Build

    public func build(digest: String, day: CampaignDay, campaign: Campaign, project: Project) -> [ClaudeMessageParam] {
        let identity = project.app
        let neighbours = campaign.days.filter { abs($0.index - day.index) <= 2 && $0.index != day.index }
            .map { "- \($0.date): \($0.topic.title) (\($0.topic.recipes.joined(separator: ", ")))" }
        var lines: [String] = []
        lines.append("Build the asset for \(day.date) (\(day.topic.duration) s), from this plan entry:")
        lines.append("")
        lines.append("Title: \(day.topic.title)")
        lines.append("Kicker: \(day.topic.kicker)")
        lines.append("Headline: \(day.topic.headline)")
        lines.append("Scenes:")
        for s in day.topic.scenes { lines.append(String(format: "- %.1f–%.1f s · %@ · %@", s.at, s.until, s.recipe, s.what)) }
        lines.append("Recipes: \(day.topic.recipes.joined(separator: ", "))")
        lines.append("Hook: \(day.hook)")
        lines.append("")
        lines.append("End card: endTitle \"\(identity.endTitle)\", endSub \"\(identity.endSub)\", endSub2 \"\(identity.endSub2)\". Kicker uses the plan's kicker.")
        if identity.comingSoon { lines.append("\(identity.name) is coming soon; label it so.") }
        if let plan = campaign.plan { lines.append("The month: \(plan.summary)") }
        if !neighbours.isEmpty { lines.append("Neighbouring days (look different from these):\n" + neighbours.joined(separator: "\n")) }
        lines.append("")
        lines.append("window.DUR=\(day.topic.duration); endAt \(Double(day.topic.duration) - 1.6). Return the page, notes and accessibility text.")
        return [.user([digestBlock(digest), .text(lines.joined(separator: "\n"))])]
    }

    public func buildFix(previous: [ClaudeMessageParam], answer: String, problems: [String]) -> [ClaudeMessageParam] {
        previous + [.assistant([.text(answer)]),
                    .user("The page has problems. Fix them and return the whole answer again:\n" + problems.map { "- \($0)" }.joined(separator: "\n"))]
    }

    // MARK: Review

    public func review(day: CampaignDay, html: String, stills: [(label: String, jpeg: Data)]) -> [ClaudeMessageParam] {
        var blocks: [JSONValue] = [.text("Review these stills of the page you wrote for \(day.date) (\(day.topic.title)). Portrait is 1080×1920, landscape 1920×1080.")]
        for still in stills {
            blocks.append(.text(still.label))
            blocks.append(.jpeg(still.jpeg))
        }
        blocks.append(.text("The page:\n```html\n\(html)\n```"))
        return [.user(blocks)]
    }

    // MARK: Retime

    public func retime(html: String, grid: BeatGrid, song: String) -> [ClaudeMessageParam] {
        func list(_ xs: [Double]) -> String { xs.map { String(format: "%.3f", $0) }.joined(separator: ", ") }
        let text = """
        Re-time this page to "\(song)" at \(String(format: "%.1f", grid.bpm)) BPM. Video-time grid:
        Beats: \(list(grid.beats))
        Downbeats: \(list(grid.downbeats))

        ```html
        \(html)
        ```
        """
        return [.user(text)]
    }
}
