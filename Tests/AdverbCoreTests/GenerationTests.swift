import Foundation
import Testing
@testable import AdverbCore

@Suite struct GenerationTests {
    @Test func digestReadsTheProjectAndSkipsTheRest() {
        let digest = ContextDigestBuilder.build(root: Fixture.url("context-sample"))
        let paths = digest.files.map(\.path)
        #expect(paths.first == "README.md")
        #expect(paths.contains("Docs/README.md"))
        #expect(paths.contains("Docs/site/01-read.html"))
        #expect(!paths.contains { $0.contains(".build") || $0.contains("node_modules") || $0.contains("._") })
        #expect(digest.text.contains("Title: Sample site"))
        #expect(digest.text.contains("Every answer & its source."))
        #expect(!digest.text.contains("var x=1"))
        #expect(ContextDigestBuilder.build(root: Fixture.url("context-sample")).sha256 == digest.sha256)
    }

    @Test func digestTruncatesWithAMarker() {
        let digest = ContextDigestBuilder.build(root: Fixture.url("context-sample"), budgetTokens: 60_000, readmeTokens: 5)
        #expect(digest.text.contains("more characters]"))
    }

    @Test func globMatches() {
        #expect(ContextDigestBuilder.matches("Docs/AII/README.md", "Docs/**/README.md"))
        #expect(ContextDigestBuilder.matches("Docs/README.md", "Docs/**/README.md"))
        #expect(ContextDigestBuilder.matches("Docs/site/01.html", "Docs/site/*.html"))
        #expect(!ContextDigestBuilder.matches("Docs/site/x/01.html", "Docs/site/*.html"))
    }

    @Test func postDatesFollowTheBrief() {
        let brief = sampleBrief(start: "2026-11-01", days: 14, postDays: [.monday, .wednesday, .friday])
        #expect(brief.postDates == ["2026-11-02", "2026-11-04", "2026-11-06", "2026-11-09", "2026-11-11", "2026-11-13"])
    }

    @Test func planBecomesDaysAcrossDST() throws {
        // New York leaves daylight time on 2026-11-01 at 02:00.
        let brief = sampleBrief(start: "2026-10-31", days: 2)
        let plan = samplePlan(dates: brief.postDates)
        #expect(PlanValidator.problems(plan, brief: brief).isEmpty)
        let days = PlanValidator.days(plan, brief: brief)
        #expect(days.count == 2)
        let utc = ISO8601DateFormatter()
        #expect(utc.string(from: days[0].postAt) == "2026-10-31T13:30:00Z")   // EDT, UTC−4
        #expect(utc.string(from: days[1].postAt) == "2026-11-01T14:30:00Z")   // EST, UTC−5
        #expect(days[0].targets.map(\.platform) == [.instagramReels, .tiktok])
        #expect(days[0].hashtags == ["ambient", "reading"])
        #expect(days[0].stem == "01-topic-1")
    }

    @Test func planProblemsAreSpecific() {
        let brief = sampleBrief(days: 3)
        var plan = samplePlan(dates: ["2026-11-01", "2026-11-01"], platform: "x", time: "9.30")
        plan.days[1].topic_slug = "topic-1"
        let problems = PlanValidator.problems(plan, brief: brief)
        #expect(problems.contains { $0.contains("2 days") })
        #expect(problems.contains { $0.contains("No post on") })
        #expect(problems.contains { $0.contains("does not use") })
        #expect(problems.contains { $0.contains("HH:MM") })
        #expect(problems.contains { $0.contains("used twice") })
    }

    @Test func pageVerifierRewritesAndChecks() {
        let page = URL(fileURLWithPath: "/w/Adverb/p/campaigns/c/assets/01-x")
        let kit = URL(fileURLWithPath: "/w/Adverb/p/kit")
        #expect(PageVerifier.relativePath(from: page, to: kit) == "../../../../kit/")
        let html = #"<!doctype html><link rel="stylesheet" href="kit.css"><script src="kit.js"></script>"#
        #expect(PageVerifier.rewriteKitPaths(html, pageFolder: page, kitFolder: kit).contains(#"src="../../../../kit/kit.js""#))
        let bad = "<html><script>setTimeout(f,1); Math.random()</script>"
        let problems = PageVerifier.problems(bad, duration: 15)
        #expect(problems.contains { $0.contains("doctype") })
        #expect(problems.contains { $0.contains("window.DUR=15") })
        #expect(problems.contains { $0.contains("setTimeout") })
        #expect(problems.contains { $0.contains("SCENES") })
        #expect(PageVerifier.scenes("window.SCENES=[0, 6.35,13.4];") == [0, 6.35, 13.4])
        let good = Fixture.text("../../AdverbRenderTests/Fixtures/sample/page.html")
        #expect(PageVerifier.problems(good, duration: 15) == [])
    }

