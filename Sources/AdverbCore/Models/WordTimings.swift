//
//  WordTimings.swift
//  AdverbCore
//
//  WHAT: A line's words spread over its voiced span, in proportion to how long each takes to say
//        (its letters, or a weight the voice gives it), with the pause a comma or a full stop
//        leaves. What a voice that reports no durations of its own gives the captions.
//  PIN:  One timing per whitespace-separated word of the line, in order: NarrationCaptions cuts
//        on them only when the counts agree.
//

import Foundation

public enum WordTimings {
    public static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// `text`'s words over `start…end`. `weights`, one per word, overrides the letter count.
    public static func spread(_ text: String, start: Double, end: Double, weights: [Double]? = nil) -> [WordTiming] {
        let words = words(text)
        guard !words.isEmpty, end > start else { return [] }
        let base = weights.flatMap { $0.count == words.count ? $0 : nil } ?? words.map(letterWeight)
        let pauses = words.map(pauseWeight)
        let total = zip(base, pauses).reduce(0) { $0 + $1.0 + $1.1 }
        guard total > 0 else { return [] }
        let scale = (end - start) / total
        var t = start
        var out: [WordTiming] = []
        for (i, word) in words.enumerated() {
            let w0 = t
            let w1 = t + base[i] * scale
            out.append(WordTiming(text: word, start: w0, end: w1))
            t = w1 + pauses[i] * scale
        }
        if var last = out.popLast() { last.end = end; out.append(last) }
        return out
    }

    /// Letters and digits, at least one: a digit is said as a word, so it counts as three.
    static func letterWeight(_ word: String) -> Double {
        let letters = word.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        let digits = word.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        return Double(max(1, letters + digits * 3))
    }

    /// The silence after a word: a comma's breath, a stop's longer one.
    static func pauseWeight(_ word: String) -> Double {
        guard let last = word.last else { return 0 }
        if ".!?".contains(last) { return 3 }
        if ",;:—–".contains(last) { return 1.5 }
        return 0.4
    }
}
