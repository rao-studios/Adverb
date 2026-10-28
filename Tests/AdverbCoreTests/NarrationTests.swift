import Foundation
import Testing
@testable import AdverbCore

private extension Array where Element == ClaudeMessageParam {
    var text: String { flatMap(\.content).compactMap { $0["text"]?.stringValue }.joined(separator: "\n") }
}

@Suite struct NarrationTests {
    func recorded(_ text: String, at: Double, until: Double, spoken: (Double, Double), words: [WordTiming] = []) -> NarrationLine {
        NarrationLine(index: 0, text: text, at: at, until: until, spokenStart: spoken.0, spokenEnd: spoken.1, words: words, clipPath: "x.mp3")
    }

    @Test func linesFromAnAnswerAreOrderedAndNumbered() {
        let lines = NarrationCaptions.lines(from: NarrationResponse(lines: [.init(at: 5, until: 9, text: " Second. "), .init(at: 0.3, until: 4.8, text: "First.")]))
        #expect(lines.map(\.text) == ["First.", "Second."])
        #expect(lines.map(\.index) == [0, 1])
        let es = NarrationCaptions.translated(NarrationResponse(lines: [.init(at: 0.3, until: 4.8, text: "Primero."), .init(at: 5.1, until: 9, text: "Segundo.")]), from: lines)
        #expect(es?.map(\.text) == ["Primero.", "Segundo."])
        #expect(es?.map(\.until) == [4.8, 9])   // the English windows stay
        #expect(NarrationCaptions.translated(NarrationResponse(lines: []), from: lines) == nil)
    }

    @Test func problemsFindOverlapsAndLongLines() {
        let lines = [
            NarrationLine(index: 0, text: "One two three four five six seven eight nine ten", at: 0.2, until: 2.0),
            NarrationLine(index: 1, text: "Overlaps.", at: 1.8, until: 4),
            NarrationLine(index: 2, text: "Past the end.", at: 12, until: 15),
        ]
        let problems = NarrationCaptions.problems(lines, duration: 15)
        #expect(problems.contains { $0.contains("10 words") })
        #expect(problems.contains { $0.contains("starts before line 1 ends") })
        #expect(problems.contains { $0.contains("inside 0–14.7 s") })
        #expect(NarrationCaptions.problems([NarrationLine(index: 0, text: "Read it in a line.", at: 0.3, until: 4)], duration: 15).isEmpty)
        // Japanese has no spaces to count.
        #expect(NarrationCaptions.problems([NarrationLine(index: 0, text: String(repeating: "あ", count: 60), at: 0.3, until: 2)], duration: 15, language: .japanese).isEmpty)
        #expect(NarrationPacing.wordBudget(2.0) == 4)
    }

    @Test func cuesFollowTheTimingsAndTheWarp() {
        let a = recorded("Hello there.", at: 1.0, until: 3.0, spoken: (0.05, 0.9))
        var b = recorded("Second line.", at: 4.0, until: 6.0, spoken: (0.1, 1.2)); b.index = 1
        let cues = NarrationCaptions.cues(lines: [a, b], warp: nil, duration: 15)
        #expect(cues.map(\.text) == ["Hello there.", "Second line."])
        #expect(abs(cues[0].start - 1.05) < 1e-9 && abs(cues[0].end - 1.9) < 1e-9)
        // A warp that moves the second scene 0.5 s earlier moves its clip with it.
        let warp = TimeWarp(knots: [.init(page: 0, real: 0), .init(page: 4, real: 3.5), .init(page: 15, real: 15)])
        let warped = NarrationCaptions.cues(lines: [a, b], warp: warp, duration: 15)
        #expect(abs(warped[1].start - 3.6) < 1e-9)
        // Short speech is held half a second; nothing runs past the asset.
        let short = NarrationCaptions.cues(lines: [recorded("Hi.", at: 14.6, until: 14.9, spoken: (0, 0.1))], warp: nil, duration: 15)
        #expect(short[0].end == 15)
    }