    @Test func warpMovesScenesToDownbeats() {
        let grid = BeatGrid(bpm: 120, confidence: 0.9, beats: stride(from: 0.2, through: 15, by: 0.5).map { $0 },
                            downbeats: stride(from: 0.2, through: 15, by: 2.0).map { $0 }, duration: 15)
        let warp = Beatmap.warp(scenes: [0, 6.35, 13.4], grid: grid, duration: 15, endAt: 13.4)
        #expect(abs(warp.pageTime(forReal: 6.2) - 6.35) < 1e-9)       // 6.35 → the downbeat at 6.2
        #expect(abs(warp.pageTime(forReal: 0) - 0) < 1e-9)
        #expect(abs(warp.pageTime(forReal: 15) - 15) < 1e-9)
        let endKnot = warp.knots.first { abs($0.page - 13.4) < 1e-9 }
        #expect(endKnot.map { $0.real >= 13.4 && $0.real <= 14.0 } == true)   // a beat in [DUR−1.6, DUR−1.0]
        var last = -1.0
        for i in 0...450 { let p = warp.pageTime(forReal: Double(i) / 30); #expect(p >= last); last = p }
        #expect(abs(warp.realTime(forPage: 6.35) - 6.2) < 1e-9)
    }

    @Test func warpLeavesUnreachableScenesAlone() {
        let grid = BeatGrid(bpm: 60, confidence: 0.9, beats: [0.0, 9.0], downbeats: [0.0, 9.0], duration: 15)
        let warp = Beatmap.warp(scenes: [0, 5], grid: grid, duration: 15)
        #expect(abs(warp.pageTime(forReal: 5) - 5) < 1e-9)
    }

    @Test func beatScriptsLoadAfterKit() {
        let html = #"<script src="../../../../kit/kit.js"></script><script>x</script>"#
        let out = Beatmap.withBeatScripts(html, kitPrefix: "../../../../kit/", beatsFile: "01-x.beats.js")
        #expect(out.contains(#"kit.js"></script><script src="../../../../kit/kit-beat.js"></script><script src="01-x.beats.js"></script>"#))
        let grid = BeatGrid(bpm: 120, confidence: 1, beats: [0.5, 1], downbeats: [0.5], duration: 15)
        #expect(Beatmap.beatsScript(grid: grid, inPoint: 30, song: "Song").contains("window.BEATS=[0.500,1.000];"))
    }

    @Test func retimeValidatorGuardsMarkup() {
        let grid = BeatGrid(bpm: 120, confidence: 1, beats: [1, 1.5, 2], downbeats: [2], duration: 15)
        let a = "<div>Hi</div><script>seek(1.0)</script>"
        #expect(RetimeValidator.problems(original: a, retimed: "<div>Hi</div><script>seek(2.0)</script>", duration: 15, grid: grid,
                                         cues: [.init(t: 2, kind: "cut")]).filter { !$0.contains("DUR") }.isEmpty)
        #expect(!RetimeValidator.problems(original: a, retimed: "<div>Hey</div><script>seek(2.0)</script>", duration: 15, grid: grid, cues: []).isEmpty)
        #expect(RetimeValidator.problems(original: a, retimed: a, duration: 15, grid: grid, cues: [.init(t: 1.25, kind: "stroke")])
            .contains { $0.contains("not on the grid") })
    }

    @Test func calendarGridsPadWeeks() {
        var campaign = Campaign(projectID: UUID(), name: "N", brief: sampleBrief(start: "2026-11-28", days: 5))
        campaign.days = PlanValidator.days(samplePlan(dates: campaign.brief.postDates), brief: campaign.brief)
        let months = CalendarLayout.months(for: campaign)
        #expect(months.map(\.month) == ["2026-11", "2026-12"])
        #expect(months[0].cells.count % 7 == 0)
        // November 2026 starts on a Sunday: no leading blanks.
        #expect(months[0].cells.first?.date == "2026-11-01")
        #expect(months[0].cells.first { $0.date == "2026-11-28" }?.dayIndex == 1)
        #expect(months[1].cells.first { $0.date == "2026-12-02" }?.dayIndex == 5)
        #expect(months[1].cells.first { $0.date == "2026-12-03" }?.inWindow == false)
        #expect(months[0].title == "November 2026")
    }

    @Test func exportsAreWellFormed() {
        var campaign = Campaign(projectID: UUID(), name: "November", brief: sampleBrief(days: 2))
        campaign.days = PlanValidator.days(samplePlan(dates: campaign.brief.postDates), brief: campaign.brief)
        campaign.days[0].caption = "Highlight a line, see its source; that's all."
        let project = Project(slug: "a", name: "Ambient", contextPath: "/tmp", app: .ambient)
        let ics = Exports.ics(campaign, project: project, now: Date(timeIntervalSince1970: 0))
        #expect(ics.hasPrefix("BEGIN:VCALENDAR\r\n"))
        #expect(ics.components(separatedBy: "BEGIN:VEVENT").count == 3)
        #expect(ics.contains("DTSTART:20261101T143000Z"))
        #expect(ics.contains("TRIGGER:PT0S"))
        #expect(ics.components(separatedBy: "\r\n").allSatisfy { $0.utf8.count <= 75 })
        #expect(ics.replacingOccurrences(of: "\r\n ", with: "").contains("source\\; that's all."))   // unfolded
        let csv = Exports.csv(campaign)
        #expect(csv.hasPrefix("date,time,timezone,post_at_utc"))
        #expect(csv.contains("\"Highlight a line, see its source; that's all.\""))
        let md = Exports.captionsMarkdown(campaign, project: project, paths: CampaignPaths(root: URL(fileURLWithPath: "/x")))
        #expect(md.contains("## Sunday 2026-11-01, 09:30"))
    }
}
