//
//  Waveform.swift
//  AdverbRender
//
//  WHAT: A song's loudness as columns, for the beatmap timeline and the library's thumbnails.
//        The beat grid's energy envelope already holds it (every 10 ms); this bins it.
//

import AdverbCore
import Foundation

public enum Waveform {
    /// `columns` peaks between `start` and `end` seconds of the grid's energy envelope, 0…1.
    public static func columns(_ grid: BeatGrid, columns: Int, start: Double = 0, end: Double? = nil) -> [Float] {
        let e = grid.energy
        guard !e.isEmpty, columns > 0 else { return [] }
        let hop = grid.energyHop
        let a = max(0, Int(start / hop)), b = min(e.count, Int((end ?? grid.duration) / hop))
        guard b > a else { return Array(repeating: 0, count: columns) }
        let span = Double(b - a) / Double(columns)
        return (0..<columns).map { c in
            let lo = a + Int(Double(c) * span), hi = max(lo + 1, min(b, a + Int(Double(c + 1) * span)))
            return e[lo..<hi].max() ?? 0
        }
    }
}
