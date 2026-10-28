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

    // MARK: Voice-over

    /// The narration for a built page: timed to its real scenes, written to be heard.
    public func narrate(digest: String, day: CampaignDay, scenes: [Double], duration: Int, project: Project) -> [ClaudeMessageParam] {
        let endAt = Double(duration) - 1.6
        let starts = scenes.isEmpty ? [0, endAt] : scenes
        var lines: [String] = []
        lines.append("Write the voice-over for the asset you built for \(day.date) (\(duration) s): \(day.topic.title).")
        lines.append("")
        lines.append("Kicker: \(day.topic.kicker)")
        lines.append("Headline: \(day.topic.headline)")
        lines.append("Hook: \(day.hook)")
        if !day.cta.isEmpty { lines.append("Call to action: \(day.cta)") }
        lines.append("What each scene shows:")
        for s in day.topic.scenes { lines.append(String(format: "- %.1f–%.1f s · %@", s.at, s.until, s.what)) }
        lines.append("The page's window.SCENES (the real scene starts, page time): \(starts.map { String(format: "%.2f", $0) }.joined(separator: ", ")).")
        lines.append(String(format: "window.DUR=%d; the end card starts at endAt %.1f.", duration, endAt))
        lines.append("")
        lines.append("Name: \(project.app.name). End card: \(project.app.endTitle) · \(project.app.endSub).")
        if project.app.comingSoon { lines.append("\(project.app.name) is coming soon: say so, never as shipping.") }
        lines.append(String(format: "Pace: about %.1f words a second, with %.1f s to spare in every line's window. Return the lines in order.", NarrationPacing.wordsPerSecond, NarrationPacing.headroom))
        return [.user([digestBlock(digest), .text(lines.joined(separator: "\n"))])]
    }

    public func narrateFix(previous: [ClaudeMessageParam], answer: String, problems: [String]) -> [ClaudeMessageParam] {
        previous + [.assistant([.text(answer)]),
                    .user("The voice-over has problems. Fix them and return every line again:\n" + problems.map { "- \($0)" }.joined(separator: "\n"))]
    }

    /// Lines that ran past their window when spoken, sent back to be shortened.
    public func narrateShorten(lines: [NarrationLine], long: [(index: Int, spoken: Double, window: Double)], language: Language) -> [ClaudeMessageParam] {
        var out: [String] = []
        out.append("These \(language == .english ? "" : language.title + " ")voice-over lines run long when spoken. Shorten the marked ones: same meaning, fewer words, in \(language.title). Keep every other line exactly, and every `at` and `until`. Return all \(lines.count) lines.")
        out.append("")
        let marks = Dictionary(long.map { ($0.index, $0) }, uniquingKeysWith: { a, _ in a })
        for line in lines {
            if let m = marks[line.index] {
                out.append(String(format: "- [%d] %.2f–%.2f s · SHORTEN (spoken %.1f s, window %.1f s): %@", line.index, line.at, line.until, m.spoken, m.window, line.text))
            } else {
                out.append(String(format: "- [%d] %.2f–%.2f s · keep: %@", line.index, line.at, line.until, line.text))
            }
        }
        return [.user(out.joined(separator: "\n"))]
    }

    /// The English narration in another language, line for line, in the same windows.
    public func translate(digest: String, lines: [NarrationLine], language: Language, day: CampaignDay, project: Project) -> [ClaudeMessageParam] {
        var out: [String] = []
        out.append("Translate this voice-over into \(language.title) (\(language.nativeTitle), \(language.code)) for \(day.date): \(day.topic.title).")
        out.append("Keep each line in its window (same `at` and `until`, same number of lines, same order), natural for a native speaker, and no longer when spoken than the English. Keep \(project.app.name), other product names and URLs as they are.")
        out.append("")
        for line in lines { out.append(String(format: "- %.2f–%.2f s: %@", line.at, line.until, line.text)) }
        return [.user([digestBlock(digest), .text(out.joined(separator: "\n"))])]
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
