//
//  NarrationCaptions.swift
//  AdverbCore
//
//  WHAT: A voice-over's lines as captions and checks: Claude's answer to lines, the contract a
//        script is held to (in order, inside the asset, each short enough for its window), the
//        spoken spans in video time (each line's clip placed through the warp, its speech from the
//        TTS timings), the caption cues made from them, and which scenes no line speaks over.
//  PIN:  A line over ~84 characters is split into two cues at the word nearest its middle, using
//        the word timings, so a caption never runs past two lines on a phone.
//

import Foundation

public enum NarrationPacing {
    public static let wordsPerSecond = 2.6
    /// Seconds a window keeps free of speech.
    public static let headroom = 0.4
    /// Seconds before its window's end a spoken line must be done, or it is recorded faster.
    public static let fitSlack = 0.1
    /// The fastest a line is re-recorded at.
    public static let maxSpeed = 1.15

    /// Words a window of `seconds` holds at the pace.
    public static func wordBudget(_ seconds: Double) -> Int { max(0, Int(((seconds - headroom) * wordsPerSecond).rounded(.down))) }

    /// Languages written without spaces between words: word counts mean nothing there.
    public static func countsWords(_ language: Language) -> Bool { ![.japanese, .chinese].contains(language) }
}

public enum NarrationCaptions {
    public static let splitAt = 84

    public static func lines(from response: NarrationResponse) -> [NarrationLine] {
        response.lines.sorted { $0.at < $1.at }.enumerated().map { i, l in
            NarrationLine(index: i, text: l.text.trimmingCharacters(in: .whitespacesAndNewlines), at: l.at, until: l.until,
                          characters: l.text.count)
        }
    }

    /// A translation answer onto the English lines: the text is the translation's, the windows
    /// stay the English ones (Claude was asked to keep them).
    public static func translated(_ response: NarrationResponse, from english: [NarrationLine]) -> [NarrationLine]? {
        let answer = response.lines.sorted { $0.at < $1.at }
        guard answer.count == english.count else { return nil }
        return zip(english, answer).map { e, t in
            NarrationLine(index: e.index, text: t.text.trimmingCharacters(in: .whitespacesAndNewlines), at: e.at, until: e.until, characters: t.text.count)
        }
    }

    /// What breaks the script's contract, said so Claude can fix it.
    /// `pacing: false` keeps only the structural problems (order, range, emptiness).
    public static func problems(_ lines: [NarrationLine], duration: Double, language: Language = .english, pacing: Bool = true) -> [String] {
        var problems: [String] = []
        if lines.isEmpty { return ["There are no lines."] }
        for (i, l) in lines.enumerated() {
            let label = "Line \(i + 1) (\(String(format: "%.1f", l.at)) s)"
            if l.text.isEmpty { problems.append("\(label) is empty.") }
            if l.at < 0 || l.until > duration - 0.2 { problems.append(String(format: "%@ must sit inside 0–%.1f s.", label, duration - 0.3)) }
            if l.until <= l.at { problems.append("\(label) ends before it starts.") }
            if i > 0, l.at < lines[i - 1].until - 0.01 { problems.append("\(label) starts before line \(i) ends.") }
            if pacing, NarrationPacing.countsWords(language) {
                let words = l.text.split(whereSeparator: \.isWhitespace).count
                let budget = NarrationPacing.wordBudget(l.window)
                if words > budget + 1 {
                    problems.append(String(format: "%@ has %d words for a %.1f s window; at most %d fit.", label, words, l.window, max(budget, 1)))
                }
            }
        }
        return problems
    }

    /// Each line's speech in video time: its clip's start through the warp, plus where the
    /// speech starts and ends inside the clip. A line not yet recorded fills its window.
    public static func spoken(_ lines: [NarrationLine], warp: TimeWarp?) -> [Cue] {
        lines.map { line in
            let start = line.placedStart(warp: warp)
            guard let a = line.spokenStart, let b = line.spokenEnd else {
                let end = warp?.realTime(forPage: line.until) ?? line.until
                return Cue(start: start, end: end, text: line.text)
            }
            return Cue(start: start + a, end: start + max(a, b), text: line.text)
        }.sorted { $0.start < $1.start }
    }

    /// The captions a narrated asset ships: the spoken spans, long lines split at a word, held
    /// on screen at least half a second, never overlapping, inside the asset.
    public static func cues(lines: [NarrationLine], warp: TimeWarp?, duration: Double) -> [Cue] {
        var out: [Cue] = []
        for line in lines.sorted(by: { $0.at < $1.at }) {
            let base = line.placedStart(warp: warp)
            let span = spoken([line], warp: warp)[0]
            if line.text.count > splitAt, let split = split(line, base: base, span: span) { out += split } else { out.append(span) }
        }
        out.sort { $0.start < $1.start }
        for i in out.indices {
            out[i].start = min(max(0, out[i].start), duration)
            out[i].end = min(max(out[i].end, out[i].start + CueTracker.minDuration), duration)
            if i + 1 < out.count, out[i].end > out[i + 1].start { out[i].end = max(out[i].start + 0.1, out[i + 1].start) }
            out[i].start = (out[i].start * 1000).rounded() / 1000
            out[i].end = (out[i].end * 1000).rounded() / 1000
        }
        return out.filter { $0.end > $0.start }
    }

    static func split(_ line: NarrationLine, base: Double, span: Cue) -> [Cue]? {
        let words = line.text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 4 else { return nil }
        // The word boundary nearest the middle by characters.
        var count = 0, cut = 1
        let half = line.text.count / 2
        for (i, w) in words.enumerated() {
            count += w.count + 1
            if count >= half { cut = max(1, min(words.count - 1, i + 1)); break }
        }
        let first = words[..<cut].joined(separator: " "), second = words[cut...].joined(separator: " ")
        let at: Double
        if line.words.count == words.count {
            at = base + line.words[cut].start
        } else {
            at = span.start + (span.end - span.start) * Double(first.count) / Double(max(1, line.text.count))
        }
        return [Cue(start: span.start, end: at, text: first), Cue(start: at, end: span.end, text: second)]
    }

    /// Scene starts (video time) no spoken line overlaps within the scene's first 1.5 s.
    public static func uncovered(scenes: [Double], cues: [Cue], duration: Double) -> [Double] {
        let starts = scenes.filter { $0 < duration - 1.0 }
        return starts.enumerated().filter { i, s in
            let next = i + 1 < starts.count ? starts[i + 1] : duration
            let end = min(s + 1.5, next)
            return !cues.contains { $0.start < end && $0.end > s - 0.2 }
        }.map(\.element)
    }

    public static func coverage(scenes: [Double], cues: [Cue], duration: Double) -> Double {
        let starts = scenes.filter { $0 < duration - 1.0 }
        guard !starts.isEmpty else { return cues.isEmpty ? 0 : 1 }
        return 1 - Double(uncovered(scenes: scenes, cues: cues, duration: duration).count) / Double(starts.count)
    }

    /// Times where one spoken line starts before the one before it has finished.
    public static func overlaps(_ spoken: [Cue]) -> [Double] {
        let sorted = spoken.sorted { $0.start < $1.start }
        return zip(sorted, sorted.dropFirst()).filter { $1.start < $0.end - 0.05 }.map { $1.start }
    }
}
