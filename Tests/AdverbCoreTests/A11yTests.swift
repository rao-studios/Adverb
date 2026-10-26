import Foundation
import Testing
@testable import AdverbCore

@Suite struct A11yTests {
    func samples() -> [CaptionSample] {
        var out: [CaptionSample] = []
        for i in 0..<150 {
            let t = Double(i) / 10
            var items: [CaptionItem] = []
            if t >= 0.2 && t < 13.4 { items.append(.init(id: "kicker", text: "Ambient, explained", kind: "kicker", x: 96, y: 226)) }
            if t >= 0.2 && t < 0.5 { items.append(.init(id: "h1", text: "Highlight", kind: "headline", x: 96, y: 300)) }
            if t >= 0.5 && t < 6.0 { items.append(.init(id: "h1", text: "Highlight a line.", kind: "headline", x: 96, y: 300)) }
            if t >= 2.6 && t < 13.2 && !(t >= 5.0 && t < 5.1) { items.append(.init(id: "c1", text: "The Bridge in the Fog", kind: "chip", x: 128, y: 830)) }
            if t >= 13.7 { items.append(.init(id: "endT", text: "Ambient", kind: "end", x: 0, y: 1090)) }
            if t >= 13.9 { items.append(.init(id: "endS", text: "ambient.rao.nyc", kind: "end", x: 0, y: 1235)) }
            out.append(CaptionSample(t: t, items: items))
        }
        return out
    }

    @Test func cuesFoldRisingHeadlinesAndGaps() {
        let cues = CueTracker.cues(from: samples(), duration: 15)
        let headline = cues.first { $0.text.hasPrefix("Highlight") }
        #expect(headline?.text == "Highlight a line.")
        #expect(headline.map { abs($0.start - 0.2) < 1e-9 && abs($0.end - 6.0) < 1e-9 } == true)
        // The chip blinked for 0.1 s and stays one cue.
        #expect(cues.filter { $0.text == "The Bridge in the Fog" }.count == 1)
        #expect(cues.contains { $0.text == "Ambient · ambient.rao.nyc" })
    }

    @Test func captionsKeepTheHeadlineAndAtMostTwoLines() {
        let cues = CueTracker.captions(from: samples(), duration: 15)
        #expect(cues.allSatisfy { $0.text.components(separatedBy: "\n").count <= 2 })
        #expect(zip(cues, cues.dropFirst()).allSatisfy { $0.end <= $1.start + 1e-9 })
        #expect(cues.allSatisfy { $0.end - $0.start >= CueTracker.minDuration - 1e-9 })
        // While the headline is up it is in every cue; the kicker only shows alone.
        #expect(cues.filter { $0.start >= 0.5 && $0.end <= 6.0 }.allSatisfy { $0.text.contains("Highlight a line.") })
        #expect(!cues.contains { $0.text.contains("Ambient, explained") && $0.text.contains("\n") })
        #expect(cues.contains { $0.text == "Ambient · ambient.rao.nyc" })
    }

    @Test func writers() {
        let cues = [Cue(start: 0.2, end: 6, text: "Highlight <a> line & more"), Cue(start: 61.5, end: 3_661.25, text: "Two\nlines")]
        let vtt = WebVTTWriter.write(cues, title: "Day 1")
        #expect(vtt.hasPrefix("WEBVTT - Day 1\nKind: captions\nLanguage: en\n"))
        #expect(vtt.contains("00:00:00.200 --> 00:00:06.000\nHighlight &lt;a&gt; line &amp; more\n"))
        #expect(vtt.contains("00:01:01.500 --> 01:01:01.250"))
        let srt = SRTWriter.write(cues)
        #expect(srt.hasPrefix("1\n00:00:00,200 --> 00:00:06,000\nHighlight <a> line & more\n"))
        #expect(srt.contains("\n2\n00:01:01,500 --> 01:01:01,250\nTwo\nlines\n"))
        let transcript = TranscriptWriter.write(title: "T", captions: cues, descriptions: [Cue(start: 0, end: 6, text: "A desk.", kind: .description)],
                                                altText: "Alt.", music: nil)
        #expect(transcript.contains("- `00.00` Shown: A desk."))
    }

    @Test func checksFindGaps() {
        let html = #"<div id="h1" class="head">Highlight <em>a line.</em></div><span class="chip" id="c1"><span class="sw"></span>The Bridge</span></div>"#
        #expect(A11yChecker.pageStrings(html: html) == ["Highlight a line.", "The Bridge"])
        let cues = [Cue(start: 0, end: 5, text: "Highlight a line.")]
        #expect(A11yChecker.coverage(of: ["Highlight a line.", "The Bridge"], in: cues) == 0.5)
        let checks = A11yChecker.check(captions: [.portrait: cues], descriptions: [], scenes: [0, 6], duration: 15,
                                       altText: String(repeating: "a", count: 1_200), platforms: [.x], pageStrings: ["Highlight a line."])
        #expect(checks.contains { $0.level == .problem && $0.message.contains("descriptions") })
        #expect(checks.contains { $0.message.contains("X takes 1000") })
    }

    @Test func platformLimits() {
        #expect(PlatformLimits.captionMax(.x) == 280)
        #expect(PlatformLimits.length(caption: "Hi", hashtags: ["a", "#b"]) == 2 + 2 + 5)
        #expect(PlatformLimits.acceptsCaptionFile(.youtubeShorts))
        #expect(!PlatformLimits.acceptsCaptionFile(.instagramReels))
    }

    @Test func gridWindowsAndInPoint() {
        let energy: [Float] = Array(repeating: 0, count: 300) + Array(repeating: 1, count: 2000)
        let grid = BeatGrid(bpm: 120, confidence: 0.9, beats: stride(from: 0.0, through: 23, by: 0.5).map { $0 },
                            downbeats: stride(from: 0.0, through: 23, by: 2).map { $0 }, energy: energy, duration: 23)
        #expect(grid.suggestedInPoint(for: 15) == 4.0)
        let window = grid.window(inPoint: 4, duration: 15)
        #expect(window.downbeats.first == 0)
        #expect(window.beats.last == 15)
        #expect(window.energy.count == 1500)
    }
}

@Suite struct CaptionReaderTests {
    @Test func readsWhatItWrites() {
        let cues = [Cue(start: 0.2, end: 6, text: "Highlight <a> line"), Cue(start: 61.5, end: 70.25, text: "Two\nlines")]
        #expect(WebVTTReader.parse(WebVTTWriter.write(cues)) == cues)
        #expect(WebVTTReader.parse(SRTWriter.write(cues)) == cues)
    }
}