    @Test func longLinesSplitAtAWord() {
        let text = "Ambient reads the page beside you and keeps every highlight you make, so the bridge in the fog is still there tomorrow."
        let words = text.split(separator: " ").enumerated().map { i, w in WordTiming(text: String(w), start: Double(i) * 0.3, end: Double(i) * 0.3 + 0.25) }
        let cues = NarrationCaptions.cues(lines: [recorded(text, at: 0, until: 8, spoken: (0, words.last!.end), words: words)], warp: nil, duration: 15)
        #expect(cues.count == 2)
        #expect(cues.allSatisfy { $0.text.count <= NarrationCaptions.splitAt })
        #expect(cues[0].text + " " + cues[1].text == text)
        #expect(cues[0].end == cues[1].start)
    }

    @Test func scenesWithoutNarrationAreFound() {
        let cues = [Cue(start: 0.3, end: 3, text: "a"), Cue(start: 8.1, end: 10, text: "b")]
        #expect(NarrationCaptions.uncovered(scenes: [0, 4, 8, 13.4], cues: cues, duration: 15) == [4, 13.4])
        #expect(abs(NarrationCaptions.coverage(scenes: [0, 4, 8, 13.4], cues: cues, duration: 15) - 0.5) < 1e-9)
        #expect(NarrationCaptions.overlaps([Cue(start: 0, end: 3, text: "a"), Cue(start: 2.5, end: 4, text: "b")]) == [2.5])
    }

    @Test func transcriptSaysAndShows() {
        let t = TranscriptWriter.write(title: "T", captions: [Cue(start: 0.5, end: 2, text: "Highlight a line."), Cue(start: 0, end: 2, text: "[♪ Song]", kind: .music)],
                                       descriptions: [Cue(start: 0, end: 4, text: "A desk.", kind: .description)], altText: "", music: "Song",
                                       said: [Cue(start: 0.3, end: 2, text: "Keep what you read.")])
        #expect(t.contains("- `00.00` Shown: A desk.\n- `00.30` Said: Keep what you read.\n- `00.50` Text: Highlight a line."))
        #expect(!t.contains("[♪"))
    }

    @Test func checksCoverScenesByNarration() {
        let narration = [Cue(start: 0.3, end: 3, text: "a"), Cue(start: 2.8, end: 6, text: "b")]
        let checks = A11yChecker.check(captions: [.portrait: narration], descriptions: [Cue(start: 0, end: 15, text: "d", kind: .description)],
                                       scenes: [0, 4, 9], duration: 15, altText: "Alt.", platforms: [], pageStrings: ["Never said aloud"], narration: narration)
        #expect(checks.contains { $0.message == "1 scene has no narration." })
        #expect(checks.contains { $0.message.contains("overlap at 2.8 s") })
        // On-screen coverage is not asked of a narrated asset.
        #expect(!checks.contains { $0.message.contains("on-screen headlines") })
    }

    @Test func promptsCarryTheWindows() {
        let prompts = PromptLibrary(skill: "s", addendum: "a")
        let day = CampaignDay(index: 2, date: "2026-11-03", postAt: Date(), postTimeLocal: "09:00", timeReason: "", targets: [],
                              topic: TopicBrief(slug: "t", title: "Highlights", duration: 15, kicker: "K", headline: "H *x.*",
                                                scenes: [.init(at: 0, until: 6, recipe: "r", what: "A line is highlighted.")], recipes: []),
                              caption: "", hashtags: [], hook: "Hook", cta: "Try it")
        let project = Project(slug: "p", name: "Ambient", contextPath: "/p", app: AppIdentity(name: "Ambient", kicker: "K", endTitle: "Ambient", endSub: "ambient.rao.nyc", endSub2: ""))
        let text = prompts.narrate(digest: "d", day: day, scenes: [0, 6.2, 13.4], duration: 15, project: project).text
        #expect(text.contains("0.00, 6.20, 13.40"))
        #expect(text.contains("endAt 13.4"))
        let es = prompts.translate(digest: "d", lines: [NarrationLine(index: 0, text: "Hello.", at: 0.3, until: 4)], language: .spanish, day: day, project: project).text
        #expect(es.contains("Spanish (Español, es)"))
        #expect(es.contains("0.30–4.00 s: Hello."))
        let short = prompts.narrateShorten(lines: [NarrationLine(index: 0, text: "Too long.", at: 0, until: 1)], long: [(0, 1.6, 1.0)], language: .english).text
        #expect(short.contains("SHORTEN (spoken 1.6 s, window 1.0 s): Too long."))
    }
}
