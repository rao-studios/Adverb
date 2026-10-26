//
//  CueTracker.swift
//  AdverbCore
//
//  WHAT: Caption samples (what was on screen, every 0.1 s) folded into closed-caption cues: one
//        cue per text block for as long as it stays up, merged across tiny gaps, at least 0.5 s,
//        in reading order, at most two lines at a time.
//  PIN:  A headline rises word by word; a cue shows it whole from the moment most of it is up,
//        so the caption never stutters through partial lines. The end card's lines are one cue.
//        Times are the video's (the render's), so a warped render's captions are already right.
//

import Foundation

public enum CueTracker {
    public static let minDuration = 0.5
    public static let mergeGap = 0.15
    /// How long a newly shown block outranks older reading text.
    public static let freshFor = 2.5

    struct Span { var id: String; var kind: String; var text: String; var start: Double; var end: Double; var y: Int; var x: Int }

    /// Cues from samples taken every `step` seconds, for a video `duration` long: one per text
    /// block, for as long as it stays up.
    public static func cues(from samples: [CaptionSample], step: Double = 0.1, duration: Double) -> [Cue] {
        spans(from: samples, step: step, duration: duration).map { Cue(start: $0.start, end: $0.end, text: $0.text, kind: .text) }
    }

    /// Closed captions: at every moment the two most important blocks on screen (a headline and
    /// the end card first, then reading text, source chips, code, the kicker last), in reading
    /// order, with no cue shorter than half a second.
    public static func captions(from samples: [CaptionSample], step: Double = 0.1, duration: Double) -> [Cue] {
        let all = spans(from: samples, step: step, duration: duration)
        guard !all.isEmpty else { return [] }
        let edges = Set(all.flatMap { [$0.start, $0.end] }).sorted()
        var out: [Cue] = []
        for (a, b) in zip(edges, edges.dropFirst()) where b - a > 1e-6 {
            let showing = all.filter { $0.start <= a + 1e-6 && $0.end >= b - 1e-6 }
            guard !showing.isEmpty else { continue }
            // The kicker is a label: captioned only when nothing else is on screen.
            let candidates = showing.count > 1 ? showing.filter { $0.kind != "kicker" } : showing
            // A block that just appeared is what the viewer is looking at: for its first few seconds it
            // ranks just under the headline, so chips and code each get their turn.
            func rank(_ s: Span) -> Double {
                let base = Double(priority(s.kind))
                return (s.kind != "kicker" && a - s.start < freshFor) ? min(base, 0.5) : base
            }
            let top = candidates.sorted { (rank($0), -$0.start) < (rank($1), -$1.start) }.prefix(2)
            let text = top.sorted { ($0.y, $0.x) < ($1.y, $1.x) }.map(\.text).joined(separator: "\n")
            if var last = out.last, last.text == text, abs(last.end - a) < 1e-6 { last.end = b; out[out.count - 1] = last }
            else { out.append(Cue(start: round3(a), end: round3(b), text: text, kind: .text)) }
        }
        return absorbSlivers(out)
    }

    static func priority(_ kind: String) -> Int {
        switch kind {
        case "headline", "end": 0
        case "body": 1
        case "chip": 2
        case "code": 3
        default: 4
        }
    }

    /// A cue under `minDuration` gives its time to a neighbour: the next one if it touches, else
    /// the previous; a sliver alone stretches to the minimum.
    static func absorbSlivers(_ cues: [Cue]) -> [Cue] {
        var out = cues
        var i = 0
        while i < out.count {
            let c = out[i]
            if c.end - c.start >= minDuration - 1e-9 { i += 1; continue }
            if i + 1 < out.count, abs(out[i + 1].start - c.end) < 1e-6 {
                out[i + 1].start = c.start; out.remove(at: i)
            } else if i > 0, abs(out[i - 1].end - c.start) < 1e-6 {
                out[i - 1].end = c.end; out.remove(at: i)
            } else {
                out[i].end = c.start + minDuration; i += 1
            }
        }
        return out
    }

    static func spans(from samples: [CaptionSample], step: Double, duration: Double) -> [Span] {
        var open: [String: Span] = [:]
        var closed: [Span] = []
        for sample in samples.sorted(by: { $0.t < $1.t }) {
            let end = min(duration, sample.t + step)
            var present = Set<String>()
            for item in sample.items {
                let text = normalise(item.text)
                guard !text.isEmpty else { continue }
                let key = item.kind == "end" ? "end" : item.id
                present.insert(key)
                if var span = open[key] {
                    if item.kind == "end" {
                        if !span.text.contains(text) { span.text += " · " + text }
                    } else if text.count >= span.text.count {
                        // A headline still rising: keep the longest (fullest) reading.
                        span.text = text
                    }
                    span.end = end
                    open[key] = span
                } else {
                    open[key] = Span(id: key, kind: item.kind, text: text, start: sample.t, end: end, y: item.y, x: item.x)
                }
            }
            for key in open.keys where !present.contains(key) {
                closed.append(open.removeValue(forKey: key)!)
            }
        }
        closed += open.values
        // Merge a block that blinked off for under `mergeGap` back into one span.
        var merged: [Span] = []
        for span in closed.sorted(by: { ($0.id, $0.start) < ($1.id, $1.start) }) {
            if var last = merged.last, last.id == span.id, span.start - last.end < mergeGap {
                last.end = max(last.end, span.end)
                if span.text.count > last.text.count { last.text = span.text }
                merged[merged.count - 1] = last
            } else {
                merged.append(span)
            }
        }
        return merged
            .filter { $0.end - $0.start >= minDuration * 0.6 }
            .map { span in
                var s = span
                s.start = round3(s.start); s.end = round3(s.end)
                if s.end - s.start < minDuration { s.end = min(duration, s.start + minDuration) }
                return s
            }
            .sorted { a, b in a.start != b.start ? a.start < b.start : (a.y, a.x) < (b.y, b.x) }
    }

    /// Adds the music cue a captioned video with a song should carry.
    public static func withMusic(_ cues: [Cue], credit: String?, duration: Double) -> [Cue] {
        guard let credit else { return cues }
        return [Cue(start: 0, end: min(duration, 2.0), text: "[♪ \(credit)]", kind: .music)] + cues
    }

    static func normalise(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    static func round3(_ x: Double) -> Double { (x * 1000).rounded() / 1000 }
}
