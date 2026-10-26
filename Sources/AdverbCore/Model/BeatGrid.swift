//
//  BeatGrid.swift
//  AdverbCore
//
//  WHAT: What the beat tracker found in a song: tempo, beats, downbeats (the bar's first beat),
//        and an energy envelope every 10 ms.
//

import Foundation

public struct BeatGrid: Codable, Sendable, Equatable, Hashable {
    public var bpm: Double
    /// 0…1. Below 0.3 the grid is a nominal one the UI says so about.
    public var confidence: Double
    public var beats: [Double]
    public var downbeats: [Double]
    public var energy: [Float]
    public var energyHop: Double
    public var duration: Double
    public var meter: Int
    public var nominal: Bool

    public init(bpm: Double, confidence: Double, beats: [Double], downbeats: [Double], energy: [Float] = [],
                energyHop: Double = 0.010, duration: Double, meter: Int = 4, nominal: Bool = false) {
        self.bpm = bpm; self.confidence = confidence; self.beats = beats; self.downbeats = downbeats
        self.energy = energy; self.energyHop = energyHop; self.duration = duration; self.meter = meter; self.nominal = nominal
    }

    /// The grid seen from video time 0 at `inPoint` in the song, over `duration` seconds.
    public func window(inPoint: Double, duration: Double) -> BeatGrid {
        let shift: (Double) -> Double = { $0 - inPoint }
        let inside: (Double) -> Bool = { $0 >= -1e-6 && $0 <= duration + 1e-6 }
        let hop = energyHop
        let first = max(0, Int(inPoint / hop)), count = Int(duration / hop)
        let slice = first < energy.count ? Array(energy[first..<min(energy.count, first + count)]) : []
        return BeatGrid(bpm: bpm, confidence: confidence, beats: beats.map(shift).filter(inside),
                        downbeats: downbeats.map(shift).filter(inside), energy: slice, energyHop: hop,
                        duration: duration, meter: meter, nominal: nominal)
    }

    /// The first downbeat after the music first comes up: a sensible default in-point.
    public func suggestedInPoint(for duration: Double) -> Double {
        let hop = energyHop
        let second = max(1, Int(1 / hop))
        var rise: Double = 0
        if energy.count > second {
            var sum = energy[0..<second].reduce(0, +)
            for i in second..<energy.count {
                sum += energy[i] - energy[i - second]
                if sum / Float(second) >= 0.35 { rise = Double(i - second) * hop; break }
            }
        }
        let candidate = downbeats.first { $0 >= rise } ?? beats.first ?? 0
        return min(candidate, max(0, self.duration - duration))
    }
}

extension BeatGrid {
    /// The grid at another octave (2: double time, a beat between every two; 0.5: every other
    /// beat) with the downbeat moved by `phaseNudge` beats: the person's corrections.
    public func adjusted(octave: Double, phaseNudge: Int) -> BeatGrid {
        var beats = self.beats
        if octave >= 2, beats.count > 1 {
            beats = zip(beats, beats.dropFirst()).flatMap { [$0, ($0 + $1) / 2] } + [beats.last!]
        } else if octave <= 0.5 {
            beats = stride(from: 0, to: beats.count, by: 2).map { beats[$0] }
        }
        // The original downbeat phase, carried onto the new beat list, then nudged.
        let anchor = downbeats.first.flatMap { d in beats.firstIndex { abs($0 - d) < 0.02 } } ?? 0
        let perBar = max(1, meter)
        let phase = (((anchor + phaseNudge) % perBar) + perBar) % perBar
        let downs = stride(from: phase, to: beats.count, by: perBar).map { beats[$0] }
        var out = self
        out.beats = beats
        out.downbeats = downs
        out.bpm = bpm * (octave >= 2 ? 2 : octave <= 0.5 ? 0.5 : 1)
        return out
    }
}
