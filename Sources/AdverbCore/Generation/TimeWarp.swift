//
//  TimeWarp.swift
//  AdverbCore
//
//  WHAT: A monotonic map from video time to page time, piecewise linear between knots. A
//        beatmapped render plays the page through it, so a scene the page starts at 4.2 s starts
//        on the downbeat at 4.03 s in the video, and everything between stretches to meet it.
//

import Foundation

public struct TimeWarp: Codable, Sendable, Equatable, Hashable {
    public struct Knot: Codable, Sendable, Equatable, Hashable {
        /// Time in the page (its own seek(t)).
        public var page: Double
        /// Time in the video.
        public var real: Double
        public init(page: Double, real: Double) { self.page = page; self.real = real }
    }

    public var knots: [Knot]

    public init(knots: [Knot]) { self.knots = knots.sorted { $0.real < $1.real } }

    public static func identity(duration: Double) -> TimeWarp {
        TimeWarp(knots: [Knot(page: 0, real: 0), Knot(page: duration, real: duration)])
    }

    /// The page time to seek to at video time `t`.
    public func pageTime(forReal t: Double) -> Double {
        guard let first = knots.first, let last = knots.last else { return t }
        if t <= first.real { return first.page + (t - first.real) }
        if t >= last.real { return last.page + (t - last.real) }
        var lo = 0, hi = knots.count - 1
        while hi - lo > 1 { let mid = (lo + hi) / 2; if knots[mid].real <= t { lo = mid } else { hi = mid } }
        let a = knots[lo], b = knots[hi]
        let span = b.real - a.real
        return span <= 0 ? a.page : a.page + (t - a.real) / span * (b.page - a.page)
    }

    /// The video time at which the page reaches `p` (the inverse, for moving cues and descriptions).
    public func realTime(forPage p: Double) -> Double {
        let flipped = TimeWarp(knots: knots.map { Knot(page: $0.real, real: $0.page) })
        return flipped.pageTime(forReal: p)
    }

    public var isIdentity: Bool { knots.allSatisfy { abs($0.page - $0.real) < 1e-9 } }
}
