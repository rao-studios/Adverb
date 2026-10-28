//
//  VoiceSync.swift
//  AdverbCore
//
//  WHAT: How a page meets its voice-over, with the beatmap's engine: each narration line is timed
//        to the moment the words or picture it speaks about appear, and the page plays through a
//        TimeWarp so that moment arrives as the voice starts the line. A line that needs longer
//        than its scene stretches the scene and moves what follows; with a song, each line (and
//        its text with it) lands on the nearest beat within reach. 0, the end card and DUR stay
//        put (the end card on the song's last downbeat in its window, as the beatmap puts it).
//  PIN:  Anchors are page time (`NarrationLine.at`), speech is clip time (`spokenStart…End`), so
//        the warp is worked out after the lines are recorded and before the frames are painted.
//

import Foundation

public enum VoiceSync {
    /// Seconds between one line's last word and the next line's first.
    public static let gap = 0.2
    /// How far a line moves to land on a beat.
    public static let beatReach = 0.12

    /// Each line's `at` moved onto the start of the on-screen text it belongs with: the nearest
    /// arrival within its reach, in order. A line with no text near it keeps its time.
    public static func anchor(_ lines: [NarrationLine], to screen: [Cue]) -> [NarrationLine] {
        let arrivals = Array(Set(screen.map { ($0.start * 1000).rounded() / 1000 })).sorted()
        var out = lines.sorted { $0.at < $1.at }
        var floor = -Double.infinity
        for i in out.indices {
            let line = out[i]
            let lo = max(line.at - 0.6, floor + gap), hi = min(line.until - 0.4, line.at + 1.5)
            if let best = arrivals.filter({ $0 >= lo && $0 <= hi }).min(by: { abs($0 - line.at) < abs($1 - line.at) }) {
                out[i].at = best
            }
            floor = out[i].at
        }
        return out
    }

    /// The warp that puts every line's text on its first word, with room to say it; nil when
    /// nothing has to move (the page plays at its own time).
    public static func warp(lines: [NarrationLine], duration: Double, endAt: Double, grid: BeatGrid? = nil) -> TimeWarp? {
        let endReal = grid.flatMap { g in
            g.downbeats.last { $0 >= duration - 1.6 && $0 <= duration - 1.0 } ?? g.beats.last { $0 >= duration - 1.6 && $0 <= duration - 1.0 }
        } ?? endAt
        let anchored = lines.filter { $0.at > 0.05 && $0.at < duration - 0.05 }.sorted { $0.at < $1.at }
        let body = anchored.filter { $0.at < endAt - 0.05 }, card = anchored.filter { $0.at >= endAt - 0.05 }
        var knots: [TimeWarp.Knot] = [.init(page: 0, real: 0)]
        knots += place(body, from: 0, to: endReal, grid: grid)
        knots.append(.init(page: endAt, real: endReal))
        knots += place(card, from: endReal, to: duration, grid: grid)
        knots.append(.init(page: duration, real: duration))
        let warp = TimeWarp(knots: knots)
        return warp.isIdentity ? nil : warp
    }

    /// The lines of one stretch (before the end card, or on it), each at its own time or its
    /// beat, then pushed later where the one before needs longer, then pulled back so the last
    /// is said before the stretch ends.
    static func place(_ lines: [NarrationLine], from start: Double, to end: Double, grid: BeatGrid?) -> [TimeWarp.Knot] {
        guard !lines.isEmpty else { return [] }
        let speech = lines.map { max(0, ($0.spokenEnd ?? $0.window) - ($0.spokenStart ?? 0)) }
        var real = [Double](repeating: 0, count: lines.count)
        var floor = start + 0.05
        for i in lines.indices {
            var target = lines[i].at
            if let grid, let beat = Beatmap.nearest(target, in: grid.downbeats, within: beatReach) ?? Beatmap.nearest(target, in: grid.beats, within: beatReach) {
                target = beat
            }
            real[i] = max(target, floor)
            floor = real[i] + speech[i] + gap
        }
        var ceiling = end - 0.1
        for i in lines.indices.reversed() {
            real[i] = min(real[i], ceiling - speech[i])
            ceiling = real[i] - gap
        }
        // Whatever could not fit still keeps its order.
        var previous = start
        for i in lines.indices {
            real[i] = min(max(real[i], previous + 0.1), end - 0.1 * Double(lines.count - i))
            previous = real[i]
        }
        return zip(lines, real).map { TimeWarp.Knot(page: $0.at, real: ($1 * 1000).rounded() / 1000) }
    }
}

extension TimeWarp {
    /// Whether two warps (nil: the page's own time) show the same frame at every instant, to a frame.
    public static func same(_ a: TimeWarp?, _ b: TimeWarp?, duration: Double, tolerance: Double = 1.0 / 30) -> Bool {
        stride(from: 0, through: duration, by: 0.05).allSatisfy { t in
            abs((a?.pageTime(forReal: t) ?? t) - (b?.pageTime(forReal: t) ?? t)) <= tolerance
        }
    }
}
