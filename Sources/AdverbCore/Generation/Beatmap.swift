//
//  Beatmap.swift
//  AdverbCore
//
//  WHAT: How a page meets a song without being rewritten: each scene start moves to the nearest
//        downbeat (or beat) within reach, the end card starts on the last downbeat in its window,
//        and the time between stretches to meet them. The result is a TimeWarp the renderer plays
//        the page through; DUR, 0 and the order of everything stay put.
//  PIN:  A boundary moves at most `maxStretch` of the segments on either side, so no scene
//        races or crawls; one that cannot reach a beat keeps its own time.
//

import Foundation

public enum Beatmap {
    /// - Parameters:
    ///   - scenes: the page's scene starts (window.SCENES), page time.
    ///   - grid: beats and downbeats in video time (BeatGrid.window(inPoint:duration:)).
    ///   - endAt: the page's end-card start; it lands on the last downbeat in [DUR−1.6, DUR−1.0].
    public static func warp(scenes: [Double], grid: BeatGrid, duration: Double, endAt: Double? = nil,
                            maxStretch: Double = 0.15) -> TimeWarp {
        var boundaries = scenes.filter { $0 > 0.05 && $0 < duration - 0.05 }
        if let endAt, !boundaries.contains(where: { abs($0 - endAt) < 0.05 }) { boundaries.append(endAt) }
        boundaries = Array(Set(boundaries.map { ($0 * 1000).rounded() / 1000 })).sorted()
        var knots: [TimeWarp.Knot] = [.init(page: 0, real: 0)]
        var previousReal = 0.0, previousPage = 0.0
        for (i, page) in boundaries.enumerated() {
            let nextPage = i + 1 < boundaries.count ? boundaries[i + 1] : duration
            let reach = maxStretch * min(page - previousPage, nextPage - page)
            let target: Double?
            if let endAt, abs(page - endAt) < 0.05 {
                target = grid.downbeats.last { $0 >= duration - 1.6 && $0 <= duration - 1.0 }
                    ?? grid.beats.last { $0 >= duration - 1.6 && $0 <= duration - 1.0 }
                    ?? nearest(page, in: grid.downbeats, within: reach)
            } else {
                target = nearest(page, in: grid.downbeats, within: reach) ?? nearest(page, in: grid.beats, within: reach)
            }
            var real = target ?? page
            // Monotonic, with room for the next segment.
            real = max(real, previousReal + 0.1)
            real = min(real, duration - 0.1)
            knots.append(.init(page: page, real: real))
            previousReal = real; previousPage = page
        }
        knots.append(.init(page: duration, real: duration))
        return TimeWarp(knots: knots)
    }

    static func nearest(_ t: Double, in times: [Double], within reach: Double) -> Double? {
        guard let best = times.min(by: { abs($0 - t) < abs($1 - t) }), abs(best - t) <= reach else { return nil }
        return best
    }

    /// `kit-beat.js`'s data file for a page: the grid in video time.
    public static func beatsScript(grid: BeatGrid, inPoint: Double, song: String) -> String {
        func list(_ xs: [Double]) -> String { "[" + xs.map { String(format: "%.3f", $0) }.joined(separator: ",") + "]" }
        let meta: JSONValue = ["inPoint": .number(inPoint), "dur": .number(grid.duration), "source": .string(song), "bpm": .number(grid.bpm)]
        return "/* Adverb: the song's beats in video time (generated). */\nwindow.BEATS=\(list(grid.beats));\nwindow.DOWNBEATS=\(list(grid.downbeats));\nwindow.BPM=\(String(format: "%.2f", grid.bpm));\nwindow.BEAT_META=\(meta.compact);\n"
    }

    /// The page with the beat helper and its data loaded after kit.js.
    public static func withBeatScripts(_ html: String, kitPrefix: String, beatsFile: String) -> String {
        let tags = "<script src=\"\(kitPrefix)kit-beat.js\"></script><script src=\"\(beatsFile)\"></script>"
        if html.contains("kit-beat.js") { return html }
        guard let r = html.range(of: #"<script[^>]*src=["'][^"']*kit\.js["'][^>]*>\s*</script>"#, options: .regularExpression) else { return html }
        return html.replacingCharacters(in: r, with: String(html[r]) + tags)
    }
}

public enum RetimeValidator {
    /// A re-timed page may change numbers inside its scripts and nothing else.
    public static func problems(original: String, retimed: String, duration: Int, grid: BeatGrid, cues: [RetimeResponse.CueMark]) -> [String] {
        var out: [String] = []
        if stripScripts(original) != stripScripts(retimed) { out.append("The markup or styles changed; only timing inside <script> may change.") }
        if PageVerifier.problems(retimed, duration: duration).contains(where: { $0.contains("DUR") }) { out.append("window.DUR changed.") }
        let tolerance = 1.0 / 30 + 1e-6
        for cue in cues {
            let pool = ["cut", "word", "end"].contains(cue.kind) ? grid.downbeats : grid.beats
            if !pool.contains(where: { abs($0 - cue.t) <= tolerance }) && !grid.beats.contains(where: { abs($0 - cue.t) <= tolerance }) {
                out.append(String(format: "A %@ at %.2f s is not on the grid.", cue.kind, cue.t))
            }
        }
        return out
    }

    static func stripScripts(_ html: String) -> String {
        html.replacingOccurrences(of: "(?s)<script[^>]*>.*?</script>", with: "<script/>", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
