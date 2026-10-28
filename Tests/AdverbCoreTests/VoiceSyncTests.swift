import Foundation
import Testing
@testable import AdverbCore

@Suite struct VoiceSyncTests {
    func line(_ i: Int, at: Double, until: Double, speech: Double) -> NarrationLine {
        NarrationLine(index: i, text: "Line \(i).", at: at, until: until, spokenStart: 0.05, spokenEnd: 0.05 + speech, clipPath: "c\(i).mp3")
    }

    @Test func linesMoveOntoTheirText() {
        let screen = [Cue(start: 0.4, end: 5.9, text: "Highlight a line."), Cue(start: 2.6, end: 13, text: "The Bridge in the Fog"), Cue(start: 6.3, end: 12, text: "Sources")]
        let lines = [line(0, at: 0.2, until: 2.4, speech: 1.5), line(1, at: 2.4, until: 6.0, speech: 2), line(2, at: 6.0, until: 13.0, speech: 3), line(3, at: 9, until: 13, speech: 1)]
        let anchored = VoiceSync.anchor(lines, to: screen)
        #expect(anchored.map(\.at) == [0.4, 2.6, 6.3, 9])   // the last has no text near it
    }

    @Test func aVoiceThatFitsLeavesThePageAlone() {
        let lines = [line(0, at: 0.4, until: 4, speech: 2), line(1, at: 5, until: 9, speech: 2.5)]
        #expect(VoiceSync.warp(lines: lines, duration: 15, endAt: 13.4) == nil)
    }

    @Test func aLongLineStretchesItsSceneAndKeepsTheEndCard() throws {
        // Line 0 needs 3.6 s but line 1's text arrives 3 s after it: the page waits for the voice.
        let lines = [line(0, at: 1.0, until: 4, speech: 3.6), line(1, at: 4.0, until: 8, speech: 2)]
        let warp = try #require(VoiceSync.warp(lines: lines, duration: 15, endAt: 13.4))
        let second = warp.realTime(forPage: 4.0)
        #expect(abs(second - (1.0 + 3.6 + VoiceSync.gap)) < 1e-6)
        #expect(abs(warp.realTime(forPage: 1.0) - 1.0) < 1e-6)
        #expect(abs(warp.realTime(forPage: 13.4) - 13.4) < 1e-6)
        #expect(abs(warp.realTime(forPage: 15) - 15) < 1e-6)
        // Speech, captions and text agree: the second line's first word is when its text arrives.
        let cues = NarrationCaptions.spoken(lines, warp: warp)
        #expect(abs(cues[1].start - second) < 1e-6)
        #expect(cues[0].end + VoiceSync.gap <= cues[1].start + 1e-6)
    }

    @Test func linesThatCannotAllFitAreSaidBeforeTheEndCard() throws {
        let lines = [line(0, at: 8, until: 10, speech: 2.5), line(1, at: 10.5, until: 13, speech: 2.5)]
        let warp = try #require(VoiceSync.warp(lines: lines, duration: 15, endAt: 13.4))
        let cues = NarrationCaptions.spoken(lines, warp: warp)
        #expect(cues[1].end <= 13.4 - 0.1 + 1e-6)
        #expect(cues[0].end + VoiceSync.gap <= cues[1].start + 1e-6)
    }

    @Test func withASongEachLineLandsOnTheBeat() throws {
        let grid = BeatGrid(bpm: 120, confidence: 1, beats: stride(from: 0.0, through: 15, by: 0.5).map { $0 },
                            downbeats: stride(from: 0.0, through: 15, by: 2.0).map { $0 }, duration: 15)
        let lines = [line(0, at: 1.95, until: 4, speech: 1.5), line(1, at: 6.08, until: 9, speech: 2)]
        let warp = try #require(VoiceSync.warp(lines: lines, duration: 15, endAt: 13.4, grid: grid))
        #expect(abs(warp.realTime(forPage: 1.95) - 2.0) < 1e-6)   // the downbeat
        #expect(abs(warp.realTime(forPage: 6.08) - 6.0) < 1e-6)
        // The end card on the last downbeat in [DUR − 1.6, DUR − 1.0].
        #expect(abs(warp.realTime(forPage: 13.4) - 14.0) < 1e-6)
    }

    @Test func warpsCompareByTheFrameTheyShow() {
        let a = TimeWarp(knots: [.init(page: 0, real: 0), .init(page: 4, real: 4.01), .init(page: 15, real: 15)])
        #expect(TimeWarp.same(nil, nil, duration: 15))
        #expect(TimeWarp.same(a, nil, duration: 15))
        #expect(!TimeWarp.same(TimeWarp(knots: [.init(page: 0, real: 0), .init(page: 4, real: 5), .init(page: 15, real: 15)]), nil, duration: 15))
    }

    @Test func descriptionsGoBackToPageTime() {
        let warp = TimeWarp(knots: [.init(page: 0, real: 0), .init(page: 4, real: 5), .init(page: 15, real: 15)])
        var asset = Asset(folder: "a", duration: 15, pagePath: "a/page.html")
        asset.a11y.descriptions = [Cue(start: 5, end: 15, text: "d", kind: .description)]
        asset.warp = warp
        #expect(asset.pageDescriptions.first.map { abs($0.start - 4) < 1e-9 } == true)
        // A re-cut starts from the originals, through the warp they were made with.
        asset.originalA11y = A11y(descriptions: [Cue(start: 2, end: 15, text: "o", kind: .description)])
        asset.originalWarp = nil
        #expect(asset.pageDescriptions.first?.start == 2)
    }
}
