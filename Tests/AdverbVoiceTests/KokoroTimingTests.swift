import Foundation
import Testing
@testable import AdverbCore
@testable import AdverbVoice

@Suite struct KokoroTimingTests {
    @Test func spokenWordsMapOntoTheLinesWords() throws {
        let spans = [KokoroWordSpan(text: "In", start: 0.1, end: 0.2), KokoroWordSpan(text: "twenty", start: 0.25, end: 0.6),
                     KokoroWordSpan(text: "twenty-six", start: 0.6, end: 1.2), KokoroWordSpan(text: "Ambient", start: 1.3, end: 1.8),
                     KokoroWordSpan(text: "reads", start: 1.85, end: 2.1)]
        let words = try #require(KokoroSynthesizer.align("In 2026, Ambient reads.", to: spans))
        #expect(words.map(\.text) == ["In", "2026,", "Ambient", "reads."])
        #expect(words[1].start == 0.25 && words[1].end == 1.2, "an expanded number takes the words it became")
        #expect(words[3].end == 2.1)
        #expect(KokoroSynthesizer.align("Something else entirely.", to: spans) == nil, "unmatched words are not trusted")
        let split = [KokoroWordSpan(text: "margin", start: 0, end: 0.4), KokoroWordSpan(text: "'s", start: 0.4, end: 0.5),
                     KokoroWordSpan(text: "edge", start: 0.6, end: 0.9)]
        #expect(KokoroSynthesizer.align("The margin's edge — again", to: split) == nil, "a word missing from the speech")
        let joined = try #require(KokoroSynthesizer.align("margin's — edge", to: split))
        #expect(joined.map(\.text) == ["margin's", "—", "edge"] && joined[0].end == 0.5 && joined[1].start == joined[1].end)
        #expect(KokoroSynthesizer.align("", to: spans) == nil)
    }

    @Test func theVoicedSpanSkipsSilence() {
        var samples = [Float](repeating: 0, count: 24_000)
        for i in 6_000..<18_000 { samples[i] = 0.3 * sin(Float(i) * 0.05) }
        let span = KokoroSynthesizer.voicedSpan(samples, sampleRate: 24_000)
        #expect(abs(span.start - 0.25) < 0.011 && abs(span.end - 0.75) < 0.011)
    }

    @Test func wordSpansComeFromTheModelsFrames() {
        // Two words: ids [5,6] and [7]; space 16 between them; BOS/EOS 0. Frames: 2 per id.
        let words: [(text: String, ids: [Int32])] = [("Hi", [5, 6]), ("there", [7])]
        let part = (ids: [Int32]([0, 5, 6, 16, 7, 0]), predDur: [Float](repeating: 2, count: 6), lead: 0)
        let spoken: [(samples: [Float], pauseAfter: KokoroPause)] = [([Float](repeating: 0, count: 6 * 2 * 600), .none)]
        let spans = KokoroEngine.wordSpans(words: words, parts: [part], spoken: spoken, sampleRate: 24_000)
        #expect(spans.map(\.text) == ["Hi", "there"])
        #expect(abs(spans[0].start - 0.05) < 1e-9 && abs(spans[0].end - 0.15) < 1e-9, "after BOS's two frames, two ids of two frames")
        #expect(abs(spans[1].start - 0.2) < 1e-9 && abs(spans[1].end - 0.25) < 1e-9)
        let missing = KokoroEngine.wordSpans(words: words + [("again", [9])], parts: [part], spoken: spoken, sampleRate: 24_000)
        #expect(missing.isEmpty, "a word the walk did not find leaves the timing to the estimate")
    }

    @Test func voicesAreNamedAsKokoroNamesThem() {
        let heart = VoiceLibrary.voice(named: "af_heart", packID: "p")
        #expect(heart.name == "Heart" && heart.accent == "American" && heart.gender == "female")
        let alice = VoiceLibrary.voice(named: "bf_alice", packID: "p")
        #expect(alice.accent == "British" && alice.summary == "Alice · British female")
        #expect(VoiceLibrary.voice(named: "plain", packID: "p").name == "Plain")
    }
}
