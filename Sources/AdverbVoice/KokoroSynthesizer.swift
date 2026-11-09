//
//  KokoroSynthesizer.swift
//  AdverbVoice
//
//  WHAT: A voice pack spoken through the lifted Kokoro engine, as AdverbCore's SpeechSynthesizer:
//        one line in, its samples out with when the voice starts and stops and when each word of
//        the line is said.
//  PIN:  Word times come from the model's own per-token durations (KokoroEngine.wordSpans), mapped
//        onto the line's own words: a word the normalizer expanded ("2026" → "twenty twenty-six")
//        takes the spans it became. When the engine reports none, the words are spread over the
//        voiced span (WordTimings) and `exactTiming` is false.
//  PIN:  Seeded: the same words in the same voice at the same speed are the same samples, so a
//        clip made again is the clip it was. One line at a time per pack (the engine's gate).
//

import AdverbCore
import Foundation

public actor KokoroSynthesizer: AdverbCore.SpeechSynthesizer {
    public nonisolated let pack: SpeechPackInfo
    let directory: URL
    let engine: KokoroEngine
    private var voice: String?

    init(pack: SpeechPackInfo, directory: URL) async throws {
        self.pack = pack
        self.directory = directory
        engine = KokoroEngine()
        try await engine.loadModels(from: directory)
    }

    public func speak(_ request: SpeechRequest) async throws -> SpeechClip {
        guard pack.supports(request.language) else { throw SpeechError.unsupportedLanguage(request.language) }
        let name = pack.voice(request.voiceID)?.id ?? pack.voices.first?.id ?? request.voiceID
        if voice != name {
            try await engine.loadVoice(named: name, in: VoiceLibrary.voicesFolder(directory))
            await engine.warmUp()
            voice = name
        }
        await engine.setSpeed(Float(request.speed))
        await engine.setNoiseSeed(request.seed)
        let chunk = try await engine.synthesizeChunk(request.text, options: .standard)
        let seconds = Double(chunk.samples.count) / max(chunk.sampleRate, 1)
        let voiced = Self.voicedSpan(chunk.samples, sampleRate: chunk.sampleRate)
        // The model's durations are the clip's frames before the seam trimmed its tail: held inside it.
        let aligned = Self.align(request.text, to: chunk.wordSpans)?.map { w in
            WordTiming(text: w.text, start: min(max(0, w.start), seconds), end: min(max(0, w.end), seconds))
        }
        let words = aligned ?? WordTimings.spread(request.text, start: voiced.start, end: voiced.end)
        // Exact: the first word's onset (the edge fade's floor is not speech) and the last word's end.
        let start = aligned?.first.map { max(voiced.start, $0.start - 0.02) } ?? voiced.start
        let end = aligned?.last.map { min(voiced.end, max($0.end, voiced.end - 0.15)) } ?? voiced.end
        return SpeechClip(samples: chunk.samples, sampleRate: chunk.sampleRate, words: words,
                          spokenStart: start, spokenEnd: max(start, end), exactTiming: aligned != nil)
    }

    /// When the voice starts and stops: the first and last 10 ms above -45 dBFS.
    static func voicedSpan(_ samples: [Float], sampleRate: Double) -> (start: Double, end: Double) {
        let window = max(1, Int(sampleRate * 0.01))
        let threshold: Float = 0.005_6
        var first: Int?, last: Int?
        var i = 0
        while i < samples.count {
            let end = min(samples.count, i + window)
            var peak: Float = 0
            for j in i..<end { peak = max(peak, abs(samples[j])) }
            if peak > threshold { if first == nil { first = i }; last = end }
            i = end
        }
        guard let first, let last, sampleRate > 0 else { return (0, Double(samples.count) / max(sampleRate, 1)) }
        return (Double(first) / sampleRate, Double(last) / sampleRate)
    }

    /// The engine's spoken words mapped onto the line's own words, one timing per word of the line.
    /// A word matches its spoken word, or the run of spoken words that spell it ("margin's" as
    /// "margin" + "'s"); only a word with digits or symbols may become other words ("2026" →
    /// "twenty twenty-six", "⌃A"); a word with no letters at all may say nothing. Anything else
    /// means the two do not line up: nil, and the captions cut on an even split.
    static func align(_ text: String, to spans: [KokoroWordSpan]) -> [WordTiming]? {
        let words = WordTimings.words(text)
        guard !words.isEmpty, !spans.isEmpty else { return nil }
        func key(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        var out: [WordTiming] = []
        var j = 0
        for (i, word) in words.enumerated() {
            let k = key(word)
            if k.isEmpty {
                // Punctuation alone: a moment at the last word's end.
                let t = out.last?.end ?? spans[min(j, spans.count - 1)].start
                out.append(WordTiming(text: word, start: t, end: t)); continue
            }
            guard j < spans.count else { return nil }
            // The spoken words that spell it, one or more.
            var spelled = "", end = j
            while end < spans.count, spelled.count < k.count, k.hasPrefix(spelled + key(spans[end].text)) {
                spelled += key(spans[end].text); end += 1
            }
            if spelled == k, end > j {
                out.append(WordTiming(text: word, start: spans[j].start, end: spans[end - 1].end)); j = end; continue
            }
            // A number or a symbol said as other words: every span up to where the next word begins.
            guard word.contains(where: { $0.isNumber || (!$0.isLetter && !$0.isPunctuation && !$0.isWhitespace) }) else { return nil }
            let nextKey = words[(i + 1)...].map(key).first { !$0.isEmpty }
            end = j
            while end < spans.count, nextKey == nil || !nextKey!.hasPrefix(key(spans[end].text)) || end == j { end += 1 }
            out.append(WordTiming(text: word, start: spans[j].start, end: spans[end - 1].end))
            j = end
        }
        return j == spans.count ? out : nil
    }
}

extension KokoroEngine {
    func setSpeed(_ value: Float) { speed = max(0.5, min(2, value)) }
}
